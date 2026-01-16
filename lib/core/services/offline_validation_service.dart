import 'dart:convert';
import 'package:myapp/core/services/crypto_service.dart';
import 'package:myapp/data/local/database_helper.dart';
import 'package:uuid/uuid.dart';

/// OfflineValidationService - Handles offline ticket validation flow.
///
/// Validation flow (target: <300ms):
/// 1. Decode QR payload
/// 2. Verify signature using cached event public key
/// 3. Check local validated ticket cache
/// 4. Accept/deny entry
/// 5. Store validation record locally
/// 6. Sync when online
class OfflineValidationService {
  final DatabaseHelper _db;
  final CryptoService _crypto;
  final _uuid = const Uuid();

  OfflineValidationService({DatabaseHelper? db, CryptoService? crypto})
    : _db = db ?? DatabaseHelper(),
      _crypto = crypto ?? CryptoService();

  /// Validate a ticket from QR code content.
  ///
  /// This is the main offline validation entry point.
  /// Target response time: <300ms
  Future<ValidationResult> validateTicket({
    required String qrContent,
    required int matcheId,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Get cached event public key
      final eventCache = await _db.getEventCache(matcheId);
      if (eventCache == null) {
        return ValidationResult.error(
          'Event not cached. Please sync first.',
          ValidationStatus.eventNotCached,
        );
      }

      final publicKey = eventCache['event_public_key'] as String?;
      if (publicKey == null || publicKey.isEmpty) {
        return ValidationResult.error(
          'Event public key not available.',
          ValidationStatus.invalidConfig,
        );
      }

      // 2. Parse and verify QR code
      final qrResult = await _crypto.verifyQrCode(
        qrContent: qrContent,
        eventPublicKey: publicKey,
      );

      if (!qrResult.isValid) {
        return ValidationResult.invalid(
          qrResult.errorMessage ?? 'Invalid ticket',
        );
      }

      final ticketId = qrResult.ticketId;
      if (ticketId == null) {
        return ValidationResult.invalid('Ticket ID not found in QR code');
      }

      // 3. Handle pending sync tickets (sold offline on this device)
      if (qrResult.isPendingSync) {
        // Only trust if we have a local record of this ticket
        final localTicket = await _db.getTicketById(ticketId);
        if (localTicket == null) {
          return ValidationResult.invalid(
            'Unsigned ticket from another device. Please sync both devices.',
            details: {'pending_sync': true},
          );
        }
      }

      // 3. Check if ticket matches the event
      if (qrResult.matcheId != matcheId) {
        return ValidationResult.invalid(
          'Ticket is for a different event',
          details: {
            'ticket_event': qrResult.matcheId,
            'current_event': matcheId,
          },
        );
      }

      // 4. Check local validated cache first (fastest - this device's validations)
      final isValidatedLocally = await _db.isTicketValidated(ticketId);
      if (isValidatedLocally) {
        final previousTime = await _db.getValidationTime(ticketId);
        return ValidationResult.alreadyUsed(
          ticketId: ticketId,
          previousValidationTime: previousTime,
        );
      }

      // 5. Check Bloom filter (cross-device validations)
      final bloomFilterBytes = eventCache['bloom_filter'] as List<int>?;

      if (bloomFilterBytes != null && bloomFilterBytes.isNotEmpty) {
        // Check if ticket was validated on another device
        final validatedElsewhere = _checkBloomFilter(
          ticketId,
          bloomFilterBytes,
        );

        if (validatedElsewhere) {
          // Bloom filter indicates this ticket was validated on another device
          // Deny entry to prevent duplicate access
          return ValidationResult.alreadyUsed(
            ticketId: ticketId,
            previousValidationTime:
                null, // Don't know exact time from other device
            details: {'validated_on_other_device': true},
          );
        }
      }

      // 6. Accept entry - add to cache and validation log
      await _acceptEntry(ticketId, qrResult.ticketData!);

      stopwatch.stop();

      return ValidationResult.valid(
        ticketId: ticketId,
        ticketData: qrResult.ticketData!,
        validationTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return ValidationResult.error(
        'Validation error: $e',
        ValidationStatus.systemError,
      );
    }
  }

  /// Check if ticket ID exists in Bloom filter
  bool _checkBloomFilter(String ticketId, List<int> bloomFilterBytes) {
    // Simple Bloom filter implementation
    // Uses multiple hash functions to check membership

    final ticketBytes = ticketId.codeUnits;
    final filterSize = bloomFilterBytes.length * 8; // bits

    // Use 3 hash functions for better accuracy
    for (int i = 0; i < 3; i++) {
      int hash = _hashFunction(ticketBytes, i);
      int bitIndex = hash % filterSize;
      int byteIndex = bitIndex ~/ 8;
      int bitPosition = bitIndex % 8;

      if (byteIndex >= bloomFilterBytes.length) continue;

      // Check if bit is set
      if ((bloomFilterBytes[byteIndex] & (1 << bitPosition)) == 0) {
        return false; // Definitely not in set
      }
    }

    return true; // Probably in set (might be false positive)
  }

  /// Simple hash function for Bloom filter
  int _hashFunction(List<int> data, int seed) {
    int hash = seed;
    for (int byte in data) {
      hash = ((hash << 5) + hash) + byte;
      hash = hash & 0xFFFFFFFF; // Keep it 32-bit
    }
    return hash.abs();
  }

  /// Accept entry for a validated ticket.
  Future<void> _acceptEntry(
    String ticketId,
    Map<String, dynamic> ticketData,
  ) async {
    final now = DateTime.now();
    final validationId = _uuid.v4();

    // Add to validated cache (for quick lookup)
    await _db.addToValidatedCache(ticketId);

    // Add to validation log (for sync)
    await _db.insertValidation(
      id: validationId,
      ticketId: ticketId,
      validatedAt: now,
      metadata: {
        'customer_name': ticketData['customer_name'],
        'ticket_type_id': ticketData['ticket_types_id'],
        'offline': true,
      },
    );
  }

  /// Manually mark a ticket as used (for edge cases).
  Future<void> manuallyMarkUsed(String ticketId) async {
    await _db.addToValidatedCache(ticketId);
    await _db.insertValidation(
      id: _uuid.v4(),
      ticketId: ticketId,
      validatedAt: DateTime.now(),
      metadata: {'manual': true},
    );
  }

  /// Unmark a ticket (admin override).
  /// Note: This only affects local cache, server is source of truth.
  Future<void> unmarkTicket(String ticketId) async {
    // We don't delete from cache, but could add a revoked flag
    // For now, this is a no-op as we maintain audit trail
  }

  /// Check if event is ready for offline validation.
  Future<bool> isEventReady(int matcheId) async {
    return await _db.isEventCached(matcheId);
  }

  /// Get event info from cache.
  Future<CachedEventInfo?> getEventInfo(int matcheId) async {
    final cache = await _db.getEventCache(matcheId);
    if (cache == null) return null;

    return CachedEventInfo(
      matcheId: matcheId,
      eventName: cache['event_name'] as String? ?? '',
      keyVersion: cache['key_version'] as int? ?? 1,
      snapshotVersion: cache['snapshot_version'] as int? ?? 0,
      cachedAt: DateTime.parse(cache['cached_at'] as String),
    );
  }

  /// Get validation statistics for this session.
  Future<ValidationStats> getValidationStats() async {
    final stats = await _db.getSyncStats();
    return ValidationStats(
      totalValidated: stats['validated_tickets'] ?? 0,
      unsyncedValidations: stats['unsynced_validations'] ?? 0,
      cachedEvents: stats['cached_events'] ?? 0,
    );
  }
}

// ==================== RESULT CLASSES ====================

/// Status of validation attempt
enum ValidationStatus {
  valid, // Entry granted
  invalid, // Invalid ticket (signature, format)
  alreadyUsed, // Already validated
  eventNotCached, // Need to sync event first
  invalidConfig, // Missing configuration
  systemError, // System error
}

/// Result of ticket validation
class ValidationResult {
  final ValidationStatus status;
  final bool isSuccess;
  final String message;
  final String? ticketId;
  final Map<String, dynamic>? ticketData;
  final Map<String, dynamic>? details;
  final DateTime? previousValidationTime;
  final int? validationTimeMs;

  ValidationResult._({
    required this.status,
    required this.isSuccess,
    required this.message,
    this.ticketId,
    this.ticketData,
    this.details,
    this.previousValidationTime,
    this.validationTimeMs,
  });

  factory ValidationResult.valid({
    required String ticketId,
    required Map<String, dynamic> ticketData,
    int? validationTimeMs,
  }) {
    return ValidationResult._(
      status: ValidationStatus.valid,
      isSuccess: true,
      message: 'Entry granted',
      ticketId: ticketId,
      ticketData: ticketData,
      validationTimeMs: validationTimeMs,
    );
  }

  factory ValidationResult.invalid(
    String reason, {
    Map<String, dynamic>? details,
  }) {
    return ValidationResult._(
      status: ValidationStatus.invalid,
      isSuccess: false,
      message: reason,
      details: details,
    );
  }

  factory ValidationResult.alreadyUsed({
    required String ticketId,
    DateTime? previousValidationTime,
    Map<String, dynamic>? details,
  }) {
    return ValidationResult._(
      status: ValidationStatus.alreadyUsed,
      isSuccess: false,
      message: 'Ticket already used',
      ticketId: ticketId,
      previousValidationTime: previousValidationTime,
      details: details,
    );
  }

  factory ValidationResult.error(String message, ValidationStatus status) {
    return ValidationResult._(
      status: status,
      isSuccess: false,
      message: message,
    );
  }

  /// Get customer name from ticket data
  String? get customerName => ticketData?['customer_name'] as String?;

  /// Check if this is a "already used" result
  bool get isAlreadyUsed => status == ValidationStatus.alreadyUsed;

  /// Check if this needs event sync
  bool get needsEventSync => status == ValidationStatus.eventNotCached;
}

/// Cached event information
class CachedEventInfo {
  final int matcheId;
  final String eventName;
  final int keyVersion;
  final int snapshotVersion;
  final DateTime cachedAt;

  CachedEventInfo({
    required this.matcheId,
    required this.eventName,
    required this.keyVersion,
    required this.snapshotVersion,
    required this.cachedAt,
  });

  /// Check if cache is stale (older than 1 hour)
  bool get isStale => DateTime.now().difference(cachedAt).inHours > 1;
}

/// Validation statistics
class ValidationStats {
  final int totalValidated;
  final int unsyncedValidations;
  final int cachedEvents;

  ValidationStats({
    required this.totalValidated,
    required this.unsyncedValidations,
    required this.cachedEvents,
  });

  bool get hasPendingSync => unsyncedValidations > 0;
}
