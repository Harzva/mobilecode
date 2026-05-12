// lib/services/local_database_service.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

/// Exception thrown when a local database operation fails.
class LocalDatabaseException implements Exception {
  final String message;
  final String? operation;
  final dynamic originalError;

  const LocalDatabaseException({
    required this.message,
    this.operation,
    this.originalError,
  });

  @override
  String toString() => 'LocalDatabaseException [$operation]: $message';
}

/// SQLite-backed local database for offline storage.
///
/// This is the **source of truth** for all application data when the device
/// is offline. Every mutation flows through here first before any remote sync.
///
/// ## Tables
/// | Table         | Purpose                                    |
/// |---------------|--------------------------------------------|
/// | `projects`    | Project metadata and structure             |
/// | `files`       | Individual file records with content       |
/// | `snippets`    | Reusable code snippets                     |
/// | `api_configs` | LLM endpoint configurations                |
/// | `sync_queue`  | Pending outbound sync operations           |
/// | `settings`    | Key/value app settings                     |
class LocalDatabaseService {
  static const String _dbName = 'mobile_coding.db';
  static const int _dbVersion = 1;
  Database? _db;

  // ── Table names ─────────────────────────────────────────────────────

  static const String tableProjects = 'projects';
  static const String tableFiles = 'files';
  static const String tableSnippets = 'snippets';
  static const String tableApiConfigs = 'api_configs';
  static const String tableSyncQueue = 'sync_queue';
  static const String tableSettings = 'settings';

  bool _initialized = false;

  /// Whether the database is open and ready.
  bool get isInitialized => _initialized;

  // ── Initialization ──────────────────────────────────────────────────

  /// Open (or create) the SQLite database.
  ///
  /// Safe to call multiple times -- subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;

    try {
      final dbPath = await getDatabasesPath();
      final fullPath = path.join(dbPath, _dbName);

      _db = await openDatabase(
        fullPath,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: (db) => debugPrint('[LocalDatabaseService] DB opened: $fullPath'),
      );

      _initialized = true;
      debugPrint('[LocalDatabaseService] Initialized (v$_dbVersion)');
    } catch (e) {
      throw LocalDatabaseException(
        message: 'Failed to open database: $e',
        operation: 'init',
        originalError: e,
      );
    }
  }

  /// Close the database connection.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _initialized = false;
      debugPrint('[LocalDatabaseService] Closed');
    }
  }

  /// Delete the entire database file (factory reset).
  Future<void> destroy() async {
    await close();
    final dbPath = await getDatabasesPath();
    final fullPath = path.join(dbPath, _dbName);
    await deleteDatabase(fullPath);
    debugPrint('[LocalDatabaseService] Database destroyed');
  }

  // ── Schema ──────────────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('[LocalDatabaseService] Creating schema v$version');

    // Projects table.
    await db.execute('''
      CREATE TABLE $tableProjects (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        language TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        file_count INTEGER NOT NULL DEFAULT 0,
        sync_version INTEGER NOT NULL DEFAULT 1,
        remote_id TEXT,
        dirty INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Index on updated_at for sorting.
    await db.execute('''
      CREATE INDEX idx_projects_updated ON $tableProjects(updated_at DESC)
    ''');

    // Files table (flattened -- one row per file).
    await db.execute('''
      CREATE TABLE $tableFiles (
        id TEXT PRIMARY KEY NOT NULL,
        project_id TEXT NOT NULL,
        name TEXT NOT NULL,
        path TEXT NOT NULL,
        is_directory INTEGER NOT NULL DEFAULT 0,
        content TEXT,
        parent_path TEXT,
        modified_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1,
        dirty INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (project_id) REFERENCES $tableProjects(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_files_project ON $tableFiles(project_id)
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX idx_files_path ON $tableFiles(project_id, path)
    ''');

    // Snippets table.
    await db.execute('''
      CREATE TABLE $tableSnippets (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        code TEXT NOT NULL,
        language TEXT NOT NULL,
        description TEXT,
        tags TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        sync_version INTEGER NOT NULL DEFAULT 1,
        dirty INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_snippets_lang ON $tableSnippets(language)
    ''');

    // API configs table.
    await db.execute('''
      CREATE TABLE $tableApiConfigs (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        api_key TEXT,
        model_name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_version INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Sync queue table.
    await db.execute('''
      CREATE TABLE $tableSyncQueue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        op_id TEXT NOT NULL UNIQUE,
        type INTEGER NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        data TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 1,
        local_version INTEGER,
        data_hash TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        error_message TEXT,
        next_retry_at TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_syncqueue_status ON $tableSyncQueue(status, priority DESC, timestamp)
    ''');

    // Settings table (key/value store).
    await db.execute('''
      CREATE TABLE $tableSettings (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT,
        value_type TEXT NOT NULL DEFAULT 'string',
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[LocalDatabaseService] Upgrading $oldVersion -> $newVersion');
    // Migration logic goes here when versions change.
  }

  // ── CRUD: Projects ──────────────────────────────────────────────────

  /// Insert or replace a project record.
  Future<int> insertProject(Map<String, dynamic> project) async {
    _ensureOpen();
    try {
      final row = _serializeProject(project);
      return await _db!.insert(
        tableProjects,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw LocalDatabaseException(
        message: 'Failed to insert project: $e',
        operation: 'insertProject',
        originalError: e,
      );
    }
  }

  /// Get all projects, ordered by favorite then updated_at desc.
  Future<List<Map<String, dynamic>>> getProjects() async {
    _ensureOpen();
    final rows = await _db!.query(
      tableProjects,
      orderBy: 'is_favorite DESC, updated_at DESC',
    );
    return rows.map(_deserializeProject).toList();
  }

  /// Get a single project by its ID.
  Future<Map<String, dynamic>?> getProject(String id) async {
    _ensureOpen();
    final rows = await _db!.query(
      tableProjects,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _deserializeProject(rows.first);
  }

  /// Update specific fields of a project.
  Future<int> updateProject(String id, Map<String, dynamic> data) async {
    _ensureOpen();
    final updateData = <String, dynamic>{
      ...data,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'dirty': 1,
    };
    // Remove the id if present to avoid attempting to change PK.
    updateData.remove('id');
    return await _db!.update(
      tableProjects,
      updateData,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a project by ID (cascades to files via FK).
  Future<int> deleteProject(String id) async {
    _ensureOpen();
    return await _db!.delete(
      tableProjects,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a project's dirty flag as cleared after successful sync.
  Future<int> markProjectClean(String id) async {
    _ensureOpen();
    return await _db!.update(
      tableProjects,
      {'dirty': 0, 'sync_version': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── CRUD: Files ─────────────────────────────────────────────────────

  /// Insert or replace a file record.
  Future<int> insertFile(Map<String, dynamic> file) async {
    _ensureOpen();
    try {
      final row = _serializeFile(file);
      return await _db!.insert(
        tableFiles,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw LocalDatabaseException(
        message: 'Failed to insert file: $e',
        operation: 'insertFile',
        originalError: e,
      );
    }
  }

  /// Get all files for a specific project.
  Future<List<Map<String, dynamic>>> getFiles(String projectId) async {
    _ensureOpen();
    final rows = await _db!.query(
      tableFiles,
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'path ASC',
    );
    return rows.map(_deserializeFile).toList();
  }

  /// Get a single file by its project + path.
  Future<Map<String, dynamic>?> getFile(String projectId, String filePath) async {
    _ensureOpen();
    final rows = await _db!.query(
      tableFiles,
      where: 'project_id = ? AND path = ?',
      whereArgs: [projectId, filePath],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _deserializeFile(rows.first);
  }

  /// Update the content of a file and bump its version.
  Future<int> updateFileContent(
    String projectId,
    String filePath,
    String content,
  ) async {
    _ensureOpen();
    return await _db!.update(
      tableFiles,
      {
        'content': content,
        'modified_at': DateTime.now().toUtc().toIso8601String(),
        'dirty': 1,
      },
      where: 'project_id = ? AND path = ?',
      whereArgs: [projectId, filePath],
    );
  }

  /// Delete a file by project + path.
  Future<int> deleteFile(String projectId, String filePath) async {
    _ensureOpen();
    return await _db!.delete(
      tableFiles,
      where: 'project_id = ? AND path = ?',
      whereArgs: [projectId, filePath],
    );
  }

  /// Delete all files belonging to a project.
  Future<int> deleteFilesForProject(String projectId) async {
    _ensureOpen();
    return await _db!.delete(
      tableFiles,
      where: 'project_id = ?',
      whereArgs: [projectId],
    );
  }

  /// Mark a file as clean after successful sync.
  Future<int> markFileClean(String projectId, String filePath) async {
    _ensureOpen();
    return await _db!.update(
      tableFiles,
      {'dirty': 0},
      where: 'project_id = ? AND path = ?',
      whereArgs: [projectId, filePath],
    );
  }

  // ── CRUD: Snippets ──────────────────────────────────────────────────

  /// Insert or replace a snippet.
  Future<int> insertSnippet(Map<String, dynamic> snippet) async {
    _ensureOpen();
    try {
      final row = _serializeSnippet(snippet);
      return await _db!.insert(
        tableSnippets,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw LocalDatabaseException(
        message: 'Failed to insert snippet: $e',
        operation: 'insertSnippet',
        originalError: e,
      );
    }
  }

  /// Get all snippets, optionally filtered by language tag.
  Future<List<Map<String, dynamic>>> getSnippets({String? tag}) async {
    _ensureOpen();
    List<Map<String, dynamic>> rows;
    if (tag != null && tag.isNotEmpty) {
      rows = await _db!.query(
        tableSnippets,
        where: 'tags LIKE ?',
        whereArgs: ['%$tag%'],
        orderBy: 'is_favorite DESC, updated_at DESC',
      );
    } else {
      rows = await _db!.query(
        tableSnippets,
        orderBy: 'is_favorite DESC, updated_at DESC',
      );
    }
    return rows.map(_deserializeSnippet).toList();
  }

  /// Get a single snippet by ID.
  Future<Map<String, dynamic>?> getSnippet(String id) async {
    _ensureOpen();
    final rows = await _db!.query(
      tableSnippets,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _deserializeSnippet(rows.first);
  }

  /// Delete a snippet by ID.
  Future<int> deleteSnippet(String id) async {
    _ensureOpen();
    return await _db!.delete(
      tableSnippets,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── CRUD: API Configs ───────────────────────────────────────────────

  /// Insert or replace an API config.
  Future<int> insertApiConfig(Map<String, dynamic> config) async {
    _ensureOpen();
    try {
      return await _db!.insert(
        tableApiConfigs,
        {
          'id': config['id'],
          'name': config['name'],
          'base_url': config['baseUrl'] ?? config['base_url'],
          'api_key': config['apiKey'] ?? config['api_key'],
          'model_name': config['modelName'] ?? config['model_name'],
          'is_active': config['isActive'] == true || config['is_active'] == 1 ? 1 : 0,
          'created_at': (config['createdAt'] ?? DateTime.now()).toString(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw LocalDatabaseException(
        message: 'Failed to insert API config: $e',
        operation: 'insertApiConfig',
        originalError: e,
      );
    }
  }

  /// Get all API configs.
  Future<List<Map<String, dynamic>>> getApiConfigs() async {
    _ensureOpen();
    final rows = await _db!.query(tableApiConfigs);
    return rows.map((r) => {
      'id': r['id'],
      'name': r['name'],
      'baseUrl': r['base_url'],
      'apiKey': r['api_key'],
      'modelName': r['model_name'],
      'isActive': r['is_active'] == 1,
      'createdAt': r['created_at'],
      'updatedAt': r['updated_at'],
    }).toList();
  }

  /// Get the active API config.
  Future<Map<String, dynamic>?> getActiveApiConfig() async {
    _ensureOpen();
    final rows = await _db!.query(
      tableApiConfigs,
      where: 'is_active = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'id': r['id'],
      'name': r['name'],
      'baseUrl': r['base_url'],
      'apiKey': r['api_key'],
      'modelName': r['model_name'],
      'isActive': r['is_active'] == 1,
    };
  }

  // ── Sync Queue ──────────────────────────────────────────────────────

  /// Enqueue a sync operation for later processing.
  Future<int> enqueueSync(Map<String, dynamic> operation) async {
    _ensureOpen();
    try {
      final data = operation['data'];
      return await _db!.insert(
        tableSyncQueue,
        {
          'op_id': operation['id'],
          'type': operation['type'],
          'entity_type': operation['entityType'],
          'entity_id': operation['entityId'],
          'data': data is String ? data : data.toString(),
          'timestamp': operation['timestamp'],
          'retry_count': operation['retryCount'] ?? 0,
          'priority': operation['priority'] ?? 1,
          'local_version': operation['localVersion'],
          'data_hash': operation['dataHash'],
          'status': 'pending',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw LocalDatabaseException(
        message: 'Failed to enqueue sync: $e',
        operation: 'enqueueSync',
        originalError: e,
      );
    }
  }

  /// Get all pending sync operations, sorted by priority then timestamp.
  Future<List<Map<String, dynamic>>> getPendingSyncs() async {
    _ensureOpen();
    final rows = await _db!.query(
      tableSyncQueue,
      where: "status = 'pending' OR status = 'failed'",
      orderBy: 'priority DESC, timestamp ASC',
    );
    return rows;
  }

  /// Mark a sync operation as completed and remove it from the queue.
  Future<int> markSyncCompleted(int id) async {
    _ensureOpen();
    return await _db!.delete(
      tableSyncQueue,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a sync operation as failed and record the error.
  Future<int> markSyncFailed(int id, String error) async {
    _ensureOpen();
    return await _db!.update(
      tableSyncQueue,
      {
        'status': 'failed',
        'error_message': error,
        'retry_count': 1, // Will be incremented by the manager.
        'next_retry_at': DateTime.now()
            .add(const Duration(seconds: 2))
            .toUtc()
            .toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get all failed sync operations.
  Future<List<Map<String, dynamic>>> getFailedSyncs() async {
    _ensureOpen();
    return await _db!.query(
      tableSyncQueue,
      where: "status = 'failed'",
      orderBy: 'timestamp ASC',
    );
  }

  /// Clear all completed and failed sync records.
  Future<int> clearSyncQueue() async {
    _ensureOpen();
    return await _db!.delete(tableSyncQueue);
  }

  /// Get the count of pending sync operations.
  Future<int> getPendingSyncCount() async {
    _ensureOpen();
    final result = await _db!.rawQuery(
      "SELECT COUNT(*) as count FROM $tableSyncQueue WHERE status = 'pending'",
    );
    return (result.first['count'] as int?) ?? 0;
  }

  // ── Settings ────────────────────────────────────────────────────────

  /// Store a setting value. Supports String, int, double, bool, DateTime.
  Future<void> setSetting(String key, dynamic value) async {
    _ensureOpen();
    String stringValue;
    String valueType;

    switch (value.runtimeType) {
      case int:
        stringValue = (value as int).toString();
        valueType = 'int';
        break;
      case double:
        stringValue = (value as double).toString();
        valueType = 'double';
        break;
      case bool:
        stringValue = (value as bool) ? '1' : '0';
        valueType = 'bool';
        break;
      case DateTime:
        stringValue = (value as DateTime).toUtc().toIso8601String();
        valueType = 'datetime';
        break;
      default:
        stringValue = value.toString();
        valueType = 'string';
    }

    await _db!.insert(
      tableSettings,
      {
        'key': key,
        'value': stringValue,
        'value_type': valueType,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieve a setting value by key.
  ///
  /// Returns `null` if the key doesn't exist. The value is automatically
  /// cast back to its original Dart type based on the stored `value_type`.
  Future<dynamic> getSetting(String key) async {
    _ensureOpen();
    final rows = await _db!.query(
      tableSettings,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final rawValue = row['value'] as String?;
    if (rawValue == null) return null;

    final valueType = row['value_type'] as String? ?? 'string';
    switch (valueType) {
      case 'int':
        return int.tryParse(rawValue);
      case 'double':
        return double.tryParse(rawValue);
      case 'bool':
        return rawValue == '1';
      case 'datetime':
        return DateTime.tryParse(rawValue);
      default:
        return rawValue;
    }
  }

  /// Delete a setting.
  Future<int> deleteSetting(String key) async {
    _ensureOpen();
    return await _db!.delete(
      tableSettings,
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  // ── Utilities ───────────────────────────────────────────────────────

  /// Get a summary of database contents for diagnostics.
  Future<Map<String, int>> getTableCounts() async {
    _ensureOpen();
    final counts = <String, int>{};
    for (final table in [
      tableProjects,
      tableFiles,
      tableSnippets,
      tableApiConfigs,
      tableSyncQueue,
      tableSettings,
    ]) {
      final result = await _db!.rawQuery('SELECT COUNT(*) as c FROM $table');
      counts[table] = (result.first['c'] as int?) ?? 0;
    }
    return counts;
  }

  /// Run a full integrity check (SQLite PRAGMA).
  Future<List<Map<String, dynamic>>> runIntegrityCheck() async {
    _ensureOpen();
    return await _db!.rawQuery('PRAGMA integrity_check');
  }

  // ── Serialization helpers ───────────────────────────────────────────

  Map<String, dynamic> _serializeProject(Map<String, dynamic> p) => {
        'id': p['id'],
        'name': p['name'],
        'description': p['description'] ?? '',
        'language': p['language'],
        'created_at': _iso(p['createdAt'] ?? p['created_at']),
        'updated_at': _iso(p['updatedAt'] ?? p['updated_at'] ?? DateTime.now()),
        'is_favorite': (p['isFavorite'] ?? p['is_favorite'] ?? false) ? 1 : 0,
        'file_count': p['fileCount'] ?? p['file_count'] ?? 0,
        'sync_version': p['syncVersion'] ?? p['sync_version'] ?? 1,
        'remote_id': p['remoteId'] ?? p['remote_id'],
        'dirty': (p['dirty'] ?? true) ? 1 : 0,
      };

  Map<String, dynamic> _deserializeProject(Map<String, dynamic> row) => {
        'id': row['id'],
        'name': row['name'],
        'description': row['description'],
        'language': row['language'],
        'createdAt': row['created_at'],
        'updatedAt': row['updated_at'],
        'isFavorite': row['is_favorite'] == 1,
        'fileCount': row['file_count'],
        'syncVersion': row['sync_version'],
        'remoteId': row['remote_id'],
        'dirty': row['dirty'] == 1,
      };

  Map<String, dynamic> _serializeFile(Map<String, dynamic> f) => {
        'id': f['id'],
        'project_id': f['projectId'] ?? f['project_id'],
        'name': f['name'],
        'path': f['path'],
        'is_directory': (f['isDirectory'] ?? f['is_directory'] ?? false) ? 1 : 0,
        'content': f['content'],
        'parent_path': f['parentPath'] ?? f['parent_path'],
        'modified_at': _iso(f['modifiedAt'] ?? f['modified_at'] ?? DateTime.now()),
        'sync_version': f['syncVersion'] ?? f['sync_version'] ?? 1,
        'dirty': (f['dirty'] ?? true) ? 1 : 0,
      };

  Map<String, dynamic> _deserializeFile(Map<String, dynamic> row) => {
        'id': row['id'],
        'projectId': row['project_id'],
        'name': row['name'],
        'path': row['path'],
        'isDirectory': row['is_directory'] == 1,
        'content': row['content'],
        'parentPath': row['parent_path'],
        'modifiedAt': row['modified_at'],
        'syncVersion': row['sync_version'],
        'dirty': row['dirty'] == 1,
      };

  Map<String, dynamic> _serializeSnippet(Map<String, dynamic> s) => {
        'id': s['id'],
        'title': s['title'],
        'code': s['code'],
        'language': s['language'],
        'description': s['description'],
        'tags': s['tags'] is List ? (s['tags'] as List).join(',') : (s['tags'] ?? ''),
        'created_at': _iso(s['createdAt'] ?? s['created_at'] ?? DateTime.now()),
        'updated_at': _iso(s['updatedAt'] ?? s['updated_at'] ?? DateTime.now()),
        'is_favorite': (s['isFavorite'] ?? s['is_favorite'] ?? false) ? 1 : 0,
        'sync_version': s['syncVersion'] ?? s['sync_version'] ?? 1,
        'dirty': (s['dirty'] ?? true) ? 1 : 0,
      };

  Map<String, dynamic> _deserializeSnippet(Map<String, dynamic> row) => {
        'id': row['id'],
        'title': row['title'],
        'code': row['code'],
        'language': row['language'],
        'description': row['description'],
        'tags': row['tags'],
        'createdAt': row['created_at'],
        'updatedAt': row['updated_at'],
        'isFavorite': row['is_favorite'] == 1,
        'syncVersion': row['sync_version'],
        'dirty': row['dirty'] == 1,
      };

  String _iso(dynamic dt) {
    if (dt is DateTime) return dt.toUtc().toIso8601String();
    if (dt is String) return dt;
    return DateTime.now().toUtc().toIso8601String();
  }

  void _ensureOpen() {
    if (_db == null || !_db!.isOpen) {
      throw const LocalDatabaseException(
        message: 'Database is not open. Call init() first.',
        operation: '_ensureOpen',
      );
    }
  }
}
