import 'dart:convert';
import 'package:myapp/core/services/app_settings_service.dart';
import 'package:myapp/core/services/device_crypto_service.dart';
import 'package:myapp/core/utils/device_info_util.dart';
import 'package:myapp/data/local/database_helper.dart';
import 'package:myapp/data/services/sync_service.dart';
import 'package:uuid/uuid.dart';

/// OfflineSaleService - Handles offline ticket creation with cryptographic signatures
class OfflineSaleService {
  final DatabaseHelper _db;
  final SyncService _syncService;
  final AppSettingsService settings;
  final DeviceCryptoService _deviceCrypto;
  final _uuid = const Uuid();

  OfflineSaleService({
    DatabaseHelper? db,
    SyncService? syncService,
    AppSettingsService? settings,
    DeviceCryptoService? deviceCrypto,
  }) : _db = db ?? DatabaseHelper(),
       _syncService = syncService ?? SyncService(),
       settings = settings ?? AppSettingsService(),
       _deviceCrypto = deviceCrypto ?? DeviceCryptoService();

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

      final deviceInfo = await DeviceInfoUtil.getDeviceInfo();
      final deviceKeys = await _deviceCrypto.ensureKeyPair();

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
        'issuer_device_uid': deviceInfo.uid,
        'issuer_key_version': deviceKeys.keyVersion,
      };

      final payload = jsonEncode(payloadData);

      final deviceSignature = await _deviceCrypto.signPayload(
        payload: payload,
        privateKeyBase64: deviceKeys.privateKeyBase64,
        publicKeyBase64: deviceKeys.publicKeyBase64,
      );

      // Store ticket locally (signature = device signature)
      await _db.insertLocalTicket(
        ticketId: tuid,
        matcheId: matcheId,
        ticketTypesId: ticketTypesId,
        customerName: customerName,
        amount: amount,
        payload: payload,
        signature: deviceSignature,
        createdAt: now,
      );

      // Trigger sync if online
      _syncService.syncNow().catchError((_) {
        // Silent fail - will sync later
      });

      final qrData = {
        'payload': payload,
        'signature': deviceSignature,
      };
      final qrPayload = jsonEncode(qrData);

      // Get total ticket count for display numbering
      final totalCount = await _db.getLocalTicketCount();

      return OfflineSaleResult.success(
        ticketId: tuid,
        qrPayload: qrPayload,
        createdAt: now,
        sequentialId: totalCount, // This ticket's number (1-based)
        totalTickets: totalCount,
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
  final int? sequentialId; // Display-friendly sequential ID (1-based)
  final int? totalTickets; // Total tickets at time of creation

  OfflineSaleResult._({
    required this.isSuccess,
    this.ticketId,
    this.qrPayload,
    this.createdAt,
    this.errorMessage,
    this.sequentialId,
    this.totalTickets,
  });

  factory OfflineSaleResult.success({
    required String ticketId,
    required String qrPayload,
    required DateTime createdAt,
    int? sequentialId,
    int? totalTickets,
  }) {
    return OfflineSaleResult._(
      isSuccess: true,
      ticketId: ticketId,
      qrPayload: qrPayload,
      createdAt: createdAt,
      sequentialId: sequentialId,
      totalTickets: totalTickets,
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
