import 'package:myapp/data/local/database_helper.dart';
import 'package:myapp/data/models/ticket_type.dart';
import 'package:myapp/data/services/ticket_api.dart';

/// OfflineTicketTypeService - Provides ticket types with cache-first strategy.
///
/// Flow:
/// 1. Try to get ticket types from local cache
/// 2. If cache is empty, fetch from API
/// 3. Update cache with fresh data
/// 4. Return ticket types
///
/// This ensures the app works offline while keeping data fresh when online.
class OfflineTicketTypeService {
  final TicketApi _ticketApi;
  final DatabaseHelper _db;

  OfflineTicketTypeService({TicketApi? ticketApi, DatabaseHelper? db})
    : _ticketApi = ticketApi ?? TicketApi(),
      _db = db ?? DatabaseHelper();

  /// Get ticket types (cache-first)
  ///
  /// Returns cached types if available, otherwise fetches from API
  Future<List<TicketType>> getTicketTypes({int? matchId}) async {
    // Try cache first
    final cachedMaps = await _db.getCachedTicketTypes(matchId: matchId);
    if (cachedMaps.isNotEmpty) {
      // Convert maps to TicketType objects
      return cachedMaps.map((map) => TicketType.fromJson(map)).toList();
    }

    // Cache is empty, try API
    return await _fetchAndCacheTypes(matchId: matchId);
  }

  /// Force refresh from API
  ///
  /// Bypasses cache and fetches fresh data from server
  Future<List<TicketType>> refreshTicketTypes({int? matchId}) async {
    return await _fetchAndCacheTypes(matchId: matchId);
  }

  /// Fetch from API and update cache
  Future<List<TicketType>> _fetchAndCacheTypes({int? matchId}) async {
    try {
      // Fetch from match-specific endpoint if matchId provided
      final types = matchId != null
          // ? await _ticketApi.getTicketTypesForMatch(matchId)
          ? await _ticketApi.getTicketTypes()
          : await _ticketApi.getTicketTypes();

      if (types.isEmpty) {
        // If API returns nothing, don't clear cache yet, maybe it's a temporary error or empty match
        return [];
      }

      // Update cache with match-specific data
      final typeMaps = types.map((t) => t.toJson()).toList();
      await _db.cacheTicketTypes(typeMaps, matchId: matchId);

      return types;
    } catch (e) {
      print('Error fetching ticket types: $e');
      // If API fails and we have cache, return it
      final cachedMaps = await _db.getCachedTicketTypes(matchId: matchId);
      if (cachedMaps.isNotEmpty) {
        return cachedMaps.map((map) => TicketType.fromJson(map)).toList();
      }

      // No cache and API failed
      rethrow;
    }
  }

  /// Get ticket type by ID (cache-first)
  Future<TicketType?> getTicketTypeById(int id) async {
    final types = await getTicketTypes();
    try {
      return types.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Check if ticket types are cached
  Future<bool> hasCache() async {
    return await _db.hasTicketTypesCached();
  }

  /// Clear ticket type cache
  Future<void> clearCache() async {
    await _db.clearCachedTicketTypes();
  }
}
