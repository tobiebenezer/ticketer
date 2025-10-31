import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:myapp/features/ticket_validation/validation_result_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class TicketValidatorScreen extends StatefulWidget {
  const TicketValidatorScreen({super.key});

  @override
  State<TicketValidatorScreen> createState() => _TicketValidatorScreenState();
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScannerOverlayPainter(),
    );
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
    final rrect = RRect.fromRectXY(Rect.fromLTWH(left, top, boxSize, boxSize), 12, 12);

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

class _TicketValidatorScreenState extends State<TicketValidatorScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  bool _isProcessing = false;
  bool _cameraReady = false;
  late final MobileScannerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController();
    _ensureCameraPermission();
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
      appBar: AppBar(title: const Text('Validate Ticket')),
      body: !_cameraReady
          ? _buildCameraPermissionView()
          : Column(
              children: <Widget>[
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
                const Expanded(
                  flex: 1,
                  child: Center(child: Text('Scan a ticket QR code')),
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ValidationResultScreen(scanData: code),
      ),
    ).then(
      (_) {
        _isProcessing = false;
        _controller.start();
      },
    ); // Reset processing flag when returning
  }
}
