import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:lost_and_found/features/collections/models/collection_model.dart';
import 'package:lost_and_found/features/library/models/indexed_folder_model.dart';

class IndexedFolderDbHelper {
  IndexedFolderDbHelper._();

  static final IndexedFolderDbHelper instance = IndexedFolderDbHelper._();

  static const _dbName = 'lostandfound.db';
  /// An upgrade from before version 2 drops and recreates the folders table, which is disposable bookkeeping. The
  /// embeddings live in the native store and are not touched.
  static const _dbVersion = 5;

  /// The user's collections, and one bare row for each built-in collection the user has changed.
  /// Built-ins live in code (see default_collections.dart) and have a row only once changed. Column `hidden` is 0 for
  /// visible, 1 for hidden and 2 for deleted. A built-in cannot be deleted for real, so deleted means off the list
  /// until it is restored from Settings. A non-empty `prompts` on a built-in means the user edited it. This is real
  /// user data, so it is only migrated by adding columns and never dropped.
  static const collectionsTable = 'collections';

  static const id = 'id';
  static const table = 'indexed_folders';
  static const colPath = 'path';
  static const colTotal = 'total';
  static const colEmbedded = 'embedded';
  static const colSkipped = 'skipped';
  static const colElapsedMs = 'elapsedMs';
  static const colProcessed = 'processed';
  static const colUpdatedAt = 'updatedAt';

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createFoldersTable(Database db) async {
    await db.execute('''
      CREATE TABLE $table (
        $id TEXT PRIMARY KEY,
        $colPath TEXT,
        $colTotal INTEGER,
        $colEmbedded INTEGER,
        $colSkipped INTEGER,
        $colElapsedMs INTEGER,
        $colProcessed INTEGER,
        $colUpdatedAt INTEGER
      )
    ''');
  }

  Future<void> _createCollectionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $collectionsTable (
        id TEXT PRIMARY KEY,
        name TEXT,
        emoji TEXT,
        prompts TEXT,
        contentMode TEXT,
        sensitivity REAL,
        isBuiltIn INTEGER,
        hidden INTEGER,
        createdAt INTEGER,
        kind TEXT,
        seed TEXT,
        personIds TEXT
      )
    ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createFoldersTable(db);
    await _createCollectionsTable(db);
  }

  /// Migrates from [oldVersion]. The collections table created at version 3 already has every column, so the column
  /// additions only apply to a table that existed before. Rows added by those migrations keep working, as a null
  /// `kind` reads as text and a null `personIds` reads as no person filter.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('DROP TABLE IF EXISTS $table');
      await _createFoldersTable(db);
    }
    if (oldVersion < 3) {
      await _createCollectionsTable(db);
    } else {
      if (oldVersion < 4) {
        await db.execute("ALTER TABLE $collectionsTable ADD COLUMN kind TEXT");
        await db.execute("ALTER TABLE $collectionsTable ADD COLUMN seed TEXT");
      }
      if (oldVersion < 5) {
        await db.execute("ALTER TABLE $collectionsTable ADD COLUMN personIds TEXT");
      }
    }
  }

  Future<List<Map<String, Object?>>> getCollectionRows() async {
    final db = await database;
    return db.query(collectionsTable, orderBy: 'createdAt ASC');
  }

  Future<void> upsertCollection(SmartCollection collection, {int hiddenState = 0}) async {
    final db = await database;
    await db.insert(
      collectionsTable,
      collection.toRow(hiddenState: hiddenState),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteCollection(String collectionId) async {
    final db = await database;
    await db.delete(collectionsTable, where: 'id = ?', whereArgs: [collectionId]);
  }

  /// Sets the `hidden` column of a collection to [state]: 0 visible, 1 hidden, 2 deleted. A built-in with no row yet
  /// gets a bare one with empty prompts, which means no edits.
  Future<void> setCollectionState(String collectionId, int state, {required bool isBuiltIn}) async {
    final db = await database;
    final updated = await db.update(
      collectionsTable,
      {'hidden': state},
      where: 'id = ?',
      whereArgs: [collectionId],
    );
    if (updated == 0 && isBuiltIn && state != 0) {
      await db.insert(collectionsTable, {
        'id': collectionId,
        'name': '',
        'emoji': '',
        'prompts': '[]',
        'contentMode': 'both',
        'sensitivity': 0.0,
        'isBuiltIn': 1,
        'hidden': state,
        'createdAt': 0,
      });
    }
  }

  /// Every built-in back to how it ships: undeleted, unhidden, unedited.
  Future<void> resetBuiltIns() async {
    final db = await database;
    await db.delete(collectionsTable, where: 'isBuiltIn = 1');
  }

  Future<int> upsertFolder({required IndexedFolder folder}) async {
    final db = await database;
    return db.insert(
      table,
      folder.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<IndexedFolder?> getFolderById({required String folderid}) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: '$id = ?',
      whereArgs: [folderid],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return IndexedFolder.fromMap(rows.first);
  }

  Future<List<IndexedFolder>> getAllFolders() async {
    final db = await database;
    final rows = await db.query(table, orderBy: '$colUpdatedAt DESC');
    return rows.map(IndexedFolder.fromMap).toList();
  }

  Future<int> deleteById(String folderid) async {
    final db = await database;
    return db.delete(table, where: '$id = ?', whereArgs: [folderid]);
  }

  Future<int> clearFolderList() async {
    final db = await database;
    return db.delete(table);
  }

  Future<void> close() async {
    final db = _db;
    if (db == null) return;
    await db.close();
    _db = null;
  }
}
