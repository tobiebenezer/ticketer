import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:myapp/core/services/app_settings_service.dart';
import 'package:myapp/data/local/database_helper.dart';
import 'package:myapp/data/services/sync_api.dart';

/// SyncService - Manages offline data synchronization.
///
/// Responsibilities:
/// - Monitor connectivity and trigger sync when online
/// - Sync offline tickets to server
/// - Sync validation logs to server
/// - Pull validation snapshots from server
/// - Handle conflict resolution
/// - Periodic background sync (every 5 minutes)
class SyncService {
  final DatabaseHelper _db;
  final SyncApi _api;
  final AppSettingsService _settings;
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicSyncTimer;
  bool _isSyncing = false;
  bool _isInitialized = false;

  // Callbacks for UI updates
  Function(SyncStatus)? onSyncStatusChanged;
  Function(int, int)? onSyncProgress; // (completed, total)
  Function(List<ConflictInfo>)? onConflictsDetected;

  SyncService({DatabaseHelper? db, SyncApi? api, AppSettingsService? settings})
    : _db = db ?? DatabaseHelper(),
      _api = api ?? SyncApi(),
      _settings = settings ?? AppSettingsService();

  /// Initialize sync service and start listening for connectivity changes.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Check if auto-sync is enabled
    final autoSyncEnabled = await _settings.getAutoSyncEnabled();
    if (!autoSyncEnabled) {
      print('Auto-sync is disabled. Skipping initialization.');
      return;
    }

    // Listen for connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    // Set up periodic sync (every 5 minutes)
    _periodicSyncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _periodicSync(),
    );

    _isInitialized = true;
    print('SyncService initialized with auto-sync enabled');

    // Do initial sync if online
    final online = await isOnline();
    if (online) {
      syncAll();
    }
  }

  /// Dispose resources.
  void dispose() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
    _isInitialized = false;
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    // Check if auto-sync is still enabled
    final autoSyncEnabled = await _settings.getAutoSyncEnabled();
    if (!autoSyncEnabled) return;

    // Check if we have internet (WiFi or mobile data)
    final hasInternet = results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet,
    );

    if (hasInternet && !_isSyncing) {
      print('Connection restored. Auto-syncing...');
      syncAll();
    }
  }

  Future<void> _periodicSync() async {
    // Check if auto-sync is still enabled
    final autoSyncEnabled = await _settings.getAutoSyncEnabled();
    if (!autoSyncEnabled) return;

    final online = await isOnline();
    if (online && !_isSyncing) {
      print('Periodic sync triggered');
      syncAll();
    }
  }

  /// Check if currently online
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet,
    );
  }

  /// Sync all pending data.
  Future<SyncResult> syncAll() async {
    if (_isSyncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    _isSyncing = true;
    onSyncStatusChanged?.call(SyncStatus.syncing);

    try {
      // 1. Push local data to server
      final ticketResult = await _syncTickets();
      final validationResult = await _syncValidations();

      // 2. Pull validated snapshots for cached events
      await _updateCachedEventSnapshots();

      final success = ticketResult.success && validationResult.success;
      final message = success
          ? 'Synced ${ticketResult.syncedCount} tickets, ${validationResult.syncedCount} validations'
          : ticketResult.message ?? validationResult.message ?? 'Sync failed';

      onSyncStatusChanged?.call(
        success ? SyncStatus.completed : SyncStatus.failed,
      );
      print('Sync completed: $message');

      return SyncResult(
        success: success,
        message: message,
        ticketsSynced: ticketResult.syncedCount,
        validationsSynced: validationResult.syncedCount,
        conflicts: validationResult.conflicts,
      );
    } catch (e) {
      onSyncStatusChanged?.call(SyncStatus.failed);
      print('Sync error: $e');
      return SyncResult(success: false, message: 'Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Update validation snapshots for all cached events
  Future<void> _updateCachedEventSnapshots() async {
    try {
      final cachedEvents = await _db.getAllCachedEvents();
      for (final event in cachedEvents) {
        final matcheId = event['matche_id'] as int?;
        if (matcheId != null) {
          await updateSnapshot(matcheId).catchError((e) {
            print('Failed to update snapshot for match $matcheId: $e');
            return false; // Return false on error
          });
        }
      }
    } catch (e) {
      print('Error updating cached event snapshots: $e');
    }
  }

  /// Sync offline tickets in batches to avoid 413 errors.
  Future<_PartialSyncResult> _syncTickets() async {
    try {
      final unsyncedTickets = await _db.getUnsyncedTicketsReadyForSync();
      if (unsyncedTickets.isEmpty) {
        return _PartialSyncResult(success: true, syncedCount: 0);
      }

      // Transform and sanitize to API format
      final ticketsPayload = <Map<String, dynamic>>[];
      final skippedTickets = <String>[];

      for (final ticket in unsyncedTickets) {
        final tuid = ticket['ticket_id']?.toString();
        final matcheId = ticket['matche_id'];
        final ticketTypesId = ticket['ticket_types_id'];
        final payload = ticket['payload']?.toString();
        final createdAt = ticket['created_at']?.toString();

        // Validate required fields
        if (tuid == null || tuid.isEmpty) {
          print('Skipping ticket: missing tuid');
          skippedTickets.add('unknown-missing-tuid');
          continue;
        }

        // Validate UUID format (8-4-4-4-12 pattern)
        final uuidRegex = RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        );
        if (!uuidRegex.hasMatch(tuid)) {
          print('Skipping ticket $tuid: invalid UUID format');
          skippedTickets.add(tuid);
          continue;
        }

        if (matcheId == null) {
          print('Skipping ticket $tuid: missing matche_id');
          skippedTickets.add(tuid);
          continue;
        }

        if (ticketTypesId == null) {
          print('Skipping ticket $tuid: missing ticket_types_id');
          skippedTickets.add(tuid);
          continue;
        }

        if (payload == null || payload.isEmpty) {
          print('Skipping ticket $tuid: missing payload');
          skippedTickets.add(tuid);
          continue;
        }

        if (createdAt == null || createdAt.isEmpty) {
          print('Skipping ticket $tuid: missing created_at');
          skippedTickets.add(tuid);
          continue;
        }

        // Build sanitized payload
        ticketsPayload.add({
          'tuid': tuid,
          'matche_id': matcheId is int
              ? matcheId
              : int.tryParse(matcheId.toString()) ?? 0,
          'ticket_types_id': ticketTypesId is int
              ? ticketTypesId
              : int.tryParse(ticketTypesId.toString()) ?? 0,
          'payload': payload,
          'signature': ticket['signature']?.toString() ?? '',
          'customer_name': ticket['customer_name']?.toString(),
          'created_at': createdAt,
        });
      }

      if (ticketsPayload.isEmpty) {
        print('No valid tickets to sync (${skippedTickets.length} skipped)');
        return _PartialSyncResult(success: true, syncedCount: 0);
      }

      print(
        'Syncing ${ticketsPayload.length} tickets (${skippedTickets.length} skipped)',
      );

      // Send in batches of 50 to avoid 413 errors
      const batchSize = 50;
      int totalAccepted = 0;
      int totalRejected = 0;
      final List<String> failedBatches = [];

      for (int i = 0; i < ticketsPayload.length; i += batchSize) {
        final end = (i + batchSize < ticketsPayload.length)
            ? i + batchSize
            : ticketsPayload.length;
        final batch = ticketsPayload.sublist(i, end);

        final batchNumber = (i ~/ batchSize) + 1;
        final totalBatches = (ticketsPayload.length / batchSize).ceil();

        print(
          'Sending batch $batchNumber/$totalBatches (${batch.length} tickets)',
        );

        try {
          final result = await _api.syncTickets(batch);

          print(
            'Batch $batchNumber result: ${result.acceptedCount} accepted, ${result.rejectedCount} rejected',
          );

          totalAccepted += result.acceptedCount;
          totalRejected += result.rejectedCount;

          // Mark accepted tickets as synced
          for (final tuid in result.accepted) {
            await _db.markTicketSynced(tuid);
          }

          // Small delay between batches to avoid overwhelming server
          if (i + batchSize < ticketsPayload.length) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          print('Batch $batchNumber failed: $e');
          failedBatches.add('Batch $batchNumber (${batch.length} tickets)');

          // Continue with next batch instead of failing completely
          continue;
        }
      }

      print(
        'Total sync result: $totalAccepted accepted, $totalRejected rejected',
      );
      if (failedBatches.isNotEmpty) {
        print('Failed batches: ${failedBatches.join(", ")}');
      }

      return _PartialSyncResult(
        success: failedBatches.isEmpty,
        syncedCount: totalAccepted,
        rejectedCount: totalRejected,
        message: failedBatches.isNotEmpty
            ? 'Some batches failed: ${failedBatches.join(", ")}'
            : null,
      );
    } catch (e) {
      print('Ticket sync error: $e');
      return _PartialSyncResult(
        success: false,
        message: 'Ticket sync error: $e',
      );
    }
  }

  /// Sync validation logs.
  Future<_PartialSyncResult> _syncValidations() async {
    try {
      final unsyncedValidations = await _db.getUnsyncedValidations();
      if (unsyncedValidations.isEmpty) {
        return _PartialSyncResult(success: true, syncedCount: 0);
      }

      // Transform and sanitize to API format
      final validationsPayload = <Map<String, dynamic>>[];
      final skippedValidations = <String>[];

      for (final validation in unsyncedValidations) {
        final ticketId = validation['ticket_id']?.toString();
        final validatedAt = validation['validated_at']?.toString();

        // Validate required fields
        if (ticketId == null || ticketId.isEmpty) {
          print('Skipping validation: missing ticket_id');
          skippedValidations.add('unknown-missing-ticket_id');
          continue;
        }

        if (validatedAt == null || validatedAt.isEmpty) {
          print('Skipping validation for $ticketId: missing validated_at');
          skippedValidations.add(ticketId);
          continue;
        }

        // Parse metadata from JSON string to object
        Map<String, dynamic>? metadata;
        final metadataStr = validation['metadata'];
        if (metadataStr != null &&
            metadataStr is String &&
            metadataStr.isNotEmpty) {
          try {
            final decoded = jsonDecode(metadataStr);
            // Ensure metadata is a Map, not other types
            if (decoded is Map<String, dynamic>) {
              metadata = decoded;
            } else if (decoded is Map) {
              metadata = Map<String, dynamic>.from(decoded);
            }
          } catch (e) {
            print('Failed to parse metadata for $ticketId: $e');
            metadata = null;
          }
        }

        validationsPayload.add({
          'ticket_id': ticketId,
          'validated_at': validatedAt,
          'metadata': metadata,
        });
      }

      if (validationsPayload.isEmpty) {
        print(
          'No valid validations to sync (${skippedValidations.length} skipped)',
        );
        return _PartialSyncResult(success: true, syncedCount: 0);
      }

      print(
        'Syncing ${validationsPayload.length} validations (${skippedValidations.length} skipped)',
      );

      // Send in batches of 100 to avoid 413 errors
      const batchSize = 100;
      int totalAccepted = 0;
      final List<String> failedBatches = [];
      final List<ConflictInfo> allConflicts = [];

      for (int i = 0; i < validationsPayload.length; i += batchSize) {
        final end = (i + batchSize < validationsPayload.length)
            ? i + batchSize
            : validationsPayload.length;
        final batch = validationsPayload.sublist(i, end);

        final batchNumber = (i ~/ batchSize) + 1;
        final totalBatches = (validationsPayload.length / batchSize).ceil();

        print(
          'Sending validation batch $batchNumber/$totalBatches (${batch.length} validations)',
        );

        try {
          final result = await _api.syncValidations(batch);

          print(
            'Validation batch $batchNumber result: ${result.accepted.length} accepted',
          );

          totalAccepted += result.accepted.length;
          allConflicts.addAll(result.conflicts);

          // Mark validations as synced with conflict info
          for (final accepted in result.accepted) {
            // Find if this validation has conflict info
            final conflictInfo = result.conflicts.firstWhere(
              (c) => c.ticketId == accepted.ticketId,
              orElse: () => ConflictInfo(
                ticketId: accepted.ticketId,
                yourValidationId: accepted.validationId,
                isFirstScan: true,
              ),
            );

            // Find local validation ID
            final localValidation = unsyncedValidations.firstWhere(
              (v) => v['ticket_id'] == accepted.ticketId,
              orElse: () => <String, dynamic>{},
            );

            if (localValidation.isNotEmpty) {
              await _db.markValidationSynced(
                localValidation['id'] as String,
                isFirstScan: conflictInfo.isFirstScan,
                conflict: !conflictInfo.isFirstScan,
              );
            }
          }

          // Small delay between batches to avoid overwhelming server
          if (i + batchSize < validationsPayload.length) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          print('Validation batch $batchNumber failed: $e');
          failedBatches.add('Batch $batchNumber (${batch.length} validations)');

          // Continue with next batch instead of failing completely
          continue;
        }
      }

      print('Total validation sync result: $totalAccepted accepted');
      if (failedBatches.isNotEmpty) {
        print('Failed validation batches: ${failedBatches.join(", ")}');
      }

      // Notify about conflicts
      if (allConflicts.isNotEmpty) {
        onConflictsDetected?.call(allConflicts);
      }

      return _PartialSyncResult(
        success: failedBatches.isEmpty,
        syncedCount: totalAccepted,
        message: failedBatches.isNotEmpty
            ? 'Some batches failed: ${failedBatches.join(", ")}'
            : null,
      );
    } catch (e) {
      return _PartialSyncResult(
        success: false,
        message: 'Validation sync error: $e',
      );
    }
  }

  /// Bootstrap event data for offline validation.
  Future<bool> bootstrapEvent(int matcheId) async {
    try {
      final bootstrap = await _api.getBootstrap(matcheId);

      // Decode bloom filter if present
      List<int>? bloomFilterBytes;
      if (bootstrap.validatedBloomFilter.isNotEmpty) {
        bloomFilterBytes = base64Decode(bootstrap.validatedBloomFilter);
      }

      // Cache event data
      await _db.cacheEvent(
        matcheId: matcheId,
        eventName: bootstrap.eventName,
        eventPublicKey: bootstrap.eventPublicKey,
        keyVersion: bootstrap.keyVersion,
        bloomFilter: bloomFilterBytes,
        snapshotVersion: bootstrap.snapshotVersion,
        rules: bootstrap.rules,
        trustedDeviceKeys: bootstrap.trustedDeviceKeys,
        revokedDevices: bootstrap.revokedDevices,
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Update validation snapshot for an event.
  Future<bool> updateSnapshot(int matcheId) async {
    try {
      final snapshot = await _api.getValidatedSnapshot(matcheId);

      List<int>? bloomFilterBytes;
      if (snapshot.bloomFilter.isNotEmpty) {
        bloomFilterBytes = base64Decode(snapshot.bloomFilter);
      }

      if (bloomFilterBytes != null) {
        await _db.updateBloomFilter(
          matcheId,
          bloomFilterBytes,
          snapshot.snapshotVersion,
        );
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get sync statistics.
  Future<Map<String, int>> getSyncStats() async {
    return await _db.getSyncStats();
  }

  /// Force sync now.
  Future<SyncResult> syncNow() async {
    final online = await isOnline();
    if (!online) {
      return SyncResult(success: false, message: 'No internet connection');
    }
    return await syncAll();
  }
}

// ==================== HELPER CLASSES ====================

/// Sync status enum
enum SyncStatus { idle, syncing, completed, failed }

/// Result of a full sync operation
class SyncResult {
  final bool success;
  final String? message;
  final int ticketsSynced;
  final int validationsSynced;
  final List<ConflictInfo> conflicts;

  SyncResult({
    required this.success,
    this.message,
    this.ticketsSynced = 0,
    this.validationsSynced = 0,
    this.conflicts = const [],
  });

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Internal partial sync result
class _PartialSyncResult {
  final bool success;
  final String? message;
  final int syncedCount;
  final int rejectedCount;
  final List<ConflictInfo> conflicts;

  _PartialSyncResult({
    required this.success,
    this.message,
    this.syncedCount = 0,
    this.rejectedCount = 0,
    this.conflicts = const [],
  });
}
