import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:twentyonevision/models/indexed_folder_model.dart';

class IndexedFolderDbHelper {
  IndexedFolderDbHelper._();

  static final IndexedFolderDbHelper instance = IndexedFolderDbHelper._();

  static const _dbName = 'twentyonevision.db';
  // onUpgrade just drops and recreates this table - it's disposable UI
  // bookkeeping, the actual embeddings live in the native store untouched.
  static const _dbVersion = 2;

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

  Future<void> _onCreate(Database db, int version) async {
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

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await db.execute('DROP TABLE IF EXISTS $table');
    await _onCreate(db, newVersion);
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
