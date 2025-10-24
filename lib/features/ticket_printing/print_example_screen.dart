import 'package:flutter/material.dart';
import 'print_service.dart';
import 'printer_selection_dialog.dart';

class PrintExampleScreen extends StatefulWidget {
  @override
  State<PrintExampleScreen> createState() => _PrintExampleScreenState();
}

class _PrintExampleScreenState extends State<PrintExampleScreen> {
  final PrintService _printService = PrintService();
  bool _isPrinting = false;

  Future<void> _printTickets() async {
    final isConnected = await _printService.isConnected();
    if (!isConnected) {
      final selected = await showDialog(
        context: context,
        builder: (context) => PrinterSelectionDialog(),
      );
      if (selected != true) {
        return;
      }
    }

    setState(() => _isPrinting = true);

    final ticketCodes = [
      'TKT-001-ABC123',
      'TKT-002-DEF456',
      'TKT-003-GHI789',
    ];

    final success = await _printService.printMultipleTickets(
      eventName: 'Summer Music Festival 2025',
      ticketType: 'VIP Access',
      price: 150.00,
      numberOfTickets: 3,
      ticketCodes: ticketCodes,
      transactionId: 'TXN-20251024-001',
      customerName: 'John Doe',
      customerEmail: 'john@example.com',
      customerPhone: '+1234567890',
    );

    setState(() => _isPrinting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully printed ${ticketCodes.length} tickets')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to print tickets'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Print Tickets')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isPrinting)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _printTickets,
                child: const Text('Print Example Tickets'),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => showPrinterSelection(context),
              child: const Text('Select Printer'),
            ),
          ],
        ),
      ),
    );
  }
}
