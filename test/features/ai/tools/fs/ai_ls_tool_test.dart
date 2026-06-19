import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/fs/ai_ls_tool.dart';

void main() {
  group('AiLsTool', () {
    late Directory tempDir;
    late String originalWorkingDirectory;

    setUp(() {
      originalWorkingDirectory = Directory.current.path;
      tempDir = Directory.systemTemp.createTempSync('openhand-ls-test-');
    });

    tearDown(() {
      Directory.current = originalWorkingDirectory;
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'defaults omitted path to the working directory and applies ignore',
      () async {
        Directory.current = tempDir.path;
        Directory('${tempDir.path}/lib').createSync();
        File(
          '${tempDir.path}/visible.dart',
        ).writeAsStringSync('void main() {}\n');
        File('${tempDir.path}/ignored.log').writeAsStringSync('debug\n');

        final result = await AiLsTool().execute(
          _context(<String, Object?>{
            'ignore': <String>['*.log'],
          }),
        );

        expect(result.status, BashToolExecutionStatus.success);
        expect(result.stdout, contains('dir\tlib'));
        expect(result.stdout, contains('file\tvisible.dart'));
        expect(result.stdout, isNot(contains('ignored.log')));
        expect(result.metadata['ls_defaulted_to_working_directory'], true);
        expect(result.metadata['ls_ignored_count'], 1);
      },
    );

    test(
      'resolves relative directory paths from the working directory',
      () async {
        Directory.current = tempDir.path;
        final srcDir = Directory('${tempDir.path}/src')..createSync();
        File('${srcDir.path}/main.dart').writeAsStringSync('void main() {}\n');

        final result = await AiLsTool().execute(
          _context(<String, Object?>{'path': 'src'}),
        );

        expect(result.status, BashToolExecutionStatus.success);
        expect(result.stdout, contains('file\tmain.dart'));
        expect('${result.metadata['ls_path']}', endsWith('/src'));
        expect(result.metadata['ls_defaulted_to_working_directory'], false);
      },
    );

    test('rejects file paths as directories', () async {
      final file = File('${tempDir.path}/single.dart')
        ..writeAsStringSync('void main() {}\n');

      final result = await AiLsTool().execute(
        _context(<String, Object?>{'path': file.path}),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('not a directory'));
    });
  });
}

AiToolExecutionContext _context(Map<String, Object?> arguments) {
  return AiToolExecutionContext(
    sessionId: 'ls-test',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'ls-call',
      name: 'LS',
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: _testModel,
    previouslyReadFiles: const <String>{},
    denyCommandRules: const <AiDenyCommandRule>[],
    requireWriteCommandConfirmation: true,
    confirmWriteCommand: null,
  );
}

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);
