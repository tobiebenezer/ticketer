import 'package:dio/dio.dart';
import 'package:myapp/data/services/api_client.dart';

/// SyncApi - API client for offline sync operations.
///
/// Handles communication with the Laravel sync endpoints:
/// - POST /api/sync/tickets - Upload offline tickets
/// - POST /api/sync/validations - Upload validation logs
/// - GET /api/bootstrap/matches/{id} - Get bootstrap data
/// - GET /api/bootstrap/matches/{id}/validated-snapshot - Get bloom filter
class SyncApi {
  Dio get _dio => ApiClient.instance.dio;

  /// Upload offline-created tickets to server.
  ///
  /// Returns accepted and rejected ticket IDs.
  Future<SyncTicketsResult> syncTickets(
    List<Map<String, dynamic>> tickets,
  ) async {
    try {
      final response = await _dio.post(
        '/sync/tickets',
        data: {'tickets': tickets},
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return SyncTicketsResult.fromJson(data);
      }

      throw Exception('Sync failed: ${response.statusCode}');
    } on DioException catch (e) {
      // Log the full error response for debugging
      if (e.response?.statusCode == 422) {
        print('Validation error: ${e.response?.data}');
      }
      throw Exception('Sync failed: ${e.message}');
    }
  }

  /// Upload validation logs to server.
  ///
  /// Returns accepted validations and conflict info.
  Future<SyncValidationsResult> syncValidations(
    List<Map<String, dynamic>> validations,
  ) async {
    try {
      print('Syncing validations payload: $validations');
      final response = await _dio.post(
        '/sync/validations',
        data: {'validations': validations},
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return SyncValidationsResult.fromJson(data);
      }

      throw Exception('Sync failed: ${response.statusCode}');
    } on DioException catch (e) {
      // Log the full error response for debugging
      if (e.response?.statusCode == 422) {
        print('Validation sync error 422: ${e.response?.data}');
      }
      print('Validation sync error: ${e.response?.data}');
      throw Exception('Sync failed: ${e.message}');
    }
  }

  /// Get bootstrap data for offline operation.
  Future<BootstrapData> getBootstrap(int matcheId) async {
    try {
      final response = await _dio.get('/bootstrap/matches/$matcheId');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return BootstrapData.fromJson(data);
      }

      throw Exception('Failed to get bootstrap: ${response.statusCode}');
    } on DioException catch (e) {
      throw Exception('Failed to get bootstrap: ${e.message}');
    }
  }

  /// Get validated tickets snapshot (bloom filter).
  Future<SnapshotData> getValidatedSnapshot(int matcheId) async {
    try {
      final response = await _dio.get(
        '/bootstrap/matches/$matcheId/validated-snapshot',
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return SnapshotData.fromJson(data);
      }

      throw Exception('Failed to get snapshot: ${response.statusCode}');
    } on DioException catch (e) {
      throw Exception('Failed to get snapshot: ${e.message}');
    }
  }

  /// Acknowledge a sync batch.
  Future<void> acknowledgeBatch(String batchId) async {
    try {
      await _dio.post('/sync/batches/$batchId/ack');
    } on DioException catch (e) {
      throw Exception('Failed to acknowledge batch: ${e.message}');
    }
  }

  /// Get pending batches for this device.
  Future<List<Map<String, dynamic>>> getPendingBatches() async {
    try {
      final response = await _dio.get('/sync/batches/pending');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return List<Map<String, dynamic>>.from(
          data['pending_batches'] as List? ?? [],
        );
      }

      return [];
    } on DioException catch (e) {
      throw Exception('Failed to get pending batches: ${e.message}');
    }
  }

  /// Get all tickets for a match for offline validation.
  /// 
  /// This is used to download tickets from other devices for offline validation.
  Future<MatchTicketsResult> getMatchTickets(int matchId) async {
    try {
      final response = await _dio.get('/match-validaton/$matchId/tickets');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        return MatchTicketsResult.fromJson(data);
      }

      throw Exception('Failed to get match tickets: ${response.statusCode}');
    } on DioException catch (e) {
      throw Exception('Failed to get match tickets: ${e.message}');
    }
  }
}

// ==================== RESULT CLASSES ====================

/// Result of ticket sync
class SyncTicketsResult {
  final String batchId;
  final List<String> accepted;
  final List<RejectedItem> rejected;
  final String processedAt;

  SyncTicketsResult({
    required this.batchId,
    required this.accepted,
    required this.rejected,
    required this.processedAt,
  });

  factory SyncTicketsResult.fromJson(Map<String, dynamic> json) {
    return SyncTicketsResult(
      batchId: json['batch_id'] as String,
      accepted: List<String>.from(json['accepted'] as List? ?? []),
      rejected: (json['rejected'] as List? ?? [])
          .map((e) => RejectedItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      processedAt: json['processed_at'] as String? ?? '',
    );
  }

  bool get hasRejections => rejected.isNotEmpty;
  int get acceptedCount => accepted.length;
  int get rejectedCount => rejected.length;
}

/// Result of validation sync
class SyncValidationsResult {
  final String batchId;
  final List<AcceptedValidation> accepted;
  final List<RejectedItem> rejected;
  final List<ConflictInfo> conflicts;
  final String processedAt;

  SyncValidationsResult({
    required this.batchId,
    required this.accepted,
    required this.rejected,
    required this.conflicts,
    required this.processedAt,
  });

  factory SyncValidationsResult.fromJson(Map<String, dynamic> json) {
    return SyncValidationsResult(
      batchId: json['batch_id'] as String,
      accepted: (json['accepted'] as List? ?? [])
          .map((e) => AcceptedValidation.fromJson(e as Map<String, dynamic>))
          .toList(),
      rejected: (json['rejected'] as List? ?? [])
          .map((e) => RejectedItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      conflicts: (json['conflicts'] as List? ?? [])
          .map((e) => ConflictInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      processedAt: json['processed_at'] as String? ?? '',
    );
  }

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Rejected item with reason
class RejectedItem {
  final String id;
  final String reason;

  RejectedItem({required this.id, required this.reason});

  factory RejectedItem.fromJson(Map<String, dynamic> json) {
    return RejectedItem(
      id: (json['tuid'] ?? json['ticket_id'] ?? '') as String,
      reason: json['reason'] as String? ?? 'unknown',
    );
  }
}

/// Accepted validation info
class AcceptedValidation {
  final String ticketId;
  final String validationId;

  AcceptedValidation({required this.ticketId, required this.validationId});

  factory AcceptedValidation.fromJson(Map<String, dynamic> json) {
    return AcceptedValidation(
      ticketId: json['ticket_id'] as String,
      validationId: json['validation_id'] as String,
    );
  }
}

/// Conflict resolution info
class ConflictInfo {
  final String ticketId;
  final String yourValidationId;
  final bool isFirstScan;
  final String? firstScanAt;
  final String? firstScanDevice;

  ConflictInfo({
    required this.ticketId,
    required this.yourValidationId,
    required this.isFirstScan,
    this.firstScanAt,
    this.firstScanDevice,
  });

  factory ConflictInfo.fromJson(Map<String, dynamic> json) {
    return ConflictInfo(
      ticketId: json['ticket_id'] as String,
      yourValidationId: json['your_validation_id'] as String,
      isFirstScan: json['is_first_scan'] as bool? ?? false,
      firstScanAt: json['first_scan_at'] as String?,
      firstScanDevice: json['first_scan_device'] as String?,
    );
  }
}

/// Bootstrap data for offline operation
class BootstrapData {
  final Map<String, dynamic> event;
  final String eventPublicKey;
  final int keyVersion;
  final Map<String, dynamic> rules;
  final String validatedBloomFilter;
  final int snapshotVersion;
  final List<String> revokedDevices;
  final List<Map<String, dynamic>> trustedDeviceKeys;
  final String serverTime;

  BootstrapData({
    required this.event,
    required this.eventPublicKey,
    required this.keyVersion,
    required this.rules,
    required this.validatedBloomFilter,
    required this.snapshotVersion,
    required this.revokedDevices,
    required this.trustedDeviceKeys,
    required this.serverTime,
  });

  factory BootstrapData.fromJson(Map<String, dynamic> json) {
    return BootstrapData(
      event: json['event'] as Map<String, dynamic>? ?? {},
      eventPublicKey: json['event_public_key'] as String? ?? '',
      keyVersion: json['key_version'] as int? ?? 1,
      rules: json['rules'] as Map<String, dynamic>? ?? {},
      validatedBloomFilter: json['validated_bloom_filter'] as String? ?? '',
      snapshotVersion: json['snapshot_version'] as int? ?? 0,
      revokedDevices: List<String>.from(json['revoked_devices'] as List? ?? []),
      trustedDeviceKeys: List<Map<String, dynamic>>.from(
        json['trusted_device_keys'] as List? ?? [],
      ),
      serverTime: json['server_time'] as String? ?? '',
    );
  }

  int get eventId => event['id'] as int? ?? 0;
  String get eventName => event['name'] as String? ?? '';
}

/// Validated tickets snapshot data
class SnapshotData {
  final int matcheId;
  final String bloomFilter;
  final int snapshotVersion;
  final Map<String, dynamic> stats;
  final String serverTime;

  SnapshotData({
    required this.matcheId,
    required this.bloomFilter,
    required this.snapshotVersion,
    required this.stats,
    required this.serverTime,
  });

  factory SnapshotData.fromJson(Map<String, dynamic> json) {
    return SnapshotData(
      matcheId: json['matche_id'] as int? ?? 0,
      bloomFilter: json['bloom_filter'] as String? ?? '',
      snapshotVersion: json['snapshot_version'] as int? ?? 0,
      stats: json['stats'] as Map<String, dynamic>? ?? {},
      serverTime: json['server_time'] as String? ?? '',
    );
  }
}

/// Match tickets result for offline validation
class MatchTicketsResult {
  final int matchId;
  final List<MatchTicket> tickets;
  final int count;
  final String generatedAt;

  MatchTicketsResult({
    required this.matchId,
    required this.tickets,
    required this.count,
    required this.generatedAt,
  });

  factory MatchTicketsResult.fromJson(Map<String, dynamic> json) {
    return MatchTicketsResult(
      matchId: json['match_id'] as int? ?? 0,
      tickets: (json['tickets'] as List? ?? [])
          .map((e) => MatchTicket.fromJson(e as Map<String, dynamic>))
          .toList(),
      count: json['count'] as int? ?? 0,
      generatedAt: json['generated_at'] as String? ?? '',
    );
  }
}

/// Individual ticket from match tickets list
class MatchTicket {
  final String ticketId;
  final String referenceNo;

  MatchTicket({
    required this.ticketId,
    required this.referenceNo,
  });

  factory MatchTicket.fromJson(Map<String, dynamic> json) {
    return MatchTicket(
      ticketId: json['ticket_id'] as String? ?? '',
      referenceNo: json['reference_no'] as String? ?? '',
    );
  }
}
