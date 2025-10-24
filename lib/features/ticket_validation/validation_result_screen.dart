import 'package:flutter/material.dart';

class ValidationResultScreen extends StatelessWidget {
  final String scanData;

  const ValidationResultScreen({super.key, required this.scanData});

  @override
  Widget build(BuildContext context) {
    // In a real app, you would validate the scanData against your backend.
    final bool isValid = scanData.startsWith('SALE-');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Validation Result'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              isValid ? Icons.check_circle : Icons.cancel,
              color: isValid ? Colors.green : Colors.red,
              size: 100,
            ),
            const SizedBox(height: 24.0),
            Text(
              isValid ? 'Ticket Valid' : 'Ticket Invalid',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: isValid ? Colors.green : Colors.red,
                  ),
            ),
            const SizedBox(height: 16.0),
            if (isValid)
              Text(
                'Ticket ID: $scanData',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 32.0),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Scan Another'),
            ),
          ],
        ),
      ),
    );
  }
}
