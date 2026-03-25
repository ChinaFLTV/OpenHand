import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openhand/features/ai/service/ai_workspace_instruction_service.dart';

void main() {
  test(
    'AiWorkspaceInstructionService loads global and ancestor instruction files',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'openhand-instructions-',
      );
      final homeDirectory = Directory(p.join(tempRoot.path, 'home'))
        ..createSync(recursive: true);
      final workspaceDirectory = Directory(p.join(tempRoot.path, 'workspace'))
        ..createSync(recursive: true);
      final nestedDirectory = Directory(p.join(workspaceDirectory.path, 'pkg'))
        ..createSync(recursive: true);

      final globalClaude =
          File(p.join(homeDirectory.path, '.claude', 'CLAUDE.md'))
            ..createSync(recursive: true)
            ..writeAsStringSync('Global Claude instructions');
      final workspaceAgents = File(p.join(workspaceDirectory.path, 'AGENTS.md'))
        ..writeAsStringSync('Workspace agent rules');
      final nestedClaude = File(p.join(nestedDirectory.path, 'CLAUDE.md'))
        ..writeAsStringSync('Nested Claude rules');
      final globalRule =
          File(
              p.join(
                homeDirectory.path,
                '.claude',
                'rules',
                'global-policy.md',
              ),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('Global policy rule');
      final workspaceRule =
          File(
              p.join(
                workspaceDirectory.path,
                '.claude',
                'rules',
                'workspace-rule.md',
              ),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync('Workspace scoped rule');

      final service = AiWorkspaceInstructionService();
      final documents = service.loadDocuments(
        startDirectory: nestedDirectory.path,
        homeDirectory: homeDirectory.path,
      );

      expect(
        documents.map((item) => item.path).toList(growable: false),
        <String>[
          p.normalize(globalClaude.path),
          p.normalize(globalRule.path),
          p.normalize(workspaceAgents.path),
          p.normalize(workspaceRule.path),
          p.normalize(nestedClaude.path),
        ],
      );
      expect(
        documents.map((item) => item.content).toList(growable: false),
        <String>[
          'Global Claude instructions',
          'Global policy rule',
          'Workspace agent rules',
          'Workspace scoped rule',
          'Nested Claude rules',
        ],
      );
    },
  );

  test(
    'AiWorkspaceInstructionService reuses a fresh cached document set',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'openhand-instructions-cache-',
      );
      addTearDown(() async {
        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final workspaceDirectory = Directory(p.join(tempRoot.path, 'workspace'))
        ..createSync(recursive: true);
      final agentsFile = File(p.join(workspaceDirectory.path, 'AGENTS.md'))
        ..writeAsStringSync('First rules');
      var now = DateTime.utc(2026, 3, 25, 1, 0, 0);
      final service = AiWorkspaceInstructionService(
        clock: () => now,
        cacheTtl: const Duration(seconds: 5),
      );

      final firstDocuments = service.loadDocuments(
        startDirectory: workspaceDirectory.path,
      );
      agentsFile.writeAsStringSync('Updated rules');
      now = now.add(const Duration(seconds: 1));
      final secondDocuments = service.loadDocuments(
        startDirectory: workspaceDirectory.path,
      );
      now = now.add(const Duration(seconds: 6));
      final thirdDocuments = service.loadDocuments(
        startDirectory: workspaceDirectory.path,
      );

      expect(firstDocuments.single.content, 'First rules');
      expect(secondDocuments.single.content, 'First rules');
      expect(thirdDocuments.single.content, 'Updated rules');
    },
  );
}
