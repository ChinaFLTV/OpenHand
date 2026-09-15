import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/cron_config.dart';
import 'package:openhand/app/model/hook_config.dart';
import 'package:openhand/features/crons/crons_controller.dart';
import 'package:openhand/features/hooks/hooks_controller.dart';
import 'package:openhand/features/instructions/instructions_controller.dart';
import 'package:openhand/features/knowledge_base/data/knowledge_base_settings_store.dart';
import 'package:openhand/features/knowledge_base/data/knowledge_base_store.dart';
import 'package:openhand/features/knowledge_base/knowledge_base_controller.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_base_settings.dart';
import 'package:openhand/features/knowledge_base/model/knowledge_source.dart';
import 'package:openhand/features/knowledge_base/service/knowledge_source_storage.dart';
import 'package:openhand/shared/db/database_service.dart';

class _LocalHttpOverrides extends HttpOverrides {}

class _KnowledgeStore extends KnowledgeBaseStore {
  bool failLoad = false;

  @override
  Future<List<KnowledgeSource>> loadSources({String query = ''}) {
    if (failLoad) throw StateError('模拟知识源重读失败');
    return super.loadSources(query: query);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('指令、钩子、定时任务及知识源删除经 SQLite 重读后保持一致', () async {
    final directory = await Directory.systemTemp.createTemp(
      'openhand-list-db-',
    );
    final database = await DatabaseService.initialize(
      databasePath: '${directory.path}/test.db',
      useNoIsolateFactory: true,
    );
    final instructions = InstructionsController.uninitialized();
    final hooks = await HooksController.create();
    final crons = CronsController.uninitialized();
    addTearDown(() async {
      instructions.dispose();
      hooks.dispose();
      await crons.shutdown();
      await database.close();
      await directory.delete(recursive: true);
    });

    expect(await instructions.createEntry(name: '持久化指令', body: '正文'), isTrue);
    final instruction = instructions.entries.single;
    expect(await instructions.updateEntry(instruction, name: '修改后的指令'), isTrue);
    await instructions.refresh();
    expect(instructions.entries.single.name, '修改后的指令');
    expect(await instructions.deleteEntry(instruction.id), isTrue);
    await instructions.refresh();
    expect(instructions.entries, isEmpty);

    const hook = HookEntry(
      id: '测试钩子',
      event: HookEvent.sessionStart,
      label: '钩子',
      enabled: false,
      scriptContent: 'echo 测试',
    );
    var observedHooks = hooks.entries;
    hooks.addListener(() => observedHooks = hooks.entries);
    expect(await hooks.addHook(hook), isTrue);
    expect(observedHooks.single.id, hook.id);
    expect(await hooks.updateHook(hook.copyWith(label: '修改后的钩子')), isTrue);
    expect(observedHooks.single.label, '修改后的钩子');
    await hooks.refresh();
    expect(hooks.entries.single.label, '修改后的钩子');
    expect(await hooks.deleteHook(hook.id), isTrue);
    expect(observedHooks, isEmpty);
    expect(await hooks.updateHook(hook), isFalse);
    await hooks.refresh();
    expect(hooks.entries, isEmpty);

    const cron = CronEntry(
      id: '测试定时任务',
      name: '定时任务',
      enabled: false,
      scriptContent: 'echo 测试',
    );
    var observedCrons = crons.entries;
    crons.addListener(() => observedCrons = crons.entries);
    expect(await crons.addCron(cron), isTrue);
    expect(observedCrons.any((entry) => entry.id == cron.id), isTrue);
    expect(await crons.updateCron(cron.copyWith(name: '修改后的定时任务')), isTrue);
    expect(
      observedCrons.firstWhere((entry) => entry.id == cron.id).name,
      '修改后的定时任务',
    );
    await crons.refresh();
    expect(
      crons.entries.firstWhere((entry) => entry.id == cron.id).name,
      '修改后的定时任务',
    );
    expect(await crons.deleteCron(cron.id), isTrue);
    expect(observedCrons.any((entry) => entry.id == cron.id), isFalse);
    expect(await crons.updateCron(cron), isFalse);
    await crons.refresh();
    expect(crons.entries.any((entry) => entry.id == cron.id), isFalse);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"status":"ok","result":true}');
      await request.response.close();
    });
    final settingsStore = KnowledgeBaseSettingsStore();
    await settingsStore.save(
      KnowledgeBaseSettings(qdrantRestPort: server.port, retryCount: 0),
    );
    final knowledgeStore = _KnowledgeStore();
    final now = DateTime.now().toUtc();
    final source = KnowledgeSource(
      id: '测试知识源',
      title: '知识源',
      kind: 'note',
      originalPath: '',
      storedPath: '',
      mimeType: 'text/plain',
      sizeBytes: 0,
      contentHash: '测试内容哈希',
      status: 'indexed',
      errorMessage: '',
      importedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    await knowledgeStore.upsertSource(source);
    final knowledge = KnowledgeBaseController(
      store: knowledgeStore,
      settingsStore: settingsStore,
    );
    addTearDown(() async {
      await knowledge.shutdown();
      await flushPendingKnowledgeSourceFileCleanups();
    });
    await knowledge.initialize();
    expect(knowledge.sources.single.id, source.id);
    var observedSources = knowledge.sources;
    knowledge.addListener(() => observedSources = knowledge.sources);
    knowledgeStore.failLoad = true;
    expect(
      await HttpOverrides.runWithHttpOverrides(
        () => knowledge.deleteSource(source),
        _LocalHttpOverrides(),
      ),
      isTrue,
    );
    expect(observedSources, isEmpty);
    expect(knowledge.error, contains('已删除'));
    expect(await knowledgeStore.loadSource(source.id), isNull);
    knowledgeStore.failLoad = false;
    await knowledge.initialize();
    expect(knowledge.sources, isEmpty);
  });
}
