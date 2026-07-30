import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/db/database_service.dart';
import '../../../shared/util/bounded_delete.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/serial_task_queue.dart';
import '../../../shared/util/storage_identifier.dart';
import '../../knowledge_base/index.dart';
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

/// 面向懒加载场景的有界消息页。
class AiSessionMessagePage {
  const AiSessionMessagePage({
    required this.messages,
    required this.offset,
    required this.totalCount,
    required this.hasMore,
  });

  final List<AiSessionMessage> messages;
  final int offset;
  final int totalCount;
  final bool hasMore;
}

class AiSessionTemplateCursor {
  const AiSessionTemplateCursor({
    required this.createdAtText,
    required this.sessionId,
  });

  final String createdAtText;
  final String sessionId;
}

class AiSessionTemplatePage {
  const AiSessionTemplatePage({
    required this.sessions,
    required this.nextCursor,
  });

  final List<AiSession> sessions;
  final AiSessionTemplateCursor? nextCursor;
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
      utcDateTimeFromValue(metadata['checkpoint_created_at']);

  Map<String, Object?> get checkpointMetadata {
    final raw = metadata['checkpoint_metadata'];
    return stringKeyedMapFromValue(raw);
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
          sessionsDirectoryPath ??
          OpenHandPaths.defaultSessionsDirectoryPath() {
    if (sessionsDirectoryPath != null &&
        nullIfBlank(sessionsDirectoryPath) == null) {
      throw ArgumentError.value(
        sessionsDirectoryPath,
        'sessionsDirectoryPath',
        'Must not be blank.',
      );
    }
  }

  static const int _compactMemoryMarkdownMaxBytes = 16 * kBytesPerMiB;
  static const int _compactMemoryMetadataMaxBytes = 2 * kBytesPerMiB;
  static const String _compactMemoryGenerationPrefix = '- generation: ';
  static const int _maxPendingSessionCleanups = 2048;
  static const int _pendingSessionCleanupRetryBatchSize = 4;
  static const int _pendingSessionCleanupMaxBytes = 256 * kBytesPerKiB;
  static const String _pendingSessionCleanupSettingPrefix =
      'ai_session_cleanup:';
  static const BoundedDeletePolicy _pendingSessionCleanupDeletePolicy =
      BoundedDeletePolicy(
        maxEntries: 100000,
        maxDepth: 128,
        directoryIdleTimeout: Duration(seconds: 2),
        operationTimeout: Duration(seconds: 5),
        totalTimeout: Duration(seconds: 10),
      );

  final String _sessionsDirectoryPath;
  final SerialTaskQueue _sessionCleanupQueue = SerialTaskQueue();
  Future<void>? _pendingSessionCleanupRetry;

  String get sessionsDirectoryPath => _sessionsDirectoryPath;

  String get attachmentsDirectoryPath =>
      p.join(_sessionsDirectoryPath, 'attachments');

  String sessionAttachmentsDirectoryPath(String sessionId) {
    return p.join(
      attachmentsDirectoryPath,
      requireSafeStorageIdentifier(sessionId, label: '会话标识符'),
    );
  }

  String sessionDirectoryPath(String sessionId) {
    return p.join(
      _sessionsDirectoryPath,
      requireSafeStorageIdentifier(sessionId, label: '会话标识符'),
    );
  }

  String sessionToolResultsDirectoryPath(String sessionId) {
    return p.join(sessionDirectoryPath(sessionId), 'tool-results');
  }

  /// Modern per-session attachments directory used by the new attachment
  /// storage layout: `~/.openhand/sessions/{sessionId}/attachments/`.
  ///
  /// Inside this directory, individual files are named
  /// `{messageId}-{attachmentId}.{ext}`. Older attachments stored under
  /// [sessionAttachmentsDirectoryPath] continue to be honored on read because
  /// each `AiMessageAttachment` carries its full storage path.
  String perSessionAttachmentsDirectoryPath(String sessionId) {
    return p.join(sessionDirectoryPath(sessionId), 'attachments');
  }

  String sessionCompactMemoryDirectoryPath(String sessionId) {
    return p.join(sessionDirectoryPath(sessionId), 'memory');
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
    final generation =
        '${checkpoint.id}:${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final metadata = <String, Object?>{
      'schema': 'openhand.compact_memory.v1',
      'session_id': session.id,
      'session_title': session.title,
      'template_id': session.templateId,
      'checkpoint_message_id': checkpoint.id,
      'checkpoint_created_at': checkpoint.createdAt.toUtc().toIso8601String(),
      'checkpoint_character_count': checkpoint.characterCount,
      'checkpoint_metadata': checkpoint.metadata,
      'generation': generation,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final markdown =
        (StringBuffer()
              ..writeln('# OpenHand Session Compact Memory')
              ..writeln()
              ..writeln('- schema: openhand.compact_memory.v1')
              ..writeln('- session_id: ${session.id}')
              ..writeln('- session_title: ${session.title}')
              ..writeln('- template_id: ${session.templateId}')
              ..writeln('- checkpoint_message_id: ${checkpoint.id}')
              ..writeln('$_compactMemoryGenerationPrefix$generation')
              ..writeln(
                '- checkpoint_created_at: ${checkpoint.createdAt.toUtc().toIso8601String()}',
              )
              ..writeln(
                '- checkpoint_character_count: ${checkpoint.characterCount}',
              )
              ..writeln()
              ..writeln('## Summary')
              ..writeln()
              ..writeln(checkpoint.content.trim()))
            .toString();
    final metadataJson = prettyPrintJson(metadata);
    if (utf8.encode(markdown).length > _compactMemoryMarkdownMaxBytes) {
      throw const FileSystemException(
        'Compact memory markdown exceeds the 16 MiB limit.',
      );
    }
    if (utf8.encode(metadataJson).length > _compactMemoryMetadataMaxBytes) {
      throw const FileSystemException(
        'Compact memory metadata exceeds the 2 MiB limit.',
      );
    }
    await writeFileAtomically(File(markdownPath), markdown);
    await writeFileAtomically(File(metadataPath), metadataJson);
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
    if (!await regularFileExistsBounded(markdownFile)) {
      return null;
    }
    final markdown = await readBoundedFileString(
      markdownFile,
      maxBytes: _compactMemoryMarkdownMaxBytes,
    );
    Map<String, Object?> metadata = const <String, Object?>{};
    try {
      if (await regularFileExistsBounded(metadataFile)) {
        final decoded = jsonDecode(
          await readBoundedFileString(
            metadataFile,
            maxBytes: _compactMemoryMetadataMaxBytes,
          ),
        );
        if (decoded is Map) {
          metadata = stringKeyedMapFromValue(decoded);
        }
      }
    } catch (error, stack) {
      silentLog('ai_session_store', '加载压缩记忆元数据', error, stack);
    }
    final markdownGeneration = _compactMemoryMarkdownGeneration(markdown);
    final metadataGeneration = '${metadata['generation'] ?? ''}'.trim();
    if ((markdownGeneration.isNotEmpty || metadataGeneration.isNotEmpty) &&
        markdownGeneration != metadataGeneration) {
      silentLog(
        'ai_session_store',
        '加载压缩记忆附属文件',
        const FormatException('压缩记忆附属文件版本不匹配。'),
        StackTrace.current,
      );
      return null;
    }
    return AiSessionCompactMemorySidecar(
      markdownPath: markdownPath,
      metadataPath: metadataPath,
      markdown: markdown,
      metadata: metadata,
    );
  }

  String _compactMemoryMarkdownGeneration(String markdown) {
    for (final line in const LineSplitter().convert(markdown)) {
      if (line.startsWith(_compactMemoryGenerationPrefix)) {
        return line.substring(_compactMemoryGenerationPrefix.length).trim();
      }
      if (line == '## Summary') break;
    }
    return '';
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
      messageLoadState: session.messageLoadState,
      messageWindowStartIndex: session.messageWindowStartIndex,
      messageTotalCount: session.messageTotalCount + 1,
    );
  }

  /// Retained for backward compatibility (attachment management).
  String sessionFilePath(String sessionId) {
    final normalizedSessionId = requireSafeStorageIdentifier(
      sessionId,
      label: '会话标识符',
    );
    return p.join(_sessionsDirectoryPath, 'session-$normalizedSessionId.json');
  }

  Database get _db => DatabaseService.instance.database;
  // Core CRUD
  Future<bool> exists(String sessionId) async {
    final normalizedSessionId = sessionId.trim();
    if (!isSafeStorageIdentifier(normalizedSessionId)) {
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

  /// SQLite 单条语句的参数上限默认 999，保守取 500 以兼顾各平台 ffi 配置。
  static const int _kMessageBatchSize = 500;
  static const int _kMessageDecodeYieldBatchSize = 96;
  static const int _kSessionDecodeYieldBatchSize = 8;
  static const int defaultTemplateSessionPageSize = 50;
  static const int maxTemplateSessionPageSize = 200;
  static const int _kTranscriptToolPairContextBatchSize = 8;
  static const int _kTranscriptToolPairContextMaxMessages = 96;
  static const String _kPromptMetadataKey = 'prompt_metadata';
  static const List<String> _kStatisticsMetadataKeys = <String>[
    aiSessionMessageSenderOriginJsonKey,
    aiSessionGoalEvaluationMessageMetadataKey,
    'plan_mode_approved',
    'idle_gap_seconds',
    'stable_prefix_hash',
    'previous_stable_prefix_hash',
    'tool_catalog_hash',
    'previous_tool_catalog_hash',
    'cache_enabled',
    'input_cache_enabled',
    'cache_control_strategy',
    'cache_provider_automatic_cache_protected',
    'cache_provider_automatic_cache_best_effort',
    'cache_affinity_enabled',
    'cache_protocol_controlled',
    'request_cache_control_marker_count',
    'request_cache_affinity_marker_count',
    'cache_affinity_degraded',
    'request_payload_prefix_continuity',
    'request_payload_prefix_probe_complete',
  ];
  static const Set<String> _kStatisticsBooleanMetadataKeys = <String>{
    aiSessionGoalEvaluationMessageMetadataKey,
    'plan_mode_approved',
  };
  static const List<String> _kMessageRowColumnsWithoutMetadata = <String>[
    'id',
    'session_id',
    'sort_order',
    'kind',
    'role',
    'content',
    'created_at',
    'character_count',
    'is_deleted',
    'model_id',
    'model_label',
    'usage_json',
  ];
  static const List<String> _kStatisticsMessageRowColumnsWithoutMetadata =
      <String>[
        'id',
        'session_id',
        'sort_order',
        'kind',
        'role',
        "CASE WHEN content = '' THEN '' ELSE '1' END AS content",
        'created_at',
        'character_count',
        'is_deleted',
        'model_id',
        'model_label',
        'usage_json',
      ];
  static final String _kDeferredTelemetryMetadataProjection =
      'json_remove(metadata_json, '
      '${aiSessionMessageDeferredTelemetryMetadataKeys.map((key) => "'\$.$key'").join(', ')}) '
      'AS metadata_json';
  static final String _kStatisticsMetadataProjection =
      'json_object('
      '${_kStatisticsMetadataKeys.map(_statisticsMetadataColumn).join(', ')}'
      ') AS metadata_json';
  // 协作式解码的字节预算：仅按"条数"让步在首屏尾窗（≤24 条）下永不触发，
  // 一旦窗口里夹着大消息（长工具结果 / 大 metadata），整窗会在一帧内同步
  // jsonDecode + 模型构建，直接撑爆帧预算造成卡死 / ANR。改为额外按累计
  // 解码成本让步：每累积约 16KB 字符就让出一次事件循环，使 UI 能在重负载
  // 消息之间稳定绘制水合占位帧，把首屏开销摊到多帧而非一帧。
  static const int _kMessageDecodeYieldCostBudget = 16000;
  static const int _kTailMessageContentPreviewChars = 4096;
  static const String _kTailContentPreviewAlias = 'content';

  static List<String> _tailMessageRowColumnsWithoutMetadata(int previewChars) {
    final boundedPreviewChars = math.max(1, previewChars);
    return <String>[
      'id',
      'session_id',
      'sort_order',
      'kind',
      'role',
      'substr(content, 1, $boundedPreviewChars) AS $_kTailContentPreviewAlias',
      'created_at',
      'character_count',
      'is_deleted',
      'model_id',
      'model_label',
      'usage_json',
      'CASE WHEN length(content) > $boundedPreviewChars THEN 1 ELSE 0 END '
          'AS $aiSessionMessageContentPreviewMetadataKey',
    ];
  }

  static String _statisticsMetadataColumn(String key) {
    if (_kStatisticsBooleanMetadataKeys.contains(key)) {
      return "'$key', CASE json_type(metadata_json, '\$.$key') "
          "WHEN 'true' THEN json('true') "
          "WHEN 'false' THEN json('false') END";
    }
    return "'$key', COALESCE(json_extract(metadata_json, '\$.$key'), "
        "json_extract(metadata_json, '\$.$_kPromptMetadataKey.$key'))";
  }

  /// 按 session id 列表批量拉取 messages，结果按 session_id 分桶；
  /// 每个桶内保持 sort_order ASC 顺序。空列表入参 → 空 map。
  Future<Map<String, List<Map<String, Object?>>>> _loadMessagesBySessionIds(
    List<String> ids,
  ) async {
    final grouped = <String, List<Map<String, Object?>>>{};
    final rows = await _rawQueryBySessionIdBatches(
      ids,
      (placeholders) =>
          'SELECT * FROM messages WHERE session_id IN ($placeholders) '
          'ORDER BY session_id, sort_order ASC',
    );
    for (final row in rows) {
      final sessionId = row['session_id'];
      if (sessionId is! String) continue;
      (grouped[sessionId] ??= <Map<String, Object?>>[]).add(row);
    }
    return grouped;
  }

  Future<Map<String, int>> _loadMessageCountsBySessionIds(
    List<String> ids,
  ) async {
    final counts = <String, int>{};
    final rows = await _rawQueryBySessionIdBatches(
      ids,
      (placeholders) =>
          'SELECT session_id, COUNT(*) AS message_count '
          'FROM messages WHERE session_id IN ($placeholders) '
          'GROUP BY session_id',
    );
    for (final row in rows) {
      final sessionId = row['session_id'];
      final count = row['message_count'];
      if (sessionId is String && count is num) {
        counts[sessionId] = count.toInt();
      }
    }
    return counts;
  }

  Future<List<Map<String, Object?>>> _rawQueryBySessionIdBatches(
    List<String> ids,
    String Function(String placeholders) sqlForPlaceholders,
  ) async {
    if (ids.isEmpty) return const <Map<String, Object?>>[];
    final rows = <Map<String, Object?>>[];
    for (var start = 0; start < ids.length; start += _kMessageBatchSize) {
      final end = math.min(start + _kMessageBatchSize, ids.length);
      final batch = ids.sublist(start, end);
      final placeholders = List<String>.filled(batch.length, '?').join(',');
      rows.addAll(await _db.rawQuery(sqlForPlaceholders(placeholders), batch));
    }
    return rows;
  }

  /// Loads **only session metadata** (no messages). Much faster and safer for
  /// building the sidebar session list. Excludes archived rows by default.
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
    final sessionIds = <String>[
      for (final row in sessionRows)
        if (row['id'] is String) row['id'] as String,
    ];
    final messageCountsBySessionId = await _loadMessageCountsBySessionIds(
      sessionIds,
    );
    for (final row in sessionRows) {
      try {
        final sessionId = row['id'] as String;
        sessions.add(
          _sessionFromRow(
            row,
            const <Map<String, Object?>>[],
            messageLoadState: AiSessionMessageLoadState.header,
            messageTotalCount: messageCountsBySessionId[sessionId] ?? 0,
          ),
        );
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

    _schedulePendingSessionCleanupRetry();
    return AiSessionLoadResult(sessions: sessions, issues: issues);
  }

  Future<AiSession?> loadHeader(String sessionId) async {
    final normalizedSessionId = requireSafeStorageIdentifier(
      sessionId,
      label: '会话标识符',
    );
    final rows = await _db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: <Object?>[normalizedSessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final countRows = await _db.rawQuery(
      'SELECT COUNT(*) AS message_count FROM messages WHERE session_id = ?',
      <Object?>[normalizedSessionId],
    );
    final messageCount = countRows.isEmpty
        ? 0
        : nonNegativeIntFromValue(
            countRows.first['message_count'],
            fallback: 0,
          );
    return _sessionFromRow(
      rows.first,
      const <Map<String, Object?>>[],
      messageLoadState: AiSessionMessageLoadState.header,
      messageTotalCount: messageCount,
    );
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
      'display_order ASC, '
      'updated_at DESC, '
      'created_at DESC, '
      'id ASC';

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
        if (!isSafeStorageIdentifier(sessionId)) continue;
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
    if (!isSafeStorageIdentifier(id)) return;
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
    if (!isSafeStorageIdentifier(id)) return;
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
        pinned: boolFromValue(row['pinned']),
        archived: boolFromValue(row['archived']),
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
               + COALESCE(LENGTH(s.auto_title_acquired), 0)
               + COALESCE(LENGTH(s.auto_title_retry_count), 0)
               + COALESCE(LENGTH(s.auto_title_first_user_content), 0)
               + COALESCE(LENGTH(s.auto_title_generated_at), 0)
               + COALESCE(LENGTH(s.auto_title_source_message_id), 0)
               + COALESCE(LENGTH(s.latest_compression_checkpoint_message_id), 0)
               + COALESCE(LENGTH(s.latest_compression_at), 0)
               + COALESCE(LENGTH(s.mode), 0)
               + COALESCE(LENGTH(s.pending_plan), 0)
               + COALESCE(LENGTH(s.pending_plan_allowed_prompts_json), 0)
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
    if (!isSafeStorageIdentifier(normalizedId)) return null;
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

  /// 加载统计修复所需的轻量会话快照，不传输完整正文与审计大字段。
  Future<AiSession?> loadSessionStatisticsSnapshot(String sessionId) async {
    final normalizedId = sessionId.trim();
    if (!isSafeStorageIdentifier(normalizedId)) return null;
    final rows = await _db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: <Object?>[normalizedId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final messageRows = await _queryMessageRows(
      columnsWithoutMetadata: _kStatisticsMessageRowColumnsWithoutMetadata,
      where: 'session_id = ?',
      whereArgs: <Object?>[normalizedId],
      orderBy: 'sort_order ASC',
      deferTelemetryMetadata: true,
      statisticsMetadataOnly: true,
    );
    return _sessionFromRowCooperatively(rows.first, messageRows);
  }

  /// 仅加载会话最新的 [limit] 条消息。
  ///
  /// 这是长会话首次打开时的快速路径，使首个可交互帧不受历史总量影响；
  /// 后续需要完整提示词历史时再通过 [loadSession] 升级加载。
  Future<AiSession?> loadSessionTailWindow(
    String sessionId, {
    required int limit,
    int? characterBudget,
    AiSession? sessionHeader,
  }) async {
    final normalizedId = sessionId.trim();
    if (!isSafeStorageIdentifier(normalizedId)) return null;
    final reusableHeader = sessionHeader?.id == normalizedId
        ? sessionHeader
        : null;
    Map<String, Object?>? sessionRow;
    if (reusableHeader == null) {
      final rows = await _db.query(
        'sessions',
        where: 'id = ?',
        whereArgs: <Object?>[normalizedId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      sessionRow = rows.first;
    }

    Future<AiSession> buildWindow(
      List<Map<String, Object?>> messageRows, {
      AiSessionMessageLoadState messageLoadState =
          AiSessionMessageLoadState.complete,
      int messageWindowStartIndex = 0,
      required int messageTotalCount,
      Map<String, Object?>? leadingKnowledgeBaseMetadata,
    }) async {
      if (reusableHeader == null) {
        return _sessionFromRowCooperatively(
          sessionRow!,
          messageRows,
          messageLoadState: messageLoadState,
          messageWindowStartIndex: messageWindowStartIndex,
          messageTotalCount: messageTotalCount,
          leadingKnowledgeBaseMetadata: leadingKnowledgeBaseMetadata,
        );
      }
      final messages = await _decodeMessagesCooperatively(
        messageRows,
        leadingKnowledgeBaseMetadata: leadingKnowledgeBaseMetadata,
      );
      return reusableHeader.copyWith(
        messages: messages,
        messageLoadState: messageLoadState,
        messageWindowStartIndex: messageWindowStartIndex,
        messageTotalCount: messageTotalCount,
      );
    }

    final totalCount = await _countMessages(normalizedId);
    if (totalCount <= 0) {
      return buildWindow(const <Map<String, Object?>>[], messageTotalCount: 0);
    }
    final effectiveLimit = _boundedMessageLoadLimit(
      requestedLimit: limit,
      totalCount: totalCount,
    );
    final previewChars = characterBudget == null || characterBudget <= 0
        ? _kTailMessageContentPreviewChars
        : math.min(characterBudget, _kTailMessageContentPreviewChars);
    final rawRows = await _queryMessageRows(
      columnsWithoutMetadata: _tailMessageRowColumnsWithoutMetadata(
        previewChars,
      ),
      where: 'session_id = ?',
      whereArgs: <Object?>[normalizedId],
      orderBy: 'sort_order DESC',
      limit: effectiveLimit,
      deferTelemetryMetadata: true,
    );
    final messageRows = _trimTailRowsToBudget(
      rawRows,
      characterBudget: characterBudget,
    );
    final leadingKnowledgeBaseMetadata =
        await _leadingKnowledgeBaseMetadataForWindowStart(
          normalizedId,
          messageRows,
        );
    final offset = _messageWindowStartOffset(
      messageRows,
      fallback: nonNegativeRemaining(totalCount, messageRows.length),
    );
    final hasContentPreviews = messageRows.any(
      (row) => row[aiSessionMessageContentPreviewMetadataKey] == 1,
    );
    final loadState =
        offset == 0 && messageRows.length >= totalCount && !hasContentPreviews
        ? AiSessionMessageLoadState.complete
        : AiSessionMessageLoadState.windowed;
    var session = await buildWindow(
      messageRows,
      messageLoadState: loadState,
      messageWindowStartIndex: offset,
      messageTotalCount: totalCount,
      leadingKnowledgeBaseMetadata: leadingKnowledgeBaseMetadata,
    );
    final expanded = await _prependTranscriptToolCallContext(
      normalizedId,
      messages: session.messages,
      offset: offset,
      deferTelemetryMetadata: true,
      characterBudget: characterBudget,
    );
    if (expanded.offset != offset) {
      final expandedHasContentPreviews = expanded.messages.any(
        (message) =>
            message.metadata[aiSessionMessageContentPreviewMetadataKey] == true,
      );
      final expandedLoadState =
          expanded.offset == 0 &&
              expanded.messages.length >= totalCount &&
              !expandedHasContentPreviews
          ? AiSessionMessageLoadState.complete
          : AiSessionMessageLoadState.windowed;
      session = session.copyWith(
        messages: expanded.messages,
        messageLoadState: expandedLoadState,
        messageWindowStartIndex: expanded.offset,
        messageTotalCount: totalCount,
      );
    }
    // 尾部窗口只服务首屏。向局部尾窗恢复旧压缩旁路文件既会增加磁盘开销，
    // 也会把历史检查点错误放到可见尾部；完整加载仍会在构建提示词前恢复。
    return session.hasCompleteMessages
        ? restoreCompressionCheckpointFromSidecar(session)
        : session;
  }

  int _boundedMessageLoadLimit({
    required int requestedLimit,
    required int totalCount,
  }) {
    if (totalCount <= 0) return 0;
    final safeLimit = requestedLimit.clamp(1, _kMessageBatchSize);
    return math.min(safeLimit, totalCount);
  }

  int _messageWindowStartOffset(
    List<Map<String, Object?>> rows, {
    required int fallback,
  }) {
    if (rows.isEmpty) {
      return fallback;
    }
    final sortOrder = rows.first['sort_order'];
    return sortOrder is int ? math.max(0, sortOrder) : fallback;
  }

  Future<List<Map<String, Object?>>> _queryMessageRows({
    required List<String> columnsWithoutMetadata,
    required String where,
    required List<Object?> whereArgs,
    required String orderBy,
    int? limit,
    int? offset,
    bool deferTelemetryMetadata = false,
    bool statisticsMetadataOnly = false,
  }) async {
    final columns = <String>[
      ...columnsWithoutMetadata,
      if (deferTelemetryMetadata)
        statisticsMetadataOnly
            ? _kStatisticsMetadataProjection
            : _kDeferredTelemetryMetadataProjection
      else
        'metadata_json',
      if (deferTelemetryMetadata)
        '1 AS $aiSessionMessageDeferredTelemetryMetadataKey',
    ];
    try {
      return await _db.query(
        'messages',
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    } on DatabaseException catch (error, stack) {
      if (!deferTelemetryMetadata) rethrow;
      silentLog(
        'ai_session_store',
        statisticsMetadataOnly ? '统计元数据投影失败，回退空元数据' : '轻量消息元数据查询失败，回退完整元数据',
        error,
        stack,
      );
      return _db.query(
        'messages',
        columns: <String>[
          ...columnsWithoutMetadata,
          if (statisticsMetadataOnly)
            "'{}' AS metadata_json"
          else
            'metadata_json',
        ],
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
    }
  }

  List<Map<String, Object?>> _trimTailRowsToBudget(
    List<Map<String, Object?>> rows, {
    required int? characterBudget,
  }) {
    if (rows.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    final budget = characterBudget == null ? 0 : math.max(0, characterBudget);
    final selected = <Map<String, Object?>>[];
    var totalDecodeCost = 0;
    for (final row in rows) {
      final rowCost = _messageRowDecodeCost(row);
      if (budget > 0 &&
          selected.isNotEmpty &&
          totalDecodeCost + rowCost > budget) {
        break;
      }
      selected.add(row);
      totalDecodeCost += rowCost;
    }
    return selected.reversed.toList(growable: false);
  }

  int _messageRowDecodeCost(Map<String, Object?> row) {
    final rawCount = row['character_count'];
    final contentCost = rawCount is int
        ? math.max(0, rawCount)
        : '${row['content'] ?? ''}'.length;
    final metadata = row['metadata_json'];
    final usage = row['usage_json'];
    return contentCost +
        (metadata is String ? metadata.length : 0) +
        (usage is String ? usage.length : 0);
  }

  /// Loads a bounded, stable page of sessions (with messages) that belong to
  /// [templateId] and whose `created_at` is on or after [minCreatedAt].
  ///
  /// Keyset pagination uses the immutable `created_at + id` pair so updates
  /// performed by a scheduler cannot reorder rows underneath its next page.
  Future<AiSessionTemplatePage> loadSessionPageByTemplate({
    required String templateId,
    required DateTime minCreatedAt,
    AiSessionTemplateCursor? after,
    int pageSize = defaultTemplateSessionPageSize,
  }) async {
    final effectivePageSize = pageSize.clamp(1, maxTemplateSessionPageSize);
    var where = 'template_id = ? AND created_at >= ?';
    final whereArgs = <Object?>[
      templateId,
      minCreatedAt.toUtc().toIso8601String(),
    ];
    if (after != null) {
      where += ' AND (created_at < ? OR (created_at = ? AND id < ?))';
      whereArgs.addAll(<Object?>[
        after.createdAtText,
        after.createdAtText,
        after.sessionId,
      ]);
    }
    final rows = await _db.query(
      'sessions',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC, id DESC',
      limit: effectivePageSize + 1,
    );
    if (rows.isEmpty) {
      return const AiSessionTemplatePage(
        sessions: <AiSession>[],
        nextCursor: null,
      );
    }
    final hasMore = rows.length > effectivePageSize;
    final selectedRows = hasMore
        ? rows.take(effectivePageSize).toList(growable: false)
        : rows;
    // 同 loadAll：批量 IN (...) 拉取所有 session 的 messages，避免 N+1。
    final ids = <String>[
      for (final row in selectedRows)
        if (row['id'] is String) row['id'] as String,
    ];
    final messagesBySessionId = await _loadMessagesBySessionIds(ids);
    final sessions = <AiSession>[];
    for (final row in selectedRows) {
      try {
        final sessionId = row['id'] as String;
        final messageRows =
            messagesBySessionId[sessionId] ?? const <Map<String, Object?>>[];
        final session = await _sessionFromRowCooperatively(row, messageRows);
        sessions.add(await restoreCompressionCheckpointFromSidecar(session));
        await _yieldAfterSessionDecodeIfNeeded(sessions.length);
      } catch (error, stack) {
        silentLog('ai_session_store', '加载模板会话 ${row['id']}', error, stack);
        // Skip rows that fail to decode; loadAllHeaders() surfaces persistence
        // issues for the UI — the scheduler should stay silent.
      }
    }
    AiSessionTemplateCursor? nextCursor;
    if (hasMore && selectedRows.isNotEmpty) {
      final lastRow = selectedRows.last;
      final createdAtText = '${lastRow['created_at'] ?? ''}'.trim();
      final sessionId = '${lastRow['id'] ?? ''}'.trim();
      if (createdAtText.isNotEmpty && sessionId.isNotEmpty) {
        nextCursor = AiSessionTemplateCursor(
          createdAtText: createdAtText,
          sessionId: sessionId,
        );
      }
    }
    return AiSessionTemplatePage(
      sessions: List<AiSession>.unmodifiable(sessions),
      nextCursor: nextCursor,
    );
  }

  /// 分页加载会话消息，按 [sort_order] 升序返回。
  ///
  /// [offset] 从零开始；[limit] 始终限制在 1 至 [_kMessageBatchSize]，
  /// 防止异常参数退化为全量历史加载。
  Future<AiSessionMessagePage> loadMessages(
    String sessionId, {
    int limit = 50,
    int offset = 0,
    bool deferTelemetryMetadata = false,
  }) async {
    final totalCount = await _countMessages(sessionId);
    final safeOffset = math.min(math.max(0, offset), totalCount);
    final safeLimit = limit.clamp(1, _kMessageBatchSize);
    final messages = await _loadMessageBatch(
      sessionId,
      limit: safeLimit,
      offset: safeOffset,
      deferTelemetryMetadata: deferTelemetryMetadata,
    );
    final expanded = await _prependTranscriptToolCallContext(
      sessionId,
      messages: messages,
      offset: safeOffset,
      deferTelemetryMetadata: deferTelemetryMetadata,
    );
    final hasMore = expanded.offset + expanded.messages.length < totalCount;

    return AiSessionMessagePage(
      messages: expanded.messages,
      offset: expanded.offset,
      totalCount: totalCount,
      hasMore: hasMore,
    );
  }

  Future<List<AiSessionMessage>> _loadMessageBatch(
    String sessionId, {
    required int limit,
    required int offset,
    bool deferTelemetryMetadata = false,
    int? contentPreviewChars,
  }) async {
    final rows = await _queryMessageRows(
      columnsWithoutMetadata:
          contentPreviewChars != null && contentPreviewChars > 0
          ? _tailMessageRowColumnsWithoutMetadata(contentPreviewChars)
          : _kMessageRowColumnsWithoutMetadata,
      where: 'session_id = ?',
      whereArgs: <Object?>[sessionId],
      orderBy: 'sort_order ASC',
      limit: limit,
      offset: offset,
      deferTelemetryMetadata: deferTelemetryMetadata,
    );

    final leadingKnowledgeBaseMetadata =
        await _leadingKnowledgeBaseMetadataForWindowStart(sessionId, rows);
    final messages = await _decodeMessagesCooperatively(
      rows,
      leadingKnowledgeBaseMetadata: leadingKnowledgeBaseMetadata,
    );
    return messages;
  }

  Future<({List<AiSessionMessage> messages, int offset})>
  _prependTranscriptToolCallContext(
    String sessionId, {
    required List<AiSessionMessage> messages,
    required int offset,
    bool deferTelemetryMetadata = false,
    int? characterBudget,
  }) async {
    var resolvedOffset = math.max(0, offset);
    var remainingContext = _kTranscriptToolPairContextMaxMessages;
    var remainingBudget = characterBudget == null || characterBudget <= 0
        ? 0
        : math.max(
            0,
            characterBudget -
                messages.fold<int>(
                  0,
                  (sum, message) => sum + message.content.length,
                ),
          );
    var expandedMessages = messages;
    var unmatchedCallIds = unmatchedTranscriptToolCallIds(expandedMessages);
    while (unmatchedCallIds.isNotEmpty &&
        resolvedOffset > 0 &&
        remainingContext > 0 &&
        (characterBudget == null ||
            characterBudget <= 0 ||
            remainingBudget > 0)) {
      final batchSize = math.min(
        math.min(_kTranscriptToolPairContextBatchSize, resolvedOffset),
        remainingContext,
      );
      final previousOffset = resolvedOffset - batchSize;
      final previousMessages = await _loadMessageBatch(
        sessionId,
        limit: batchSize,
        offset: previousOffset,
        deferTelemetryMetadata: deferTelemetryMetadata,
        contentPreviewChars: remainingBudget > 0
            ? math.min(remainingBudget, _kTailMessageContentPreviewChars)
            : null,
      );
      if (previousMessages.isEmpty) break;
      final boundedBatch = remainingBudget > 0
          ? _takeMessagesWithinContentBudget(previousMessages, remainingBudget)
          : (messages: previousMessages, skippedPrefixCount: 0);
      if (boundedBatch.messages.isEmpty) break;
      expandedMessages = <AiSessionMessage>[
        ...boundedBatch.messages,
        ...expandedMessages,
      ];
      resolvedOffset = previousOffset + boundedBatch.skippedPrefixCount;
      remainingContext -= boundedBatch.messages.length;
      if (remainingBudget > 0) {
        remainingBudget = math.max(
          0,
          remainingBudget -
              boundedBatch.messages.fold<int>(
                0,
                (sum, message) => sum + message.content.length,
              ),
        );
      }
      unmatchedCallIds = unmatchedTranscriptToolCallIds(expandedMessages);
    }
    return (
      messages: List<AiSessionMessage>.unmodifiable(expandedMessages),
      offset: resolvedOffset,
    );
  }

  ({List<AiSessionMessage> messages, int skippedPrefixCount})
  _takeMessagesWithinContentBudget(
    List<AiSessionMessage> messages,
    int budget,
  ) {
    final selected = <AiSessionMessage>[];
    var used = 0;
    for (final message in messages.reversed) {
      final cost = message.content.length;
      if (selected.isNotEmpty && used + cost > budget) break;
      selected.add(message);
      used += cost;
    }
    final boundedMessages = selected.reversed.toList(growable: false);
    return (
      messages: boundedMessages,
      skippedPrefixCount: messages.length - boundedMessages.length,
    );
  }

  /// Loads one message row without hydrating the whole session.
  Future<AiSessionMessage?> loadMessage(
    String sessionId,
    String messageId,
  ) async {
    final normalizedSessionId = requireSafeStorageIdentifier(
      sessionId,
      label: '会话标识符',
    );
    final normalizedMessageId = requireSafeStorageIdentifier(
      messageId,
      label: '消息标识符',
    );
    final rows = await _db.query(
      'messages',
      where: 'id = ? AND session_id = ?',
      whereArgs: <Object?>[normalizedMessageId, normalizedSessionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _messageFromRow(rows.first);
  }

  /// 返回消息在会话持久化顺序中的零基偏移，不加载消息正文。
  Future<int?> messageOffset(String sessionId, String messageId) async {
    final normalizedSessionId = sessionId.trim();
    final normalizedMessageId = messageId.trim();
    if (!isSafeStorageIdentifier(normalizedSessionId) ||
        !isSafeStorageIdentifier(normalizedMessageId)) {
      return null;
    }
    final rows = await _db.query(
      'messages',
      columns: const <String>['sort_order'],
      where: 'session_id = ? AND id = ?',
      whereArgs: <Object?>[normalizedSessionId, normalizedMessageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final offset = rows.first['sort_order'];
    return offset is int ? math.max(0, offset) : null;
  }

  /// Returns the stored message count without decoding any message rows.
  Future<int> countMessages(String sessionId) => _countMessages(sessionId);

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

      // 完整会话回写走 delete + 批量重插。带遥测裁剪标记的消息在内存里是有损
      // 副本（尾窗加载时遥测被 json_remove 裁过），先把库内完整遥测读出来，
      // 重插时补回，避免整轮覆盖永久清空 request_payload / response_raw 等大字段。
      final deferredIds = <String>[
        for (final message in session.messages)
          if (message.metadata[aiSessionMessageDeferredTelemetryMetadataKey] ==
              true)
            message.id,
      ];
      final storedTelemetry = <String, Map<String, Object?>>{};
      if (deferredIds.isNotEmpty) {
        final placeholders = List.filled(deferredIds.length, '?').join(', ');
        final rows = await txn.query(
          'messages',
          columns: const <String>['id', 'metadata_json'],
          where: 'session_id = ? AND id IN ($placeholders)',
          whereArgs: <Object?>[session.id, ...deferredIds],
        );
        for (final row in rows) {
          final id = row['id'] as String?;
          if (id != null) {
            storedTelemetry[id] = _decodeJsonMap(row['metadata_json']);
          }
        }
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
          _messageToRow(
            session.messages[i],
            session.id,
            i,
            storedTelemetry: storedTelemetry,
          ),
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
    await _db.transaction((txn) async {
      final updated = await txn.update(
        'sessions',
        row,
        where: 'id = ?',
        whereArgs: <Object?>[session.id],
      );
      if (updated == 0) {
        await txn.insert(
          'sessions',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// Updates only one message's metadata. This keeps small UI-only changes
  /// from forcing full transcript hydration or a delete + bulk-insert cycle.
  Future<bool> updateMessageMetadata({
    required String sessionId,
    required String messageId,
    required Map<String, Object?> metadata,
  }) async {
    final normalizedSessionId = requireSafeStorageIdentifier(
      sessionId,
      label: '会话标识符',
    );
    final normalizedMessageId = requireSafeStorageIdentifier(
      messageId,
      label: '消息标识符',
    );
    Map<String, Object?>? stored;
    if (metadata[aiSessionMessageDeferredTelemetryMetadataKey] == true) {
      // 传入的是遥测裁剪副本（如在尾窗里点赞/点踩）：先读回库内完整遥测再合并，
      // 否则整列覆盖会把 request_payload / response_raw 等大字段一并清空。
      final rows = await _db.query(
        'messages',
        columns: const <String>['metadata_json'],
        where: 'id = ? AND session_id = ?',
        whereArgs: <Object?>[normalizedMessageId, normalizedSessionId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        stored = _decodeJsonMap(rows.first['metadata_json']);
      }
    }
    final updated = await _db.update(
      'messages',
      <String, Object?>{
        'metadata_json': jsonEncode(
          _metadataForPersistence(metadata, stored: stored),
        ),
      },
      where: 'id = ? AND session_id = ?',
      whereArgs: <Object?>[normalizedMessageId, normalizedSessionId],
    );
    return updated > 0;
  }

  /// Deletes a session and all its messages from the database, plus
  /// per-session artifacts from disk.
  Future<void> delete(String sessionId) async {
    final normalizedSessionId = requireSafeStorageIdentifier(
      sessionId,
      label: '会话标识符',
    );
    await _sessionCleanupQueue.enqueue(() async {
      await _db.transaction((txn) async {
        final markerKey = _pendingSessionCleanupSettingKey(normalizedSessionId);
        final existing = await txn.query(
          'app_settings',
          columns: const <String>['key'],
          where: 'key = ?',
          whereArgs: <Object?>[markerKey],
          limit: 1,
        );
        if (existing.isEmpty) {
          final countRows = await txn.rawQuery(
            'SELECT COUNT(*) AS marker_count FROM app_settings '
            'WHERE key GLOB ?',
            <Object?>['$_pendingSessionCleanupSettingPrefix*'],
          );
          final count = countRows.isEmpty
              ? 0
              : nonNegativeIntFromValue(
                  countRows.first['marker_count'],
                  fallback: 0,
                );
          if (count >= _maxPendingSessionCleanups) {
            throw StateError('待处理会话清理任务过多。');
          }
          await txn.insert('app_settings', <String, Object?>{
            'key': markerKey,
            'value': normalizedSessionId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        // Database CASCADE will remove messages automatically.
        await txn.delete(
          'sessions',
          where: 'id = ?',
          whereArgs: <Object?>[normalizedSessionId],
        );
      });
      await _deleteSessionArtifacts(normalizedSessionId);
      await _deletePendingSessionCleanup(normalizedSessionId);
    });
  }

  Future<void> retryPendingSessionCleanups() {
    return _sessionCleanupQueue.enqueue(() async {
      try {
        await _migratePendingSessionCleanupFile();
        final pending = await _loadPendingSessionCleanups();
        if (pending.isEmpty) return;
        for (final sessionId in pending) {
          try {
            if (await exists(sessionId)) {
              await _deletePendingSessionCleanup(sessionId);
              continue;
            }
            await _deleteSessionArtifacts(
              sessionId,
              policy: _pendingSessionCleanupDeletePolicy,
            );
            await _deletePendingSessionCleanup(sessionId);
          } catch (error, stack) {
            silentLog('ai_session_store', '重试待处理会话清理', error, stack);
          }
        }
      } catch (error, stack) {
        silentLog('ai_session_store', '处理待处理会话清理', error, stack);
      }
    });
  }

  void _schedulePendingSessionCleanupRetry() {
    if (_pendingSessionCleanupRetry != null) return;
    final future = retryPendingSessionCleanups();
    _pendingSessionCleanupRetry = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_pendingSessionCleanupRetry, future)) {
          _pendingSessionCleanupRetry = null;
        }
      }),
    );
  }

  File get _pendingSessionCleanupFile =>
      File(p.join(_sessionsDirectoryPath, '.cleanup-pending.json'));

  String _pendingSessionCleanupSettingKey(String sessionId) =>
      '$_pendingSessionCleanupSettingPrefix$sessionId';

  Future<List<String>> _loadPendingSessionCleanups() async {
    final rows = await _db.query(
      'app_settings',
      columns: const <String>['key', 'value'],
      where: 'key GLOB ?',
      whereArgs: <Object?>['$_pendingSessionCleanupSettingPrefix*'],
      orderBy: 'key ASC',
      limit: _maxPendingSessionCleanups,
    );
    final sessionIds = <String>[];
    for (final row in rows) {
      final key = row['key'];
      final value = row['value'];
      final sessionId = value is String ? value.trim() : '';
      if (!isSafeStorageIdentifier(sessionId) ||
          key != _pendingSessionCleanupSettingKey(sessionId)) {
        if (key is String) {
          await _db.delete(
            'app_settings',
            where: 'key = ?',
            whereArgs: <Object?>[key],
          );
        }
        continue;
      }
      if (sessionIds.length < _pendingSessionCleanupRetryBatchSize) {
        sessionIds.add(sessionId);
      }
    }
    return sessionIds;
  }

  Future<void> _deletePendingSessionCleanup(String sessionId) {
    return _db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: <Object?>[_pendingSessionCleanupSettingKey(sessionId)],
    );
  }

  Future<void> _migratePendingSessionCleanupFile() async {
    final file = _pendingSessionCleanupFile;
    try {
      await recoverAtomicWriteBackupIfNeeded(file);
      if (!await regularFileExistsBounded(file)) return;
      final decoded = jsonDecode(
        await readBoundedFileString(
          file,
          maxBytes: _pendingSessionCleanupMaxBytes,
        ),
      );
      final rawIds = decoded is Map ? decoded['session_ids'] : null;
      if (rawIds is! List) {
        await deleteFileAtomically(file);
        return;
      }
      final sessionIds = <String>{
        for (final value in rawIds.take(_maxPendingSessionCleanups))
          if (value is String && isSafeStorageIdentifier(value.trim()))
            value.trim(),
      };
      await _db.transaction((txn) async {
        for (final sessionId in sessionIds) {
          await txn.insert('app_settings', <String, Object?>{
            'key': _pendingSessionCleanupSettingKey(sessionId),
            'value': sessionId,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      });
      await deleteFileAtomically(file);
    } catch (error, stack) {
      silentLog('ai_session_store', '迁移待处理会话清理', error, stack);
    }
  }

  Future<void> _deleteSessionArtifacts(
    String sessionId, {
    BoundedDeletePolicy policy = defaultBoundedDeletePolicy,
  }) async {
    final modernSessionDirectoryPath = sessionDirectoryPath(sessionId);
    final paths = <String>[
      sessionAttachmentsDirectoryPath(sessionId),
      if (!p.equals(modernSessionDirectoryPath, attachmentsDirectoryPath))
        modernSessionDirectoryPath,
      sessionFilePath(sessionId),
    ];
    for (final path in paths) {
      await deletePathBounded(
        p.absolute(path),
        policy: policy,
        allowedRoot: p.absolute(_sessionsDirectoryPath),
      );
    }
  }

  Future<void> openStorageDirectory() {
    return openDirectoryInFileManager(Directory(_sessionsDirectoryPath));
  }

  /// 清空全部会话行，并删除磁盘上的会话目录、附件和旧版会话文件。
  ///
  /// 调用前应确保控制器没有活动流；完成后由调用方刷新内存状态。
  Future<void> clearAll() async {
    await _db.delete('sessions');
    final root = Directory(_sessionsDirectoryPath);
    await deletePathBounded(
      p.absolute(root.path),
      allowedRoot: p.absolute(_sessionsDirectoryPath),
    );
    await root
        .create(recursive: true)
        .timeout(defaultBoundedFileReadIdleTimeout);
  }

  // Row ↔ Model conversion
  AiSession _sessionFromRow(
    Map<String, Object?> row,
    List<Map<String, Object?>> messageRows, {
    AiSessionMessageLoadState messageLoadState =
        AiSessionMessageLoadState.complete,
    int messageWindowStartIndex = 0,
    int? messageTotalCount,
  }) {
    final messages = _normalizeKnowledgeBaseAssistantMetadata(
      messageRows.map(_messageFromRow).toList(growable: false),
    );
    return _sessionFromRowWithMessages(
      row,
      messages,
      messageLoadState: messageLoadState,
      messageWindowStartIndex: messageWindowStartIndex,
      messageTotalCount: messageTotalCount,
    );
  }

  Future<AiSession> _sessionFromRowCooperatively(
    Map<String, Object?> row,
    List<Map<String, Object?>> messageRows, {
    AiSessionMessageLoadState messageLoadState =
        AiSessionMessageLoadState.complete,
    int messageWindowStartIndex = 0,
    int? messageTotalCount,
    Map<String, Object?>? leadingKnowledgeBaseMetadata,
  }) async {
    final messages = await _decodeMessagesCooperatively(
      messageRows,
      leadingKnowledgeBaseMetadata: leadingKnowledgeBaseMetadata,
    );
    return _sessionFromRowWithMessages(
      row,
      messages,
      messageLoadState: messageLoadState,
      messageWindowStartIndex: messageWindowStartIndex,
      messageTotalCount: messageTotalCount,
    );
  }

  Future<List<AiSessionMessage>> _decodeMessagesCooperatively(
    List<Map<String, Object?>> messageRows, {
    Map<String, Object?>? leadingKnowledgeBaseMetadata,
  }) async {
    if (messageRows.isEmpty) {
      return const <AiSessionMessage>[];
    }
    final messages = <AiSessionMessage>[];
    var costSinceYield = 0;
    for (var index = 0; index < messageRows.length; index++) {
      final row = messageRows[index];
      costSinceYield += _messageRowDecodeCost(row);
      messages.add(_messageFromRow(row));
      final isLastRow = index + 1 >= messageRows.length;
      final reachedCountBatch =
          (index + 1) % _kMessageDecodeYieldBatchSize == 0;
      final reachedCostBudget =
          costSinceYield >= _kMessageDecodeYieldCostBudget;
      if (!isLastRow && (reachedCountBatch || reachedCostBudget)) {
        costSinceYield = 0;
        await Future<void>.delayed(Duration.zero);
      }
    }
    return _normalizeKnowledgeBaseAssistantMetadata(
      messages,
      leadingKnowledgeBaseMetadata: leadingKnowledgeBaseMetadata,
    );
  }

  Future<Map<String, Object?>?> _leadingKnowledgeBaseMetadataForWindowStart(
    String sessionId,
    List<Map<String, Object?>> messageRows,
  ) async {
    if (messageRows.isEmpty) return null;
    final firstSortOrder = messageRows.first['sort_order'];
    if (firstSortOrder is! int || firstSortOrder <= 0) return null;
    final rows = await _queryMessageRows(
      columnsWithoutMetadata: const <String>['kind', 'content'],
      where:
          'session_id = ? AND sort_order < ? AND '
          '(kind = ? OR (kind = ? AND TRIM(content) <> \'\'))',
      whereArgs: <Object?>[
        sessionId,
        firstSortOrder,
        AiSessionMessageKind.user.storageValue,
        AiSessionMessageKind.assistant.storageValue,
      ],
      orderBy: 'sort_order DESC',
      limit: 1,
      deferTelemetryMetadata: true,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final kind = AiSessionMessageKind.fromStorage('${row['kind'] ?? ''}');
    if (kind == AiSessionMessageKind.user) {
      return _knowledgeBaseReferenceMetadata(
        _decodeJsonMap(row['metadata_json']),
      );
    }
    return null;
  }

  List<AiSessionMessage> _normalizeKnowledgeBaseAssistantMetadata(
    List<AiSessionMessage> messages, {
    Map<String, Object?>? leadingKnowledgeBaseMetadata,
  }) {
    if (messages.isEmpty) return const <AiSessionMessage>[];
    var activeKnowledgeBaseMetadata = _knowledgeBaseReferenceMetadata(
      leadingKnowledgeBaseMetadata,
    );
    List<AiSessionMessage>? updatedMessages;

    for (var index = 0; index < messages.length; index++) {
      final message = updatedMessages?[index] ?? messages[index];
      if (message.kind == AiSessionMessageKind.user) {
        activeKnowledgeBaseMetadata = _knowledgeBaseReferenceMetadata(
          message.metadata,
        );
        continue;
      }
      if (message.kind != AiSessionMessageKind.assistant ||
          message.content.trim().isEmpty) {
        continue;
      }

      final existingKnowledgeBaseMetadata = _knowledgeBaseReferenceMetadata(
        message.metadata,
      );
      if (existingKnowledgeBaseMetadata == null &&
          activeKnowledgeBaseMetadata != null) {
        updatedMessages ??= List<AiSessionMessage>.from(messages);
        updatedMessages[index] = message.copyWith(
          metadata: <String, Object?>{
            ...message.metadata,
            knowledgeBaseMessageMetadataKey:
                _assistantDisplayKnowledgeBaseMetadata(
                  activeKnowledgeBaseMetadata,
                ),
          },
        );
      }
      activeKnowledgeBaseMetadata = null;
    }

    return List<AiSessionMessage>.unmodifiable(updatedMessages ?? messages);
  }

  Map<String, Object?>? _knowledgeBaseReferenceMetadata(
    Map<String, Object?>? messageMetadata,
  ) {
    if (messageMetadata == null) return null;
    final metadata = KnowledgeMessageMetadata.fromMessageMetadata(
      messageMetadata,
    );
    if (metadata == null || !KnowledgeMessageMetadata.hasReferences(metadata)) {
      return null;
    }
    return metadata;
  }

  Map<String, Object?> _assistantDisplayKnowledgeBaseMetadata(
    Map<String, Object?> metadata,
  ) {
    return <String, Object?>{...metadata};
  }

  Future<void> _yieldAfterSessionDecodeIfNeeded(int decodedCount) async {
    if (decodedCount % _kSessionDecodeYieldBatchSize == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  AiSession _sessionFromRowWithMessages(
    Map<String, Object?> row,
    List<AiSessionMessage> messages, {
    required AiSessionMessageLoadState messageLoadState,
    required int messageWindowStartIndex,
    required int? messageTotalCount,
  }) {
    final now = DateTime.now().toUtc();
    final statistics = AiSessionStatistics.fromJson(
      _decodeJsonMap(row['statistics_json']),
    );

    return AiSession(
      id: (row['id'] as String?) ?? '',
      title: (row['title'] as String?) ?? '',
      templateId: (row['template_id'] as String?) ?? '',
      templateName: (row['template_name'] as String?) ?? '',
      templateIconName: (row['template_icon_name'] as String?) ?? '',
      templateInternalVersion:
          (row['template_internal_version'] as String?) ?? '',
      createdAt: utcDateTimeFromValue(row['created_at']) ?? now,
      updatedAt: utcDateTimeFromValue(row['updated_at']) ?? now,
      messages: messages,
      environment: AiSessionEnvironment.fromJson(
        _decodeJsonMap(row['environment_json']),
      ),
      statistics: statistics,
      recentErrors: stringKeyedMapListFromValue(
        _decodeJsonList(row['recent_errors_json']),
      ).map(AiSessionErrorRecord.fromJson).toList(growable: false),
      lastUsedModelId: row['last_used_model_id'] as String?,
      lastUsedModelLabel: row['last_used_model_label'] as String?,
      isTitleManuallyEdited: boolFromValue(row['is_title_manually_edited']),
      autoTitleAcquired: boolFromValue(row['auto_title_acquired']),
      autoTitleRetryCount: nonNegativeIntFromValue(
        row['auto_title_retry_count'],
        fallback: 0,
      ),
      autoTitleFirstUserContent:
          row['auto_title_first_user_content'] as String?,
      autoTitleGeneratedAt: _parseNullableDateTime(
        row['auto_title_generated_at'],
      ),
      autoTitleSourceMessageId: row['auto_title_source_message_id'] as String?,
      latestCompressionCheckpointMessageId:
          row['latest_compression_checkpoint_message_id'] as String?,
      latestCompressionAt: _parseNullableDateTime(row['latest_compression_at']),
      mode: AiSessionMode.fromStorage((row['mode'] as String?) ?? 'chat'),
      awaitingPlanApproval: boolFromValue(row['awaiting_plan_approval']),
      pendingPlan: row['pending_plan'] as String?,
      pendingPlanAllowedPrompts: AiSessionPlanAllowedPrompt.listFromJson(
        _decodeJsonList(row['pending_plan_allowed_prompts_json']),
      ),
      fullAccessPermission: boolFromValue(row['full_access_permission']),
      metadata: _decodeJsonMap(row['metadata_json']),
      lastPromptMetadata: _decodeJsonMap(row['last_prompt_metadata_json']),
      todoItems: stringKeyedMapListFromValue(
        _decodeJsonList(row['todo_items_json']),
      ).map(AiSessionTodoItem.fromJson).toList(growable: false),
      planHistory: stringKeyedMapListFromValue(
        _decodeJsonList(row['plan_history_json']),
      ).map(AiSessionPlanRecord.fromJson).toList(growable: false),
      messageLoadState: messageLoadState,
      messageWindowStartIndex: messageWindowStartIndex,
      messageTotalCount: messageTotalCount ?? statistics.totalMessageCount,
    );
  }

  bool _isMetadataOnlySessionSnapshot(AiSession session) {
    return session.hasPartialMessages ||
        (session.messages.isEmpty && session.statistics.totalMessageCount > 0);
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
      'auto_title_acquired': session.autoTitleAcquired ? 1 : 0,
      'auto_title_retry_count': session.autoTitleRetryCount < 0
          ? 0
          : session.autoTitleRetryCount,
      'auto_title_first_user_content': session.autoTitleFirstUserContent,
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
      'pending_plan_allowed_prompts_json': jsonEncode(
        session.pendingPlanAllowedPrompts
            .map((item) => item.toJson())
            .toList(growable: false),
      ),
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
          usage = AiTokenUsage.fromJson(stringKeyedMapFromValue(decoded));
        }
      } catch (error, stack) {
        silentLog('ai_session_store', '解析 usage_json 列', error, stack);
      }
    }

    var metadata = _decodeJsonMap(row['metadata_json']);
    if (row[aiSessionMessageDeferredTelemetryMetadataKey] == 1) {
      metadata = <String, Object?>{
        ...metadata,
        aiSessionMessageDeferredTelemetryMetadataKey: true,
      };
    }
    if (row[aiSessionMessageContentPreviewMetadataKey] == 1) {
      metadata = <String, Object?>{
        ...metadata,
        aiSessionMessageContentPreviewMetadataKey: true,
      };
    }
    return AiSessionMessage(
      id: (row['id'] as String?) ?? '',
      kind: AiSessionMessageKind.fromStorage((row['kind'] as String?) ?? ''),
      role: AiSessionMessageRole.fromStorage((row['role'] as String?) ?? ''),
      content: (row['content'] as String?) ?? '',
      createdAt:
          utcDateTimeFromValue(row['created_at']) ?? DateTime.now().toUtc(),
      characterCount: nonNegativeIntFromValue(
        row['character_count'],
        fallback: 0,
      ),
      isDeleted: boolFromValue(row['is_deleted']),
      modelId: row['model_id'] as String?,
      modelLabel: row['model_label'] as String?,
      usage: usage,
      metadata: metadata,
    );
  }

  /// 计算某条消息最终要落库的 metadata。
  ///
  /// 加载尾窗时遥测大字段会被 json_remove 裁掉、并打上
  /// [aiSessionMessageDeferredTelemetryMetadataKey] 标记，这份内存副本是有损的。
  /// 直接回写会用裁剪版整列覆盖库里的完整遥测，永久丢失 request_payload /
  /// response_raw / composed_prompt_* / prompt_metadata。
  ///
  /// 以内存 metadata 为准（保留调用方对普通字段的增删意图，如点赞/点踩），
  /// 但当它带遥测裁剪标记时，从 [stored] 把被裁掉的遥测键补回；两个仅供加载期
  /// 使用的标记键（遥测裁剪、正文预览）一律不落库。
  static Map<String, Object?> _metadataForPersistence(
    Map<String, Object?> inMemory, {
    Map<String, Object?>? stored,
  }) {
    final deferred =
        inMemory[aiSessionMessageDeferredTelemetryMetadataKey] == true;
    final result = <String, Object?>{
      for (final entry in inMemory.entries)
        if (entry.key != aiSessionMessageDeferredTelemetryMetadataKey &&
            entry.key != aiSessionMessageContentPreviewMetadataKey)
          entry.key: entry.value,
    };
    if (deferred && stored != null) {
      for (final key in aiSessionMessageDeferredTelemetryMetadataKeys) {
        if (!result.containsKey(key) && stored.containsKey(key)) {
          result[key] = stored[key];
        }
      }
    }
    return result;
  }

  Map<String, Object?> _messageToRow(
    AiSessionMessage message,
    String sessionId,
    int sortOrder, {
    Map<String, Map<String, Object?>> storedTelemetry =
        const <String, Map<String, Object?>>{},
  }) {
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
      'metadata_json': jsonEncode(
        _metadataForPersistence(
          message.metadata,
          stored: storedTelemetry[message.id],
        ),
      ),
    };
  }

  static Map<String, Object?> _decodeJsonMap(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return stringKeyedMapFromValue(decoded);
      } catch (error, stack) {
        silentLog('ai_session_store', '解析 JSON 对象', error, stack);
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
        silentLog('ai_session_store', '解析 JSON 列表', error, stack);
      }
    }
    return const <Object?>[];
  }

  static DateTime? _parseNullableDateTime(Object? value) {
    return utcDateTimeFromValue(value);
  }

  Future<int> _countMessages(String sessionId) async {
    final countResult = await _db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM messages WHERE session_id = ?',
      <Object?>[sessionId],
    );
    final count = countResult.isEmpty ? null : countResult.first['cnt'];
    return count is int ? count : 0;
  }
}

void _validateSessionForStorage(
  AiSession session, {
  Set<String>? seenSessionIds,
  bool checkDuplicateSessionIds = false,
}) {
  final sessionId = requireSafeStorageIdentifier(session.id, label: '会话标识符');
  if (checkDuplicateSessionIds &&
      seenSessionIds != null &&
      !seenSessionIds.add(sessionId)) {
    throw FormatException('检测到重复会话标识符：$sessionId');
  }

  final seenMessageIds = <String>{};
  for (final message in session.messages) {
    final messageId = requireSafeStorageIdentifier(message.id, label: '消息标识符');
    if (!seenMessageIds.add(messageId)) {
      throw FormatException('会话 $sessionId 中检测到重复消息标识符：$messageId');
    }
  }
}
