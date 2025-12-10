import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:esc_pos_printer/esc_pos_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:myapp/core/constants/network_constants.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';

class NetworkPrintService {
  // Thermal printer paper width in pixels (58mm ≈ 384px, 80mm ≈ 576px at 203 DPI)
  static const double kPaperWidth58mm = 384.0;
  static const double kPaperWidth80mm = 576.0;

  Future<bool> printMultipleTickets({
    required String ip,
    int port = 9100,
    PaperSize paperSize = PaperSize.mm80,
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
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(paperSize, profile);
    final res = await printer.connect(
      ip,
      port: port,
      timeout: const Duration(seconds: 2),
    );
    if (res != PosPrintResult.success) {
      return false;
    }

    try {
      final paperWidthPx = paperSize == PaperSize.mm58
          ? kPaperWidth58mm
          : kPaperWidth80mm;

      // Pre-load logo once before loop
      final logoBytes = await _loadLogoBytes();
      print(
        'Logo loaded: ${logoBytes != null ? '${logoBytes.length} bytes' : 'null'}',
      );

      for (int i = 0; i < numberOfTickets; i++) {
        final code = ticketCodes[i];
        final validationUrl =
            '${kBaseUrl.replaceAll('/api', '')}/validate/$code';

        // Generate ticket as image
        final ticketImageBytes = await _generateTicketImage(
          eventName: eventName,
          ticketType: ticketType,
          price: price,
          ticketNumber: i + 1,
          totalTickets: numberOfTickets,
          validationUrl: validationUrl,
          transactionId: transactionId,
          customerName: customerName,
          customerEmail: customerEmail,
          customerPhone: customerPhone,
          paperWidthPx: paperWidthPx,
          logoImage: logoBytes != null ? img.decodeImage(logoBytes) : null,
          venue: venue,
        );

        if (ticketImageBytes != null) {
          final decodedImage = img.decodeImage(ticketImageBytes);
          if (decodedImage != null) {
            printer.image(decodedImage, align: PosAlign.center);
          }
        }

        printer.feed(1);
        printer.cut();
      }
    } catch (e) {
      try {
        printer.disconnect();
      } catch (_) {}
      return false;
    }

    try {
      printer.disconnect();
    } catch (_) {}
    return true;
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
    required double paperWidthPx,
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
        paperWidthPx: paperWidthPx,
        venue: venue,
      );

      final bytes = await _widgetToImage(ticketWidget, paperWidthPx);

      // Composite logo onto the ticket image if available
      if (bytes != null && logoImage != null) {
        return _compositeLogoOnTicket(bytes, logoImage, paperWidthPx);
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
    required double paperWidthPx,
    String? venue,
  }) {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    // final txnShort = transactionId.length > 12 ? '...${transactionId.substring(transactionId.length - 12)}' : transactionId;
    final txnShort = transactionId;
    final isWide = paperWidthPx > 400;
    final qrSize = isWide ? 200.0 : 150.0;

    return Container(
      width: paperWidthPx,
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 20 : 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Space for logo (will be composited later)
          const SizedBox(height: 110),
          Text(
            'TICKET #$ticketNumber/$totalTickets',
            style: TextStyle(
              fontSize: isWide ? 20 : 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          // Event
          Text(
            eventName.toUpperCase(),
            style: TextStyle(
              fontSize: isWide ? 18 : 16,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Date
          Text(
            dateStr,
            style: TextStyle(
              fontSize: isWide ? 16 : 14,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          if (venue != null && venue.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              venue,
              style: TextStyle(
                fontSize: isWide ? 16 : 14,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              'Jos New Stadium',
              style: TextStyle(
                fontSize: isWide ? 14 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Divider(height: 12, thickness: 2),
          // Ticket Type + Price
          Text(
            '$ticketType  ₦${price.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: isWide ? 16 : 14,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Customer
          Text(
            customerName,
            style: TextStyle(
              fontSize: isWide ? 14 : 13,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          if (customerPhone != null && customerPhone.isNotEmpty)
            Text(
              customerPhone,
              style: TextStyle(
                fontSize: isWide ? 13 : 12,
                fontWeight: FontWeight.w500,
              ),
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
              size: qrSize,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'SCAN TO VALIDATE',
            style: TextStyle(
              fontSize: isWide ? 14 : 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Divider(height: 12, thickness: 2),
          // Footer with date and time
          Text(
            '$txnShort',
            style: TextStyle(
              fontSize: isWide ? 12 : 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$dateStr  $timeStr',
            style: TextStyle(
              fontSize: isWide ? 12 : 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Composite logo onto ticket image
  Uint8List? _compositeLogoOnTicket(
    Uint8List ticketBytes,
    img.Image logoImage,
    double paperWidthPx,
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
  Future<Uint8List?> _widgetToImage(Widget widget, double paperWidthPx) async {
    try {
      final repaintBoundary = RenderRepaintBoundary();
      final renderView = RenderView(
        view: WidgetsBinding.instance.platformDispatcher.views.first,
        child: RenderPositionedBox(
          alignment: Alignment.topCenter,
          child: repaintBoundary,
        ),
        configuration: ViewConfiguration(
          logicalConstraints: BoxConstraints(
            maxWidth: paperWidthPx,
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
      // The image package's grayscale + threshold was causing issues
      final resized = img.copyResize(originalImage, width: 100);
      return Uint8List.fromList(img.encodePng(resized));
    } catch (e) {
      print('Error converting logo: $e');
      return null;
    }
  }
}
