import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../features/ai/model/ai_allow_command_rule.dart';
import '../../features/ai/model/ai_deny_command_rule.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../../shared/data/database_service.dart';
import '../model/app_language.dart';
import '../model/app_settings_snapshot.dart';
import '../model/dialog_animation_settings.dart';
import '../model/openhand_shortcut.dart';
import '../support/openhand_paths.dart';
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
          } catch (_) {
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
    await _db.insert(
      'app_settings',
      <String, Object?>{
        'key': _dbSettingsKey,
        'value': jsonStr,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------
  // JSON serialization for AppSettingsSnapshot
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _snapshotToJson(AppSettingsSnapshot snapshot) {
    return <String, Object?>{
      'version': 1,
      'theme_mode': _themeModeToStorage(snapshot.themeMode),
      'theme_preset': snapshot.themePreset.storageValue,
      'language': snapshot.language.storageValue,
      'skills_storage_path': snapshot.skillsStoragePath,
      'mcp_enabled': snapshot.mcpEnabled,
      'mcp_servers_file_path': snapshot.mcpServersFilePath,
      'memory_enabled': snapshot.memoryEnabled,
      'user_memory_file_path': snapshot.userMemoryFilePath,
      'ai_message_compression_threshold_chars':
          snapshot.aiMessageCompressionThresholdChars,
      'ai_single_round_tool_call_limit': snapshot.aiSingleRoundToolCallLimit,
      'ai_sequential_tool_round_limit': snapshot.aiSequentialToolRoundLimit,
      'ai_write_command_confirmation_enabled':
          snapshot.aiWriteCommandConfirmationEnabled,
      'ai_allow_command_rules': snapshot.aiAllowCommandRules
          .map((item) => item.toJson())
          .toList(growable: false),
      'ai_deny_command_rules': snapshot.aiDenyCommandRules
          .map((item) => item.toJson())
          .toList(growable: false),
      'selected_ai_model_id': snapshot.selectedAiModelId ?? '',
      'shortcut_bindings': <String, List<int>>{
        for (final entry in snapshot.shortcutBindings.entries)
          openHandShortcutActionStorageKey(entry.key):
              normalizeShortcutKeyIds(entry.value),
      },
      'dialog_animation_settings': snapshot.dialogAnimationSettings.toJson(),
      'menu_animation_settings': snapshot.menuAnimationSettings.toJson(),
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
    final aiMessageCompressionThresholdChars =
        json['ai_message_compression_threshold_chars'] is int &&
            (json['ai_message_compression_threshold_chars'] as int) > 0
        ? json['ai_message_compression_threshold_chars'] as int
        : AppSettingsSnapshot.defaultAiMessageCompressionThresholdChars;
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
          } catch (_) {}
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
          } catch (_) {}
        }
      }
    }

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
          } catch (_) {}
        }
      }
    }

    var selectedAiModelId = '${json['selected_ai_model_id'] ?? ''}'.trim();
    if (selectedAiModelId.isNotEmpty &&
        !aiModels.any((item) => item.id == selectedAiModelId)) {
      selectedAiModelId = aiModels.isEmpty ? '' : aiModels.first.id;
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

    return AppSettingsSnapshot(
      themeMode: themeMode,
      themePreset: themePreset,
      language: language,
      skillsStoragePath: skillsStoragePath,
      mcpEnabled: mcpEnabled,
      mcpServersFilePath: mcpServersFilePath,
      memoryEnabled: memoryEnabled,
      userMemoryFilePath: userMemoryFilePath,
      aiMessageCompressionThresholdChars: aiMessageCompressionThresholdChars,
      aiSingleRoundToolCallLimit: aiSingleRoundToolCallLimit,
      aiSequentialToolRoundLimit: aiSequentialToolRoundLimit,
      aiWriteCommandConfirmationEnabled: aiWriteCommandConfirmationEnabled,
      aiAllowCommandRules: aiAllowCommandRules,
      aiDenyCommandRules: aiDenyCommandRules,
      aiModels: aiModels,
      selectedAiModelId: selectedAiModelId.isEmpty ? null : selectedAiModelId,
      shortcutBindings: shortcutBindings,
      dialogAnimationSettings: dialogAnimationSettings,
      menuAnimationSettings: menuAnimationSettings,
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
