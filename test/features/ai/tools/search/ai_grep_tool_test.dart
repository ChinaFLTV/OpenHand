import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/search/ai_grep_tool.dart';

void main() {
  group('AiGrepTool', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('openhand-grep-test-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('accepts Claude-style context alias for -C', () async {
      final file = File('${tempDir.path}/context.txt')
        ..writeAsStringSync('before\nneedle\nafter\n');

      final result = await AiGrepTool().execute(
        _context(<String, Object?>{
          'pattern': 'needle',
          'path': file.path,
          'output_mode': 'content',
          'context': 1,
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('before'));
      expect(result.stdout, contains('needle'));
      expect(result.stdout, contains('after'));
    });

    test('applies offset before head_limit', () async {
      final file = File('${tempDir.path}/matches.txt')
        ..writeAsStringSync('match one\nmatch two\nmatch three\n');

      final result = await AiGrepTool().execute(
        _context(<String, Object?>{
          'pattern': 'match',
          'path': file.path,
          'output_mode': 'content',
          'offset': 1,
          'head_limit': 1,
        }),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, contains('match two'));
      expect(result.stdout, isNot(contains('match one')));
      expect(result.stdout, isNot(contains('match three')));
    });
  });
}

AiToolExecutionContext _context(Map<String, Object?> arguments) {
  return AiToolExecutionContext(
    sessionId: 'grep-test',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'grep-call',
      name: 'Grep',
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
