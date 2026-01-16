import 'package:myapp/data/local/database_helper.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/models/ticket_type.dart';
import 'package:myapp/data/services/event_api.dart';
import 'package:myapp/data/services/ticket_api.dart';
import 'package:myapp/data/services/sync_service.dart';

/// PostLoginSyncService - Orchestrates all post-login data caching.
///
/// This service runs after successful login to cache:
/// - Event list
/// - Ticket types
/// - Event bootstrap data (for active events)
///
/// Ensures the app works fully offline after initial login.
class PostLoginSyncService {
  final EventApi _eventApi;
  final TicketApi _ticketApi;
  final SyncService _syncService;
  final DatabaseHelper _db;

  PostLoginSyncService({
    EventApi? eventApi,
    TicketApi? ticketApi,
    SyncService? syncService,
    DatabaseHelper? db,
  }) : _eventApi = eventApi ?? EventApi(),
       _ticketApi = ticketApi ?? TicketApi(),
       _syncService = syncService ?? SyncService(),
       _db = db ?? DatabaseHelper();

  /// Run all post-login sync operations
  ///
  /// Returns result with counts of synced items
  Future<PostLoginSyncResult> syncAfterLogin() async {
    try {
      // 1. Fetch and cache event list
      final events = await _cacheEventList();

      // 2. Fetch and cache ticket types
      final ticketTypes = await _cacheTicketTypes();

      // 3. Bootstrap active/upcoming events
      final bootstrapped = await _bootstrapActiveEvents(events);

      return PostLoginSyncResult.success(
        eventCount: events.length,
        ticketTypeCount: ticketTypes.length,
        bootstrappedCount: bootstrapped,
      );
    } catch (e) {
      return PostLoginSyncResult.error(e.toString());
    }
  }

  /// Cache event list from API
  Future<List<Event>> _cacheEventList() async {
    try {
      // Fetch all events (don't filter by status - let user see all)
      final events = await _eventApi.getEvents();

      // Convert to map for database storage
      final eventMaps = events.map((e) => e.toJson()).toList();
      await _db.cacheEventList(eventMaps);

      return events;
    } catch (e) {
      print('Error caching events: $e');
      // If API fails, return empty list (will use cached data if available)
      return [];
    }
  }

  /// Cache ticket types from API
  Future<List<TicketType>> _cacheTicketTypes() async {
    try {
      final types = await _ticketApi.getTicketTypes();

      if (types.isNotEmpty) {
        // Clear all cached types first to ensure fresh data after login
        await _db.clearCachedTicketTypes();

        // Convert to map for database storage (global cache for now)
        final typeMaps = types.map((t) => t.toJson()).toList();
        await _db.cacheTicketTypes(typeMaps);
      }

      return types;
    } catch (e) {
      // If API fails, return empty list
      return [];
    }
  }

  /// Bootstrap active events for offline validation
  ///
  /// Only bootstraps events that are active or upcoming
  Future<int> _bootstrapActiveEvents(List<Event> events) async {
    int count = 0;

    // Filter to active/upcoming events
    final now = DateTime.now();
    final activeEvents = events.where((event) {
      // Only bootstrap if event is today or in the future
      return event.matchDateParsed.isAfter(
        now.subtract(const Duration(days: 1)),
      );
    }).toList();

    // Bootstrap each event (limit to 5 to avoid long wait)
    final eventsToBootstrap = activeEvents.take(5);

    for (final event in eventsToBootstrap) {
      try {
        final success = await _syncService.bootstrapEvent(event.id);
        if (success) {
          count++;
        }
      } catch (e) {
        // Log but continue with other events
        print('Failed to bootstrap event ${event.id}: $e');
      }
    }

    return count;
  }

  /// Check if initial sync is needed
  ///
  /// Returns true if no cached data exists
  Future<bool> needsInitialSync() async {
    final hasEvents = await _db.hasEventsCached();
    final hasTypes = await _db.hasTicketTypesCached();
    return !hasEvents || !hasTypes;
  }

  /// Get sync status
  Future<SyncStatus> getSyncStatus() async {
    final hasEvents = await _db.hasEventsCached();
    final hasTypes = await _db.hasTicketTypesCached();
    final stats = await _db.getSyncStats();

    return SyncStatus(
      hasEventsCached: hasEvents,
      hasTicketTypesCached: hasTypes,
      cachedEventCount: stats['cached_events'] ?? 0,
      unsyncedTickets: stats['unsynced_tickets'] ?? 0,
      unsyncedValidations: stats['unsynced_validations'] ?? 0,
    );
  }
}

// ==================== RESULT CLASSES ====================

/// Result of post-login sync
class PostLoginSyncResult {
  final bool isSuccess;
  final int eventCount;
  final int ticketTypeCount;
  final int bootstrappedCount;
  final String? errorMessage;

  PostLoginSyncResult._({
    required this.isSuccess,
    this.eventCount = 0,
    this.ticketTypeCount = 0,
    this.bootstrappedCount = 0,
    this.errorMessage,
  });

  factory PostLoginSyncResult.success({
    required int eventCount,
    required int ticketTypeCount,
    required int bootstrappedCount,
  }) {
    return PostLoginSyncResult._(
      isSuccess: true,
      eventCount: eventCount,
      ticketTypeCount: ticketTypeCount,
      bootstrappedCount: bootstrappedCount,
    );
  }

  factory PostLoginSyncResult.error(String message) {
    return PostLoginSyncResult._(isSuccess: false, errorMessage: message);
  }

  String get summary {
    if (!isSuccess) {
      return 'Sync failed: $errorMessage';
    }
    return '$eventCount events, $ticketTypeCount ticket types, '
        '$bootstrappedCount bootstrapped';
  }
}

/// Sync status information
class SyncStatus {
  final bool hasEventsCached;
  final bool hasTicketTypesCached;
  final int cachedEventCount;
  final int unsyncedTickets;
  final int unsyncedValidations;

  SyncStatus({
    required this.hasEventsCached,
    required this.hasTicketTypesCached,
    required this.cachedEventCount,
    required this.unsyncedTickets,
    required this.unsyncedValidations,
  });

  bool get isFullyCached => hasEventsCached && hasTicketTypesCached;
  bool get hasPendingSync => unsyncedTickets > 0 || unsyncedValidations > 0;
}
