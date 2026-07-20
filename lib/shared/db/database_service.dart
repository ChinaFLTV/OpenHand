import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../app/support/openhand_paths.dart';

/// 应用级 SQLite 持久化服务。
class DatabaseService {
  DatabaseService._();

  static DatabaseService? _instance;
  static Future<DatabaseService>? _initializationFuture;
  static Future<void>? _closingFuture;
  Database? _database;
  RandomAccessFile? _instanceLock;

  static const int schemaVersion = 10;
  static const String _databaseFileName = 'openhand.db';
  static const String _harnessSessionsTable = 'harness_sessions';
  static const String _harnessEngineeringTemplateId = 'harness_engineering';
  static const String _harnessConfigMetadataKey = 'harness_config';
  static const String _createUserInstructionsTableSql = '''
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
  ''';
  static const String _createUserInstructionsSortIndexSql =
      'CREATE INDEX IF NOT EXISTS idx_user_instructions_sort '
      'ON user_instructions(sort_order)';
  static const List<int> _legacyHarnessPrefixCodeUnits = <int>[
    104,
    97,
    114,
    100,
    110,
    101,
    115,
    115,
  ];
  static final String _legacyHarnessPrefix = String.fromCharCodes(
    _legacyHarnessPrefixCodeUnits,
  );
  static final String _legacyHarnessSessionsTable =
      '${_legacyHarnessPrefix}_sessions';
  static final String _legacyHarnessEngineeringTemplateId =
      '${_legacyHarnessPrefix}_engineering';
  static final String _legacyHarnessConfigMetadataKey =
      '${_legacyHarnessPrefix}_config';

  /// 获取已初始化的单例。
  static DatabaseService get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError('DatabaseService has not been initialized.');
    }
    return inst;
  }

  /// 是否已完成初始化。
  static bool get isInitialized => _instance != null;

  /// 底层数据库句柄。
  Database get database {
    final db = _database;
    if (db == null) {
      throw StateError('Database has not been opened.');
    }
    return db;
  }

  /// 数据库文件绝对路径。
  static String defaultDatabasePath() {
    return p.join(
      OpenHandPaths.homeDirectoryPath(),
      '.openhand',
      _databaseFileName,
    );
  }

  /// 幂等初始化数据库服务。
  static Future<DatabaseService> initialize({
    String? databasePath,
    bool useNoIsolateFactory = false,
  }) async {
    final closing = _closingFuture;
    if (closing != null) await closing;
    if (_instance != null) {
      return _instance!;
    }
    final pending = _initializationFuture;
    if (pending != null) return pending;
    late final Future<DatabaseService> initialization;
    initialization =
        _initialize(
          databasePath: databasePath,
          useNoIsolateFactory: useNoIsolateFactory,
        ).whenComplete(() {
          if (identical(_initializationFuture, initialization)) {
            _initializationFuture = null;
          }
        });
    _initializationFuture = initialization;
    return initialization;
  }

  static Future<DatabaseService> _initialize({
    required String? databasePath,
    required bool useNoIsolateFactory,
  }) async {
    if (_instance != null) return _instance!;

    // 桌面平台使用 FFI 数据库工厂。
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
    final lock = await File('$effectivePath.lock').open(mode: FileMode.append);
    try {
      await lock.lock();
      service._instanceLock = lock;
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
    } catch (error) {
      try {
        await lock.close();
      } catch (_) {
        // 保留首次初始化异常，避免后续调用误判成功。
      }
      if (service._instanceLock == null && error is FileSystemException) {
        throw StateError(
          'Another OpenHand instance is already using $effectivePath.',
        );
      }
      rethrow;
    }
  }

  /// 关闭数据库并释放单例。
  Future<void> close() {
    if (!identical(_instance, this)) return Future<void>.value();
    final pending = _closingFuture;
    if (pending != null) return pending;
    late final Future<void> closing;
    closing = _close().whenComplete(() {
      if (identical(_closingFuture, closing)) {
        _closingFuture = null;
      }
    });
    _closingFuture = closing;
    return closing;
  }

  Future<void> _close() async {
    final database = _database;
    final lock = _instanceLock;
    try {
      await database?.close();
    } finally {
      try {
        if (lock != null) {
          try {
            await lock.unlock();
          } finally {
            await lock.close();
          }
        }
      } finally {
        _database = null;
        _instanceLock = null;
        if (identical(_instance, this)) _instance = null;
      }
    }
  }

  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA journal_mode = WAL');
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // 会话元数据；消息单独存表。
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
        auto_title_acquired                       INTEGER NOT NULL DEFAULT 0,
        auto_title_retry_count                    INTEGER NOT NULL DEFAULT 0,
        auto_title_first_user_content             TEXT,
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

    // 会话消息。
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

    // 用户记忆。
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

    // 应用键值设置。
    batch.execute('''
      CREATE TABLE app_settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Harness Engineering 会话。
    batch.execute('''
      CREATE TABLE $_harnessSessionsTable (
        id        TEXT PRIMARY KEY,
        data_json TEXT NOT NULL
      )
    ''');

    // 数据迁移状态。
    batch.execute('''
      CREATE TABLE migration_meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 用户指令表（【指令】模块）。
    // 充当调用者可编辑的"全局提示词碎片"，启用后会被拼装到所
    // 有线程模板的 system prompt 中。
    batch.execute(_createUserInstructionsTableSql);
    batch.execute(_createUserInstructionsSortIndexSql);
    _createKnowledgeBaseSchema(batch);
    _createAiUsageSchema(batch);

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

  static void _createAiUsageSchema(Batch batch) {
    batch.execute('''
      CREATE TABLE IF NOT EXISTS ai_usage_records (
        id TEXT PRIMARY KEY,
        trace_id TEXT NOT NULL DEFAULT '',
        started_at TEXT NOT NULL,
        ended_at TEXT NOT NULL,
        local_date TEXT NOT NULL,
        local_hour TEXT NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        first_token_ms INTEGER,
        status TEXT NOT NULL DEFAULT 'success',
        error_type TEXT,
        surface TEXT NOT NULL DEFAULT 'app',
        source TEXT NOT NULL DEFAULT 'other',
        operation TEXT NOT NULL DEFAULT 'chat',
        session_id TEXT,
        thread_template_id TEXT,
        knowledge_base_id TEXT,
        provider_config_id TEXT NOT NULL DEFAULT '',
        provider_name TEXT NOT NULL DEFAULT '',
        protocol TEXT NOT NULL DEFAULT '',
        model_id TEXT NOT NULL DEFAULT '',
        api_family TEXT NOT NULL DEFAULT 'chat',
        prompt_tokens INTEGER NOT NULL DEFAULT 0,
        completion_tokens INTEGER NOT NULL DEFAULT 0,
        cache_creation_tokens INTEGER NOT NULL DEFAULT 0,
        cache_read_tokens INTEGER NOT NULL DEFAULT 0,
        reasoning_tokens INTEGER NOT NULL DEFAULT 0,
        audio_input_tokens INTEGER NOT NULL DEFAULT 0,
        image_input_tokens INTEGER NOT NULL DEFAULT 0,
        video_input_tokens INTEGER NOT NULL DEFAULT 0,
        web_search_tool_usage INTEGER NOT NULL DEFAULT 0,
        web_search_page_usage INTEGER NOT NULL DEFAULT 0,
        total_tokens INTEGER NOT NULL DEFAULT 0,
        usage_estimated INTEGER NOT NULL DEFAULT 0,
        input_cost_usd REAL,
        output_cost_usd REAL,
        cache_read_cost_usd REAL,
        cache_write_cost_usd REAL,
        total_cost_usd REAL,
        metadata_json TEXT NOT NULL DEFAULT '{}'
      )
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_usage_started_at '
      'ON ai_usage_records(started_at)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_usage_local_date '
      'ON ai_usage_records(local_date)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_usage_provider_model '
      'ON ai_usage_records(provider_config_id, model_id, started_at)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_usage_source '
      'ON ai_usage_records(source, started_at)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_usage_session '
      'ON ai_usage_records(session_id, started_at)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_usage_template '
      'ON ai_usage_records(thread_template_id, started_at)',
    );
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // v2：为记忆增加独立标题，旧数据使用空标题并由界面回退展示正文摘要。
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE memories ADD COLUMN title TEXT NOT NULL DEFAULT ''",
      );
    }
    // v3：增加用户指令表及排序索引。
    if (oldVersion < 3) {
      await db.execute(_createUserInstructionsTableSql);
      await db.execute(_createUserInstructionsSortIndexSql);
    }
    // v4：增加会话手动排序字段；空值继续按更新时间倒序排列。
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE sessions ADD COLUMN display_order INTEGER');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sessions_display_order '
        'ON sessions(display_order)',
      );
    }
    // v5：增加置顶与归档状态及其索引。
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
    // v6：持久化待执行计划声明的 Bash 操作类别，不改变运行时权限判定。
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
    if (oldVersion < 8) {
      await db.execute(
        'ALTER TABLE sessions ADD COLUMN auto_title_acquired '
        'INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE sessions ADD COLUMN auto_title_retry_count '
        'INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE sessions ADD COLUMN auto_title_first_user_content TEXT',
      );
    }
    if (oldVersion < 9) {
      await _migrateHarnessNaming(db);
    }
    if (oldVersion < 10) {
      final batch = db.batch();
      _createAiUsageSchema(batch);
      await batch.commit(noResult: true);
    }
  }

  static Future<void> _migrateHarnessNaming(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_harnessSessionsTable (
        id        TEXT PRIMARY KEY,
        data_json TEXT NOT NULL
      )
    ''');
    if (await _tableExists(db, _legacyHarnessSessionsTable)) {
      await db.execute('''
        INSERT OR REPLACE INTO $_harnessSessionsTable (id, data_json)
        SELECT id, data_json FROM $_legacyHarnessSessionsTable
      ''');
    }
    await db.update(
      'sessions',
      <String, Object?>{'template_id': _harnessEngineeringTemplateId},
      where: 'template_id = ?',
      whereArgs: <Object?>[_legacyHarnessEngineeringTemplateId],
    );
    await db.rawUpdate(
      '''
      UPDATE sessions
      SET metadata_json = REPLACE(
        REPLACE(metadata_json, ?, ?),
        ?, ?
      )
      WHERE metadata_json LIKE ? OR metadata_json LIKE ?
      ''',
      <Object?>[
        _legacyHarnessConfigMetadataKey,
        _harnessConfigMetadataKey,
        _legacyHarnessEngineeringTemplateId,
        _harnessEngineeringTemplateId,
        _sqlContainsPattern(_legacyHarnessConfigMetadataKey),
        _sqlContainsPattern(_legacyHarnessEngineeringTemplateId),
      ],
    );
  }

  static Future<bool> _tableExists(Database db, String tableName) async {
    final rows = await db.query(
      'sqlite_master',
      columns: const <String>['name'],
      where: 'type = ? AND name = ?',
      whereArgs: <Object?>['table', tableName],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static String _sqlContainsPattern(String value) {
    return '%$value%';
  }
}
