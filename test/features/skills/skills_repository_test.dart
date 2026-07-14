import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/skills/data/skills_repository.dart';

void main() {
  late Directory storageDirectory;

  setUp(() async {
    storageDirectory = await Directory.systemTemp.createTemp(
      'openhand-skills-repository-',
    );
  });

  tearDown(() async {
    await storageDirectory.delete(recursive: true);
  });

  Future<void> writeManifest(String relativeDirectory, String name) async {
    final directory = Directory('${storageDirectory.path}/$relativeDirectory');
    await directory.create(recursive: true);
    await File('${directory.path}/SKILL.md').writeAsString('''
---
name: $name
description: $name description
---

# $name
''');
  }

  test('installed skill scan skips nested skill content', () async {
    await writeManifest('alpha', 'Alpha');
    await writeManifest('alpha/examples/nested', 'Nested');
    await writeManifest('beta/deeper', 'Beta');

    final skills = await SkillsRepository().loadInstalledSkills(
      storageDirectory.path,
    );

    expect(skills.map((skill) => skill.name), <String>['Alpha', 'Beta']);
    expect(skills.map((skill) => skill.relativeDirectoryPath), <String>[
      'alpha',
      'beta/deeper',
    ]);
  });

  test(
    'oversized manifests are isolated from other installed skills',
    () async {
      final oversizedDirectory = Directory(
        '${storageDirectory.path}/oversized',
      );
      await oversizedDirectory.create();
      await File(
        '${oversizedDirectory.path}/SKILL.md',
      ).writeAsString(List<String>.filled(2 * 1024 * 1024 + 1, 'x').join());
      await writeManifest('oversized/nested-healthy', 'Healthy');

      final skills = await SkillsRepository().loadInstalledSkills(
        storageDirectory.path,
      );

      expect(skills.map((skill) => skill.name), <String>['Healthy']);
    },
  );

  test('directory import copies a complete external skill', () async {
    final sourceDirectory = await Directory.systemTemp.createTemp(
      'openhand-external-skill-',
    );
    try {
      await File('${sourceDirectory.path}/SKILL.md').writeAsString('''
---
name: Imported
description: Imported description
---

# Imported
''');
      final assetDirectory = Directory('${sourceDirectory.path}/assets');
      await assetDirectory.create();
      await File('${assetDirectory.path}/example.txt').writeAsString('example');

      final skill = await SkillsRepository().importSkillDirectory(
        storageDirectory.path,
        sourceDirectory.path,
      );

      expect(skill.name, 'Imported');
      expect(await File('${skill.directoryPath}/SKILL.md').exists(), isTrue);
      expect(
        await File('${skill.directoryPath}/assets/example.txt').readAsString(),
        'example',
      );
    } finally {
      await sourceDirectory.delete(recursive: true);
    }
  });
}
