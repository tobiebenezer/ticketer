import 'dart:convert';
import 'package:myapp/core/services/app_settings_service.dart';
import 'package:myapp/data/local/database_helper.dart';
import 'package:myapp/data/services/sync_service.dart';
import 'package:uuid/uuid.dart';

/// OfflineSaleService - Handles offline ticket creation with cryptographic signatures
class OfflineSaleService {
  final DatabaseHelper _db;
  final SyncService _syncService;
  final AppSettingsService settings;
  final _uuid = const Uuid();

  OfflineSaleService({
    DatabaseHelper? db,
    SyncService? syncService,
    AppSettingsService? settings,
  }) : _db = db ?? DatabaseHelper(),
       _syncService = syncService ?? SyncService(),
       settings = settings ?? AppSettingsService();

  /// Create a ticket offline
  ///
  /// This creates a ticket locally without server signature.
  /// The ticket will be signed by the server during sync.
  Future<OfflineSaleResult> createTicket({
    required int matcheId,
    required int ticketTypesId,
    required double amount,
    String? customerName,
  }) async {
    try {
      // Check if event is cached
      final eventCache = await _db.getEventCache(matcheId);
      if (eventCache == null) {
        return OfflineSaleResult.error(
          'Event not cached. Please sync event data first.',
        );
      }

      // Generate TUID
      final tuid = _uuid.v4();
      final now = DateTime.now();

      // Create payload (will be signed by server during sync)
      final payloadData = {
        'tuid': tuid,
        'matche_id': matcheId,
        'ticket_types_id': ticketTypesId,
        if (customerName != null && customerName.isNotEmpty)
          'customer_name': customerName,
        'amount': amount.toStringAsFixed(2),
        'issued_at': now.toIso8601String(),
        'issuer_type': 'device', // Mark as device-issued
      };

      final payload = jsonEncode(payloadData);

      final eventPublicKey = eventCache['event_public_key'] as String;

      // Store ticket locally (using public key as marker - will be signed during sync)
      await _db.insertLocalTicket(
        ticketId: tuid,
        matcheId: matcheId,
        ticketTypesId: ticketTypesId,
        customerName: customerName,
        amount: amount,
        payload: payload,
        signature:
            eventPublicKey, // Use public key as marker for unsigned tickets
        createdAt: now,
      );

      // Trigger sync if online
      _syncService.syncNow().catchError((_) {
        // Silent fail - will sync later
      });

      // Create QR payload with proper format: {"payload": "...", "signature": "..."}
      // For offline tickets, signature = public key (marker for pending sync)
      final qrData = {
        'payload': payload,
        'signature':
            eventPublicKey, // Will be valid once synced and signed by server
      };
      final qrPayload = jsonEncode(qrData);

      return OfflineSaleResult.success(
        ticketId: tuid,
        qrPayload: qrPayload,
        createdAt: now,
      );
    } catch (e) {
      return OfflineSaleResult.error('Failed to create ticket: $e');
    }
  }

  /// Create multiple tickets offline (batch sale)
  Future<BatchSaleResult> createTickets({
    required int matcheId,
    required int ticketTypesId,
    required double amount,
    required int quantity,
    String? customerName,
  }) async {
    final results = <OfflineSaleResult>[];
    int successCount = 0;
    int failCount = 0;

    for (int i = 0; i < quantity; i++) {
      final result = await createTicket(
        matcheId: matcheId,
        ticketTypesId: ticketTypesId,
        amount: amount,
        customerName: customerName != null && customerName.isNotEmpty
            ? '$customerName (${i + 1}/$quantity)'
            : null,
      );

      results.add(result);
      if (result.isSuccess) {
        successCount++;
      } else {
        failCount++;
      }
    }

    return BatchSaleResult(
      results: results,
      successCount: successCount,
      failCount: failCount,
      totalAmount: amount * successCount,
    );
  }

  /// Get all unsynced tickets for display
  Future<List<Map<String, dynamic>>> getUnsyncedTickets() async {
    return await _db.getUnsyncedTickets();
  }

  /// Get ticket by ID
  Future<Map<String, dynamic>?> getTicketById(String ticketId) async {
    return await _db.getTicketById(ticketId);
  }

  /// Check if event is ready for offline sales
  Future<bool> isEventReady(int matcheId) async {
    return await _db.isEventCached(matcheId);
  }

  /// Bootstrap event for offline sales
  Future<bool> bootstrapEvent(int matcheId) async {
    return await _syncService.bootstrapEvent(matcheId);
  }
}

/// Result of offline ticket creation
class OfflineSaleResult {
  final bool isSuccess;
  final String? ticketId;
  final String? qrPayload;
  final DateTime? createdAt;
  final String? errorMessage;

  OfflineSaleResult._({
    required this.isSuccess,
    this.ticketId,
    this.qrPayload,
    this.createdAt,
    this.errorMessage,
  });

  factory OfflineSaleResult.success({
    required String ticketId,
    required String qrPayload,
    required DateTime createdAt,
  }) {
    return OfflineSaleResult._(
      isSuccess: true,
      ticketId: ticketId,
      qrPayload: qrPayload,
      createdAt: createdAt,
    );
  }

  factory OfflineSaleResult.error(String message) {
    return OfflineSaleResult._(isSuccess: false, errorMessage: message);
  }
}

/// Result of batch ticket creation
class BatchSaleResult {
  final List<OfflineSaleResult> results;
  final int successCount;
  final int failCount;
  final double totalAmount;

  BatchSaleResult({
    required this.results,
    required this.successCount,
    required this.failCount,
    required this.totalAmount,
  });

  bool get hasFailures => failCount > 0;
  bool get allSuccess => failCount == 0;
  int get totalCount => results.length;

  List<OfflineSaleResult> get successfulTickets =>
      results.where((r) => r.isSuccess).toList();

  List<OfflineSaleResult> get failedTickets =>
      results.where((r) => !r.isSuccess).toList();
}
