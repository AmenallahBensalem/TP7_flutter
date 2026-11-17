import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'models/sync_status.dart';

/// Stockage SQLite local (offline-first).
class LocalQueueService {
  Future<Database>? _opening;
  static const String tableName = 'local_clients';
  static const int _dbVersion = 2;

  final bool _inMemory;
  final String? _accountId;

  LocalQueueService({bool inMemory = false, String? accountId})
    : _inMemory = inMemory,
      _accountId = accountId;

  Future<Database> get database async {
    final opening = _opening ??= _initDB();
    try {
      return await opening;
    } catch (_) {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  Future<Database> _initDB() async {
    if (_inMemory) {
      return openDatabase(
        inMemoryDatabasePath,
        version: _dbVersion,
        onCreate: _onCreate,
      );
    }
    final dbPath = await getDatabasesPath();
    final fileName = _accountId == null
        ? 'waiting_room.db'
        : 'waiting_room_$_accountId.db';
    final path = join(dbPath, fileName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableName (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        lat REAL,
        lng REAL,
        location_accuracy_m REAL,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
  }

  /// Migration v1 → v2 : is_synced (0/1) → sync_status.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN location_accuracy_m REAL',
      );
      await db.execute(
        "ALTER TABLE $tableName ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending'",
      );
      await db.execute(
        "UPDATE $tableName SET sync_status = CASE WHEN is_synced = 1 THEN 'synced' ELSE 'pending' END",
      );
    }
  }

  Future<void> insertClientLocally(Map<String, dynamic> client) async {
    final db = await database;
    await db.insert(
      tableName,
      client,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getClients() async {
    final db = await database;
    return db.query(tableName, orderBy: 'created_at ASC, id ASC');
  }

  /// Tout ce qui n'est pas encore `synced` (pending, syncing, failed).
  Future<List<Map<String, dynamic>>> getUnsyncedClients() async {
    final db = await database;
    return db.query(
      tableName,
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.synced.name],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<void> updateSyncStatus(String id, SyncStatus status) async {
    final db = await database;
    await db.update(
      tableName,
      {'sync_status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markClientAsSynced(String id) =>
      updateSyncStatus(id, SyncStatus.synced);

  Future<void> deleteClient(String id) async {
    final db = await database;
    await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final opening = _opening;
    if (opening != null) {
      final db = await opening;
      await db.close();
      _opening = null;
    }
  }
}
