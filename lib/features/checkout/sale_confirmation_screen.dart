import 'package:flutter/material.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/models/ticket_model.dart';
import 'package:myapp/data/models/ticket_type.dart';
import 'package:myapp/features/ticket_printing/print_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:uuid/uuid.dart';

class SaleConfirmationScreen extends StatefulWidget {
  final Event event;
  final TicketType ticketType;
  final List<Ticket> tickets;
  final int numberOfTickets;
  final String? customerName;

  const SaleConfirmationScreen({
    super.key,
    required this.event,
    required this.ticketType,
    required this.tickets,
    required this.numberOfTickets,
    this.customerName,
  });

  @override
  State<SaleConfirmationScreen> createState() => _SaleConfirmationScreenState();
}

class _SaleConfirmationScreenState extends State<SaleConfirmationScreen> {
  final PrintService _printService = PrintService();
  bool _isPrinting = false;
  final String transactionId = const Uuid().v4();
  String? _savedPdfPath;

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

    // Use backend-generated references when available
    final ticketCodes = widget.tickets.isNotEmpty
        ? widget.tickets.map((t) => t.referenceNo).toList()
        : List.generate(
            widget.numberOfTickets,
            (_) => 'TKT-${const Uuid().v4().substring(0, 8).toUpperCase()}',
          );

    // Extract ticket IDs from backend response
    final ticketIds = widget.tickets.isNotEmpty
        ? widget.tickets.map((t) => t.id).toList()
        : null;
    final matchIds = widget.tickets.isNotEmpty
        ? widget.tickets.map((t) => t.matchId).toList()
        : null;
    final ticketTypeIds = widget.tickets.isNotEmpty
        ? widget.tickets.map((t) => t.ticketTypeId).toList()
        : null;

    // Print the tickets
    final bool success = await _printService.printMultipleTickets(
      eventName: '${widget.event.homeTeam} vs ${widget.event.awayTeam}',
      ticketType: widget.ticketType.name,
      price: widget.ticketType.price,
      numberOfTickets: widget.numberOfTickets,
      ticketCodes: ticketCodes,
      transactionId: transactionId,
      customerName: widget.customerName,
      ticketIds: ticketIds,
      matchIds: matchIds,
      ticketTypeIds: ticketTypeIds,
      onSavedPdf: (path) {
        _savedPdfPath = path;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No printer found. Saved tickets PDF: $path'),
              action: SnackBarAction(
                label: 'Share',
                onPressed: () {
                  Share.shareXFiles([XFile(path)], text: 'Tickets PDF');
                },
              ),
            ),
          );
        }
      },
    );

    setState(() {
      _isPrinting = false;
    });

    if (!mounted) return;

    final usedPdfFallback = _savedPdfPath != null;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (usedPdfFallback
                    ? 'Tickets saved to PDF. You can view or share below.'
                    : 'Tickets printed successfully')
              : 'Failed to print tickets. Please try again.',
        ),
      ),
    );

    // Auto-pop only when thermal print succeeded and no PDF fallback was used
    if (success && !usedPdfFallback) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.of(context).pop();
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
              Column(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Colors.green,
                    size: 80,
                  ),
                  const SizedBox(height: 20),
                  Text('${widget.event.homeTeam} vs ${widget.event.awayTeam}'),
                  const SizedBox(height: 8),
                  Text('${widget.numberOfTickets} × ${widget.ticketType.name}'),
                  const SizedBox(height: 4),
                  Text(
                    'Customer: ${(widget.customerName == null || widget.customerName!.isEmpty) ? 'N/A' : widget.customerName}',
                  ),
                ],
              ),
            const SizedBox(height: 30),
            _isPrinting
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    child: Column(
                      children: [
                        // Action row: View + Share side by side when PDF exists
                        if (_savedPdfPath != null) ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    final path = _savedPdfPath!;
                                    OpenFilex.open(path);
                                  },
                                  icon: const Icon(Icons.picture_as_pdf),
                                  label: const Text('View PDF'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    final path = _savedPdfPath!;
                                    Share.shareXFiles([
                                      XFile(path),
                                    ], text: 'Tickets PDF');
                                  },
                                  icon: const Icon(Icons.ios_share),
                                  label: const Text('Share PDF'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Tickets History entry point
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed('/tickets-history');
                          },
                          icon: const Icon(Icons.folder),
                          label: const Text('Tickets History'),
                        ),
                        const SizedBox(height: 12),

                        // Back button
                        ElevatedButton.icon(
                          style: ButtonStyle(
                            padding: WidgetStateProperty.all(
                              const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Go Back'),
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
