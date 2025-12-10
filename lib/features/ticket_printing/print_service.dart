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

  // Thermal printer paper width in pixels (58mm ≈ 384px at 203 DPI)
  static const double kPaperWidthPx = 384.0;

  /// Print a single ticket using Widget-to-Image rendering
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
      // Check connection
      bool? isConnected = await _printer.isConnected;
      if (isConnected != true) {
        final connected = await _connectToPrinter();
        if (!connected) {
          throw Exception('Failed to connect to printer');
        }
      }

      // Pre-load logo
      final logoBytes = await _loadLogoBytes();
      print(
        'Logo loaded: ${logoBytes != null ? '${logoBytes.length} bytes' : 'null'}',
      );
      final logoImage = logoBytes != null ? img.decodeImage(logoBytes) : null;

      // Generate ticket widget and convert to image
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
        logoImage: logoImage,
        venue: venue,
      );

      if (ticketImageBytes != null) {
        // Print the complete ticket as a single image
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

  /// Generate ticket as image from Flutter widget
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
    img.Image? logoImage,
    String? venue,
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
      );

      // Convert widget to image
      final bytes = await _widgetToImage(ticketWidget);

      // Composite logo onto the ticket image if available
      if (bytes != null && logoImage != null) {
        return _compositeLogoOnTicket(bytes, logoImage);
      }

      return bytes;
    } catch (e) {
      print('Error generating ticket image: $e');
      return null;
    }
  }

  /// Build ticket widget with full control over layout
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
  }) {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final txnShort = transactionId.length > 12
        ? '...${transactionId.substring(transactionId.length - 12)}'
        : transactionId;

    return Container(
      width: kPaperWidthPx,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Space for logo (will be composited later)
          const SizedBox(height: 110),
          Text(
            'TICKET #$ticketNumber/$totalTickets',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          // Event
          Text(
            eventName.toUpperCase(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Date
          Text(
            dateStr,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          if (venue != null && venue.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              venue,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const SizedBox(height: 4),
            const Text(
              'Jos New Stadium',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
          const Divider(height: 12, thickness: 2),
          // Ticket Type + Price
          Text(
            '$ticketType  ₦${price.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Customer
          Text(
            customerName,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          if (customerPhone != null && customerPhone.isNotEmpty)
            Text(
              customerPhone,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          const SizedBox(height: 8),
          // QR Code
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: QrImageView(
              data: validationUrl,
              version: QrVersions.auto,
              size: 150,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'SCAN TO VALIDATE',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
          const Divider(height: 12, thickness: 2),
          // Footer with date and time
          Text(
            txnShort,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            '$dateStr  $timeStr',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
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

      // Resize logo to fit - preserve aspect ratio, target ~100px height for bolder look
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
      final y = 4; // Top padding

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

  /// Convert Flutter widget to image bytes
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
      print('Error converting widget to image: $e');
      return null;
    }
  }

  /// Load logo as bytes and convert to black and white for thermal printing
  Future<Uint8List?> _loadLogoBytes() async {
    try {
      final data = await rootBundle.load('assets/images/Plateau_United.png');
      final logoBytes = data.buffer.asUint8List();

      // Convert to black and white for thermal printer compatibility
      final processedLogo = await _convertToBlackAndWhite(logoBytes);
      return processedLogo ?? logoBytes;
    } catch (e) {
      return null;
    }
  }

  /// Convert image to black and white for thermal printing
  /// Removes background by making light pixels transparent/white
  Future<Uint8List?> _convertToBlackAndWhite(Uint8List imageBytes) async {
    try {
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) return null;

      // Just resize and return - let the printer handle it
      final resized = img.copyResize(originalImage, width: 100);
      return Uint8List.fromList(img.encodePng(resized));
    } catch (e) {
      print('Error converting logo: $e');
      return null;
    }
  }

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
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final dateStr =
        '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    // Load logo
    final logoImage = await _loadLogo();

    for (int i = 0; i < numberOfTickets; i++) {
      final code = ticketCodes[i];
      final validationUrl = '${kBaseUrl.replaceAll('/api', '')}/validate/$code';
      doc.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(24),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Logo and Header
              if (logoImage != null) ...[
                pw.Image(logoImage, width: 80, height: 80),
                pw.SizedBox(height: 12),
              ],
              pw.Text(
                'TICKET',
                style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Ticket #${i + 1} of $numberOfTickets',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 20),

              // Event Details Card
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 1),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      eventName.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Type:',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(ticketType),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Price:',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'N ${price.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Customer Details
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'CUSTOMER',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      customerName,
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                    if (customerEmail != null && customerEmail.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        customerEmail,
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                    if (customerPhone != null && customerPhone.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        customerPhone,
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // QR Code
              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 2),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(8),
                    ),
                  ),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: validationUrl,
                    width: 200,
                    height: 200,
                  ),
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'SCAN THIS CODE AT ENTRANCE',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1,
                  color: PdfColors.grey700,
                ),
              ),
              pw.Spacer(),

              // Footer
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Transaction: $transactionId',
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    dateStr,
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/tickets_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<pw.ImageProvider?> _loadLogo() async {
    try {
      final data = await rootBundle.load('assets/images/Plateau_United.png');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      print('Logo not found: $e');
      return null;
    }
  }

  /// Print multiple tickets
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
      // Try Wi‑Fi printing first if preferred and IP is saved
      try {
        final prefs = await SharedPreferences.getInstance();
        final preferred = prefs.getString('kPreferredPrintPath') ?? 'wifi';
        final wifiIp = prefs.getString('kPreferredWifiPrinterIp');
        if (preferred == 'wifi' && wifiIp != null && wifiIp.isNotEmpty) {
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
      } catch (_) {}

      // Request Bluetooth permissions (Android 12+)
      final ok = await _requestBluetoothPermissions();
      if (!ok) {
        print('Bluetooth permissions not granted');
        return false;
      }

      // Ensure connected once per batch with a very short timeout
      bool connected = await ensureConnected(
        deviceAddress: deviceAddress,
        timeoutMs: connectTimeoutMs,
      );
      if (!connected) {
        // Fallback: save as PDF
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
        );
        if (onSavedPdf != null) onSavedPdf(pdfPath);
        print('No printer available. Tickets saved to PDF: $pdfPath');
        return true;
      }

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

        if (!success) {
          return false;
        }

        // Small delay between tickets
        if (i < numberOfTickets - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      return true;
    } catch (e) {
      print('Error printing multiple tickets: $e');
      return false;
    }
  }

  Future<bool> _requestBluetoothPermissions() async {
    try {
      final result = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      final scan = result[Permission.bluetoothScan]?.isGranted ?? true;
      final connect = result[Permission.bluetoothConnect]?.isGranted ?? true;
      return scan && connect;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ensureConnected({
    String? deviceAddress,
    int timeoutMs = 1200,
  }) async {
    try {
      final isConn = await _printer.isConnected;
      if (isConn == true) return true;
      final start = DateTime.now();
      // Try fast connect once, then one quick retry if time remains
      var ok = await _connectToPrinter(deviceAddress: deviceAddress);
      if (ok) return true;
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final remain = timeoutMs - elapsed;
      if (remain > 250) {
        await Future.delayed(Duration(milliseconds: 250));
        ok = await _connectToPrinter(deviceAddress: deviceAddress);
        if (ok) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Connect to a specific or first available paired printer
  Future<bool> _connectToPrinter({String? deviceAddress}) async {
    try {
      List<BluetoothDevice> devices = await _printer.getBondedDevices();
      if (devices.isEmpty) {
        print('No bonded Bluetooth devices found.');
        return false;
      }

      BluetoothDevice target;
      if (deviceAddress != null) {
        target = devices.firstWhere(
          (d) => (d.address ?? '') == deviceAddress,
          orElse: () => devices.first,
        );
      } else {
        target = devices.first;
      }

      await _printer.connect(target);

      // Wait briefly for connection to establish
      await Future.delayed(const Duration(milliseconds: 400));

      bool? isConnected = await _printer.isConnected;
      return isConnected == true;
    } catch (e) {
      print('Error connecting to printer: $e');
      return false;
    }
  }

  /// Get list of paired Bluetooth printers
  Future<List<BluetoothDevice>> getPairedPrinters() async {
    try {
      return await _printer.getBondedDevices();
    } catch (e) {
      print('Error getting paired devices: $e');
      return [];
    }
  }

  /// Connect to a specific printer
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

  /// Check if printer is connected
  Future<bool> isConnected() async {
    try {
      bool? connected = await _printer.isConnected;
      return connected == true;
    } catch (e) {
      return false;
    }
  }

  /// Disconnect from printer
  Future<void> disconnect() async {
    try {
      await _printer.disconnect();
    } catch (e) {
      print('Error disconnecting: $e');
    }
  }

  /// Test print - useful for debugging
  Future<bool> testPrint() async {
    try {
      bool? isConnected = await _printer.isConnected;
      if (isConnected != true) {
        final connected = await _connectToPrinter();
        if (!connected) return false;
      }

      await _printer.printNewLine();
      await _printer.printCustom('TEST PRINT', 3, 1);
      await _printer.printNewLine();
      await _printer.printCustom('Printer is working!', 1, 1);
      await _printer.printNewLine();
      await _printer.printNewLine();
      await _printer.paperCut();

      return true;
    } catch (e) {
      print('Error in test print: $e');
      return false;
    }
  }
}
