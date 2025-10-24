
import 'package:flutter/material.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/models/ticket_model.dart';
import 'package:myapp/features/checkout/sell_ticket_screen.dart';
import 'package:myapp/features/ticket_printing/print_service.dart';
import 'package:uuid/uuid.dart';

class SaleConfirmationScreen extends StatefulWidget {
  final Event event;
  final Ticket ticket;
  final int numberOfTickets;
  final String customerName;

  const SaleConfirmationScreen({
    super.key,
    required this.event,
    required this.ticket,
    required this.numberOfTickets,
    required this.customerName,
  });

  @override
  State<SaleConfirmationScreen> createState() => _SaleConfirmationScreenState();
}

class _SaleConfirmationScreenState extends State<SaleConfirmationScreen> {
  final PrintService _printService = PrintService();
  bool _isPrinting = false;
  final String transactionId = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _printAndNavigate();
    });
  }

  Future<void> _printAndNavigate() async {
    setState(() {
      _isPrinting = true;
    });

    // Generate unique ticket codes
    final ticketCodes = List.generate(
      widget.numberOfTickets,
      (index) => 'TKT-${const Uuid().v4().substring(0, 8).toUpperCase()}',
    );

    // Print the tickets
    final bool success = await _printService.printMultipleTickets(
      eventName: widget.event.title,
      ticketType: widget.ticket.type,
      price: widget.ticket.price,
      numberOfTickets: widget.numberOfTickets,
      ticketCodes: ticketCodes,
      transactionId: transactionId,
      customerName: widget.customerName,
    );

    setState(() {
      _isPrinting = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Printing complete!' : 'Printing failed. Please try again.',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );

      // Navigate back to the SellTicketScreen after a short delay
      await Future.delayed(const Duration(seconds: 2));
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SellTicketScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirming Sale...'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isPrinting)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Printing tickets, please wait...'),
                ],
              )
            else
              const Column(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
                  SizedBox(height: 20),
                  Text('Sale Confirmed!'),
                ],
              ),
            const SizedBox(height: 30),
            _isPrinting
                ? const SizedBox.shrink()
                : ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const SellTicketScreen(),
                        ),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Go Back Manually'),
                  ),
          ],
        ),
      ),
    );
  }
}
