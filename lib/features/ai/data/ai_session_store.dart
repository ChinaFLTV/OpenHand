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
import '../../../shared/util/async_concurrency.dart';
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

const String aiSessionEditorTabsSettingPrefix = 'editor_tabs_';

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
        '不能为空。',
      );
    }
  }

  static const Duration runtimeCleanupTimeout =
      kOpenHandServiceRuntimeCleanupTimeout;
  static const int _compactMemoryMarkdownMaxBytes = 16 * kBytesPerMiB;
  static const int _compactMemoryMetadataMaxBytes = 2 * kBytesPerMiB;
  static const String _compactMemoryGenerationPrefix = '- generation: ';
  static const int _maxPendingSessionCleanups = 2048;
  static const int _maxPendingSessionWrites = 512;
  static const int _pendingSessionCleanupRetryBatchSize = 4;
  static const int _pendingSessionCleanupMaxBytes = 256 * kBytesPerKiB;
  static const String _pendingSessionCleanupSettingPrefix =
      'ai_session_cleanup:';
  static const String _legacyEmptyEditorTabsPayload =
      '{"open_files":[],"active_file":null}';
  static const BoundedDeletePolicy _pendingSessionCleanupDeletePolicy =
      BoundedDeletePolicy(
        maxEntries: 100000,
        maxDepth: 128,
        directoryIdleTimeout: Duration(seconds: 2),
        operationTimeout: Duration(seconds: 5),
        totalTimeout: Duration(seconds: 10),
      );

  final String _sessionsDirectoryPath;
  final SerialTaskQueue _sessionCleanupQueue = SerialTaskQueue(
    maxPendingTasks: _maxPendingSessionCleanups,
  );
  final SerialTaskQueue _sessionWriteQueue = SerialTaskQueue(
    maxPendingTasks: _maxPendingSessionWrites,
  );
  final Map<String, int> _sessionDeletionGuardCounts = <String, int>{};
  Future<void>? _pendingSessionCleanupRetry;

  /// 最近一次成功落库的完整消息列表影子（按会话，LRU 有界）。
  ///
  /// 消息对象不可变：`identical` 即该行内容未变。发送/流式周期内的高频
  /// 提交只改尾部或追加，可据此把「DELETE + 全量重插」降级为 O(变更行数)
  /// 的增量 upsert，避免千条会话每轮提交重复 jsonEncode + 重写全部行。
  /// 影子缺失、消息被删除或重排时回退全量重写，保证行为与旧路径一致。
  final Map<String, List<AiSessionMessage>> _savedMessagesShadowBySessionId =
      <String, List<AiSessionMessage>>{};
  static const int _kSavedMessagesShadowMaxSessions = 8;
  static const List<Duration> _databaseBusyRetryDelays = <Duration>[
    Duration(milliseconds: 100),
    Duration(milliseconds: 300),
  ];

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

  /// 当前会话附件目录。旧版附件仍按附件对象中保存的完整路径读取。
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
      throw const FileSystemException('压缩记忆 Markdown 超过 16 MiB 上限。');
    }
    if (utf8.encode(metadataJson).length > _compactMemoryMetadataMaxBytes) {
      throw const FileSystemException('压缩记忆元数据超过 2 MiB 上限。');
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

  /// 为兼容旧版附件管理保留。
  String sessionFilePath(String sessionId) {
    final normalizedSessionId = requireSafeStorageIdentifier(
      sessionId,
      label: '会话标识符',
    );
    return p.join(_sessionsDirectoryPath, 'session-$normalizedSessionId.json');
  }

  Database get _db => DatabaseService.instance.database;

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

  /// 全量正文 + 遥测裁剪投影用的基础列（不含 metadata_json，由
  /// [_queryMessageRows] 按需拼接投影）。
  static const List<String> _kFullMessageRowColumnsWithoutMetadata = <String>[
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

  /// 仅加载会话元数据，不加载消息；默认排除已归档会话。
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

  /// 会话默认顺序：置顶优先；未手动排序的会话按更新时间降序；其余按手动顺序排列。
  /// `display_order IS NULL` 必须降序，确保新建会话不会落到手动排序会话之后。
  static const String _sessionsOrderBy =
      'pinned DESC, '
      '(display_order IS NULL) DESC, '
      'display_order ASC, '
      'updated_at DESC, '
      'created_at DESC, '
      'id ASC';

  /// 原子保存 [orderedSessionIds] 的手动顺序；未传入的会话保持原顺序。
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

  /// 设置单个会话的置顶状态。
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

  /// 设置单个会话的归档状态；默认加载不会返回已归档会话。
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

  /// 加载全部会话的置顶与归档状态，避免为管理界面加载完整会话模型。
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

  /// 单次查询计算全部会话文本列的存储字节数，并保留无消息会话。
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

  /// 加载单个会话及其全部消息。
  ///
  /// [deferTelemetry] 为 true 时用 json_remove 在 SQL 侧裁掉
  /// request_payload / response_raw / composed_prompt_* / prompt_metadata
  /// 等遥测大字段（可达数十 MB），消息带上遥测裁剪标记。构建提示词、
  /// 编辑、切换变体等常规全量水合都不需要这些字段；审计弹窗按需
  /// loadMessage 单条补齐，save() 回写时自动从库内补回，功能无损。
  /// 导出等需要全保真 metadata 的调用方保持默认 false。
  Future<AiSession?> loadSession(
    String sessionId, {
    bool deferTelemetry = false,
  }) async {
    final normalizedId = sessionId.trim();
    if (!isSafeStorageIdentifier(normalizedId)) return null;
    final rows = await _db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: <Object?>[normalizedId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final messageRows = deferTelemetry
        ? await _queryMessageRows(
            columnsWithoutMetadata: _kFullMessageRowColumnsWithoutMetadata,
            where: 'session_id = ?',
            whereArgs: <Object?>[normalizedId],
            orderBy: 'sort_order ASC',
            deferTelemetryMetadata: true,
          )
        : await _db.query(
            'messages',
            where: 'session_id = ?',
            whereArgs: <Object?>[normalizedId],
            orderBy: 'sort_order ASC',
          );
    final session = await _sessionFromRowCooperatively(rows.first, messageRows);
    // 播种落库影子：刚加载的消息列表即数据库当前状态，作为增量落库的
    // 对比基线后，水合→normalize→首次 save 也只写真正变化的行，而不是
    // 因影子缺失回退整会话重写。必须在压缩旁路恢复之前取列表——旁路
    // 可能替换内存中的检查点消息，而数据库里仍是原行。
    _rememberSavedMessages(session.id, session.messages);
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
    if (!session.hasCompleteMessages) {
      return session;
    }
    // 小会话经尾窗一次性加载完整（无预览截断、offset=0）时，列表即数据库
    // 状态，可直接作为增量落库基线；同样须在压缩旁路恢复之前取列表。
    _rememberSavedMessages(session.id, session.messages);
    return restoreCompressionCheckpointFromSidecar(session);
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

  /// 分页加载指定模板和起始时间后的会话及消息。
  /// 使用不可变的 `created_at + id` 游标，避免调度更新干扰翻页顺序。
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
        // 跳过损坏行；持久化问题由 loadAllHeaders() 统一呈现。
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

  /// 加载单条消息，不加载完整会话。
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

  /// 不解码消息行，直接返回持久化消息数。
  Future<int> countMessages(String sessionId) => _countMessages(sessionId);

  /// 原子保存完整 [session]，包括元数据和全部消息。
  Future<void> save(AiSession session) async {
    _validateSessionForStorage(session);
    if (_sessionDeletionGuardCounts.containsKey(session.id)) return;
    final replaceMessages = !_isMetadataOnlySessionSnapshot(session);

    await _sessionWriteQueue.enqueue(
      () => _retryTransientDatabaseWrite(() async {
        final previousMessages = replaceMessages
            ? _savedMessagesShadowBySessionId[session.id]
            : null;
        var messagesPersisted = false;
        await _db.transaction((txn) async {
          if (_sessionDeletionGuardCounts.containsKey(session.id)) return;
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

          final changedIndices = _incrementalMessageSavePlan(
            previousMessages,
            session.messages,
          );
          if (changedIndices != null) {
            // 增量快速路径：只 upsert 变化的行（典型为流式尾消息 + 追加），
            // 未变化的行连同其库内完整遥测原样保留。
            final storedTelemetry = await _loadStoredTelemetry(
              txn,
              session,
              changedIndices,
            );
            await _writeMessageRows(
              txn,
              session,
              changedIndices,
              storedTelemetry,
            );
            messagesPersisted = true;
            return;
          }

          // 全量回写：删除旧消息后按当前列表重插。带遥测裁剪标记的消息在内存里
          // 是有损副本（加载时遥测被 json_remove 裁过），删除前先把库内完整遥测
          // 读出来补回，避免整轮覆盖永久清空 request_payload / response_raw 等大字段。
          final allIndices = List<int>.generate(
            session.messages.length,
            (index) => index,
          );
          final storedTelemetry = await _loadStoredTelemetry(
            txn,
            session,
            allIndices,
          );
          await txn.delete(
            'messages',
            where: 'session_id = ?',
            whereArgs: <Object?>[session.id],
          );
          await _writeMessageRows(txn, session, allIndices, storedTelemetry);
          messagesPersisted = true;
        });
        if (messagesPersisted) {
          _rememberSavedMessages(session.id, session.messages);
        }
      }),
    );
  }

  /// 计算增量落库计划：返回需要 upsert 的消息下标（下标即 sort_order）。
  /// 影子缺失、消息被删除或顺序变化时返回 null，走全量重写。
  List<int>? _incrementalMessageSavePlan(
    List<AiSessionMessage>? previous,
    List<AiSessionMessage> next,
  ) {
    if (previous == null || previous.isEmpty || next.length < previous.length) {
      return null;
    }
    final changedIndices = <int>[];
    for (var index = 0; index < previous.length; index += 1) {
      final before = previous[index];
      final after = next[index];
      if (identical(before, after)) continue;
      if (before.id != after.id) return null;
      changedIndices.add(index);
    }
    for (var index = previous.length; index < next.length; index += 1) {
      changedIndices.add(index);
    }
    return changedIndices;
  }

  /// 批量 upsert [indices] 指定的消息行（下标即 sort_order）。
  Future<void> _writeMessageRows(
    Transaction txn,
    AiSession session,
    List<int> indices,
    Map<String, Map<String, Object?>> storedTelemetry,
  ) async {
    if (indices.isEmpty) return;
    final batch = txn.batch();
    for (final index in indices) {
      batch.insert(
        'messages',
        _messageToRow(
          session.messages[index],
          session.id,
          index,
          storedTelemetry: storedTelemetry,
        ),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 读回 [indices] 中带遥测裁剪标记的消息在库内的完整 metadata，
  /// 供 [_messageToRow] 落库时补回被裁剪的遥测大字段。
  Future<Map<String, Map<String, Object?>>> _loadStoredTelemetry(
    Transaction txn,
    AiSession session,
    List<int> indices,
  ) {
    final deferredIds = <String>[
      for (final index in indices)
        if (session
                .messages[index]
                .metadata[aiSessionMessageDeferredTelemetryMetadataKey] ==
            true)
          session.messages[index].id,
    ];
    return _queryMessageMetadataByIds(txn, session.id, deferredIds);
  }

  /// 批量读回指定消息在库内的完整 metadata（含遥测大字段）。
  ///
  /// 供分叉等需要把全保真 metadata 复制到新 id / 新会话的场景使用——
  /// 这类副本换了主键，落库时的按 id 遥测补回无法再命中源行。
  Future<Map<String, Map<String, Object?>>> loadFullMessageMetadata(
    String sessionId,
    List<String> messageIds,
  ) {
    final normalizedSessionId = sessionId.trim();
    if (!isSafeStorageIdentifier(normalizedSessionId)) {
      return Future.value(const <String, Map<String, Object?>>{});
    }
    return _queryMessageMetadataByIds(_db, normalizedSessionId, messageIds);
  }

  Future<Map<String, Map<String, Object?>>> _queryMessageMetadataByIds(
    DatabaseExecutor executor,
    String sessionId,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) {
      return const <String, Map<String, Object?>>{};
    }
    final metadataById = <String, Map<String, Object?>>{};
    for (
      var start = 0;
      start < messageIds.length;
      start += _kMessageBatchSize
    ) {
      final end = math.min(start + _kMessageBatchSize, messageIds.length);
      final batchIds = messageIds.sublist(start, end);
      final placeholders = List.filled(batchIds.length, '?').join(', ');
      final rows = await executor.query(
        'messages',
        columns: const <String>['id', 'metadata_json'],
        where: 'session_id = ? AND id IN ($placeholders)',
        whereArgs: <Object?>[sessionId, ...batchIds],
      );
      for (final row in rows) {
        final id = row['id'] as String?;
        if (id != null) {
          metadataById[id] = _decodeJsonMap(row['metadata_json']);
        }
      }
    }
    return metadataById;
  }

  void _rememberSavedMessages(
    String sessionId,
    List<AiSessionMessage> messages,
  ) {
    // 重插保证 LRU 顺序：最近保存的会话最后被淘汰。
    _savedMessagesShadowBySessionId.remove(sessionId);
    _savedMessagesShadowBySessionId[sessionId] = messages;
    while (_savedMessagesShadowBySessionId.length >
        _kSavedMessagesShadowMaxSessions) {
      _savedMessagesShadowBySessionId.remove(
        _savedMessagesShadowBySessionId.keys.first,
      );
    }
  }

  /// 仅保存会话头，避免标题、权限等轻量变更重写完整长会话。
  Future<void> saveSessionHeader(AiSession session) async {
    _validateSessionForStorage(session);
    if (_sessionDeletionGuardCounts.containsKey(session.id)) return;
    final row = _sessionToRow(session);
    await _sessionWriteQueue.enqueue(
      () => _retryTransientDatabaseWrite(
        () => _db.transaction((txn) async {
          if (_sessionDeletionGuardCounts.containsKey(session.id)) return;
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
        }),
      ),
    );
  }

  Future<T> _retryTransientDatabaseWrite<T>(
    Future<T> Function() operation,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await operation();
      } on DatabaseException catch (error, stack) {
        if (!_isTransientDatabaseBusy(error) ||
            attempt >= _databaseBusyRetryDelays.length) {
          Error.throwWithStackTrace(error, stack);
        }
        await Future<void>.delayed(_databaseBusyRetryDelays[attempt]);
      }
    }
  }

  bool _isTransientDatabaseBusy(DatabaseException error) {
    final message = error.toString().toLowerCase();
    return message.contains('database is locked') ||
        message.contains('database is busy') ||
        message.contains('sqlite_busy') ||
        message.contains('sqlite_locked');
  }

  /// 仅更新单条消息元数据，避免轻量界面变更重写完整会话。
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
    return _sessionWriteQueue.enqueue(() async {
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
      final updated = await _retryTransientDatabaseWrite(
        () => _db.update(
          'messages',
          <String, Object?>{
            'metadata_json': jsonEncode(
              _metadataForPersistence(metadata, stored: stored),
            ),
          },
          where: 'id = ? AND session_id = ?',
          whereArgs: <Object?>[normalizedMessageId, normalizedSessionId],
        ),
      );
      return updated > 0;
    });
  }

  /// 删除数据库中的会话及消息，并清理磁盘会话产物。
  Future<void> delete(String sessionId) async {
    final normalizedSessionId = requireSafeStorageIdentifier(
      sessionId,
      label: '会话标识符',
    );
    _savedMessagesShadowBySessionId.remove(normalizedSessionId);
    beginSessionDeletion(normalizedSessionId);
    await _sessionCleanupQueue
        .enqueue(() async {
          await _db.transaction((txn) async {
            final markerKey = _pendingSessionCleanupSettingKey(
              normalizedSessionId,
            );
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
            // 数据库级联删除关联消息。
            await txn.delete(
              'sessions',
              where: 'id = ?',
              whereArgs: <Object?>[normalizedSessionId],
            );
            await txn.delete(
              'app_settings',
              where: 'key = ?',
              whereArgs: <Object?>[
                '$aiSessionEditorTabsSettingPrefix$normalizedSessionId',
              ],
            );
          });
          await _deleteSessionArtifacts(normalizedSessionId);
          await _deletePendingSessionCleanup(normalizedSessionId);
        })
        .whenComplete(() => endSessionDeletion(normalizedSessionId));
  }

  /// 阻止已经开始的迟到写入在删除事务完成后重新创建会话。
  void beginSessionDeletion(String sessionId) {
    final normalizedSessionId = requireSafeStorageIdentifier(
      sessionId,
      label: '会话标识符',
    );
    _sessionDeletionGuardCounts.update(
      normalizedSessionId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  /// 删除控制器确认该会话的全部异步工作结束后释放写入保护。
  void endSessionDeletion(String sessionId) {
    final normalizedSessionId = sessionId.trim();
    final count = _sessionDeletionGuardCounts[normalizedSessionId];
    if (count == null) return;
    if (count <= 1) {
      _sessionDeletionGuardCounts.remove(normalizedSessionId);
    } else {
      _sessionDeletionGuardCounts[normalizedSessionId] = count - 1;
    }
  }

  Future<void> retryPendingSessionCleanups() {
    return _sessionCleanupQueue.enqueue(() async {
      try {
        await _migratePendingSessionCleanupFile();
        await _pruneEditorTabsSettings();
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

  Future<void> flush() {
    return _sessionCleanupQueue.idle.timeout(runtimeCleanupTimeout);
  }

  void _schedulePendingSessionCleanupRetry() {
    if (_pendingSessionCleanupRetry != null) return;
    final future = retryPendingSessionCleanups();
    _pendingSessionCleanupRetry = future;
    unawaited(
      future
          .whenComplete(() {
            if (identical(_pendingSessionCleanupRetry, future)) {
              _pendingSessionCleanupRetry = null;
            }
          })
          .catchError((Object error, StackTrace stack) {
            silentLog('ai_session_store', '调度待处理会话清理', error, stack);
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

  Future<void> _pruneEditorTabsSettings() async {
    await _db.rawDelete(
      '''
      DELETE FROM app_settings
      WHERE key GLOB ?
        AND (
          value = ?
          OR NOT EXISTS (
            SELECT 1
            FROM sessions
            WHERE app_settings.key = ? || sessions.id
          )
        )
      ''',
      <Object?>[
        '$aiSessionEditorTabsSettingPrefix*',
        _legacyEmptyEditorTabsPayload,
        aiSessionEditorTabsSettingPrefix,
      ],
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
    _savedMessagesShadowBySessionId.clear();
    await _db.transaction((txn) async {
      await txn.delete('sessions');
      await txn.delete(
        'app_settings',
        where: 'key GLOB ?',
        whereArgs: const <Object?>['$aiSessionEditorTabsSettingPrefix*'],
      );
    });
    final root = Directory(_sessionsDirectoryPath);
    await deletePathBounded(
      p.absolute(root.path),
      allowedRoot: p.absolute(_sessionsDirectoryPath),
    );
    await root
        .create(recursive: true)
        .timeout(defaultBoundedFileReadIdleTimeout);
  }

  // 数据库行与模型转换。
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
      recentErrors: _decodeJsonList(row['recent_errors_json'])
          .take(AiSessionDataLimits.maxRecentErrors)
          .whereType<Map>()
          .map(
            (item) =>
                AiSessionErrorRecord.fromJson(stringKeyedMapFromValue(item)),
          )
          .toList(growable: false),
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
      todoItems: AiSessionTodoItem.listFromJson(
        _decodeJsonList(row['todo_items_json']),
      ),
      planHistory: () {
        final items = _decodeJsonList(row['plan_history_json']);
        final start = items.length > AiSessionDataLimits.maxPlanHistoryEntries
            ? items.length - AiSessionDataLimits.maxPlanHistoryEntries
            : 0;
        return items
            .skip(start)
            .whereType<Map>()
            .map(
              (item) =>
                  AiSessionPlanRecord.fromJson(stringKeyedMapFromValue(item)),
            )
            .toList(growable: false);
      }(),
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
