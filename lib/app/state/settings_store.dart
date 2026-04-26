import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../features/ai/model/ai_allow_command_rule.dart';
import '../../features/ai/model/ai_builtin_tool_config.dart';
import '../../features/ai/model/ai_deny_command_rule.dart';
import '../../features/ai/model/ai_lsp_language_settings.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../../shared/data/database_service.dart';
import '../model/app_language.dart';
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
      'ai_write_tool_summary_max_chars': snapshot.aiWriteToolSummaryMaxChars,
      'ai_single_round_tool_call_limit': snapshot.aiSingleRoundToolCallLimit,
      'ai_max_recent_errors': snapshot.aiMaxRecentErrors,
      'ai_max_plan_history_entries': snapshot.aiMaxPlanHistoryEntries,
      'ai_max_truncation_continuations': snapshot.aiMaxTruncationContinuations,
      'ai_estimated_characters_per_token': snapshot.aiEstimatedCharactersPerToken,
      'ai_max_tool_output_chars': snapshot.aiMaxToolOutputChars,
      'ai_write_confirmation_timeout_ms': snapshot.aiWriteConfirmationTimeoutMs,
      'ai_fast_path_write_analysis_threshold': snapshot.aiFastPathWriteAnalysisThreshold,
      'ai_max_hook_text_characters': snapshot.aiMaxHookTextCharacters,
      'ai_web_fetch_max_response_bytes': snapshot.aiWebFetchMaxResponseBytes,
      'ai_web_fetch_max_redirects': snapshot.aiWebFetchMaxRedirects,
      'ai_web_fetch_max_cache_entries': snapshot.aiWebFetchMaxCacheEntries,
      'ai_attachment_max_inline_image_dimension': snapshot.aiAttachmentMaxInlineImageDimension,
      'ai_attachment_max_text_raw_bytes': snapshot.aiAttachmentMaxTextRawBytes,
      'ai_attachment_max_pdf_raw_bytes': snapshot.aiAttachmentMaxPdfRawBytes,
      'ai_attachment_max_image_raw_bytes': snapshot.aiAttachmentMaxImageRawBytes,
      'ai_chat_max_stream_line_buffer_bytes': snapshot.aiChatMaxStreamLineBufferBytes,
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
      'ai_connect_timeout_seconds': snapshot.aiConnectTimeoutSeconds,
      'ai_response_timeout_seconds': snapshot.aiResponseTimeoutSeconds,
      'ai_stream_idle_timeout_seconds': snapshot.aiStreamIdleTimeoutSeconds,
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
      'builtin_tool_configs': snapshot.builtinToolConfigs
          .map((item) => item.toJson())
          .toList(growable: false),
      'telemetry_debug_enabled': snapshot.telemetryDebugEnabled,
      'telemetry_capture_raw_payload': snapshot.telemetryCaptureRawPayload,
      'telemetry_capture_environment': snapshot.telemetryCaptureEnvironment,
      'telemetry_max_payload_chars': snapshot.telemetryMaxPayloadChars,
      'self_learning_enabled': snapshot.selfLearningEnabled,
      'self_learning_concurrency': snapshot.selfLearningConcurrency,
      'show_self_learning_messages': snapshot.showSelfLearningMessages,
      'cron_auto_cleanup_enabled': snapshot.cronAutoCleanupEnabled,
      'cron_auto_cleanup_retention_days': snapshot.cronAutoCleanupRetentionDays,
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
        json['ai_message_compression_threshold_chars'] is int &&
            (json['ai_message_compression_threshold_chars'] as int) > 0
        ? json['ai_message_compression_threshold_chars'] as int
        : AppSettingsSnapshot.defaultAiMessageCompressionThresholdChars;
    final aiToolResultCompressionThresholdChars =
        json['ai_tool_result_compression_threshold_chars'] is int &&
            (json['ai_tool_result_compression_threshold_chars'] as int) > 0
        ? json['ai_tool_result_compression_threshold_chars'] as int
        : AppSettingsSnapshot.defaultAiToolResultCompressionThresholdChars;
    final aiToolResultCompressionEnabled =
        json['ai_tool_result_compression_enabled'] is bool
        ? json['ai_tool_result_compression_enabled'] as bool
        : true;
    final aiToolResultCompressionHeadTailWindowChars =
        json['ai_tool_result_compression_head_tail_window_chars'] is int &&
            (json['ai_tool_result_compression_head_tail_window_chars'] as int) >=
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
    final aiWebFetchMaxResponseBytes = json['ai_web_fetch_max_response_bytes'] is int
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
    final aiWebFetchMaxCacheEntries = json['ai_web_fetch_max_cache_entries'] is int
        ? (json['ai_web_fetch_max_cache_entries'] as int).clamp(
            AppSettingsSnapshot.minAiWebFetchMaxCacheEntries,
            AppSettingsSnapshot.maxAiWebFetchMaxCacheEntries,
          )
        : AppSettingsSnapshot.defaultAiWebFetchMaxCacheEntries;
    final aiAttachmentMaxInlineImageDimension = json['ai_attachment_max_inline_image_dimension'] is int
        ? (json['ai_attachment_max_inline_image_dimension'] as int).clamp(
            AppSettingsSnapshot.minAiAttachmentMaxInlineImageDimension,
            AppSettingsSnapshot.maxAiAttachmentMaxInlineImageDimension,
          )
        : AppSettingsSnapshot.defaultAiAttachmentMaxInlineImageDimension;
    final aiAttachmentMaxTextRawBytes = json['ai_attachment_max_text_raw_bytes'] is int
        ? (json['ai_attachment_max_text_raw_bytes'] as int).clamp(
            AppSettingsSnapshot.minAiAttachmentMaxTextRawBytes,
            AppSettingsSnapshot.maxAiAttachmentMaxTextRawBytes,
          )
        : AppSettingsSnapshot.defaultAiAttachmentMaxTextRawBytes;
    final aiAttachmentMaxPdfRawBytes = json['ai_attachment_max_pdf_raw_bytes'] is int
        ? (json['ai_attachment_max_pdf_raw_bytes'] as int).clamp(
            AppSettingsSnapshot.minAiAttachmentMaxPdfRawBytes,
            AppSettingsSnapshot.maxAiAttachmentMaxPdfRawBytes,
          )
        : AppSettingsSnapshot.defaultAiAttachmentMaxPdfRawBytes;
    final aiAttachmentMaxImageRawBytes = json['ai_attachment_max_image_raw_bytes'] is int
        ? (json['ai_attachment_max_image_raw_bytes'] as int).clamp(
            AppSettingsSnapshot.minAiAttachmentMaxImageRawBytes,
            AppSettingsSnapshot.maxAiAttachmentMaxImageRawBytes,
          )
        : AppSettingsSnapshot.defaultAiAttachmentMaxImageRawBytes;
    final aiChatMaxStreamLineBufferBytes = json['ai_chat_max_stream_line_buffer_bytes'] is int
        ? (json['ai_chat_max_stream_line_buffer_bytes'] as int).clamp(
            AppSettingsSnapshot.minAiChatMaxStreamLineBufferBytes,
            AppSettingsSnapshot.maxAiChatMaxStreamLineBufferBytes,
          )
        : AppSettingsSnapshot.defaultAiChatMaxStreamLineBufferBytes;
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

    return AppSettingsSnapshot(
      themeMode: themeMode,
      themePreset: themePreset,
      language: language,
      skillsStoragePath: skillsStoragePath,
      mcpEnabled: mcpEnabled,
      mcpServersFilePath: mcpServersFilePath,
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
      aiImageSizeLimitBytes: aiImageSizeLimitBytes,
      aiWriteCommandConfirmationEnabled: aiWriteCommandConfirmationEnabled,
      aiAllowCommandRules: aiAllowCommandRules,
      aiDenyCommandRules: aiDenyCommandRules,
      aiConnectTimeoutSeconds: aiConnectTimeoutSeconds,
      aiResponseTimeoutSeconds: aiResponseTimeoutSeconds,
      aiStreamIdleTimeoutSeconds: aiStreamIdleTimeoutSeconds,
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
      builtinToolConfigs: builtinToolConfigs,
      telemetryDebugEnabled: telemetryDebugEnabled,
      telemetryCaptureRawPayload: telemetryCaptureRawPayload,
      telemetryCaptureEnvironment: telemetryCaptureEnvironment,
      telemetryMaxPayloadChars: telemetryMaxPayloadChars,
      selfLearningEnabled: selfLearningEnabled,
      selfLearningConcurrency: selfLearningConcurrency,
      showSelfLearningMessages: showSelfLearningMessages,
      cronAutoCleanupEnabled: cronAutoCleanupEnabled,
      cronAutoCleanupRetentionDays: cronAutoCleanupRetentionDays,
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
