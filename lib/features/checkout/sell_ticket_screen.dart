
import 'package:flutter/material.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/models/ticket_type.dart';
import 'package:myapp/data/services/ticket_api.dart';
import 'package:myapp/features/checkout/sale_confirmation_screen.dart';

class SellTicketScreen extends StatefulWidget {
  final Event event;
  final TicketType ticketType;

  const SellTicketScreen({super.key, required this.event, required this.ticketType});

  @override
  State<SellTicketScreen> createState() => _SellTicketScreenState();
}

class _SellTicketScreenState extends State<SellTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _ticketNumberController = TextEditingController(text: '1');
  final TextEditingController _customerNameController = TextEditingController();
  final TicketApi _ticketApi = TicketApi();
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
      final bookedTickets = await _ticketApi.bookTicket(
        matchId: widget.event.id,
        ticketTypeId: widget.ticketType.id,
        quantity: quantity,
        amount: amount,
        customerName: customerName.isEmpty ? null : customerName,
      );

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SaleConfirmationScreen(
            event: widget.event,
            ticketType: widget.ticketType,
            tickets: bookedTickets,
            numberOfTickets: quantity,
            customerName: customerName,
          ),
        ),
      );

      if (!mounted) return;

      _ticketNumberController.text = '1';
      _customerNameController.clear();
    } catch (e) {
      setState(() {
        _error = 'Failed to process sale. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sell Ticket')),
      body: SingleChildScrollView(
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
                      Text('Price: ₦${widget.ticketType.price.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12.0),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
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
                  labelText: 'Customer Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the customer\'s name';
                  }
                  return null;
                },
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
      ),
    );
  }

  @override
  void dispose() {
    _ticketNumberController.dispose();
    _customerNameController.dispose();
    super.dispose();
  }
}
