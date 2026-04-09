import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../app/support/openhand_paths.dart';

/// Central database service providing SQLite-backed persistence for the app.
///
/// Initialize once at startup via [DatabaseService.initialize], then access
/// the singleton through [DatabaseService.instance].
class DatabaseService {
  DatabaseService._();

  static DatabaseService? _instance;
  Database? _database;

  static const int schemaVersion = 1;
  static const String _databaseFileName = 'openhand.db';

  /// Returns the singleton instance.  Must call [initialize] first.
  static DatabaseService get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError('DatabaseService has not been initialized.');
    }
    return inst;
  }

  /// Whether the service has been initialized.
  static bool get isInitialized => _instance != null;

  /// The underlying database handle.
  Database get database {
    final db = _database;
    if (db == null) {
      throw StateError('Database has not been opened.');
    }
    return db;
  }

  /// Full path to the database file.
  static String defaultDatabasePath() {
    return p.join(
      OpenHandPaths.homeDirectoryPath(),
      '.openhand',
      _databaseFileName,
    );
  }

  /// Initialize the database service.  Safe to call multiple times (idempotent).
  static Future<DatabaseService> initialize({String? databasePath}) async {
    if (_instance != null) {
      return _instance!;
    }

    // Initialize FFI for desktop platforms.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final effectivePath = databasePath ?? defaultDatabasePath();
    final dbDirectory = Directory(p.dirname(effectivePath));
    if (!await dbDirectory.exists()) {
      await dbDirectory.create(recursive: true);
    }

    final service = DatabaseService._();
    service._database = await databaseFactoryFfi.openDatabase(
      effectivePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
      ),
    );
    _instance = service;
    return service;
  }

  /// Close the database and release the singleton.
  Future<void> close() async {
    await _database?.close();
    _database = null;
    _instance = null;
  }

  // ---------------------------------------------------------------------------
  // Schema
  // ---------------------------------------------------------------------------

  static Future<void> _onConfigure(Database db) async {
    // Enable foreign key enforcement.
    await db.execute('PRAGMA foreign_keys = ON');
    // WAL mode for better concurrent read/write performance.
    await db.execute('PRAGMA journal_mode = WAL');
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // ----- Sessions (metadata only, messages in separate table) -----
    batch.execute('''
      CREATE TABLE sessions (
        id                                        TEXT PRIMARY KEY,
        title                                     TEXT NOT NULL DEFAULT '',
        template_id                               TEXT NOT NULL DEFAULT '',
        template_name                             TEXT NOT NULL DEFAULT '',
        template_icon_name                        TEXT NOT NULL DEFAULT '',
        template_internal_version                 TEXT NOT NULL DEFAULT '',
        created_at                                TEXT NOT NULL,
        updated_at                                TEXT NOT NULL,
        last_used_model_id                        TEXT,
        last_used_model_label                     TEXT,
        is_title_manually_edited                  INTEGER NOT NULL DEFAULT 0,
        auto_title_generated_at                   TEXT,
        auto_title_source_message_id              TEXT,
        latest_compression_checkpoint_message_id  TEXT,
        latest_compression_at                     TEXT,
        mode                                      TEXT NOT NULL DEFAULT 'chat',
        awaiting_plan_approval                    INTEGER NOT NULL DEFAULT 0,
        pending_plan                              TEXT,
        full_access_permission                    INTEGER NOT NULL DEFAULT 0,
        metadata_json                             TEXT NOT NULL DEFAULT '{}',
        environment_json                          TEXT NOT NULL DEFAULT '{}',
        statistics_json                           TEXT NOT NULL DEFAULT '{}',
        last_prompt_metadata_json                 TEXT NOT NULL DEFAULT '{}',
        recent_errors_json                        TEXT NOT NULL DEFAULT '[]',
        todo_items_json                           TEXT NOT NULL DEFAULT '[]',
        plan_history_json                         TEXT NOT NULL DEFAULT '[]'
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_sessions_updated_at ON sessions(updated_at)',
    );

    // ----- Messages (one per row, linked to session) -----
    batch.execute('''
      CREATE TABLE messages (
        id              TEXT PRIMARY KEY,
        session_id      TEXT NOT NULL,
        sort_order      INTEGER NOT NULL,
        kind            TEXT NOT NULL,
        role            TEXT NOT NULL,
        content         TEXT NOT NULL DEFAULT '',
        created_at      TEXT NOT NULL,
        character_count INTEGER NOT NULL DEFAULT 0,
        is_deleted      INTEGER NOT NULL DEFAULT 0,
        model_id        TEXT,
        model_label     TEXT,
        usage_json      TEXT,
        metadata_json   TEXT NOT NULL DEFAULT '{}',
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_messages_session_id ON messages(session_id)',
    );
    batch.execute(
      'CREATE INDEX idx_messages_session_order ON messages(session_id, sort_order)',
    );

    // ----- User memory entries -----
    batch.execute('''
      CREATE TABLE memories (
        id          TEXT PRIMARY KEY,
        type        TEXT NOT NULL DEFAULT 'user',
        created_at  TEXT NOT NULL,
        content     TEXT NOT NULL DEFAULT '',
        tags_json   TEXT NOT NULL DEFAULT '[]'
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_memories_created_at ON memories(created_at)',
    );

    // ----- App settings (key-value store) -----
    batch.execute('''
      CREATE TABLE app_settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // ----- Hardness engineering session (single record) -----
    batch.execute('''
      CREATE TABLE hardness_sessions (
        id        TEXT PRIMARY KEY,
        data_json TEXT NOT NULL
      )
    ''');

    // ----- Migration metadata -----
    batch.execute('''
      CREATE TABLE migration_meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await batch.commit(noResult: true);
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Future schema migrations go here.
    // Example:
    // if (oldVersion < 2) { ... }
  }
}
