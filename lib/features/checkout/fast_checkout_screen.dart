import 'package:flutter/material.dart';
import 'package:myapp/core/services/offline_sale_service.dart';
import 'package:myapp/data/models/event_model.dart';
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
  final OfflineSaleService _saleService = OfflineSaleService();
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
  final List<PrintJob> _printQueue = [];
  int _printingCount = 0;
  int _printedCount = 0;
  int _printFailedCount = 0;

  @override
  void initState() {
    super.initState();
    _checkEventReady();
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
          for (final ticket in result.successfulTickets) {
            _queuePrintJob(
              ticketId: ticket.ticketId!,
              customerName: customerName,
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
  }) {
    final job = PrintJob(
      ticketId: ticketId,
      customerName: customerName,
      ticketNumber: _ticketsSoldCount,
    );

    setState(() {
      _printQueue.add(job);
    });

    // Process the queue
    _processPrintQueue();
  }

  /// Process print queue sequentially to ensure completion
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
        String? savedPdfPath;
        final success = await _printService.printTicket(
          eventName: '${widget.event.homeTeam} vs ${widget.event.awayTeam}',
          ticketType: widget.ticketTypeName,
          price: widget.ticketPrice,
          ticketNumber: job.ticketNumber,
          totalTickets: _ticketsSoldCount,
          ticketCode: job.ticketId,
          validationUrl: job.ticketId,
          transactionId: job.ticketId,
          customerName: job.customerName.isEmpty ? null : job.customerName,
          onSavedPdf: (path) {
            savedPdfPath = path;
          },
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

          if (savedPdfPath != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('No printer found. Ticket saved to: $savedPdfPath'),
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }

        // Small delay between prints to avoid printer overload
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
      appBar: AppBar(
        title: Column(
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
        ),
        actions: const [SyncIndicator()],
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
            if (_printQueue.isNotEmpty || _printFailedCount > 0)
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
                      });
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
