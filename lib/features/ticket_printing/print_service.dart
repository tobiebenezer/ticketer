import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:myapp/core/constants/network_constants.dart';
import 'package:myapp/core/services/app_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/features/ticket_printing/network_print_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

enum PrintDispatchStatus { sent, failed, pdfFallback }

class PrintDispatchResult {
  final PrintDispatchStatus status;
  final String mode;
  final String? error;
  final String? pdfPath;

  const PrintDispatchResult({
    required this.status,
    required this.mode,
    this.error,
    this.pdfPath,
  });

  bool get isSent => status == PrintDispatchStatus.sent;
  bool get isFailed => status == PrintDispatchStatus.failed;
  bool get isPdfFallback => status == PrintDispatchStatus.pdfFallback;
}

class PrintService {
  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;
  final AppSettingsService _settingsService = AppSettingsService();

  // Thermal printer paper width in pixels (58mm ≈ 384px)
  static const double kPaperWidthPx = 384.0;

  // --- 1. PRINT SINGLE TICKET (Direct Print) ---
  Future<PrintDispatchResult> printTicketWithResult({
    required String eventName,
    required String ticketType,
    required double price,
    required int ticketNumber,
    required int totalTickets,
    required String ticketCode,
    required String validationUrl,
    required String transactionId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? venue,
    int? ticketId,
    int? matchId,
    int? ticketTypeId,
    void Function(String pdfPath)? onSavedPdf,
  }) async {
    final mode = await _getPreferredPrintPath();
    String? savedPdfPath;

    final success = await printTicket(
      eventName: eventName,
      ticketType: ticketType,
      price: price,
      ticketNumber: ticketNumber,
      totalTickets: totalTickets,
      ticketCode: ticketCode,
      validationUrl: validationUrl,
      transactionId: transactionId,
      customerName: customerName,
      customerEmail: customerEmail,
      customerPhone: customerPhone,
      venue: venue,
      ticketId: ticketId,
      matchId: matchId,
      ticketTypeId: ticketTypeId,
      onSavedPdf: (path) {
        savedPdfPath = path;
        if (onSavedPdf != null) {
          onSavedPdf(path);
        }
      },
    );

    if (!success) {
      return PrintDispatchResult(
        status: PrintDispatchStatus.failed,
        mode: mode,
        error: 'Failed to send ticket to printer',
      );
    }

    if (savedPdfPath != null) {
      return PrintDispatchResult(
        status: PrintDispatchStatus.pdfFallback,
        mode: mode,
        pdfPath: savedPdfPath,
      );
    }

    return PrintDispatchResult(status: PrintDispatchStatus.sent, mode: mode);
  }

  Future<PrintDispatchResult> printMultipleTicketsWithResult({
    required String eventName,
    required String ticketType,
    required double price,
    required int numberOfTickets,
    required List<String> ticketCodes,
    required String transactionId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? deviceAddress,
    void Function(String pdfPath)? onSavedPdf,
    int connectTimeoutMs = 1200,
    String? venue,
    List<int>? ticketIds,
    List<int>? matchIds,
    List<int>? ticketTypeIds,
  }) async {
    final mode = await _getPreferredPrintPath();
    String? savedPdfPath;

    final success = await printMultipleTickets(
      eventName: eventName,
      ticketType: ticketType,
      price: price,
      numberOfTickets: numberOfTickets,
      ticketCodes: ticketCodes,
      transactionId: transactionId,
      customerName: customerName,
      customerEmail: customerEmail,
      customerPhone: customerPhone,
      deviceAddress: deviceAddress,
      onSavedPdf: (path) {
        savedPdfPath = path;
        if (onSavedPdf != null) {
          onSavedPdf(path);
        }
      },
      connectTimeoutMs: connectTimeoutMs,
      venue: venue,
      ticketIds: ticketIds,
      matchIds: matchIds,
      ticketTypeIds: ticketTypeIds,
    );

    if (!success) {
      return PrintDispatchResult(
        status: PrintDispatchStatus.failed,
        mode: mode,
        error: 'Failed to send tickets to printer',
      );
    }

    if (savedPdfPath != null) {
      return PrintDispatchResult(
        status: PrintDispatchStatus.pdfFallback,
        mode: mode,
        pdfPath: savedPdfPath,
      );
    }

    return PrintDispatchResult(status: PrintDispatchStatus.sent, mode: mode);
  }

  Future<String> _getPreferredPrintPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('kPreferredPrintPath') ?? 'system';
  }

  Future<bool> printTicket({
    required String eventName,
    required String ticketType,
    required double price,
    required int ticketNumber,
    required int totalTickets,
    required String ticketCode,
    required String validationUrl,
    required String transactionId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? venue,
    int? ticketId,
    int? matchId,
    int? ticketTypeId,
    void Function(String pdfPath)? onSavedPdf,
  }) async {
    // Use the multi-path printing logic from printMultipleTickets
    return await printMultipleTickets(
      eventName: eventName,
      ticketType: ticketType,
      price: price,
      numberOfTickets: 1,
      ticketCodes: [ticketCode],
      transactionId: transactionId,
      ticketNumbers: [ticketNumber],
      ticketTotals: [totalTickets],
      customerName: customerName,
      customerEmail: customerEmail,
      customerPhone: customerPhone,
      venue: venue,
      ticketIds: ticketId != null ? [ticketId] : null,
      matchIds: matchId != null ? [matchId] : null,
      ticketTypeIds: ticketTypeId != null ? [ticketTypeId] : null,
      onSavedPdf: onSavedPdf,
    );
  }

  // Get default printer (only works on desktop/web)
  Future<Printer?> _getDefaultPrinter() async {
    try {
      // Check if we're on a platform that supports printer listing
      if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
        // Mobile platforms don't support Printing.listPrinters()
        // Return null to trigger fallback to Bluetooth printing
        return null;
      }

      final printers = await Printing.listPrinters();
      if (printers.isEmpty) return null;

      // Try to find thermal printer by name
      final thermalPrinter = printers.firstWhere(
        (p) =>
            p.name.toLowerCase().contains('thermal') ||
            p.name.toLowerCase().contains('pos') ||
            p.name.toLowerCase().contains('receipt'),
        orElse: () => printers.first,
      );

      return thermalPrinter;
    } on MissingPluginException catch (e) {
      // Plugin not available on this platform (mobile)
      print('Printing plugin not available on this platform: $e');
      return null;
    } catch (e) {
      print('Error getting default printer: $e');
      return null;
    }
  }

  // --- 2. GENERATE THERMAL PDF DOCUMENT (Returns pw.Document) ---
  Future<pw.Document> _generateThermalStylePdfDoc({
    required String eventName,
    required String ticketType,
    required double price,
    required int numberOfTickets,
    required List<String> ticketCodes,
    required String transactionId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? venue,
    List<int>? ticketIds,
    List<int>? matchIds,
    List<int>? ticketTypeIds,
    List<int>? ticketNumbers,
    List<int>? ticketTotals,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final logoImage = await _loadLogo();

    // Thermal receipt width (58mm) with proper margins
    const receiptWidth = 58.0 * PdfPageFormat.mm;
    const margin = 2.0 * PdfPageFormat.mm;

    for (int i = 0; i < numberOfTickets; i++) {
      final code = ticketCodes[i];
      final displayTicketNumber =
          ticketNumbers != null && i < ticketNumbers.length
          ? ticketNumbers[i]
          : i + 1;
      final displayTicketTotal = ticketTotals != null && i < ticketTotals.length
          ? ticketTotals[i]
          : numberOfTickets;
      final validationUrl =
          '${kBaseUrl.replaceAll('/api', '')}/ticket/validate/$code';
      final ticketIdStr = ticketIds != null && i < ticketIds.length
          ? ticketIds[i].toString()
          : '-';
      final matchIdStr = matchIds != null && i < matchIds.length
          ? matchIds[i].toString()
          : '-';
      final ticketTypeIdStr = ticketTypeIds != null && i < ticketTypeIds.length
          ? ticketTypeIds[i].toString()
          : '-';

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            receiptWidth,
            double.infinity,
            marginLeft: margin,
            marginRight: margin,
            marginTop: margin,
            marginBottom: margin,
          ),
          build: (context) {
            return pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Border container
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1.5),
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      // Top dashed line
                      _buildDashedLine(),
                      pw.SizedBox(height: 6),

                      // Ticket ID (top-right) - show ticket code/reference
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          'ID: ${code.substring(0, code.length > 8 ? 8 : code.length).toUpperCase()}',
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.SizedBox(height: 2),

                      // Logo (if available)
                      if (logoImage != null) ...[
                        pw.Image(
                          logoImage,
                          width: 50,
                          height: 50,
                          fit: pw.BoxFit.contain,
                        ),
                        pw.SizedBox(height: 6),
                      ],

                      // Event Name
                      pw.Text(
                        eventName.toUpperCase(),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),

                      // Ticket Type Badge
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColors.black,
                            width: 1,
                          ),
                          borderRadius: pw.BorderRadius.circular(2),
                        ),
                        child: pw.Text(
                          ticketType.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 6),

                      // Divider
                      pw.Container(height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 5),

                      // Date & Time
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text(
                            dateStr,
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            ' • ',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          pw.Text(
                            timeStr,
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 3),

                      // Venue
                      pw.Text(
                        venue ?? 'Jos New Stadium',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 6),

                      // Price & Ticket Number
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'PRICE',
                                style: const pw.TextStyle(
                                  fontSize: 6,
                                  color: PdfColors.grey600,
                                ),
                              ),
                              pw.Text(
                                '₦${price.toStringAsFixed(0)}',
                                style: pw.TextStyle(
                                  fontSize: 14,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(
                                color: PdfColors.black,
                                width: 1,
                              ),
                              borderRadius: pw.BorderRadius.circular(2),
                            ),
                            child: pw.Column(
                              children: [
                                pw.Text(
                                  'TICKET',
                                  style: pw.TextStyle(
                                    fontSize: 5,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.Text(
                                  '#$displayTicketNumber/$displayTicketTotal',
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // pw.SizedBox(height: 6),

                      // Customer Info
                      // pw.Container(
                      //   width: double.infinity,
                      //   padding: const pw.EdgeInsets.all(5),
                      //   decoration: pw.BoxDecoration(
                      //     border: pw.Border.all(
                      //       color: PdfColors.black,
                      //       width: 0.8,
                      //     ),
                      //     borderRadius: pw.BorderRadius.circular(2),
                      //   ),
                      //   child: pw.Column(
                      //     crossAxisAlignment: pw.CrossAxisAlignment.start,
                      //     children: [
                      //       pw.Text(
                      //         'TICKET HOLDER',
                      //         style: pw.TextStyle(
                      //           fontSize: 6,
                      //           fontWeight: pw.FontWeight.bold,
                      //           color: PdfColors.grey600,
                      //         ),
                      //       ),
                      //       pw.Text(
                      //         (customerName ?? 'GUEST').toUpperCase(),
                      //         style: pw.TextStyle(
                      //           fontSize: 8,
                      //           fontWeight: pw.FontWeight.bold,
                      //         ),
                      //       ),
                      //       if (customerPhone != null &&
                      //           customerPhone.isNotEmpty)
                      //         pw.Text(
                      //           customerPhone,
                      //           style: const pw.TextStyle(fontSize: 7),
                      //         ),
                      //     ],
                      //   ),
                      // ),
                      // pw.SizedBox(height: 6),

                      // Perforation line
                      _buildDashedLine(),
                      pw.SizedBox(height: 6),

                      // QR Code
                      pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColors.black,
                            width: 1.5,
                          ),
                        ),
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: validationUrl,
                          width: 100,
                          height: 100,
                          drawText: false,
                        ),
                      ),
                      pw.SizedBox(height: 4),

                      pw.Text(
                        'SCAN TO ENTER',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      // pw.SizedBox(height: 3),
                      // Ticket IDs: matchId-ticketTypeId-ticketId
                      // pw.Text(
                      //   '$matchIdStr-$ticketTypeIdStr-$ticketIdStr',
                      //   style: pw.TextStyle(
                      //     fontSize: 6,
                      //     fontWeight: pw.FontWeight.bold,
                      //   ),
                      // ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        code.length > 8
                            ? code.substring(code.length - 8).toUpperCase()
                            : code.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 5),

                      // Bottom dashed line
                      _buildDashedLine(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    return doc;
  }

  // Helper: Build dashed line
  pw.Widget _buildDashedLine() {
    return pw.Row(
      children: List.generate(
        15,
        (index) => pw.Expanded(
          child: pw.Container(
            height: 1,
            color: index % 2 == 0 ? PdfColors.black : PdfColors.white,
          ),
        ),
      ),
    );
  }

  // --- 3. LOAD LOGO ---
  Future<pw.ImageProvider?> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/images/Plateau_United.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      print('Could not load logo: $e');
      return null;
    }
  }

  // --- 4. PRINT MULTIPLE TICKETS ---
  Future<bool> printMultipleTickets({
    required String eventName,
    required String ticketType,
    required double price,
    required int numberOfTickets,
    required List<String> ticketCodes,
    required String transactionId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? deviceAddress,
    void Function(String pdfPath)? onSavedPdf,
    int connectTimeoutMs = 1200,
    String? venue,
    List<int>? ticketIds,
    List<int>? matchIds,
    List<int>? ticketTypeIds,
    List<int>? ticketNumbers,
    List<int>? ticketTotals,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preferredPath = prefs.getString('kPreferredPrintPath') ?? 'system';

      // 1. System Print (Direct) - Only on desktop platforms
      if (preferredPath == 'system') {
        // System print only works on desktop - skip on mobile
        if (Platform.isAndroid || Platform.isIOS) {
          print(
            'System print not available on mobile, falling back to WiFi/Bluetooth',
          );
        } else {
          try {
            final pdf = await _generateThermalStylePdfDoc(
              eventName: eventName,
              ticketType: ticketType,
              price: price,
              numberOfTickets: numberOfTickets,
              ticketCodes: ticketCodes,
              transactionId: transactionId,
              customerName: customerName,
              customerEmail: customerEmail,
              customerPhone: customerPhone,
              venue: venue,
              ticketIds: ticketIds,
              matchIds: matchIds,
              ticketTypeIds: ticketTypeIds,
              ticketNumbers: ticketNumbers,
              ticketTotals: ticketTotals,
            );

            final printer = await _getDefaultPrinter();
            if (printer != null) {
              final success = await Printing.directPrintPdf(
                printer: printer,
                onLayout: (format) => pdf.save(),
              );
              if (success) return true;
            }
          } catch (e) {
            print('System print failed: $e');
          }
        }
      }

      // 2. Wi-Fi Printer (primary on mobile, or when selected)
      if (preferredPath == 'wifi' ||
          (preferredPath == 'system' &&
              (Platform.isAndroid || Platform.isIOS))) {
        try {
          final wifiIp =
              prefs.getString('kPreferredWifiPrinterIp') ?? '192.168.1.88';
          if (wifiIp.isNotEmpty) {
            final net = NetworkPrintService();
            final ok = await net.printMultipleTickets(
              ip: wifiIp,
              eventName: eventName,
              ticketType: ticketType,
              price: price,
              numberOfTickets: numberOfTickets,
              ticketCodes: ticketCodes,
              transactionId: transactionId,
              customerName: customerName,
              customerEmail: customerEmail,
              customerPhone: customerPhone,
              venue: venue,
              ticketIds: ticketIds,
              matchIds: matchIds,
              ticketTypeIds: ticketTypeIds,
              ticketNumbers: ticketNumbers,
              ticketTotals: ticketTotals,
            );
            if (ok) return true;
          }
        } catch (e) {
          print('WiFi print failed: $e');
        }
      }

      // 3. Bluetooth Printer (fallback on mobile, or when selected)
      if (preferredPath == 'bluetooth' ||
          (preferredPath == 'system' &&
              (Platform.isAndroid || Platform.isIOS))) {
        if (await _requestBluetoothPermissions()) {
          if (await _connectToPrinter(deviceAddress: deviceAddress)) {
            for (int i = 0; i < numberOfTickets; i++) {
              final displayTicketNumber =
                  ticketNumbers != null && i < ticketNumbers.length
                  ? ticketNumbers[i]
                  : i + 1;
              final displayTicketTotal =
                  ticketTotals != null && i < ticketTotals.length
                  ? ticketTotals[i]
                  : numberOfTickets;
              final success = await printTicket(
                eventName: eventName,
                ticketType: ticketType,
                price: price,
                ticketNumber: displayTicketNumber,
                totalTickets: displayTicketTotal,
                ticketCode: ticketCodes[i],
                validationUrl:
                    '${kBaseUrl.replaceAll('/api', '')}/validate/${ticketCodes[i]}',
                transactionId: transactionId,
                customerName: customerName,
                customerEmail: customerEmail,
                customerPhone: customerPhone,
                venue: venue,
                ticketId: ticketIds != null && i < ticketIds.length
                    ? ticketIds[i]
                    : null,
                matchId: matchIds != null && i < matchIds.length
                    ? matchIds[i]
                    : null,
                ticketTypeId: ticketTypeIds != null && i < ticketTypeIds.length
                    ? ticketTypeIds[i]
                    : null,
              );
              if (!success) return false;
              if (i < numberOfTickets - 1) {
                final delayMs = await _settingsService.getPrinterDelayMs();
                await Future.delayed(Duration(milliseconds: delayMs));
              }
            }
            return true;
          }
        }
      }

      // 4. Fallback: Save PDF
      print('All print methods failed - saving to PDF as fallback');
      final pdfPath = await _savePdfToFile(
        eventName: eventName,
        ticketType: ticketType,
        price: price,
        numberOfTickets: numberOfTickets,
        ticketCodes: ticketCodes,
        transactionId: transactionId,
        customerName: customerName,
        customerEmail: customerEmail,
        customerPhone: customerPhone,
        venue: venue,
        ticketIds: ticketIds,
        matchIds: matchIds,
        ticketTypeIds: ticketTypeIds,
        ticketNumbers: ticketNumbers,
        ticketTotals: ticketTotals,
      );
      if (onSavedPdf != null) onSavedPdf(pdfPath);
      return true;
    } catch (e) {
      print('Error in printMultipleTickets: $e');
      return false;
    }
  }

  // Save PDF to file in Downloads folder (publicly accessible)
  Future<String> _savePdfToFile({
    required String eventName,
    required String ticketType,
    required double price,
    required int numberOfTickets,
    required List<String> ticketCodes,
    required String transactionId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? venue,
    List<int>? ticketIds,
    List<int>? matchIds,
    List<int>? ticketTypeIds,
    List<int>? ticketNumbers,
    List<int>? ticketTotals,
  }) async {
    try {
      // Request storage permission
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        print('Storage permission denied');
        // Fallback to app directory if permission denied
        final dir = await getApplicationDocumentsDirectory();
        return await _savePdfToAppDirectory(
          dir: dir,
          eventName: eventName,
          ticketType: ticketType,
          price: price,
          numberOfTickets: numberOfTickets,
          ticketCodes: ticketCodes,
          transactionId: transactionId,
          customerName: customerName,
          customerEmail: customerEmail,
          customerPhone: customerPhone,
          venue: venue,
          ticketIds: ticketIds,
          matchIds: matchIds,
          ticketTypeIds: ticketTypeIds,
          ticketNumbers: ticketNumbers,
          ticketTotals: ticketTotals,
        );
      }

      final pdf = await _generateThermalStylePdfDoc(
        eventName: eventName,
        ticketType: ticketType,
        price: price,
        numberOfTickets: numberOfTickets,
        ticketCodes: ticketCodes,
        transactionId: transactionId,
        customerName: customerName,
        customerEmail: customerEmail,
        customerPhone: customerPhone,
        venue: venue,
        ticketIds: ticketIds,
        matchIds: matchIds,
        ticketTypeIds: ticketTypeIds,
        ticketNumbers: ticketNumbers,
        ticketTotals: ticketTotals,
      );

      final bytes = await pdf.save();

      // Save to Downloads folder (publicly accessible)
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else {
        downloadsDir = await getDownloadsDirectory();
      }

      if (downloadsDir == null || !await downloadsDir.exists()) {
        print('Downloads directory not found, using app directory');
        final dir = await getApplicationDocumentsDirectory();
        return await _savePdfToAppDirectory(
          dir: dir,
          eventName: eventName,
          ticketType: ticketType,
          price: price,
          numberOfTickets: numberOfTickets,
          ticketCodes: ticketCodes,
          transactionId: transactionId,
          customerName: customerName,
          customerEmail: customerEmail,
          customerPhone: customerPhone,
          venue: venue,
          ticketIds: ticketIds,
          matchIds: matchIds,
          ticketTypeIds: ticketTypeIds,
          ticketNumbers: ticketNumbers,
          ticketTotals: ticketTotals,
        );
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName =
          'Ticket_${eventName.replaceAll(' ', '_')}_$timestamp.pdf';
      final file = File('${downloadsDir.path}/$fileName');

      await file.writeAsBytes(bytes, flush: true);
      print('PDF saved to: ${file.path}');

      return file.path;
    } catch (e) {
      print('Error saving PDF: $e');
      // Fallback to app directory on error
      final dir = await getApplicationDocumentsDirectory();
      return await _savePdfToAppDirectory(
        dir: dir,
        eventName: eventName,
        ticketType: ticketType,
        price: price,
        numberOfTickets: numberOfTickets,
        ticketCodes: ticketCodes,
        transactionId: transactionId,
        customerName: customerName,
        customerEmail: customerEmail,
        customerPhone: customerPhone,
        venue: venue,
        ticketIds: ticketIds,
        matchIds: matchIds,
        ticketTypeIds: ticketTypeIds,
        ticketNumbers: ticketNumbers,
        ticketTotals: ticketTotals,
      );
    }
  }

  // Helper: Save to app directory (fallback)
  Future<String> _savePdfToAppDirectory({
    required Directory dir,
    required String eventName,
    required String ticketType,
    required double price,
    required int numberOfTickets,
    required List<String> ticketCodes,
    required String transactionId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    String? venue,
    List<int>? ticketIds,
    List<int>? matchIds,
    List<int>? ticketTypeIds,
    List<int>? ticketNumbers,
    List<int>? ticketTotals,
  }) async {
    final pdf = await _generateThermalStylePdfDoc(
      eventName: eventName,
      ticketType: ticketType,
      price: price,
      numberOfTickets: numberOfTickets,
      ticketCodes: ticketCodes,
      transactionId: transactionId,
      customerName: customerName,
      customerEmail: customerEmail,
      customerPhone: customerPhone,
      venue: venue,
      ticketIds: ticketIds,
      matchIds: matchIds,
      ticketTypeIds: ticketTypeIds,
      ticketNumbers: ticketNumbers,
      ticketTotals: ticketTotals,
    );

    final bytes = await pdf.save();
    final file = File(
      '${dir.path}/thermal_ticket_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    print('PDF saved to app directory: ${file.path}');
    return file.path;
  }

  // --- BLUETOOTH HELPERS ---
  Future<bool> _requestBluetoothPermissions() async {
    try {
      final result = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      return (result[Permission.bluetoothScan]?.isGranted ?? true) &&
          (result[Permission.bluetoothConnect]?.isGranted ?? true);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _connectToPrinter({String? deviceAddress}) async {
    try {
      List<BluetoothDevice> devices = await _printer.getBondedDevices();
      if (devices.isEmpty) return false;

      BluetoothDevice target = (deviceAddress != null)
          ? devices.firstWhere(
              (d) => (d.address ?? '') == deviceAddress,
              orElse: () => devices.first,
            )
          : devices.first;

      await _printer.connect(target);
      await Future.delayed(const Duration(milliseconds: 400));
      return await _printer.isConnected == true;
    } catch (e) {
      print('Error connecting to printer: $e');
      return false;
    }
  }

  Future<List<BluetoothDevice>> getPairedPrinters() async =>
      await _printer.getBondedDevices();

  Future<bool> isConnected() async => await _printer.isConnected == true;

  Future<void> disconnect() async => await _printer.disconnect();

  /// Connect to a specific Bluetooth printer device
  Future<bool> connectToSpecificPrinter(BluetoothDevice device) async {
    try {
      await _printer.connect(device);
      await Future.delayed(const Duration(milliseconds: 400));
      return await _printer.isConnected == true;
    } catch (e) {
      print('Error connecting to specific printer: $e');
      return false;
    }
  }
}
