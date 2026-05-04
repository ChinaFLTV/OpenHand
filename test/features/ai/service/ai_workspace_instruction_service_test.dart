import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/ai_workspace_instruction_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'openhand_workspace_instruction_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'loads workspace instruction files asynchronously in stable order',
    () async {
      final projectDir = Directory(p.join(tempDir.path, 'project'));
      final rulesDir = Directory(p.join(projectDir.path, '.claude', 'rules'));
      await rulesDir.create(recursive: true);
      await File(p.join(projectDir.path, 'AGENTS.md')).writeAsString('agents');
      await File(p.join(projectDir.path, 'CLAUDE.md')).writeAsString('claude');
      await File(p.join(rulesDir.path, 'b.md')).writeAsString('rule b');
      await File(p.join(rulesDir.path, 'a.md')).writeAsString('rule a');
      await File(p.join(rulesDir.path, 'ignored.txt')).writeAsString('ignore');

      final service = AiWorkspaceInstructionService(cacheTtl: Duration.zero);

      final documents = await service.loadDocuments(
        startDirectory: projectDir.path,
      );

      expect(documents.map((item) => item.name), <String>[
        'AGENTS.md',
        'CLAUDE.md',
        'a.md',
        'b.md',
      ]);
      expect(documents.map((item) => item.content), <String>[
        'agents',
        'claude',
        'rule a',
        'rule b',
      ]);
    },
  );
}
