// 2026-05-01: the dialog-animation defaults block in this file mirrors
// the documentation pattern used in `app_settings_snapshot.dart` — every
// field is listed for parallel readability even when it equals the
// constructor default.
// ignore_for_file: avoid_redundant_argument_values

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../features/ai/model/ai_allow_command_rule.dart';
import '../../features/ai/model/ai_builtin_tool_config.dart';
import '../../features/ai/model/ai_deny_command_rule.dart';
import '../../features/ai/model/ai_lsp_language_settings.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../../features/ai/model/ai_sandbox_settings.dart';
import '../../features/mcp/model/mcp_keyword_index_update_mode.dart';
import '../../features/mcp/model/mcp_lazy_loading_mode.dart';
import '../../features/mcp/model/mcp_stdio_mirror_mode.dart';
import '../../shared/db/database_service.dart';
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
      'version': 2,
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
      'ai_web_fetch_max_response_bytes': snapshot.aiWebFetchMaxResponseBytes,
      'ai_web_fetch_max_redirects': snapshot.aiWebFetchMaxRedirects,
      'ai_web_fetch_max_cache_entries': snapshot.aiWebFetchMaxCacheEntries,
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

  static AppSettingsSnapshot _snapshotFromJson(Map<String, Object?> json) {
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
    final mcpStdioMirrorMode = McpStdioMirrorMode.fromStorage(
      '${json['mcp_stdio_mirror_mode'] ?? ''}',
    );
    final mcpLazyLoadingThresholdTokens =
        json['mcp_lazy_loading_threshold_tokens'] is int &&
            (json['mcp_lazy_loading_threshold_tokens'] as int) >=
                AppSettingsSnapshot.minMcpLazyLoadingThresholdTokens
        ? (json['mcp_lazy_loading_threshold_tokens'] as int).clamp(
            AppSettingsSnapshot.minMcpLazyLoadingThresholdTokens,
            AppSettingsSnapshot.maxMcpLazyLoadingThresholdTokens,
          )
        : AppSettingsSnapshot.defaultMcpLazyLoadingThresholdTokens;
    final mcpAutoProbeConcurrency = json['mcp_auto_probe_concurrency'] is int
        ? (json['mcp_auto_probe_concurrency'] as int).clamp(
            AppSettingsSnapshot.minMcpAutoProbeConcurrency,
            AppSettingsSnapshot.maxMcpAutoProbeConcurrency,
          )
        : AppSettingsSnapshot.defaultMcpAutoProbeConcurrency;
    final mcpKeywordIndexUpdateMode = McpKeywordIndexUpdateMode.fromStorage(
      '${json['mcp_keyword_index_update_mode'] ?? ''}',
    );
    final mcpKeywordIndexIntervalValue =
        json['mcp_keyword_index_interval_value'] is int
        ? (json['mcp_keyword_index_interval_value'] as int).clamp(
            AppSettingsSnapshot.minMcpKeywordIndexIntervalValue,
            AppSettingsSnapshot.maxMcpKeywordIndexIntervalValue,
          )
        : AppSettingsSnapshot.defaultMcpKeywordIndexIntervalValue;
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
    final aiToolResultCompressionHeadTailWindowChars =
        json['ai_tool_result_compression_head_tail_window_chars'] is int &&
            (json['ai_tool_result_compression_head_tail_window_chars']
                    as int) >=
                AppSettingsSnapshot
                    .minAiToolResultCompressionHeadTailWindowChars
        ? (json['ai_tool_result_compression_head_tail_window_chars'] as int)
              .clamp(
                AppSettingsSnapshot
                    .minAiToolResultCompressionHeadTailWindowChars,
                AppSettingsSnapshot
                    .maxAiToolResultCompressionHeadTailWindowChars,
              )
        : AppSettingsSnapshot.defaultAiToolResultCompressionHeadTailWindowChars;
    final aiToolResultCompressionMaxPathHits =
        json['ai_tool_result_compression_max_path_hits'] is int &&
            (json['ai_tool_result_compression_max_path_hits'] as int) >=
                AppSettingsSnapshot.minAiToolResultCompressionMaxPathHits
        ? (json['ai_tool_result_compression_max_path_hits'] as int).clamp(
            AppSettingsSnapshot.minAiToolResultCompressionMaxPathHits,
            AppSettingsSnapshot.maxAiToolResultCompressionMaxPathHits,
          )
        : AppSettingsSnapshot.defaultAiToolResultCompressionMaxPathHits;
    final aiInputCacheEnabled = json['ai_input_cache_enabled'] is bool
        ? json['ai_input_cache_enabled'] as bool
        : AppSettingsSnapshot.defaultAiInputCacheEnabled;
    final aiInputCacheUpdateMode =
        json['ai_input_cache_update_mode'] is String &&
            AppSettingsSnapshot.validAiInputCacheUpdateModes.contains(
              json['ai_input_cache_update_mode'] as String,
            )
        ? json['ai_input_cache_update_mode'] as String
        : AppSettingsSnapshot.defaultAiInputCacheUpdateMode;
    final aiInputCacheUpdateInterval =
        json['ai_input_cache_update_interval'] is int &&
            (json['ai_input_cache_update_interval'] as int) >=
                AppSettingsSnapshot.minAiInputCacheUpdateInterval
        ? (json['ai_input_cache_update_interval'] as int).clamp(
            AppSettingsSnapshot.minAiInputCacheUpdateInterval,
            AppSettingsSnapshot.maxAiInputCacheUpdateInterval,
          )
        : AppSettingsSnapshot.defaultAiInputCacheUpdateInterval;
    final aiInputCacheBreakpointCount =
        json['ai_input_cache_breakpoint_count'] is int &&
            (json['ai_input_cache_breakpoint_count'] as int) >=
                AppSettingsSnapshot.minAiInputCacheBreakpointCount
        ? (json['ai_input_cache_breakpoint_count'] as int).clamp(
            AppSettingsSnapshot.minAiInputCacheBreakpointCount,
            AppSettingsSnapshot.maxAiInputCacheBreakpointCount,
          )
        : AppSettingsSnapshot.defaultAiInputCacheBreakpointCount;
    // 2026-05-04 — 用户自定义前 N-1 个静态缓存点位置（百分比 0..1，升序）。
    // JSON 形如 [0.25, 0.5, 0.75]；非法元素直接忽略，越界 clamp 至 [0,1]。
    final List<double> aiInputCacheBreakpointPositions = () {
      final raw = json['ai_input_cache_breakpoint_positions'];
      if (raw is! List) {
        return AppSettingsSnapshot.defaultAiInputCacheBreakpointPositions;
      }
      final parsed = <double>[];
      for (final entry in raw) {
        double? v;
        if (entry is num) {
          v = entry.toDouble();
        } else if (entry is String) {
          v = double.tryParse(entry);
        }
        if (v == null || v.isNaN || !v.isFinite) continue;
        parsed.add(v.clamp(0.0, 1.0));
      }
      parsed.sort();
      return List<double>.unmodifiable(parsed);
    }();
    final aiBudgetUsdPerSession = () {
      final raw = json['ai_budget_usd_per_session'];
      double? v;
      if (raw is num) v = raw.toDouble();
      if (raw is String) v = double.tryParse(raw);
      if (v == null || v.isNaN || !v.isFinite) {
        return AppSettingsSnapshot.defaultAiBudgetUsdPerSession;
      }
      return v.clamp(
        AppSettingsSnapshot.minAiBudgetUsdPerSession,
        AppSettingsSnapshot.maxAiBudgetUsdPerSession,
      );
    }();
    final aiWriteToolSummaryMaxChars =
        json['ai_write_tool_summary_max_chars'] is int &&
            (json['ai_write_tool_summary_max_chars'] as int) >=
                AppSettingsSnapshot.minAiWriteToolSummaryMaxChars
        ? (json['ai_write_tool_summary_max_chars'] as int).clamp(
            AppSettingsSnapshot.minAiWriteToolSummaryMaxChars,
            AppSettingsSnapshot.maxAiWriteToolSummaryMaxChars,
          )
        : AppSettingsSnapshot.defaultAiWriteToolSummaryMaxChars;
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
    final aiMaxRecentErrors = json['ai_max_recent_errors'] is int
        ? (json['ai_max_recent_errors'] as int).clamp(
            AppSettingsSnapshot.minAiMaxRecentErrors,
            AppSettingsSnapshot.maxAiMaxRecentErrors,
          )
        : AppSettingsSnapshot.defaultAiMaxRecentErrors;
    final aiMaxPlanHistoryEntries = json['ai_max_plan_history_entries'] is int
        ? (json['ai_max_plan_history_entries'] as int).clamp(
            AppSettingsSnapshot.minAiMaxPlanHistoryEntries,
            AppSettingsSnapshot.maxAiMaxPlanHistoryEntries,
          )
        : AppSettingsSnapshot.defaultAiMaxPlanHistoryEntries;
    final aiMaxTruncationContinuations =
        json['ai_max_truncation_continuations'] is int
        ? (json['ai_max_truncation_continuations'] as int).clamp(
            AppSettingsSnapshot.minAiMaxTruncationContinuations,
            AppSettingsSnapshot.maxAiMaxTruncationContinuations,
          )
        : AppSettingsSnapshot.defaultAiMaxTruncationContinuations;
    final aiEstimatedCharactersPerToken =
        json['ai_estimated_characters_per_token'] is int
        ? (json['ai_estimated_characters_per_token'] as int).clamp(
            AppSettingsSnapshot.minAiEstimatedCharactersPerToken,
            AppSettingsSnapshot.maxAiEstimatedCharactersPerToken,
          )
        : AppSettingsSnapshot.defaultAiEstimatedCharactersPerToken;
    final aiMaxToolOutputChars = json['ai_max_tool_output_chars'] is int
        ? (json['ai_max_tool_output_chars'] as int).clamp(
            AppSettingsSnapshot.minAiMaxToolOutputChars,
            AppSettingsSnapshot.maxAiMaxToolOutputChars,
          )
        : AppSettingsSnapshot.defaultAiMaxToolOutputChars;
    final aiWriteConfirmationTimeoutMs =
        json['ai_write_confirmation_timeout_ms'] is int
        ? (json['ai_write_confirmation_timeout_ms'] as int).clamp(
            AppSettingsSnapshot.minAiWriteConfirmationTimeoutMs,
            AppSettingsSnapshot.maxAiWriteConfirmationTimeoutMs,
          )
        : AppSettingsSnapshot.defaultAiWriteConfirmationTimeoutMs;
    final aiFastPathWriteAnalysisThreshold =
        json['ai_fast_path_write_analysis_threshold'] is int
        ? (json['ai_fast_path_write_analysis_threshold'] as int).clamp(
            AppSettingsSnapshot.minAiFastPathWriteAnalysisThreshold,
            AppSettingsSnapshot.maxAiFastPathWriteAnalysisThreshold,
          )
        : AppSettingsSnapshot.defaultAiFastPathWriteAnalysisThreshold;
    final aiMaxHookTextCharacters = json['ai_max_hook_text_characters'] is int
        ? (json['ai_max_hook_text_characters'] as int).clamp(
            AppSettingsSnapshot.minAiMaxHookTextCharacters,
            AppSettingsSnapshot.maxAiMaxHookTextCharacters,
          )
        : AppSettingsSnapshot.defaultAiMaxHookTextCharacters;
    final aiWebFetchMaxResponseBytes =
        json['ai_web_fetch_max_response_bytes'] is int
        ? (json['ai_web_fetch_max_response_bytes'] as int).clamp(
            AppSettingsSnapshot.minAiWebFetchMaxResponseBytes,
            AppSettingsSnapshot.maxAiWebFetchMaxResponseBytes,
          )
        : AppSettingsSnapshot.defaultAiWebFetchMaxResponseBytes;
    final aiWebFetchMaxRedirects = json['ai_web_fetch_max_redirects'] is int
        ? (json['ai_web_fetch_max_redirects'] as int).clamp(
            AppSettingsSnapshot.minAiWebFetchMaxRedirects,
            AppSettingsSnapshot.maxAiWebFetchMaxRedirects,
          )
        : AppSettingsSnapshot.defaultAiWebFetchMaxRedirects;
    final aiWebFetchMaxCacheEntries =
        json['ai_web_fetch_max_cache_entries'] is int
        ? (json['ai_web_fetch_max_cache_entries'] as int).clamp(
            AppSettingsSnapshot.minAiWebFetchMaxCacheEntries,
            AppSettingsSnapshot.maxAiWebFetchMaxCacheEntries,
          )
        : AppSettingsSnapshot.defaultAiWebFetchMaxCacheEntries;
    final aiAttachmentMaxInlineImageDimension =
        json['ai_attachment_max_inline_image_dimension'] is int
        ? (json['ai_attachment_max_inline_image_dimension'] as int).clamp(
            AppSettingsSnapshot.minAiAttachmentMaxInlineImageDimension,
            AppSettingsSnapshot.maxAiAttachmentMaxInlineImageDimension,
          )
        : AppSettingsSnapshot.defaultAiAttachmentMaxInlineImageDimension;
    final aiAttachmentMaxTextRawBytes =
        json['ai_attachment_max_text_raw_bytes'] is int
        ? (json['ai_attachment_max_text_raw_bytes'] as int).clamp(
            AppSettingsSnapshot.minAiAttachmentMaxTextRawBytes,
            AppSettingsSnapshot.maxAiAttachmentMaxTextRawBytes,
          )
        : AppSettingsSnapshot.defaultAiAttachmentMaxTextRawBytes;
    final aiAttachmentMaxPdfRawBytes =
        json['ai_attachment_max_pdf_raw_bytes'] is int
        ? (json['ai_attachment_max_pdf_raw_bytes'] as int).clamp(
            AppSettingsSnapshot.minAiAttachmentMaxPdfRawBytes,
            AppSettingsSnapshot.maxAiAttachmentMaxPdfRawBytes,
          )
        : AppSettingsSnapshot.defaultAiAttachmentMaxPdfRawBytes;
    final aiAttachmentMaxImageRawBytes =
        json['ai_attachment_max_image_raw_bytes'] is int
        ? (json['ai_attachment_max_image_raw_bytes'] as int).clamp(
            AppSettingsSnapshot.minAiAttachmentMaxImageRawBytes,
            AppSettingsSnapshot.maxAiAttachmentMaxImageRawBytes,
          )
        : AppSettingsSnapshot.defaultAiAttachmentMaxImageRawBytes;
    final aiChatMaxStreamLineBufferBytes =
        json['ai_chat_max_stream_line_buffer_bytes'] is int
        ? (json['ai_chat_max_stream_line_buffer_bytes'] as int).clamp(
            AppSettingsSnapshot.minAiChatMaxStreamLineBufferBytes,
            AppSettingsSnapshot.maxAiChatMaxStreamLineBufferBytes,
          )
        : AppSettingsSnapshot.defaultAiChatMaxStreamLineBufferBytes;
    final aiFallbackTitleMaxCharacters =
        json['ai_fallback_title_max_characters'] is int
        ? (json['ai_fallback_title_max_characters'] as int).clamp(
            AppSettingsSnapshot.minAiFallbackTitleMaxCharacters,
            AppSettingsSnapshot.maxAiFallbackTitleMaxCharacters,
          )
        : AppSettingsSnapshot.defaultAiFallbackTitleMaxCharacters;
    final aiGeneratedTitleMaxCharacters =
        json['ai_generated_title_max_characters'] is int
        ? (json['ai_generated_title_max_characters'] as int).clamp(
            AppSettingsSnapshot.minAiGeneratedTitleMaxCharacters,
            AppSettingsSnapshot.maxAiGeneratedTitleMaxCharacters,
          )
        : AppSettingsSnapshot.defaultAiGeneratedTitleMaxCharacters;
    final aiAutoTitleMaxRetryCount =
        json['ai_auto_title_max_retry_count'] is int
        ? (json['ai_auto_title_max_retry_count'] as int).clamp(
            AppSettingsSnapshot.minAiAutoTitleMaxRetryCount,
            AppSettingsSnapshot.maxAiAutoTitleMaxRetryCount,
          )
        : AppSettingsSnapshot.defaultAiAutoTitleMaxRetryCount;
    final aiMinimumMeaningfulTitleCharacters =
        json['ai_minimum_meaningful_title_characters'] is int
        ? (json['ai_minimum_meaningful_title_characters'] as int).clamp(
            AppSettingsSnapshot.minAiMinimumMeaningfulTitleCharacters,
            AppSettingsSnapshot.maxAiMinimumMeaningfulTitleCharacters,
          )
        : AppSettingsSnapshot.defaultAiMinimumMeaningfulTitleCharacters;
    final aiMinimumMeaningfulLatinTitleWords =
        json['ai_minimum_meaningful_latin_title_words'] is int
        ? (json['ai_minimum_meaningful_latin_title_words'] as int).clamp(
            AppSettingsSnapshot.minAiMinimumMeaningfulLatinTitleWords,
            AppSettingsSnapshot.maxAiMinimumMeaningfulLatinTitleWords,
          )
        : AppSettingsSnapshot.defaultAiMinimumMeaningfulLatinTitleWords;
    final aiMaxSkillContentLength = json['ai_max_skill_content_length'] is int
        ? (json['ai_max_skill_content_length'] as int).clamp(
            AppSettingsSnapshot.minAiMaxSkillContentLength,
            AppSettingsSnapshot.maxAiMaxSkillContentLength,
          )
        : AppSettingsSnapshot.defaultAiMaxSkillContentLength;
    final aiMaxWorkspaceDocumentCharacters =
        json['ai_max_workspace_document_characters'] is int
        ? (json['ai_max_workspace_document_characters'] as int).clamp(
            AppSettingsSnapshot.minAiMaxWorkspaceDocumentCharacters,
            AppSettingsSnapshot.maxAiMaxWorkspaceDocumentCharacters,
          )
        : AppSettingsSnapshot.defaultAiMaxWorkspaceDocumentCharacters;
    final rawImageSizeLimit = json['ai_image_size_limit_bytes'];
    final aiImageSizeLimitBytes =
        (rawImageSizeLimit is int && rawImageSizeLimit > 0)
        ? rawImageSizeLimit.clamp(
            AppSettingsSnapshot.minAiImageSizeLimitBytes,
            AppSettingsSnapshot.maxAiImageSizeLimitBytes,
          )
        : AppSettingsSnapshot.defaultAiImageSizeLimitBytes;
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
    final aiSandboxSettings = rawSandboxSettings is Map
        ? AiSandboxSettings.fromJson(
            Map<String, Object?>.from(rawSandboxSettings),
          )
        : AiSandboxSettings.defaults();

    // Session timeout settings.
    final rawConnectTimeout = json['ai_connect_timeout_seconds'];
    final aiConnectTimeoutSeconds =
        (rawConnectTimeout is int &&
            rawConnectTimeout >= AppSettingsSnapshot.minAiConnectTimeoutSeconds)
        ? rawConnectTimeout.clamp(
            AppSettingsSnapshot.minAiConnectTimeoutSeconds,
            AppSettingsSnapshot.maxAiConnectTimeoutSeconds,
          )
        : AppSettingsSnapshot.defaultAiConnectTimeoutSeconds;
    final rawResponseTimeout = json['ai_response_timeout_seconds'];
    final aiResponseTimeoutSeconds =
        (rawResponseTimeout is int &&
            rawResponseTimeout >=
                AppSettingsSnapshot.minAiResponseTimeoutSeconds)
        ? rawResponseTimeout.clamp(
            AppSettingsSnapshot.minAiResponseTimeoutSeconds,
            AppSettingsSnapshot.maxAiResponseTimeoutSeconds,
          )
        : AppSettingsSnapshot.defaultAiResponseTimeoutSeconds;
    final rawStreamIdleTimeout = json['ai_stream_idle_timeout_seconds'];
    final aiStreamIdleTimeoutSeconds =
        (rawStreamIdleTimeout is int &&
            rawStreamIdleTimeout >=
                AppSettingsSnapshot.minAiStreamIdleTimeoutSeconds)
        ? rawStreamIdleTimeout.clamp(
            AppSettingsSnapshot.minAiStreamIdleTimeoutSeconds,
            AppSettingsSnapshot.maxAiStreamIdleTimeoutSeconds,
          )
        : AppSettingsSnapshot.defaultAiStreamIdleTimeoutSeconds;
    final rawStreamMaxChars = json['ai_stream_max_chars_per_second'];
    final aiStreamMaxCharsPerSecond =
        (rawStreamMaxChars is int &&
            rawStreamMaxChars >=
                AppSettingsSnapshot.minAiStreamMaxCharsPerSecond)
        ? rawStreamMaxChars.clamp(
            AppSettingsSnapshot.minAiStreamMaxCharsPerSecond,
            AppSettingsSnapshot.maxAiStreamMaxCharsPerSecond,
          )
        : AppSettingsSnapshot.defaultAiStreamMaxCharsPerSecond;
    final rawStreamMaxMessageCards =
        json['ai_stream_max_message_cards_per_second'];
    final aiStreamMaxMessageCardsPerSecond =
        (rawStreamMaxMessageCards is int &&
            rawStreamMaxMessageCards >=
                AppSettingsSnapshot.minAiStreamMaxMessageCardsPerSecond)
        ? rawStreamMaxMessageCards.clamp(
            AppSettingsSnapshot.minAiStreamMaxMessageCardsPerSecond,
            AppSettingsSnapshot.maxAiStreamMaxMessageCardsPerSecond,
          )
        : AppSettingsSnapshot.defaultAiStreamMaxMessageCardsPerSecond;
    // 2026-05-22 — v3 schema 起，按线程模板覆盖节流参数已下线。
    // 老 settings.json 上仍可能携带 `ai_stream_throttle_template_overrides`
    // 字段（v1/v2 残留），这里完全忽略：不再读、不再透传给 snapshot，
    // write 路径也不会再写出。任何形状的旧 value（Map/null/异常类型）都
    // 必须被静默丢弃，保证 `load()` 不抛。
    final aiStreamThrottleEnabled = json['ai_stream_throttle_enabled'] is bool
        ? json['ai_stream_throttle_enabled'] as bool
        : AppSettingsSnapshot.defaultAiStreamThrottleEnabled;
    final aiStreamThrottleAutoMode = json['ai_stream_throttle_auto_mode'] is bool
        ? json['ai_stream_throttle_auto_mode'] as bool
        : AppSettingsSnapshot.defaultAiStreamThrottleAutoMode;
    final aiStreamThrottleDurationSeconds =
        json['ai_stream_throttle_duration_seconds'] is int
            ? (json['ai_stream_throttle_duration_seconds'] as int).clamp(
                AppSettingsSnapshot.minAiStreamThrottleDurationSeconds,
                AppSettingsSnapshot.maxAiStreamThrottleDurationSeconds,
              )
            : AppSettingsSnapshot.defaultAiStreamThrottleDurationSeconds;
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
    final rawDialogAnim = json['dialog_animation_settings'];
    var dialogAnimationSettings = const DialogAnimationSettings();
    if (rawDialogAnim is Map<String, dynamic>) {
      dialogAnimationSettings = DialogAnimationSettings.fromJson(rawDialogAnim);
    }
    final rawMenuAnim = json['menu_animation_settings'];
    var menuAnimationSettings = const DialogAnimationSettings();
    if (rawMenuAnim is Map<String, dynamic>) {
      menuAnimationSettings = DialogAnimationSettings.fromJson(rawMenuAnim);
    }
    final rawPageAnim = json['page_animation_settings'];
    const pageAnimationDefault = DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.fade,
      exitStyle: DialogAnimationStyle.fade,
      durationMs: 800,
      curve: DialogAnimationCurve.easeInOutCubicEmphasized,
    );
    var pageAnimationSettings = pageAnimationDefault;
    if (rawPageAnim is Map<String, dynamic>) {
      pageAnimationSettings = DialogAnimationSettings.fromJson(rawPageAnim);
      // Auto-repair legacy / under-tuned persisted snapshots so the page
      // transition is actually perceptible. Only triggers on the exact
      // historical default tuples below — anything the user explicitly
      // customized (any field differs) is left untouched.
      //
      // Case 1: both styles `none` → user effectively sees instant cut.
      // Case 2: original v1 default fade/fade/240ms/easeOutCubic — too
      //         subtle on similar Material layouts.
      // Case 3: previous migration target fade/fade/420ms/
      //         easeInOutCubicEmphasized — emphasized curve front-loads the
      //         flat portion, making 420ms still hard to see; bump to 800ms.
      final isAllNone =
          pageAnimationSettings.entranceStyle == DialogAnimationStyle.none &&
          pageAnimationSettings.exitStyle == DialogAnimationStyle.none;
      final isLegacyDefaultV1 =
          pageAnimationSettings.entranceStyle == DialogAnimationStyle.fade &&
          pageAnimationSettings.exitStyle == DialogAnimationStyle.fade &&
          pageAnimationSettings.durationMs == 240 &&
          pageAnimationSettings.curve == DialogAnimationCurve.easeOutCubic;
      final isLegacyDefaultV2 =
          pageAnimationSettings.entranceStyle == DialogAnimationStyle.fade &&
          pageAnimationSettings.exitStyle == DialogAnimationStyle.fade &&
          pageAnimationSettings.durationMs == 420 &&
          pageAnimationSettings.curve ==
              DialogAnimationCurve.easeInOutCubicEmphasized;
      if (isAllNone || isLegacyDefaultV1 || isLegacyDefaultV2) {
        pageAnimationSettings = pageAnimationDefault;
      }
    }
    final rawPanelAnim = json['panel_animation_settings'];
    const panelAnimationDefault = DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.fade,
      exitStyle: DialogAnimationStyle.fade,
      durationMs: 600,
      curve: DialogAnimationCurve.easeInOutCubicEmphasized,
    );
    var panelAnimationSettings = panelAnimationDefault;
    if (rawPanelAnim is Map<String, dynamic>) {
      panelAnimationSettings = DialogAnimationSettings.fromJson(rawPanelAnim);
      // Repair the legacy/unset panel default (fadeScale/fadeScale/320ms/
      // easeOutCubic, produced by `const DialogAnimationSettings()`) so the
      // workspace left/right panel switches share the new emphasized fade
      // identity. Same protection: only triggers on the exact legacy tuple.
      // Also auto-recover from both-styles=`none`.
      final isAllNonePanel =
          panelAnimationSettings.entranceStyle == DialogAnimationStyle.none &&
          panelAnimationSettings.exitStyle == DialogAnimationStyle.none;
      final isLegacyPanelDefault =
          panelAnimationSettings.entranceStyle ==
              DialogAnimationStyle.fadeScale &&
          panelAnimationSettings.exitStyle == DialogAnimationStyle.fadeScale &&
          panelAnimationSettings.durationMs == 320 &&
          panelAnimationSettings.curve == DialogAnimationCurve.easeOutCubic;
      if (isAllNonePanel || isLegacyPanelDefault) {
        panelAnimationSettings = panelAnimationDefault;
      }
    }

    // Chip (capsule) and list-item channels — newer additions, no
    // legacy migration needed; just read with defaults.
    const chipAnimationDefault = DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.springScale,
      exitStyle: DialogAnimationStyle.fadeScale,
      durationMs: 320,
      curve: DialogAnimationCurve.easeInOutCubicEmphasized,
    );
    var chipAnimationSettings = chipAnimationDefault;
    final rawChipAnim = json['chip_animation_settings'];
    if (rawChipAnim is Map<String, dynamic>) {
      chipAnimationSettings = DialogAnimationSettings.fromJson(rawChipAnim);
    }
    const listItemAnimationDefault = DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.slideUp,
      exitStyle: DialogAnimationStyle.fade,
      durationMs: 320,
      curve: DialogAnimationCurve.easeInOutCubicEmphasized,
    );
    var listItemAnimationSettings = listItemAnimationDefault;
    final rawListItemAnim = json['list_item_animation_settings'];
    if (rawListItemAnim is Map<String, dynamic>) {
      listItemAnimationSettings = DialogAnimationSettings.fromJson(
        rawListItemAnim,
      );
    }

    // Builtin tool configs.
    final rawBuiltinToolConfigs = json['builtin_tool_configs'];
    var builtinToolConfigs = AiBuiltinToolConfig.defaults();
    if (rawBuiltinToolConfigs is List) {
      final parsed = <AiBuiltinToolConfig>[];
      for (final item in rawBuiltinToolConfigs) {
        if (item is Map) {
          try {
            parsed.add(
              AiBuiltinToolConfig.fromJson(Map<String, Object?>.from(item)),
            );
          } catch (error, stack) {
            silentLog(
              'settings_store',
              'parse builtin_tool_configs entry',
              error,
              stack,
            );
          }
        }
      }
      if (parsed.isNotEmpty) {
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
    final rawTelemetryMaxPayload = json['telemetry_max_payload_chars'];
    final telemetryMaxPayloadChars =
        (rawTelemetryMaxPayload is int && rawTelemetryMaxPayload > 0)
        ? rawTelemetryMaxPayload.clamp(
            AppSettingsSnapshot.minTelemetryMaxPayloadChars,
            AppSettingsSnapshot.maxTelemetryMaxPayloadChars,
          )
        : AppSettingsSnapshot.defaultTelemetryMaxPayloadChars;

    final selfLearningEnabled = json['self_learning_enabled'] is bool
        ? json['self_learning_enabled'] as bool
        : true;
    final rawSelfLearningConcurrency = json['self_learning_concurrency'];
    final selfLearningConcurrency =
        (rawSelfLearningConcurrency is int && rawSelfLearningConcurrency > 0)
        ? rawSelfLearningConcurrency.clamp(
            AppSettingsSnapshot.minSelfLearningConcurrency,
            AppSettingsSnapshot.maxSelfLearningConcurrency,
          )
        : AppSettingsSnapshot.defaultSelfLearningConcurrency;

    final rawSelfLearningFlushMs =
        json['self_learning_stream_flush_interval_ms'];
    final selfLearningStreamFlushIntervalMs =
        (rawSelfLearningFlushMs is int && rawSelfLearningFlushMs > 0)
        ? rawSelfLearningFlushMs.clamp(
            AppSettingsSnapshot.minSelfLearningStreamFlushIntervalMs,
            AppSettingsSnapshot.maxSelfLearningStreamFlushIntervalMs,
          )
        : AppSettingsSnapshot.defaultSelfLearningStreamFlushIntervalMs;

    final showSelfLearningMessages = json['show_self_learning_messages'] is bool
        ? json['show_self_learning_messages'] as bool
        : true;

    final cronAutoCleanupEnabled = json['cron_auto_cleanup_enabled'] is bool
        ? json['cron_auto_cleanup_enabled'] as bool
        : true;
    final rawCronRetention = json['cron_auto_cleanup_retention_days'];
    final cronAutoCleanupRetentionDays =
        (rawCronRetention is int && rawCronRetention > 0)
        ? rawCronRetention.clamp(
            AppSettingsSnapshot.minCronAutoCleanupRetentionDays,
            AppSettingsSnapshot.maxCronAutoCleanupRetentionDays,
          )
        : AppSettingsSnapshot.defaultCronAutoCleanupRetentionDays;

    final rawHardnessHistoryCap =
        json['hardness_tool_search_history_max_phases'];
    final hardnessToolSearchHistoryMaxPhases =
        (rawHardnessHistoryCap is int && rawHardnessHistoryCap > 0)
        ? rawHardnessHistoryCap.clamp(
            AppSettingsSnapshot.minHardnessToolSearchHistoryMaxPhases,
            AppSettingsSnapshot.maxHardnessToolSearchHistoryMaxPhases,
          )
        : AppSettingsSnapshot.defaultHardnessToolSearchHistoryMaxPhases;

    final rawReplayCancelWindow =
        json['tool_search_replay_cancel_window_seconds'];
    final toolSearchReplayCancelWindowSeconds =
        (rawReplayCancelWindow is int && rawReplayCancelWindow > 0)
        ? rawReplayCancelWindow.clamp(
            AppSettingsSnapshot.minToolSearchReplayCancelWindowSeconds,
            AppSettingsSnapshot.maxToolSearchReplayCancelWindowSeconds,
          )
        : AppSettingsSnapshot.defaultToolSearchReplayCancelWindowSeconds;

    final reduceMotion = json['reduce_motion'] is bool
        ? json['reduce_motion'] as bool
        : false;

    final proxySettings = AppProxySettings.fromJson(json['proxy']);

    final subprocessGracefulShutdownMs =
        json['subprocess_graceful_shutdown_ms'] is num
        ? (json['subprocess_graceful_shutdown_ms'] as num).round().clamp(
            AppSettingsSnapshot.minSubprocessGracefulShutdownMs,
            AppSettingsSnapshot.maxSubprocessGracefulShutdownMs,
          )
        : AppSettingsSnapshot.defaultSubprocessGracefulShutdownMs;
    final bashOutputMaxBytes = json['bash_output_max_bytes'] is num
        ? (json['bash_output_max_bytes'] as num).round().clamp(
            AppSettingsSnapshot.minBashOutputMaxBytes,
            AppSettingsSnapshot.maxBashOutputMaxBytes,
          )
        : AppSettingsSnapshot.defaultBashOutputMaxBytes;
    final maxConcurrentTools = json['max_concurrent_tools'] is num
        ? (json['max_concurrent_tools'] as num).round().clamp(
            AppSettingsSnapshot.minMaxConcurrentTools,
            AppSettingsSnapshot.maxMaxConcurrentTools,
          )
        : AppSettingsSnapshot.defaultMaxConcurrentTools;

    return AppSettingsSnapshot(
      themeMode: themeMode,
      themePreset: themePreset,
      language: language,
      skillsStoragePath: skillsStoragePath,
      mcpEnabled: mcpEnabled,
      mcpServersFilePath: mcpServersFilePath,
      mcpLazyLoadingMode: mcpLazyLoadingMode,
      mcpLazyLoadingThresholdTokens: mcpLazyLoadingThresholdTokens,
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
      aiWebFetchMaxResponseBytes: aiWebFetchMaxResponseBytes,
      aiWebFetchMaxRedirects: aiWebFetchMaxRedirects,
      aiWebFetchMaxCacheEntries: aiWebFetchMaxCacheEntries,
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
