import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// DatabaseHelper - Manages SQLite database for offline ticket operations.
///
/// Tables:
/// - local_tickets: Offline-created tickets pending sync
/// - local_validations: Offline validation logs pending sync
/// - validated_ticket_cache: Local cache of validated ticket IDs
/// - event_cache: Cached event data for offline validation
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'offline_tickets.db');

    return await openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Local tickets table (offline sales)
    await db.execute('''
      CREATE TABLE local_tickets (
        ticket_id TEXT PRIMARY KEY,
        matche_id INTEGER NOT NULL,
        ticket_types_id INTEGER NOT NULL,
        customer_name TEXT,
        amount REAL NOT NULL,
        payload TEXT NOT NULL,
        signature TEXT NOT NULL,
        status TEXT DEFAULT 'sold',
        created_at TEXT NOT NULL,
        synced_at TEXT
      )
    ''');

    // Local validations table
    await db.execute('''
      CREATE TABLE local_validations (
        id TEXT PRIMARY KEY,
        ticket_id TEXT NOT NULL,
        validated_at TEXT NOT NULL,
        synced INTEGER DEFAULT 0,
        conflict INTEGER DEFAULT 0,
        is_first_scan INTEGER DEFAULT 0,
        metadata TEXT,
        FOREIGN KEY (ticket_id) REFERENCES local_tickets (ticket_id)
      )
    ''');

    // Validated ticket cache (quick lookup)
    await db.execute('''
      CREATE TABLE validated_ticket_cache (
        ticket_id TEXT PRIMARY KEY,
        validated_at TEXT NOT NULL
      )
    ''');

    // Event cache for offline operations
    await db.execute('''
      CREATE TABLE event_cache (
        matche_id INTEGER PRIMARY KEY,
        event_name TEXT,
        event_public_key TEXT NOT NULL,
        key_version INTEGER DEFAULT 1,
        bloom_filter BLOB,
        snapshot_version INTEGER DEFAULT 0,
        rules TEXT,
        trusted_device_keys TEXT,
        revoked_devices TEXT,
        cached_at TEXT NOT NULL
      )
    ''');

    // Cached events table (for offline event list)
    await db.execute('''
      CREATE TABLE cached_events (
        id INTEGER PRIMARY KEY,
        user_id INTEGER,
        season TEXT,
        home_team TEXT,
        away_team TEXT,
        venue TEXT,
        stadium_capacity INTEGER,
        match_date TEXT,
        competition TEXT,
        match_week TEXT,
        status TEXT,
        created_at TEXT,
        updated_at TEXT,
        cached_at TEXT NOT NULL
      )
    ''');

    // Cached ticket types
    await db.execute('''
      CREATE TABLE cached_ticket_types (
        id INTEGER PRIMARY KEY,
        match_id INTEGER,
        name TEXT NOT NULL,
        amount TEXT NOT NULL,
        desc TEXT,
        cached_at TEXT NOT NULL
      )
    ''');

    // Create indexes for common queries
    await db.execute(
      'CREATE INDEX idx_local_tickets_status ON local_tickets(status)',
    );
    await db.execute(
      'CREATE INDEX idx_local_validations_synced ON local_validations(synced)',
    );
    await db.execute(
      'CREATE INDEX idx_event_cache_matche ON event_cache(matche_id)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Upgrade from v1 to v2: Add cached_events and cached_ticket_types
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cached_events (
          id INTEGER PRIMARY KEY,
          name TEXT,
          home_team TEXT,
          away_team TEXT,
          venue TEXT,
          match_date TEXT,
          status TEXT,
          cached_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS cached_ticket_types (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          amount TEXT NOT NULL,
          description TEXT,
          cached_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 3) {
      // Upgrade from v2 to v3: Update cached_events schema
      // Drop and recreate with new schema
      await db.execute('DROP TABLE IF EXISTS cached_events');
      await db.execute('''
        CREATE TABLE cached_events (
          id INTEGER PRIMARY KEY,
          user_id INTEGER,
          season TEXT,
          home_team TEXT,
          away_team TEXT,
          venue TEXT,
          stadium_capacity INTEGER,
          match_date TEXT,
          competition TEXT,
          match_week TEXT,
          status TEXT,
          created_at TEXT,
          updated_at TEXT,
          cached_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 4) {
      // Upgrade from v3 to v4: Align cached_ticket_types with model/API
      await db.execute('DROP TABLE IF EXISTS cached_ticket_types');
      await db.execute('''
        CREATE TABLE cached_ticket_types (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          amount TEXT NOT NULL,
          desc TEXT,
          cached_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 5) {
      // Upgrade from v4 to v5: Add match_id to cached_ticket_types
      await db.execute('DROP TABLE IF EXISTS cached_ticket_types');
      await db.execute('''
        CREATE TABLE cached_ticket_types (
          id INTEGER PRIMARY KEY,
          match_id INTEGER,
          name TEXT NOT NULL,
          amount TEXT NOT NULL,
          desc TEXT,
          cached_at TEXT NOT NULL
        )
      ''');
    }

    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE event_cache ADD COLUMN trusted_device_keys TEXT',
      );
      await db.execute(
        'ALTER TABLE event_cache ADD COLUMN revoked_devices TEXT',
      );
    }
  }

  // ==================== LOCAL TICKETS CRUD ====================

  /// Insert a new offline ticket
  Future<void> insertLocalTicket({
    required String ticketId,
    required int matcheId,
    required int ticketTypesId,
    String? customerName,
    required double amount,
    required String payload,
    required String signature,
    required DateTime createdAt,
  }) async {
    final db = await database;
    await db.insert('local_tickets', {
      'ticket_id': ticketId,
      'matche_id': matcheId,
      'ticket_types_id': ticketTypesId,
      'customer_name': customerName,
      'amount': amount,
      'payload': payload,
      'signature': signature,
      'status': 'sold',
      'created_at': createdAt.toIso8601String(),
    });
  }

  /// Get all unsynced tickets
  Future<List<Map<String, dynamic>>> getUnsyncedTickets() async {
    final db = await database;
    return await db.query('local_tickets', where: 'synced_at IS NULL');
  }

  /// Mark ticket as synced
  Future<void> markTicketSynced(String ticketId) async {
    final db = await database;
    await db.update(
      'local_tickets',
      {'synced_at': DateTime.now().toIso8601String(), 'status': 'synced'},
      where: 'ticket_id = ?',
      whereArgs: [ticketId],
    );
  }

  /// Get ticket by ID
  Future<Map<String, dynamic>?> getTicketById(String ticketId) async {
    final db = await database;
    final results = await db.query(
      'local_tickets',
      where: 'ticket_id = ?',
      whereArgs: [ticketId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get all local tickets (for reprint screen)
  Future<List<Map<String, dynamic>>> getAllLocalTickets() async {
    final db = await database;
    return await db.query('local_tickets', orderBy: 'created_at DESC');
  }

  /// Get total count of local tickets
  Future<int> getLocalTicketCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM local_tickets',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Batch insert downloaded tickets for offline validation
  /// 
  /// This stores tickets from other devices so they can be validated offline.
  /// Clears old downloaded tickets for the event before inserting new ones.
  Future<int> insertDownloadedTickets({
    required int matcheId,
    required List<Map<String, String>> tickets,
  }) async {
    final db = await database;
    
    // Clear old downloaded tickets for this event
    await db.delete(
      'local_tickets',
      where: 'matche_id = ? AND status = ?',
      whereArgs: [matcheId, 'downloaded'],
    );
    
    int insertedCount = 0;

    for (final ticket in tickets) {
      try {
        // Insert as a downloaded ticket (no payload/signature, just reference)
        await db.insert('local_tickets', {
          'ticket_id': ticket['ticket_id'],
          'matche_id': matcheId,
          'ticket_types_id': 0, // Unknown ticket type
          'customer_name': null,
          'amount': 0.0,
          'payload': '', // No payload for downloaded tickets
          'signature': '', // No signature for downloaded tickets
          'status': 'downloaded', // Mark as downloaded for tracking
          'created_at': DateTime.now().toIso8601String(),
          'synced_at': DateTime.now().toIso8601String(), // Already synced
        });
        insertedCount++;
      } catch (e) {
        // Skip duplicates or errors
        continue;
      }
    }

    return insertedCount;
  }

  /// Get the sequential row number for a ticket (1-based, ordered by creation)
  Future<int?> getTicketSequentialId(String ticketId) async {
    final db = await database;
    // Get all ticket IDs ordered by creation, then find position
    final result = await db.rawQuery('''
      SELECT ticket_id, 
             ROW_NUMBER() OVER (ORDER BY created_at ASC) as seq_id
      FROM local_tickets
    ''');

    for (final row in result) {
      if (row['ticket_id'] == ticketId) {
        return row['seq_id'] as int?;
      }
    }
    return null;
  }

  // ==================== LOCAL VALIDATIONS CRUD ====================

  /// Insert a new validation record
  Future<void> insertValidation({
    required String id,
    required String ticketId,
    required DateTime validatedAt,
    Map<String, dynamic>? metadata,
  }) async {
    final db = await database;
    await db.insert('local_validations', {
      'id': id,
      'ticket_id': ticketId,
      'validated_at': validatedAt.toIso8601String(),
      'synced': 0,
      'conflict': 0,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
    });
  }

  /// Get all unsynced validations
  Future<List<Map<String, dynamic>>> getUnsyncedValidations() async {
    final db = await database;
    return await db.query('local_validations', where: 'synced = 0');
  }

  /// Mark validation as synced
  Future<void> markValidationSynced(
    String id, {
    bool isFirstScan = false,
    bool conflict = false,
  }) async {
    final db = await database;
    await db.update(
      'local_validations',
      {
        'synced': 1,
        'is_first_scan': isFirstScan ? 1 : 0,
        'conflict': conflict ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== VALIDATED TICKET CACHE ====================

  /// Add ticket to validated cache
  Future<void> addToValidatedCache(String ticketId) async {
    final db = await database;
    await db.insert('validated_ticket_cache', {
      'ticket_id': ticketId,
      'validated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Check if ticket is in validated cache
  Future<bool> isTicketValidated(String ticketId) async {
    final db = await database;
    final results = await db.query(
      'validated_ticket_cache',
      where: 'ticket_id = ?',
      whereArgs: [ticketId],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  /// Get validation timestamp for ticket
  Future<DateTime?> getValidationTime(String ticketId) async {
    final db = await database;
    final results = await db.query(
      'validated_ticket_cache',
      columns: ['validated_at'],
      where: 'ticket_id = ?',
      whereArgs: [ticketId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return DateTime.parse(results.first['validated_at'] as String);
  }

  /// Clear validated cache for a match
  Future<void> clearValidatedCache() async {
    final db = await database;
    await db.delete('validated_ticket_cache');
  }

  // ==================== EVENT CACHE ====================

  /// Cache event data for offline validation
  Future<void> cacheEvent({
    required int matcheId,
    required String eventName,
    required String eventPublicKey,
    required int keyVersion,
    List<int>? bloomFilter,
    required int snapshotVersion,
    Map<String, dynamic>? rules,
    List<Map<String, dynamic>>? trustedDeviceKeys,
    List<String>? revokedDevices,
  }) async {
    final db = await database;
    await db.insert('event_cache', {
      'matche_id': matcheId,
      'event_name': eventName,
      'event_public_key': eventPublicKey,
      'key_version': keyVersion,
      'bloom_filter': bloomFilter,
      'snapshot_version': snapshotVersion,
      'rules': rules?.toString(),
      'trusted_device_keys':
          trustedDeviceKeys == null ? null : jsonEncode(trustedDeviceKeys),
      'revoked_devices': revokedDevices == null ? null : jsonEncode(revokedDevices),
      'cached_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get cached event
  Future<Map<String, dynamic>?> getEventCache(int matcheId) async {
    final db = await database;
    final results = await db.query(
      'event_cache',
      where: 'matche_id = ?',
      whereArgs: [matcheId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Get event public key
  Future<String?> getEventPublicKey(int matcheId) async {
    final cache = await getEventCache(matcheId);
    return cache?['event_public_key'] as String?;
  }

  /// Check if event is cached
  Future<bool> isEventCached(int matcheId) async {
    final cache = await getEventCache(matcheId);
    return cache != null;
  }

  /// Get all cached events
  Future<List<Map<String, dynamic>>> getAllCachedEvents() async {
    final db = await database;
    return await db.query('event_cache');
  }

  /// Update bloom filter for event
  Future<void> updateBloomFilter(
    int matcheId,
    List<int> bloomFilter,
    int snapshotVersion,
  ) async {
    final db = await database;
    await db.update(
      'event_cache',
      {
        'bloom_filter': bloomFilter,
        'snapshot_version': snapshotVersion,
        'cached_at': DateTime.now().toIso8601String(),
      },
      where: 'matche_id = ?',
      whereArgs: [matcheId],
    );
  }

  /// Delete event cache
  Future<void> deleteEventCache(int matcheId) async {
    final db = await database;
    await db.delete(
      'event_cache',
      where: 'matche_id = ?',
      whereArgs: [matcheId],
    );
  }

  // ==================== STATISTICS ====================

  /// Get sync statistics
  Future<Map<String, int>> getSyncStats() async {
    final db = await database;

    final unsyncedTickets = await db.rawQuery(
      'SELECT COUNT(*) as count FROM local_tickets WHERE synced_at IS NULL',
    );
    final unsyncedValidations = await db.rawQuery(
      'SELECT COUNT(*) as count FROM local_validations WHERE synced = 0',
    );
    final cachedEvents = await db.rawQuery(
      'SELECT COUNT(*) as count FROM event_cache',
    );
    final validatedTickets = await db.rawQuery(
      'SELECT COUNT(*) as count FROM validated_ticket_cache',
    );

    return {
      'unsynced_tickets': (unsyncedTickets.first['count'] as int?) ?? 0,
      'unsynced_validations': (unsyncedValidations.first['count'] as int?) ?? 0,
      'cached_events': (cachedEvents.first['count'] as int?) ?? 0,
      'validated_tickets': (validatedTickets.first['count'] as int?) ?? 0,
    };
  }

  /// Clear all local data
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('local_tickets');
    await db.delete('local_validations');
    await db.delete('validated_ticket_cache');
    await db.delete('event_cache');
    await db.delete('cached_events');
    await db.delete('cached_ticket_types');
  }

  // ==================== CACHED EVENTS ====================

  /// Cache event list from API
  Future<void> cacheEventList(List<Map<String, dynamic>> events) async {
    final db = await database;
    final batch = db.batch();

    // Clear existing cache
    batch.delete('cached_events');

    // Insert new events - match Event model fields exactly
    for (final event in events) {
      batch.insert('cached_events', {
        'id': event['id'],
        'user_id': event['user_id'] ?? 0,
        'season': event['season'] ?? '',
        'home_team': event['home_team'] ?? '',
        'away_team': event['away_team'] ?? '',
        'venue': event['venue'] ?? '',
        'stadium_capacity': event['stadium_capacity'] ?? 0,
        'match_date': event['match_date'] ?? '',
        'competition': event['competition'] ?? '',
        'match_week': event['match_week'] ?? '',
        'status': event['status'] ?? '',
        'created_at': event['created_at'] ?? DateTime.now().toIso8601String(),
        'updated_at': event['updated_at'] ?? DateTime.now().toIso8601String(),
        'cached_at': DateTime.now().toIso8601String(),
      });
    }

    await batch.commit(noResult: true);
  }

  /// Get cached events
  Future<List<Map<String, dynamic>>> getCachedEvents() async {
    final db = await database;
    return await db.query('cached_events', orderBy: 'match_date DESC');
  }

  /// Check if events are cached
  Future<bool> hasEventsCached() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM cached_events',
    );
    final count = result.first['count'];
    return (count is int ? count : 0) > 0;
  }

  /// Clear cached events
  Future<void> clearCachedEvents() async {
    final db = await database;
    await db.delete('cached_events');
  }

  // ==================== CACHED TICKET TYPES ====================

  /// Cache ticket types from API
  Future<void> cacheTicketTypes(
    List<Map<String, dynamic>> types, {
    int? matchId,
  }) async {
    final db = await database;
    final batch = db.batch();

    // Clear existing cache for this match or global
    if (matchId != null) {
      batch.delete(
        'cached_ticket_types',
        where: 'match_id = ?',
        whereArgs: [matchId],
      );
    } else {
      batch.delete('cached_ticket_types', where: 'match_id IS NULL');
    }

    // Insert new types - match TicketType model and API format
    for (final type in types) {
      batch.insert('cached_ticket_types', {
        'id': type['id'],
        'match_id': matchId,
        'name': type['name'] ?? '',
        'amount': type['amount']?.toString() ?? '0.0',
        'desc': type['desc'],
        'cached_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }

  /// Get cached ticket types
  Future<List<Map<String, dynamic>>> getCachedTicketTypes({
    int? matchId,
  }) async {
    final db = await database;
    if (matchId != null) {
      return await db.query(
        'cached_ticket_types',
        where: 'match_id = ?',
        whereArgs: [matchId],
        orderBy: 'name ASC',
      );
    }
    return await db.query(
      'cached_ticket_types',
      where: 'match_id IS NULL',
      orderBy: 'name ASC',
    );
  }

  /// Check if ticket types are cached
  Future<bool> hasTicketTypesCached({int? matchId}) async {
    final db = await database;
    final result = await db.rawQuery(
      matchId != null
          ? 'SELECT COUNT(*) as count FROM cached_ticket_types WHERE match_id = ?'
          : 'SELECT COUNT(*) as count FROM cached_ticket_types WHERE match_id IS NULL',
      matchId != null ? [matchId] : [],
    );
    final count = result.first['count'];
    return (count is int ? count : 0) > 0;
  }

  /// Clear cached ticket types
  Future<void> clearCachedTicketTypes() async {
    final db = await database;
    await db.delete('cached_ticket_types');
  }
}
