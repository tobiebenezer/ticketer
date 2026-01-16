import 'package:flutter/material.dart';
import 'package:myapp/core/services/offline_sale_service.dart';
import 'package:myapp/core/services/app_settings_service.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/models/ticket_model.dart';
import 'package:myapp/data/models/ticket_type.dart';
import 'package:myapp/data/services/ticket_api.dart';
import 'package:myapp/features/checkout/sale_confirmation_screen.dart';
import 'package:myapp/features/ticket_printing/print_service.dart';
import 'package:myapp/features/ticket_validation/widgets/sync_status_widget.dart';

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

  bool _isSubmitting = false;
  String? _error;

  // Settings (loaded on init)
  bool _isFastMode = false;
  bool _autoPrintEnabled = true;

  // Fast mode features
  int _ticketsSoldCount = 0;
  final List<PrintJob> _printQueue = [];
  int _printingCount = 0;
  int _printedCount = 0;
  int _printFailedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();

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
          for (int i = 0; i < offlineTicketIds.length; i++) {
            _queuePrintJob(
              ticketId: offlineTicketIds[i],
              customerName: customerName,
              ticketNumber: _ticketsSoldCount - quantity + i + 1,
            );
          }
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
          for (int i = 0; i < bookedTickets.length; i++) {
            _queuePrintJob(
              ticketId: bookedTickets[i].id.toString(),
              customerName: customerName,
              ticketNumber: _ticketsSoldCount - quantity + i + 1,
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

  /// Queue a print job and process it
  void _queuePrintJob({
    required String ticketId,
    required String customerName,
    required int ticketNumber,
  }) {
    final job = PrintJob(
      ticketId: ticketId,
      customerName: customerName,
      ticketNumber: ticketNumber,
    );

    setState(() {
      _printQueue.add(job);
    });

    // Process the queue
    _processPrintQueue();
  }

  /// Process print queue sequentially
  Future<void> _processPrintQueue() async {
    // If already printing, don't start another process
    if (_printingCount > 0) return;

    while (_printQueue.isNotEmpty) {
      final job = _printQueue.first;

      setState(() {
        _printingCount++;
        job.status = PrintStatus.printing;
      });

      try {
        final success = await _printService.printTicket(
          eventName: '${widget.event.homeTeam} vs ${widget.event.awayTeam}',
          ticketType: widget.ticketType.name,
          price: widget.ticketType.price,
          ticketNumber: job.ticketNumber,
          totalTickets: _ticketsSoldCount,
          ticketCode: job.ticketId,
          validationUrl: job.ticketId,
          transactionId: job.ticketId,
          customerName: job.customerName.isEmpty ? null : job.customerName,
        );

        if (mounted) {
          setState(() {
            job.status = success ? PrintStatus.completed : PrintStatus.failed;
            if (success) {
              _printedCount++;
            } else {
              _printFailedCount++;
            }
            _printingCount--;
            _printQueue.removeAt(0);
          });
        }

        // Small delay between prints
        if (_printQueue.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            job.status = PrintStatus.failed;
            _printFailedCount++;
            _printingCount--;
            _printQueue.removeAt(0);
          });
        }
        debugPrint('Print failed: $e');
      }
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isFastMode
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Fast Checkout'),
                  if (_ticketsSoldCount > 0)
                    Text(
                      '$_ticketsSoldCount sold • ${_printQueue.length} queued • $_printedCount printed',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                ],
              )
            : const Text('Sell Ticket'),
        actions: _isFastMode ? const [SyncIndicator()] : null,
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
            if (_printQueue.isNotEmpty || _printFailedCount > 0) ...[
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
                child: Row(
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
                            ? 'Printing... ${_printQueue.length} in queue'
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
                      });
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

/// Print job model
class PrintJob {
  final String ticketId;
  final String customerName;
  final int ticketNumber;
  PrintStatus status;

  PrintJob({
    required this.ticketId,
    required this.customerName,
    required this.ticketNumber,
    this.status = PrintStatus.queued,
  });
}

enum PrintStatus { queued, printing, completed, failed }
