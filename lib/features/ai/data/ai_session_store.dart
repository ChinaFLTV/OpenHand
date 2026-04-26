import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/data/atomic_file_operations.dart';
import '../../../shared/data/database_service.dart';
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
  Future<AiSessionLoadResult> loadAll() async {
    final issues = <AiSessionPersistenceIssue>[];
    final sessionRows = await _db.query('sessions', orderBy: 'updated_at DESC');

    final sessions = <AiSession>[];
    for (final row in sessionRows) {
      try {
        final sessionId = row['id'] as String;
        final messageRows = await _db.query(
          'messages',
          where: 'session_id = ?',
          whereArgs: <Object?>[sessionId],
          orderBy: 'sort_order ASC',
        );
        sessions.add(_sessionFromRow(row, messageRows));
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

  /// Loads **only session metadata** (no messages).  Much faster for building
  /// the sidebar session list.
  Future<AiSessionLoadResult> loadAllHeaders() async {
    final issues = <AiSessionPersistenceIssue>[];
    final sessionRows = await _db.query('sessions', orderBy: 'updated_at DESC');

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
    return _sessionFromRow(rows.first, messageRows);
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
      orderBy: 'updated_at DESC',
    );
    final sessions = <AiSession>[];
    for (final row in rows) {
      try {
        final sessionId = row['id'] as String;
        final messageRows = await _db.query(
          'messages',
          where: 'session_id = ?',
          whereArgs: <Object?>[sessionId],
          orderBy: 'sort_order ASC',
        );
        sessions.add(_sessionFromRow(row, messageRows));
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

    final messages = rows.map(_messageFromRow).toList(growable: false);
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

    await _db.transaction((txn) async {
      // Upsert session row.
      await txn.insert(
        'sessions',
        _sessionToRow(session),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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
