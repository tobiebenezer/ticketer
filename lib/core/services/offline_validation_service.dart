import 'dart:convert';
import 'package:myapp/core/services/crypto_service.dart';
import 'package:myapp/core/services/device_crypto_service.dart';
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
  final DeviceCryptoService _deviceCrypto;
  final _uuid = const Uuid();

  OfflineValidationService({
    DatabaseHelper? db,
    CryptoService? crypto,
    DeviceCryptoService? deviceCrypto,
  }) : _db = db ?? DatabaseHelper(),
       _crypto = crypto ?? CryptoService(),
       _deviceCrypto = deviceCrypto ?? DeviceCryptoService();

  /// Validate a ticket from QR code content.
  ///
  /// This is the main offline validation entry point.
  /// Target response time: <300ms
  ///
  /// Supports multiple QR formats:
  /// - Crypto JSON: Full signature verification
  /// - URL/Plain: Requires local ticket record or online verification
  Future<ValidationResult> validateTicket({
    required String qrContent,
    required int matcheId,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Get cached event data (optional - we can still validate without it)
      final eventCache = await _db.getEventCache(matcheId);
      final publicKey = eventCache?['event_public_key'] as String?;

      // 2. Get this device's public key for same-device validation
      final deviceKeys = await _deviceCrypto.ensureKeyPair();
      final thisDevicePublicKey = deviceKeys.publicKeyBase64;

      // 3. Build trusted device keys map (include this device)
      Map<String, String> trustedDevicePublicKeys = {};
      try {
        final raw = eventCache?['trusted_device_keys'] as String?;
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as List<dynamic>;
          trustedDevicePublicKeys = <String, String>{
            for (final item in decoded)
              if (item is Map)
                (item['device_uid']?.toString() ?? ''):
                    (item['public_key']?.toString() ?? ''),
          }..removeWhere((k, v) => k.isEmpty || v.isEmpty);
        }
      } catch (_) {}

      Set<String>? revokedDeviceUids;
      try {
        final raw = eventCache?['revoked_devices'] as String?;
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as List<dynamic>;
          revokedDeviceUids = decoded.map((e) => e.toString()).toSet();
        }
      } catch (_) {}

      // 4. Try to parse and extract ticket data from QR
      String? ticketId;
      Map<String, dynamic>? ticketData;
      bool signatureValid = false;
      int? ticketMatcheId;

      // Try parsing as crypto JSON first
      try {
        final qrData = jsonDecode(qrContent) as Map<String, dynamic>;
        final payload = qrData['payload'] as String?;
        final signature = qrData['signature'] as String?;

        if (payload != null && signature != null) {
          ticketData = jsonDecode(payload) as Map<String, dynamic>;
          ticketId = ticketData['tuid'] as String?;
          ticketMatcheId = ticketData['matche_id'] as int?;

          final issuerType = ticketData['issuer_type'] as String?;
          final issuerDeviceUid = ticketData['issuer_device_uid'] as String?;

          // Check if device is revoked
          if (issuerDeviceUid != null &&
              revokedDeviceUids != null &&
              revokedDeviceUids.contains(issuerDeviceUid)) {
            return ValidationResult.invalid('Issuer device has been revoked');
          }

          // Try to verify signature with appropriate key
          String? verificationKey;

          if (issuerType == 'device' && issuerDeviceUid != null) {
            // Device-issued ticket - try device's public key
            verificationKey = trustedDevicePublicKeys[issuerDeviceUid];

            // If not in trusted list, check if it matches THIS device's key
            if (verificationKey == null) {
              // Try verifying with this device's public key (same-device validation)
              signatureValid = await _crypto.verifySignature(
                payload: payload,
                signatureBase64: signature,
                publicKeyBase64: thisDevicePublicKey,
              );
            }
          }

          // If we have a verification key from trusted list, use it
          if (!signatureValid && verificationKey != null) {
            signatureValid = await _crypto.verifySignature(
              payload: payload,
              signatureBase64: signature,
              publicKeyBase64: verificationKey,
            );
          }

          // Try event public key as fallback (server-issued tickets)
          if (!signatureValid && publicKey != null && publicKey.isNotEmpty) {
            signatureValid = await _crypto.verifySignature(
              payload: payload,
              signatureBase64: signature,
              publicKeyBase64: publicKey,
            );
          }
        }
      } catch (_) {
        // Not crypto JSON - try URL/plain format
      }

      // If not crypto format, try URL/plain format
      if (ticketId == null) {
        // Try URL format
        final urlPatterns = [
          RegExp(r'/ticket/validate/([a-f0-9\-]{36})', caseSensitive: false),
          RegExp(r'/validate/([a-f0-9\-]{36})', caseSensitive: false),
          RegExp(r'^([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$', caseSensitive: false),
        ];

        for (final pattern in urlPatterns) {
          final match = pattern.firstMatch(qrContent);
          if (match != null) {
            ticketId = match.group(1) ?? match.group(0);
            break;
          }
        }

        // Plain reference fallback
        if (ticketId == null && qrContent.length >= 8) {
          ticketId = qrContent.trim();
        }
      }

      if (ticketId == null || ticketId.isEmpty) {
        return ValidationResult.invalid('Could not extract ticket ID from QR code');
      }

      // 5. Check if already validated on THIS device
      final isValidatedLocally = await _db.isTicketValidated(ticketId);
      if (isValidatedLocally) {
        final previousTime = await _db.getValidationTime(ticketId);
        return ValidationResult.alreadyUsed(
          ticketId: ticketId,
          previousValidationTime: previousTime,
        );
      }

      // 6. For crypto tickets with valid signature - trust it even if not in local DB
      if (ticketData != null && signatureValid) {
        // Signature is valid - ticket is authentic, proceed with validation
        // No need to check local database
      } else if (ticketData != null && !signatureValid) {
        // Signature verification failed - check if we have local record as fallback
        final localTicket = await _db.getTicketById(ticketId);
        if (localTicket != null) {
          // We have a local record - trust it (same device created it)
          ticketData = localTicket;
          signatureValid = true;
        } else {
          return ValidationResult.invalid(
            'Invalid signature. Ticket may be from an unsynced device.',
          );
        }
      }

      // 7. For non-crypto tickets (URL/plain format), check local database
      if (ticketData == null) {
        final localTicket = await _db.getTicketById(ticketId);
        if (localTicket != null) {
          ticketData = localTicket;
          ticketMatcheId = localTicket['matche_id'] as int?;
        } else {
          // No local record and no crypto signature - cannot validate offline
          return ValidationResult.error(
            'Non-crypto ticket not found locally. Cannot validate offline.',
            ValidationStatus.systemError,
            details: {'requires_online': true, 'ticket_id': ticketId},
          );
        }
      }

      // 8. Verify ticket is for the correct event
      if (ticketMatcheId != null && ticketMatcheId != matcheId) {
        return ValidationResult.invalid(
          'Ticket is for a different event',
          details: {'ticket_event': ticketMatcheId, 'current_event': matcheId},
        );
      }

      // 9. Bloom filter check (informational only - don't block validation)
      bool possiblyValidatedElsewhere = false;
      final bloomFilterBytes = eventCache?['bloom_filter'] as List<int>?;
      if (bloomFilterBytes != null && bloomFilterBytes.isNotEmpty) {
        possiblyValidatedElsewhere = _checkBloomFilter(ticketId, bloomFilterBytes);
      }

      // 10. Accept entry - save validation record for syncing
      await _acceptEntry(ticketId, ticketData);

      stopwatch.stop();

      return ValidationResult.valid(
        ticketId: ticketId,
        ticketData: ticketData,
        validationTimeMs: stopwatch.elapsedMilliseconds,
        details: possiblyValidatedElsewhere
            ? {'warning': 'May have been validated on another device'}
            : null,
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
    Map<String, dynamic>? details,
  }) {
    return ValidationResult._(
      status: ValidationStatus.valid,
      isSuccess: true,
      message: 'Entry granted',
      ticketId: ticketId,
      ticketData: ticketData,
      validationTimeMs: validationTimeMs,
      details: details,
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

  factory ValidationResult.error(
    String message,
    ValidationStatus status, {
    Map<String, dynamic>? details,
  }) {
    return ValidationResult._(
      status: status,
      isSuccess: false,
      message: message,
      details: details,
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
