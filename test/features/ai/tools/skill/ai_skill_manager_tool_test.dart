import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/tools/skill/ai_skill_manager_tool.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AiSkillManagerTool', () {
    late Directory tempDir;
    late AiSkillManagerTool tool;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('openhand_skill_tool_');
      tool = AiSkillManagerTool(skillsDirProvider: () => tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('creates a skill manifest with valid frontmatter', () async {
      final result = await tool.run(<String, Object?>{
        'action': 'create',
        'name': 'demo-skill',
        'content': _skillContent('demo-skill'),
      });

      expect(result.status, BashToolExecutionStatus.success);
      expect(
        await File(
          p.join(tempDir.path, 'demo-skill', 'SKILL.md'),
        ).readAsString(),
        _skillContent('demo-skill'),
      );
    });

    test('writes, patches, and removes allowed sidecar files', () async {
      await _createSkill(tool, 'demo-skill', category: 'tools');

      final writeResult = await tool.run(<String, Object?>{
        'action': 'write_file',
        'name': 'demo-skill',
        'file_path': 'references/nested/info.md',
        'content': 'hello old value\n',
      });
      expect(writeResult.status, BashToolExecutionStatus.success);

      final sidecar = File(
        p.join(
          tempDir.path,
          'tools',
          'demo-skill',
          'references',
          'nested',
          'info.md',
        ),
      );
      expect(await sidecar.readAsString(), 'hello old value\n');

      final patchResult = await tool.run(<String, Object?>{
        'action': 'patch',
        'name': 'demo-skill',
        'file_path': 'references/nested/info.md',
        'old_string': 'old',
        'new_string': 'new',
      });
      expect(patchResult.status, BashToolExecutionStatus.success);
      expect(await sidecar.readAsString(), 'hello new value\n');

      final removeResult = await tool.run(<String, Object?>{
        'action': 'remove_file',
        'name': 'demo-skill',
        'file_path': 'references/nested/info.md',
      });
      expect(removeResult.status, BashToolExecutionStatus.success);
      expect(await sidecar.exists(), isFalse);
      expect(
        await Directory(
          p.join(tempDir.path, 'tools', 'demo-skill', 'references'),
        ).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(tempDir.path, 'tools', 'demo-skill')).exists(),
        isTrue,
      );
    });

    test('rejects sidecar path traversal', () async {
      await _createSkill(tool, 'demo-skill');

      final result = await tool.run(<String, Object?>{
        'action': 'write_file',
        'name': 'demo-skill',
        'file_path': 'references/../outside.md',
        'content': 'nope',
      });

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('must not traverse parent directories'));
      expect(await File(p.join(tempDir.path, 'outside.md')).exists(), isFalse);
    });

    test('stops scanning oversized skill trees', () async {
      for (var i = 0; i < 5001; i++) {
        await File(p.join(tempDir.path, 'noise_$i.txt')).writeAsString('x');
      }

      final result = await tool.run(<String, Object?>{
        'action': 'edit',
        'name': 'missing-skill',
        'content': _skillContent('missing-skill'),
      });

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('Skill scan exceeded'));
    });
  });
}

Future<void> _createSkill(
  AiSkillManagerTool tool,
  String name, {
  String category = '',
}) async {
  final result = await tool.run(<String, Object?>{
    'action': 'create',
    'name': name,
    if (category.isNotEmpty) 'category': category,
    'content': _skillContent(name),
  });
  expect(result.status, BashToolExecutionStatus.success);
}

String _skillContent(String name) {
  return '---\n'
      'name: $name\n'
      'description: Test skill.\n'
      '---\n'
      'Body.\n';
}
