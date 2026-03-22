import 'package:flutter/material.dart';

import '../../features/ai/model/ai_model_config.dart';
import '../model/app_language.dart';
import '../support/openhand_paths.dart';
import '../theme/openhand_theme_preset.dart';

class AppSettingsSnapshot {
  const AppSettingsSnapshot({
    required this.themeMode,
    required this.themePreset,
    required this.language,
    required this.skillsStoragePath,
    required this.mcpEnabled,
    required this.mcpServersFilePath,
    required this.memoryEnabled,
    required this.userMemoryFilePath,
    required this.aiModels,
    required this.selectedAiModelId,
  });

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
      aiModels: const <AiModelConfig>[],
      selectedAiModelId: null,
    );
  }

  final ThemeMode themeMode;
  final OpenHandThemePreset themePreset;
  final AppLanguage language;
  final String skillsStoragePath;
  final bool mcpEnabled;
  final String mcpServersFilePath;
  final bool memoryEnabled;
  final String userMemoryFilePath;
  final List<AiModelConfig> aiModels;
  final String? selectedAiModelId;

  AppSettingsSnapshot copyWith({
    ThemeMode? themeMode,
    OpenHandThemePreset? themePreset,
    AppLanguage? language,
    String? skillsStoragePath,
    bool? mcpEnabled,
    String? mcpServersFilePath,
    bool? memoryEnabled,
    String? userMemoryFilePath,
    List<AiModelConfig>? aiModels,
    String? selectedAiModelId,
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
      aiModels: aiModels ?? this.aiModels,
      selectedAiModelId: clearSelectedAiModelId
          ? null
          : selectedAiModelId ?? this.selectedAiModelId,
    );
  }
}
