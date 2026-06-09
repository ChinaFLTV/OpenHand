import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/db/database_service.dart';
import '../model/ai_session.dart';
import '../model/ai_session_message.dart';
import '../model/ai_token_usage.dart';

enum AiSessionPersistenceIssueKind { recoveredInvalidFile }

class AiSessionPersistenceIssue {
  const AiSessionPersistenceIssue({
    required this.kind,
    required this.filePath,
    this.detail,
  });

  final AiSessionPersistenceIssueKind kind;
  final String filePath;
  final String? detail;
}

class AiSessionLoadResult {
  const AiSessionLoadResult({required this.sessions, required this.issues});

  final List<AiSession> sessions;
  final List<AiSessionPersistenceIssue> issues;
}

/// Provides a page of messages for lazy-loading scenarios.
class AiSessionMessagePage {
  const AiSessionMessagePage({
    required this.messages,
    required this.totalCount,
    required this.hasMore,
  });

  final List<AiSessionMessage> messages;
  final int totalCount;
  final bool hasMore;
}

class AiSessionCompactMemorySidecar {
  const AiSessionCompactMemorySidecar({
    required this.markdownPath,
    required this.metadataPath,
    required this.markdown,
    required this.metadata,
  });

  final String markdownPath;
  final String metadataPath;
  final String markdown;
  final Map<String, Object?> metadata;

  String get checkpointMessageId =>
      '${metadata['checkpoint_message_id'] ?? ''}'.trim();

  DateTime? get checkpointCreatedAt =>
      DateTime.tryParse('${metadata['checkpoint_created_at'] ?? ''}')?.toUtc();

  Map<String, Object?> get checkpointMetadata {
    final raw = metadata['checkpoint_metadata'];
    if (raw is Map) {
      return Map<String, Object?>.from(raw);
    }
    return const <String, Object?>{};
  }

  String get summaryContent {
    const marker = '\n## Summary\n\n';
    final index = markdown.indexOf(marker);
    if (index == -1) {
      return markdown.trim();
    }
    return markdown.substring(index + marker.length).trim();
  }
}

class AiSessionStore {
  AiSessionStore({String? sessionsDirectoryPath})
    : _sessionsDirectoryPath =
          sessionsDirectoryPath ?? OpenHandPaths.defaultSessionsDirectoryPath();

  final String _sessionsDirectoryPath;

  String get sessionsDirectoryPath => _sessionsDirectoryPath;

  String get attachmentsDirectoryPath =>
      p.join(_sessionsDirectoryPath, 'attachments');

  String sessionAttachmentsDirectoryPath(String sessionId) {
    return p.join(
      attachmentsDirectoryPath,
      _requireSafeStorageIdentifier(sessionId, label: 'session id'),
    );
  }

  /// Modern per-session attachments directory used by the new attachment
  /// storage layout: `~/.openhand/sessions/{sessionId}/attachments/`.
  ///
  /// Inside this directory, individual files are named
  /// `{messageId}-{attachmentId}.{ext}`. Older attachments stored under
  /// [sessionAttachmentsDirectoryPath] continue to be honored on read because
  /// each `AiMessageAttachment` carries its full storage path.
  String perSessionAttachmentsDirectoryPath(String sessionId) {
    return p.join(
      _sessionsDirectoryPath,
      _requireSafeStorageIdentifier(sessionId, label: 'session id'),
      'attachments',
    );
  }

  String sessionCompactMemoryDirectoryPath(String sessionId) {
    return p.join(
      _sessionsDirectoryPath,
      _requireSafeStorageIdentifier(sessionId, label: 'session id'),
      'memory',
    );
  }

  String sessionCompactMemoryMarkdownPath(String sessionId) {
    return p.join(
      sessionCompactMemoryDirectoryPath(sessionId),
      'compact-latest.md',
    );
  }

  String sessionCompactMemoryMetadataPath(String sessionId) {
    return p.join(
      sessionCompactMemoryDirectoryPath(sessionId),
      'compact-latest.json',
    );
  }

  Future<void> saveCompressionMemorySidecar({
    required AiSession session,
    required AiSessionMessage checkpoint,
  }) async {
    final markdownPath = sessionCompactMemoryMarkdownPath(session.id);
    final metadataPath = sessionCompactMemoryMetadataPath(session.id);
    final metadata = <String, Object?>{
      'schema': 'openhand.compact_memory.v1',
      'session_id': session.id,
      'session_title': session.title,
      'template_id': session.templateId,
      'checkpoint_message_id': checkpoint.id,
      'checkpoint_created_at': checkpoint.createdAt.toUtc().toIso8601String(),
      'checkpoint_character_count': checkpoint.characterCount,
      'checkpoint_metadata': checkpoint.metadata,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final markdown = StringBuffer()
      ..writeln('# OpenHand Session Compact Memory')
      ..writeln()
      ..writeln('- schema: openhand.compact_memory.v1')
      ..writeln('- session_id: ${session.id}')
      ..writeln('- session_title: ${session.title}')
      ..writeln('- template_id: ${session.templateId}')
      ..writeln('- checkpoint_message_id: ${checkpoint.id}')
      ..writeln(
        '- checkpoint_created_at: ${checkpoint.createdAt.toUtc().toIso8601String()}',
      )
      ..writeln('- checkpoint_character_count: ${checkpoint.characterCount}')
      ..writeln()
      ..writeln('## Summary')
      ..writeln()
      ..writeln(checkpoint.content.trim());
    await writeFileAtomically(File(markdownPath), markdown.toString());
    await writeFileAtomically(
      File(metadataPath),
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  Future<AiSessionCompactMemorySidecar?> loadCompressionMemorySidecar(
    String sessionId,
  ) async {
    final markdownPath = sessionCompactMemoryMarkdownPath(sessionId);
    final metadataPath = sessionCompactMemoryMetadataPath(sessionId);
    final markdownFile = File(markdownPath);
    final metadataFile = File(metadataPath);
    await recoverAtomicWriteBackupIfNeeded(markdownFile);
    await recoverAtomicWriteBackupIfNeeded(metadataFile);
    if (!await markdownFile.exists()) {
      return null;
    }
    final markdown = await markdownFile.readAsString();
    Map<String, Object?> metadata = const <String, Object?>{};
    if (await metadataFile.exists()) {
      final decoded = jsonDecode(await metadataFile.readAsString());
      if (decoded is Map) {
        metadata = Map<String, Object?>.from(decoded);
      }
    }
    return AiSessionCompactMemorySidecar(
      markdownPath: markdownPath,
      metadataPath: metadataPath,
      markdown: markdown,
      metadata: metadata,
    );
  }

  Future<AiSession> restoreCompressionCheckpointFromSidecar(
    AiSession session,
  ) async {
    if (session.latestCompressionPoint != null) {
      return session;
    }
    final sidecar = await loadCompressionMemorySidecar(session.id);
    if (sidecar == null) {
      return session;
    }
    final checkpointId = sidecar.checkpointMessageId;
    final summary = sidecar.summaryContent;
    if (checkpointId.isEmpty || summary.isEmpty) {
      return session;
    }
    if (session.messages.any((message) => message.id == checkpointId)) {
      return session;
    }
    final createdAt =
        sidecar.checkpointCreatedAt ??
        session.latestCompressionAt ??
        session.updatedAt;
    final checkpoint = AiSessionMessage.compressionPoint(
      id: checkpointId,
      content: summary,
      createdAt: createdAt,
      metadata: <String, Object?>{
        ...sidecar.checkpointMetadata,
        'restored_from_compact_memory_sidecar': true,
        'compact_memory_sidecar_path': sidecar.markdownPath,
      },
    );
    return session.copyWith(
      messages: <AiSessionMessage>[...session.messages, checkpoint],
      updatedAt: session.updatedAt.isAfter(createdAt)
          ? session.updatedAt
          : createdAt,
      latestCompressionCheckpointMessageId: checkpoint.id,
      latestCompressionAt: checkpoint.createdAt,
      statistics: session.statistics.copyWith(
        totalMessageCount: session.statistics.totalMessageCount + 1,
        compressionPointCount: session.statistics.compressionPointCount + 1,
      ),
    );
  }

  /// Retained for backward compatibility (attachment management).
  String sessionFilePath(String sessionId) {
    final normalizedSessionId = _requireSafeStorageIdentifier(
      sessionId,
      label: 'session id',
    );
    return p.join(_sessionsDirectoryPath, 'session-$normalizedSessionId.json');
  }

  Database get _db => DatabaseService.instance.database;

  // ---------------------------------------------------------------------------
  // Core CRUD
  // ---------------------------------------------------------------------------

  Future<bool> exists(String sessionId) async {
    final normalizedSessionId = sessionId.trim();
    if (!_isSafeStorageIdentifier(normalizedSessionId)) {
      return false;
    }
    final rows = await _db.query(
      'sessions',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[normalizedSessionId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Loads all sessions **with their messages** (backward-compatible API).
  /// By default, sessions flagged as `archived` are excluded so the
  /// sidebar does not surface long-shelved threads. Pass
  /// [includeArchived] to load every row regardless of archive state
  /// (used by the Thread Session Management dialog).
  Future<AiSessionLoadResult> loadAll({bool includeArchived = false}) async {
    final issues = <AiSessionPersistenceIssue>[];
    final sessionRows = await _db.query(
      'sessions',
      where: includeArchived ? null : 'archived = 0',
      orderBy: _sessionsOrderBy,
    );
    if (sessionRows.isEmpty) {
      return AiSessionLoadResult(sessions: const <AiSession>[], issues: issues);
    }

    // 批量拉取所有 session 的 messages：原先 N+1 次小查询（60 个会话即 60 次
    // round trip）改为按 _kMessageBatchSize 分批 IN (...) 拉取，常见情况一两个
    // 批次拿完。结果按 session_id 分组后保持 sort_order ASC，与原行为等价。
    final ids = <String>[
      for (final row in sessionRows)
        if (row['id'] is String) row['id'] as String,
    ];
    final messagesBySessionId = await _loadMessagesBySessionIds(ids);

    final sessions = <AiSession>[];
    for (final row in sessionRows) {
      try {
        final sessionId = row['id'] as String;
        final messageRows =
            messagesBySessionId[sessionId] ?? const <Map<String, Object?>>[];
        final session = await _sessionFromRowCooperatively(row, messageRows);
        sessions.add(await restoreCompressionCheckpointFromSidecar(session));
        await _yieldAfterSessionDecodeIfNeeded(sessions.length);
      } catch (error) {
        issues.add(
          AiSessionPersistenceIssue(
            kind: AiSessionPersistenceIssueKind.recoveredInvalidFile,
            filePath: 'session id: ${row['id']}',
            detail: '$error',
          ),
        );
      }
    }

    return AiSessionLoadResult(sessions: sessions, issues: issues);
  }

  /// SQLite 单条语句的参数上限默认 999，保守取 500 以兼顾各平台 ffi 配置。
  static const int _kMessageBatchSize = 500;
  static const int _kMessageDecodeYieldBatchSize = 96;
  static const int _kSessionDecodeYieldBatchSize = 8;

  /// 按 session id 列表批量拉取 messages，结果按 session_id 分桶；
  /// 每个桶内保持 sort_order ASC 顺序。空列表入参 → 空 map。
  Future<Map<String, List<Map<String, Object?>>>> _loadMessagesBySessionIds(
    List<String> ids,
  ) async {
    final grouped = <String, List<Map<String, Object?>>>{};
    if (ids.isEmpty) return grouped;
    for (var start = 0; start < ids.length; start += _kMessageBatchSize) {
      final end = math.min(start + _kMessageBatchSize, ids.length);
      final batch = ids.sublist(start, end);
      final placeholders = List<String>.filled(batch.length, '?').join(',');
      final rows = await _db.rawQuery(
        'SELECT * FROM messages WHERE session_id IN ($placeholders) '
        'ORDER BY session_id, sort_order ASC',
        batch,
      );
      for (final row in rows) {
        final sessionId = row['session_id'];
        if (sessionId is! String) continue;
        (grouped[sessionId] ??= <Map<String, Object?>>[]).add(row);
      }
    }
    return grouped;
  }

  /// Loads **only session metadata** (no messages).  Much faster for building
  /// the sidebar session list. Like [loadAll], excludes archived rows by
  /// default.
  Future<AiSessionLoadResult> loadAllHeaders({
    bool includeArchived = false,
  }) async {
    final issues = <AiSessionPersistenceIssue>[];
    final sessionRows = await _db.query(
      'sessions',
      where: includeArchived ? null : 'archived = 0',
      orderBy: _sessionsOrderBy,
    );

    final sessions = <AiSession>[];
    for (final row in sessionRows) {
      try {
        sessions.add(_sessionFromRow(row, const <Map<String, Object?>>[]));
      } catch (error) {
        issues.add(
          AiSessionPersistenceIssue(
            kind: AiSessionPersistenceIssueKind.recoveredInvalidFile,
            filePath: 'session id: ${row['id']}',
            detail: '$error',
          ),
        );
      }
    }

    return AiSessionLoadResult(sessions: sessions, issues: issues);
  }

  /// Default ordering for the sessions table.
  ///
  /// Pinned sessions come first. Among the rest, sessions that have NEVER
  /// been manually reordered (`display_order IS NULL`) are surfaced before
  /// any manually-ordered ones, sorted by `updated_at DESC` so freshly
  /// created threads land at the top of the sidebar — this is the original
  /// sidebar behaviour and matches the user expectation that "the thread I
  /// just opened sits at the top". Sessions that the user explicitly
  /// reordered via the Thread Session Management dialog follow in their
  /// saved order.
  ///
  /// This uses `(display_order IS NULL) DESC` rather than ASC so NULLs sort
  /// above manually ordered rows. A previous ASC ordering accidentally pushed
  /// all newly-created sessions beneath any manually ordered session, making
  /// fresh threads appear to vanish from the visible sidebar when the user had
  /// scrolled off-screen below their dragged threads even though they were
  /// correctly persisted in SQLite.
  static const String _sessionsOrderBy =
      'pinned DESC, '
      '(display_order IS NULL) DESC, '
      'updated_at DESC, '
      'display_order ASC, '
      'created_at DESC';

  /// Persist a manual ordering of the supplied [orderedSessionIds]. The
  /// first id receives `display_order = 0`, the second `1`, etc. Any
  /// session id missing from the list keeps its existing order (which may
  /// be NULL). The transaction is atomic and silent on errors so the UI
  /// can fall back to the previous ordering on disk.
  Future<void> reorderSessions(List<String> orderedSessionIds) async {
    if (orderedSessionIds.isEmpty) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (var i = 0; i < orderedSessionIds.length; i++) {
        final sessionId = orderedSessionIds[i].trim();
        if (!_isSafeStorageIdentifier(sessionId)) continue;
        batch.update(
          'sessions',
          <String, Object?>{'display_order': i},
          where: 'id = ?',
          whereArgs: <Object?>[sessionId],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Sets the `pinned` flag for a single session. Pinned sessions sort
  /// to the top of every listing (above any manual `display_order`).
  Future<void> setSessionPinned(String sessionId, bool pinned) async {
    final id = sessionId.trim();
    if (!_isSafeStorageIdentifier(id)) return;
    await _db.update(
      'sessions',
      <String, Object?>{'pinned': pinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Sets the `archived` flag for a single session. Archived sessions
  /// are excluded from default loaders (sidebar) but remain accessible
  /// via [loadAll]/[loadAllHeaders] when `includeArchived: true`.
  Future<void> setSessionArchived(String sessionId, bool archived) async {
    final id = sessionId.trim();
    if (!_isSafeStorageIdentifier(id)) return;
    await _db.update(
      'sessions',
      <String, Object?>{'archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Returns a map of `sessionId -> (pinned, archived)` flags for every
  /// session in the database. The Thread Session Management dialog uses
  /// this to render badges and toggle states without bloating the
  /// in-memory `AiSession` model.
  Future<Map<String, ({bool pinned, bool archived})>> loadSessionFlags() async {
    final rows = await _db.query(
      'sessions',
      columns: const <String>['id', 'pinned', 'archived'],
    );
    final result = <String, ({bool pinned, bool archived})>{};
    for (final row in rows) {
      final id = row['id'];
      if (id is! String) continue;
      result[id] = (
        pinned: (row['pinned'] as int? ?? 0) != 0,
        archived: (row['archived'] as int? ?? 0) != 0,
      );
    }
    return result;
  }

  /// Computes the on-disk byte footprint of every session in a single
  /// pass. Returns a map of `sessionId -> bytes`. Counts the LENGTH of
  /// every TEXT column on the session row plus every TEXT column on its
  /// associated messages — this matches what a `VACUUM`-trimmed SQLite
  /// file actually pays for those rows. The query joins via correlated
  /// subquery so sessions with zero messages still receive an entry.
  ///
  /// We intentionally do this in one query rather than per-session loops
  /// so opening the Thread Session Management dialog stays O(1) round
  /// trips even with thousands of sessions.
  Future<Map<String, int>> computeAllSessionDiskBytes() async {
    final rows = await _db.rawQuery('''
      SELECT s.id AS session_id,
             COALESCE(LENGTH(s.title), 0)
               + COALESCE(LENGTH(s.template_id), 0)
               + COALESCE(LENGTH(s.template_name), 0)
               + COALESCE(LENGTH(s.template_icon_name), 0)
               + COALESCE(LENGTH(s.template_internal_version), 0)
               + COALESCE(LENGTH(s.created_at), 0)
               + COALESCE(LENGTH(s.updated_at), 0)
               + COALESCE(LENGTH(s.last_used_model_id), 0)
               + COALESCE(LENGTH(s.last_used_model_label), 0)
               + COALESCE(LENGTH(s.auto_title_generated_at), 0)
               + COALESCE(LENGTH(s.auto_title_source_message_id), 0)
               + COALESCE(LENGTH(s.latest_compression_checkpoint_message_id), 0)
               + COALESCE(LENGTH(s.latest_compression_at), 0)
               + COALESCE(LENGTH(s.mode), 0)
               + COALESCE(LENGTH(s.pending_plan), 0)
               + COALESCE(LENGTH(s.metadata_json), 0)
               + COALESCE(LENGTH(s.environment_json), 0)
               + COALESCE(LENGTH(s.statistics_json), 0)
               + COALESCE(LENGTH(s.last_prompt_metadata_json), 0)
               + COALESCE(LENGTH(s.recent_errors_json), 0)
               + COALESCE(LENGTH(s.todo_items_json), 0)
               + COALESCE(LENGTH(s.plan_history_json), 0)
               + COALESCE((
                   SELECT SUM(
                     COALESCE(LENGTH(m.id), 0)
                     + COALESCE(LENGTH(m.session_id), 0)
                     + COALESCE(LENGTH(m.kind), 0)
                     + COALESCE(LENGTH(m.role), 0)
                     + COALESCE(LENGTH(m.content), 0)
                     + COALESCE(LENGTH(m.created_at), 0)
                     + COALESCE(LENGTH(m.model_id), 0)
                     + COALESCE(LENGTH(m.model_label), 0)
                     + COALESCE(LENGTH(m.usage_json), 0)
                     + COALESCE(LENGTH(m.metadata_json), 0)
                   )
                   FROM messages m
                   WHERE m.session_id = s.id
                 ), 0) AS total_bytes
      FROM sessions s
    ''');
    final result = <String, int>{};
    for (final row in rows) {
      final id = row['session_id'];
      final bytes = row['total_bytes'];
      if (id is String && bytes is num) {
        result[id] = bytes.toInt();
      }
    }
    return result;
  }

  /// Loads a single session with all its messages.
  Future<AiSession?> loadSession(String sessionId) async {
    final normalizedId = sessionId.trim();
    if (!_isSafeStorageIdentifier(normalizedId)) return null;
    final rows = await _db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: <Object?>[normalizedId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final messageRows = await _db.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: <Object?>[normalizedId],
      orderBy: 'sort_order ASC',
    );
    final session = await _sessionFromRowCooperatively(rows.first, messageRows);
    return restoreCompressionCheckpointFromSidecar(session);
  }

  /// Loads all sessions (with messages) that belong to the given [templateId]
  /// AND whose `created_at` is on or after [minCreatedAt].
  ///
  /// Added for Hermes Talker self-learning (Task 17 / 2026-04-25). Ordered
  /// most-recently-updated first so that the scheduler prioritises active
  /// sessions when concurrency is capped.
  Future<List<AiSession>> loadSessionsByTemplate({
    required String templateId,
    required DateTime minCreatedAt,
  }) async {
    final rows = await _db.query(
      'sessions',
      where: 'template_id = ? AND created_at >= ?',
      whereArgs: <Object?>[templateId, minCreatedAt.toUtc().toIso8601String()],
      orderBy: _sessionsOrderBy,
    );
    if (rows.isEmpty) return const <AiSession>[];
    // 同 loadAll：批量 IN (...) 拉取所有 session 的 messages，避免 N+1。
    final ids = <String>[
      for (final row in rows)
        if (row['id'] is String) row['id'] as String,
    ];
    final messagesBySessionId = await _loadMessagesBySessionIds(ids);
    final sessions = <AiSession>[];
    for (final row in rows) {
      try {
        final sessionId = row['id'] as String;
        final messageRows =
            messagesBySessionId[sessionId] ?? const <Map<String, Object?>>[];
        final session = await _sessionFromRowCooperatively(row, messageRows);
        sessions.add(await restoreCompressionCheckpointFromSidecar(session));
        await _yieldAfterSessionDecodeIfNeeded(sessions.length);
      } catch (error, stack) {
        silentLog(
          'ai_session_store',
          'load template session ${row['id']}',
          error,
          stack,
        );
        // Skip rows that fail to decode; the main loadAll() path surfaces
        // persistence issues for the UI — the scheduler should stay silent.
      }
    }
    return sessions;
  }

  /// Loads a page of messages for a session (for lazy / paginated loading).
  ///
  /// Messages are ordered by [sort_order] ascending.
  /// [offset] is 0-based.  Pass [limit] = -1 to load all remaining.
  Future<AiSessionMessagePage> loadMessages(
    String sessionId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final countResult = await _db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM messages WHERE session_id = ?',
      <Object?>[sessionId],
    );
    final totalCount = (countResult.first['cnt'] as int?) ?? 0;

    final rows = await _db.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: <Object?>[sessionId],
      orderBy: 'sort_order ASC',
      limit: limit > 0 ? limit : null,
      offset: offset,
    );

    final messages = await _decodeMessagesCooperatively(rows);
    final hasMore = offset + messages.length < totalCount;

    return AiSessionMessagePage(
      messages: messages,
      totalCount: totalCount,
      hasMore: hasMore,
    );
  }

  /// Persists a complete [session] (metadata + all messages) atomically.
  Future<void> save(AiSession session) async {
    _validateSessionForStorage(session);
    final replaceMessages = !_isMetadataOnlySessionSnapshot(session);

    await _db.transaction((txn) async {
      final row = _sessionToRow(session);
      await txn.insert(
        'sessions',
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await txn.update(
        'sessions',
        row,
        where: 'id = ?',
        whereArgs: <Object?>[session.id],
      );

      if (!replaceMessages) {
        return;
      }

      // Replace all messages: delete existing, then bulk-insert.
      await txn.delete(
        'messages',
        where: 'session_id = ?',
        whereArgs: <Object?>[session.id],
      );
      final batch = txn.batch();
      for (var i = 0; i < session.messages.length; i++) {
        batch.insert(
          'messages',
          _messageToRow(session.messages[i], session.id, i),
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Persists only the session row. Use this for title, permission, model,
  /// metadata and other header-only updates so long transcripts do not pay a
  /// delete + bulk-insert cycle for every small state change.
  Future<void> saveSessionHeader(AiSession session) async {
    _validateSessionForStorage(session);
    final row = _sessionToRow(session);
    await _db.insert(
      'sessions',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await _db.update(
      'sessions',
      row,
      where: 'id = ?',
      whereArgs: <Object?>[session.id],
    );
  }

  /// Deletes a session and all its messages from the database, plus
  /// attachment files from disk.
  Future<void> delete(String sessionId) async {
    // Database CASCADE will remove messages automatically.
    await _db.delete(
      'sessions',
      where: 'id = ?',
      whereArgs: <Object?>[sessionId],
    );

    // Remove attachment files.
    final attachmentsDirectory = Directory(
      sessionAttachmentsDirectoryPath(sessionId),
    );
    if (await attachmentsDirectory.exists()) {
      await attachmentsDirectory.delete(recursive: true);
    }
  }

  Future<void> openStorageDirectory() {
    return openDirectoryInFileManager(Directory(_sessionsDirectoryPath));
  }

  /// Wipes every session row from the database (messages cascade) and
  /// removes the on-disk sessions directory tree (including all attachment
  /// subfolders and any legacy `session-*.json` files).
  ///
  /// Safe to call when the controller has no active streams. Callers should
  /// invoke `AiSessionController.refresh()` afterwards so in-memory state is
  /// rebuilt from the now-empty store.
  Future<void> clearAll() async {
    await _db.delete('sessions');
    final root = Directory(_sessionsDirectoryPath);
    if (await root.exists()) {
      // Re-create the empty directory so subsequent writes do not race on a
      // missing parent (the per-session writers `mkdir` on first use, but
      // some callers — e.g. `openStorageDirectory()` — still need a real
      // directory to open).
      await root.delete(recursive: true);
      await root.create(recursive: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Row ↔ Model conversion
  // ---------------------------------------------------------------------------

  AiSession _sessionFromRow(
    Map<String, Object?> row,
    List<Map<String, Object?>> messageRows,
  ) {
    final messages = messageRows.map(_messageFromRow).toList(growable: false);
    return _sessionFromRowWithMessages(row, messages);
  }

  Future<AiSession> _sessionFromRowCooperatively(
    Map<String, Object?> row,
    List<Map<String, Object?>> messageRows,
  ) async {
    final messages = await _decodeMessagesCooperatively(messageRows);
    return _sessionFromRowWithMessages(row, messages);
  }

  Future<List<AiSessionMessage>> _decodeMessagesCooperatively(
    List<Map<String, Object?>> messageRows,
  ) async {
    if (messageRows.isEmpty) {
      return const <AiSessionMessage>[];
    }
    final messages = <AiSessionMessage>[];
    for (var index = 0; index < messageRows.length; index++) {
      messages.add(_messageFromRow(messageRows[index]));
      final shouldYield =
          (index + 1) % _kMessageDecodeYieldBatchSize == 0 &&
          index + 1 < messageRows.length;
      if (shouldYield) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return List<AiSessionMessage>.unmodifiable(messages);
  }

  Future<void> _yieldAfterSessionDecodeIfNeeded(int decodedCount) async {
    if (decodedCount % _kSessionDecodeYieldBatchSize == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  AiSession _sessionFromRowWithMessages(
    Map<String, Object?> row,
    List<AiSessionMessage> messages,
  ) {
    final now = DateTime.now().toUtc();

    return AiSession(
      id: (row['id'] as String?) ?? '',
      title: (row['title'] as String?) ?? '',
      templateId: (row['template_id'] as String?) ?? '',
      templateName: (row['template_name'] as String?) ?? '',
      templateIconName: (row['template_icon_name'] as String?) ?? '',
      templateInternalVersion:
          (row['template_internal_version'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((row['created_at'] as String?) ?? '')?.toUtc() ??
          now,
      updatedAt:
          DateTime.tryParse((row['updated_at'] as String?) ?? '')?.toUtc() ??
          now,
      messages: messages,
      environment: AiSessionEnvironment.fromJson(
        _decodeJsonMap(row['environment_json']),
      ),
      statistics: AiSessionStatistics.fromJson(
        _decodeJsonMap(row['statistics_json']),
      ),
      recentErrors: _decodeJsonList(row['recent_errors_json'])
          .map(
            (item) => AiSessionErrorRecord.fromJson(
              item is Map<String, Object?>
                  ? item
                  : item is Map
                  ? Map<String, Object?>.from(item)
                  : const <String, Object?>{},
            ),
          )
          .toList(growable: false),
      lastUsedModelId: row['last_used_model_id'] as String?,
      lastUsedModelLabel: row['last_used_model_label'] as String?,
      isTitleManuallyEdited: (row['is_title_manually_edited'] as int?) == 1,
      autoTitleGeneratedAt: _parseNullableDateTime(
        row['auto_title_generated_at'] as String?,
      ),
      autoTitleSourceMessageId: row['auto_title_source_message_id'] as String?,
      latestCompressionCheckpointMessageId:
          row['latest_compression_checkpoint_message_id'] as String?,
      latestCompressionAt: _parseNullableDateTime(
        row['latest_compression_at'] as String?,
      ),
      mode: AiSessionMode.fromStorage((row['mode'] as String?) ?? 'chat'),
      awaitingPlanApproval: (row['awaiting_plan_approval'] as int?) == 1,
      pendingPlan: row['pending_plan'] as String?,
      fullAccessPermission: (row['full_access_permission'] as int?) == 1,
      metadata: _decodeJsonMap(row['metadata_json']),
      lastPromptMetadata: _decodeJsonMap(row['last_prompt_metadata_json']),
      todoItems: _decodeJsonList(row['todo_items_json'])
          .map(
            (item) => AiSessionTodoItem.fromJson(
              item is Map<String, Object?>
                  ? item
                  : item is Map
                  ? Map<String, Object?>.from(item)
                  : const <String, Object?>{},
            ),
          )
          .toList(growable: false),
      planHistory: _decodeJsonList(row['plan_history_json'])
          .map(
            (item) => AiSessionPlanRecord.fromJson(
              item is Map<String, Object?>
                  ? item
                  : item is Map
                  ? Map<String, Object?>.from(item)
                  : const <String, Object?>{},
            ),
          )
          .toList(growable: false),
    );
  }

  bool _isMetadataOnlySessionSnapshot(AiSession session) {
    return session.messages.isEmpty && session.statistics.totalMessageCount > 0;
  }

  Map<String, Object?> _sessionToRow(AiSession session) {
    return <String, Object?>{
      'id': session.id,
      'title': session.title,
      'template_id': session.templateId,
      'template_name': session.templateName,
      'template_icon_name': session.templateIconName,
      'template_internal_version': session.templateInternalVersion,
      'created_at': session.createdAt.toUtc().toIso8601String(),
      'updated_at': session.updatedAt.toUtc().toIso8601String(),
      'last_used_model_id': session.lastUsedModelId,
      'last_used_model_label': session.lastUsedModelLabel,
      'is_title_manually_edited': session.isTitleManuallyEdited ? 1 : 0,
      'auto_title_generated_at': session.autoTitleGeneratedAt
          ?.toUtc()
          .toIso8601String(),
      'auto_title_source_message_id': session.autoTitleSourceMessageId,
      'latest_compression_checkpoint_message_id':
          session.latestCompressionCheckpointMessageId,
      'latest_compression_at': session.latestCompressionAt
          ?.toUtc()
          .toIso8601String(),
      'mode': session.mode.storageValue,
      'awaiting_plan_approval': session.awaitingPlanApproval ? 1 : 0,
      'pending_plan': session.pendingPlan,
      'full_access_permission': session.fullAccessPermission ? 1 : 0,
      'metadata_json': jsonEncode(session.metadata),
      'environment_json': jsonEncode(session.environment.toJson()),
      'statistics_json': jsonEncode(session.statistics.toJson()),
      'last_prompt_metadata_json': jsonEncode(session.lastPromptMetadata),
      'recent_errors_json': jsonEncode(
        session.recentErrors
            .map((item) => item.toJson())
            .toList(growable: false),
      ),
      'todo_items_json': jsonEncode(
        session.todoItems.map((item) => item.toJson()).toList(growable: false),
      ),
      'plan_history_json': jsonEncode(
        session.planHistory
            .map((item) => item.toJson())
            .toList(growable: false),
      ),
    };
  }

  AiSessionMessage _messageFromRow(Map<String, Object?> row) {
    final usageRaw = row['usage_json'] as String?;
    AiTokenUsage? usage;
    if (usageRaw != null && usageRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(usageRaw);
        if (decoded is Map) {
          usage = AiTokenUsage.fromJson(Map<String, Object?>.from(decoded));
        }
      } catch (error, stack) {
        silentLog('ai_session_store', 'decode usage_json column', error, stack);
      }
    }

    return AiSessionMessage(
      id: (row['id'] as String?) ?? '',
      kind: AiSessionMessageKind.fromStorage((row['kind'] as String?) ?? ''),
      role: AiSessionMessageRole.fromStorage((row['role'] as String?) ?? ''),
      content: (row['content'] as String?) ?? '',
      createdAt:
          DateTime.tryParse((row['created_at'] as String?) ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      characterCount: (row['character_count'] as int?) ?? 0,
      isDeleted: (row['is_deleted'] as int?) == 1,
      modelId: row['model_id'] as String?,
      modelLabel: row['model_label'] as String?,
      usage: usage,
      metadata: _decodeJsonMap(row['metadata_json']),
    );
  }

  Map<String, Object?> _messageToRow(
    AiSessionMessage message,
    String sessionId,
    int sortOrder,
  ) {
    return <String, Object?>{
      'id': message.id,
      'session_id': sessionId,
      'sort_order': sortOrder,
      'kind': message.kind.storageValue,
      'role': message.role.storageValue,
      'content': message.content,
      'created_at': message.createdAt.toUtc().toIso8601String(),
      'character_count': message.characterCount,
      'is_deleted': message.isDeleted ? 1 : 0,
      'model_id': message.modelId,
      'model_label': message.modelLabel,
      'usage_json': message.usage != null
          ? jsonEncode(message.usage!.toJson())
          : null,
      'metadata_json': jsonEncode(message.metadata),
    };
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _decodeJsonMap(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, Object?>) return decoded;
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } catch (error, stack) {
        silentLog('ai_session_store', 'decode json map', error, stack);
      }
    }
    return const <String, Object?>{};
  }

  static List<Object?> _decodeJsonList(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded;
      } catch (error, stack) {
        silentLog('ai_session_store', 'decode json list', error, stack);
      }
    }
    return const <Object?>[];
  }

  static DateTime? _parseNullableDateTime(String? value) {
    if (value == null || value.isEmpty || value == 'null') return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}

// ---------------------------------------------------------------------------
// Validation helpers (preserved from original)
// ---------------------------------------------------------------------------

final RegExp _unsafeStorageIdentifierPattern = RegExp(
  r'[\u0000-\u001F\u007F/\\]',
);

String _requireSafeStorageIdentifier(String value, {required String label}) {
  final normalizedValue = value.trim();
  if (!_isSafeStorageIdentifier(normalizedValue)) {
    throw FormatException('Invalid $label: $value');
  }
  return normalizedValue;
}

bool _isSafeStorageIdentifier(String value) {
  final normalizedValue = value.trim();
  return normalizedValue.isNotEmpty &&
      normalizedValue != '.' &&
      normalizedValue != '..' &&
      !_unsafeStorageIdentifierPattern.hasMatch(normalizedValue);
}

void _validateSessionForStorage(
  AiSession session, {
  Set<String>? seenSessionIds,
  bool checkDuplicateSessionIds = false,
}) {
  final sessionId = _requireSafeStorageIdentifier(
    session.id,
    label: 'session id',
  );
  if (checkDuplicateSessionIds &&
      seenSessionIds != null &&
      !seenSessionIds.add(sessionId)) {
    throw FormatException('Duplicate session id detected: $sessionId');
  }

  final seenMessageIds = <String>{};
  for (final message in session.messages) {
    final messageId = _requireSafeStorageIdentifier(
      message.id,
      label: 'message id',
    );
    if (!seenMessageIds.add(messageId)) {
      throw FormatException(
        'Duplicate message id detected in session $sessionId: $messageId',
      );
    }
  }
}
