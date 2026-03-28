import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../model/openhand_shortcut.dart';
import '../../features/ai/model/ai_allow_command_rule.dart';
import '../../features/ai/model/ai_deny_command_rule.dart';
import '../../features/ai/model/ai_model_config.dart';
import '../model/app_language.dart';
import '../model/app_settings_snapshot.dart';
import '../support/openhand_paths.dart';
import '../theme/openhand_theme_preset.dart';
import 'settings_store.dart';

enum _MutationDisposition { apply, successNoChange, reject }

class SettingsController extends ChangeNotifier {
  static const Uuid _uuid = Uuid();

  SettingsController._({
    required SettingsStore store,
    required AppSettingsSnapshot snapshot,
    SettingsPersistenceIssue? persistenceIssue,
  }) : _store = store,
       _themeMode = snapshot.themeMode,
       _themePreset = snapshot.themePreset,
       _language = snapshot.language,
       _skillsStoragePath = snapshot.skillsStoragePath,
       _mcpEnabled = snapshot.mcpEnabled,
       _mcpServersFilePath = snapshot.mcpServersFilePath,
       _memoryEnabled = snapshot.memoryEnabled,
       _userMemoryFilePath = snapshot.userMemoryFilePath,
       _aiMessageCompressionThresholdChars =
           snapshot.aiMessageCompressionThresholdChars,
       _aiSingleRoundToolCallLimit = snapshot.aiSingleRoundToolCallLimit,
       _aiSequentialToolRoundLimit = snapshot.aiSequentialToolRoundLimit,
       _aiWriteCommandConfirmationEnabled =
           snapshot.aiWriteCommandConfirmationEnabled,
       _aiAllowCommandRules = List<AiAllowCommandRule>.from(
         snapshot.aiAllowCommandRules,
       ),
       _aiDenyCommandRules = List<AiDenyCommandRule>.from(
         snapshot.aiDenyCommandRules,
       ),
       _aiModels = List<AiModelConfig>.from(snapshot.aiModels),
       _selectedAiModelId = snapshot.selectedAiModelId,
       _shortcutBindings = _cloneShortcutBindings(snapshot.shortcutBindings),
       _persistenceIssue = persistenceIssue;

  static Future<SettingsController> create({SettingsStore? store}) async {
    final effectiveStore = store ?? SettingsStore();
    final loadResult = await effectiveStore.load();
    return SettingsController._(
      store: effectiveStore,
      snapshot: loadResult.snapshot,
      persistenceIssue: loadResult.issue,
    );
  }

  final SettingsStore _store;
  ThemeMode _themeMode;
  OpenHandThemePreset _themePreset;
  AppLanguage _language;
  String _skillsStoragePath;
  bool _mcpEnabled;
  String _mcpServersFilePath;
  bool _memoryEnabled;
  String _userMemoryFilePath;
  int _aiMessageCompressionThresholdChars;
  int _aiSingleRoundToolCallLimit;
  int _aiSequentialToolRoundLimit;
  bool _aiWriteCommandConfirmationEnabled;
  List<AiAllowCommandRule> _aiAllowCommandRules;
  List<AiDenyCommandRule> _aiDenyCommandRules;
  List<AiModelConfig> _aiModels;
  String? _selectedAiModelId;
  Map<OpenHandShortcutAction, List<int>> _shortcutBindings;
  SettingsPersistenceIssue? _persistenceIssue;
  bool _isDisposed = false;
  Future<void> _mutationQueue = Future<void>.value();

  ThemeMode get themeMode => _themeMode;
  OpenHandThemePreset get themePreset => _themePreset;
  AppLanguage get language => _language;
  Locale get locale => _language.locale;
  String get skillsStoragePath => _skillsStoragePath;
  String get displaySkillsStoragePath =>
      OpenHandPaths.shortenHomePath(_skillsStoragePath);
  String get defaultSkillsStoragePath =>
      OpenHandPaths.defaultSkillsDirectoryPath();
  String get defaultSkillsStorageLabel =>
      OpenHandPaths.defaultSkillsDirectoryLabel;
  bool get mcpEnabled => _mcpEnabled;
  String get mcpServersFilePath => _mcpServersFilePath;
  String get displayMcpServersFilePath =>
      OpenHandPaths.shortenHomePath(_mcpServersFilePath);
  String get defaultMcpServersFilePath =>
      OpenHandPaths.defaultMcpServersFilePath();
  String get defaultMcpServersFileLabel =>
      OpenHandPaths.defaultMcpServersFileLabel;
  bool get memoryEnabled => _memoryEnabled;
  String get userMemoryFilePath => _userMemoryFilePath;
  int get aiMessageCompressionThresholdChars =>
      _aiMessageCompressionThresholdChars;
  int get aiSingleRoundToolCallLimit => _aiSingleRoundToolCallLimit;
  int get aiSequentialToolRoundLimit => _aiSequentialToolRoundLimit;
  bool get aiWriteCommandConfirmationEnabled =>
      _aiWriteCommandConfirmationEnabled;
  List<AiAllowCommandRule> get aiAllowCommandRules =>
      List<AiAllowCommandRule>.unmodifiable(_aiAllowCommandRules);
  List<AiDenyCommandRule> get aiDenyCommandRules =>
      List<AiDenyCommandRule>.unmodifiable(_aiDenyCommandRules);
  String get displayUserMemoryFilePath =>
      OpenHandPaths.shortenHomePath(_userMemoryFilePath);
  String get defaultUserMemoryFilePath =>
      OpenHandPaths.defaultUserMemoryFilePath();
  String get defaultUserMemoryFileLabel =>
      OpenHandPaths.defaultUserMemoryFileLabel();
  String get settingsFilePath => _store.settingsFilePath;
  String get displaySettingsFilePath =>
      OpenHandPaths.shortenHomePath(_store.settingsFilePath);
  List<AiModelConfig> get aiModels =>
      List<AiModelConfig>.unmodifiable(_aiModels);
  String? get selectedAiModelId => _selectedAiModelId;
  Map<OpenHandShortcutAction, List<int>> get shortcutBindings =>
      _cloneShortcutBindings(_shortcutBindings);
  SettingsPersistenceIssue? get persistenceIssue => _persistenceIssue;

  @override
  void notifyListeners() {
    if (_isDisposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  AiModelConfig? get selectedAiModel {
    final selectedAiModelId = _selectedAiModelId;
    if (selectedAiModelId == null) {
      return null;
    }
    for (final item in _aiModels) {
      if (item.id == selectedAiModelId) {
        return item;
      }
    }
    return null;
  }

  void clearPersistenceIssue() {
    if (_persistenceIssue == null) {
      return;
    }
    _persistenceIssue = null;
    notifyListeners();
  }

  Future<bool> updateThemeMode(ThemeMode value) async {
    return _commitMutation(() {
      if (_themeMode == value) {
        return _MutationDisposition.successNoChange;
      }
      _themeMode = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateThemePreset(OpenHandThemePreset value) async {
    return _commitMutation(() {
      if (_themePreset == value) {
        return _MutationDisposition.successNoChange;
      }
      _themePreset = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateLanguage(AppLanguage value) async {
    return _commitMutation(() {
      if (_language == value) {
        return _MutationDisposition.successNoChange;
      }
      _language = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateSkillsStoragePath(String value) async {
    final normalizedPath = OpenHandPaths.normalizeUserPath(value);
    return _commitMutation(() {
      if (_skillsStoragePath == normalizedPath) {
        return _MutationDisposition.successNoChange;
      }
      _skillsStoragePath = normalizedPath;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateMcpEnabled(bool value) async {
    return _commitMutation(() {
      if (_mcpEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _mcpEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateMemoryEnabled(bool value) async {
    return _commitMutation(() {
      if (_memoryEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _memoryEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateUserMemoryFilePath(String value) async {
    final normalizedPath = OpenHandPaths.normalizePath(
      value,
      defaultPath: OpenHandPaths.defaultUserMemoryFilePath(),
    );
    return _commitMutation(() {
      if (_userMemoryFilePath == normalizedPath) {
        return _MutationDisposition.successNoChange;
      }
      _userMemoryFilePath = normalizedPath;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiMessageCompressionThresholdChars(int value) async {
    final normalizedValue = value <= 0
        ? AppSettingsSnapshot.defaultAiMessageCompressionThresholdChars
        : value;
    return _commitMutation(() {
      if (_aiMessageCompressionThresholdChars == normalizedValue) {
        return _MutationDisposition.successNoChange;
      }
      _aiMessageCompressionThresholdChars = normalizedValue;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiSingleRoundToolCallLimit(int value) async {
    final normalizedValue = value <= 0
        ? AppSettingsSnapshot.defaultAiSingleRoundToolCallLimit
        : value;
    return _commitMutation(() {
      if (_aiSingleRoundToolCallLimit == normalizedValue) {
        return _MutationDisposition.successNoChange;
      }
      _aiSingleRoundToolCallLimit = normalizedValue;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiSequentialToolRoundLimit(int value) async {
    final normalizedValue = value <= 0
        ? AppSettingsSnapshot.defaultAiSequentialToolRoundLimit
        : value;
    return _commitMutation(() {
      if (_aiSequentialToolRoundLimit == normalizedValue) {
        return _MutationDisposition.successNoChange;
      }
      _aiSequentialToolRoundLimit = normalizedValue;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiWriteCommandConfirmationEnabled(bool value) async {
    return _commitMutation(() {
      if (_aiWriteCommandConfirmationEnabled == value) {
        return _MutationDisposition.successNoChange;
      }
      _aiWriteCommandConfirmationEnabled = value;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> addAiAllowCommandRule(AiAllowCommandRule rule) async {
    return _commitMutation(() {
      if (_aiAllowCommandRules.any((item) => item.id == rule.id)) {
        return _MutationDisposition.reject;
      }
      _aiAllowCommandRules = <AiAllowCommandRule>[
        ..._aiAllowCommandRules,
        rule,
      ];
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiAllowCommandRule(AiAllowCommandRule rule) async {
    return _commitMutation(() {
      final index = _aiAllowCommandRules.indexWhere(
        (item) => item.id == rule.id,
      );
      if (index == -1) {
        return _MutationDisposition.reject;
      }
      final updatedRules = List<AiAllowCommandRule>.from(_aiAllowCommandRules);
      updatedRules[index] = rule;
      _aiAllowCommandRules = updatedRules;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> deleteAiAllowCommandRule(String id) async {
    return _commitMutation(() {
      final updatedRules = _aiAllowCommandRules
          .where((item) => item.id != id)
          .toList(growable: false);
      if (updatedRules.length == _aiAllowCommandRules.length) {
        return _MutationDisposition.successNoChange;
      }
      _aiAllowCommandRules = updatedRules;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> addAiDenyCommandRule(AiDenyCommandRule rule) async {
    return _commitMutation(() {
      if (_aiDenyCommandRules.any((item) => item.id == rule.id)) {
        return _MutationDisposition.reject;
      }
      _aiDenyCommandRules = <AiDenyCommandRule>[..._aiDenyCommandRules, rule];
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateAiDenyCommandRule(AiDenyCommandRule rule) async {
    return _commitMutation(() {
      final index = _aiDenyCommandRules.indexWhere(
        (item) => item.id == rule.id,
      );
      if (index == -1) {
        return _MutationDisposition.reject;
      }
      final updatedRules = List<AiDenyCommandRule>.from(_aiDenyCommandRules);
      updatedRules[index] = rule;
      _aiDenyCommandRules = updatedRules;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> deleteAiDenyCommandRule(String id) async {
    return _commitMutation(() {
      final updatedRules = _aiDenyCommandRules
          .where((item) => item.id != id)
          .toList(growable: false);
      if (updatedRules.length == _aiDenyCommandRules.length) {
        return _MutationDisposition.successNoChange;
      }
      _aiDenyCommandRules = updatedRules;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> saveAiModel(AiModelConfig value) async {
    return _commitMutation(() {
      final updatedModels = List<AiModelConfig>.from(_aiModels);
      final index = updatedModels.indexWhere((item) => item.id == value.id);
      if (index == -1) {
        updatedModels.add(value);
      } else {
        updatedModels[index] = value;
      }
      final nextSelectedModelId = _selectedAiModelId ?? value.id;
      _aiModels = updatedModels;
      _selectedAiModelId =
          updatedModels.any((item) => item.id == nextSelectedModelId)
          ? nextSelectedModelId
          : value.id;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> deleteAiModel(String id) async {
    return _commitMutation(() {
      final updatedModels = _aiModels.where((item) => item.id != id).toList();
      if (updatedModels.length == _aiModels.length) {
        return _MutationDisposition.successNoChange;
      }
      _aiModels = updatedModels;
      if (_selectedAiModelId == id) {
        _selectedAiModelId = _aiModels.isEmpty ? null : _aiModels.first.id;
      }
      return _MutationDisposition.apply;
    });
  }

  Future<bool> moveAiModel(int fromIndex, int toIndex) async {
    return _commitMutation(() {
      if (fromIndex < 0 ||
          toIndex < 0 ||
          fromIndex >= _aiModels.length ||
          toIndex >= _aiModels.length ||
          fromIndex == toIndex) {
        return _MutationDisposition.successNoChange;
      }
      final updatedModels = List<AiModelConfig>.from(_aiModels);
      final model = updatedModels.removeAt(fromIndex);
      updatedModels.insert(toIndex, model);
      _aiModels = updatedModels;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateSelectedAiModel(String? id) async {
    return _commitMutation(() {
      if (id != null && !_aiModels.any((item) => item.id == id)) {
        return _MutationDisposition.reject;
      }
      if (_selectedAiModelId == id) {
        return _MutationDisposition.successNoChange;
      }
      _selectedAiModelId = id;
      return _MutationDisposition.apply;
    });
  }

  Future<bool> updateShortcutBinding(
    OpenHandShortcutAction action,
    List<int> keyIds,
  ) async {
    final normalizedKeyIds = normalizeShortcutKeyIds(keyIds);
    if (!isValidShortcutBinding(normalizedKeyIds)) {
      return false;
    }
    return _commitMutation(() {
      final currentKeyIds = _shortcutBindings[action] ?? const <int>[];
      if (_sameIntList(currentKeyIds, normalizedKeyIds)) {
        return _MutationDisposition.successNoChange;
      }
      _shortcutBindings = <OpenHandShortcutAction, List<int>>{
        ..._shortcutBindings,
        action: normalizedKeyIds,
      };
      return _MutationDisposition.apply;
    });
  }

  Future<bool> resetShortcutBinding(OpenHandShortcutAction action) async {
    return updateShortcutBinding(
      action,
      defaultOpenHandShortcutBindings()[action] ?? const <int>[],
    );
  }

  String createAiModelId() {
    return _uuid.v4();
  }

  String createAiDenyCommandRuleId() {
    return _uuid.v4();
  }

  String createAiAllowCommandRuleId() {
    return _uuid.v4();
  }

  AppSettingsSnapshot _snapshot() {
    return AppSettingsSnapshot(
      themeMode: _themeMode,
      themePreset: _themePreset,
      language: _language,
      skillsStoragePath: _skillsStoragePath,
      mcpEnabled: _mcpEnabled,
      mcpServersFilePath: _mcpServersFilePath,
      memoryEnabled: _memoryEnabled,
      userMemoryFilePath: _userMemoryFilePath,
      aiMessageCompressionThresholdChars: _aiMessageCompressionThresholdChars,
      aiSingleRoundToolCallLimit: _aiSingleRoundToolCallLimit,
      aiSequentialToolRoundLimit: _aiSequentialToolRoundLimit,
      aiWriteCommandConfirmationEnabled: _aiWriteCommandConfirmationEnabled,
      aiAllowCommandRules: List<AiAllowCommandRule>.from(_aiAllowCommandRules),
      aiDenyCommandRules: List<AiDenyCommandRule>.from(_aiDenyCommandRules),
      aiModels: List<AiModelConfig>.from(_aiModels),
      selectedAiModelId: _selectedAiModelId,
      shortcutBindings: _cloneShortcutBindings(_shortcutBindings),
    );
  }

  void _applySnapshot(AppSettingsSnapshot snapshot) {
    _themeMode = snapshot.themeMode;
    _themePreset = snapshot.themePreset;
    _language = snapshot.language;
    _skillsStoragePath = snapshot.skillsStoragePath;
    _mcpEnabled = snapshot.mcpEnabled;
    _mcpServersFilePath = snapshot.mcpServersFilePath;
    _memoryEnabled = snapshot.memoryEnabled;
    _userMemoryFilePath = snapshot.userMemoryFilePath;
    _aiMessageCompressionThresholdChars =
        snapshot.aiMessageCompressionThresholdChars;
    _aiSingleRoundToolCallLimit = snapshot.aiSingleRoundToolCallLimit;
    _aiSequentialToolRoundLimit = snapshot.aiSequentialToolRoundLimit;
    _aiWriteCommandConfirmationEnabled =
        snapshot.aiWriteCommandConfirmationEnabled;
    _aiAllowCommandRules = List<AiAllowCommandRule>.from(
      snapshot.aiAllowCommandRules,
    );
    _aiDenyCommandRules = List<AiDenyCommandRule>.from(
      snapshot.aiDenyCommandRules,
    );
    _aiModels = List<AiModelConfig>.from(snapshot.aiModels);
    _selectedAiModelId = snapshot.selectedAiModelId;
    _shortcutBindings = _cloneShortcutBindings(snapshot.shortcutBindings);
  }

  Future<bool> _commitMutation(_MutationDisposition Function() mutation) async {
    final completer = Completer<bool>();
    _mutationQueue = _mutationQueue.catchError((_) {}).then((_) async {
      final previousSnapshot = _snapshot();
      final disposition = mutation();
      if (disposition == _MutationDisposition.successNoChange) {
        completer.complete(true);
        return;
      }
      if (disposition == _MutationDisposition.reject) {
        completer.complete(false);
        return;
      }
      notifyListeners();
      try {
        await _store.save(_snapshot());
        if (_persistenceIssue != null) {
          _persistenceIssue = null;
          notifyListeners();
        }
        completer.complete(true);
      } catch (error) {
        _applySnapshot(previousSnapshot);
        _persistenceIssue = SettingsPersistenceIssue(
          kind: SettingsPersistenceIssueKind.saveFailed,
          filePath: _store.settingsFilePath,
          detail: '$error',
        );
        notifyListeners();
        completer.complete(false);
      }
    });
    return completer.future;
  }
}

Map<OpenHandShortcutAction, List<int>> _cloneShortcutBindings(
  Map<OpenHandShortcutAction, List<int>> bindings,
) {
  return <OpenHandShortcutAction, List<int>>{
    for (final entry in bindings.entries)
      entry.key: List<int>.from(entry.value, growable: false),
  };
}

bool _sameIntList(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
