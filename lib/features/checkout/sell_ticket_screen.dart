import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:myapp/core/services/offline_sale_service.dart';
import 'package:myapp/core/services/app_settings_service.dart';
import 'package:myapp/data/local/database_helper.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/models/ticket_model.dart';
import 'package:myapp/data/models/ticket_type.dart';
import 'package:myapp/data/services/sync_service.dart';
import 'package:myapp/data/services/ticket_api.dart';
import 'package:myapp/features/checkout/sale_confirmation_screen.dart';
import 'package:myapp/features/checkout/widgets/print_flow_drawer.dart';
import 'package:myapp/features/ticket_printing/print_service.dart';
import 'package:myapp/features/ticket_validation/widgets/sync_status_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Unified Sell Ticket Screen
///
/// Intelligently handles both offline and online sales with adaptive UI:
/// - Normal Mode: Full details, navigation to confirmation
/// - Fast Mode: Compact UI, inline messages, print queue
///
/// Features:
/// - Offline-first based on settings
/// - Auto-print based on settings
/// - Print queue management in fast mode
/// - Sales counter in fast mode
/// - Event auto-bootstrap
class SellTicketScreen extends StatefulWidget {
  final Event event;
  final TicketType ticketType;

  const SellTicketScreen({
    super.key,
    required this.event,
    required this.ticketType,
  });

  @override
  State<SellTicketScreen> createState() => _SellTicketScreenState();
}

class _SellTicketScreenState extends State<SellTicketScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _ticketNumberController = TextEditingController(
    text: '1',
  );
  final TextEditingController _customerNameController = TextEditingController();
  final FocusNode _customerNameFocus = FocusNode();

  final TicketApi _ticketApi = TicketApi();
  final OfflineSaleService _offlineSaleService = OfflineSaleService();
  final AppSettingsService _appSettingsService = AppSettingsService();
  final PrintService _printService = PrintService();
  final DatabaseHelper _db = DatabaseHelper();

  bool _isSubmitting = false;
  String? _error;

  // Settings (loaded on init)
  bool _isFastMode = false;
  bool _autoPrintEnabled = true;

  // Fast mode features
  int _ticketsSoldCount = 0;
  final List<PrintFlowJob> _printQueue = [];
  int _printingCount = 0;
  int _printedCount = 0;
  int _printFailedCount = 0;
  int _syncReadyCount = 0;
  int _syncBlockedCount = 0;
  bool _isManualSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadPersistedPrintJobs();

    // Listen to quantity changes to update total dynamically
    _ticketNumberController.addListener(() {
      if (mounted && _isFastMode) {
        setState(() {
          // Trigger rebuild to update total display
        });
      }
    });
  }

  @override
  void dispose() {
    _ticketNumberController.dispose();
    _customerNameController.dispose();
    _customerNameFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final fastMode = await _appSettingsService.getFastCheckoutMode();
    final autoPrintEnabled = await _appSettingsService.getAutoPrintEnabled();

    if (mounted) {
      setState(() {
        _isFastMode = fastMode;
        _autoPrintEnabled = autoPrintEnabled;
      });
    }
  }

  Future<void> _loadPersistedPrintJobs() async {
    try {
      final rows = await _db.getPrintJobs();
      if (!mounted) return;

      final loaded = rows.map(PrintFlowJob.fromMap).toList();
      for (final job in loaded) {
        if (job.status == PrintFlowStatus.sending) {
          job.status = PrintFlowStatus.queued;
        }
        job.selected = false;
      }

      setState(() {
        _printQueue
          ..clear()
          ..addAll(loaded);
      });
      _persistAllJobs();
      _recalculatePrintCounters();
      _refreshSyncEligibilityCounts();

      if (_queuedPrintCount > 0) {
        _processPrintQueue();
      }
    } catch (e) {
      debugPrint('Failed to load print jobs: $e');
    }
  }

  Future<void> _persistJob(PrintFlowJob job) async {
    await _db.upsertPrintJob(job.toMap());
  }

  Future<void> _persistAllJobs() async {
    await _db.upsertPrintJobs(_printQueue.map((j) => j.toMap()).toList());
  }

  void _recalculatePrintCounters() {
    if (!mounted) return;
    final sent = _printQueue
        .where((j) => j.status == PrintFlowStatus.sent)
        .length;
    final failed = _printQueue
        .where(
          (j) =>
              j.status == PrintFlowStatus.failed ||
              j.status == PrintFlowStatus.pdfFallback,
        )
        .length;

    setState(() {
      _printedCount = sent;
      _printFailedCount = failed;
    });
  }

  Future<void> _refreshSyncEligibilityCounts() async {
    try {
      final ready = await _db.getUnsyncedReadyForSyncCount();
      final blocked = await _db.getUnsyncedBlockedByPrintCount();
      if (!mounted) return;
      setState(() {
        _syncReadyCount = ready;
        _syncBlockedCount = blocked;
      });
    } catch (e) {
      debugPrint('Failed to refresh sync eligibility counts: $e');
    }
  }

  Future<void> _syncReadyTicketsNow() async {
    if (_isManualSyncing) return;

    setState(() {
      _isManualSyncing = true;
    });

    try {
      final syncService = SyncService(db: _db);
      final result = await syncService.syncNow();
      await _refreshSyncEligibilityCounts();
      if (!mounted) return;

      _showQuickMessage(
        result.success
            ? 'Sync done: ${result.ticketsSynced} ticket(s)'
            : (result.message ?? 'Sync failed'),
        isSuccess: result.success,
        isError: !result.success,
      );
    } catch (e) {
      if (!mounted) return;
      _showQuickMessage('Sync error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isManualSyncing = false;
        });
      }
    }
  }

  Future<void> _processSale() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final quantity = int.parse(_ticketNumberController.text);
    final customerName = _customerNameController.text.trim();
    final amount = widget.ticketType.price * quantity;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // Check system-wide offline preference
      final preferOffline = await _appSettingsService.getPreferOfflineSales();
      print(
        'Sale preference: ${preferOffline ? "Offline-First" : "Online-First"}',
      );

      bool offlineSuccess = false;
      List<Ticket>? bookedTickets;
      List<String> offlineTicketIds = [];
      List<int> offlineSequentialIds = [];

      if (preferOffline) {
        // OFFLINE-FIRST: Try offline sale first
        if (quantity == 1) {
          // Single ticket - use offline service with PER-TICKET price
          final result = await _offlineSaleService.createTicket(
            matcheId: widget.event.id,
            ticketTypesId: widget.ticketType.id,
            amount: widget.ticketType.price, // Per-ticket price, not total
            customerName: customerName.isEmpty ? null : customerName,
          );

          if (result.isSuccess) {
            offlineSuccess = true;
            offlineTicketIds.add(result.ticketId!);
            if (result.sequentialId != null) {
              offlineSequentialIds.add(result.sequentialId!);
            }
          } else {
            print('Offline single sale failed: ${result.errorMessage}');
          }
        } else {
          // Batch sale - use offline service with PER-TICKET price
          final batchResult = await _offlineSaleService.createTickets(
            matcheId: widget.event.id,
            ticketTypesId: widget.ticketType.id,
            amount: widget.ticketType.price, // Per-ticket price
            quantity: quantity,
            customerName: customerName.isEmpty ? null : customerName,
          );

          if (batchResult.allSuccess) {
            offlineSuccess = true;
            offlineTicketIds = batchResult.successfulTickets
                .map((t) => t.ticketId!)
                .toList();
            offlineSequentialIds = batchResult.successfulTickets
                .where((t) => t.sequentialId != null)
                .map((t) => t.sequentialId!)
                .toList();
          } else {
            print(
              'Offline batch sale failed: ${batchResult.failCount} failures',
            );
          }
        }
      }

      if (offlineSuccess) {
        if (!mounted) return;

        setState(() {
          _isSubmitting = false;
        });

        // Increment counter in fast mode
        if (_isFastMode) {
          setState(() {
            _ticketsSoldCount += quantity;
          });
        }

        // Queue print jobs if auto-print enabled
        if (_autoPrintEnabled) {
          // Queue ALL tickets as ONE batch job for proper 1/N, 2/N numbering
          _queueBatchPrintJob(
            ticketIds: offlineTicketIds,
            customerName: customerName,
            sequentialIds: offlineSequentialIds,
            totalTickets: offlineTicketIds.length,
          );
        }

        // Show success message
        if (_isFastMode) {
          // Fast mode: Quick inline message
          _clearFormForNextSale();
          _showQuickMessage(
            quantity == 1
                ? 'Ticket #$_ticketsSoldCount created'
                : '$quantity tickets created (#${_ticketsSoldCount - quantity + 1}-$_ticketsSoldCount)',
            isSuccess: true,
          );
        } else {
          // Normal mode: Full snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                quantity == 1
                    ? 'Ticket created offline - will sync when online'
                    : '$quantity tickets created offline - will sync when online',
              ),
              backgroundColor: Colors.green,
            ),
          );

          // Clear form for next sale
          _ticketNumberController.text = '1';
          _customerNameController.clear();
        }

        return;
      }

      // FALLBACK or ONLINE-FIRST: Try API
      print('Proceeding with API-based sale...');
      bookedTickets = await _ticketApi.bookTicket(
        matchId: widget.event.id,
        ticketTypeId: widget.ticketType.id,
        quantity: quantity,
        amount: amount,
        customerName: customerName.isEmpty ? null : customerName,
      );

      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      if (_isFastMode) {
        // Fast mode: Increment counter and show quick message
        setState(() {
          _ticketsSoldCount += quantity;
        });

        // Queue print jobs
        if (_autoPrintEnabled) {
          final purchaseBatchId = '${DateTime.now().microsecondsSinceEpoch}';
          for (int i = 0; i < bookedTickets.length; i++) {
            _queuePrintJob(
              ticketId: bookedTickets[i].id.toString(),
              customerName: customerName,
              ticketNumber: i + 1,
              totalTickets: bookedTickets.length,
              purchaseBatchId: purchaseBatchId,
              purchaseIndex: i + 1,
              purchaseQuantity: bookedTickets.length,
            );
          }
        }

        _clearFormForNextSale();
        _showQuickMessage(
          quantity == 1
              ? 'Ticket #$_ticketsSoldCount sold'
              : '$quantity tickets sold (#${_ticketsSoldCount - quantity + 1}-$_ticketsSoldCount)',
          isSuccess: true,
        );
      } else {
        // Normal mode: Navigate to confirmation screen
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SaleConfirmationScreen(
              event: widget.event,
              ticketType: widget.ticketType,
              tickets: bookedTickets!,
              numberOfTickets: quantity,
              customerName: customerName,
            ),
          ),
        );

        if (!mounted) return;

        _ticketNumberController.text = '1';
        _customerNameController.clear();
      }
    } catch (e) {
      print('Sale error: $e');
      setState(() {
        _error = 'Failed to process sale: $e';
        _isSubmitting = false;
      });

      if (_isFastMode) {
        _showQuickMessage('Error: $e', isError: true);
      }
    }
  }

  /// Queue a batch print job (all tickets in one PDF with 1/N, 2/N numbering)
  Future<void> _queueBatchPrintJob({
    required List<String> ticketIds,
    required String customerName,
    required List<int> sequentialIds,
    required int totalTickets,
  }) async {
    if (ticketIds.isEmpty) return;
    final purchaseBatchId = '${DateTime.now().microsecondsSinceEpoch}';

    for (int i = 0; i < ticketIds.length; i++) {
      _queuePrintJob(
        ticketId: ticketIds[i],
        customerName: customerName,
        ticketNumber: i + 1,
        purchaseBatchId: purchaseBatchId,
        purchaseIndex: i + 1,
        purchaseQuantity: totalTickets,
        sequentialId: sequentialIds.isNotEmpty && i < sequentialIds.length
            ? sequentialIds[i]
            : null,
        totalTickets: totalTickets,
      );
    }
  }

  /// Queue a print job and process it (for single tickets)
  void _queuePrintJob({
    required String ticketId,
    required String customerName,
    required int ticketNumber,
    String? purchaseBatchId,
    int? purchaseIndex,
    int? purchaseQuantity,
    int? sequentialId,
    int? totalTickets,
  }) {
    final effectiveTotal = totalTickets ?? ticketNumber;
    final now = DateTime.now();
    final job = PrintFlowJob(
      id: '${ticketId}_${DateTime.now().microsecondsSinceEpoch}',
      ticketId: ticketId,
      customerName: customerName,
      ticketNumber: ticketNumber,
      purchaseBatchId: purchaseBatchId,
      purchaseIndex: purchaseIndex ?? ticketNumber,
      purchaseQuantity: purchaseQuantity ?? effectiveTotal,
      displayTicketId: sequentialId,
      totalTickets: effectiveTotal,
      createdAt: now,
      updatedAt: now,
    );

    setState(() {
      _printQueue.add(job);
    });
    _persistJob(job);
    _recalculatePrintCounters();
    _refreshSyncEligibilityCounts();

    // Process the queue
    _processPrintQueue();
  }

  /// Process print queue sequentially
  Future<void> _processPrintQueue() async {
    // If already printing, don't start another process
    if (_printingCount > 0) return;

    while (true) {
      final nextIndex = _printQueue.indexWhere(
        (job) => job.status == PrintFlowStatus.queued,
      );
      if (nextIndex == -1) break;

      final job = _printQueue[nextIndex];

      if (!mounted) break;

      setState(() {
        _printingCount++;
        job.status = PrintFlowStatus.sending;
        job.attemptCount++;
        job.updatedAt = DateTime.now();
      });
      await _persistJob(job);

      try {
        final result = await _printService.printTicketWithResult(
          eventName: '${widget.event.homeTeam} vs ${widget.event.awayTeam}',
          ticketType: widget.ticketType.name,
          price: widget.ticketType.price,
          ticketNumber: job.effectiveTicketNumber,
          totalTickets: job.effectiveTotalTickets,
          ticketCode: job.ticketId,
          validationUrl: job.ticketId,
          transactionId: job.ticketId,
          customerName: job.customerName.isEmpty ? null : job.customerName,
          ticketId: job.displayTicketId,
        );

        if (mounted) {
          setState(() {
            if (result.isSent) {
              job.status = PrintFlowStatus.sent;
              job.lastError = null;
              job.pdfPath = null;
            } else if (result.isPdfFallback) {
              job.status = PrintFlowStatus.pdfFallback;
              job.lastError = 'Printer unavailable, PDF saved';
              job.pdfPath = result.pdfPath;
            } else {
              job.status = PrintFlowStatus.failed;
              job.lastError = result.error ?? 'Failed to send to printer';
            }
            _printingCount--;
            job.updatedAt = DateTime.now();
          });
        }
        await _persistJob(job);
        _recalculatePrintCounters();
        _refreshSyncEligibilityCounts();

        // Small delay between prints
        if (result.isSent) {
          await Future.delayed(const Duration(milliseconds: 1000));
        } else {
          _showQuickMessage(
            result.isPdfFallback
                ? 'Printer unavailable. Ticket saved as PDF.'
                : 'Print failed - check printer',
            isError: true,
          );
          break;
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            job.status = PrintFlowStatus.failed;
            _printingCount--;
            job.lastError = e.toString();
            job.updatedAt = DateTime.now();
          });
        }
        await _persistJob(job);
        _recalculatePrintCounters();
        _refreshSyncEligibilityCounts();
        debugPrint('Print failed: $e');
        debugPrint('Failed ticket ID: ${job.ticketId}');
        // Stop processing on error
        break;
      }
    }
  }

  /// Retry all failed print jobs
  void _retryFailedPrints() {
    // Reset failed jobs to queued status
    setState(() {
      for (final job in _printQueue) {
        if (job.status == PrintFlowStatus.failed ||
            job.status == PrintFlowStatus.pdfFallback) {
          job.status = PrintFlowStatus.queued;
          job.lastError = null;
          job.pdfPath = null;
          job.selected = false;
          job.updatedAt = DateTime.now();
        }
      }
    });
    _persistAllJobs();
    _recalculatePrintCounters();
    _refreshSyncEligibilityCounts();
    // Restart queue processing
    _processPrintQueue();
  }

  /// Clear all failed print jobs from queue
  void _clearFailedPrints() {
    final idsToDelete = _printQueue
        .where(
          (job) =>
              job.status == PrintFlowStatus.failed ||
              job.status == PrintFlowStatus.pdfFallback,
        )
        .map((j) => j.id)
        .toList();
    setState(() {
      _printQueue.removeWhere(
        (job) =>
            job.status == PrintFlowStatus.failed ||
            job.status == PrintFlowStatus.pdfFallback,
      );
    });
    for (final id in idsToDelete) {
      _db.deletePrintJob(id);
    }
    _recalculatePrintCounters();
    _refreshSyncEligibilityCounts();
  }

  void _resendSelectedPrints() {
    setState(() {
      for (final job in _printQueue) {
        if (job.selected) {
          job.status = PrintFlowStatus.queued;
          job.lastError = null;
          job.pdfPath = null;
          job.selected = false;
          job.updatedAt = DateTime.now();
        }
      }
    });
    _persistAllJobs();
    _recalculatePrintCounters();
    _refreshSyncEligibilityCounts();
    _processPrintQueue();
  }

  void _clearSentPrints() {
    final idsToDelete = _printQueue
        .where((job) => job.status == PrintFlowStatus.sent)
        .map((j) => j.id)
        .toList();
    setState(() {
      _printQueue.removeWhere((job) => job.status == PrintFlowStatus.sent);
    });
    for (final id in idsToDelete) {
      _db.deletePrintJob(id);
    }
    _recalculatePrintCounters();
    _refreshSyncEligibilityCounts();
  }

  void _togglePrintSelection(String jobId) {
    setState(() {
      final idx = _printQueue.indexWhere((job) => job.id == jobId);
      if (idx != -1) {
        _printQueue[idx].selected = !_printQueue[idx].selected;
        _printQueue[idx].updatedAt = DateTime.now();
      }
    });
    _persistAllJobs();
  }

  int get _queuedPrintCount => _printQueue
      .where(
        (job) =>
            job.status == PrintFlowStatus.queued ||
            job.status == PrintFlowStatus.sending,
      )
      .length;

  /// Clear form and focus for next sale (fast mode)
  void _clearFormForNextSale() {
    _customerNameController.clear();
    _ticketNumberController.text = '1';
    // Auto-focus customer name for next entry
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _customerNameFocus.requestFocus();
      }
    });
  }

  /// Show quick toast message (fast mode)
  void _showQuickMessage(
    String message, {
    bool isSuccess = false,
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess
                  ? Icons.check_circle
                  : isError
                  ? Icons.error
                  : Icons.info,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isSuccess
            ? Colors.green
            : isError
            ? Colors.red
            : Colors.blue,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Export unsynced tickets as JSON file
  Future<void> _exportUnsyncedTickets() async {
    try {
      // Get unsynced tickets from database
      final unsyncedTickets = await _db.getUnsyncedTickets();

      if (unsyncedTickets.isEmpty) {
        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.info, color: Colors.blue, size: 48),
            title: const Text('No Data'),
            content: const Text('There are no unsynced tickets to export.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      // Create export data with metadata
      final exportData = {
        'exported_at': DateTime.now().toIso8601String(),
        'device_info': 'Flutter App Export',
        'ticket_count': unsyncedTickets.length,
        'tickets': unsyncedTickets.map((ticket) {
          return {
            'tuid': ticket['ticket_id'],
            'matche_id': ticket['matche_id'],
            'ticket_types_id': ticket['ticket_types_id'],
            'payload': ticket['payload'],
            'signature': ticket['signature'],
            'customer_name': ticket['customer_name'],
            'amount': ticket['amount'],
            'status': ticket['status'],
            'created_at': ticket['created_at'],
          };
        }).toList(),
      };

      // Convert to JSON
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

      // Get downloads directory
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'unsynced_tickets_$timestamp.json';
      final file = File('${directory.path}/$fileName');

      // Write file
      await file.writeAsString(jsonString);

      if (!mounted) return;

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Unsynced Tickets Export',
        text: 'Exported ${unsyncedTickets.length} unsynced tickets',
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.error, color: Colors.red, size: 48),
          title: const Text('Export Failed'),
          content: Text('Failed to export tickets: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: _isFastMode
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Fast Checkout'),
                  if (_ticketsSoldCount > 0)
                    Text(
                      '$_ticketsSoldCount sold • $_queuedPrintCount queued • $_printedCount sent',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  if (_syncReadyCount > 0 || _syncBlockedCount > 0)
                    Text(
                      'Sync: $_syncReadyCount ready • $_syncBlockedCount blocked',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                ],
              )
            : const Text('Sell Ticket'),
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                _isManualSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                if (_syncReadyCount > 0 && !_isManualSyncing)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_syncReadyCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Sync ready tickets now',
            onPressed: _syncReadyCount > 0 && !_isManualSyncing
                ? _syncReadyTicketsNow
                : null,
          ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.print),
                if (_printFailedCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_printFailedCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Open print flow',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export unsynced tickets as JSON',
            onPressed: _exportUnsyncedTickets,
          ),
          const SyncIndicator(),
        ],
      ),
      endDrawer: PrintFlowDrawer(
        jobs: _printQueue,
        isProcessing: _printingCount > 0,
        isSyncingReady: _isManualSyncing,
        syncReadyCount: _syncReadyCount,
        syncBlockedCount: _syncBlockedCount,
        onSyncReadyNow: _syncReadyTicketsNow,
        onRetryFailed: _retryFailedPrints,
        onResendSelected: _resendSelectedPrints,
        onClearCompleted: _clearSentPrints,
        onToggleSelected: _togglePrintSelection,
      ),
      body: _isFastMode ? _buildFastModeUI() : _buildNormalModeUI(),
    );
  }

  Widget _buildNormalModeUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Order Summary',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16.0),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.event.homeTeam} vs ${widget.event.awayTeam}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8.0),
                    Text(widget.event.matchDate),
                    const SizedBox(height: 8.0),
                    Text(widget.event.venue),
                    const SizedBox(height: 8.0),
                    Text('Ticket type: ${widget.ticketType.name}'),
                    const SizedBox(height: 4.0),
                    Text(
                      'Price: ₦${widget.ticketType.price.toStringAsFixed(2)}',
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12.0),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16.0),
            TextFormField(
              controller: _ticketNumberController,
              decoration: const InputDecoration(
                labelText: 'Number of Tickets',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter the number of tickets';
                }
                if (int.tryParse(value) == null || int.parse(value) <= 0) {
                  return 'Please enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16.0),
            TextFormField(
              controller: _customerNameController,
              decoration: const InputDecoration(
                labelText: 'Customer Name (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24.0),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _processSale,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _isSubmitting
                  ? const CircularProgressIndicator.adaptive()
                  : const Text('Confirm Sale'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFastModeUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Print Queue Status (only show if active)
            if (_queuedPrintCount > 0 || _printFailedCount > 0) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _printFailedCount > 0
                      ? Colors.orange.shade50
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _printFailedCount > 0
                        ? Colors.orange.shade200
                        : Colors.blue.shade200,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        if (_printingCount > 0)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            _printFailedCount > 0 ? Icons.warning : Icons.print,
                            size: 16,
                            color: _printFailedCount > 0
                                ? Colors.orange.shade700
                                : Colors.blue.shade700,
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _printingCount > 0
                                ? 'Printing... $_queuedPrintCount in queue'
                                : _printFailedCount > 0
                                ? '$_printFailedCount print(s) failed - $_queuedPrintCount in queue'
                                : 'All prints completed',
                            style: TextStyle(
                              fontSize: 12,
                              color: _printFailedCount > 0
                                  ? Colors.orange.shade700
                                  : Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Sync eligibility: $_syncReadyCount ready • $_syncBlockedCount blocked',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                    ),
                    if (_printFailedCount > 0 && _printingCount == 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _retryFailedPrints,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text(
                                'Retry',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _clearFailedPrints,
                              icon: const Icon(Icons.clear, size: 16),
                              label: const Text(
                                'Clear',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Event Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.event.homeTeam} vs ${widget.event.awayTeam}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8.0),
                    Text(widget.event.matchDate),
                    const SizedBox(height: 8.0),
                    Text(widget.event.venue),
                    const SizedBox(height: 8.0),
                    Text('Ticket type: ${widget.ticketType.name}'),
                    const SizedBox(height: 4.0),
                    Text(
                      'Price: ₦${widget.ticketType.price.toStringAsFixed(2)}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16.0),

            // Customer Name
            TextFormField(
              controller: _customerNameController,
              focusNode: _customerNameFocus,
              decoration: const InputDecoration(
                labelText: 'Customer Name (Optional)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16.0),

            // Quantity
            TextFormField(
              controller: _ticketNumberController,
              decoration: const InputDecoration(
                labelText: 'Number of Tickets',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _processSale(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter the number of tickets';
                }
                if (int.tryParse(value) == null || int.parse(value) <= 0) {
                  return 'Please enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16.0),

            // Total Display
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Amount',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '₦${_calculateTotal().toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24.0),

            // SELL Button
            ElevatedButton(
              onPressed: _isSubmitting ? null : _processSale,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _isSubmitting
                  ? const CircularProgressIndicator.adaptive()
                  : const Text('SELL TICKET'),
            ),

            // Quick Actions
            const SizedBox(height: 16.0),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearFormForNextSale,
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _ticketsSoldCount = 0;
                        _printedCount = 0;
                        _printFailedCount = 0;
                        _syncReadyCount = 0;
                        _syncBlockedCount = 0;
                        _printQueue.clear();
                      });
                      _db.clearPrintJobs();
                      _refreshSyncEligibilityCounts();
                      _showQuickMessage('Counter reset');
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reset'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _calculateTotal() {
    final qty = int.tryParse(_ticketNumberController.text) ?? 1;
    return widget.ticketType.price * qty;
  }
}
