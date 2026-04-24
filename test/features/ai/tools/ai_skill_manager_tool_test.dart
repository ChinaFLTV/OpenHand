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
}) {
  return tool.run(<String, Object?>{
    'action': action,
    if (name != null) 'name': name,
    if (category != null) 'category': category,
    if (content != null) 'content': content,
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
      expect(result.status, BashToolExecutionStatus.success, reason: result.stderr);
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
      final big = '---\nname: my-skill\ndescription: x\n---\n\n${'a' * 100_001}';
      final result = await _execute(
        tool,
        action: 'create',
        name: 'my-skill',
        content: big,
      );
      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('maximum'));
    });
  });
}
