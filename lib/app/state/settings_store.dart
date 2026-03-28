import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../features/ai/model/ai_allow_command_rule.dart';
import '../../features/ai/model/ai_deny_command_rule.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../support/url_validation.dart';
import '../model/app_language.dart';
import '../model/app_settings_snapshot.dart';
import '../model/openhand_shortcut.dart';
import '../theme/openhand_theme_preset.dart';
import '../support/openhand_paths.dart';

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
  SettingsStore({String? settingsFilePath})
    : _settingsFilePath =
          settingsFilePath ?? OpenHandPaths.defaultSettingsFilePath();

  final String _settingsFilePath;

  String get settingsFilePath => _settingsFilePath;

  Future<SettingsLoadResult> load() async {
    final targetFile = File(_settingsFilePath);
    if (!await targetFile.exists()) {
      final migrated = await _migrateLegacySandboxSettings(targetFile);
      if (migrated) {
        return load();
      }
      final snapshot = AppSettingsSnapshot.defaults();
      try {
        await save(snapshot);
        return SettingsLoadResult(snapshot: snapshot);
      } catch (error) {
        return SettingsLoadResult(
          snapshot: snapshot,
          issue: SettingsPersistenceIssue(
            kind: SettingsPersistenceIssueKind.saveFailed,
            filePath: _settingsFilePath,
            detail: '$error',
          ),
        );
      }
    }

    final fallbackSnapshot = AppSettingsSnapshot.defaults();
    late final String rawContent;
    try {
      rawContent = await targetFile.readAsString();
    } catch (error) {
      return SettingsLoadResult(
        snapshot: fallbackSnapshot,
        issue: SettingsPersistenceIssue(
          kind: SettingsPersistenceIssueKind.saveFailed,
          filePath: _settingsFilePath,
          detail: '$error',
        ),
      );
    }

    try {
      final parsedDocument = _parse(rawContent);
      final sanitizedResult = _sanitize(parsedDocument);
      if (!sanitizedResult.didSanitize) {
        return SettingsLoadResult(snapshot: sanitizedResult.snapshot);
      }
      try {
        await save(sanitizedResult.snapshot);
        return SettingsLoadResult(
          snapshot: sanitizedResult.snapshot,
          issue: SettingsPersistenceIssue(
            kind: SettingsPersistenceIssueKind.sanitizedInvalidContent,
            filePath: _settingsFilePath,
          ),
        );
      } catch (error) {
        return SettingsLoadResult(
          snapshot: sanitizedResult.snapshot,
          issue: SettingsPersistenceIssue(
            kind: SettingsPersistenceIssueKind.saveFailed,
            filePath: _settingsFilePath,
            detail: '$error',
          ),
        );
      }
    } catch (error) {
      try {
        final backupPath = await _backupInvalidFile(targetFile);
        await save(fallbackSnapshot);
        return SettingsLoadResult(
          snapshot: fallbackSnapshot,
          issue: SettingsPersistenceIssue(
            kind: SettingsPersistenceIssueKind.recoveredInvalidFile,
            filePath: backupPath,
            detail: '$error',
          ),
        );
      } catch (saveError) {
        return SettingsLoadResult(
          snapshot: fallbackSnapshot,
          issue: SettingsPersistenceIssue(
            kind: SettingsPersistenceIssueKind.saveFailed,
            filePath: _settingsFilePath,
            detail: '$error\n$saveError',
          ),
        );
      }
    }
  }

  Future<void> save(AppSettingsSnapshot snapshot) async {
    final targetFile = File(_settingsFilePath);
    final targetDirectory = targetFile.parent;
    if (!await targetDirectory.exists()) {
      await targetDirectory.create(recursive: true);
    }
    final content = _encode(snapshot);
    await _writeAtomically(targetFile, content);
  }

  Future<bool> _migrateLegacySandboxSettings(File targetFile) async {
    final legacyPath = OpenHandPaths.legacySandboxSettingsFilePath();
    if (legacyPath == null || p.equals(legacyPath, targetFile.path)) {
      return false;
    }
    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) {
      return false;
    }
    final targetDirectory = targetFile.parent;
    if (!await targetDirectory.exists()) {
      await targetDirectory.create(recursive: true);
    }
    await legacyFile.copy(targetFile.path);
    return true;
  }

  Future<String> _backupInvalidFile(File sourceFile) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final backupPath = p.join(
      sourceFile.parent.path,
      'SETTINGS.invalid-$stamp.toml',
    );
    final backupFile = File(backupPath);
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    await sourceFile.rename(backupPath);
    return backupPath;
  }

  Future<void> _writeAtomically(File targetFile, String content) async {
    final tempFile = File('${targetFile.path}.tmp');
    final backupFile = File('${targetFile.path}.bak');

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await tempFile.writeAsString(content, flush: true);

    var movedExistingFile = false;
    try {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      if (await targetFile.exists()) {
        await targetFile.rename(backupFile.path);
        movedExistingFile = true;
      }
      await tempFile.rename(targetFile.path);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (_) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (movedExistingFile && await backupFile.exists()) {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await backupFile.rename(targetFile.path);
      }
      rethrow;
    }
  }

  _ParsedSettingsDocument _parse(String rawContent) {
    final rootValues = <String, Object?>{};
    final modelValues = <Map<String, Object?>>[];
    Map<String, Object?>? currentModel;

    for (final rawLine in const LineSplitter().convert(rawContent)) {
      final line = _stripInlineComment(rawLine).trim();
      if (line.isEmpty) {
        continue;
      }
      if (line == '[[ai_models]]') {
        currentModel = <String, Object?>{};
        modelValues.add(currentModel);
        continue;
      }
      if (line.startsWith('[') || line.endsWith(']')) {
        throw const FormatException('Unsupported TOML section found.');
      }

      final separatorIndex = line.indexOf('=');
      if (separatorIndex <= 0) {
        throw FormatException('Invalid setting entry: $line');
      }
      final key = line.substring(0, separatorIndex).trim();
      final rawValue = line.substring(separatorIndex + 1).trim();
      final value = _parseValue(rawValue);
      if (currentModel != null) {
        currentModel[key] = value;
      } else {
        rootValues[key] = value;
      }
    }

    return _ParsedSettingsDocument(
      rootValues: rootValues,
      modelValues: modelValues,
    );
  }

  Object? _parseValue(String rawValue) {
    if (rawValue.startsWith('"') && rawValue.endsWith('"')) {
      return jsonDecode(rawValue);
    }
    final intValue = int.tryParse(rawValue);
    if (intValue != null) {
      return intValue;
    }
    if (rawValue == 'true') {
      return true;
    }
    if (rawValue == 'false') {
      return false;
    }
    throw FormatException('Unsupported value: $rawValue');
  }

  String _stripInlineComment(String rawLine) {
    final buffer = StringBuffer();
    var inString = false;
    var escaping = false;
    for (final rune in rawLine.runes) {
      final char = String.fromCharCode(rune);
      if (escaping) {
        buffer.write(char);
        escaping = false;
        continue;
      }
      if (char == r'\') {
        buffer.write(char);
        escaping = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        buffer.write(char);
        continue;
      }
      if (char == '#' && !inString) {
        break;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  _SanitizedSettingsResult _sanitize(_ParsedSettingsDocument document) {
    var didSanitize = false;
    final rootValues = document.rootValues;
    final rawVersion = rootValues['version'];
    if (rawVersion != 1) {
      didSanitize = true;
    }

    final themeMode = _themeModeFromStorage(
      '${rootValues['theme_mode'] ?? ''}',
    );
    if ('${rootValues['theme_mode'] ?? ''}'.trim().isEmpty) {
      didSanitize = true;
    }
    final rawThemePreset = '${rootValues['theme_preset'] ?? ''}'.trim();
    final themePreset = OpenHandThemePreset.fromStorage(rawThemePreset);
    if (!OpenHandThemePreset.isValidStorageValue(rawThemePreset)) {
      didSanitize = true;
    }
    final language = appLanguageFromStorage('${rootValues['language'] ?? ''}');
    if ('${rootValues['language'] ?? ''}'.trim().isEmpty) {
      didSanitize = true;
    }

    final rawSkillsPath = '${rootValues['skills_storage_path'] ?? ''}';
    final skillsStoragePath = OpenHandPaths.normalizeUserPath(rawSkillsPath);
    if (rawSkillsPath.trim().isEmpty) {
      didSanitize = true;
    }
    final rawMcpEnabled = rootValues['mcp_enabled'];
    final mcpEnabled = rawMcpEnabled is bool ? rawMcpEnabled : true;
    if (rawMcpEnabled is! bool) {
      didSanitize = true;
    }
    final rawMcpServersFilePath =
        '${rootValues['mcp_servers_file_path'] ?? ''}';
    final mcpServersFilePath = OpenHandPaths.normalizePath(
      rawMcpServersFilePath,
      defaultPath: OpenHandPaths.defaultMcpServersFilePath(),
    );
    if (rawMcpServersFilePath.trim().isEmpty) {
      didSanitize = true;
    }
    final rawMemoryEnabled = rootValues['memory_enabled'];
    final memoryEnabled = rawMemoryEnabled is bool ? rawMemoryEnabled : true;
    if (rawMemoryEnabled is! bool) {
      didSanitize = true;
    }
    final rawUserMemoryFilePath = '${rootValues['user_memory_file'] ?? ''}';
    final normalizedRawUserMemoryFilePath = rawUserMemoryFilePath.trim().isEmpty
        ? ''
        : OpenHandPaths.normalizePath(
            rawUserMemoryFilePath,
            defaultPath: OpenHandPaths.defaultUserMemoryFilePath(),
          );
    final shouldMigrateLegacyUserMemoryPath =
        normalizedRawUserMemoryFilePath.isNotEmpty &&
        p.equals(
          normalizedRawUserMemoryFilePath,
          OpenHandPaths.legacyDefaultUserMemoryFilePath(),
        );
    final userMemoryFilePath = shouldMigrateLegacyUserMemoryPath
        ? OpenHandPaths.defaultUserMemoryFilePath()
        : OpenHandPaths.normalizePath(
            rawUserMemoryFilePath,
            defaultPath: OpenHandPaths.defaultUserMemoryFilePath(),
          );
    if (rawUserMemoryFilePath.trim().isEmpty ||
        shouldMigrateLegacyUserMemoryPath) {
      didSanitize = true;
    }
    final rawCompressionThreshold =
        rootValues['ai_message_compression_threshold_chars'];
    final aiMessageCompressionThresholdChars =
        rawCompressionThreshold is int && rawCompressionThreshold > 0
        ? rawCompressionThreshold
        : AppSettingsSnapshot.defaultAiMessageCompressionThresholdChars;
    if (rawCompressionThreshold is! int || rawCompressionThreshold <= 0) {
      didSanitize = true;
    }
    final rawSingleRoundToolCallLimit =
        rootValues['ai_single_round_tool_call_limit'];
    final aiSingleRoundToolCallLimit =
        rawSingleRoundToolCallLimit is int && rawSingleRoundToolCallLimit > 0
        ? rawSingleRoundToolCallLimit
        : AppSettingsSnapshot.defaultAiSingleRoundToolCallLimit;
    if (rawSingleRoundToolCallLimit is! int ||
        rawSingleRoundToolCallLimit <= 0) {
      didSanitize = true;
    }
    final rawSequentialToolRoundLimit =
        rootValues['ai_sequential_tool_round_limit'];
    final aiSequentialToolRoundLimit =
        rawSequentialToolRoundLimit is int && rawSequentialToolRoundLimit > 0
        ? rawSequentialToolRoundLimit
        : AppSettingsSnapshot.defaultAiSequentialToolRoundLimit;
    if (rawSequentialToolRoundLimit is! int ||
        rawSequentialToolRoundLimit <= 0) {
      didSanitize = true;
    }
    final rawWriteCommandConfirmationEnabled =
        rootValues['ai_write_command_confirmation_enabled'];
    final aiWriteCommandConfirmationEnabled =
        rawWriteCommandConfirmationEnabled is bool
        ? rawWriteCommandConfirmationEnabled
        : true;
    if (rawWriteCommandConfirmationEnabled is! bool) {
      didSanitize = true;
    }
    final rawAllowCommandRules =
        '${rootValues['ai_allow_command_rules'] ?? ''}';
    final aiAllowCommandRules = <AiAllowCommandRule>[];
    if (rawAllowCommandRules.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAllowCommandRules);
        if (decoded is List) {
          final seenRuleIds = <String>{};
          for (final item in decoded) {
            if (item is! Map) {
              didSanitize = true;
              continue;
            }
            final rule = AiAllowCommandRule.fromJson(
              Map<String, Object?>.from(item),
            );
            if (rule.id.isEmpty || rule.pattern.trim().isEmpty) {
              didSanitize = true;
              continue;
            }
            if (!seenRuleIds.add(rule.id)) {
              didSanitize = true;
              continue;
            }
            aiAllowCommandRules.add(rule);
          }
        } else {
          didSanitize = true;
        }
      } catch (_) {
        didSanitize = true;
      }
    }
    final rawDenyCommandRules = '${rootValues['ai_deny_command_rules'] ?? ''}';
    final aiDenyCommandRules = <AiDenyCommandRule>[];
    if (rawDenyCommandRules.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawDenyCommandRules);
        if (decoded is List) {
          final seenRuleIds = <String>{};
          for (final item in decoded) {
            if (item is! Map) {
              didSanitize = true;
              continue;
            }
            final rule = AiDenyCommandRule.fromJson(
              Map<String, Object?>.from(item),
            );
            if (rule.id.isEmpty || rule.pattern.trim().isEmpty) {
              didSanitize = true;
              continue;
            }
            if (!seenRuleIds.add(rule.id)) {
              didSanitize = true;
              continue;
            }
            aiDenyCommandRules.add(rule);
          }
        } else {
          didSanitize = true;
        }
      } catch (_) {
        didSanitize = true;
      }
    }

    final aiModels = <AiModelConfig>[];
    final seenAiModelIds = <String>{};
    for (final rawModel in document.modelValues) {
      final rawAuthScheme = '${rawModel['auth_scheme'] ?? ''}'.trim();
      final rawProtocolType = '${rawModel['protocol_type'] ?? ''}'.trim();
      final rawMaxContextTokens = rawModel['max_context_tokens'];
      final model = AiModelConfig.fromJson(rawModel);
      final isValid =
          model.id.trim().isNotEmpty &&
          model.modelId.trim().isNotEmpty &&
          isValidHttpUrl(model.baseUrl);
      if (!isValid) {
        didSanitize = true;
        continue;
      }
      if (!seenAiModelIds.add(model.id)) {
        didSanitize = true;
        continue;
      }
      if (!AiAuthScheme.isValidStorageValue(rawAuthScheme)) {
        didSanitize = true;
      }
      if (!AiProtocolType.isValidStorageValue(rawProtocolType)) {
        didSanitize = true;
      }
      if (!_isValidNullablePositiveInt(rawMaxContextTokens)) {
        didSanitize = true;
      }
      aiModels.add(model);
    }

    var selectedAiModelId = '${rootValues['selected_ai_model_id'] ?? ''}'
        .trim();
    if (selectedAiModelId.isEmpty) {
      selectedAiModelId = aiModels.isEmpty ? '' : aiModels.first.id;
      if (aiModels.isNotEmpty) {
        didSanitize = true;
      }
    }
    if (selectedAiModelId.isNotEmpty &&
        !aiModels.any((item) => item.id == selectedAiModelId)) {
      selectedAiModelId = aiModels.isEmpty ? '' : aiModels.first.id;
      didSanitize = true;
    }
    final rawShortcutBindings = '${rootValues['shortcut_bindings'] ?? ''}';
    var shortcutBindings = defaultOpenHandShortcutBindings();
    if (rawShortcutBindings.trim().isEmpty) {
      didSanitize = true;
    } else {
      try {
        final decoded = jsonDecode(rawShortcutBindings);
        if (decoded is Map) {
          final parsedBindings = <OpenHandShortcutAction, List<int>>{};
          for (final entry in decoded.entries) {
            final action = openHandShortcutActionFromStorageKey('${entry.key}');
            if (action == null) {
              didSanitize = true;
              continue;
            }
            final value = entry.value;
            if (value is! List) {
              didSanitize = true;
              continue;
            }
            final normalizedKeyIds = normalizeShortcutKeyIds(
              value.whereType<num>().map((item) => item.toInt()),
            );
            if (!isValidShortcutBinding(normalizedKeyIds)) {
              didSanitize = true;
              continue;
            }
            parsedBindings[action] = normalizedKeyIds;
          }
          for (final action in OpenHandShortcutAction.values) {
            if (!parsedBindings.containsKey(action)) {
              didSanitize = true;
            }
          }
          shortcutBindings = <OpenHandShortcutAction, List<int>>{
            ...defaultOpenHandShortcutBindings(),
            ...parsedBindings,
          };
        } else {
          didSanitize = true;
        }
      } catch (_) {
        didSanitize = true;
      }
    }

    return _SanitizedSettingsResult(
      didSanitize: didSanitize,
      snapshot: AppSettingsSnapshot(
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
      ),
    );
  }

  String _encode(AppSettingsSnapshot snapshot) {
    final buffer = StringBuffer()
      ..writeln('version = 1')
      ..writeln(
        'theme_mode = ${jsonEncode(_themeModeToStorage(snapshot.themeMode))}',
      )
      ..writeln(
        'theme_preset = ${jsonEncode(snapshot.themePreset.storageValue)}',
      )
      ..writeln('language = ${jsonEncode(snapshot.language.storageValue)}')
      ..writeln(
        'skills_storage_path = ${jsonEncode(snapshot.skillsStoragePath)}',
      )
      ..writeln('mcp_enabled = ${snapshot.mcpEnabled}')
      ..writeln(
        'mcp_servers_file_path = ${jsonEncode(snapshot.mcpServersFilePath)}',
      )
      ..writeln('memory_enabled = ${snapshot.memoryEnabled}')
      ..writeln('user_memory_file = ${jsonEncode(snapshot.userMemoryFilePath)}')
      ..writeln(
        'ai_message_compression_threshold_chars = ${snapshot.aiMessageCompressionThresholdChars}',
      )
      ..writeln(
        'ai_single_round_tool_call_limit = ${snapshot.aiSingleRoundToolCallLimit}',
      )
      ..writeln(
        'ai_sequential_tool_round_limit = ${snapshot.aiSequentialToolRoundLimit}',
      )
      ..writeln(
        'ai_write_command_confirmation_enabled = ${snapshot.aiWriteCommandConfirmationEnabled}',
      )
      ..writeln(
        'ai_allow_command_rules = ${jsonEncode(jsonEncode(snapshot.aiAllowCommandRules.map((item) => item.toJson()).toList(growable: false)))}',
      )
      ..writeln(
        'ai_deny_command_rules = ${jsonEncode(jsonEncode(snapshot.aiDenyCommandRules.map((item) => item.toJson()).toList(growable: false)))}',
      )
      ..writeln(
        'selected_ai_model_id = ${jsonEncode(snapshot.selectedAiModelId ?? '')}',
      )
      ..writeln(
        'shortcut_bindings = ${jsonEncode(jsonEncode(<String, List<int>>{for (final entry in snapshot.shortcutBindings.entries) openHandShortcutActionStorageKey(entry.key): normalizeShortcutKeyIds(entry.value)}))}',
      );

    for (final model in snapshot.aiModels) {
      buffer
        ..writeln()
        ..writeln('[[ai_models]]')
        ..writeln('id = ${jsonEncode(model.id)}')
        ..writeln('base_url = ${jsonEncode(model.normalizedBaseUrl)}')
        ..writeln('auth_scheme = ${jsonEncode(model.authScheme.storageValue)}')
        ..writeln('token = ${jsonEncode(model.token)}')
        ..writeln('model_id = ${jsonEncode(model.modelId.trim())}')
        ..writeln(
          'protocol_type = ${jsonEncode(model.protocolType.storageValue)}',
        );
      if (model.maxContextTokens != null) {
        buffer.writeln('max_context_tokens = ${model.maxContextTokens}');
      }
    }

    return buffer.toString();
  }
}

class _ParsedSettingsDocument {
  const _ParsedSettingsDocument({
    required this.rootValues,
    required this.modelValues,
  });

  final Map<String, Object?> rootValues;
  final List<Map<String, Object?>> modelValues;
}

class _SanitizedSettingsResult {
  const _SanitizedSettingsResult({
    required this.didSanitize,
    required this.snapshot,
  });

  final bool didSanitize;
  final AppSettingsSnapshot snapshot;
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

bool _isValidNullablePositiveInt(Object? value) {
  if (value == null) {
    return true;
  }
  if (value is int) {
    return value > 0;
  }
  if (value is num) {
    return value > 0 && value == value.toInt();
  }
  final parsed = int.tryParse('$value'.trim());
  return parsed != null && parsed > 0;
}
