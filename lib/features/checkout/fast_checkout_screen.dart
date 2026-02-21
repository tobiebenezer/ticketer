import 'package:flutter/material.dart';
import 'package:myapp/core/services/offline_sale_service.dart';
import 'package:myapp/data/local/database_helper.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/services/sync_service.dart';
import 'package:myapp/features/checkout/widgets/print_flow_drawer.dart';
import 'package:myapp/features/ticket_printing/print_service.dart';
import 'package:myapp/features/ticket_validation/widgets/sync_status_widget.dart';

/// Fast Checkout Screen - Optimized for rapid ticket sales
///
/// Features:
/// - Instant ticket creation (no waiting for print)
/// - Queued printing with status tracking
/// - Auto-clear form for next sale
/// - Quick toast notifications
class FastCheckoutScreen extends StatefulWidget {
  final Event event;
  final int ticketTypeId;
  final String ticketTypeName;
  final double ticketPrice;

  const FastCheckoutScreen({
    super.key,
    required this.event,
    required this.ticketTypeId,
    required this.ticketTypeName,
    required this.ticketPrice,
  });

  @override
  State<FastCheckoutScreen> createState() => _FastCheckoutScreenState();
}

class _FastCheckoutScreenState extends State<FastCheckoutScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final OfflineSaleService _saleService = OfflineSaleService();
  final DatabaseHelper _db = DatabaseHelper();
  final PrintService _printService = PrintService();
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _customerNameFocus = FocusNode();

  bool _isProcessing = false;
  bool _eventReady = false;
  bool _isCheckingEvent = true;
  int _ticketsSoldCount = 0;

  // Print queue tracking
  final List<PrintFlowJob> _printQueue = [];
  int _printingCount = 0;
  bool _isProcessingPrintQueue = false;
  int _printedCount = 0;
  int _printFailedCount = 0;
  int _syncReadyCount = 0;
  int _syncBlockedCount = 0;
  bool _isManualSyncing = false;

  @override
  void initState() {
    super.initState();
    _checkEventReady();
    _loadPersistedPrintJobs();
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _quantityController.dispose();
    _customerNameFocus.dispose();
    super.dispose();
  }

  Future<void> _checkEventReady() async {
    final ready = await _saleService.isEventReady(widget.event.id);
    if (mounted) {
      setState(() {
        _eventReady = ready;
        _isCheckingEvent = false;
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

  Future<void> _bootstrapEvent() async {
    setState(() {
      _isCheckingEvent = true;
    });

    final success = await _saleService.bootstrapEvent(widget.event.id);
    if (mounted) {
      setState(() {
        _eventReady = success;
        _isCheckingEvent = false;
      });

      if (!success) {
        _showQuickMessage('Failed to sync event data', isError: true);
      }
    }
  }

  Future<void> _processSale() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
    });

    final quantity = int.tryParse(_quantityController.text) ?? 1;
    final customerName = _customerNameController.text.trim();

    try {
      if (quantity == 1) {
        // Single ticket - FAST PATH
        final result = await _saleService.createTicket(
          matcheId: widget.event.id,
          ticketTypesId: widget.ticketTypeId,
          amount: widget.ticketPrice,
          customerName: customerName.isEmpty ? null : customerName,
        );

        if (mounted) {
          setState(() {
            _isProcessing = false;
          });

          if (result.isSuccess) {
            // Increment counter
            setState(() {
              _ticketsSoldCount++;
            });

            // Queue print job
            _queuePrintJob(
              ticketId: result.ticketId!,
              customerName: customerName,
              ticketNumber: 1,
              totalTickets: 1,
              purchaseBatchId: result.ticketId,
              purchaseIndex: 1,
              purchaseQuantity: 1,
            );

            // Clear form immediately for next sale
            _clearFormForNextSale();

            // Quick success feedback
            _showQuickMessage(
              'Ticket #${_ticketsSoldCount} created',
              isSuccess: true,
            );
          } else {
            _showQuickMessage(result.errorMessage ?? 'Failed', isError: true);
          }
        }
      } else {
        // Batch sale
        final result = await _saleService.createTickets(
          matcheId: widget.event.id,
          ticketTypesId: widget.ticketTypeId,
          amount: widget.ticketPrice,
          quantity: quantity,
          customerName: customerName.isEmpty ? null : customerName,
        );

        if (mounted) {
          setState(() {
            _isProcessing = false;
            _ticketsSoldCount += result.successCount;
          });

          // Queue all successful tickets for printing
          final purchaseBatchId = '${DateTime.now().microsecondsSinceEpoch}';
          for (int i = 0; i < result.successfulTickets.length; i++) {
            final ticket = result.successfulTickets[i];
            _queuePrintJob(
              ticketId: ticket.ticketId!,
              customerName: customerName,
              ticketNumber: i + 1,
              totalTickets: result.successfulTickets.length,
              purchaseBatchId: purchaseBatchId,
              purchaseIndex: i + 1,
              purchaseQuantity: result.successfulTickets.length,
            );
          }

          _clearFormForNextSale();
          _showQuickMessage(
            '${result.successCount} tickets created',
            isSuccess: true,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        _showQuickMessage('Error: $e', isError: true);
      }
    }
  }

  /// Queue a print job and process it
  void _queuePrintJob({
    required String ticketId,
    required String customerName,
    required int ticketNumber,
    required int totalTickets,
    String? purchaseBatchId,
    int? purchaseIndex,
    int? purchaseQuantity,
  }) {
    final now = DateTime.now();
    final job = PrintFlowJob(
      id: '${ticketId}_${DateTime.now().microsecondsSinceEpoch}',
      ticketId: ticketId,
      customerName: customerName,
      ticketNumber: ticketNumber,
      totalTickets: totalTickets,
      purchaseBatchId: purchaseBatchId,
      purchaseIndex: purchaseIndex ?? ticketNumber,
      purchaseQuantity: purchaseQuantity ?? totalTickets,
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

  /// Process print queue sequentially.
  /// For Bluetooth: connects ONCE before the loop and reuses the connection
  /// for all queued jobs — avoids per-ticket reconnect lag.
  Future<void> _processPrintQueue() async {
    if (_printingCount > 0 || _isProcessingPrintQueue) return;
    _isProcessingPrintQueue = true;

    try {
      final printPath = await _printService.getPreferredPrintPath();
      final isBluetooth = printPath == 'bluetooth';

      // For BT: establish connection once before processing any jobs.
      bool btConnected = false;
      if (isBluetooth) {
        btConnected = await _printService.ensureBluetoothConnected();
        if (!btConnected) {
          final reason =
              _printService.lastBluetoothError ??
              'Bluetooth printer not connected. Check selected printer and permissions.';
          _showQuickMessage(reason, isError: true);
          return;
        }
      }

      final eventName = '${widget.event.homeTeam} vs ${widget.event.awayTeam}';

      while (true) {
        final nextIndex = _printQueue.indexWhere(
          (job) => job.status == PrintFlowStatus.queued,
        );
        if (nextIndex == -1) break;

        final job = _printQueue[nextIndex];

        setState(() {
          _printingCount++;
          job.status = PrintFlowStatus.sending;
          job.attemptCount++;
          job.updatedAt = DateTime.now();
        });
        await _persistJob(job);

        try {
          PrintDispatchResult result;

          if (isBluetooth && btConnected) {
            // Fast path: reuse existing BT connection — no reconnect overhead
            result = await _printService.printSingleTicketBluetooth(
              eventName: eventName,
              ticketType: widget.ticketTypeName,
              price: widget.ticketPrice,
              ticketNumber: job.effectiveTicketNumber,
              totalTickets: job.effectiveTotalTickets,
              ticketCode: job.ticketId,
              validationUrl: job.ticketId,
              ticketId: job.displayTicketId,
              customerName: job.customerName.isEmpty ? null : job.customerName,
              venue: widget.event.venue,
            );
          } else {
            // WiFi / system path (or BT fallback if connect failed)
            result = await _printService.printTicketWithResult(
              eventName: eventName,
              ticketType: widget.ticketTypeName,
              price: widget.ticketPrice,
              ticketNumber: job.effectiveTicketNumber,
              totalTickets: job.effectiveTotalTickets,
              ticketCode: job.ticketId,
              validationUrl: job.ticketId,
              transactionId: job.ticketId,
              customerName: job.customerName.isEmpty ? null : job.customerName,
            );
          }

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

          if (result.isSent) {
            // Short inter-ticket pause — lets the printer finish cutting/feeding
            // before the next ESC/POS command stream arrives.
            // Configurable in Settings; default 500ms is safe for most printers.
            final delayMs = await _printService.getInterTicketDelayMs();
            if (delayMs > 0) {
              await Future.delayed(Duration(milliseconds: delayMs));
            }
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
          break;
        }
      }
    } finally {
      _isProcessingPrintQueue = false;
    }
  }

  void _retryFailedPrints() {
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
    _processPrintQueue();
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

  /// Clear form and focus for next sale
  void _clearFormForNextSale() {
    _customerNameController.clear();
    _quantityController.text = '1';
    // Auto-focus customer name for next entry
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _customerNameFocus.requestFocus();
      }
    });
  }

  /// Show quick toast message
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Column(
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
        ),
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
      body: _isCheckingEvent
          ? const Center(child: CircularProgressIndicator())
          : !_eventReady
          ? _buildEventNotReady()
          : _buildFastCheckoutForm(),
    );
  }

  Widget _buildEventNotReady() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 80, color: Colors.orange.shade700),
            const SizedBox(height: 24),
            Text(
              'Event data not available offline',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'You need to sync event data before selling tickets offline.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _bootstrapEvent,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Sync Event Data'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFastCheckoutForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sync Status (compact)
            const SyncStatusWidget(),
            const SizedBox(height: 16),

            // Print Queue Status
            if (_queuedPrintCount > 0 || _printFailedCount > 0)
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
                                ? '$_printFailedCount print(s) failed'
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
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Event Info (compact)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.event.homeTeam} vs ${widget.event.awayTeam}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.ticketTypeName} • \$${widget.ticketPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Customer Name (focused for fast entry)
            TextFormField(
              controller: _customerNameController,
              focusNode: _customerNameFocus,
              decoration: const InputDecoration(
                labelText: 'Customer Name (Optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            // Quantity (minimal)
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.confirmation_number),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _processSale(),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Required';
                      final qty = int.tryParse(value);
                      if (qty == null || qty < 1) return 'Min 1';
                      if (qty > 100) return 'Max 100';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Total (inline)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Total', style: TextStyle(fontSize: 12)),
                      Text(
                        '\$${_calculateTotal().toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Large SELL button
            ElevatedButton(
              onPressed: _isProcessing ? null : _processSale,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor: Colors.green,
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : const Text('SELL TICKET'),
            ),

            // Quick actions
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _clearFormForNextSale,
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 8),
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
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reset'),
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
    final qty = int.tryParse(_quantityController.text) ?? 1;
    return widget.ticketPrice * qty;
  }
}
