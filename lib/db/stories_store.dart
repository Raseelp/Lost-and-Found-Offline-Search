import 'package:flutter/foundation.dart';
import 'package:lost_and_found/models/story_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Where the stories remember things: the state of each ring, and the ledger of what each ring has already shown
/// in its current round (so a photo is not shown again until the round is over).
abstract class StoriesStore {
  Future<List<RingState>> loadStates();

  /// How many pictures each ring has shown in its current round, by ring key.
  Future<Map<String, int>> shownCounts();

  Future<void> saveState(RingState state);

  Future<Set<String>> shownUris(String ringKey);

  Future<void> addShown(String ringKey, Iterable<String> uris, int at);

  /// Starts a new round for the ring.
  Future<void> clearShown(String ringKey);

  /// A small saved value (the batch of rings of the row), by name.
  Future<String?> loadMeta(String key);

  Future<void> saveMeta(String key, String value);
}

class SqliteStoriesStore implements StoriesStore {
  Database? _db;

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final path = p.join(await getDatabasesPath(), 'stories.db');
    return _db = await openDatabase(
      path,
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        // Version 1 had no saved batch; a build from before the column "eligible" may lack it too.
        await db.execute('CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
        final columns = await db.rawQuery('PRAGMA table_info(rings)');
        if (!columns.any((c) => c['name'] == 'eligible')) {
          await db.execute('ALTER TABLE rings ADD COLUMN eligible INTEGER NOT NULL DEFAULT 0');
        }
      },
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
        await db.execute('''CREATE TABLE rings (
          key TEXT PRIMARY KEY,
          built_at INTEGER NOT NULL DEFAULT 0,
          viewed_at INTEGER NOT NULL DEFAULT 0,
          last_count INTEGER NOT NULL DEFAULT 0,
          eligible INTEGER NOT NULL DEFAULT 0,
          lens TEXT,
          caption TEXT,
          frames TEXT,
          rest_until INTEGER NOT NULL DEFAULT 0,
          muted_until INTEGER NOT NULL DEFAULT 0
        )''');
        await db.execute('''CREATE TABLE shown (
          ring_key TEXT NOT NULL,
          uri TEXT NOT NULL,
          at INTEGER NOT NULL,
          PRIMARY KEY (ring_key, uri)
        )''');
      },
    );
  }

  @override
  Future<List<RingState>> loadStates() async {
    try {
      final db = await _open();
      return [for (final row in await db.query('rings')) RingState.fromMap(row)];
    } catch (e) {
      debugPrint('stories: could not read the rings: $e');
      return [];
    }
  }

  @override
  Future<Map<String, int>> shownCounts() async {
    try {
      final db = await _open();
      final rows = await db.rawQuery('SELECT ring_key, COUNT(*) AS n FROM shown GROUP BY ring_key');
      return {for (final r in rows) r['ring_key'] as String: (r['n'] as num).toInt()};
    } catch (e) {
      debugPrint('stories: could not read the ledger: $e');
      return {};
    }
  }

  @override
  Future<void> saveState(RingState state) async {
    try {
      final db = await _open();
      await db.insert('rings', state.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('stories: could not save a ring: $e');
    }
  }

  @override
  Future<Set<String>> shownUris(String ringKey) async {
    try {
      final db = await _open();
      final rows = await db.query('shown', columns: ['uri'], where: 'ring_key = ?', whereArgs: [ringKey]);
      return {for (final r in rows) r['uri'] as String};
    } catch (e) {
      debugPrint('stories: could not read what a ring showed: $e');
      return {};
    }
  }

  @override
  Future<void> addShown(String ringKey, Iterable<String> uris, int at) async {
    try {
      final db = await _open();
      final batch = db.batch();
      for (final uri in uris) {
        batch.insert('shown', {'ring_key': ringKey, 'uri': uri, 'at': at}, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('stories: could not note what a ring showed: $e');
    }
  }

  @override
  Future<void> clearShown(String ringKey) async {
    try {
      final db = await _open();
      await db.delete('shown', where: 'ring_key = ?', whereArgs: [ringKey]);
    } catch (e) {
      debugPrint('stories: could not start a new round: $e');
    }
  }

  @override
  Future<String?> loadMeta(String key) async {
    try {
      final db = await _open();
      final rows = await db.query('meta', columns: ['v'], where: 'k = ?', whereArgs: [key]);
      return rows.isEmpty ? null : rows.first['v'] as String?;
    } catch (e) {
      debugPrint('stories: could not read a saved value: $e');
      return null;
    }
  }

  @override
  Future<void> saveMeta(String key, String value) async {
    try {
      final db = await _open();
      await db.insert('meta', {'k': key, 'v': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('stories: could not save a value: $e');
    }
  }
}
