import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../features/ai/model/ai_allow_command_rule.dart';
import '../../features/ai/model/ai_auto_title_fetch_mode.dart';
import '../../features/ai/model/ai_builtin_tool_config.dart';
import '../../features/ai/model/ai_deny_command_rule.dart';
import '../../features/ai/model/ai_lsp_language_settings.dart';
import '../../features/ai/model/ai_message_content_format.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../../features/ai/model/ai_sandbox_settings.dart';
import '../../features/ai/model/ai_translation_settings.dart';
import '../../features/ai/model/ai_tts_settings.dart';
import '../../features/mcp/model/mcp_keyword_index_update_mode.dart';
import '../../features/mcp/model/mcp_lazy_loading_mode.dart';
import '../../features/mcp/model/mcp_stdio_mirror_mode.dart';
import '../../shared/db/database_service.dart';
import '../../shared/db/legacy_persistence.dart';
import '../../shared/model/native_audio_playback_settings.dart';
import '../../shared/util/input_value_parsing.dart';
import '../model/app_language.dart';
import '../model/app_proxy_settings.dart';
import '../model/app_settings_snapshot.dart';
import '../model/dialog_animation_settings.dart';
import '../model/editor_code_theme.dart';
import '../model/editor_indent.dart';
import '../model/editor_shortcut.dart';
import '../model/openhand_shortcut.dart';
import '../support/openhand_paths.dart';
import '../support/silent_log.dart';
import '../support/url_validation.dart';
import '../theme/openhand_theme_preset.dart';

enum SettingsPersistenceIssueKind { loadFailed, invalidContent, saveFailed }

class SettingsPersistenceIssue {
  const SettingsPersistenceIssue({required this.kind, required this.filePath});

  final SettingsPersistenceIssueKind kind;
  final String filePath;
}

class SettingsLoadResult {
  const SettingsLoadResult({
    required this.snapshot,
    required this.canPersist,
    this.issue,
  });

  final AppSettingsSnapshot snapshot;
  final bool canPersist;
  final SettingsPersistenceIssue? issue;
}

class SettingsStore {
  static const String _dbSettingsKey = 'app_settings_json';
  static const String _legacyMigrationKey = 'legacy_settings_toml_v1';
  static const String _emptySettingsJsonMessage = '设置 JSON 为空。';
  static const String _invalidSettingsRootMessage = '设置 JSON 根节点必须是对象。';
  static const String _retiredBuiltinToolKindPrefix = 'agent';
  static const int _currentSchemaVersion = 5;

  /// 保留该路径以兼容仍对外暴露路径的控制器。
  String get settingsFilePath => 'db://app_settings';

  Database get _db => DatabaseService.instance.database;
  // 数据库承载的主要加载与保存入口。
  Future<SettingsLoadResult> load() async {
    try {
      final rows = await _db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: <Object?>[_dbSettingsKey],
        limit: 1,
      );

      if (rows.isNotEmpty) {
        try {
          final source = _decodeSettingsJson(rows.first['value']);
          final removedRetiredTools = _removeRetiredBuiltinToolConfigs(source);
          final snapshot = _snapshotFromJson(source);
          try {
            await markLegacyTargetPresentIfAbsent(
              _db,
              key: _legacyMigrationKey,
            );
          } catch (error, stack) {
            silentLog('settings_store', '标记旧版设置迁移', error, stack);
          }
          if (removedRetiredTools) {
            try {
              await save(snapshot);
            } catch (error, stack) {
              silentLog('settings_store', '清理已下线内置工具配置', error, stack);
            }
          }
          return SettingsLoadResult(snapshot: snapshot, canPersist: true);
        } catch (error, stack) {
          silentLog('settings_store', '解码数据库设置', error, stack);
          return SettingsLoadResult(
            snapshot: AppSettingsSnapshot.defaults(),
            canPersist: false,
            issue: SettingsPersistenceIssue(
              kind: SettingsPersistenceIssueKind.invalidContent,
              filePath: settingsFilePath,
            ),
          );
        }
      }

      return await _initializeMissingSettings();
    } catch (error, stack) {
      silentLog('settings_store', '加载数据库设置', error, stack);
      return SettingsLoadResult(
        snapshot: AppSettingsSnapshot.defaults(),
        canPersist: false,
        issue: SettingsPersistenceIssue(
          kind: SettingsPersistenceIssueKind.loadFailed,
          filePath: settingsFilePath,
        ),
      );
    }
  }

  Future<void> save(AppSettingsSnapshot snapshot) async {
    final jsonStr = _encodeSettingsSnapshot(snapshot);
    await _db.insert('app_settings', <String, Object?>{
      'key': _dbSettingsKey,
      'value': jsonStr,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  bool _removeRetiredBuiltinToolConfigs(Map<String, Object?> source) {
    final rawConfigs = source['builtin_tool_configs'];
    if (rawConfigs is! List) return false;
    final filtered = <Object?>[];
    var removed = false;
    for (final item in rawConfigs) {
      final config = optionalStringKeyedMapFromValueOrJsonText(item);
      final kind = config == null ? '' : stringFromValue(config['kind']);
      const suffixIndex = _retiredBuiltinToolKindPrefix.length;
      final isRetired =
          kind.startsWith(_retiredBuiltinToolKindPrefix) &&
          kind.length > suffixIndex &&
          kind.codeUnitAt(suffixIndex) >= 0x41 &&
          kind.codeUnitAt(suffixIndex) <= 0x5A;
      if (isRetired) {
        removed = true;
      } else {
        filtered.add(item);
      }
    }
    if (removed) source['builtin_tool_configs'] = filtered;
    return removed;
  }

  Future<SettingsLoadResult> _initializeMissingSettings() async {
    var issuePath = settingsFilePath;
    try {
      final markerRows = await _db.query(
        legacyMigrationMetaTable,
        where: 'key = ?',
        whereArgs: <Object?>[_legacyMigrationKey],
        limit: 1,
      );
      final markerExisted = markerRows.isNotEmpty;
      final legacyFile = markerExisted ? null : await findLegacySettingsFile();
      issuePath = legacyFile?.path ?? settingsFilePath;

      LegacySettingsDocument? document;
      var candidate = AppSettingsSnapshot.defaults();
      if (legacyFile != null) {
        document = await readLegacySettingsDocument(legacyFile);
        if (optionalIntegralIntFromValue(document.rootValues['version']) != 1) {
          throw const FormatException('旧版设置缺少版本号或版本不受支持。');
        }
        candidate = _snapshotFromJson(_legacySettingsJson(document));
      }

      final persisted = await _db.transaction<AppSettingsSnapshot?>((
        txn,
      ) async {
        final currentRows = await txn.query(
          'app_settings',
          columns: const <String>['value'],
          where: 'key = ?',
          whereArgs: <Object?>[_dbSettingsKey],
          limit: 1,
        );
        if (currentRows.isNotEmpty) return null;

        final currentMarkerRows = await txn.query(
          legacyMigrationMetaTable,
          columns: const <String>['value'],
          where: 'key = ?',
          whereArgs: <Object?>[_legacyMigrationKey],
          limit: 1,
        );
        final markerAppeared = !markerExisted && currentMarkerRows.isNotEmpty;
        final snapshot = markerAppeared
            ? AppSettingsSnapshot.defaults()
            : candidate;
        final encodedSnapshot = _encodeSettingsSnapshot(snapshot);
        await txn.insert('app_settings', <String, Object?>{
          'key': _dbSettingsKey,
          'value': encodedSnapshot,
        }, conflictAlgorithm: ConflictAlgorithm.abort);
        if (currentMarkerRows.isEmpty) {
          await txn.insert(legacyMigrationMetaTable, <String, Object?>{
            'key': _legacyMigrationKey,
            'value': encodeLegacyMigrationMarker(
              status: legacyFile == null
                  ? legacyMigrationStatusNotFound
                  : legacyMigrationStatusImported,
              sourcePath: legacyFile?.path,
              memoryFilePath: document?.configuredMemoryFilePath,
            ),
          }, conflictAlgorithm: ConflictAlgorithm.abort);
        }
        return snapshot;
      });
      if (persisted != null) {
        return SettingsLoadResult(snapshot: persisted, canPersist: true);
      }

      final racedRows = await _db.query(
        'app_settings',
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: <Object?>[_dbSettingsKey],
        limit: 1,
      );
      if (racedRows.isEmpty) {
        throw StateError('设置初始化期间目标记录丢失。');
      }
      return SettingsLoadResult(
        snapshot: _snapshotFromJson(
          _decodeSettingsJson(racedRows.first['value']),
        ),
        canPersist: true,
      );
    } on FormatException catch (error, stack) {
      silentLog('settings_store', '初始化旧版设置', error, stack);
      return SettingsLoadResult(
        snapshot: AppSettingsSnapshot.defaults(),
        canPersist: false,
        issue: SettingsPersistenceIssue(
          kind: SettingsPersistenceIssueKind.invalidContent,
          filePath: issuePath,
        ),
      );
    } catch (error, stack) {
      silentLog('settings_store', '初始化应用设置', error, stack);
      return SettingsLoadResult(
        snapshot: AppSettingsSnapshot.defaults(),
        canPersist: false,
        issue: SettingsPersistenceIssue(
          kind: SettingsPersistenceIssueKind.loadFailed,
          filePath: issuePath,
        ),
      );
    }
  }

  static Map<String, Object?> _decodeSettingsJson(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException(_emptySettingsJsonMessage);
    }
    _validateSettingsJsonSize(value);
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException(_invalidSettingsRootMessage);
    }
    return stringKeyedMapFromValue(decoded);
  }

  static String _encodeSettingsSnapshot(AppSettingsSnapshot snapshot) {
    final encoded = jsonEncode(_snapshotToJson(snapshot));
    _validateSettingsJsonSize(encoded);
    return encoded;
  }

  static void _validateSettingsJsonSize(String value) {
    if (value.length > maxSettingsDocumentBytes ||
        utf8.encode(value).length > maxSettingsDocumentBytes) {
      throw const FormatException('设置 JSON 超过存储安全上限。');
    }
  }

  static Map<String, Object?> _legacySettingsJson(
    LegacySettingsDocument document,
  ) {
    final json = Map<String, Object?>.from(document.rootValues)
      ..['ai_models'] = document.modelValues
      ..['user_memory_file_path'] = OpenHandPaths.defaultDatabasePath();
    for (final key in const <String>[
      'shortcut_bindings',
      'dialog_animation_settings',
      'menu_animation_settings',
    ]) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) continue;
      try {
        json[key] = jsonDecode(value);
      } on FormatException {
        // 当前解析会为该字段应用生产默认值。
      }
    }
    return json;
  }

  // AppSettingsSnapshot 的 JSON 序列化。
  static Map<String, Object?> _snapshotToJson(AppSettingsSnapshot snapshot) {
    return <String, Object?>{
      'version': _currentSchemaVersion,
      'theme_mode': _themeModeToStorage(snapshot.themeMode),
      'theme_preset': snapshot.themePreset.storageValue,
      'language': snapshot.language.storageValue,
      'skills_storage_path': snapshot.skillsStoragePath,
      'mcp_enabled': snapshot.mcpEnabled,
      'mcp_servers_file_path': snapshot.mcpServersFilePath,
      'mcp_lazy_loading_mode': snapshot.mcpLazyLoadingMode.storageValue,
      'mcp_stdio_mirror_mode': snapshot.mcpStdioMirrorMode.storageValue,
      'mcp_lazy_loading_threshold_tokens':
          snapshot.mcpLazyLoadingThresholdTokens,
      'builtin_tool_lazy_loading_mode':
          snapshot.builtinToolLazyLoadingMode.storageValue,
      'mcp_auto_probe_concurrency': snapshot.mcpAutoProbeConcurrency,
      'mcp_keyword_index_update_mode':
          snapshot.mcpKeywordIndexUpdateMode.storageValue,
      'mcp_keyword_index_interval_value': snapshot.mcpKeywordIndexIntervalValue,
      'mcp_keyword_index_interval_unit':
          snapshot.mcpKeywordIndexIntervalUnit.storageValue,
      'mcp_keyword_index_scheduled_time_of_day':
          snapshot.mcpKeywordIndexScheduledTimeOfDay,
      'memory_enabled': snapshot.memoryEnabled,
      'user_memory_file_path': snapshot.userMemoryFilePath,
      'editor_word_wrap': snapshot.editorWordWrap,
      'editor_indent_spaces': normalizeEditorIndentSpaces(
        snapshot.editorIndentSpaces,
      ),
      'editor_code_theme': snapshot.editorCodeTheme.storageValue,
      'editor_lsp_settings': <String, Object?>{
        for (final entry in snapshot.editorLspSettings.entries)
          entry.key: entry.value.toJson(),
      },
      'editor_shortcut_bindings': <String, List<int>>{
        for (final entry in snapshot.editorShortcutBindings.entries)
          editorShortcutActionStorageKey(entry.key): normalizeShortcutKeyIds(
            entry.value,
          ),
      },
      'ai_message_compression_threshold_chars':
          snapshot.aiMessageCompressionThresholdChars,
      'ai_tool_result_compression_threshold_chars':
          snapshot.aiToolResultCompressionThresholdChars,
      'ai_tool_result_compression_enabled':
          snapshot.aiToolResultCompressionEnabled,
      'ai_micro_compression_enabled': snapshot.aiMicroCompressionEnabled,
      'ai_message_content_format': snapshot.aiMessageContentFormat.storageKey,
      'ai_html_render_fallback': snapshot.aiHtmlRenderFallback.storageKey,
      'ai_html_content_richness': snapshot.aiHtmlContentRichness.storageKey,
      'ai_tool_result_compression_head_tail_window_chars':
          snapshot.aiToolResultCompressionHeadTailWindowChars,
      'ai_tool_result_compression_max_path_hits':
          snapshot.aiToolResultCompressionMaxPathHits,
      'ai_input_cache_enabled': snapshot.aiInputCacheEnabled,
      'ai_input_cache_update_mode': snapshot.aiInputCacheUpdateMode,
      'ai_input_cache_update_interval': snapshot.aiInputCacheUpdateInterval,
      'ai_input_cache_breakpoint_count': snapshot.aiInputCacheBreakpointCount,
      'ai_input_cache_breakpoint_positions':
          snapshot.aiInputCacheBreakpointPositions,
      'ai_budget_usd_per_session': snapshot.aiBudgetUsdPerSession,
      'ai_write_tool_summary_max_chars': snapshot.aiWriteToolSummaryMaxChars,
      'ai_single_round_tool_call_limit': snapshot.aiSingleRoundToolCallLimit,
      'ai_max_recent_errors': snapshot.aiMaxRecentErrors,
      'ai_max_plan_history_entries': snapshot.aiMaxPlanHistoryEntries,
      'ai_max_truncation_continuations': snapshot.aiMaxTruncationContinuations,
      'ai_estimated_characters_per_token':
          snapshot.aiEstimatedCharactersPerToken,
      'ai_max_tool_output_chars': snapshot.aiMaxToolOutputChars,
      'ai_write_confirmation_timeout_ms': snapshot.aiWriteConfirmationTimeoutMs,
      'ai_fast_path_write_analysis_threshold':
          snapshot.aiFastPathWriteAnalysisThreshold,
      'ai_max_hook_text_characters': snapshot.aiMaxHookTextCharacters,
      'ai_attachment_max_inline_image_dimension':
          snapshot.aiAttachmentMaxInlineImageDimension,
      'ai_attachment_max_text_raw_bytes': snapshot.aiAttachmentMaxTextRawBytes,
      'ai_attachment_max_pdf_raw_bytes': snapshot.aiAttachmentMaxPdfRawBytes,
      'ai_attachment_max_image_raw_bytes':
          snapshot.aiAttachmentMaxImageRawBytes,
      'ai_chat_max_stream_line_buffer_bytes':
          snapshot.aiChatMaxStreamLineBufferBytes,
      'ai_fallback_title_max_characters': snapshot.aiFallbackTitleMaxCharacters,
      'ai_generated_title_max_characters':
          snapshot.aiGeneratedTitleMaxCharacters,
      'ai_auto_title_max_retry_count': snapshot.aiAutoTitleMaxRetryCount,
      'ai_minimum_meaningful_title_characters':
          snapshot.aiMinimumMeaningfulTitleCharacters,
      'ai_minimum_meaningful_latin_title_words':
          snapshot.aiMinimumMeaningfulLatinTitleWords,
      'ai_max_skill_content_length': snapshot.aiMaxSkillContentLength,
      'ai_max_workspace_document_characters':
          snapshot.aiMaxWorkspaceDocumentCharacters,
      'ai_sequential_tool_round_limit': snapshot.aiSequentialToolRoundLimit,
      'ai_image_size_limit_bytes': snapshot.aiImageSizeLimitBytes,
      'ai_translation': snapshot.aiTranslationSettings.toJson(),
      'ai_tts': snapshot.aiTtsSettings.toJson(),
      'ai_write_command_confirmation_enabled':
          snapshot.aiWriteCommandConfirmationEnabled,
      'ai_allow_command_rules': snapshot.aiAllowCommandRules
          .map((item) => item.toJson())
          .toList(growable: false),
      'ai_deny_command_rules': snapshot.aiDenyCommandRules
          .map((item) => item.toJson())
          .toList(growable: false),
      'ai_sandbox': snapshot.aiSandboxSettings.toJson(),
      'ai_connect_timeout_seconds': snapshot.aiConnectTimeoutSeconds,
      'ai_response_timeout_seconds': snapshot.aiResponseTimeoutSeconds,
      'ai_stream_idle_timeout_seconds': snapshot.aiStreamIdleTimeoutSeconds,
      'ai_stream_max_chars_per_second': snapshot.aiStreamMaxCharsPerSecond,
      'ai_stream_max_message_cards_per_second':
          snapshot.aiStreamMaxMessageCardsPerSecond,
      'ai_stream_throttle_enabled': snapshot.aiStreamThrottleEnabled,
      'ai_stream_throttle_auto_mode': snapshot.aiStreamThrottleAutoMode,
      'ai_stream_throttle_duration_seconds':
          snapshot.aiStreamThrottleDurationSeconds,
      'ai_stream_throttle_cloud_sync_provider':
          snapshot.aiStreamThrottleCloudSyncProvider,
      'ai_stream_throttle_cloud_sync_endpoint':
          snapshot.aiStreamThrottleCloudSyncEndpoint,
      'ai_stream_throttle_cloud_sync_token':
          snapshot.aiStreamThrottleCloudSyncToken,
      'ai_stream_throttle_config_updated_at_ms':
          snapshot.aiStreamThrottleConfigUpdatedAtMs,
      // v3 schema 起，按线程模板覆盖节流参数已下线，
      // 持久化层不再写出 `ai_stream_throttle_template_overrides`；
      // 读取路径会静默丢弃任何旧文档上的同名字段。
      'ai_auto_title_enabled': snapshot.aiAutoTitleEnabled,
      'ai_auto_title_fetch_mode': snapshot.aiAutoTitleFetchMode.storageValue,
      'ai_default_session_mode': snapshot.aiDefaultSessionMode,
      'ai_default_full_access_permission':
          snapshot.aiDefaultFullAccessPermission,
      'selected_ai_model_id': snapshot.selectedAiModelId ?? '',
      'recent_model_selections': snapshot.recentModelSelections
          .map((item) => item.toJson())
          .toList(growable: false),
      'shortcut_bindings': <String, List<int>>{
        for (final entry in snapshot.shortcutBindings.entries)
          openHandShortcutActionStorageKey(entry.key): normalizeShortcutKeyIds(
            entry.value,
          ),
      },
      'dialog_animation_settings': snapshot.dialogAnimationSettings.toJson(),
      'menu_animation_settings': snapshot.menuAnimationSettings.toJson(),
      'page_animation_settings': snapshot.pageAnimationSettings.toJson(),
      'panel_animation_settings': snapshot.panelAnimationSettings.toJson(),
      'chip_animation_settings': snapshot.chipAnimationSettings.toJson(),
      'list_item_animation_settings': snapshot.listItemAnimationSettings
          .toJson(),
      'native_audio_playback': snapshot.nativeAudioPlaybackSettings.toJson(),
      'builtin_tool_configs': snapshot.builtinToolConfigs
          .map((item) => item.toJson())
          .toList(growable: false),
      'telemetry_debug_enabled': snapshot.telemetryDebugEnabled,
      'telemetry_capture_raw_payload': snapshot.telemetryCaptureRawPayload,
      'telemetry_capture_environment': snapshot.telemetryCaptureEnvironment,
      'telemetry_max_payload_chars': snapshot.telemetryMaxPayloadChars,
      'self_learning_enabled': snapshot.selfLearningEnabled,
      'self_learning_concurrency': snapshot.selfLearningConcurrency,
      'self_learning_stream_flush_interval_ms':
          snapshot.selfLearningStreamFlushIntervalMs,
      'show_self_learning_messages': snapshot.showSelfLearningMessages,
      'cron_auto_cleanup_enabled': snapshot.cronAutoCleanupEnabled,
      'cron_auto_cleanup_retention_days': snapshot.cronAutoCleanupRetentionDays,
      'harness_tool_search_history_max_phases':
          snapshot.harnessToolSearchHistoryMaxPhases,
      'tool_search_replay_cancel_window_seconds':
          snapshot.toolSearchReplayCancelWindowSeconds,
      'reduce_motion': snapshot.reduceMotion,
      'proxy': snapshot.proxySettings.toJson(),
      'subprocess_graceful_shutdown_ms': snapshot.subprocessGracefulShutdownMs,
      'bash_output_max_bytes': snapshot.bashOutputMaxBytes,
      'max_concurrent_tools': snapshot.maxConcurrentTools,
      'ai_models': snapshot.aiModels
          .map((model) => model.toJson())
          .toList(growable: false),
    };
  }

  static bool _migrateAiInputCacheEnabled({
    required bool persisted,
    required int schemaVersion,
  }) {
    if (schemaVersion < 3 && !persisted) {
      // v2 为大量用户写入旧的 false 默认值。升级时将其视为旧默认状态，
      // 让 Claude 兼容会话启用明确的提示缓存断点；v3 的 false 仍表示主动关闭。
      return AppSettingsSnapshot.defaultAiInputCacheEnabled;
    }
    return persisted;
  }

  static bool _migrateAiMicroCompressionEnabled({
    required bool persisted,
    required int schemaVersion,
  }) {
    if (schemaVersion < 4 && !persisted) {
      // 旧架构为多数用户写入 false 默认值。升级时将其视为旧默认状态，
      // 避免已消费的工具结果持续膨胀后续提示；v4 的 false 仍表示主动关闭。
      return AppSettingsSnapshot.defaultAiMicroCompressionEnabled;
    }
    return persisted;
  }

  static int _migrateMcpLazyLoadingThresholdTokens({
    required int persisted,
    required int schemaVersion,
  }) {
    if (schemaVersion < 5 &&
        persisted == AppSettingsSnapshot.legacyMcpLazyLoadingThresholdTokens) {
      // 旧版把默认值 80000 写进了库，升级后一次性收敛到新默认值 16000。
      // 仅迁移版本 5 之前的旧默认值，避免覆盖用户主动设置的 80000。
      return AppSettingsSnapshot.defaultMcpLazyLoadingThresholdTokens;
    }
    return persisted;
  }

  static AppSettingsSnapshot _snapshotFromJson(Map<String, Object?> json) {
    final schemaVersion = optionalIntegralIntFromValue(json['version']) ?? 0;
    final themeMode = _themeModeFromStorage('${json['theme_mode'] ?? ''}');
    final rawThemePreset = '${json['theme_preset'] ?? ''}'.trim();
    final themePreset = OpenHandThemePreset.fromStorage(rawThemePreset);
    final language = appLanguageFromStorage('${json['language'] ?? ''}');

    final skillsStoragePath = OpenHandPaths.normalizeUserPath(
      '${json['skills_storage_path'] ?? ''}',
    );
    final mcpEnabled = boolFromValue(json['mcp_enabled'], defaultValue: true);
    final mcpServersFilePath = OpenHandPaths.normalizePath(
      '${json['mcp_servers_file_path'] ?? ''}',
      defaultPath: OpenHandPaths.defaultMcpServersFilePath(),
    );
    final mcpLazyLoadingMode = McpLazyLoadingMode.fromStorage(
      '${json['mcp_lazy_loading_mode'] ?? ''}',
    );
    final builtinToolLazyLoadingMode = AiBuiltinToolLazyLoadingMode.fromStorage(
      '${json['builtin_tool_lazy_loading_mode'] ?? ''}',
    );
    final mcpStdioMirrorMode = McpStdioMirrorMode.fromStorage(
      '${json['mcp_stdio_mirror_mode'] ?? ''}',
    );
    final loadedMcpLazyLoadingThresholdTokens = clampedIntFromValue(
      json['mcp_lazy_loading_threshold_tokens'],
      fallback: AppSettingsSnapshot.defaultMcpLazyLoadingThresholdTokens,
      min: AppSettingsSnapshot.minMcpLazyLoadingThresholdTokens,
      max: AppSettingsSnapshot.maxMcpLazyLoadingThresholdTokens,
    );
    final mcpLazyLoadingThresholdTokens = _migrateMcpLazyLoadingThresholdTokens(
      persisted: loadedMcpLazyLoadingThresholdTokens,
      schemaVersion: schemaVersion,
    );
    final mcpAutoProbeConcurrency = clampedIntFromValue(
      json['mcp_auto_probe_concurrency'],
      fallback: AppSettingsSnapshot.defaultMcpAutoProbeConcurrency,
      min: AppSettingsSnapshot.minMcpAutoProbeConcurrency,
      max: AppSettingsSnapshot.maxMcpAutoProbeConcurrency,
    );
    final mcpKeywordIndexUpdateMode = McpKeywordIndexUpdateMode.fromStorage(
      '${json['mcp_keyword_index_update_mode'] ?? ''}',
    );
    final mcpKeywordIndexIntervalValue = clampedIntFromValue(
      json['mcp_keyword_index_interval_value'],
      fallback: AppSettingsSnapshot.defaultMcpKeywordIndexIntervalValue,
      min: AppSettingsSnapshot.minMcpKeywordIndexIntervalValue,
      max: AppSettingsSnapshot.maxMcpKeywordIndexIntervalValue,
    );
    final mcpKeywordIndexIntervalUnit = McpKeywordIndexIntervalUnit.fromStorage(
      '${json['mcp_keyword_index_interval_unit'] ?? ''}',
    );
    final mcpKeywordIndexScheduledTimeOfDay =
        normalizeMcpKeywordIndexScheduledTimeOfDay(
          '${json['mcp_keyword_index_scheduled_time_of_day'] ?? AppSettingsSnapshot.defaultMcpKeywordIndexScheduledTimeOfDay}',
        );
    final memoryEnabled = boolFromValue(
      json['memory_enabled'],
      defaultValue: true,
    );
    final userMemoryFilePath = OpenHandPaths.defaultDatabasePath();
    final editorWordWrap = boolFromValue(
      json['editor_word_wrap'],
      defaultValue: true,
    );
    final editorIndentSpaces = normalizeEditorIndentSpaces(
      (json['editor_indent_spaces'] as num?)?.toInt(),
    );
    final editorCodeTheme = EditorCodeTheme.fromStorage(
      '${json['editor_code_theme'] ?? ''}',
    );
    final editorLspSettings = <String, AiLspLanguageSettings>{};
    final rawEditorLspSettings = json['editor_lsp_settings'];
    if (rawEditorLspSettings is Map) {
      for (final entry in rawEditorLspSettings.entries) {
        final language = stringFromValue(entry.key);
        if (language.isEmpty) continue;
        final value = optionalStringKeyedMapFromValueOrJsonText(entry.value);
        if (value == null) continue;
        try {
          editorLspSettings[language] = AiLspLanguageSettings.fromJson(value);
        } catch (error, stack) {
          silentLog('settings_store', '解析编辑器 LSP 设置项', error, stack);
        }
      }
    }
    final rawEditorShortcutBindings = json['editor_shortcut_bindings'];
    var editorShortcutBindings = defaultEditorShortcutBindings();
    if (rawEditorShortcutBindings is Map) {
      final parsed = <EditorShortcutAction, List<int>>{};
      for (final entry in rawEditorShortcutBindings.entries) {
        final action = editorShortcutActionFromStorageKey('${entry.key}');
        if (action == null) {
          continue;
        }
        final value = entry.value;
        if (value is! List) {
          continue;
        }
        final normalized = normalizeShortcutKeyIds(
          value.whereType<num>().map((item) => item.toInt()),
        );
        if (isValidShortcutBinding(normalized)) {
          parsed[action] = normalized;
        }
      }
      editorShortcutBindings = <EditorShortcutAction, List<int>>{
        ...defaultEditorShortcutBindings(),
        ...parsed,
      };
    }
    final aiMessageCompressionThresholdChars =
        AppSettingsSnapshot.normalizeAiMessageCompressionThresholdChars(
          intFromValue(
            json['ai_message_compression_threshold_chars'],
            fallback:
                AppSettingsSnapshot.defaultAiMessageCompressionThresholdChars,
          ),
        );
    final aiToolResultCompressionThresholdChars =
        AppSettingsSnapshot.normalizeAiToolResultCompressionThresholdChars(
          intFromValue(
            json['ai_tool_result_compression_threshold_chars'],
            fallback: AppSettingsSnapshot
                .defaultAiToolResultCompressionThresholdChars,
          ),
        );
    final aiToolResultCompressionEnabled = boolFromValue(
      json['ai_tool_result_compression_enabled'],
      defaultValue: true,
    );
    final rawAiMicroCompressionEnabled = optionalBoolFromValue(
      json['ai_micro_compression_enabled'],
    );
    final aiMicroCompressionEnabled = rawAiMicroCompressionEnabled == null
        ? AppSettingsSnapshot.defaultAiMicroCompressionEnabled
        : _migrateAiMicroCompressionEnabled(
            persisted: rawAiMicroCompressionEnabled,
            schemaVersion: schemaVersion,
          );
    final aiMessageContentFormat = AiMessageContentFormat.fromStorageKey(
      json['ai_message_content_format'],
    );
    final aiHtmlRenderFallback = AiHtmlRenderFallback.fromStorageKey(
      json['ai_html_render_fallback'],
    );
    final aiHtmlContentRichness = AiHtmlContentRichness.fromStorageKey(
      json['ai_html_content_richness'],
    );
    final aiToolResultCompressionHeadTailWindowChars = clampedIntFromValue(
      json['ai_tool_result_compression_head_tail_window_chars'],
      fallback:
          AppSettingsSnapshot.defaultAiToolResultCompressionHeadTailWindowChars,
      min: AppSettingsSnapshot.minAiToolResultCompressionHeadTailWindowChars,
      max: AppSettingsSnapshot.maxAiToolResultCompressionHeadTailWindowChars,
    );
    final aiToolResultCompressionMaxPathHits = clampedIntFromValue(
      json['ai_tool_result_compression_max_path_hits'],
      fallback: AppSettingsSnapshot.defaultAiToolResultCompressionMaxPathHits,
      min: AppSettingsSnapshot.minAiToolResultCompressionMaxPathHits,
      max: AppSettingsSnapshot.maxAiToolResultCompressionMaxPathHits,
    );
    final rawAiInputCacheEnabled = optionalBoolFromValue(
      json['ai_input_cache_enabled'],
    );
    final aiInputCacheEnabled = rawAiInputCacheEnabled == null
        ? AppSettingsSnapshot.defaultAiInputCacheEnabled
        : _migrateAiInputCacheEnabled(
            persisted: rawAiInputCacheEnabled,
            schemaVersion: schemaVersion,
          );
    final aiInputCacheUpdateMode =
        json['ai_input_cache_update_mode'] is String &&
            AppSettingsSnapshot.validAiInputCacheUpdateModes.contains(
              json['ai_input_cache_update_mode'] as String,
            )
        ? json['ai_input_cache_update_mode'] as String
        : AppSettingsSnapshot.defaultAiInputCacheUpdateMode;
    final aiInputCacheUpdateInterval = clampedIntFromValue(
      json['ai_input_cache_update_interval'],
      fallback: AppSettingsSnapshot.defaultAiInputCacheUpdateInterval,
      min: AppSettingsSnapshot.minAiInputCacheUpdateInterval,
      max: AppSettingsSnapshot.maxAiInputCacheUpdateInterval,
    );
    final aiInputCacheBreakpointCount = clampedIntFromValue(
      json['ai_input_cache_breakpoint_count'],
      fallback: AppSettingsSnapshot.defaultAiInputCacheBreakpointCount,
      min: AppSettingsSnapshot.minAiInputCacheBreakpointCount,
      max: AppSettingsSnapshot.maxAiInputCacheBreakpointCount,
    );
    // 用户自定义的历史消息候选点位置（百分比 0..1，升序）。
    // JSON 形如 [0.25, 0.5, 0.75]；非法元素直接忽略，越界 clamp 至 [0,1]。
    final List<double> aiInputCacheBreakpointPositions = () {
      final raw = json['ai_input_cache_breakpoint_positions'];
      return optionalUnitIntervalListFromValue(raw, sorted: true) ??
          AppSettingsSnapshot.defaultAiInputCacheBreakpointPositions;
    }();
    final aiBudgetUsdPerSession = clampedDoubleFromValue(
      json['ai_budget_usd_per_session'],
      fallback: AppSettingsSnapshot.defaultAiBudgetUsdPerSession,
      min: AppSettingsSnapshot.minAiBudgetUsdPerSession,
      max: AppSettingsSnapshot.maxAiBudgetUsdPerSession,
    );
    final aiWriteToolSummaryMaxChars = clampedIntFromValue(
      json['ai_write_tool_summary_max_chars'],
      fallback: AppSettingsSnapshot.defaultAiWriteToolSummaryMaxChars,
      min: AppSettingsSnapshot.minAiWriteToolSummaryMaxChars,
      max: AppSettingsSnapshot.maxAiWriteToolSummaryMaxChars,
    );
    final aiSingleRoundToolCallLimit =
        AppSettingsSnapshot.aiSingleRoundToolCallLimitFromValue(
          json['ai_single_round_tool_call_limit'],
        );
    final aiSequentialToolRoundLimit =
        AppSettingsSnapshot.aiSequentialToolRoundLimitFromValue(
          json['ai_sequential_tool_round_limit'],
        );
    final aiMaxRecentErrors = clampedIntFromValue(
      json['ai_max_recent_errors'],
      fallback: AppSettingsSnapshot.defaultAiMaxRecentErrors,
      min: AppSettingsSnapshot.minAiMaxRecentErrors,
      max: AppSettingsSnapshot.maxAiMaxRecentErrors,
    );
    final aiMaxPlanHistoryEntries = clampedIntFromValue(
      json['ai_max_plan_history_entries'],
      fallback: AppSettingsSnapshot.defaultAiMaxPlanHistoryEntries,
      min: AppSettingsSnapshot.minAiMaxPlanHistoryEntries,
      max: AppSettingsSnapshot.maxAiMaxPlanHistoryEntries,
    );
    final aiMaxTruncationContinuations = clampedIntFromValue(
      json['ai_max_truncation_continuations'],
      fallback: AppSettingsSnapshot.defaultAiMaxTruncationContinuations,
      min: AppSettingsSnapshot.minAiMaxTruncationContinuations,
      max: AppSettingsSnapshot.maxAiMaxTruncationContinuations,
    );
    final aiEstimatedCharactersPerToken = clampedIntFromValue(
      json['ai_estimated_characters_per_token'],
      fallback: AppSettingsSnapshot.defaultAiEstimatedCharactersPerToken,
      min: AppSettingsSnapshot.minAiEstimatedCharactersPerToken,
      max: AppSettingsSnapshot.maxAiEstimatedCharactersPerToken,
    );
    final aiMaxToolOutputChars =
        AppSettingsSnapshot.aiMaxToolOutputCharsFromValue(
          json['ai_max_tool_output_chars'],
        );
    final aiWriteConfirmationTimeoutMs =
        AppSettingsSnapshot.aiWriteConfirmationTimeoutMsFromValue(
          json['ai_write_confirmation_timeout_ms'],
        );
    final aiFastPathWriteAnalysisThreshold =
        AppSettingsSnapshot.aiFastPathWriteAnalysisThresholdFromValue(
          json['ai_fast_path_write_analysis_threshold'],
        );
    final aiMaxHookTextCharacters =
        AppSettingsSnapshot.aiMaxHookTextCharactersFromValue(
          json['ai_max_hook_text_characters'],
        );
    final aiAttachmentMaxInlineImageDimension = clampedIntFromValue(
      json['ai_attachment_max_inline_image_dimension'],
      fallback: AppSettingsSnapshot.defaultAiAttachmentMaxInlineImageDimension,
      min: AppSettingsSnapshot.minAiAttachmentMaxInlineImageDimension,
      max: AppSettingsSnapshot.maxAiAttachmentMaxInlineImageDimension,
    );
    final aiAttachmentMaxTextRawBytes = clampedIntFromValue(
      json['ai_attachment_max_text_raw_bytes'],
      fallback: AppSettingsSnapshot.defaultAiAttachmentMaxTextRawBytes,
      min: AppSettingsSnapshot.minAiAttachmentMaxTextRawBytes,
      max: AppSettingsSnapshot.maxAiAttachmentMaxTextRawBytes,
    );
    final aiAttachmentMaxPdfRawBytes = clampedIntFromValue(
      json['ai_attachment_max_pdf_raw_bytes'],
      fallback: AppSettingsSnapshot.defaultAiAttachmentMaxPdfRawBytes,
      min: AppSettingsSnapshot.minAiAttachmentMaxPdfRawBytes,
      max: AppSettingsSnapshot.maxAiAttachmentMaxPdfRawBytes,
    );
    final aiAttachmentMaxImageRawBytes = clampedIntFromValue(
      json['ai_attachment_max_image_raw_bytes'],
      fallback: AppSettingsSnapshot.defaultAiAttachmentMaxImageRawBytes,
      min: AppSettingsSnapshot.minAiAttachmentMaxImageRawBytes,
      max: AppSettingsSnapshot.maxAiAttachmentMaxImageRawBytes,
    );
    final aiChatMaxStreamLineBufferBytes = clampedIntFromValue(
      json['ai_chat_max_stream_line_buffer_bytes'],
      fallback: AppSettingsSnapshot.defaultAiChatMaxStreamLineBufferBytes,
      min: AppSettingsSnapshot.minAiChatMaxStreamLineBufferBytes,
      max: AppSettingsSnapshot.maxAiChatMaxStreamLineBufferBytes,
    );
    final aiFallbackTitleMaxCharacters = clampedIntFromValue(
      json['ai_fallback_title_max_characters'],
      fallback: AppSettingsSnapshot.defaultAiFallbackTitleMaxCharacters,
      min: AppSettingsSnapshot.minAiFallbackTitleMaxCharacters,
      max: AppSettingsSnapshot.maxAiFallbackTitleMaxCharacters,
    );
    final aiGeneratedTitleMaxCharacters = clampedIntFromValue(
      json['ai_generated_title_max_characters'],
      fallback: AppSettingsSnapshot.defaultAiGeneratedTitleMaxCharacters,
      min: AppSettingsSnapshot.minAiGeneratedTitleMaxCharacters,
      max: AppSettingsSnapshot.maxAiGeneratedTitleMaxCharacters,
    );
    final aiAutoTitleMaxRetryCount = clampedIntFromValue(
      json['ai_auto_title_max_retry_count'],
      fallback: AppSettingsSnapshot.defaultAiAutoTitleMaxRetryCount,
      min: AppSettingsSnapshot.minAiAutoTitleMaxRetryCount,
      max: AppSettingsSnapshot.maxAiAutoTitleMaxRetryCount,
    );
    final aiMinimumMeaningfulTitleCharacters = clampedIntFromValue(
      json['ai_minimum_meaningful_title_characters'],
      fallback: AppSettingsSnapshot.defaultAiMinimumMeaningfulTitleCharacters,
      min: AppSettingsSnapshot.minAiMinimumMeaningfulTitleCharacters,
      max: AppSettingsSnapshot.maxAiMinimumMeaningfulTitleCharacters,
    );
    final aiMinimumMeaningfulLatinTitleWords = clampedIntFromValue(
      json['ai_minimum_meaningful_latin_title_words'],
      fallback: AppSettingsSnapshot.defaultAiMinimumMeaningfulLatinTitleWords,
      min: AppSettingsSnapshot.minAiMinimumMeaningfulLatinTitleWords,
      max: AppSettingsSnapshot.maxAiMinimumMeaningfulLatinTitleWords,
    );
    final aiMaxSkillContentLength = clampedIntFromValue(
      json['ai_max_skill_content_length'],
      fallback: AppSettingsSnapshot.defaultAiMaxSkillContentLength,
      min: AppSettingsSnapshot.minAiMaxSkillContentLength,
      max: AppSettingsSnapshot.maxAiMaxSkillContentLength,
    );
    final aiMaxWorkspaceDocumentCharacters = clampedIntFromValue(
      json['ai_max_workspace_document_characters'],
      fallback: AppSettingsSnapshot.defaultAiMaxWorkspaceDocumentCharacters,
      min: AppSettingsSnapshot.minAiMaxWorkspaceDocumentCharacters,
      max: AppSettingsSnapshot.maxAiMaxWorkspaceDocumentCharacters,
    );
    final aiImageSizeLimitBytes = clampedIntFromValue(
      json['ai_image_size_limit_bytes'],
      fallback: AppSettingsSnapshot.defaultAiImageSizeLimitBytes,
      min: AppSettingsSnapshot.minAiImageSizeLimitBytes,
      max: AppSettingsSnapshot.maxAiImageSizeLimitBytes,
    );
    final aiTranslationSettings = AiTranslationSettings.fromJson(
      json['ai_translation'],
    );
    final aiTtsSettings = AiTtsSettings.fromJson(json['ai_tts']);
    final aiWriteCommandConfirmationEnabled = boolFromValue(
      json['ai_write_command_confirmation_enabled'],
      defaultValue: true,
    );

    final aiAllowCommandRules = _readSettingsObjectList(
      json['ai_allow_command_rules'],
      AiAllowCommandRule.fromJson,
      '解析 AI 允许命令规则项',
    );
    final aiDenyCommandRules = _readSettingsObjectList(
      json['ai_deny_command_rules'],
      AiDenyCommandRule.fromJson,
      '解析 AI 禁止命令规则项',
    );

    final rawSandboxSettings = json['ai_sandbox'];
    final aiSandboxSettings = AiSandboxSettings.fromJson(rawSandboxSettings);

    // 会话超时设置。
    final aiConnectTimeoutSeconds =
        AppSettingsSnapshot.aiConnectTimeoutSecondsFromValue(
          json['ai_connect_timeout_seconds'],
        );
    final aiResponseTimeoutSeconds =
        AppSettingsSnapshot.aiResponseTimeoutSecondsFromValue(
          json['ai_response_timeout_seconds'],
        );
    final aiStreamIdleTimeoutSeconds =
        AppSettingsSnapshot.aiStreamIdleTimeoutSecondsFromValue(
          json['ai_stream_idle_timeout_seconds'],
        );
    final aiStreamMaxCharsPerSecond =
        AppSettingsSnapshot.aiStreamMaxCharsPerSecondFromValue(
          json['ai_stream_max_chars_per_second'],
        );
    final aiStreamMaxMessageCardsPerSecond =
        AppSettingsSnapshot.aiStreamMaxMessageCardsPerSecondFromValue(
          json['ai_stream_max_message_cards_per_second'],
        );
    // v3 schema 起，按线程模板覆盖节流参数已下线。
    // 旧设置记录仍可能携带 `ai_stream_throttle_template_overrides` 字段
    //（v1/v2 残留），这里完全忽略：不再读、不再透传给快照，
    // 写入路径也不会再写出。任何形状的旧值（Map/null/异常类型）都
    // 必须被静默丢弃，保证 `load()` 不抛。
    final aiStreamThrottleEnabled = boolFromValue(
      json['ai_stream_throttle_enabled'],
      defaultValue: AppSettingsSnapshot.defaultAiStreamThrottleEnabled,
    );
    final aiStreamThrottleAutoMode = boolFromValue(
      json['ai_stream_throttle_auto_mode'],
    );
    final aiStreamThrottleDurationSeconds =
        AppSettingsSnapshot.aiStreamThrottleDurationSecondsFromValue(
          json['ai_stream_throttle_duration_seconds'],
        );
    final aiStreamThrottleCloudSyncProvider =
        '${json['ai_stream_throttle_cloud_sync_provider'] ?? AppSettingsSnapshot.defaultAiStreamThrottleCloudSyncProvider}'
            .trim();
    final aiStreamThrottleCloudSyncEndpoint =
        '${json['ai_stream_throttle_cloud_sync_endpoint'] ?? AppSettingsSnapshot.defaultAiStreamThrottleCloudSyncEndpoint}'
            .trim();
    final aiStreamThrottleCloudSyncToken =
        '${json['ai_stream_throttle_cloud_sync_token'] ?? AppSettingsSnapshot.defaultAiStreamThrottleCloudSyncToken}'
            .trim();
    final aiStreamThrottleConfigUpdatedAtMs = nonNegativeIntFromValue(
      json['ai_stream_throttle_config_updated_at_ms'],
      fallback: AppSettingsSnapshot.defaultAiStreamThrottleConfigUpdatedAtMs,
    );
    final aiAutoTitleEnabled = boolFromValue(
      json['ai_auto_title_enabled'],
      defaultValue: true,
    );
    final aiAutoTitleFetchMode = AiAutoTitleFetchMode.fromStorage(
      '${json['ai_auto_title_fetch_mode'] ?? ''}',
    );
    final rawDefaultSessionMode = '${json['ai_default_session_mode'] ?? ''}'
        .trim();
    final aiDefaultSessionMode = rawDefaultSessionMode == 'plan'
        ? 'plan'
        : 'chat';
    final aiDefaultFullAccessPermission = boolFromValue(
      json['ai_default_full_access_permission'],
    );

    // AI 模型。
    final aiModels = <AiModelConfig>[];
    for (final item in stringKeyedMapListFromValueOrJsonText(
      json['ai_models'],
    )) {
      try {
        final model = AiModelConfig.fromJson(item);
        if (model.id.trim().isNotEmpty && isValidHttpUrl(model.baseUrl)) {
          aiModels.add(model);
        }
      } catch (error, stack) {
        silentLog('settings_store', '解析 AI 模型设置项', error, stack);
      }
    }

    var selectedAiModelId = '${json['selected_ai_model_id'] ?? ''}'.trim();
    if (selectedAiModelId.isNotEmpty &&
        !aiModels.any((item) => item.id == selectedAiModelId)) {
      selectedAiModelId = aiModels.isEmpty ? '' : aiModels.first.id;
    }

    // 最近模型选择。
    final recentModelSelections = <RecentModelSelection>[];
    for (final item in stringKeyedMapListFromValueOrJsonText(
      json['recent_model_selections'],
    )) {
      try {
        final entry = RecentModelSelection.fromJson(item);
        if (entry.configId.isNotEmpty && entry.modelId.isNotEmpty) {
          recentModelSelections.add(entry);
        }
      } catch (error, stack) {
        silentLog('settings_store', '解析最近模型选择项', error, stack);
      }
    }

    // 快捷键绑定。
    final rawBindings = json['shortcut_bindings'];
    var shortcutBindings = defaultOpenHandShortcutBindings();
    if (rawBindings is Map) {
      final parsed = <OpenHandShortcutAction, List<int>>{};
      for (final entry in rawBindings.entries) {
        final action = openHandShortcutActionFromStorageKey('${entry.key}');
        if (action == null) continue;
        final value = entry.value;
        if (value is! List) continue;
        final normalized = normalizeShortcutKeyIds(
          value.whereType<num>().map((item) => item.toInt()),
        );
        if (isValidShortcutBinding(normalized)) {
          parsed[action] = normalized;
        }
      }
      shortcutBindings = <OpenHandShortcutAction, List<int>>{
        ...defaultOpenHandShortcutBindings(),
        ...parsed,
      };
    }

    // 动画设置。
    final dialogAnimationSettings = _animationSettingsFromStorage(
      json,
      'dialog_animation_settings',
      fallback: OpenHandMotionDefaults.dialog,
      schemaVersion: schemaVersion,
      legacyDefaults: const <DialogAnimationSettings>[
        DialogAnimationSettings.legacyFadeScale,
        DialogAnimationSettings(
          entranceStyle: DialogAnimationStyle.springScale,
        ),
      ],
    );
    final menuAnimationSettings = _animationSettingsFromStorage(
      json,
      'menu_animation_settings',
      fallback: OpenHandMotionDefaults.menu,
      schemaVersion: schemaVersion,
      legacyDefaults: const <DialogAnimationSettings>[
        DialogAnimationSettings.legacyFadeScale,
        DialogAnimationSettings(
          entranceStyle: DialogAnimationStyle.springScale,
          durationMs: 260,
        ),
      ],
    );
    final pageAnimationSettings = _animationSettingsFromStorage(
      json,
      'page_animation_settings',
      fallback: OpenHandMotionDefaults.page,
      schemaVersion: schemaVersion,
      replaceDisabledWithFallback: true,
      legacyDefaults: const <DialogAnimationSettings>[
        DialogAnimationSettings(
          entranceStyle: DialogAnimationStyle.fade,
          exitStyle: DialogAnimationStyle.fade,
          durationMs: 240,
        ),
        DialogAnimationSettings(
          entranceStyle: DialogAnimationStyle.fade,
          exitStyle: DialogAnimationStyle.fade,
          durationMs: 420,
          curve: DialogAnimationCurve.easeInOutCubicEmphasized,
        ),
      ],
    );
    final panelAnimationSettings = _animationSettingsFromStorage(
      json,
      'panel_animation_settings',
      fallback: OpenHandMotionDefaults.panel,
      schemaVersion: schemaVersion,
      replaceDisabledWithFallback: true,
      legacyDefaults: const <DialogAnimationSettings>[
        DialogAnimationSettings.legacyFadeScale,
      ],
    );
    final chipAnimationSettings = _animationSettingsFromStorage(
      json,
      'chip_animation_settings',
      fallback: OpenHandMotionDefaults.chip,
      schemaVersion: schemaVersion,
    );
    final listItemAnimationSettings = _animationSettingsFromStorage(
      json,
      'list_item_animation_settings',
      fallback: OpenHandMotionDefaults.listItem,
      schemaVersion: schemaVersion,
    );
    final nativeAudioPlaybackSettings = NativeAudioPlaybackSettings.fromJson(
      json['native_audio_playback'],
    );

    // 内置工具配置。
    final rawBuiltinToolConfigs = json['builtin_tool_configs'];
    var builtinToolConfigs = AiBuiltinToolConfig.defaults();
    if (rawBuiltinToolConfigs is List) {
      final parsed = <AiBuiltinToolConfig>[];
      for (final item in rawBuiltinToolConfigs) {
        if (optionalStringKeyedMapFromValueOrJsonText(item) == null) {
          continue;
        }
        try {
          parsed.add(AiBuiltinToolConfig.fromJson(item));
        } catch (error, stack) {
          silentLog('settings_store', '解析内置工具配置项', error, stack);
        }
      }
      if (parsed.isNotEmpty) {
        if (AiBuiltinToolConfig.looksLikeLegacyEagerDefaults(parsed) ||
            AiBuiltinToolConfig.looksLikeLegacyBuiltinOrderingDefaults(
              parsed,
            )) {
          builtinToolConfigs = AiBuiltinToolConfig.defaults();
        } else {
          // 保留已解析条目，并为新增工具类型补齐默认配置。
          final parsedKinds = parsed.map((c) => c.kind).toSet();
          final defaults = AiBuiltinToolConfig.defaults();
          for (final def in defaults) {
            if (!parsedKinds.contains(def.kind)) {
              parsed.add(def);
            }
          }
          builtinToolConfigs = parsed;
        }
      }
    }

    final telemetryDebugEnabled = boolFromValue(
      json['telemetry_debug_enabled'],
    );
    final telemetryCaptureRawPayload = boolFromValue(
      json['telemetry_capture_raw_payload'],
      defaultValue: true,
    );
    final telemetryCaptureEnvironment = boolFromValue(
      json['telemetry_capture_environment'],
    );
    final telemetryMaxPayloadChars = clampedIntFromValue(
      json['telemetry_max_payload_chars'],
      fallback: AppSettingsSnapshot.defaultTelemetryMaxPayloadChars,
      min: AppSettingsSnapshot.minTelemetryMaxPayloadChars,
      max: AppSettingsSnapshot.maxTelemetryMaxPayloadChars,
    );

    final selfLearningEnabled = boolFromValue(
      json['self_learning_enabled'],
      defaultValue: true,
    );
    final selfLearningConcurrency = clampedIntFromValue(
      json['self_learning_concurrency'],
      fallback: AppSettingsSnapshot.defaultSelfLearningConcurrency,
      min: AppSettingsSnapshot.minSelfLearningConcurrency,
      max: AppSettingsSnapshot.maxSelfLearningConcurrency,
    );

    final selfLearningStreamFlushIntervalMs = clampedIntFromValue(
      json['self_learning_stream_flush_interval_ms'],
      fallback: AppSettingsSnapshot.defaultSelfLearningStreamFlushIntervalMs,
      min: AppSettingsSnapshot.minSelfLearningStreamFlushIntervalMs,
      max: AppSettingsSnapshot.maxSelfLearningStreamFlushIntervalMs,
    );

    final showSelfLearningMessages = boolFromValue(
      json['show_self_learning_messages'],
      defaultValue: true,
    );

    final cronAutoCleanupEnabled = boolFromValue(
      json['cron_auto_cleanup_enabled'],
      defaultValue: true,
    );
    final cronAutoCleanupRetentionDays = clampedIntFromValue(
      json['cron_auto_cleanup_retention_days'],
      fallback: AppSettingsSnapshot.defaultCronAutoCleanupRetentionDays,
      min: AppSettingsSnapshot.minCronAutoCleanupRetentionDays,
      max: AppSettingsSnapshot.maxCronAutoCleanupRetentionDays,
    );

    final harnessToolSearchHistoryMaxPhases = clampedIntFromValue(
      json['harness_tool_search_history_max_phases'],
      fallback: AppSettingsSnapshot.defaultHarnessToolSearchHistoryMaxPhases,
      min: AppSettingsSnapshot.minHarnessToolSearchHistoryMaxPhases,
      max: AppSettingsSnapshot.maxHarnessToolSearchHistoryMaxPhases,
    );

    final toolSearchReplayCancelWindowSeconds = clampedIntFromValue(
      json['tool_search_replay_cancel_window_seconds'],
      fallback: AppSettingsSnapshot.defaultToolSearchReplayCancelWindowSeconds,
      min: AppSettingsSnapshot.minToolSearchReplayCancelWindowSeconds,
      max: AppSettingsSnapshot.maxToolSearchReplayCancelWindowSeconds,
    );

    final reduceMotion = boolFromValue(json['reduce_motion']);

    final proxySettings = AppProxySettings.fromJson(json['proxy']);

    final subprocessGracefulShutdownMs =
        AppSettingsSnapshot.subprocessGracefulShutdownMsFromValue(
          json['subprocess_graceful_shutdown_ms'],
        );
    final bashOutputMaxBytes = AppSettingsSnapshot.bashOutputMaxBytesFromValue(
      json['bash_output_max_bytes'],
    );
    final maxConcurrentTools = AppSettingsSnapshot.maxConcurrentToolsFromValue(
      json['max_concurrent_tools'],
    );

    return AppSettingsSnapshot(
      themeMode: themeMode,
      themePreset: themePreset,
      language: language,
      skillsStoragePath: skillsStoragePath,
      mcpEnabled: mcpEnabled,
      mcpServersFilePath: mcpServersFilePath,
      mcpLazyLoadingMode: mcpLazyLoadingMode,
      mcpLazyLoadingThresholdTokens: mcpLazyLoadingThresholdTokens,
      builtinToolLazyLoadingMode: builtinToolLazyLoadingMode,
      mcpStdioMirrorMode: mcpStdioMirrorMode,
      mcpAutoProbeConcurrency: mcpAutoProbeConcurrency,
      mcpKeywordIndexUpdateMode: mcpKeywordIndexUpdateMode,
      mcpKeywordIndexIntervalValue: mcpKeywordIndexIntervalValue,
      mcpKeywordIndexIntervalUnit: mcpKeywordIndexIntervalUnit,
      mcpKeywordIndexScheduledTimeOfDay: mcpKeywordIndexScheduledTimeOfDay,
      memoryEnabled: memoryEnabled,
      userMemoryFilePath: userMemoryFilePath,
      editorWordWrap: editorWordWrap,
      editorIndentSpaces: editorIndentSpaces,
      editorCodeTheme: editorCodeTheme,
      editorLspSettings: editorLspSettings,
      editorShortcutBindings: editorShortcutBindings,
      aiMessageCompressionThresholdChars: aiMessageCompressionThresholdChars,
      aiToolResultCompressionThresholdChars:
          aiToolResultCompressionThresholdChars,
      aiToolResultCompressionEnabled: aiToolResultCompressionEnabled,
      aiMicroCompressionEnabled: aiMicroCompressionEnabled,
      aiMessageContentFormat: aiMessageContentFormat,
      aiHtmlRenderFallback: aiHtmlRenderFallback,
      aiHtmlContentRichness: aiHtmlContentRichness,
      aiToolResultCompressionHeadTailWindowChars:
          aiToolResultCompressionHeadTailWindowChars,
      aiToolResultCompressionMaxPathHits: aiToolResultCompressionMaxPathHits,
      aiInputCacheEnabled: aiInputCacheEnabled,
      aiInputCacheUpdateMode: aiInputCacheUpdateMode,
      aiInputCacheUpdateInterval: aiInputCacheUpdateInterval,
      aiInputCacheBreakpointCount: aiInputCacheBreakpointCount,
      aiInputCacheBreakpointPositions: aiInputCacheBreakpointPositions,
      aiBudgetUsdPerSession: aiBudgetUsdPerSession,
      aiWriteToolSummaryMaxChars: aiWriteToolSummaryMaxChars,
      aiSingleRoundToolCallLimit: aiSingleRoundToolCallLimit,
      aiSequentialToolRoundLimit: aiSequentialToolRoundLimit,
      aiMaxRecentErrors: aiMaxRecentErrors,
      aiMaxPlanHistoryEntries: aiMaxPlanHistoryEntries,
      aiMaxTruncationContinuations: aiMaxTruncationContinuations,
      aiEstimatedCharactersPerToken: aiEstimatedCharactersPerToken,
      aiMaxToolOutputChars: aiMaxToolOutputChars,
      aiWriteConfirmationTimeoutMs: aiWriteConfirmationTimeoutMs,
      aiFastPathWriteAnalysisThreshold: aiFastPathWriteAnalysisThreshold,
      aiMaxHookTextCharacters: aiMaxHookTextCharacters,
      aiAttachmentMaxInlineImageDimension: aiAttachmentMaxInlineImageDimension,
      aiAttachmentMaxTextRawBytes: aiAttachmentMaxTextRawBytes,
      aiAttachmentMaxPdfRawBytes: aiAttachmentMaxPdfRawBytes,
      aiAttachmentMaxImageRawBytes: aiAttachmentMaxImageRawBytes,
      aiChatMaxStreamLineBufferBytes: aiChatMaxStreamLineBufferBytes,
      aiFallbackTitleMaxCharacters: aiFallbackTitleMaxCharacters,
      aiGeneratedTitleMaxCharacters: aiGeneratedTitleMaxCharacters,
      aiAutoTitleMaxRetryCount: aiAutoTitleMaxRetryCount,
      aiMinimumMeaningfulTitleCharacters: aiMinimumMeaningfulTitleCharacters,
      aiMinimumMeaningfulLatinTitleWords: aiMinimumMeaningfulLatinTitleWords,
      aiMaxSkillContentLength: aiMaxSkillContentLength,
      aiMaxWorkspaceDocumentCharacters: aiMaxWorkspaceDocumentCharacters,
      aiImageSizeLimitBytes: aiImageSizeLimitBytes,
      aiTranslationSettings: aiTranslationSettings,
      aiTtsSettings: aiTtsSettings,
      aiWriteCommandConfirmationEnabled: aiWriteCommandConfirmationEnabled,
      aiAllowCommandRules: aiAllowCommandRules,
      aiDenyCommandRules: aiDenyCommandRules,
      aiSandboxSettings: aiSandboxSettings,
      aiConnectTimeoutSeconds: aiConnectTimeoutSeconds,
      aiResponseTimeoutSeconds: aiResponseTimeoutSeconds,
      aiStreamIdleTimeoutSeconds: aiStreamIdleTimeoutSeconds,
      aiStreamMaxCharsPerSecond: aiStreamMaxCharsPerSecond,
      aiStreamMaxMessageCardsPerSecond: aiStreamMaxMessageCardsPerSecond,
      aiStreamThrottleEnabled: aiStreamThrottleEnabled,
      aiStreamThrottleAutoMode: aiStreamThrottleAutoMode,
      aiStreamThrottleDurationSeconds: aiStreamThrottleDurationSeconds,
      aiStreamThrottleCloudSyncProvider: aiStreamThrottleCloudSyncProvider,
      aiStreamThrottleCloudSyncEndpoint: aiStreamThrottleCloudSyncEndpoint,
      aiStreamThrottleCloudSyncToken: aiStreamThrottleCloudSyncToken,
      aiStreamThrottleConfigUpdatedAtMs: aiStreamThrottleConfigUpdatedAtMs,
      // 模板级节流覆盖已从设置模型移除；会话覆盖由会话元数据管理。
      aiAutoTitleEnabled: aiAutoTitleEnabled,
      aiAutoTitleFetchMode: aiAutoTitleFetchMode,
      aiDefaultSessionMode: aiDefaultSessionMode,
      aiDefaultFullAccessPermission: aiDefaultFullAccessPermission,
      aiModels: aiModels,
      selectedAiModelId: selectedAiModelId.isEmpty ? null : selectedAiModelId,
      recentModelSelections: recentModelSelections,
      shortcutBindings: shortcutBindings,
      dialogAnimationSettings: dialogAnimationSettings,
      menuAnimationSettings: menuAnimationSettings,
      pageAnimationSettings: pageAnimationSettings,
      panelAnimationSettings: panelAnimationSettings,
      chipAnimationSettings: chipAnimationSettings,
      listItemAnimationSettings: listItemAnimationSettings,
      nativeAudioPlaybackSettings: nativeAudioPlaybackSettings,
      builtinToolConfigs: builtinToolConfigs,
      telemetryDebugEnabled: telemetryDebugEnabled,
      telemetryCaptureRawPayload: telemetryCaptureRawPayload,
      telemetryCaptureEnvironment: telemetryCaptureEnvironment,
      telemetryMaxPayloadChars: telemetryMaxPayloadChars,
      selfLearningEnabled: selfLearningEnabled,
      selfLearningConcurrency: selfLearningConcurrency,
      selfLearningStreamFlushIntervalMs: selfLearningStreamFlushIntervalMs,
      showSelfLearningMessages: showSelfLearningMessages,
      cronAutoCleanupEnabled: cronAutoCleanupEnabled,
      cronAutoCleanupRetentionDays: cronAutoCleanupRetentionDays,
      harnessToolSearchHistoryMaxPhases: harnessToolSearchHistoryMaxPhases,
      toolSearchReplayCancelWindowSeconds: toolSearchReplayCancelWindowSeconds,
      reduceMotion: reduceMotion,
      proxySettings: proxySettings,
      subprocessGracefulShutdownMs: subprocessGracefulShutdownMs,
      bashOutputMaxBytes: bashOutputMaxBytes,
      maxConcurrentTools: maxConcurrentTools,
    );
  }
}

List<T> _readSettingsObjectList<T>(
  Object? raw,
  T Function(Object? raw) parse,
  String logAction,
) {
  final out = <T>[];
  for (final item in stringKeyedMapListFromValueOrJsonText(raw)) {
    try {
      out.add(parse(item));
    } catch (error, stack) {
      silentLog('settings_store', logAction, error, stack);
    }
  }
  return out;
}

DialogAnimationSettings _dialogAnimationFromValue(
  Object? value, {
  required DialogAnimationSettings fallback,
}) {
  if (value is! Map) return fallback;
  return DialogAnimationSettings.fromJson(
    stringKeyedMapFromValue(value),
    fallbackDurationMs: fallback.configuredDurationMs,
  );
}

DialogAnimationSettings _animationSettingsFromStorage(
  Map<String, Object?> json,
  String key, {
  required DialogAnimationSettings fallback,
  required int schemaVersion,
  Iterable<DialogAnimationSettings> legacyDefaults =
      const <DialogAnimationSettings>[],
  bool replaceDisabledWithFallback = false,
}) {
  final settings = _dialogAnimationFromValue(json[key], fallback: fallback);
  if (schemaVersion < SettingsStore._currentSchemaVersion) {
    if (replaceDisabledWithFallback && settings.disablesAnimation) {
      return fallback;
    }
    for (final legacyDefault in legacyDefaults) {
      if (settings == legacyDefault) {
        return fallback;
      }
    }
  }
  return settings;
}

ThemeMode _themeModeFromStorage(String? value) {
  return switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

String _themeModeToStorage(ThemeMode value) {
  return switch (value) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}
