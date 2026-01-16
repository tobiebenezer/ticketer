import 'package:myapp/data/local/database_helper.dart';
import 'package:myapp/data/models/event_model.dart';
import 'package:myapp/data/services/event_api.dart';

/// OfflineEventService - Provides events with cache-first strategy.
///
/// Flow:
/// 1. Try to get events from local cache
/// 2. If cache is empty or stale, fetch from API
/// 3. Update cache with fresh data
/// 4. Return events
///
/// This ensures the app works offline while keeping data fresh when online.
class OfflineEventService {
  final EventApi _eventApi;
  final DatabaseHelper _db;

  OfflineEventService({EventApi? eventApi, DatabaseHelper? db})
    : _eventApi = eventApi ?? EventApi(),
      _db = db ?? DatabaseHelper();

  /// Get events (cache-first)
  ///
  /// Returns cached events if available, otherwise fetches from API
  Future<List<Event>> getEvents({String? status}) async {
    // Try cache first
    final cachedMaps = await _db.getCachedEvents();
    if (cachedMaps.isNotEmpty) {
      // Convert maps to Event objects
      final cachedEvents = cachedMaps
          .map((map) => Event.fromJson(map))
          .toList();

      // Filter by status if requested
      if (status != null) {
        return cachedEvents.where((e) => e.status == status).toList();
      }
      return cachedEvents;
    }

    // Cache is empty, try API
    return await _fetchAndCacheEvents(status: status);
  }

  /// Force refresh from API
  ///
  /// Bypasses cache and fetches fresh data from server
  Future<List<Event>> refreshEvents({String? status}) async {
    return await _fetchAndCacheEvents(status: status);
  }

  /// Fetch from API and update cache
  Future<List<Event>> _fetchAndCacheEvents({String? status}) async {
    try {
      final events = await _eventApi.getEvents(status: status);

      // Update cache
      final eventMaps = events.map((e) => e.toJson()).toList();
      await _db.cacheEventList(eventMaps);

      return events;
    } catch (e) {
      // If API fails and we have cache, return it
      final cachedMaps = await _db.getCachedEvents();
      if (cachedMaps.isNotEmpty) {
        final cachedEvents = cachedMaps
            .map((map) => Event.fromJson(map))
            .toList();
        if (status != null) {
          return cachedEvents.where((e) => e.status == status).toList();
        }
        return cachedEvents;
      }

      // No cache and API failed
      rethrow;
    }
  }

  /// Get event by ID (cache-first)
  Future<Event?> getEventById(int id) async {
    final events = await getEvents();
    try {
      return events.firstWhere((e) => e.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Check if events are cached
  Future<bool> hasCache() async {
    return await _db.hasEventsCached();
  }

  /// Clear event cache
  Future<void> clearCache() async {
    await _db.clearCachedEvents();
  }
}
