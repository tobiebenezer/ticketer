import 'package:flutter/material.dart';
import 'package:myapp/core/services/offline_sale_service.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/features/checkout/widgets/ticket_confirmation_dialog.dart';
import 'package:myapp/features/ticket_validation/widgets/sync_status_widget.dart';

/// Enhanced Checkout Screen with Offline Sale Support
///
/// Features:
/// - Offline ticket creation
/// - Batch ticket sales
/// - Sync status indicator
/// - QR code generation for tickets
class OfflineCheckoutScreen extends StatefulWidget {
  final Event event;
  final int ticketTypeId;
  final String ticketTypeName;
  final double ticketPrice;

  const OfflineCheckoutScreen({
    super.key,
    required this.event,
    required this.ticketTypeId,
    required this.ticketTypeName,
    required this.ticketPrice,
  });

  @override
  State<OfflineCheckoutScreen> createState() => _OfflineCheckoutScreenState();
}

class _OfflineCheckoutScreenState extends State<OfflineCheckoutScreen> {
  final OfflineSaleService _saleService = OfflineSaleService();
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  bool _isProcessing = false;
  bool _eventReady = false;
  bool _isCheckingEvent = true;

  @override
  void initState() {
    super.initState();
    _checkEventReady();
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _quantityController.dispose();
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to sync event data. Check internet connection.',
            ),
            backgroundColor: Colors.red,
          ),
        );
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
        // Single ticket sale
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
            _showSuccessDialog(result);
          } else {
            _showErrorDialog(result.errorMessage ?? 'Unknown error');
          }
        }
      } else {
        // Batch ticket sale
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
          });

          _showBatchResultDialog(result);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        _showErrorDialog('Error: $e');
      }
    }
  }

  void _showSuccessDialog(OfflineSaleResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => TicketConfirmationDialog(
        ticketId: result.ticketId!,
        eventName: '${widget.event.homeTeam} vs ${widget.event.awayTeam}',
        ticketType: widget.ticketTypeName,
        amount: widget.ticketPrice,
        customerName: _customerNameController.text.trim(),
        qrPayload: result.qrPayload!,
      ),
    );
  }

  void _showBatchResultDialog(BatchSaleResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.allSuccess ? Icons.check_circle : Icons.warning,
              color: result.allSuccess ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            const Text('Batch Sale Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Tickets: ${result.totalCount}'),
            Text(
              'Successful: ${result.successCount}',
              style: const TextStyle(color: Colors.green),
            ),
            if (result.hasFailures)
              Text(
                'Failed: ${result.failCount}',
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 8),
            Text(
              'Total Amount: \$${result.totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (result.hasFailures) ...[
              const SizedBox(height: 12),
              const Text(
                'Some tickets failed to create. Please try again.',
                style: TextStyle(color: Colors.orange),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Return to previous screen
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Sale Failed'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        actions: const [SyncIndicator()],
      ),
      body: _isCheckingEvent
          ? const Center(child: CircularProgressIndicator())
          : !_eventReady
          ? _buildEventNotReady()
          : _buildCheckoutForm(),
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

  Widget _buildCheckoutForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sync Status
            const SyncStatusWidget(),
            const SizedBox(height: 16),
            // Event Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.event.homeTeam} vs ${widget.event.awayTeam}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16),
                        const SizedBox(width: 4),
                        Text(widget.event.venue),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16),
                        const SizedBox(width: 4),
                        Text(widget.event.matchDate.toString().split(' ')[0]),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Ticket Type Card
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.ticketTypeName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\$${widget.ticketPrice.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Customer Name
            TextFormField(
              controller: _customerNameController,
              decoration: const InputDecoration(
                labelText: 'Customer Name (Optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            // Quantity
            TextFormField(
              controller: _quantityController,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.confirmation_number),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter quantity';
                }
                final qty = int.tryParse(value);
                if (qty == null || qty < 1) {
                  return 'Quantity must be at least 1';
                }
                if (qty > 100) {
                  return 'Maximum 100 tickets per transaction';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            // Total Amount
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Amount',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '\$${(_calculateTotal()).toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Complete Sale Button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _processSale,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.shopping_cart_checkout),
              label: Text(_isProcessing ? 'Processing...' : 'Complete Sale'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
              ),
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
