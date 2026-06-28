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

enum SettingsPersistenceIssueKind {
  recoveredInvalidFile,
  sanitizedInvalidContent,
  saveFailed,
}

class SettingsPersistenceIssue {
  const SettingsPersistenceIssue({
    required this.kind,
    required this.filePath,
    this.detail,
  });

  final SettingsPersistenceIssueKind kind;
  final String filePath;
  final String? detail;
}

class SettingsLoadResult {
  const SettingsLoadResult({required this.snapshot, this.issue});

  final AppSettingsSnapshot snapshot;
  final SettingsPersistenceIssue? issue;
}

class SettingsStore {
  SettingsStore();

  static const String _dbSettingsKey = 'app_settings_json';

  /// Retained for backward compatibility with controllers that expose a path.
  String get settingsFilePath => 'db://app_settings';

  Database get _db => DatabaseService.instance.database;

  // ---------------------------------------------------------------------------
  // Primary load / save (DB-backed)
  // ---------------------------------------------------------------------------

  Future<SettingsLoadResult> load() async {
    try {
      final rows = await _db.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: <Object?>[_dbSettingsKey],
        limit: 1,
      );

      if (rows.isNotEmpty) {
        final jsonStr = rows.first['value'] as String?;
        if (jsonStr != null && jsonStr.isNotEmpty) {
          try {
            final decoded = jsonDecode(jsonStr);
            if (decoded is Map) {
              final snapshot = _snapshotFromJson(
                Map<String, Object?>.from(decoded),
              );
              return SettingsLoadResult(snapshot: snapshot);
            }
          } catch (error, stack) {
            silentLog('settings_store', 'decode db settings', error, stack);
            // DB data is corrupt; fall through to defaults.
          }
        }
      }

      // No settings in DB yet — use defaults and persist them.
      final snapshot = AppSettingsSnapshot.defaults();
      try {
        await save(snapshot);
        return SettingsLoadResult(snapshot: snapshot);
      } catch (error) {
        return SettingsLoadResult(
          snapshot: snapshot,
          issue: SettingsPersistenceIssue(
            kind: SettingsPersistenceIssueKind.saveFailed,
            filePath: 'db://app_settings',
            detail: '$error',
          ),
        );
      }
    } catch (error) {
      return SettingsLoadResult(
        snapshot: AppSettingsSnapshot.defaults(),
        issue: SettingsPersistenceIssue(
          kind: SettingsPersistenceIssueKind.saveFailed,
          filePath: 'db://app_settings',
          detail: '$error',
        ),
      );
    }
  }

  Future<void> save(AppSettingsSnapshot snapshot) async {
    final jsonStr = jsonEncode(_snapshotToJson(snapshot));
    await _db.insert('app_settings', <String, Object?>{
      'key': _dbSettingsKey,
      'value': jsonStr,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------------------
  // JSON serialization for AppSettingsSnapshot
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _snapshotToJson(AppSettingsSnapshot snapshot) {
    return <String, Object?>{
      'version': 4,
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
      // 2026-05-22 — v3 schema 起，按线程模板覆盖节流参数已下线，
      // 持久化层不再写出 `ai_stream_throttle_template_overrides`；
      // read 路径会静默丢弃任何老 doc 上的同名字段。
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
      'hardness_tool_search_history_max_phases':
          snapshot.hardnessToolSearchHistoryMaxPhases,
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
      // v2 wrote the old false default into DB for many users. Treat that
      // value as legacy default state once so Claude-compatible threads get
      // explicit prompt-cache breakpoints after upgrade; v3 false remains a
      // deliberate opt-out.
      return AppSettingsSnapshot.defaultAiInputCacheEnabled;
    }
    return persisted;
  }

  static bool _migrateAiMicroCompressionEnabled({
    required bool persisted,
    required int schemaVersion,
  }) {
    if (schemaVersion < 4 && !persisted) {
      // Earlier schema versions wrote the old false default for most users.
      // Treat that value as legacy default state once so consumed tool
      // results stop bloating every follow-up prompt after upgrade; v4 false
      // remains an explicit opt-out.
      return AppSettingsSnapshot.defaultAiMicroCompressionEnabled;
    }
    return persisted;
  }

  static AppSettingsSnapshot _snapshotFromJson(Map<String, Object?> json) {
    final schemaVersion = json['version'] is int ? json['version'] as int : 0;
    final themeMode = _themeModeFromStorage('${json['theme_mode'] ?? ''}');
    final rawThemePreset = '${json['theme_preset'] ?? ''}'.trim();
    final themePreset = OpenHandThemePreset.fromStorage(rawThemePreset);
    final language = appLanguageFromStorage('${json['language'] ?? ''}');

    final skillsStoragePath = OpenHandPaths.normalizeUserPath(
      '${json['skills_storage_path'] ?? ''}',
    );
    final mcpEnabled = json['mcp_enabled'] is bool
        ? json['mcp_enabled'] as bool
        : true;
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
    final mcpLazyLoadingThresholdTokens =
        loadedMcpLazyLoadingThresholdTokens ==
            AppSettingsSnapshot.legacyMcpLazyLoadingThresholdTokens
        ? AppSettingsSnapshot.defaultMcpLazyLoadingThresholdTokens
        : loadedMcpLazyLoadingThresholdTokens;
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
    final memoryEnabled = json['memory_enabled'] is bool
        ? json['memory_enabled'] as bool
        : true;
    final userMemoryFilePath = OpenHandPaths.normalizePath(
      '${json['user_memory_file_path'] ?? ''}',
      defaultPath: OpenHandPaths.defaultUserMemoryFilePath(),
    );
    final editorWordWrap = json['editor_word_wrap'] is bool
        ? json['editor_word_wrap'] as bool
        : true;
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
        if (entry.value is! Map) {
          continue;
        }
        try {
          editorLspSettings['${entry.key}'
              .trim()] = AiLspLanguageSettings.fromJson(
            Map<String, Object?>.from(entry.value as Map),
          );
        } catch (error, stack) {
          silentLog(
            'settings_store',
            'parse editor_lsp_settings entry',
            error,
            stack,
          );
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
        json['ai_message_compression_threshold_chars'] is int
        ? AppSettingsSnapshot.normalizeAiMessageCompressionThresholdChars(
            json['ai_message_compression_threshold_chars'] as int,
          )
        : AppSettingsSnapshot.defaultAiMessageCompressionThresholdChars;
    final aiToolResultCompressionThresholdChars =
        json['ai_tool_result_compression_threshold_chars'] is int
        ? AppSettingsSnapshot.normalizeAiToolResultCompressionThresholdChars(
            json['ai_tool_result_compression_threshold_chars'] as int,
          )
        : AppSettingsSnapshot.defaultAiToolResultCompressionThresholdChars;
    final aiToolResultCompressionEnabled =
        json['ai_tool_result_compression_enabled'] is bool
        ? json['ai_tool_result_compression_enabled'] as bool
        : true;
    final aiMicroCompressionEnabled =
        json['ai_micro_compression_enabled'] is bool
        ? _migrateAiMicroCompressionEnabled(
            persisted: json['ai_micro_compression_enabled'] as bool,
            schemaVersion: schemaVersion,
          )
        : AppSettingsSnapshot.defaultAiMicroCompressionEnabled;
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
    final aiInputCacheEnabled = json['ai_input_cache_enabled'] is bool
        ? _migrateAiInputCacheEnabled(
            persisted: json['ai_input_cache_enabled'] as bool,
            schemaVersion: schemaVersion,
          )
        : AppSettingsSnapshot.defaultAiInputCacheEnabled;
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
    // 2026-05-04 — 用户自定义前 N-1 个静态缓存点位置（百分比 0..1，升序）。
    // JSON 形如 [0.25, 0.5, 0.75]；非法元素直接忽略，越界 clamp 至 [0,1]。
    final List<double> aiInputCacheBreakpointPositions = () {
      final raw = json['ai_input_cache_breakpoint_positions'];
      if (raw is! List) {
        return AppSettingsSnapshot.defaultAiInputCacheBreakpointPositions;
      }
      final parsed = <double>[];
      for (final entry in raw) {
        final v = optionalDoubleFromValue(entry);
        if (v == null) continue;
        parsed.add(v.clamp(0.0, 1.0));
      }
      parsed.sort();
      return List<double>.unmodifiable(parsed);
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
        json['ai_single_round_tool_call_limit'] is int &&
            (json['ai_single_round_tool_call_limit'] as int) > 0
        ? json['ai_single_round_tool_call_limit'] as int
        : AppSettingsSnapshot.defaultAiSingleRoundToolCallLimit;
    final aiSequentialToolRoundLimit =
        json['ai_sequential_tool_round_limit'] is int &&
            (json['ai_sequential_tool_round_limit'] as int) > 0
        ? json['ai_sequential_tool_round_limit'] as int
        : AppSettingsSnapshot.defaultAiSequentialToolRoundLimit;
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
    final aiMaxToolOutputChars = clampedIntFromValue(
      json['ai_max_tool_output_chars'],
      fallback: AppSettingsSnapshot.defaultAiMaxToolOutputChars,
      min: AppSettingsSnapshot.minAiMaxToolOutputChars,
      max: AppSettingsSnapshot.maxAiMaxToolOutputChars,
    );
    final aiWriteConfirmationTimeoutMs = clampedIntFromValue(
      json['ai_write_confirmation_timeout_ms'],
      fallback: AppSettingsSnapshot.defaultAiWriteConfirmationTimeoutMs,
      min: AppSettingsSnapshot.minAiWriteConfirmationTimeoutMs,
      max: AppSettingsSnapshot.maxAiWriteConfirmationTimeoutMs,
    );
    final aiFastPathWriteAnalysisThreshold = clampedIntFromValue(
      json['ai_fast_path_write_analysis_threshold'],
      fallback: AppSettingsSnapshot.defaultAiFastPathWriteAnalysisThreshold,
      min: AppSettingsSnapshot.minAiFastPathWriteAnalysisThreshold,
      max: AppSettingsSnapshot.maxAiFastPathWriteAnalysisThreshold,
    );
    final aiMaxHookTextCharacters = clampedIntFromValue(
      json['ai_max_hook_text_characters'],
      fallback: AppSettingsSnapshot.defaultAiMaxHookTextCharacters,
      min: AppSettingsSnapshot.minAiMaxHookTextCharacters,
      max: AppSettingsSnapshot.maxAiMaxHookTextCharacters,
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
    final aiWriteCommandConfirmationEnabled =
        json['ai_write_command_confirmation_enabled'] is bool
        ? json['ai_write_command_confirmation_enabled'] as bool
        : true;

    // Allow command rules.
    final rawAllowRules = json['ai_allow_command_rules'];
    final aiAllowCommandRules = <AiAllowCommandRule>[];
    if (rawAllowRules is List) {
      for (final item in rawAllowRules) {
        if (item is Map) {
          try {
            aiAllowCommandRules.add(
              AiAllowCommandRule.fromJson(Map<String, Object?>.from(item)),
            );
          } catch (error, stack) {
            silentLog(
              'settings_store',
              'parse ai_allow_command_rules entry',
              error,
              stack,
            );
          }
        }
      }
    }

    // Deny command rules.
    final rawDenyRules = json['ai_deny_command_rules'];
    final aiDenyCommandRules = <AiDenyCommandRule>[];
    if (rawDenyRules is List) {
      for (final item in rawDenyRules) {
        if (item is Map) {
          try {
            aiDenyCommandRules.add(
              AiDenyCommandRule.fromJson(Map<String, Object?>.from(item)),
            );
          } catch (error, stack) {
            silentLog(
              'settings_store',
              'parse ai_deny_command_rules entry',
              error,
              stack,
            );
          }
        }
      }
    }

    final rawSandboxSettings = json['ai_sandbox'];
    final aiSandboxSettings = AiSandboxSettings.fromJson(rawSandboxSettings);

    // Session timeout settings.
    final aiConnectTimeoutSeconds = clampedIntFromValue(
      json['ai_connect_timeout_seconds'],
      fallback: AppSettingsSnapshot.defaultAiConnectTimeoutSeconds,
      min: AppSettingsSnapshot.minAiConnectTimeoutSeconds,
      max: AppSettingsSnapshot.maxAiConnectTimeoutSeconds,
    );
    final aiResponseTimeoutSeconds = clampedIntFromValue(
      json['ai_response_timeout_seconds'],
      fallback: AppSettingsSnapshot.defaultAiResponseTimeoutSeconds,
      min: AppSettingsSnapshot.minAiResponseTimeoutSeconds,
      max: AppSettingsSnapshot.maxAiResponseTimeoutSeconds,
    );
    final aiStreamIdleTimeoutSeconds = clampedIntFromValue(
      json['ai_stream_idle_timeout_seconds'],
      fallback: AppSettingsSnapshot.defaultAiStreamIdleTimeoutSeconds,
      min: AppSettingsSnapshot.minAiStreamIdleTimeoutSeconds,
      max: AppSettingsSnapshot.maxAiStreamIdleTimeoutSeconds,
    );
    final aiStreamMaxCharsPerSecond = clampedIntFromValue(
      json['ai_stream_max_chars_per_second'],
      fallback: AppSettingsSnapshot.defaultAiStreamMaxCharsPerSecond,
      min: AppSettingsSnapshot.minAiStreamMaxCharsPerSecond,
      max: AppSettingsSnapshot.maxAiStreamMaxCharsPerSecond,
    );
    final aiStreamMaxMessageCardsPerSecond = clampedIntFromValue(
      json['ai_stream_max_message_cards_per_second'],
      fallback: AppSettingsSnapshot.defaultAiStreamMaxMessageCardsPerSecond,
      min: AppSettingsSnapshot.minAiStreamMaxMessageCardsPerSecond,
      max: AppSettingsSnapshot.maxAiStreamMaxMessageCardsPerSecond,
    );
    // 2026-05-22 — v3 schema 起，按线程模板覆盖节流参数已下线。
    // 老 settings.json 上仍可能携带 `ai_stream_throttle_template_overrides`
    // 字段（v1/v2 残留），这里完全忽略：不再读、不再透传给 snapshot，
    // write 路径也不会再写出。任何形状的旧 value（Map/null/异常类型）都
    // 必须被静默丢弃，保证 `load()` 不抛。
    final aiStreamThrottleEnabled = json['ai_stream_throttle_enabled'] is bool
        ? json['ai_stream_throttle_enabled'] as bool
        : AppSettingsSnapshot.defaultAiStreamThrottleEnabled;
    final aiStreamThrottleAutoMode =
        json['ai_stream_throttle_auto_mode'] is bool
        ? json['ai_stream_throttle_auto_mode'] as bool
        : AppSettingsSnapshot.defaultAiStreamThrottleAutoMode;
    final aiStreamThrottleDurationSeconds = clampedIntFromValue(
      json['ai_stream_throttle_duration_seconds'],
      fallback: AppSettingsSnapshot.defaultAiStreamThrottleDurationSeconds,
      min: AppSettingsSnapshot.minAiStreamThrottleDurationSeconds,
      max: AppSettingsSnapshot.maxAiStreamThrottleDurationSeconds,
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
    final rawConfigUpdatedAt = json['ai_stream_throttle_config_updated_at_ms'];
    final aiStreamThrottleConfigUpdatedAtMs = rawConfigUpdatedAt is int
        ? rawConfigUpdatedAt
        : AppSettingsSnapshot.defaultAiStreamThrottleConfigUpdatedAtMs;
    final aiAutoTitleEnabled = json['ai_auto_title_enabled'] is bool
        ? json['ai_auto_title_enabled'] as bool
        : true;
    final aiAutoTitleFetchMode = AiAutoTitleFetchMode.fromStorage(
      '${json['ai_auto_title_fetch_mode'] ?? ''}',
    );
    final rawDefaultSessionMode = '${json['ai_default_session_mode'] ?? ''}'
        .trim();
    final aiDefaultSessionMode = rawDefaultSessionMode == 'plan'
        ? 'plan'
        : 'chat';
    final aiDefaultFullAccessPermission =
        json['ai_default_full_access_permission'] is bool
        ? json['ai_default_full_access_permission'] as bool
        : false;

    // AI models.
    final rawModels = json['ai_models'];
    final aiModels = <AiModelConfig>[];
    if (rawModels is List) {
      for (final item in rawModels) {
        if (item is Map) {
          try {
            final model = AiModelConfig.fromJson(
              Map<String, Object?>.from(item),
            );
            if (model.id.trim().isNotEmpty && isValidHttpUrl(model.baseUrl)) {
              aiModels.add(model);
            }
          } catch (error, stack) {
            silentLog('settings_store', 'parse ai_models entry', error, stack);
          }
        }
      }
    }

    var selectedAiModelId = '${json['selected_ai_model_id'] ?? ''}'.trim();
    if (selectedAiModelId.isNotEmpty &&
        !aiModels.any((item) => item.id == selectedAiModelId)) {
      selectedAiModelId = aiModels.isEmpty ? '' : aiModels.first.id;
    }

    // Recent model selections.
    final rawRecentSelections = json['recent_model_selections'];
    final recentModelSelections = <RecentModelSelection>[];
    if (rawRecentSelections is List) {
      for (final item in rawRecentSelections) {
        if (item is Map) {
          try {
            final entry = RecentModelSelection.fromJson(
              Map<String, Object?>.from(item),
            );
            if (entry.configId.isNotEmpty && entry.modelId.isNotEmpty) {
              recentModelSelections.add(entry);
            }
          } catch (error, stack) {
            silentLog(
              'settings_store',
              'parse recent_model_selections entry',
              error,
              stack,
            );
          }
        }
      }
    }

    // Shortcut bindings.
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

    // Animation settings.
    final dialogAnimationSettings = _animationSettingsFromStorage(
      json,
      'dialog_animation_settings',
      fallback: OpenHandMotionDefaults.dialog,
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
      replaceDisabledWithFallback: true,
      legacyDefaults: const <DialogAnimationSettings>[
        DialogAnimationSettings.legacyFadeScale,
      ],
    );
    final chipAnimationSettings = _animationSettingsFromStorage(
      json,
      'chip_animation_settings',
      fallback: OpenHandMotionDefaults.chip,
    );
    final listItemAnimationSettings = _animationSettingsFromStorage(
      json,
      'list_item_animation_settings',
      fallback: OpenHandMotionDefaults.listItem,
    );

    // Builtin tool configs.
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
          silentLog(
            'settings_store',
            'parse builtin_tool_configs entry',
            error,
            stack,
          );
        }
      }
      if (parsed.isNotEmpty) {
        if (AiBuiltinToolConfig.looksLikeLegacyEagerDefaults(parsed)) {
          builtinToolConfigs = AiBuiltinToolConfig.defaults();
        } else {
          // Merge: keep parsed entries, add missing defaults for new tool kinds.
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

    final telemetryDebugEnabled = json['telemetry_debug_enabled'] is bool
        ? json['telemetry_debug_enabled'] as bool
        : false;
    final telemetryCaptureRawPayload =
        json['telemetry_capture_raw_payload'] is bool
        ? json['telemetry_capture_raw_payload'] as bool
        : true;
    final telemetryCaptureEnvironment =
        json['telemetry_capture_environment'] is bool
        ? json['telemetry_capture_environment'] as bool
        : false;
    final telemetryMaxPayloadChars = clampedIntFromValue(
      json['telemetry_max_payload_chars'],
      fallback: AppSettingsSnapshot.defaultTelemetryMaxPayloadChars,
      min: AppSettingsSnapshot.minTelemetryMaxPayloadChars,
      max: AppSettingsSnapshot.maxTelemetryMaxPayloadChars,
    );

    final selfLearningEnabled = json['self_learning_enabled'] is bool
        ? json['self_learning_enabled'] as bool
        : true;
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

    final showSelfLearningMessages = json['show_self_learning_messages'] is bool
        ? json['show_self_learning_messages'] as bool
        : true;

    final cronAutoCleanupEnabled = json['cron_auto_cleanup_enabled'] is bool
        ? json['cron_auto_cleanup_enabled'] as bool
        : true;
    final cronAutoCleanupRetentionDays = clampedIntFromValue(
      json['cron_auto_cleanup_retention_days'],
      fallback: AppSettingsSnapshot.defaultCronAutoCleanupRetentionDays,
      min: AppSettingsSnapshot.minCronAutoCleanupRetentionDays,
      max: AppSettingsSnapshot.maxCronAutoCleanupRetentionDays,
    );

    final hardnessToolSearchHistoryMaxPhases = clampedIntFromValue(
      json['hardness_tool_search_history_max_phases'],
      fallback: AppSettingsSnapshot.defaultHardnessToolSearchHistoryMaxPhases,
      min: AppSettingsSnapshot.minHardnessToolSearchHistoryMaxPhases,
      max: AppSettingsSnapshot.maxHardnessToolSearchHistoryMaxPhases,
    );

    final toolSearchReplayCancelWindowSeconds = clampedIntFromValue(
      json['tool_search_replay_cancel_window_seconds'],
      fallback: AppSettingsSnapshot.defaultToolSearchReplayCancelWindowSeconds,
      min: AppSettingsSnapshot.minToolSearchReplayCancelWindowSeconds,
      max: AppSettingsSnapshot.maxToolSearchReplayCancelWindowSeconds,
    );

    final reduceMotion = json['reduce_motion'] is bool
        ? json['reduce_motion'] as bool
        : false;

    final proxySettings = AppProxySettings.fromJson(json['proxy']);

    final subprocessGracefulShutdownMs = clampedIntFromValue(
      json['subprocess_graceful_shutdown_ms'],
      fallback: AppSettingsSnapshot.defaultSubprocessGracefulShutdownMs,
      min: AppSettingsSnapshot.minSubprocessGracefulShutdownMs,
      max: AppSettingsSnapshot.maxSubprocessGracefulShutdownMs,
    );
    final bashOutputMaxBytes = clampedIntFromValue(
      json['bash_output_max_bytes'],
      fallback: AppSettingsSnapshot.defaultBashOutputMaxBytes,
      min: AppSettingsSnapshot.minBashOutputMaxBytes,
      max: AppSettingsSnapshot.maxBashOutputMaxBytes,
    );
    final maxConcurrentTools = clampedIntFromValue(
      json['max_concurrent_tools'],
      fallback: AppSettingsSnapshot.defaultMaxConcurrentTools,
      min: AppSettingsSnapshot.minMaxConcurrentTools,
      max: AppSettingsSnapshot.maxMaxConcurrentTools,
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
      // 2026-05-22 — v3 schema 起，`aiStreamThrottleTemplateOverrides`
      // 字段已从 AppSettingsSnapshot 上移除（task 4.1），此处不再透传。
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
      hardnessToolSearchHistoryMaxPhases: hardnessToolSearchHistoryMaxPhases,
      toolSearchReplayCancelWindowSeconds: toolSearchReplayCancelWindowSeconds,
      reduceMotion: reduceMotion,
      proxySettings: proxySettings,
      subprocessGracefulShutdownMs: subprocessGracefulShutdownMs,
      bashOutputMaxBytes: bashOutputMaxBytes,
      maxConcurrentTools: maxConcurrentTools,
    );
  }
}

DialogAnimationSettings _dialogAnimationFromValue(
  Object? value, {
  required DialogAnimationSettings fallback,
}) {
  if (value is! Map) return fallback;
  return DialogAnimationSettings.fromJson(Map<String, Object?>.from(value));
}

DialogAnimationSettings _animationSettingsFromStorage(
  Map<String, Object?> json,
  String key, {
  required DialogAnimationSettings fallback,
  Iterable<DialogAnimationSettings> legacyDefaults =
      const <DialogAnimationSettings>[],
  bool replaceDisabledWithFallback = false,
}) {
  final settings = _dialogAnimationFromValue(json[key], fallback: fallback);
  if (replaceDisabledWithFallback && settings.disablesAnimation) {
    return fallback;
  }
  for (final legacyDefault in legacyDefaults) {
    if (settings == legacyDefault) {
      return fallback;
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
