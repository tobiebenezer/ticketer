import 'package:flutter/material.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/models/ticket_model.dart';
import 'package:myapp/features/checkout/sale_confirmation_screen.dart';
import 'dart:math';

class SellTicketScreen extends StatefulWidget {
  final Event event;
  final Ticket ticket;

  const SellTicketScreen({super.key, required this.event, required this.ticket});

  @override
}

class _SellTicketScreenState extends State<SellTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _ticketNumberController = TextEditingController();

  void _processSale() {
    if (_formKey.currentState!.validate()) {
      // In a real app, you would process the payment and generate a unique sale ID here.
      final saleId =
          'SALE-${Random().nextInt(999999).toString().padLeft(6, '0')}';
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SaleConfirmationScreen(saleId: saleId),
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
                        widget.event.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8.0),
                      Text(widget.event.date),
                      const SizedBox(height: 8.0),
                      Text(widget.event.location),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _ticketNumberController,
                decoration: const InputDecoration(
                  labelText: 'Ticket Number',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter the ticket number';
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
    super.dispose();
  }
}
