import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openhand/features/skills/data/skills_repository.dart';
import 'package:openhand/features/skills/model/local_skill.dart';
import 'package:openhand/features/skills/skills_controller.dart';

void main() {
  test('SkillsController serializes create and refresh operations', () async {
    final repository = _QueuedSkillsRepository(
      initialSkills: const <LocalSkill>[],
    );
    final controller = await SkillsController.create(
      initialStoragePath: repository.storagePath,
      repository: repository,
    );

    expect(repository.loadCallCount, 1);

    final createFuture = controller.createSkill(
      name: 'Planner Skill',
      emojiIcon: '🧠',
      imageIconBytes: null,
      shortDescription: 'Custom planning skill.',
      manifestContent: '# Planner Skill',
    );
    final refreshFuture = controller.refresh();

    await Future<void>.delayed(Duration.zero);

    expect(repository.pendingCreateCount, 1);
    expect(repository.loadCallCount, 1);
    expect(controller.skills, isEmpty);

    repository.completeNextCreate();

    final createdSkill = await createFuture;
    await refreshFuture;

    expect(repository.loadCallCount, 3);
    expect(createdSkill.name, 'Planner Skill');
    expect(controller.skills, hasLength(1));
    expect(controller.skills.single.name, 'Planner Skill');
    expect(controller.errorMessage, isNull);
  });
}

class _QueuedSkillsRepository extends SkillsRepository {
  _QueuedSkillsRepository({required List<LocalSkill> initialSkills})
    : _persistedSkills = List<LocalSkill>.from(initialSkills);

  final String storagePath = '/tmp/openhand-test-skills';
  List<LocalSkill> _persistedSkills;
  int loadCallCount = 0;
  final List<_PendingSkillCreate> _pendingCreates = <_PendingSkillCreate>[];

  int get pendingCreateCount => _pendingCreates.length;

  @override
  Future<List<LocalSkill>> loadInstalledSkills(String storagePath) async {
    loadCallCount += 1;
    return List<LocalSkill>.from(_persistedSkills);
  }

  @override
  Future<LocalSkill> createSkill(
    String storagePath, {
    required String name,
    String? emojiIcon,
    Uint8List? imageIconBytes,
    required String shortDescription,
    required String manifestContent,
  }) {
    final slug = name.toLowerCase().replaceAll(' ', '-');
    final skill = LocalSkill(
      name: name,
      description: name,
      directoryPath: p.join(this.storagePath, slug),
      manifestPath: p.join(this.storagePath, slug, 'SKILL.md'),
      relativeDirectoryPath: slug,
      emojiIcon: emojiIcon,
    );
    final completer = Completer<LocalSkill>();
    _pendingCreates.add(
      _PendingSkillCreate(completer: completer, skill: skill),
    );
    return completer.future;
  }

  void completeNextCreate() {
    final pendingCreate = _pendingCreates.removeAt(0);
    _persistedSkills = <LocalSkill>[..._persistedSkills, pendingCreate.skill];
    pendingCreate.completer.complete(pendingCreate.skill);
  }
}

class _PendingSkillCreate {
  const _PendingSkillCreate({required this.completer, required this.skill});

  final Completer<LocalSkill> completer;
  final LocalSkill skill;
}
