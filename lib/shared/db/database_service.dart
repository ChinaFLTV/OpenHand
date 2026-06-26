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

  static const int schemaVersion = 7;
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
  static Future<DatabaseService> initialize({
    String? databasePath,
    bool useNoIsolateFactory = false,
  }) async {
    if (_instance != null) {
      return _instance!;
    }

    // Initialize FFI for desktop platforms.
    sqfliteFfiInit();
    final effectiveFactory = useNoIsolateFactory
        ? databaseFactoryFfiNoIsolate
        : databaseFactoryFfi;

    final effectivePath = databasePath ?? defaultDatabasePath();
    final dbDirectory = Directory(p.dirname(effectivePath));
    if (!await dbDirectory.exists()) {
      await dbDirectory.create(recursive: true);
    }

    final service = DatabaseService._();
    service._database = await effectiveFactory.openDatabase(
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
        pending_plan_allowed_prompts_json         TEXT NOT NULL DEFAULT '[]',
        full_access_permission                    INTEGER NOT NULL DEFAULT 0,
        metadata_json                             TEXT NOT NULL DEFAULT '{}',
        environment_json                          TEXT NOT NULL DEFAULT '{}',
        statistics_json                           TEXT NOT NULL DEFAULT '{}',
        last_prompt_metadata_json                 TEXT NOT NULL DEFAULT '{}',
        recent_errors_json                        TEXT NOT NULL DEFAULT '[]',
        todo_items_json                           TEXT NOT NULL DEFAULT '[]',
        plan_history_json                         TEXT NOT NULL DEFAULT '[]',
        display_order                             INTEGER,
        pinned                                    INTEGER NOT NULL DEFAULT 0,
        archived                                  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_sessions_updated_at ON sessions(updated_at)',
    );
    batch.execute(
      'CREATE INDEX idx_sessions_display_order ON sessions(display_order)',
    );
    batch.execute('CREATE INDEX idx_sessions_pinned ON sessions(pinned)');
    batch.execute('CREATE INDEX idx_sessions_archived ON sessions(archived)');

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
        title       TEXT NOT NULL DEFAULT '',
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

    // 2026-04-25 — 用户指令表（【指令】模块）。
    // 充当调用者可编辑的"全局提示词碎片"，启用后会被拼装到所
    // 有线程模板的 system prompt 中。
    batch.execute('''
      CREATE TABLE user_instructions (
        id              TEXT PRIMARY KEY,
        name            TEXT NOT NULL DEFAULT '',
        body            TEXT NOT NULL DEFAULT '',
        description     TEXT NOT NULL DEFAULT '',
        version         TEXT NOT NULL DEFAULT '1.0',
        apply_to        TEXT NOT NULL DEFAULT '',
        notes_json      TEXT NOT NULL DEFAULT '[]',
        task_types_json TEXT NOT NULL DEFAULT '[]',
        keywords_json   TEXT NOT NULL DEFAULT '[]',
        enabled         INTEGER NOT NULL DEFAULT 1,
        sort_order      INTEGER NOT NULL DEFAULT 0,
        created_at      TEXT NOT NULL,
        updated_at      TEXT NOT NULL
      )
    ''');
    batch.execute(
      'CREATE INDEX idx_user_instructions_sort ON user_instructions(sort_order)',
    );
    _createKnowledgeBaseSchema(batch);

    await batch.commit(noResult: true);
  }

  static void _createKnowledgeBaseSchema(Batch batch) {
    batch.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_sources (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL DEFAULT 'note',
        original_path TEXT NOT NULL DEFAULT '',
        stored_path TEXT NOT NULL DEFAULT '',
        mime_type TEXT NOT NULL DEFAULT '',
        size_bytes INTEGER NOT NULL DEFAULT 0,
        content_hash TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending',
        error_message TEXT NOT NULL DEFAULT '',
        document_time TEXT,
        imported_at TEXT NOT NULL,
        indexed_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        metadata_json TEXT NOT NULL DEFAULT '{}'
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_chunks (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        chunk_index INTEGER NOT NULL DEFAULT 0,
        parent_chunk_id TEXT,
        title TEXT NOT NULL DEFAULT '',
        heading_path TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        content_hash TEXT NOT NULL DEFAULT '',
        char_count INTEGER NOT NULL DEFAULT 0,
        token_estimate INTEGER NOT NULL DEFAULT 0,
        start_offset INTEGER,
        end_offset INTEGER,
        page_number INTEGER,
        document_time TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        FOREIGN KEY (source_id) REFERENCES knowledge_sources(id) ON DELETE CASCADE
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        color TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_source_tags (
        source_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (source_id, tag_id),
        FOREIGN KEY (source_id) REFERENCES knowledge_sources(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES knowledge_tags(id) ON DELETE CASCADE
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_chunk_tags (
        chunk_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (chunk_id, tag_id),
        FOREIGN KEY (chunk_id) REFERENCES knowledge_chunks(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES knowledge_tags(id) ON DELETE CASCADE
      )
    ''');
    batch.execute('''
      CREATE TABLE IF NOT EXISTS knowledge_embedding_jobs (
        id TEXT PRIMARY KEY,
        chunk_id TEXT NOT NULL,
        provider_config_id TEXT NOT NULL DEFAULT '',
        model_id TEXT NOT NULL DEFAULT '',
        dimensions INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0,
        error_message TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (chunk_id) REFERENCES knowledge_chunks(id) ON DELETE CASCADE
      )
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_knowledge_sources_status ON knowledge_sources(status)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_knowledge_sources_updated_at ON knowledge_sources(updated_at)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_knowledge_sources_document_time ON knowledge_sources(document_time)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_source_id ON knowledge_chunks(source_id)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_knowledge_chunks_document_time ON knowledge_chunks(document_time)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_knowledge_embedding_jobs_status ON knowledge_embedding_jobs(status)',
    );
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // 2026-04-25: schema v2 — add `title` column to memories so the AI
    // self-learning sub-agent can keep a separate, readable title alongside
    // each memory's full content. Existing rows default to an empty title;
    // UI falls back to deriving a preview from `content` when title is
    // empty, preserving backward compatibility.
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE memories ADD COLUMN title TEXT NOT NULL DEFAULT ''",
      );
    }
    // 2026-04-25: schema v3 — introduce the user_instructions table for the
    // 【指令】 module. Old installs simply gain an empty table.
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_instructions (
          id              TEXT PRIMARY KEY,
          name            TEXT NOT NULL DEFAULT '',
          body            TEXT NOT NULL DEFAULT '',
          description     TEXT NOT NULL DEFAULT '',
          version         TEXT NOT NULL DEFAULT '1.0',
          apply_to        TEXT NOT NULL DEFAULT '',
          notes_json      TEXT NOT NULL DEFAULT '[]',
          task_types_json TEXT NOT NULL DEFAULT '[]',
          keywords_json   TEXT NOT NULL DEFAULT '[]',
          enabled         INTEGER NOT NULL DEFAULT 1,
          sort_order      INTEGER NOT NULL DEFAULT 0,
          created_at      TEXT NOT NULL,
          updated_at      TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_user_instructions_sort '
        'ON user_instructions(sort_order)',
      );
    }
    // 2026-04-26: schema v4 — add display_order to sessions for the
    // 'Thread Session Management' dialog's drag-reorder feature. Null
    // means "no manual order"; sessions sort by updated_at DESC for
    // those rows. Manual rows sort by display_order ASC first.
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE sessions ADD COLUMN display_order INTEGER');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sessions_display_order '
        'ON sessions(display_order)',
      );
    }
    // 2026-05-XX: schema v5 — pinned/archived columns for the Thread
    // Session Management dialog. Pinned sessions are forced to the top
    // (above any manual display_order); archived sessions are hidden by
    // default in both the sidebar and the manager unless explicitly
    // requested via includeArchived.
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE sessions ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE sessions ADD COLUMN archived INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sessions_pinned '
        'ON sessions(pinned)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sessions_archived '
        'ON sessions(archived)',
      );
    }
    // 2026-06-19: schema v6 — persist semantic Bash action categories
    // collected by ExitPlanMode.allowed_prompts for the currently pending
    // plan. This records implementation intent only; runtime permissions and
    // write-command confirmation remain authoritative.
    if (oldVersion < 6) {
      await db.execute(
        "ALTER TABLE sessions ADD COLUMN pending_plan_allowed_prompts_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
    if (oldVersion < 7) {
      final batch = db.batch();
      _createKnowledgeBaseSchema(batch);
      await batch.commit(noResult: true);
    }
  }
}
