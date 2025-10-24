import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:myapp/features/ticket_validation/validation_result_screen.dart';

class TicketValidatorScreen extends StatefulWidget {
  const TicketValidatorScreen({super.key});

  @override
  State<TicketValidatorScreen> createState() => _TicketValidatorScreenState();
}

class _TicketValidatorScreenState extends State<TicketValidatorScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Validate Ticket')),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 5,
            child: MobileScanner(
              key: qrKey,
              onDetect: (capture) {
                if (!_isProcessing) {
                  _isProcessing = true;
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty) {
                    final String? code = barcodes.first.rawValue;
                    if (code != null) {
                      _navigateToResult(code);
                    }
                  }
                }
              },
            ),
          ),
          const Expanded(
            flex: 1,
            child: Center(child: Text('Scan a ticket QR code')),
          ),
        ],
      ),
    );
  }

  void _navigateToResult(String code) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ValidationResultScreen(scanData: code),
      ),
    ).then(
      (_) => _isProcessing = false,
    ); // Reset processing flag when returning
  }
}
