import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:myapp/core/services/offline_validation_service.dart';
import 'package:myapp/data/local/database_helper.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/services/offline_event_service.dart';
import 'package:myapp/data/services/sync_api.dart';
import 'package:myapp/data/services/sync_service.dart';
import 'package:myapp/features/ticket_validation/offline_validation_result_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TicketValidatorScreen extends StatefulWidget {
  final int? eventId;

  const TicketValidatorScreen({super.key, this.eventId});

  @override
  State<TicketValidatorScreen> createState() => _TicketValidatorScreenState();
}

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
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
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

class _TicketValidatorScreenState extends State<TicketValidatorScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  final OfflineValidationService _validationService = OfflineValidationService();
  final SyncApi _syncApi = SyncApi();
  final OfflineEventService _offlineEventService = OfflineEventService();
  final DatabaseHelper _db = DatabaseHelper();
  final SyncService _syncService = SyncService();
  bool _isProcessing = false;
  bool _cameraReady = false;
  bool _isDownloading = false;
  bool _isSyncing = false;
  late final MobileScannerController _controller;
  int _validatedCount = 0;
  int _unsyncedValidations = 0;
  final Set<String> _countedRefs = <String>{};
  int? _eventId;
  String? _eventName;

  String? get _countKey {
    final id = _eventId;
    if (id == null) return null;
    return 'validatedCount_event_$id';
  }

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadEventAndCount();
    _controller = MobileScannerController(
      formats: [
        BarcodeFormat.qrCode,
        BarcodeFormat.pdf417,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.aztec,
      ],
    );
    _ensureCameraPermission();
  }

  Future<void> _loadStats() async {
    final stats = await _validationService.getValidationStats();
    if (mounted) {
      setState(() {
        _unsyncedValidations = stats.unsyncedValidations;
      });
    }
  }

  Future<void> _loadEventAndCount() async {
    final prefs = await SharedPreferences.getInstance();
    final effectiveEventId = widget.eventId ?? prefs.getInt('kActiveEventId');
    final key = effectiveEventId == null
        ? null
        : 'validatedCount_event_$effectiveEventId';
    final count = key == null ? 0 : (prefs.getInt(key) ?? 0);
    
    // Load event name
    String? eventName;
    if (effectiveEventId != null) {
      try {
        final events = await _offlineEventService.getEvents();
        final event = events.firstWhere(
          (e) => e.id == effectiveEventId,
          orElse: () => events.first,
        );
        eventName = event.name;
      } catch (_) {}
    }
    
    if (!mounted) return;
    setState(() {
      _eventId = effectiveEventId;
      _eventName = eventName;
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Validate Ticket', style: TextStyle(fontSize: 18)),
            if (_eventName != null)
              Text(
                _eventName!,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download tickets for offline validation',
            onPressed: _isDownloading ? null : _downloadTickets,
          ),
          if (_unsyncedValidations > 0)
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload),
              tooltip: 'Sync validations to server',
              onPressed: _isSyncing ? null : _manualSync,
            ),
          if (_unsyncedValidations > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sync, size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        '$_unsyncedValidations',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                  'Validated: $_validatedCount',
                  style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
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
                Expanded(
                  flex: 1,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Validated: $_validatedCount',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (_unsyncedValidations > 0) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.sync, size: 16, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text(
                                  '$_unsyncedValidations pending sync',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        const Text('Scan a ticket QR code'),
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

  Future<void> _manualSync() async {
    setState(() {
      _isSyncing = true;
    });

    try {
      final result = await _syncService.syncAll();
      
      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Synced: ${result.validationsSynced} validations, ${result.ticketsSynced} tickets',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Reload stats to update the indicator
        await _loadStats();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Sync failed: ${result.message}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Sync error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _downloadTickets() async {
    final selectedEvent = await showModalBottomSheet<Event>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _EventSelectionModal(
        offlineEventService: _offlineEventService,
        syncApi: _syncApi,
        db: _db,
      ),
    );

    // If an event was selected and downloaded, update the UI immediately
    if (selectedEvent != null) {
      setState(() {
        _eventId = selectedEvent.id;
        _eventName = selectedEvent.name;
        _validatedCount = 0; // Reset count for new event
      });
    }
  }

  void _navigateToResult(String code) {
    final eventId = _eventId;
    if (eventId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No event selected. Please select an event first.')),
      );
      _isProcessing = false;
      _controller.start();
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OfflineValidationResultScreen(
          qrContent: code,
          matcheId: eventId,
        ),
      ),
    ).then((validatedRef) {
      if (validatedRef is String && validatedRef.isNotEmpty) {
        if (!_countedRefs.contains(validatedRef)) {
          setState(() {
            _validatedCount += 1;
            _countedRefs.add(validatedRef);
          });
          _persistCount();
        }
      }
      // Reload stats to update sync indicator
      _loadStats();
      _isProcessing = false;
      _controller.start();
    }); // Reset processing flag when returning
  }
}

/// Event Selection Modal for downloading tickets
class _EventSelectionModal extends StatefulWidget {
  final OfflineEventService offlineEventService;
  final SyncApi syncApi;
  final DatabaseHelper db;

  const _EventSelectionModal({
    required this.offlineEventService,
    required this.syncApi,
    required this.db,
  });

  @override
  State<_EventSelectionModal> createState() => _EventSelectionModalState();
}

class _EventSelectionModalState extends State<_EventSelectionModal> {
  List<Event>? _events;
  bool _isLoading = true;
  String? _error;
  int? _downloadingEventId;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Use cached events from OfflineEventService (already loaded in HomeScreen)
      final events = await widget.offlineEventService.getEvents();
      if (mounted) {
        setState(() {
          _events = events;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load events: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _downloadEventTickets(Event event) async {
    setState(() {
      _downloadingEventId = event.id;
    });

    try {
      final result = await widget.syncApi.getMatchTickets(event.id);
      
      final ticketsData = result.tickets.map((t) => {
        'ticket_id': t.ticketId,
        'reference_no': t.referenceNo,
      }).toList();

      final insertedCount = await widget.db.insertDownloadedTickets(
        matcheId: event.id,
        tickets: ticketsData,
      );

      // Set this event as the active event
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('kActiveEventId', event.id);

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded $insertedCount tickets for ${event.name}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.pop(context, event); // Return the event to parent
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download tickets: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingEventId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.download, size: 24),
                      const SizedBox(width: 12),
                      const Text(
                        'Download Tickets',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select an event to download tickets for offline validation',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                                const SizedBox(height: 16),
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadEvents,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _events == null || _events!.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text('No events available'),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: _events!.length,
                              itemBuilder: (context, index) {
                                final event = _events![index];
                                final isDownloading = _downloadingEventId == event.id;

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    child: Icon(
                                      Icons.event,
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                  title: Text(
                                    event.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    event.venue ?? 'No venue',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: isDownloading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : IconButton(
                                          icon: const Icon(Icons.download),
                                          onPressed: () => _downloadEventTickets(event),
                                        ),
                                  onTap: isDownloading ? null : () => _downloadEventTickets(event),
                                );
                              },
                            ),
            ),
          ],
        );
      },
    );
  }
}
