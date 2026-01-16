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

  /// Sync offline tickets.
  Future<_PartialSyncResult> _syncTickets() async {
    try {
      final unsyncedTickets = await _db.getUnsyncedTickets();
      if (unsyncedTickets.isEmpty) {
        return _PartialSyncResult(success: true, syncedCount: 0);
      }

      // Transform to API format
      final ticketsPayload = unsyncedTickets.map((ticket) {
        return {
          'tuid': ticket['ticket_id'],
          'matche_id': ticket['matche_id'],
          'ticket_types_id': ticket['ticket_types_id'],
          'payload': ticket['payload'],
          'signature': ticket['signature'],
          'customer_name': ticket['customer_name'],
          'created_at': ticket['created_at'],
        };
      }).toList();

      print('Syncing ${ticketsPayload.length} tickets');
      print(
        'First ticket sample: ${ticketsPayload.isNotEmpty ? ticketsPayload.first : "none"}',
      );

      final result = await _api.syncTickets(ticketsPayload);

      print('Sync result: $result');

      // Mark accepted tickets as synced
      for (final tuid in result.accepted) {
        await _db.markTicketSynced(tuid);
      }

      return _PartialSyncResult(
        success: true,
        syncedCount: result.acceptedCount,
        rejectedCount: result.rejectedCount,
      );
    } catch (e) {
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

      // Transform to API format
      final validationsPayload = unsyncedValidations.map((validation) {
        return {
          'ticket_id': validation['ticket_id'],
          'validated_at': validation['validated_at'],
          'metadata': validation['metadata'],
        };
      }).toList();

      final result = await _api.syncValidations(validationsPayload);

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

      // Notify about conflicts
      if (result.hasConflicts) {
        onConflictsDetected?.call(result.conflicts);
      }

      return _PartialSyncResult(
        success: true,
        syncedCount: result.accepted.length,
        rejectedCount: result.rejected.length,
        conflicts: result.conflicts,
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
