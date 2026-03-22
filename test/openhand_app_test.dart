import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/model/app_language.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/app/support/openhand_paths.dart';
import 'package:openhand/app/theme/openhand_theme_preset.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/ai_protocol_adapter.dart';

void main() {
  test('SettingsController persists settings to SETTINGS.toml', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_settings_controller_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final settingsFilePath = p.join(
      tempDirectory.path,
      '.openhand',
      'settings',
      'SETTINGS.toml',
    );
    final store = SettingsStore(settingsFilePath: settingsFilePath);

    final controller = await SettingsController.create(store: store);

    expect(File(settingsFilePath).existsSync(), isTrue);
    expect(controller.themeMode, ThemeMode.system);
    expect(controller.skillsStoragePath, controller.defaultSkillsStoragePath);
    expect(controller.mcpEnabled, isTrue);
    expect(controller.memoryEnabled, isTrue);
    expect(
      controller.displayMcpServersFilePath,
      OpenHandPaths.defaultMcpServersFileLabel,
    );
    expect(
      controller.displaySkillsStoragePath,
      OpenHandPaths.defaultSkillsDirectoryLabel,
    );
    expect(
      controller.displayUserMemoryFilePath,
      OpenHandPaths.defaultUserMemoryFileLabel(),
    );

    expect(await controller.updateThemeMode(ThemeMode.dark), isTrue);
    expect(
      await controller.updateThemePreset(OpenHandThemePreset.emberOrange),
      isTrue,
    );
    expect(await controller.updateMcpEnabled(false), isTrue);
    expect(await controller.updateMemoryEnabled(false), isTrue);
    expect(await controller.updateLanguage(AppLanguage.german), isTrue);
    expect(await controller.updateSkillsStoragePath('~/custom-skills'), isTrue);
    final customMemoryFilePath = p.join(
      tempDirectory.path,
      'custom-memory.json',
    );
    expect(
      await controller.updateUserMemoryFilePath(customMemoryFilePath),
      isTrue,
    );
    expect(
      await controller.saveAiModel(
        const AiModelConfig(
          id: 'model-1',
          baseUrl: 'https://api.openai.example/v1',
          authScheme: AiAuthScheme.bearer,
          token: 'secret-token',
          modelId: 'gpt-5.4',
          protocolType: AiProtocolType.openai,
        ),
      ),
      isTrue,
    );
    expect(
      await controller.saveAiModel(
        const AiModelConfig(
          id: 'model-2',
          baseUrl: 'https://api.anthropic.example',
          authScheme: AiAuthScheme.apiKey,
          token: 'second-token',
          modelId: 'claude-sonnet',
          protocolType: AiProtocolType.claude,
        ),
      ),
      isTrue,
    );
    expect(await controller.updateSelectedAiModel('model-2'), isTrue);
    expect(await controller.moveAiModel(1, 0), isTrue);

    final reloadedController = await SettingsController.create(store: store);

    expect(reloadedController.themeMode, ThemeMode.dark);
    expect(reloadedController.themePreset, OpenHandThemePreset.emberOrange);
    expect(reloadedController.mcpEnabled, isFalse);
    expect(reloadedController.memoryEnabled, isFalse);
    expect(reloadedController.language, AppLanguage.german);
    expect(reloadedController.displaySkillsStoragePath, '~/custom-skills');
    expect(
      reloadedController.displayMcpServersFilePath,
      OpenHandPaths.defaultMcpServersFileLabel,
    );
    expect(reloadedController.userMemoryFilePath, customMemoryFilePath);
    expect(reloadedController.aiModels, hasLength(2));
    expect(reloadedController.aiModels.first.id, 'model-2');
    expect(reloadedController.selectedAiModel?.modelId, 'claude-sonnet');
    final persistedSkillsPath = OpenHandPaths.normalizeUserPath(
      '~/custom-skills',
    );
    expect(
      File(settingsFilePath).readAsStringSync(),
      contains('skills_storage_path = "$persistedSkillsPath"'),
    );
    expect(
      File(settingsFilePath).readAsStringSync(),
      contains('theme_preset = "ember_orange"'),
    );
    expect(
      File(settingsFilePath).readAsStringSync(),
      contains('mcp_enabled = false'),
    );
    expect(
      File(settingsFilePath).readAsStringSync(),
      contains('memory_enabled = false'),
    );
    expect(
      File(settingsFilePath).readAsStringSync(),
      contains('user_memory_file = "$customMemoryFilePath"'),
    );
  });

  test(
    'SettingsController recovers from invalid settings file content',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_settings_recovery_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final settingsDirectory = Directory(
        p.join(tempDirectory.path, '.openhand', 'settings'),
      );
      await settingsDirectory.create(recursive: true);
      final settingsFile = File(
        p.join(settingsDirectory.path, 'SETTINGS.toml'),
      );
      await settingsFile.writeAsString('broken = [', flush: true);

      final controller = await SettingsController.create(
        store: SettingsStore(settingsFilePath: settingsFile.path),
      );

      expect(controller.themeMode, ThemeMode.system);
      expect(controller.themePreset, OpenHandThemePreset.deepSeaBlue);
      expect(controller.mcpEnabled, isTrue);
      expect(controller.memoryEnabled, isTrue);
      expect(
        controller.persistenceIssue?.kind,
        SettingsPersistenceIssueKind.recoveredInvalidFile,
      );
      final backupFiles = settingsDirectory
          .listSync()
          .whereType<File>()
          .where(
            (file) => p.basename(file.path).startsWith('SETTINGS.invalid-'),
          )
          .toList();
      expect(backupFiles, isNotEmpty);
    },
  );

  test(
    'SettingsController serializes concurrent mutations to avoid stale saves',
    () async {
      final store = _QueuedSettingsStore(
        snapshot: AppSettingsSnapshot.defaults(),
      );
      final controller = await SettingsController.create(store: store);

      final firstUpdate = controller.updateThemeMode(ThemeMode.dark);
      final secondUpdate = controller.updateLanguage(AppLanguage.german);

      await Future<void>.delayed(Duration.zero);

      expect(store.pendingSaveCount, 1);
      expect(store.savedSnapshots.single.themeMode, ThemeMode.dark);
      expect(
        store.savedSnapshots.single.language,
        AppLanguage.simplifiedChinese,
      );

      store.completeNextSave();
      await Future<void>.delayed(Duration.zero);

      expect(store.pendingSaveCount, 1);
      expect(store.savedSnapshots, hasLength(2));
      expect(store.savedSnapshots.last.themeMode, ThemeMode.dark);
      expect(store.savedSnapshots.last.language, AppLanguage.german);

      store.completeNextSave();

      expect(await firstUpdate, isTrue);
      expect(await secondUpdate, isTrue);
      expect(controller.themeMode, ThemeMode.dark);
      expect(controller.language, AppLanguage.german);
    },
  );

  test(
    'SettingsController applies queued mutations against latest state',
    () async {
      final store = _QueuedSettingsStore(
        snapshot: AppSettingsSnapshot.defaults(),
      );
      final controller = await SettingsController.create(store: store);

      final firstUpdate = controller.updateThemeMode(ThemeMode.dark);
      final secondUpdate = controller.updateThemeMode(ThemeMode.system);

      await Future<void>.delayed(Duration.zero);
      expect(store.pendingSaveCount, 1);
      expect(store.savedSnapshots.single.themeMode, ThemeMode.dark);

      store.completeNextSave();
      await Future<void>.delayed(Duration.zero);

      expect(store.pendingSaveCount, 1);
      expect(store.savedSnapshots.last.themeMode, ThemeMode.system);

      store.completeNextSave();

      expect(await firstUpdate, isTrue);
      expect(await secondUpdate, isTrue);
      expect(controller.themeMode, ThemeMode.system);
    },
  );

  test(
    'SettingsStore sanitizes duplicate ai models and invalid enum values',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_settings_sanitize_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final settingsDirectory = Directory(
        p.join(tempDirectory.path, '.openhand', 'settings'),
      );
      await settingsDirectory.create(recursive: true);
      final settingsFile = File(
        p.join(settingsDirectory.path, 'SETTINGS.toml'),
      );
      await settingsFile.writeAsString('''
version = 1
theme_mode = "system"
theme_preset = "deep_sea_blue"
language = "zh_Hans"
skills_storage_path = "/tmp/skills"
mcp_enabled = true
mcp_servers_file_path = "/tmp/mcp_servers.json"
memory_enabled = true
user_memory_file = "/tmp/user-memory.json"
selected_ai_model_id = "missing-model"

[[ai_models]]
id = "primary-model"
base_url = "https://api.example.com/v1/"
auth_scheme = "broken"
token = "secret"
model_id = "gpt-5.4"
protocol_type = "invalid"

[[ai_models]]
id = "primary-model"
base_url = "https://api.duplicate.example/v1"
auth_scheme = "token"
token = "other-secret"
model_id = "gpt-duplicate"
protocol_type = "openai"
''', flush: true);

      final loadResult = await SettingsStore(
        settingsFilePath: settingsFile.path,
      ).load();

      expect(
        loadResult.issue?.kind,
        SettingsPersistenceIssueKind.sanitizedInvalidContent,
      );
      expect(loadResult.snapshot.aiModels, hasLength(1));
      expect(loadResult.snapshot.selectedAiModelId, 'primary-model');
      final model = loadResult.snapshot.aiModels.single;
      expect(model.id, 'primary-model');
      expect(model.baseUrl, 'https://api.example.com/v1');
      expect(model.authScheme, AiAuthScheme.bearer);
      expect(model.protocolType, AiProtocolType.openai);

      final persistedContent = await settingsFile.readAsString();
      expect(
        RegExp(
          r'^\[\[ai_models\]\]$',
          multiLine: true,
        ).allMatches(persistedContent).length,
        1,
      );
      expect(
        persistedContent,
        contains('selected_ai_model_id = "primary-model"'),
      );
      expect(persistedContent, contains('auth_scheme = "bearer"'));
      expect(persistedContent, contains('protocol_type = "openai"'));
    },
  );

  test('Gemini request URLs encode model ids safely', () {
    const model = AiModelConfig(
      id: 'gemini-model',
      baseUrl: 'https://generativelanguage.googleapis.com/',
      authScheme: AiAuthScheme.apiKey,
      token: 'secret',
      modelId: 'gemini pro/1.5',
      protocolType: AiProtocolType.gemini,
    );

    final blueprint = AiProtocolRegistry.adapterFor(model.protocolType)
        .buildChatRequest(
          model: model,
          messages: const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.user, content: 'Hello'),
          ],
        );

    expect(
      blueprint.url,
      'https://generativelanguage.googleapis.com/v1beta/models/gemini%20pro%2F1.5:generateContent',
    );
  });

  test('OpenAI-compatible URLs do not duplicate version segments', () {
    const model = AiModelConfig(
      id: 'deepseek-model',
      baseUrl: 'https://api.deepseek.com/v1/',
      authScheme: AiAuthScheme.bearer,
      token: 'secret',
      modelId: 'deepseek-reasoner',
      protocolType: AiProtocolType.openai,
    );

    final blueprint = AiProtocolRegistry.adapterFor(model.protocolType)
        .buildChatRequest(
          model: model,
          messages: const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.user, content: 'Hello'),
          ],
        );

    expect(blueprint.url, 'https://api.deepseek.com/v1/chat/completions');
  });

  test('Gemini headers keep only x-goog-api-key for apiKey auth', () {
    const model = AiModelConfig(
      id: 'gemini-model',
      baseUrl: 'https://generativelanguage.googleapis.com/',
      authScheme: AiAuthScheme.apiKey,
      token: 'secret',
      modelId: 'gemini-1.5-pro',
      protocolType: AiProtocolType.gemini,
    );

    final headers = AiProtocolRegistry.adapterFor(model.protocolType)
        .buildChatRequest(
          model: model,
          messages: const <AiChatTurn>[
            AiChatTurn(role: AiChatRole.user, content: 'Hello'),
          ],
        )
        .headers;

    expect(headers['x-goog-api-key'], 'secret');
    expect(headers.containsKey('x-api-key'), isFalse);
    expect(headers.containsKey('authorization'), isFalse);
  });
}

class _QueuedSettingsStore extends SettingsStore {
  _QueuedSettingsStore({required AppSettingsSnapshot snapshot})
    : _snapshot = snapshot,
      super(settingsFilePath: '/tmp/openhand-test-settings.toml');

  AppSettingsSnapshot _snapshot;
  final List<AppSettingsSnapshot> savedSnapshots = <AppSettingsSnapshot>[];
  final List<Completer<void>> _pendingSaves = <Completer<void>>[];

  int get pendingSaveCount => _pendingSaves.length;

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: _snapshot);
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) {
    _snapshot = snapshot;
    savedSnapshots.add(snapshot);
    final completer = Completer<void>();
    _pendingSaves.add(completer);
    return completer.future;
  }

  void completeNextSave() {
    final completer = _pendingSaves.removeAt(0);
    completer.complete();
  }
}
