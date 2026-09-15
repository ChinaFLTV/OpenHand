import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/memory/data/memory_store.dart';
import 'package:openhand/features/memory/memory_controller.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';
import 'package:openhand/features/skills/data/skills_repository.dart';
import 'package:openhand/features/skills/model/local_skill.dart';
import 'package:openhand/features/skills/skills_controller.dart';
import 'package:openhand/features/workflows/data/workflows_store.dart';
import 'package:openhand/features/workflows/model/workflow_definition.dart';
import 'package:openhand/features/workflows/workflows_controller.dart';

class _SkillsRepository extends SkillsRepository {
  List<LocalSkill> entries = [];
  bool failLoad = false;

  @override
  Future<List<LocalSkill>> loadInstalledSkills(String storagePath) async {
    if (failLoad) throw StateError('模拟目录扫描失败');
    return List.of(entries);
  }

  @override
  Future<LocalSkill> createSkillTemplate(String storagePath) async {
    const skill = LocalSkill(
      name: '测试技能',
      description: '测试',
      directoryPath: '/测试/技能',
      manifestPath: '/测试/技能/SKILL.md',
      relativeDirectoryPath: '技能',
    );
    entries.add(skill);
    return skill;
  }

  @override
  Future<LocalSkill> updateSkillManifest(
    LocalSkill skill,
    String storagePath,
    String content,
  ) async {
    final updated = LocalSkill(
      name: content,
      description: skill.description,
      directoryPath: skill.directoryPath,
      manifestPath: skill.manifestPath,
      relativeDirectoryPath: skill.relativeDirectoryPath,
    );
    entries = [updated];
    return updated;
  }

  @override
  Future<void> deleteSkill(LocalSkill skill, String storagePath) async {
    entries.removeWhere((entry) => entry.manifestPath == skill.manifestPath);
  }
}

class _MemoryStore extends MemoryStore {
  List<UserMemoryEntry> entries = [];
  bool failLoad = false;
  bool overQuota = false;

  @override
  Future<MemoryLoadResult> load() async {
    if (failLoad) throw StateError('模拟记忆重读失败');
    return MemoryLoadResult(entries: List.of(entries), isOverQuota: overQuota);
  }

  @override
  Future<void> insertEntry(UserMemoryEntry entry) async => entries.add(entry);

  @override
  Future<void> updateEntry(UserMemoryEntry entry) async {
    entries[entries.indexWhere((item) => item.id == entry.id)] = entry;
  }

  @override
  Future<void> deleteEntry(String id) async =>
      entries.removeWhere((entry) => entry.id == id);
}

class _WorkflowsStore extends WorkflowsStore {
  List<WorkflowDefinition> entries = [];

  @override
  Future<void> ensureTable() async {}
  @override
  Future<List<WorkflowDefinition>> loadAll() async => List.of(entries);
  @override
  Future<void> save(WorkflowDefinition workflow) async {
    entries = [workflow, ...entries.where((entry) => entry.id != workflow.id)];
  }

  @override
  Future<void> delete(String id) async =>
      entries.removeWhere((entry) => entry.id == id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('技能增删改成功后，即使重扫失败仍发布已提交的卡片状态', () async {
    final repository = _SkillsRepository();
    final controller = SkillsController.uninitialized(
      initialStoragePath: '/测试',
      repository: repository,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    var observed = controller.skills;
    controller.addListener(() => observed = controller.skills);
    repository.failLoad = true;
    final skill = await controller.createSkillTemplate();
    expect(observed.single.name, '测试技能');
    expect(controller.errorMessage, isNotNull);
    final updated = await controller.updateSkillManifest(skill, '修改后的技能');
    expect(observed.single.name, '修改后的技能');
    await controller.deleteSkill(updated);
    expect(observed, isEmpty);
    repository.failLoad = false;
    await controller.refresh();
    expect(controller.skills, isEmpty);
  });

  for (final deleting in [false, true]) {
    test('记忆超额恢复中${deleting ? '删除' : '编辑'}成功而重读失败时，不恢复旧快照', () async {
      final store = _MemoryStore();
      final controller = MemoryController.uninitialized(store: store);
      addTearDown(controller.dispose);
      await controller.createMemory(content: '旧正文', tags: []);
      store.overQuota = true;
      await controller.refresh();
      final entry = controller.entries.single;
      var observed = controller.entries;
      controller.addListener(() => observed = controller.entries);
      store.failLoad = true;
      final success = deleting
          ? await controller.deleteMemory(entry)
          : await controller.updateMemory(entry, content: '新正文');
      expect(success, isTrue);
      expect(controller.errorMessage, isNotNull);
      if (deleting) {
        expect(observed, isEmpty);
      } else {
        expect(observed.single.content, '新正文');
      }
      store.failLoad = false;
      await controller.refresh();
      expect(
        controller.entries.map((item) => item.content),
        observed.map((item) => item.content),
      );
    });
  }

  test('工作流删除后拒绝旧编辑提交，并保持新增和正常编辑可用', () async {
    final store = _WorkflowsStore();
    final controller = await WorkflowsController.create(store: store);
    addTearDown(controller.dispose);
    final now = DateTime.now().toUtc();
    final workflow = WorkflowDefinition(
      id: '测试',
      name: '工作流',
      createdAt: now,
      updatedAt: now,
    );
    expect(await controller.save(workflow), isTrue);
    expect(
      await controller.save(
        workflow.copyWith(name: '已编辑'),
        requireExisting: true,
      ),
      isTrue,
    );
    var observed = controller.workflows;
    controller.addListener(() => observed = controller.workflows);
    expect(await controller.delete(workflow.id), isTrue);
    expect(await controller.save(workflow, requireExisting: true), isFalse);
    expect(await controller.setEnabled(workflow.id, false), isFalse);
    expect(observed, isEmpty);
    expect(store.entries, isEmpty);
  });

  test('MCP 删除后旧编辑不能重新创建服务器，刷新和重新加载均保持删除结果', () async {
    final directory = await Directory.systemTemp.createTemp(
      'openhand-mcp-test-',
    );
    final path = '${directory.path}/servers.json';
    final controller = McpController.uninitialized(initialFilePath: path);
    addTearDown(() async {
      await controller.shutdown();
      await directory.delete(recursive: true);
    });
    const server = McpServer(
      name: '测试服务器',
      type: McpServerType.streamableHttp,
      enabled: false,
      probeEnabled: false,
      url: 'http://127.0.0.1:12345/mcp',
    );
    expect(await controller.saveServer(server), isTrue);
    expect(
      await controller.saveServer(
        server.copyWith(name: '新名称'),
        previousName: server.name,
      ),
      isTrue,
    );
    expect(
      await controller.saveServer(server, previousName: server.name),
      isFalse,
    );
    expect(await controller.deleteServer(server.copyWith(name: '新名称')), isTrue);
    expect(await controller.saveServer(server, previousName: '新名称'), isFalse);
    await controller.refresh();
    expect(controller.servers, isEmpty);
  });
}
