import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qr/qr.dart' as qr;
import 'package:permission_handler/permission_handler.dart';
import 'package:myapp/core/constants/network_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myapp/features/ticket_printing/network_print_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';


class PrintService {
  final BlueThermalPrinter _printer = BlueThermalPrinter.instance;

  /// Print a single ticket with QR code
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

      // Print header
      await _printer.printNewLine();
      await _printer.printCustom('TICKET', 3, 1); // Size 3, Center
      await _printer.printNewLine();
      await _printer.printCustom('Ticket #$ticketNumber of $totalTickets', 0, 1);
      await _printer.printNewLine();
      await _printer.printNewLine();

      // Event details section
      await _printer.printCustom('================================', 0, 1);
      await _printer.printCustom(eventName.toUpperCase(), 2, 1);
      await _printer.printCustom('================================', 0, 1);
      await _printer.printNewLine();
      await _printer.printLeftRight('Type:', ticketType, 1);
      await _printer.printLeftRight('Price:', 'N ${price.toStringAsFixed(2)}', 1);
      await _printer.printNewLine();

      // Customer details
      await _printer.printCustom('--------------------------------', 0, 1);
      await _printer.printCustom('CUSTOMER', 1, 0);
      await _printer.printCustom(customerName, 0, 0);
      if (customerEmail != null && customerEmail.isNotEmpty) {
        await _printer.printCustom(customerEmail, 0, 0);
      }
      if (customerPhone != null && customerPhone.isNotEmpty) {
        await _printer.printCustom(customerPhone, 0, 0);
      }
      await _printer.printNewLine();

      // QR Code section
      await _printer.printCustom('--------------------------------', 0, 1);
      await _printer.printNewLine();

      // Generate and print QR code
      final qrImageBytes = await _generateQrImageBytes(validationUrl);
      if (qrImageBytes != null) {
        await _printer.printImageBytes(qrImageBytes);
        await _printer.printNewLine();
      } else {
        // Fallback: print QR code using built-in method
        await _printer.printQRcode(validationUrl, 200, 200, 1);
        await _printer.printNewLine();
      }

      // Footer
      await _printer.printCustom('SCAN THIS CODE AT ENTRANCE', 1, 1);
      await _printer.printNewLine();
      await _printer.printCustom('--------------------------------', 0, 1);

      // Transaction info and Date/Time
      final now = DateTime.now();
      final dateStr = '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
      await _printer.printLeftRight('Txn:', transactionId.substring(0, transactionId.length > 20 ? 20 : transactionId.length), 0);
      await _printer.printCustom(dateStr, 0, 1);

      // Cut paper
      await _printer.printNewLine();
      await _printer.printNewLine();
      await _printer.paperCut();

      return true;
    } catch (e) {
      print('Error printing ticket: $e');
      return false;
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
    final dateStr = '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    
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
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
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
                        pw.Text('Type:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text(ticketType),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Price:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.Text('N ${price.toStringAsFixed(2)}', 
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
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
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('CUSTOMER', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
                    pw.SizedBox(height: 6),
                    pw.Text(customerName, style: const pw.TextStyle(fontSize: 12)),
                    if (customerEmail != null && customerEmail.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(customerEmail, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    ],
                    if (customerPhone != null && customerPhone.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(customerPhone, style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
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
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: validationUrl,
                    width: 160,
                    height: 160,
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
                  pw.Text('Transaction: $transactionId', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  pw.Text(dateStr, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/tickets_${DateTime.now().millisecondsSinceEpoch}.pdf');
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
          validationUrl: '${kBaseUrl.replaceAll('/api', '')}/validate/${ticketCodes[i]}',
          transactionId: transactionId,
          customerName: customerName,
          customerEmail: customerEmail,
          customerPhone: customerPhone,
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

  Future<bool> ensureConnected({String? deviceAddress, int timeoutMs = 1200}) async {
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

  /// Generate QR code as image bytes
  Future<Uint8List?> _generateQrImageBytes(String data) async {
    try {
      // Validate QR data
      final qrValidationResult = QrValidator.validate(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
      );

      if (qrValidationResult.status != QrValidationStatus.valid) {
        print('Invalid QR data');
        return null;
      }

      // Create QR painter
      final qrPainter = QrPainter.withQr(
        qr: qrValidationResult.qrCode!,
        color: const Color(0xFF000000),
        emptyColor: const Color(0xFFFFFFFF),
        gapless: true,
      );

      // Convert to image
      final picData = await qrPainter.toImageData(
        300.0, // Size in pixels
        format: ui.ImageByteFormat.png,
      );

      if (picData == null) {
        print('Failed to generate QR image data');
        return null;
      }

      return picData.buffer.asUint8List();
    } catch (e) {
      print('Error generating QR image: $e');
      return null;
    }
  }

  /// Alternative: Generate QR using image package (more control)
  Future<Uint8List?> _generateQrImageBytesAlternative(String data) async {
    try {
      final qrValidationResult = QrValidator.validate(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
      );

      if (qrValidationResult.status != QrValidationStatus.valid) {
        return null;
      }

      final qrCode = qrValidationResult.qrCode!;
      final moduleCount = qrCode.moduleCount;
      final pixelSize = 10; // Size of each QR module in pixels
      // final imageSize = moduleCount * pixelSize; // unused variable removed

      // Create white background image
      final image = img.Image(moduleCount * pixelSize, moduleCount * pixelSize);
      img.fill(image, img.getColor(255, 255, 255));

      // Draw QR code
      final qrImg = qr.QrImage(qrCode);
      for (int x = 0; x < moduleCount; x++) {
        for (int y = 0; y < moduleCount; y++) {
          if (qrImg.isDark(y, x)) {
            // Draw black module
            img.fillRect(image, x * pixelSize, y * pixelSize, (x + 1) * pixelSize, (y + 1) * pixelSize, img.getColor(0, 0, 0));
          }
        }
      }

      // Encode as PNG
      return Uint8List.fromList(img.encodePng(image));
    } catch (e) {
      print('Error generating QR image (alternative): $e');
      return null;
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
