import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/git/ai_git_tool.dart';

void main() {
  group('AiGitTool', () {
    test('rejects unsupported operations as invalid arguments', () async {
      final repoDir = await Directory.systemTemp.createTemp(
        'openhand_git_tool_test_',
      );
      addTearDown(() async {
        if (await repoDir.exists()) {
          await repoDir.delete(recursive: true);
        }
      });

      final result = await _executeGit(<String, Object?>{
        'operation': 'commit',
        'working_directory': repoDir.path,
      });

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.workingDirectory, repoDir.path);
      expect(result.stderr, contains('Unsupported Git operation "commit"'));
      expect(result.stderr, contains('status, diff, log'));
      expect(result.toToolOutput(), startsWith('status: invalid_arguments'));
    });

    test('reports Git argument validation as invalid arguments', () async {
      final repoDir = await Directory.systemTemp.createTemp(
        'openhand_git_tool_test_',
      );
      addTearDown(() async {
        if (await repoDir.exists()) {
          await repoDir.delete(recursive: true);
        }
      });

      final result = await _executeGit(<String, Object?>{
        'operation': 'show',
        'target': '-p',
        'working_directory': repoDir.path,
      });

      expect(result.status.storageValue, 'invalid_arguments');
      expect(result.stderr, contains('Git show ref must not start with "-"'));
      expect(result.toToolOutput(), startsWith('status: invalid_arguments'));
    });

    test('show reads target ref from the public schema field', () async {
      final repoDir = await Directory.systemTemp.createTemp(
        'openhand_git_tool_test_',
      );
      addTearDown(() async {
        if (await repoDir.exists()) {
          await repoDir.delete(recursive: true);
        }
      });

      await _runGit(repoDir, <String>['init']);
      await _runGit(repoDir, <String>['config', 'user.name', 'OpenHand Test']);
      await _runGit(repoDir, <String>[
        'config',
        'user.email',
        'openhand-test@example.invalid',
      ]);
      await File('${repoDir.path}/sample.txt').writeAsString('hello\n');
      await _runGit(repoDir, <String>['add', 'sample.txt']);
      await _runGit(repoDir, <String>['commit', '-m', 'initial']);
      final head = (await _runGit(repoDir, <String>[
        'rev-parse',
        'HEAD',
      ])).trim();

      final result = await _executeGit(<String, Object?>{
        'operation': 'show',
        'target': head,
        'working_directory': repoDir.path,
      }, id: 'git-show');

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains('sample.txt'));
      expect(result.stdout, contains('+hello'));
    });
  });
}

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

Future<AiToolExecutionResult> _executeGit(
  Map<String, Object?> args, {
  String id = 'git-test',
}) {
  return AiGitTool().execute(
    AiToolExecutionContext(
      sessionId: 'test-session',
      catalog: const AiResolvedToolCatalog(
        definitions: <AiToolDefinition>[],
        toolsByName: <String, AiResolvedTool>{},
      ),
      toolCall: AiToolCall(id: id, name: 'Git', arguments: jsonEncode(args)),
      decodedArguments: args,
      model: _testModel,
      previouslyReadFiles: <String>{},
      denyCommandRules: const <Never>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: null,
    ),
  );
}

Future<String> _runGit(Directory repoDir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: repoDir.path);
  if (result.exitCode != 0) {
    fail(
      'git ${args.join(' ')} failed with ${result.exitCode}\n'
      'stdout: ${result.stdout}\n'
      'stderr: ${result.stderr}',
    );
  }
  return '${result.stdout}';
}
