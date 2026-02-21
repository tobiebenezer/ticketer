import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:esc_pos_printer_lts/esc_pos_printer_lts.dart';
import 'package:esc_pos_utils_lts/esc_pos_utils_lts.dart';
import 'package:myapp/core/constants/network_constants.dart';
import 'package:myapp/core/services/app_settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NetworkPrintService {
  // Thermal printer paper width in pixels (58mm ≈ 384px, 80mm ≈ 576px at 203 DPI)
  static const double kPaperWidth58mm = 384.0;
  static const double kPaperWidth80mm = 576.0;

  final AppSettingsService _settingsService = AppSettingsService();

  /// Generate custom ticket number format: TKA-{userId}-{shortId}
  Future<String> _getTicketNumber(int? ticketId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;

      // Use ticketId or generate a short ID from timestamp
      final shortId =
          ticketId?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString().substring(7);

      return 'TKA-$userId-$shortId';
    } catch (e) {
      // Fallback to simple format if error
      return 'TKA-${ticketId ?? 0}';
    }
  }

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
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(paperSize, profile);
    print('Connecting to printer at $ip:$port...');
    final res = await printer.connect(
      ip,
      port: port,
      timeout: const Duration(seconds: 5),
    );
    print('Printer connection result: $res');
    if (res != PosPrintResult.success) {
      print('Failed to connect to printer: $res');
      return false;
    }

    try {
      final paperWidthPx = paperSize == PaperSize.mm58
          ? kPaperWidth58mm
          : kPaperWidth80mm;

      // Pre-load and decode logo once before loop — avoids repeated PNG decode
      final logoBytes = await loadLogoBytes();
      final logoImage = logoBytes != null ? img.decodeImage(logoBytes) : null;

      for (int i = 0; i < numberOfTickets; i++) {
        final code = ticketCodes[i];
        final displayTicketNumber =
            ticketNumbers != null && i < ticketNumbers.length
            ? ticketNumbers[i]
            : i + 1;
        final displayTicketTotal =
            ticketTotals != null && i < ticketTotals.length
            ? ticketTotals[i]
            : numberOfTickets;
        final validationUrl =
            '${kBaseUrl.replaceAll('/api', '')}/validate/$code';

        // Generate ticket as image
        final ticketImageBytes = await generateTicketImage(
          eventName: eventName,
          ticketType: ticketType,
          price: price,
          ticketNumber: displayTicketNumber,
          totalTickets: displayTicketTotal,
          validationUrl: validationUrl,
          transactionId: transactionId,
          customerName: customerName,
          customerEmail: customerEmail,
          customerPhone: customerPhone,
          paperWidthPx: paperWidthPx,
          logoImage: logoImage,
          venue: venue,
          ticketId: ticketIds != null && i < ticketIds.length
              ? ticketIds[i]
              : null,
          matchId: matchIds != null && i < matchIds.length ? matchIds[i] : null,
          ticketTypeId: ticketTypeIds != null && i < ticketTypeIds.length
              ? ticketTypeIds[i]
              : null,
        );

        if (ticketImageBytes != null) {
          final decodedImage = img.decodeImage(ticketImageBytes);
          if (decodedImage != null) {
            printer.image(decodedImage, align: PosAlign.center);
          }
        }

        printer.feed(1);
        printer.cut();

        // Delay between tickets to prevent printer buffer overflow
        // This gives the printer time to process and print each ticket
        if (i < numberOfTickets - 1) {
          final delayMs = await _settingsService.getPrinterDelayMs();
          await Future.delayed(Duration(milliseconds: delayMs));
        }
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
  Future<Uint8List?> generateTicketImage({
    required String eventName,
    required String ticketType,
    required double price,
    required int ticketNumber,
    required int totalTickets,
    required String validationUrl,
    required String transactionId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    required double paperWidthPx,
    img.Image? logoImage,
    String? venue,
    int? ticketId,
    int? matchId,
    int? ticketTypeId,
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
        ticketId: ticketId,
        matchId: matchId,
        ticketTypeId: ticketTypeId,
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

  /// Build ticket widget with space for logo at top (composited later)
  Widget _buildTicketWidget({
    required String eventName,
    required String ticketType,
    required double price,
    required int ticketNumber,
    required int totalTickets,
    required String validationUrl,
    required String transactionId,
    String? customerName,
    String? customerEmail,
    String? customerPhone,
    required double paperWidthPx,
    String? venue,
    int? ticketId,
    int? matchId,
    int? ticketTypeId,
  }) {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final isWide = paperWidthPx > 400;
    final displayId = (ticketId != null)
        ? ticketId.toString()
        : transactionId.trim().isEmpty
        ? '-'
        : transactionId;

    return Container(
      width: paperWidthPx,
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
                  isWide ? 40 : 30,
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
              padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'ID: $displayId',
                      style: TextStyle(
                        fontSize: isWide ? 12 : 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Space for logo (will be composited later)
                  const SizedBox(height: 100),

                  // Event Name
                  Text(
                    eventName.toUpperCase(),
                    style: TextStyle(
                      fontSize: isWide ? 24 : 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  SizedBox(height: isWide ? 8 : 6),

                  // Ticket Type Badge
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 16 : 12,
                      vertical: isWide ? 6 : 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      ticketType.toUpperCase(),
                      style: TextStyle(
                        fontSize: isWide ? 18 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  SizedBox(height: isWide ? 12 : 10),
                  const Divider(height: 2, thickness: 2, color: Colors.black),
                  SizedBox(height: isWide ? 12 : 10),

                  // Date & Time Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_today, size: isWide ? 18 : 16),
                      const SizedBox(width: 6),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: isWide ? 16 : 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: isWide ? 24 : 16),
                      Icon(Icons.access_time, size: isWide ? 18 : 16),
                      const SizedBox(width: 6),
                      Text(
                        // timeStr,
                        "4:00 pm",
                        style: TextStyle(
                          fontSize: isWide ? 16 : 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: isWide ? 8 : 6),

                  // Venue
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_on, size: isWide ? 18 : 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          venue ?? 'Jos New Stadium',
                          style: TextStyle(
                            fontSize: isWide ? 15 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: isWide ? 12 : 10),

                  // Price & Ticket Number Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PRICE',
                            style: TextStyle(
                              fontSize: isWide ? 12 : 10,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₦${price.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: isWide ? 28 : 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isWide ? 14 : 12,
                          vertical: isWide ? 8 : 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'TICKET',
                              style: TextStyle(
                                fontSize: isWide ? 10 : 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '#$ticketNumber/$totalTickets',
                              style: TextStyle(
                                fontSize: isWide ? 18 : 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: isWide ? 12 : 10),

                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isWide ? 12 : 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 1.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CUSTOMER',
                          style: TextStyle(
                            fontSize: isWide ? 10 : 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          (customerName == null || customerName.trim().isEmpty)
                              ? 'GUEST'
                              : customerName.trim().toUpperCase(),
                          style: TextStyle(
                            fontSize: isWide ? 16 : 14,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: isWide ? 8 : 6),

            // Stub Divider with notches (perforation line)
            Stack(
              alignment: Alignment.center,
              children: [
                // Dashed line
                Row(
                  children: List.generate(
                    isWide ? 35 : 25,
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
                    width: isWide ? 18 : 14,
                    height: isWide ? 36 : 28,
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
                    width: isWide ? 18 : 14,
                    height: isWide ? 36 : 28,
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

            SizedBox(height: isWide ? 10 : 8),

            // QR Code and Data Matrix Section - Side by Side
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isWide ? 16 : 10),
              child: Column(
                children: [
                  // QR Code
                  Container(
                    padding: EdgeInsets.all(isWide ? 8 : 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: QrImageView(
                      data: validationUrl,
                      version: QrVersions.auto,
                      size: isWide ? 220 : 200,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  SizedBox(height: isWide ? 10 : 8),

                  Text(
                    'SCAN TO ENTER',
                    style: TextStyle(
                      fontSize: isWide ? 16 : 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  // SizedBox(height: isWide ? 6 : 4),
                  // Ticket IDs: matchId-ticketTypeId-ticketId
                  // Text(
                  //   '${matchId ?? "-"}-${ticketTypeId ?? "-"}-${ticketId ?? "-"}',
                  //   style: TextStyle(
                  //     fontSize: isWide ? 10 : 9,
                  //     color: Colors.black,
                  //     fontWeight: FontWeight.bold,
                  //   ),
                  // ),
                  SizedBox(height: isWide ? 4 : 3),
                  // Ticket code (from validation URL)
                  Text(
                    validationUrl.split('/').last.length > 8
                        ? validationUrl
                              .split('/')
                              .last
                              .substring(
                                validationUrl.split('/').last.length - 8,
                              )
                        : validationUrl.split('/').last,
                    style: TextStyle(
                      fontSize: isWide ? 16 : 14,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
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
                  isWide ? 40 : 30,
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

  /// Load logo as bytes for thermal printing
  Future<Uint8List?> loadLogoBytes() async {
    try {
      final data = await rootBundle.load('assets/images/Plateau_United.png');
      return data.buffer.asUint8List();
    } catch (e) {
      print('Error loading logo: $e');
      return null;
    }
  }
}
