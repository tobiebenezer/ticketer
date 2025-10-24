
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';

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
      await _printer.printCustom('TICKET RECEIPT', 3, 1); // Size 3, Center
      await _printer.printNewLine();

      // Transaction info
      await _printer.printCustom('Transaction: $transactionId', 1, 1);
      await _printer.printCustom('Ticket #$ticketNumber of $totalTickets', 2, 1);
      await _printer.printNewLine();

      // Divider
      await _printer.printCustom('--------------------------------', 0, 1);

      // Event details
      await _printer.printLeftRight('EVENT:', eventName, 1);
      await _printer.printLeftRight('Type:', ticketType, 0);
      await _printer.printLeftRight('Price:', '\$$price', 0);
      await _printer.printNewLine();

      // Customer details
      await _printer.printCustom('CUSTOMER DETAILS', 1, 0);
      await _printer.printLeftRight('Name:', customerName, 0);
      if (customerEmail != null && customerEmail.isNotEmpty) {
        await _printer.printCustom('Email: $customerEmail', 0, 0);
      }
      if (customerPhone != null && customerPhone.isNotEmpty) {
        await _printer.printCustom('Phone: $customerPhone', 0, 0);
      }
      await _printer.printNewLine();

      // Divider
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

      // Ticket code
      await _printer.printCustom(ticketCode, 1, 1);
      await _printer.printNewLine();

      // Footer
      await _printer.printCustom('Scan this code at entrance', 0, 1);
      await _printer.printCustom('Thank you!', 0, 1);
      await _printer.printNewLine();

      // Date/Time
      final now = DateTime.now();
      await _printer.printCustom(
        '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
        0,
        1,
      );

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
  }) async {
    try {
      for (int i = 0; i < numberOfTickets; i++) {
        final success = await printTicket(
          eventName: eventName,
          ticketType: ticketType,
          price: price,
          ticketNumber: i + 1,
          totalTickets: numberOfTickets,
          ticketCode: ticketCodes[i],
          validationUrl: 'https://your-api.com/validate/${ticketCodes[i]}',
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

  /// Connect to the first available paired printer
  Future<bool> _connectToPrinter() async {
    try {
      List<BluetoothDevice> devices = await _printer.getBondedDevices();
      if (devices.isEmpty) {
        print('No bonded Bluetooth devices found.');
        return false;
      }

      // Connect to the first bonded device
      // In production, let user select printer
      await _printer.connect(devices.first);
      
      // Wait for connection to establish
      await Future.delayed(const Duration(seconds: 2));
      
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
      final imageSize = moduleCount * pixelSize;

      // Create white background image
      final image = img.Image(width: imageSize, height: imageSize);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));

      // Draw QR code
      for (int x = 0; x < moduleCount; x++) {
        for (int y = 0; y < moduleCount; y++) {
          if (qrCode.isDark(y, x)) {
            // Draw black module
            img.fillRect(
              image,
              x1: x * pixelSize,
              y1: y * pixelSize,
              x2: (x + 1) * pixelSize,
              y2: (y + 1) * pixelSize,
              color: img.ColorRgb8(0, 0, 0),
            );
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
