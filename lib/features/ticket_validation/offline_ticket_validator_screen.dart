import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:myapp/features/ticket_validation/offline_validation_result_screen.dart';
import 'package:myapp/features/ticket_validation/widgets/sync_status_widget.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enhanced Ticket Validator Screen with Offline Support
///
/// Features:
/// - QR code scanning with camera overlay
/// - Offline validation support
/// - Sync status indicator
/// - Validated ticket counter
class OfflineTicketValidatorScreen extends StatefulWidget {
  final int? eventId;

  const OfflineTicketValidatorScreen({super.key, this.eventId});

  @override
  State<OfflineTicketValidatorScreen> createState() =>
      _OfflineTicketValidatorScreenState();
}

class _OfflineTicketValidatorScreenState
    extends State<OfflineTicketValidatorScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  bool _isProcessing = false;
  bool _cameraReady = false;
  late final MobileScannerController _controller;
  int _validatedCount = 0;
  final Set<String> _countedRefs = <String>{};
  int? _eventId;

  String? get _countKey {
    final id = _eventId;
    if (id == null) return null;
    return 'validatedCount_event_$id';
  }

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
    _ensureCameraPermission();
    _loadEventAndCount();
  }

  Future<void> _loadEventAndCount() async {
    final prefs = await SharedPreferences.getInstance();
    final effectiveEventId = widget.eventId ?? prefs.getInt('kActiveEventId');
    final key = effectiveEventId == null
        ? null
        : 'validatedCount_event_$effectiveEventId';
    final count = key == null ? 0 : (prefs.getInt(key) ?? 0);
    if (!mounted) return;
    setState(() {
      _eventId = effectiveEventId;
      _validatedCount = count;
    });
  }

  Future<void> _persistCount() async {
    final key = _countKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, _validatedCount);
  }

  Future<void> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!mounted) return;
    setState(() {
      _cameraReady = status.isGranted;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Validate Ticket'),
        actions: const [
          SyncIndicator(), // Sync status in AppBar
        ],
      ),
      body: !_cameraReady
          ? _buildCameraPermissionView()
          : Column(
              children: <Widget>[
                // Sync Status Card
                const SyncStatusWidget(),
                // Camera Scanner
                Expanded(
                  flex: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        key: qrKey,
                        controller: _controller,
                        onDetect: (capture) async {
                          if (_isProcessing) return;
                          _isProcessing = true;
                          final List<Barcode> barcodes = capture.barcodes;
                          if (barcodes.isNotEmpty) {
                            final String? code = barcodes.first.rawValue;
                            if (code != null) {
                              _controller.stop();
                              _navigateToResult(code);
                            } else {
                              _isProcessing = false;
                            }
                          } else {
                            _isProcessing = false;
                          }
                        },
                      ),
                      const _ScannerOverlay(),
                    ],
                  ),
                ),
                // Bottom Info
                Expanded(
                  flex: 1,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Validated: $_validatedCount',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text('Scan a ticket QR code'),
                        if (_eventId != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Event ID: $_eventId',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCameraPermissionView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_camera_front, size: 64),
            const SizedBox(height: 16),
            const Text('Camera permission is required to scan tickets.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _ensureCameraPermission,
              child: const Text('Grant Permission'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: openAppSettings,
              child: const Text('Open App Settings'),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToResult(String code) {
    // Use offline validation if event ID is available
    if (_eventId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OfflineValidationResultScreen(
            qrContent: code,
            matcheId: _eventId!,
          ),
        ),
      ).then((result) {
        // Increment counter if validation was successful
        if (result is bool && result) {
          setState(() {
            _validatedCount += 1;
          });
          _persistCount();
        }
        _isProcessing = false;
        _controller.start();
      });
    } else {
      // Fallback to online validation if no event ID
      // (Keep existing ValidationResultScreen as fallback)
      _isProcessing = false;
      _controller.start();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an event first'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}

/// Scanner Overlay with rounded rectangle cutout
class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ScannerOverlayPainter());
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.5);
    final clearPaint = Paint()..blendMode = BlendMode.clear;

    final rect = Offset.zero & size;
    final boxSize = size.width * 0.6;
    final left = (size.width - boxSize) / 2;
    final top = (size.height - boxSize) / 2;
    final rrect = RRect.fromRectXY(
      Rect.fromLTWH(left, top, boxSize, boxSize),
      12,
      12,
    );

    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, overlayPaint);
    canvas.drawRRect(rrect, clearPaint);
    canvas.restore();

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
