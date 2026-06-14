import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/skills/data/skills_repository.dart';
import 'package:openhand/features/skills/model/local_skill.dart';
import 'package:path/path.dart' as p;

void main() {
  group('SkillsRepository', () {
    late Directory tempDir;
    late SkillsRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('openhand_skills_repo_');
      repository = SkillsRepository();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates template skill with manifest and metadata', () async {
      final skill = await repository.createSkillTemplate(tempDir.path);

      expect(skill.name, 'New Skill');
      expect(await File(skill.manifestPath).exists(), isTrue);
      expect(
        await File(
          p.join(skill.directoryPath, 'agents', 'openai.yaml'),
        ).exists(),
        isTrue,
      );
      expect(await File('${skill.manifestPath}.tmp').exists(), isFalse);
      expect(await File('${skill.manifestPath}.bak').exists(), isFalse);
    });

    test('updates manifest through atomic text writes', () async {
      final skill = await repository.createSkillTemplate(tempDir.path);
      final updated = await repository.updateSkillManifest(
        skill,
        tempDir.path,
        _manifest('Renamed Skill', 'Updated description.'),
      );

      expect(updated.name, 'Renamed Skill');
      expect(updated.description, 'Updated description.');
      expect(
        await File(updated.manifestPath).readAsString(),
        contains('Body.'),
      );
      expect(await File('${updated.manifestPath}.tmp').exists(), isFalse);
      expect(await File('${updated.manifestPath}.bak').exists(), isFalse);
    });

    test('refuses to delete skills outside storage root', () async {
      final outsideDir = await Directory.systemTemp.createTemp(
        'openhand_external_skill_',
      );
      try {
        final manifest = File(p.join(outsideDir.path, 'SKILL.md'));
        await manifest.writeAsString(_manifest('External', 'Outside.'));
        final skill = LocalSkill(
          name: 'External',
          description: 'Outside.',
          directoryPath: outsideDir.path,
          manifestPath: manifest.path,
          relativeDirectoryPath: 'external',
        );

        expect(
          () => repository.deleteSkill(skill, tempDir.path),
          throwsA(isA<FileSystemException>()),
        );
        expect(await outsideDir.exists(), isTrue);
      } finally {
        if (await outsideDir.exists()) {
          await outsideDir.delete(recursive: true);
        }
      }
    });
  });
}

String _manifest(String name, String description) {
  return '---\n'
      'name: "$name"\n'
      'description: "$description"\n'
      '---\n'
      'Body.\n';
}
