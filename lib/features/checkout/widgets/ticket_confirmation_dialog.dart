import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:myapp/features/ticket_printing/print_service.dart';
import 'package:open_filex/open_filex.dart';

/// Ticket Confirmation Dialog
///
/// Shows ticket details with QR code after successful sale
/// Automatically prints the ticket using PrintService
/// If printing fails, saves PDF as fallback
class TicketConfirmationDialog extends StatefulWidget {
  final String ticketId;
  final String eventName;
  final String ticketType;
  final double amount;
  final String? customerName;
  final String qrPayload;

  const TicketConfirmationDialog({
    super.key,
    required this.ticketId,
    required this.eventName,
    required this.ticketType,
    required this.amount,
    this.customerName,
    required this.qrPayload,
  });

  @override
  State<TicketConfirmationDialog> createState() =>
      _TicketConfirmationDialogState();
}

class _TicketConfirmationDialogState extends State<TicketConfirmationDialog> {
  final PrintService _printService = PrintService();
  bool _isProcessing = false;
  bool _printSuccess = false;
  String? _savedPdfPath;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    // Automatically print ticket on dialog display
    _printTicket();
  }

  Future<void> _printTicket() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Printing ticket...';
      _savedPdfPath = null;
    });

    try {
      // Try to print first
      final success = await _printService.printTicket(
        eventName: widget.eventName,
        ticketType: widget.ticketType,
        price: widget.amount,
        ticketNumber: 1,
        totalTickets: 1,
        ticketCode: widget.ticketId,
        validationUrl: widget.qrPayload,
        transactionId: widget.ticketId,
        customerName: widget.customerName,
      );

      if (success) {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _printSuccess = true;
            _statusMessage = 'Printed successfully';
          });
        }
      } else {
        // Printing failed - save PDF as fallback
        await _savePdfFallback();
      }
    } catch (e) {
      // Error during printing - save PDF as fallback
      await _savePdfFallback();
    }
  }

  Future<void> _savePdfFallback() async {
    setState(() {
      _statusMessage = 'Saving PDF...';
    });

    try {
      String? pdfPath;
      await _printService.printMultipleTickets(
        eventName: widget.eventName,
        ticketType: widget.ticketType,
        price: widget.amount,
        numberOfTickets: 1,
        ticketCodes: [widget.ticketId],
        transactionId: widget.ticketId,
        customerName: widget.customerName,
        onSavedPdf: (path) {
          pdfPath = path;
        },
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _printSuccess = false;
          _savedPdfPath = pdfPath;
          _statusMessage = pdfPath != null
              ? 'Ticket saved as PDF'
              : 'Failed to save PDF';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Failed to save ticket: $e';
        });
      }
    }
  }

  Future<void> _openPdf() async {
    if (_savedPdfPath != null) {
      try {
        await OpenFilex.open(_savedPdfPath!);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not open PDF: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green.shade700,
                  size: 64,
                ),
              ),
              const SizedBox(height: 16),
              // Title
              Text(
                'Ticket Created!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(height: 8),
              // Status Message
              if (_statusMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _printSuccess
                        ? Colors.green.shade50
                        : _savedPdfPath != null
                        ? Colors.blue.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isProcessing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _printSuccess
                              ? Icons.print
                              : _savedPdfPath != null
                              ? Icons.picture_as_pdf
                              : Icons.warning,
                          color: _printSuccess
                              ? Colors.green.shade700
                              : _savedPdfPath != null
                              ? Colors.blue.shade700
                              : Colors.orange.shade700,
                          size: 16,
                        ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            color: _printSuccess
                                ? Colors.green.shade700
                                : _savedPdfPath != null
                                ? Colors.blue.shade700
                                : Colors.orange.shade700,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              // QR Code
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                ),
                child: QrImageView(
                  data: widget.qrPayload,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              // Ticket Details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(
                      context,
                      'Ticket ID',
                      widget.ticketId,
                      isMonospace: true,
                    ),
                    const Divider(),
                    _buildDetailRow(context, 'Event', widget.eventName),
                    const Divider(),
                    _buildDetailRow(context, 'Type', widget.ticketType),
                    if (widget.customerName != null &&
                        widget.customerName!.isNotEmpty) ...[
                      const Divider(),
                      _buildDetailRow(
                        context,
                        'Customer',
                        widget.customerName!,
                      ),
                    ],
                    const Divider(),
                    _buildDetailRow(
                      context,
                      'Amount',
                      '\$${widget.amount.toStringAsFixed(2)}',
                      valueStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Sync Notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ticket will be synced to server when online',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareTicket(context),
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_savedPdfPath != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _openPdf,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                        ),
                      ),
                    )
                  else if (!_printSuccess && !_isProcessing)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _printTicket,
                        icon: const Icon(Icons.print),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                Navigator.of(
                                  context,
                                ).pop(); // Return to previous screen
                              },
                        icon: const Icon(Icons.check),
                        label: const Text('Done'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    bool isMonospace = false,
    TextStyle? valueStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style:
                  valueStyle ??
                  TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    fontFamily: isMonospace ? 'monospace' : null,
                  ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  void _shareTicket(BuildContext context) {
    final text =
        '''
Ticket Confirmation

Event: ${widget.eventName}
Type: ${widget.ticketType}
${widget.customerName != null && widget.customerName!.isNotEmpty ? 'Customer: ${widget.customerName}\n' : ''}Amount: \$${widget.amount.toStringAsFixed(2)}
Ticket ID: ${widget.ticketId}

Scan the QR code at the venue for entry.
''';

    Share.share(text, subject: 'Ticket for ${widget.eventName}');
  }
}
