import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/workspace/ai_workspace_instruction_service.dart';

import '../../support/test_directory.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory projectDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-workspace-instructions-',
    );
    projectDirectory = Directory('${temporaryDirectory.path}/project');
    await projectDirectory.create();
  });

  tearDown(() => deleteTestDirectory(temporaryDirectory));

  test('loads and truncates a bounded workspace instruction', () async {
    final instructionFile = File('${projectDirectory.path}/AGENTS.md');
    await instructionFile.writeAsString('0123456789');
    final service = AiWorkspaceInstructionService(cacheTtl: Duration.zero)
      ..maxDocumentCharacters = 5;

    final documents = await service.loadDocuments(
      startDirectory: projectDirectory.path,
    );

    final document = documents.singleWhere(
      (item) => item.path == instructionFile.path,
    );
    expect(document.content, '01234\n\n...[truncated]');
  });

  test('ignores an oversized workspace instruction', () async {
    final instructionFile = File('${projectDirectory.path}/AGENTS.md');
    await instructionFile.writeAsString('x' * (256 * 1024 + 1));
    final service = AiWorkspaceInstructionService(cacheTtl: Duration.zero);

    final documents = await service.loadDocuments(
      startDirectory: projectDirectory.path,
    );

    expect(
      documents.where((item) => item.path == instructionFile.path),
      isEmpty,
    );
  });

  test('limits rule files discovered in one directory', () async {
    final rulesDirectory = Directory('${projectDirectory.path}/.claude/rules');
    await rulesDirectory.create(recursive: true);
    for (var index = 0; index < 140; index++) {
      await File('${rulesDirectory.path}/rule-$index.md').writeAsString('rule');
    }
    final service = AiWorkspaceInstructionService(cacheTtl: Duration.zero);

    final documents = await service.loadDocuments(
      startDirectory: projectDirectory.path,
    );

    expect(
      documents.where((item) => item.path.startsWith(rulesDirectory.path)),
      hasLength(128),
    );
  });
}
