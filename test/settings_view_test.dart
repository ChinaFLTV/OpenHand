import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:openhand/features/skills/data/skills_repository.dart';
import 'package:openhand/features/skills/model/local_skill.dart';

void main() {
  test(
    'SkillsRepository scans, imports, updates, and deletes skills',
    () async {
      final repository = SkillsRepository();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_repository_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final existingSkillDirectory = Directory(
        p.join(tempDirectory.path, 'sample-skill'),
      );
      await existingSkillDirectory.create(recursive: true);
      await File(p.join(existingSkillDirectory.path, 'SKILL.md')).writeAsString(
        '''
---
name: Sample Skill
description: A sample local skill.
---

# Sample Skill
''',
      );

      final initialSkills = await repository.loadInstalledSkills(
        tempDirectory.path,
      );
      expect(initialSkills, hasLength(1));
      expect(initialSkills.first.name, 'Sample Skill');

      final createdSkill = await repository.createSkill(
        tempDirectory.path,
        name: 'Planner Skill',
        emojiIcon: '🧠',
        imageIconBytes: null,
        shortDescription: 'Custom planning skill.',
        manifestContent: '''
---
description: Custom planning skill.
---

# Planner Skill

Help plan multi-step work.
''',
      );
      final updatedSkills = await repository.loadInstalledSkills(
        tempDirectory.path,
      );

      expect(createdSkill.name, 'Planner Skill');
      expect(createdSkill.description, 'Custom planning skill.');
      expect(createdSkill.emojiIcon, '🧠');
      expect(updatedSkills, hasLength(2));
      final createdManifest = File(
        p.join(createdSkill.directoryPath, 'SKILL.md'),
      );
      expect(createdManifest.existsSync(), isTrue);
      expect(await createdManifest.readAsString(), contains('icon: "🧠"'));
      expect(
        await createdManifest.readAsString(),
        contains('description: "Custom planning skill."'),
      );
      final openAiMetadataFile = File(
        p.join(createdSkill.directoryPath, 'agents', 'openai.yaml'),
      );
      final generatedIconFile = File(
        p.join(
          createdSkill.directoryPath,
          'agents',
          'assets',
          'skill-icon.svg',
        ),
      );
      expect(openAiMetadataFile.existsSync(), isTrue);
      expect(generatedIconFile.existsSync(), isTrue);
      expect(
        await openAiMetadataFile.readAsString(),
        contains('display_name: "Planner Skill"'),
      );
      expect(
        await openAiMetadataFile.readAsString(),
        contains('short_description: "Custom planning skill."'),
      );
      expect(
        await openAiMetadataFile.readAsString(),
        contains('icon_small: "./assets/skill-icon.svg"'),
      );
      expect(
        await openAiMetadataFile.readAsString(),
        contains('default_prompt: "Help plan multi-step work."'),
      );
      expect(createdSkill.iconKind, LocalSkillIconKind.svg);
      expect(createdSkill.iconPath, endsWith('agents/assets/skill-icon.svg'));

      final updatedCreatedSkill = await repository.updateSkill(
        createdSkill,
        tempDirectory.path,
        name: 'Planner Skill Updated',
        emojiIcon: '🧠',
        imageIconBytes: null,
        shortDescription: 'Updated planning skill description.',
        manifestContent: '''
---
name: Planner Skill Updated
description: Updated planning skill description.
icon: "🧠"
---

# Planner Skill Updated

Drive a refreshed multi-step plan.
''',
      );
      expect(updatedCreatedSkill.name, 'Planner Skill Updated');
      expect(
        updatedCreatedSkill.description,
        'Updated planning skill description.',
      );
      expect(
        await openAiMetadataFile.readAsString(),
        contains('display_name: "Planner Skill Updated"'),
      );
      expect(
        await openAiMetadataFile.readAsString(),
        contains('short_description: "Updated planning skill description."'),
      );
      expect(
        await openAiMetadataFile.readAsString(),
        contains('default_prompt: "Drive a refreshed multi-step plan."'),
      );
      expect(
        await openAiMetadataFile.readAsString(),
        contains('icon_small: "./assets/skill-icon.svg"'),
      );
      expect(
        await File(updatedCreatedSkill.manifestPath).readAsString(),
        contains('description: "Updated planning skill description."'),
      );

      final importSource = await Directory.systemTemp.createTemp(
        'openhand_skills_import_test_',
      );
      addTearDown(() => importSource.delete(recursive: true));
      await File(p.join(importSource.path, 'SKILL.md')).writeAsString('''
---
name: Imported Skill
description: Imported from another directory.
---

# Imported Skill
''');

      final importedSkill = await repository.importSkillDirectory(
        tempDirectory.path,
        importSource.path,
      );
      expect(importedSkill.name, 'Imported Skill');

      final manifestContent = await repository.readSkillManifest(importedSkill);
      expect(manifestContent, contains('Imported Skill'));

      final updatedImportedSkill = await repository.updateSkillManifest(
        importedSkill,
        tempDirectory.path,
        '''
---
name: Imported Skill Updated
description: Updated content.
---

# Imported Skill Updated
''',
      );
      expect(updatedImportedSkill.name, 'Imported Skill Updated');

      await repository.deleteSkill(updatedImportedSkill, tempDirectory.path);
      final finalSkills = await repository.loadInstalledSkills(
        tempDirectory.path,
      );
      expect(finalSkills, hasLength(2));
    },
  );

  test(
    'SkillsRepository template creation also writes OpenAI metadata',
    () async {
      final repository = SkillsRepository();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_template_metadata_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final createdSkill = await repository.createSkillTemplate(
        tempDirectory.path,
      );
      final openAiMetadataFile = File(
        p.join(createdSkill.directoryPath, 'agents', 'openai.yaml'),
      );
      final generatedIconFile = File(
        p.join(
          createdSkill.directoryPath,
          'agents',
          'assets',
          'skill-icon.svg',
        ),
      );

      expect(openAiMetadataFile.existsSync(), isTrue);
      expect(generatedIconFile.existsSync(), isTrue);
      expect(
        await openAiMetadataFile.readAsString(),
        contains('display_name: "${createdSkill.name}"'),
      );
      expect(
        await openAiMetadataFile.readAsString(),
        contains('short_description: "Describe what this skill does."'),
      );
      expect(
        await openAiMetadataFile.readAsString(),
        contains('icon_small: "./assets/skill-icon.svg"'),
      );
      expect(createdSkill.iconKind, LocalSkillIconKind.svg);
      expect(createdSkill.iconPath, endsWith('agents/assets/skill-icon.svg'));
    },
  );

  test(
    'SkillsRepository updateSkill preserves existing OpenAI icon paths',
    () async {
      final repository = SkillsRepository();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_update_preserve_icon_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final skillDirectory = Directory(
        p.join(tempDirectory.path, 'speech-skill'),
      );
      await skillDirectory.create(recursive: true);
      await File(p.join(skillDirectory.path, 'SKILL.md')).writeAsString('''
---
name: Speech Generation Skill
description: Generate narrated audio from text
---

# Speech Generation Skill

Generate spoken audio for this text with the right voice style.
''');
      final agentsDirectory = Directory(p.join(skillDirectory.path, 'agents'));
      await agentsDirectory.create(recursive: true);
      final assetsDirectory = Directory(p.join(agentsDirectory.path, 'assets'));
      await assetsDirectory.create(recursive: true);
      await File(
        p.join(assetsDirectory.path, 'speech-small.svg'),
      ).writeAsString('''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <circle cx="16" cy="16" r="12" fill="#4E93C8"/>
</svg>
''');
      await File(p.join(agentsDirectory.path, 'openai.yaml')).writeAsString('''
interface:
  display_name: "Speech Generation Skill"
  short_description: "Generate narrated audio from text"
  icon_small: "./assets/speech-small.svg"
  icon_large: "./assets/speech-small.svg"
  default_prompt: "Generate spoken audio for this text with the right voice style."
''');

      final loadedSkill = (await repository.loadInstalledSkills(
        tempDirectory.path,
      )).single;
      final updatedSkill = await repository.updateSkill(
        loadedSkill,
        tempDirectory.path,
        name: 'Speech Generation Skill Updated',
        shortDescription: 'Generate polished spoken audio from text',
        manifestContent: '''
---
name: Speech Generation Skill Updated
description: Generate polished spoken audio from text
---

# Speech Generation Skill Updated

Produce refined spoken audio for the supplied text.
''',
        preserveExistingIcon: true,
      );

      final openAiMetadataContent = await File(
        p.join(updatedSkill.directoryPath, 'agents', 'openai.yaml'),
      ).readAsString();
      expect(updatedSkill.name, 'Speech Generation Skill Updated');
      expect(
        updatedSkill.description,
        'Generate polished spoken audio from text',
      );
      expect(
        openAiMetadataContent,
        contains('display_name: "Speech Generation Skill Updated"'),
      );
      expect(
        openAiMetadataContent,
        contains(
          'short_description: "Generate polished spoken audio from text"',
        ),
      );
      expect(
        openAiMetadataContent,
        contains('icon_small: "./assets/speech-small.svg"'),
      );
      expect(
        openAiMetadataContent,
        contains(
          'default_prompt: "Produce refined spoken audio for the supplied text."',
        ),
      );
      expect(updatedSkill.iconKind, LocalSkillIconKind.svg);
      expect(updatedSkill.iconPath, endsWith('agents/assets/speech-small.svg'));
    },
  );

  test(
    'SkillsRepository stores edited local image icons as OpenAI assets',
    () async {
      final repository = SkillsRepository();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_local_image_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final sourceImage = img.Image(width: 24, height: 12);
      for (var y = 0; y < sourceImage.height; y++) {
        for (var x = 0; x < sourceImage.width; x++) {
          sourceImage.setPixelRgba(x, y, 40 + x * 8, 120 + y * 8, 180, 255);
        }
      }
      final iconBytes = Uint8List.fromList(img.encodePng(sourceImage));

      final createdSkill = await repository.createSkill(
        tempDirectory.path,
        name: 'Raster Skill',
        emojiIcon: null,
        imageIconBytes: iconBytes,
        shortDescription: 'Use a local image as the skill icon.',
        manifestContent: '''
# Raster Skill

Summarize the selected image workflow.
''',
      );

      final openAiMetadataFile = File(
        p.join(createdSkill.directoryPath, 'agents', 'openai.yaml'),
      );
      final generatedIconFile = File(
        p.join(
          createdSkill.directoryPath,
          'agents',
          'assets',
          'skill-icon.png',
        ),
      );

      expect(openAiMetadataFile.existsSync(), isTrue);
      expect(generatedIconFile.existsSync(), isTrue);
      expect(
        await openAiMetadataFile.readAsString(),
        contains('icon_small: "./assets/skill-icon.png"'),
      );
      expect(createdSkill.iconKind, LocalSkillIconKind.raster);
      expect(createdSkill.iconPath, endsWith('agents/assets/skill-icon.png'));
    },
  );

  test(
    'SkillsRepository ignores OpenAI icon paths outside the skill directory',
    () async {
      final repository = SkillsRepository();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_external_icon_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final skillDirectory = Directory(
        p.join(tempDirectory.path, 'external-icon-skill'),
      );
      await skillDirectory.create(recursive: true);
      await File(p.join(skillDirectory.path, 'SKILL.md')).writeAsString('''
---
name: External Icon Skill
description: Metadata should not load icons outside the skill root.
---

# External Icon Skill
''');
      final agentsDirectory = Directory(p.join(skillDirectory.path, 'agents'));
      await agentsDirectory.create(recursive: true);
      final outsideIcon = File(p.join(tempDirectory.path, 'outside-icon.svg'));
      await outsideIcon.writeAsString(
        '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
      );
      await File(p.join(agentsDirectory.path, 'openai.yaml')).writeAsString('''
interface:
  display_name: "External Icon Skill"
  short_description: "Metadata should not load icons outside the skill root."
  icon_small: "${outsideIcon.path.replaceAll(r'\\', r'\\\\')}"
  default_prompt: "Stay inside the skill sandbox."
''');

      final skills = await repository.loadInstalledSkills(tempDirectory.path);

      expect(skills, hasLength(1));
      expect(skills.single.name, 'External Icon Skill');
      expect(skills.single.iconPath, isNull);
      expect(skills.single.iconKind, isNull);
    },
  );

  test(
    'SkillsRepository reads OpenAI Codex skill metadata when available',
    () async {
      final repository = SkillsRepository();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_openai_metadata_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final skillDirectory = Directory(
        p.join(tempDirectory.path, 'speech-skill'),
      );
      await skillDirectory.create(recursive: true);
      await File(p.join(skillDirectory.path, 'SKILL.md')).writeAsString('''
---
name: Generic Skill
description: Generic fallback description.
---

# Generic Skill
''');
      final agentsDirectory = Directory(p.join(skillDirectory.path, 'agents'));
      await agentsDirectory.create(recursive: true);
      final assetsDirectory = Directory(p.join(agentsDirectory.path, 'assets'));
      await assetsDirectory.create(recursive: true);
      await File(
        p.join(assetsDirectory.path, 'speech-small.svg'),
      ).writeAsString('''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <circle cx="16" cy="16" r="12" fill="#4E93C8"/>
</svg>
''');
      await File(p.join(agentsDirectory.path, 'openai.yaml')).writeAsString('''
interface:
  display_name: "Speech Generation Skill"
  short_description: "Generate narrated audio from text"
  icon_small: "./assets/speech-small.svg"
  icon_large: "./assets/speech.png"
  default_prompt: "Generate spoken audio for this text with the right voice style."
''');

      final skills = await repository.loadInstalledSkills(tempDirectory.path);

      expect(skills, hasLength(1));
      expect(skills.single.name, 'Speech Generation Skill');
      expect(skills.single.description, 'Generate narrated audio from text');
      expect(
        skills.single.defaultPrompt,
        'Generate spoken audio for this text with the right voice style.',
      );
      expect(skills.single.iconKind, LocalSkillIconKind.svg);
      expect(skills.single.iconPath, endsWith('speech-small.svg'));
    },
  );

  test(
    'SkillsRepository resolves OpenAI icon paths relative to the skill root',
    () async {
      final repository = SkillsRepository();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_openai_root_icon_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final skillDirectory = Directory(
        p.join(tempDirectory.path, 'speech-skill-root-assets'),
      );
      await skillDirectory.create(recursive: true);
      await File(p.join(skillDirectory.path, 'SKILL.md')).writeAsString('''
---
name: Root Asset Skill
description: Root asset fallback description.
---

# Root Asset Skill
''');
      final agentsDirectory = Directory(p.join(skillDirectory.path, 'agents'));
      await agentsDirectory.create(recursive: true);
      final assetsDirectory = Directory(p.join(skillDirectory.path, 'assets'));
      await assetsDirectory.create(recursive: true);
      await File(
        p.join(assetsDirectory.path, 'speech-small.svg'),
      ).writeAsString('''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <rect x="6" y="6" width="20" height="20" rx="6" fill="#4E93C8"/>
</svg>
''');
      await File(p.join(agentsDirectory.path, 'openai.yaml')).writeAsString('''
interface:
  display_name: "Speech Root Icon Skill"
  short_description: "Resolve icon from the skill root"
  icon_small: "./assets/speech-small.svg"
''');

      final skills = await repository.loadInstalledSkills(tempDirectory.path);

      expect(skills, hasLength(1));
      expect(skills.single.name, 'Speech Root Icon Skill');
      expect(skills.single.iconKind, LocalSkillIconKind.svg);
      expect(skills.single.iconPath, endsWith('assets/speech-small.svg'));
    },
  );

  test('SkillsRepository falls back when OpenAI metadata is invalid', () async {
    final repository = SkillsRepository();
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_skills_openai_fallback_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final skillDirectory = Directory(
      p.join(tempDirectory.path, 'broken-skill'),
    );
    await skillDirectory.create(recursive: true);
    await File(p.join(skillDirectory.path, 'SKILL.md')).writeAsString('''
---
name: "Fallback Skill"
description: "Fallback description."
---

# Fallback Skill
''');
    final agentsDirectory = Directory(p.join(skillDirectory.path, 'agents'));
    await agentsDirectory.create(recursive: true);
    await File(
      p.join(agentsDirectory.path, 'openai.yaml'),
    ).writeAsString('interface: [broken');

    final skills = await repository.loadInstalledSkills(tempDirectory.path);

    expect(skills, hasLength(1));
    expect(skills.single.name, 'Fallback Skill');
    expect(skills.single.description, 'Fallback description.');
    expect(skills.single.defaultPrompt, isNull);
    expect(skills.single.iconPath, isNull);
    expect(skills.single.iconKind, isNull);
  });

  test(
    'SkillsRepository skips unreadable skill manifests while loading others',
    () async {
      final repository = SkillsRepository();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_skip_invalid_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final validSkillDirectory = Directory(
        p.join(tempDirectory.path, 'valid-skill'),
      );
      await validSkillDirectory.create(recursive: true);
      await File(p.join(validSkillDirectory.path, 'SKILL.md')).writeAsString('''
---
name: Valid Skill
description: Should still load.
---

# Valid Skill
''');

      final invalidSkillDirectory = Directory(
        p.join(tempDirectory.path, 'invalid-skill'),
      );
      await invalidSkillDirectory.create(recursive: true);
      await File(
        p.join(invalidSkillDirectory.path, 'SKILL.md'),
      ).writeAsBytes(const <int>[0xff, 0xfe, 0xff], flush: true);

      final skills = await repository.loadInstalledSkills(tempDirectory.path);

      expect(skills, hasLength(1));
      expect(skills.single.name, 'Valid Skill');
    },
  );

  test(
    'SkillsRepository rolls back manifest changes when OpenAI metadata update fails',
    () async {
      final repository = SkillsRepository();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_update_rollback_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final skillDirectory = Directory(
        p.join(tempDirectory.path, 'broken-metadata-skill'),
      );
      await skillDirectory.create(recursive: true);
      final manifestFile = File(p.join(skillDirectory.path, 'SKILL.md'));
      await manifestFile.writeAsString('''
---
name: Stable Skill
description: Original description.
---

# Stable Skill
''');
      await File(
        p.join(skillDirectory.path, 'agents'),
      ).writeAsString('block metadata directory creation');

      final skill = (await repository.loadInstalledSkills(
        tempDirectory.path,
      )).single;

      await expectLater(
        () => repository.updateSkill(
          skill,
          tempDirectory.path,
          name: 'Broken Update',
          emojiIcon: '🧠',
          imageIconBytes: null,
          shortDescription: 'Updated description.',
          manifestContent: '''
---
name: Broken Update
description: Updated description.
---

# Broken Update
''',
        ),
        throwsA(isA<FileSystemException>()),
      );

      final restoredManifest = await manifestFile.readAsString();
      expect(restoredManifest, contains('name: Stable Skill'));
      expect(restoredManifest, contains('description: Original description.'));
      expect(restoredManifest, isNot(contains('Broken Update')));

      final reloadedSkill = (await repository.loadInstalledSkills(
        tempDirectory.path,
      )).single;
      expect(reloadedSkill.name, 'Stable Skill');
      expect(reloadedSkill.description, 'Original description.');
    },
  );

  test(
    'SkillsRepository ignores nested manifests inside an installed skill directory',
    () async {
      final repository = SkillsRepository();
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_nested_manifest_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));

      final parentSkillDirectory = Directory(
        p.join(tempDirectory.path, 'parent-skill'),
      );
      await parentSkillDirectory.create(recursive: true);
      await File(p.join(parentSkillDirectory.path, 'SKILL.md')).writeAsString(
        '''
---
name: Parent Skill
description: The real installed skill.
---

# Parent Skill
''',
      );

      final nestedDirectory = Directory(
        p.join(parentSkillDirectory.path, 'references', 'example-skill'),
      );
      await nestedDirectory.create(recursive: true);
      await File(p.join(nestedDirectory.path, 'SKILL.md')).writeAsString('''
---
name: Nested Skill
description: Should not appear as an installed skill.
---

# Nested Skill
''');

      final skills = await repository.loadInstalledSkills(tempDirectory.path);

      expect(skills, hasLength(1));
      expect(skills.single.name, 'Parent Skill');
      expect(skills.single.relativeDirectoryPath, 'parent-skill');
    },
  );

  test(
    'SkillsRepository removes copied directories when import parsing fails',
    () async {
      final repository = SkillsRepository();
      final storageDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_import_cleanup_storage_test_',
      );
      final sourceDirectory = await Directory.systemTemp.createTemp(
        'openhand_skills_import_cleanup_source_test_',
      );
      addTearDown(() => storageDirectory.delete(recursive: true));
      addTearDown(() => sourceDirectory.delete(recursive: true));

      await File(
        p.join(sourceDirectory.path, 'SKILL.md'),
      ).writeAsBytes(const <int>[0xff, 0xfe, 0xff], flush: true);

      await expectLater(
        () => repository.importSkillDirectory(
          storageDirectory.path,
          sourceDirectory.path,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await storageDirectory.list().toList(), isEmpty);
    },
  );
}
