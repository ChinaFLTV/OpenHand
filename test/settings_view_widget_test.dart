import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:openhand/app/model/app_info.dart';
import 'package:openhand/app/model/app_language.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/features/memory/data/memory_store.dart';
import 'package:openhand/features/memory/memory_controller.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';
import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/settings/settings_view.dart';
import 'package:openhand/features/skills/data/skills_repository.dart';
import 'package:openhand/features/skills/model/local_skill.dart';
import 'package:openhand/features/skills/skills_controller.dart';
import 'package:openhand/l10n/app_localizations.dart';

void main() {
  const skillsPathFieldKey = ValueKey<String>('settingsSkillsPathField');
  const skillsSaveButtonKey = ValueKey<String>('settingsSkillsSaveButton');
  const memoryFileFieldKey = ValueKey<String>('settingsMemoryFileField');
  const memorySaveButtonKey = ValueKey<String>('settingsMemorySaveButton');
  const toolCallLimitFieldKey = ValueKey<String>('settingsToolCallLimitField');
  const toolCallLimitSaveButtonKey = ValueKey<String>(
    'settingsToolCallLimitSaveButton',
  );

  testWidgets('SettingsView rolls back skills path when skills reload fails', (
    tester,
  ) async {
    final harness = await _createSettingsViewHarness();
    addTearDown(harness.dispose);
    final invalidSkillsPath = p.join('/broken', 'skills');

    await tester.pumpWidget(_SettingsViewTestApp(harness: harness));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.ensureVisible(find.byKey(skillsPathFieldKey));
    await tester.enterText(find.byKey(skillsPathFieldKey), invalidSkillsPath);
    await tester.ensureVisible(find.byKey(skillsSaveButtonKey));
    await tester.tap(find.byKey(skillsSaveButtonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      harness.settingsController.skillsStoragePath,
      harness.initialSkillsPath,
    );
    expect(harness.skillsController.storagePath, harness.initialSkillsPath);
    expect(harness.skillsController.errorMessage, isNull);
    expect(
      find.text('The skill action failed. Please try again.'),
      findsOneWidget,
    );
    expect(
      find.text('The skills storage location has been updated'),
      findsNothing,
    );
    final field = tester.widget<TextField>(find.byKey(skillsPathFieldKey));
    expect(field.controller!.text, harness.initialSkillsPath);
  });

  testWidgets(
    'SettingsView rolls back memory file path when memory reload fails',
    (tester) async {
      final harness = await _createSettingsViewHarness();
      addTearDown(harness.dispose);
      final invalidMemoryPath = p.join('/broken', 'memory');

      await tester.pumpWidget(_SettingsViewTestApp(harness: harness));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      await tester.ensureVisible(find.byKey(memoryFileFieldKey));
      await tester.enterText(find.byKey(memoryFileFieldKey), invalidMemoryPath);
      await tester.ensureVisible(find.byKey(memorySaveButtonKey));
      await tester.tap(find.byKey(memorySaveButtonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        harness.settingsController.userMemoryFilePath,
        harness.initialMemoryFilePath,
      );
      expect(
        harness.memoryController.userMemoryFilePath,
        harness.initialMemoryFilePath,
      );
      expect(harness.memoryController.errorMessage, isNull);
      expect(harness.memoryController.persistenceIssue, isNull);
      expect(
        find.text('The memory action failed. Please try again.'),
        findsOneWidget,
      );
      expect(
        find.text('The user memory file path has been updated'),
        findsNothing,
      );
      final field = tester.widget<TextField>(find.byKey(memoryFileFieldKey));
      expect(field.controller!.text, harness.initialMemoryFilePath);
    },
  );

  testWidgets('SettingsView saves the per-response tool call limit', (
    tester,
  ) async {
    final harness = await _createSettingsViewHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_SettingsViewTestApp(harness: harness));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.ensureVisible(find.byKey(toolCallLimitFieldKey));
    await tester.enterText(find.byKey(toolCallLimitFieldKey), '55');
    await tester.ensureVisible(find.byKey(toolCallLimitSaveButtonKey));
    await tester.tap(find.byKey(toolCallLimitSaveButtonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(harness.settingsController.aiSingleRoundToolCallLimit, 55);
    expect(
      find.text('The per-response tool call limit has been saved.'),
      findsOneWidget,
    );
  });
}

Future<_SettingsViewHarness> _createSettingsViewHarness() async {
  final initialSkillsPath = p.join('/workspace', 'skills');
  final initialMemoryFilePath = p.join(
    '/workspace',
    'memory',
    'user-memory.json',
  );
  final initialMcpFilePath = p.join('/workspace', 'mcp', 'servers.json');
  final settingsController = await SettingsController.create(
    store: _InMemorySettingsStore(),
  );
  expect(
    await settingsController.updateSkillsStoragePath(initialSkillsPath),
    isTrue,
  );
  expect(
    await settingsController.updateUserMemoryFilePath(initialMemoryFilePath),
    isTrue,
  );

  final skillsController = await SkillsController.create(
    initialStoragePath: initialSkillsPath,
    repository: _PathAwareSkillsRepository(
      failingPaths: <String>{p.join('/broken', 'skills')},
    ),
  );
  final memoryStoreFactory = _PathAwareMemoryStoreFactory(
    failingPaths: <String>{p.join('/broken', 'memory')},
  );
  final memoryController = await MemoryController.create(
    initialFilePath: initialMemoryFilePath,
    store: memoryStoreFactory.create(initialMemoryFilePath),
    storeFactory: memoryStoreFactory.create,
  );
  final mcpController = await McpController.create(
    initialFilePath: initialMcpFilePath,
    store: _InMemoryMcpStore(initialFilePath: initialMcpFilePath),
  );

  return _SettingsViewHarness(
    initialSkillsPath: initialSkillsPath,
    initialMemoryFilePath: initialMemoryFilePath,
    settingsController: settingsController,
    skillsController: skillsController,
    memoryController: memoryController,
    mcpController: mcpController,
  );
}

class _SettingsViewTestApp extends StatelessWidget {
  const _SettingsViewTestApp({required this.harness});

  final _SettingsViewHarness harness;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppInfo>.value(value: AppInfo.fallback()),
        ChangeNotifierProvider<SettingsController>.value(
          value: harness.settingsController,
        ),
        ChangeNotifierProvider<SkillsController>.value(
          value: harness.skillsController,
        ),
        ChangeNotifierProvider<MemoryController>.value(
          value: harness.memoryController,
        ),
        ChangeNotifierProvider<McpController>.value(
          value: harness.mcpController,
        ),
      ],
      child: MaterialApp(
        locale: AppLanguage.english.locale,
        supportedLocales: supportedAppLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: SettingsView()),
      ),
    );
  }
}

class _SettingsViewHarness {
  const _SettingsViewHarness({
    required this.initialSkillsPath,
    required this.initialMemoryFilePath,
    required this.settingsController,
    required this.skillsController,
    required this.memoryController,
    required this.mcpController,
  });

  final String initialSkillsPath;
  final String initialMemoryFilePath;
  final SettingsController settingsController;
  final SkillsController skillsController;
  final MemoryController memoryController;
  final McpController mcpController;

  Future<void> dispose() async {
    settingsController.dispose();
    skillsController.dispose();
    memoryController.dispose();
    mcpController.dispose();
  }
}

class _InMemorySettingsStore extends SettingsStore {
  _InMemorySettingsStore({AppSettingsSnapshot? snapshot})
    : _snapshot = snapshot ?? AppSettingsSnapshot.defaults(),
      super(settingsFilePath: '/virtual/SETTINGS.toml');

  AppSettingsSnapshot _snapshot;

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: _snapshot);
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}

class _PathAwareSkillsRepository extends SkillsRepository {
  _PathAwareSkillsRepository({required this.failingPaths});

  final Set<String> failingPaths;

  @override
  Future<List<LocalSkill>> loadInstalledSkills(String storagePath) async {
    if (failingPaths.contains(storagePath)) {
      throw const FileSystemException('Cannot load skills from this path.');
    }
    return const <LocalSkill>[];
  }
}

class _PathAwareMemoryStoreFactory {
  _PathAwareMemoryStoreFactory({required this.failingPaths});

  final Set<String> failingPaths;
  final Map<String, List<UserMemoryEntry>> _entriesByPath =
      <String, List<UserMemoryEntry>>{};

  MemoryStore create(String filePath) {
    return _PathAwareMemoryStore(
      userMemoryFilePath: filePath,
      failingPaths: failingPaths,
      entriesByPath: _entriesByPath,
    );
  }
}

class _PathAwareMemoryStore extends MemoryStore {
  _PathAwareMemoryStore({
    required String userMemoryFilePath,
    required this.failingPaths,
    required this.entriesByPath,
  }) : super(userMemoryFilePath: userMemoryFilePath);

  final Set<String> failingPaths;
  final Map<String, List<UserMemoryEntry>> entriesByPath;

  @override
  Future<MemoryLoadResult> load() async {
    if (failingPaths.contains(userMemoryFilePath)) {
      return MemoryLoadResult(
        entries: const <UserMemoryEntry>[],
        issue: MemoryPersistenceIssue(
          kind: MemoryPersistenceIssueKind.saveFailed,
          filePath: userMemoryFilePath,
          detail: 'Synthetic test failure.',
        ),
      );
    }
    return MemoryLoadResult(
      entries: List<UserMemoryEntry>.from(
        entriesByPath[userMemoryFilePath] ?? const <UserMemoryEntry>[],
      ),
    );
  }

  @override
  Future<void> save(List<UserMemoryEntry> entries) async {
    if (failingPaths.contains(userMemoryFilePath)) {
      throw const FileSystemException('Cannot save memory to this path.');
    }
    entriesByPath[userMemoryFilePath] = List<UserMemoryEntry>.from(entries);
  }
}

class _InMemoryMcpStore extends McpStore {
  _InMemoryMcpStore({required String initialFilePath})
    : super(serversFilePath: initialFilePath);

  @override
  Future<McpLoadResult> load() async {
    return const McpLoadResult(servers: <McpServer>[]);
  }

  @override
  Future<void> save(List<McpServer> servers) async {}
}
