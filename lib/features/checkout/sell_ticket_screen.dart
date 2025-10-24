
import 'package:flutter/material.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/models/ticket_model.dart';
import 'package:myapp/features/checkout/sale_confirmation_screen.dart';

class SellTicketScreen extends StatefulWidget {
  final Event? event; // Make event nullable
  final Ticket? ticket; // Make ticket nullable

  const SellTicketScreen({super.key, this.event, this.ticket});

  @override
  State<SellTicketScreen> createState() => _SellTicketScreenState();
}

class _SellTicketScreenState extends State<SellTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _ticketNumberController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();

  // Mock data for event and ticket if not provided
  late Event _event;
  late Ticket _ticket;

  @override
  void initState() {
    super.initState();
    _event = widget.event ??
        Event(
          id: '1',
          title: 'Default Event',
          description: 'This is a default event description.',
          date: '2024-12-25',
          location: 'Default Location',
          imageUrl: 'https://via.placeholder.com/150',
          category: 'Default Category',
        );
    _ticket = widget.ticket ??
        Ticket(
          id: '1',
          eventId: '1',
          type: 'General Admission',
          price: 50.00,
          quantity: 100,
        );
  }

  void _processSale() {
    if (_formKey.currentState!.validate()) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SaleConfirmationScreen(
            event: _event,
            ticket: _ticket,
            numberOfTickets: int.parse(_ticketNumberController.text),
            customerName: _customerNameController.text,
          ),
        ),
      );
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
                        _event.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8.0),
                      Text(_event.date),
                      const SizedBox(height: 8.0),
                      Text(_event.location),
                    ],
                  ),
                ),
              ),
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
                onPressed: _processSale,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Confirm Sale'),
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
