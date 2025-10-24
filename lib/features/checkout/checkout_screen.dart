import 'package:flutter/material.dart';
import 'package:myapp/data/models/event_model.dart';

class CheckoutScreen extends StatelessWidget {
  final Event event;

  const CheckoutScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Center(child: Text('Checkout screen for ${event.title}')),
    );
  }
}
