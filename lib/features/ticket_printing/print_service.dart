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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/features/ticket_printing/network_print_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

class PrintService {
  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;

  // Thermal printer paper width in pixels (58mm ≈ 384px)
  static const double kPaperWidthPx = 384.0;

  // --- 1. PRINT SINGLE TICKET (Bluetooth) ---
  Future<bool> printTicket({
    required String eventName,
    required String ticketType,
    required double price,
    required int ticketNumber,
    required int totalTickets,
    required String ticketCode,
    required String validationUrl,
    required String transactionId,
    required String customerName,
    String? customerEmail,
    String? customerPhone,
    String? venue,
  }) async {
    try {
      bool? isConnected = await _printer.isConnected;
      if (isConnected != true) {
        final connected = await _connectToPrinter();
        if (!connected) throw Exception('Failed to connect to printer');
      }

      // Load Logo Bytes to pass into the Widget
      final logoBytes = await _loadLogoBytes();

      // Generate Image from Widget
      final ticketImageBytes = await _generateTicketImage(
        eventName: eventName,
        ticketType: ticketType,
        price: price,
        ticketNumber: ticketNumber,
        totalTickets: totalTickets,
        validationUrl: validationUrl,
        transactionId: transactionId,
        customerName: customerName,
        customerEmail: customerEmail,
        customerPhone: customerPhone,
        venue: venue,
        ticketCode: ticketCode,
        logoBytes: logoBytes,
      );

      if (ticketImageBytes != null) {
        await _printer.printImageBytes(ticketImageBytes);
        await _printer.printNewLine();
        await _printer.paperCut();
        return true;
      }
      return false;
    } catch (e) {
      print('Error printing ticket: $e');
      return false;
    }
  }

  // --- 2. GENERATE IMAGE HELPER (with logo compositing) ---
  Future<Uint8List?> _generateTicketImage({
    required String eventName,
    required String ticketType,
    required double price,
    required int ticketNumber,
    required int totalTickets,
    required String validationUrl,
    required String transactionId,
    required String customerName,
    String? customerEmail,
    String? customerPhone,
    String? venue,
    required String ticketCode,
    Uint8List? logoBytes,
  }) async {
    try {
      final ticketWidget = _buildTicketWidget(
        eventName: eventName,
        ticketType: ticketType,
        price: price,
        ticketNumber: ticketNumber,
        totalTickets: totalTickets,
        validationUrl: validationUrl,
        transactionId: transactionId,
        customerName: customerName,
        customerEmail: customerEmail,
        customerPhone: customerPhone,
        venue: venue,
        ticketCode: ticketCode,
      );

      final bytes = await _widgetToImage(ticketWidget);

      // Composite logo onto the ticket image if available
      if (bytes != null && logoBytes != null) {
        final logoImage = img.decodeImage(logoBytes);
        if (logoImage != null) {
          return _compositeLogoOnTicket(bytes, logoImage);
        }
      }

      return bytes;
    } catch (e) {
      print('Error generating ticket image: $e');
      return null;
    }
  }

  // --- 3. THERMAL WIDGET DESIGN (Space for logo at top - composited later) ---
  Widget _buildTicketWidget({
    required String eventName,
    required String ticketType,
    required double price,
    required int ticketNumber,
    required int totalTickets,
    required String validationUrl,
    required String transactionId,
    required String customerName,
    String? customerEmail,
    String? customerPhone,
    String? venue,
    required String ticketCode,
  }) {
    final now = DateTime.now();
    final dateStr = '${now.day}/${now.month}/${now.year}';
    final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    return Container(
      width: kPaperWidthPx,
      color: Colors.white,
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: 3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top dashed decoration
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: List.generate(
                  30,
                  (index) => Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: index % 2 == 0
                            ? Colors.black
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Main Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Space for logo (will be composited later)
                  const SizedBox(height: 100),

                  // EVENT NAME
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      eventName.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // TICKET TYPE
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      ticketType.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                  const Divider(color: Colors.black, height: 2, thickness: 2),
                  const SizedBox(height: 10),

                  // Date & Time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 5),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.access_time, size: 16),
                      const SizedBox(width: 5),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Venue
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_on, size: 16),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          venue ?? 'Jos New Stadium',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Price & Ticket Number
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PRICE',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                          Text(
                            '₦${price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'TICKET',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '#$ticketNumber/$totalTickets',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // TICKET HOLDER
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 1.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TICKET HOLDER',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          customerName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (customerPhone != null)
                          Text(
                            customerPhone,
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // STUB DIVIDER with notches (perforation line)
            Stack(
              alignment: Alignment.center,
              children: [
                // Dashed line
                Row(
                  children: List.generate(
                    25,
                    (index) => Expanded(
                      child: Container(
                        height: 4,
                        color: index % 2 == 0 ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                ),
                // Left notch (semicircle)
                Positioned(
                  left: 0,
                  child: Container(
                    width: 14,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(50),
                        bottomRight: Radius.circular(50),
                      ),
                    ),
                  ),
                ),
                // Right notch (semicircle)
                Positioned(
                  right: 0,
                  child: Container(
                    width: 14,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(50),
                        bottomLeft: Radius.circular(50),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // QR Code Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  // QR CODE - LARGER AND CENTERED
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 3),
                    ),
                    child: QrImageView(
                      data: validationUrl,
                      version: QrVersions.auto,
                      size: 160,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'SCAN TO ENTER',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    ticketCode,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Bottom dashed decoration
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: List.generate(
                  30,
                  (index) => Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: index % 2 == 0
                            ? Colors.black
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 4. PDF GENERATION (Green & Yellow) ---
  Future<String> _saveTicketsAsPdf({
    required String eventName,
    required String ticketType,
    required double price,
    required int numberOfTickets,
    required List<String> ticketCodes,
    required String transactionId,
    required String customerName,
    String? customerEmail,
    String? customerPhone,
    String? venue,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final dateStr = '${now.day}/${now.month}/${now.year}';
    final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    final logoImage = await _loadLogo();

    // Plateau United Colors
    final greenColor = PdfColor.fromHex('#006400');
    final whiteColor = PdfColors.white;

    for (int i = 0; i < numberOfTickets; i++) {
      final code = ticketCodes[i];
      final validationUrl = '${kBaseUrl.replaceAll('/api', '')}/validate/$code';

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(30),
          build: (context) {
            return pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: greenColor, width: 3),
                borderRadius: pw.BorderRadius.circular(12),
              ),
              padding: const pw.EdgeInsets.all(25),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // LEFT SECTION: Main Ticket Content
                  pw.Expanded(
                    flex: 6,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Header with Logo and Event Name
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            if (logoImage != null)
                              pw.Container(
                                padding: const pw.EdgeInsets.all(5),
                                child: pw.Image(
                                  logoImage,
                                  width: 70,
                                  height: 70,
                                ),
                              ),
                            pw.SizedBox(width: 20),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    'EVENT TICKET',
                                    style: pw.TextStyle(
                                      fontSize: 12,
                                      color: PdfColors.grey600,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                  pw.SizedBox(height: 4),
                                  pw.Text(
                                    eventName.toUpperCase(),
                                    style: pw.TextStyle(
                                      fontSize: 28,
                                      fontWeight: pw.FontWeight.bold,
                                      color: greenColor,
                                    ),
                                  ),
                                  pw.SizedBox(height: 8),
                                  pw.Text(
                                    venue ?? 'Jos New Stadium',
                                    style: const pw.TextStyle(
                                      fontSize: 14,
                                      color: PdfColors.grey700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        pw.Spacer(),

                        // Details Grid
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            // Date/Time
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'DATE & TIME',
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.grey600,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  '$dateStr  ·  $timeStr',
                                  style: pw.TextStyle(
                                    fontSize: 16,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            // Ticket Type
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: pw.BoxDecoration(
                                color: greenColor,
                                borderRadius: pw.BorderRadius.circular(6),
                              ),
                              child: pw.Text(
                                ticketType.toUpperCase(),
                                style: pw.TextStyle(
                                  color: whiteColor,
                                  fontSize: 16,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                            // Price
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Text(
                                  'PRICE',
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.grey600,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  'N${price.toStringAsFixed(0)}',
                                  style: pw.TextStyle(
                                    fontSize: 28,
                                    fontWeight: pw.FontWeight.bold,
                                    color: greenColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        pw.SizedBox(height: 20),
                        pw.Divider(color: PdfColors.grey300, thickness: 1),
                        pw.SizedBox(height: 15),

                        // Customer & Ticket Number
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'TICKET HOLDER',
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.grey600,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  customerName.toUpperCase(),
                                  style: pw.TextStyle(
                                    fontSize: 18,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                if (customerPhone != null)
                                  pw.Text(
                                    customerPhone,
                                    style: const pw.TextStyle(
                                      fontSize: 12,
                                      color: PdfColors.grey700,
                                    ),
                                  ),
                              ],
                            ),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Text(
                                  'TICKET NO',
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.grey600,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  '#${i + 1} of $numberOfTickets',
                                  style: pw.TextStyle(
                                    fontSize: 18,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        pw.Spacer(),

                        // Footer
                        pw.Text(
                          'Transaction: $transactionId',
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Vertical Divider
                  pw.Container(
                    width: 1,
                    margin: const pw.EdgeInsets.symmetric(horizontal: 25),
                    color: PdfColors.grey300,
                  ),

                  // RIGHT SECTION: QR Code
                  pw.SizedBox(
                    width: 180,
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          'SCAN TO',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.Text(
                          'ENTER',
                          style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: greenColor,
                          ),
                        ),
                        pw.SizedBox(height: 20),
                        // QR Code - clean, no background
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: validationUrl,
                          width: 140,
                          height: 140,
                          color: PdfColors.black,
                        ),
                        pw.SizedBox(height: 20),
                        pw.Text(
                          code,
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/plateau_tickets_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // --- 5. UTILS & HELPERS ---

  Future<Uint8List?> _widgetToImage(Widget widget) async {
    try {
      final repaintBoundary = RenderRepaintBoundary();
      final renderView = RenderView(
        view: WidgetsBinding.instance.platformDispatcher.views.first,
        child: RenderPositionedBox(
          alignment: Alignment.topCenter,
          child: repaintBoundary,
        ),
        configuration: const ViewConfiguration(
          logicalConstraints: BoxConstraints(
            maxWidth: kPaperWidthPx,
            maxHeight: 2000,
          ),
          devicePixelRatio: 1.0,
        ),
      );

      final pipelineOwner = PipelineOwner()..rootNode = renderView;
      renderView.prepareInitialFrame();

      final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
        container: repaintBoundary,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontFamily: 'Roboto',
              ),
              child: widget,
            ),
          ),
        ),
      ).attachToRenderTree(BuildOwner(focusManager: FocusManager()));

      rootElement.performRebuild();
      pipelineOwner.flushLayout();
      pipelineOwner.flushCompositingBits();
      pipelineOwner.flushPaint();

      final image = await repaintBoundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _loadLogoBytes() async {
    try {
      final data = await rootBundle.load('assets/images/Plateau_United.png');
      return data.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  /// Composite logo onto ticket image
  Uint8List? _compositeLogoOnTicket(
    Uint8List ticketBytes,
    img.Image logoImage,
  ) {
    try {
      final ticketImage = img.decodeImage(ticketBytes);
      if (ticketImage == null) {
        print('Failed to decode ticket image');
        return ticketBytes;
      }

      // Resize logo to fit - preserve aspect ratio, target ~100px height
      final targetHeight = 100;
      final aspectRatio = logoImage.width / logoImage.height;
      final targetWidth = (targetHeight * aspectRatio).round();
      final resizedLogo = img.copyResize(
        logoImage,
        width: targetWidth,
        height: targetHeight,
      );

      // Calculate center position for logo at the top
      final x = (ticketImage.width - resizedLogo.width) ~/ 2;
      final y = 12; // Top padding

      print(
        'Compositing logo at ($x, $y) - ticket: ${ticketImage.width}x${ticketImage.height}, logo: ${resizedLogo.width}x${resizedLogo.height}',
      );

      // Draw logo pixel by pixel onto ticket
      for (int ly = 0; ly < resizedLogo.height; ly++) {
        for (int lx = 0; lx < resizedLogo.width; lx++) {
          final pixel = resizedLogo.getPixel(lx, ly);
          final destX = x + lx;
          final destY = y + ly;
          if (destX >= 0 &&
              destX < ticketImage.width &&
              destY >= 0 &&
              destY < ticketImage.height) {
            ticketImage.setPixel(destX, destY, pixel);
          }
        }
      }

      final result = Uint8List.fromList(img.encodePng(ticketImage));
      print('Logo composited successfully, result: ${result.length} bytes');
      return result;
    } catch (e) {
      print('Error compositing logo: $e');
      return ticketBytes;
    }
  }

  Future<pw.ImageProvider?> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/images/Plateau_United.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      return null;
    }
  }

  // --- 6. BLUETOOTH / PRINT MULTIPLE LOGIC ---

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

  Future<bool> ensureConnected({
    String? deviceAddress,
    int timeoutMs = 1200,
  }) async {
    try {
      if (await _printer.isConnected == true) return true;
      if (await _connectToPrinter(deviceAddress: deviceAddress)) return true;
      return false;
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
      return false;
    }
  }

  Future<List<BluetoothDevice>> getPairedPrinters() async =>
      await _printer.getBondedDevices();

  Future<bool> connectToSpecificPrinter(BluetoothDevice device) async {
    try {
      await _printer.connect(device);
      await Future.delayed(const Duration(seconds: 2));
      bool? isConnected = await _printer.isConnected;
      return isConnected == true;
    } catch (e) {
      print('Error connecting to specific printer: $e');
      return false;
    }
  }

  Future<bool> isConnected() async => await _printer.isConnected == true;
  Future<void> disconnect() async => await _printer.disconnect();

  Future<bool> printMultipleTickets({
    required String eventName,
    required String ticketType,
    required double price,
    required int numberOfTickets,
    required List<String> ticketCodes,
    required String transactionId,
    required String customerName,
    String? customerEmail,
    String? customerPhone,
    String? deviceAddress,
    void Function(String pdfPath)? onSavedPdf,
    int connectTimeoutMs = 1200,
    String? venue,
  }) async {
    try {
      // 1. Wifi Check
      try {
        final prefs = await SharedPreferences.getInstance();
        if ((prefs.getString('kPreferredPrintPath') ?? 'wifi') == 'wifi') {
          final wifiIp = prefs.getString('kPreferredWifiPrinterIp');
          if (wifiIp != null && wifiIp.isNotEmpty) {
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
            );
            if (ok) return true;
          }
        }
      } catch (_) {}

      // 2. Bluetooth Check
      if (!await _requestBluetoothPermissions()) return false;

      if (!await ensureConnected(deviceAddress: deviceAddress)) {
        // 3. PDF Fallback
        final pdfPath = await _saveTicketsAsPdf(
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
        );
        if (onSavedPdf != null) onSavedPdf(pdfPath);
        return true;
      }

      // 4. Print Loop
      for (int i = 0; i < numberOfTickets; i++) {
        final success = await printTicket(
          eventName: eventName,
          ticketType: ticketType,
          price: price,
          ticketNumber: i + 1,
          totalTickets: numberOfTickets,
          ticketCode: ticketCodes[i],
          validationUrl:
              '${kBaseUrl.replaceAll('/api', '')}/validate/${ticketCodes[i]}',
          transactionId: transactionId,
          customerName: customerName,
          customerEmail: customerEmail,
          customerPhone: customerPhone,
          venue: venue,
        );
        if (!success) return false;
        if (i < numberOfTickets - 1)
          await Future.delayed(const Duration(milliseconds: 500));
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}
