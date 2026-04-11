import 'package:flutter/material.dart';

import '../../features/ai/model/ai_allow_command_rule.dart';
import '../../features/ai/model/ai_deny_command_rule.dart';
import '../../features/ai/model/ai_lsp_language_settings.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../model/app_language.dart';
import '../model/dialog_animation_settings.dart';
import '../support/openhand_paths.dart';
import '../theme/openhand_theme_preset.dart';
import 'openhand_shortcut.dart';

class AppSettingsSnapshot {
  factory AppSettingsSnapshot.defaults() {
    return AppSettingsSnapshot(
      themeMode: ThemeMode.system,
      themePreset: OpenHandThemePreset.deepSeaBlue,
      language: AppLanguage.simplifiedChinese,
      skillsStoragePath: OpenHandPaths.defaultSkillsDirectoryPath(),
      mcpEnabled: true,
      mcpServersFilePath: OpenHandPaths.defaultMcpServersFilePath(),
      memoryEnabled: true,
      userMemoryFilePath: OpenHandPaths.defaultUserMemoryFilePath(),
      editorLspSettings: const <String, AiLspLanguageSettings>{},
      aiMessageCompressionThresholdChars:
          defaultAiMessageCompressionThresholdChars,
      aiSingleRoundToolCallLimit: defaultAiSingleRoundToolCallLimit,
      aiSequentialToolRoundLimit: defaultAiSequentialToolRoundLimit,
      aiWriteCommandConfirmationEnabled: true,
      aiAllowCommandRules: const <AiAllowCommandRule>[],
      aiDenyCommandRules: const <AiDenyCommandRule>[],
      aiModels: const <AiModelConfig>[],
      selectedAiModelId: null,
      shortcutBindings: defaultOpenHandShortcutBindings(),
      dialogAnimationSettings: const DialogAnimationSettings(),
      menuAnimationSettings: const DialogAnimationSettings(),
      panelAnimationSettings: const DialogAnimationSettings(),
    );
  }
  const AppSettingsSnapshot({
    required this.themeMode,
    required this.themePreset,
    required this.language,
    required this.skillsStoragePath,
    required this.mcpEnabled,
    required this.mcpServersFilePath,
    required this.memoryEnabled,
    required this.userMemoryFilePath,
    required this.editorLspSettings,
    required this.aiMessageCompressionThresholdChars,
    required this.aiSingleRoundToolCallLimit,
    required this.aiSequentialToolRoundLimit,
    required this.aiWriteCommandConfirmationEnabled,
    required this.aiAllowCommandRules,
    required this.aiDenyCommandRules,
    required this.aiModels,
    required this.selectedAiModelId,
    required this.shortcutBindings,
    required this.dialogAnimationSettings,
    required this.menuAnimationSettings,
    required this.panelAnimationSettings,
  });

  static const int defaultAiMessageCompressionThresholdChars = 12000;
  static const int defaultAiSingleRoundToolCallLimit = 40;
  static const int defaultAiSequentialToolRoundLimit = 24;

  final ThemeMode themeMode;
  final OpenHandThemePreset themePreset;
  final AppLanguage language;
  final String skillsStoragePath;
  final bool mcpEnabled;
  final String mcpServersFilePath;
  final bool memoryEnabled;
  final String userMemoryFilePath;
  final Map<String, AiLspLanguageSettings> editorLspSettings;
  final int aiMessageCompressionThresholdChars;
  final int aiSingleRoundToolCallLimit;
  final int aiSequentialToolRoundLimit;
  final bool aiWriteCommandConfirmationEnabled;
  final List<AiAllowCommandRule> aiAllowCommandRules;
  final List<AiDenyCommandRule> aiDenyCommandRules;
  final List<AiModelConfig> aiModels;
  final String? selectedAiModelId;
  final Map<OpenHandShortcutAction, List<int>> shortcutBindings;
  final DialogAnimationSettings dialogAnimationSettings;
  final DialogAnimationSettings menuAnimationSettings;
  final DialogAnimationSettings panelAnimationSettings;

  AppSettingsSnapshot copyWith({
    ThemeMode? themeMode,
    OpenHandThemePreset? themePreset,
    AppLanguage? language,
    String? skillsStoragePath,
    bool? mcpEnabled,
    String? mcpServersFilePath,
    bool? memoryEnabled,
    String? userMemoryFilePath,
    Map<String, AiLspLanguageSettings>? editorLspSettings,
    int? aiMessageCompressionThresholdChars,
    int? aiSingleRoundToolCallLimit,
    int? aiSequentialToolRoundLimit,
    bool? aiWriteCommandConfirmationEnabled,
    List<AiAllowCommandRule>? aiAllowCommandRules,
    List<AiDenyCommandRule>? aiDenyCommandRules,
    List<AiModelConfig>? aiModels,
    String? selectedAiModelId,
    Map<OpenHandShortcutAction, List<int>>? shortcutBindings,
    DialogAnimationSettings? dialogAnimationSettings,
    DialogAnimationSettings? menuAnimationSettings,
    DialogAnimationSettings? panelAnimationSettings,
    bool clearSelectedAiModelId = false,
  }) {
    return AppSettingsSnapshot(
      themeMode: themeMode ?? this.themeMode,
      themePreset: themePreset ?? this.themePreset,
      language: language ?? this.language,
      skillsStoragePath: skillsStoragePath ?? this.skillsStoragePath,
      mcpEnabled: mcpEnabled ?? this.mcpEnabled,
      mcpServersFilePath: mcpServersFilePath ?? this.mcpServersFilePath,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      userMemoryFilePath: userMemoryFilePath ?? this.userMemoryFilePath,
      editorLspSettings: editorLspSettings ?? this.editorLspSettings,
      aiMessageCompressionThresholdChars:
          aiMessageCompressionThresholdChars ??
          this.aiMessageCompressionThresholdChars,
      aiSingleRoundToolCallLimit:
          aiSingleRoundToolCallLimit ?? this.aiSingleRoundToolCallLimit,
      aiSequentialToolRoundLimit:
          aiSequentialToolRoundLimit ?? this.aiSequentialToolRoundLimit,
      aiWriteCommandConfirmationEnabled:
          aiWriteCommandConfirmationEnabled ??
          this.aiWriteCommandConfirmationEnabled,
      aiAllowCommandRules: aiAllowCommandRules ?? this.aiAllowCommandRules,
      aiDenyCommandRules: aiDenyCommandRules ?? this.aiDenyCommandRules,
      aiModels: aiModels ?? this.aiModels,
      selectedAiModelId: clearSelectedAiModelId
          ? null
          : selectedAiModelId ?? this.selectedAiModelId,
      shortcutBindings: shortcutBindings ?? this.shortcutBindings,
      dialogAnimationSettings:
          dialogAnimationSettings ?? this.dialogAnimationSettings,
      menuAnimationSettings:
          menuAnimationSettings ?? this.menuAnimationSettings,
      panelAnimationSettings:
          panelAnimationSettings ?? this.panelAnimationSettings,
    );
  }
}
