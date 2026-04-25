import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_skill_manager_tool.dart';
import 'package:path/path.dart' as p;

const _goodSkill = '''---
name: my-skill
description: Test skill
version: 1.0.0
---

# My Skill

Body.''';

Future<AiToolExecutionResult> _execute(
  AiSkillManagerTool tool, {
  required String action,
  String? name,
  String? category,
  String? content,
  String? oldString,
  String? newString,
  bool? replaceAll,
  String? filePath,
}) {
  return tool.run(<String, Object?>{
    'action': action,
    if (name != null) 'name': name,
    if (category != null) 'category': category,
    if (content != null) 'content': content,
    if (oldString != null) 'old_string': oldString,
    if (newString != null) 'new_string': newString,
    if (replaceAll != null) 'replace_all': replaceAll,
    if (filePath != null) 'file_path': filePath,
  });
}

void main() {
  late Directory tmp;
  late AiSkillManagerTool tool;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('skills_');
    tool = AiSkillManagerTool(skillsDirProvider: () => tmp.path);
  });

  tearDown(() async {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  group('AiSkillManagerTool', () {
    test('create with valid name + frontmatter succeeds', () async {
      final result = await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: _goodSkill,
      );
      expect(
        result.status,
        BashToolExecutionStatus.success,
        reason: result.stderr,
      );
      final file = File(p.join(tmp.path, 'my-skill', 'SKILL.md'));
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), _goodSkill);
    });

    test('create with invalid name fails', () async {
      final uppercase = await _execute(
        tool,
        action: 'create',
        name: 'Bad-Name',
        content: _goodSkill,
      );
      expect(uppercase.status, BashToolExecutionStatus.invalidArguments);

      final spaces = await _execute(
        tool,
        action: 'create',
        name: 'bad name',
        content: _goodSkill,
      );
      expect(spaces.status, BashToolExecutionStatus.invalidArguments);

      final exclaim = await _execute(
        tool,
        action: 'create',
        name: 'bad!',
        content: _goodSkill,
      );
      expect(exclaim.status, BashToolExecutionStatus.invalidArguments);
    });

    test('create collision (same name, different category) fails', () async {
      final first = await _execute(
        tool,
        action: 'create',
        name: 'shared',
        content: _goodSkill,
      );
      expect(first.status, BashToolExecutionStatus.success);

      final collision = await _execute(
        tool,
        action: 'create',
        name: 'shared',
        category: 'other',
        content: _goodSkill,
      );
      expect(collision.status, BashToolExecutionStatus.invalidArguments);
      expect(collision.stderr, contains('already exists'));
    });

    test('create frontmatter missing description fails', () async {
      const body = '''---
name: my-skill
---

Body.''';
      final result = await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: body,
      );
      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('description'));
    });

    test('create content > 100_000 chars fails', () async {
      final big =
          '---\nname: my-skill\ndescription: x\n---\n\n${'a' * 100_001}';
      final result = await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: big,
      );
      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('maximum'));
    });

    test('edit rewrites SKILL.md of existing skill', () async {
      await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: _goodSkill,
      );
      const updated = '''---
name: my-skill
description: Updated desc
---

# Rewritten

New body.''';
      final edit = await _execute(
        tool,
        action: 'edit',
        name: 'my-skill',
        content: updated,
      );
      expect(edit.status, BashToolExecutionStatus.success, reason: edit.stderr);
      expect(
        File(p.join(tmp.path, 'my-skill', 'SKILL.md')).readAsStringSync(),
        updated,
      );
    });

    test('edit of missing skill fails', () async {
      final edit = await _execute(
        tool,
        action: 'edit',
        name: 'ghost',
        content: _goodSkill,
      );
      expect(edit.status, BashToolExecutionStatus.invalidArguments);
      expect(edit.stderr, contains('not found'));
    });

    test('delete removes skill directory and cleans empty category', () async {
      await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        category: 'cat',
        content: _goodSkill,
      );
      final skillDir = Directory(p.join(tmp.path, 'cat', 'my-skill'));
      expect(skillDir.existsSync(), isTrue);

      final del = await _execute(tool, action: 'delete', name: 'my-skill');
      expect(del.status, BashToolExecutionStatus.success, reason: del.stderr);
      expect(skillDir.existsSync(), isFalse);
      // Category directory should have been cleaned up (was empty).
      expect(Directory(p.join(tmp.path, 'cat')).existsSync(), isFalse);
    });

    test('delete of missing skill fails', () async {
      final del = await _execute(tool, action: 'delete', name: 'ghost');
      expect(del.status, BashToolExecutionStatus.invalidArguments);
    });

    test('patch with unique match replaces once', () async {
      await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: _goodSkill,
      );
      final patch = await _execute(
        tool,
        action: 'patch',
        name: 'my-skill',
        oldString: 'Body.',
        newString: 'New body line.',
      );
      expect(
        patch.status,
        BashToolExecutionStatus.success,
        reason: patch.stderr,
      );
      final text = File(
        p.join(tmp.path, 'my-skill', 'SKILL.md'),
      ).readAsStringSync();
      expect(text, contains('New body line.'));
      expect(text, isNot(contains('Body.')));
    });

    test('patch with multiple matches + replace_all=false fails', () async {
      const body = '''---
name: my-skill
description: x
---

alpha alpha alpha''';
      await _execute(tool, action: 'create', name: 'my-skill', content: body);
      final patch = await _execute(
        tool,
        action: 'patch',
        name: 'my-skill',
        oldString: 'alpha',
        newString: 'beta',
      );
      expect(patch.status, BashToolExecutionStatus.invalidArguments);
      expect(patch.stderr, contains('3 occurrences'));
    });

    test('patch with replace_all=true replaces all', () async {
      const body = '''---
name: my-skill
description: x
---

alpha alpha alpha''';
      await _execute(tool, action: 'create', name: 'my-skill', content: body);
      final patch = await _execute(
        tool,
        action: 'patch',
        name: 'my-skill',
        oldString: 'alpha',
        newString: 'beta',
        replaceAll: true,
      );
      expect(
        patch.status,
        BashToolExecutionStatus.success,
        reason: patch.stderr,
      );
      final text = File(
        p.join(tmp.path, 'my-skill', 'SKILL.md'),
      ).readAsStringSync();
      expect(text, contains('beta beta beta'));
    });

    test('patch that breaks frontmatter is rejected without writing', () async {
      await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: _goodSkill,
      );
      final before = File(
        p.join(tmp.path, 'my-skill', 'SKILL.md'),
      ).readAsStringSync();
      final patch = await _execute(
        tool,
        action: 'patch',
        name: 'my-skill',
        oldString: 'description: Test skill',
        newString: '',
      );
      expect(patch.status, BashToolExecutionStatus.invalidArguments);
      expect(patch.stderr, contains('frontmatter'));
      final after = File(
        p.join(tmp.path, 'my-skill', 'SKILL.md'),
      ).readAsStringSync();
      expect(
        after,
        before,
        reason: 'file must not be written on validation failure',
      );
    });

    test('write_file into allowed subdir succeeds', () async {
      await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: _goodSkill,
      );
      final write = await _execute(
        tool,
        action: 'write_file',
        name: 'my-skill',
        filePath: 'scripts/run.sh',
        content: '#!/bin/bash\necho hi\n',
      );
      expect(
        write.status,
        BashToolExecutionStatus.success,
        reason: write.stderr,
      );
      expect(
        File(p.join(tmp.path, 'my-skill', 'scripts', 'run.sh')).existsSync(),
        isTrue,
      );
    });

    test('write_file to disallowed subdir fails', () async {
      await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: _goodSkill,
      );
      final write = await _execute(
        tool,
        action: 'write_file',
        name: 'my-skill',
        filePath: 'secrets/key.txt',
        content: 'bad',
      );
      expect(write.status, BashToolExecutionStatus.invalidArguments);
    });

    test('write_file rejects path traversal', () async {
      await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: _goodSkill,
      );
      final write = await _execute(
        tool,
        action: 'write_file',
        name: 'my-skill',
        filePath: 'scripts/../../evil.txt',
        content: 'x',
      );
      expect(write.status, BashToolExecutionStatus.invalidArguments);
    });

    test('write_file refuses to target SKILL.md', () async {
      await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: _goodSkill,
      );
      final write = await _execute(
        tool,
        action: 'write_file',
        name: 'my-skill',
        filePath: 'SKILL.md',
        content: 'x',
      );
      expect(write.status, BashToolExecutionStatus.invalidArguments);
    });

    test('remove_file removes nested file and cleans empty parents', () async {
      await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: _goodSkill,
      );
      await _execute(
        tool,
        action: 'write_file',
        name: 'my-skill',
        filePath: 'references/docs/intro.md',
        content: 'hi',
      );
      final rm = await _execute(
        tool,
        action: 'remove_file',
        name: 'my-skill',
        filePath: 'references/docs/intro.md',
      );
      expect(rm.status, BashToolExecutionStatus.success, reason: rm.stderr);
      expect(
        Directory(p.join(tmp.path, 'my-skill', 'references')).existsSync(),
        isFalse,
        reason: 'empty references/ should be cleaned up',
      );
      expect(
        Directory(p.join(tmp.path, 'my-skill')).existsSync(),
        isTrue,
        reason: 'skill dir itself must not be removed',
      );
    });

    test('remove_file of missing file fails', () async {
      await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: _goodSkill,
      );
      final rm = await _execute(
        tool,
        action: 'remove_file',
        name: 'my-skill',
        filePath: 'scripts/missing.sh',
      );
      expect(rm.status, BashToolExecutionStatus.invalidArguments);
    });

    test('remove_file refuses to target SKILL.md', () async {
      await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: _goodSkill,
      );
      final rm = await _execute(
        tool,
        action: 'remove_file',
        name: 'my-skill',
        filePath: 'SKILL.md',
      );
      expect(rm.status, BashToolExecutionStatus.invalidArguments);
    });
  });
}
