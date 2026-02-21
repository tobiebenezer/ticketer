import 'dart:io';
import 'dart:ui' as ui;
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:esc_pos_utils_lts/esc_pos_utils_lts.dart';
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
  String? _lastBluetoothError;

  static const String _kBluetoothPrintMode = 'kBluetoothPrintMode';
  static const String _kBluetoothPaperWidthMm = 'kBluetoothPaperWidthMm';

  String? get lastBluetoothError => _lastBluetoothError;

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

  /// Public accessor for the preferred print path (wifi / bluetooth / system).
  Future<String> getPreferredPrintPath() => _getPreferredPrintPath();

  /// Inter-ticket delay in ms for the queue processor.
  /// Uses the same configurable value as the batch printer (default 500ms).
  Future<int> getInterTicketDelayMs() => _settingsService.getPrinterDelayMs();

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
      final preferredBtAddress =
          deviceAddress ?? prefs.getString('kPreferredBtAddress');

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

      // 3. Bluetooth Printer (selected path, or fallback from Wi-Fi on mobile
      // when a preferred BT printer is configured)
      // Connect ONCE and print all tickets in a single session to avoid
      // per-ticket reconnect overhead which causes significant lag.
      if (preferredPath == 'bluetooth' ||
          (preferredPath == 'wifi' &&
              (Platform.isAndroid || Platform.isIOS) &&
              preferredBtAddress != null &&
              preferredBtAddress.isNotEmpty) ||
          (preferredPath == 'system' &&
              (Platform.isAndroid || Platform.isIOS))) {
        if (await _requestBluetoothPermissions()) {
          if (await _connectToPrinter(deviceAddress: preferredBtAddress)) {
            final delayMs = await _settingsService.getPrinterDelayMs();
            for (int i = 0; i < numberOfTickets; i++) {
              final displayTicketNumber =
                  ticketNumbers != null && i < ticketNumbers.length
                  ? ticketNumbers[i]
                  : i + 1;
              final displayTicketTotal =
                  ticketTotals != null && i < ticketTotals.length
                  ? ticketTotals[i]
                  : numberOfTickets;
              final success = await _printTicketViaBluetooth(
                eventName: eventName,
                ticketType: ticketType,
                price: price,
                ticketNumber: displayTicketNumber,
                totalTickets: displayTicketTotal,
                ticketCode: ticketCodes[i],
                validationUrl:
                    '${kBaseUrl.replaceAll('/api', '')}/validate/${ticketCodes[i]}',
                ticketId: ticketIds != null && i < ticketIds.length
                    ? ticketIds[i]
                    : null,
                customerName: customerName,
                venue: venue,
              );
              if (!success) return false;
              if (i < numberOfTickets - 1) {
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

  Future<bool> _printTicketViaBluetooth({
    required String eventName,
    required String ticketType,
    required double price,
    required int ticketNumber,
    required int totalTickets,
    required String ticketCode,
    required String validationUrl,
    int? ticketId,
    String? customerName,
    String? venue,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final btMode = prefs.getString(_kBluetoothPrintMode) ?? 'image';
    final paperWidthMm = await _getBluetoothPaperWidthMm();
    final paperWidthPx = paperWidthMm == 80 ? 576.0 : 384.0;

    Future<bool> printTextFallback() async {
      try {
        await _printer.printNewLine();
        await _printer.printCustom(eventName.toUpperCase(), 2, 1);
        await _printer.printCustom(ticketType.toUpperCase(), 1, 1);
        await _printer.printCustom('NGN ${price.toStringAsFixed(0)}', 2, 1);
        await _printer.printCustom('Ticket $ticketNumber/$totalTickets', 1, 1);
        if (customerName != null && customerName.trim().isNotEmpty) {
          await _printer.printCustom(
            'Customer: ${customerName.trim().toUpperCase()}',
            0,
            0,
          );
        }
        if (venue != null && venue.isNotEmpty) {
          await _printer.printCustom(venue, 0, 1);
        }
        await _printer.printNewLine();
        await _printer.printCustom('Code: ${ticketCode.toUpperCase()}', 1, 0);
        await _printer.printQRcode(validationUrl, 220, 220, 1);
        await _printer.printNewLine();
        try {
          await _printer.paperCut();
        } catch (_) {}
        return true;
      } catch (e) {
        print('Bluetooth plain-text fallback failed: $e');
        return false;
      }
    }

    if (btMode == 'text_only') {
      return await printTextFallback();
    }

    try {
      // Render the same ticket image used by the WiFi/PDF path so all three
      // print methods produce an identical design.
      final netService = NetworkPrintService();
      final logoBytes = await netService.loadLogoBytes();
      final logoImage = logoBytes != null ? img.decodeImage(logoBytes) : null;

      final imageBytes = await netService.generateTicketImage(
        eventName: eventName,
        ticketType: ticketType,
        price: price,
        ticketNumber: ticketNumber,
        totalTickets: totalTickets,
        validationUrl: validationUrl,
        transactionId: ticketCode,
        customerName: customerName,
        ticketId: ticketId,
        paperWidthPx: paperWidthPx,
        logoImage: logoImage,
        venue: venue,
      );

      if (imageBytes == null) {
        return await printTextFallback();
      }

      try {
        final decoded = img.decodeImage(imageBytes);
        if (decoded == null) {
          return await printTextFallback();
        }

        final printed = await _printImageViaBluetoothEscPos(
          decoded,
          paperWidthMm: paperWidthMm,
        );
        if (!printed) {
          return await printTextFallback();
        }
        return true;
      } catch (e) {
        print('Bluetooth image print failed, trying text fallback: $e');
        return await printTextFallback();
      }
    } catch (e) {
      print('Bluetooth print failed: $e');
      return await printTextFallback();
    }
  }

  Future<bool> _printImageViaBluetoothEscPos(
    img.Image source, {
    required int paperWidthMm,
  }) async {
    try {
      final profile = await CapabilityProfile.load();
      final paperSize = paperWidthMm == 80 ? PaperSize.mm80 : PaperSize.mm58;
      final targetWidth = paperWidthMm == 80 ? 576 : 384;
      final generator = Generator(paperSize, profile);

      final prepared = _prepareBluetoothImage(source, targetWidth: targetWidth);
      final slices = _splitImageByHeight(prepared, maxHeight: 192);

      final didReset = await _sendEscPosChunked(
        generator.reset(),
        chunkSize: 256,
        interChunkDelayMs: 20,
      );
      if (!didReset) return false;

      for (final slice in slices) {
        final bytes = generator.imageRaster(
          slice,
          align: PosAlign.center,
          imageFn: PosImageFn.bitImageRaster,
          highDensityHorizontal: true,
          highDensityVertical: true,
        );

        final ok = await _sendEscPosChunked(
          bytes,
          chunkSize: 256,
          interChunkDelayMs: 25,
        );
        if (!ok) return false;

        await Future.delayed(const Duration(milliseconds: 120));
      }

      final fed = await _sendEscPosChunked(
        generator.feed(3),
        chunkSize: 128,
        interChunkDelayMs: 10,
      );
      if (!fed) return false;

      await Future.delayed(const Duration(milliseconds: 250));

      final cut = await _sendEscPosChunked(
        [0x1D, 0x56, 0x00],
        chunkSize: 128,
        interChunkDelayMs: 10,
      );
      return cut;
    } catch (e) {
      print('ESC/POS bluetooth image print failed: $e');
      return false;
    }
  }

  img.Image _prepareBluetoothImage(
    img.Image source, {
    required int targetWidth,
  }) {
    final base = img.Image(width: source.width, height: source.height);
    img.fill(base, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(base, source, dstX: 0, dstY: 0);

    img.Image resized = base;
    if (base.width > targetWidth) {
      final ratio = targetWidth / base.width;
      final targetHeight = (base.height * ratio).round();
      resized = img.copyResize(
        base,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.average,
      );
    }

    final paddedWidth = ((resized.width + 7) ~/ 8) * 8;
    if (paddedWidth == resized.width) {
      return resized;
    }

    final padded = img.Image(width: paddedWidth, height: resized.height);
    img.fill(padded, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(padded, resized, dstX: 0, dstY: 0);
    return padded;
  }

  List<img.Image> _splitImageByHeight(
    img.Image image, {
    required int maxHeight,
  }) {
    if (image.height <= maxHeight) {
      return [image];
    }

    final slices = <img.Image>[];
    int y = 0;
    while (y < image.height) {
      final remaining = image.height - y;
      final h = remaining > maxHeight ? maxHeight : remaining;
      slices.add(
        img.copyCrop(image, x: 0, y: y, width: image.width, height: h),
      );
      y += h;
    }
    return slices;
  }

  Future<bool> _sendEscPosChunked(
    List<int> bytes, {
    required int chunkSize,
    required int interChunkDelayMs,
  }) async {
    try {
      if (bytes.isEmpty) return true;

      int offset = 0;
      while (offset < bytes.length) {
        final end = (offset + chunkSize < bytes.length)
            ? offset + chunkSize
            : bytes.length;
        final chunk = Uint8List.fromList(bytes.sublist(offset, end));
        await _printer.writeBytes(chunk);
        offset = end;

        if (offset < bytes.length && interChunkDelayMs > 0) {
          await Future.delayed(Duration(milliseconds: interChunkDelayMs));
        }
      }

      return true;
    } catch (e) {
      print('Chunked ESC/POS write failed: $e');
      return false;
    }
  }

  Future<int> _getBluetoothPaperWidthMm() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configured = prefs.getInt(_kBluetoothPaperWidthMm);
      if (configured == 52 || configured == 80) {
        return configured!;
      }

      // Default to 52mm for bigger Bluetooth receipts.
      return 52;
    } catch (_) {
      return 52;
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
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final scanGranted = result[Permission.bluetoothScan]?.isGranted ?? true;
      final connectGranted =
          result[Permission.bluetoothConnect]?.isGranted ?? true;
      final legacyBluetoothGranted =
          result[Permission.bluetooth]?.isGranted ?? true;
      final locationGranted =
          result[Permission.locationWhenInUse]?.isGranted ?? true;

      if (!scanGranted || !connectGranted || !legacyBluetoothGranted) {
        final missing = <String>[];
        if (!scanGranted) missing.add('BLUETOOTH_SCAN');
        if (!connectGranted) missing.add('BLUETOOTH_CONNECT');
        if (!legacyBluetoothGranted) missing.add('BLUETOOTH');
        _lastBluetoothError =
            'Bluetooth permissions missing: ${missing.join(', ')}';
        return false;
      }

      // Some devices still require location permission for bonded device queries.
      if (!locationGranted) {
        _lastBluetoothError =
            'Location permission missing (required on some Android devices)';
      } else {
        _lastBluetoothError = null;
      }

      return true;
    } catch (_) {
      _lastBluetoothError = 'Failed to request Bluetooth permissions';
      return false;
    }
  }

  Future<bool> _connectToPrinter({String? deviceAddress}) async {
    try {
      if (deviceAddress == null || deviceAddress.isEmpty) {
        _lastBluetoothError =
            'No Bluetooth printer selected. Please select a printer in Settings.';
        return false;
      }

      List<BluetoothDevice> devices = await _printer.getBondedDevices();
      if (devices.isEmpty) {
        _lastBluetoothError =
            'No bonded Bluetooth printers found. Pair printer in Android Bluetooth settings first.';
        return false;
      }

      final matches = devices.where((d) => (d.address ?? '') == deviceAddress);
      if (matches.isEmpty) {
        _lastBluetoothError =
            'Selected printer ($deviceAddress) is not bonded or not available.';
        print('Selected Bluetooth printer not found: $deviceAddress');
        return false;
      }
      final target = matches.first;

      // If already connected, check if it's the same device — reuse if so.
      // This avoids the expensive disconnect/reconnect cycle between tickets.
      final alreadyConnected = await _printer.isConnected == true;
      if (alreadyConnected) {
        final sameDevice = await _printer.isDeviceConnected(target) == true;
        if (sameDevice) {
          _lastBluetoothError = null;
          return true;
        }
        // Different device connected — disconnect first
        try {
          await _printer.disconnect();
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (_) {}
      }

      await _printer.connect(target);
      // Give the printer time to establish the SPP channel
      await Future.delayed(const Duration(milliseconds: 900));
      final connected = await _printer.isConnected == true;
      if (!connected) {
        _lastBluetoothError =
            'Could not connect to printer ${target.name ?? ''} (${target.address ?? ''})';
      } else {
        _lastBluetoothError = null;
      }
      return connected;
    } catch (e) {
      if (e.toString().toLowerCase().contains('already connected')) {
        final connected = await _printer.isConnected == true;
        if (connected) {
          _lastBluetoothError = null;
        }
        return connected;
      }
      _lastBluetoothError = 'Bluetooth connect error: $e';
      print('Error connecting to printer: $e');
      return false;
    }
  }

  Future<List<BluetoothDevice>> getPairedPrinters() async =>
      await _printer.getBondedDevices();

  Future<bool> isConnected() async => await _printer.isConnected == true;

  Future<void> disconnect() async => await _printer.disconnect();

  /// Ensure BT is connected to the saved/preferred printer.
  /// Returns true if connected (or already connected). Safe to call repeatedly —
  /// it will reuse an existing connection rather than reconnecting.
  Future<bool> ensureBluetoothConnected() async {
    if (!await _requestBluetoothPermissions()) return false;
    final prefs = await SharedPreferences.getInstance();
    final preferredBtAddress = prefs.getString('kPreferredBtAddress');
    return _connectToPrinter(deviceAddress: preferredBtAddress);
  }

  Future<PrintDispatchResult> testBluetoothPrinter({
    String? deviceAddress,
  }) async {
    final okPermissions = await _requestBluetoothPermissions();
    if (!okPermissions) {
      return PrintDispatchResult(
        status: PrintDispatchStatus.failed,
        mode: 'bluetooth',
        error: _lastBluetoothError ?? 'Bluetooth permission denied',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final selected = deviceAddress ?? prefs.getString('kPreferredBtAddress');
    final connected = await _connectToPrinter(deviceAddress: selected);
    if (!connected) {
      return PrintDispatchResult(
        status: PrintDispatchStatus.failed,
        mode: 'bluetooth',
        error: _lastBluetoothError ?? 'Unable to connect to Bluetooth printer',
      );
    }

    try {
      await _printer.printCustom('BLUETOOTH TEST OK', 1, 1);
      await _printer.printCustom(DateTime.now().toString(), 0, 1);
      await _printer.printNewLine();
      return const PrintDispatchResult(
        status: PrintDispatchStatus.sent,
        mode: 'bluetooth',
      );
    } catch (e) {
      _lastBluetoothError = 'Connected but test print failed: $e';
      return PrintDispatchResult(
        status: PrintDispatchStatus.failed,
        mode: 'bluetooth',
        error: _lastBluetoothError,
      );
    }
  }

  /// Print a single ticket via Bluetooth WITHOUT reconnecting.
  /// Caller must call [ensureBluetoothConnected] first.
  Future<PrintDispatchResult> printSingleTicketBluetooth({
    required String eventName,
    required String ticketType,
    required double price,
    required int ticketNumber,
    required int totalTickets,
    required String ticketCode,
    required String validationUrl,
    int? ticketId,
    String? customerName,
    String? venue,
  }) async {
    final success = await _printTicketViaBluetooth(
      eventName: eventName,
      ticketType: ticketType,
      price: price,
      ticketNumber: ticketNumber,
      totalTickets: totalTickets,
      ticketCode: ticketCode,
      validationUrl: validationUrl,
      ticketId: ticketId,
      customerName: customerName,
      venue: venue,
    );
    return PrintDispatchResult(
      status: success ? PrintDispatchStatus.sent : PrintDispatchStatus.failed,
      mode: 'bluetooth',
      error: success ? null : 'Bluetooth print command failed',
    );
  }

  /// Connect to a specific Bluetooth printer device
  Future<bool> connectToSpecificPrinter(BluetoothDevice device) async {
    try {
      final alreadyConnected = await _printer.isConnected == true;
      if (alreadyConnected) {
        final sameDevice = await _printer.isDeviceConnected(device) == true;
        if (sameDevice) return true;
        try {
          await _printer.disconnect();
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (_) {}
      }

      await _printer.connect(device);
      await Future.delayed(const Duration(milliseconds: 300));
      return await _printer.isConnected == true;
    } catch (e) {
      if (e.toString().toLowerCase().contains('already connected')) {
        return await _printer.isConnected == true;
      }
      print('Error connecting to specific printer: $e');
      return false;
    }
  }
}
