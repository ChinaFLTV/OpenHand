import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/lsp/ai_lsp_tool.dart';

void main() {
  group('AiLspTool', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('openhand-lsp-test-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('accepts Claude-style filePath argument', () async {
      final file = File('${tempDir.path}/sample.no_lsp_backend')
        ..writeAsStringSync('symbol\n');

      final result = await AiLspTool().execute(
        _context(<String, Object?>{
          'operation': 'hover',
          'filePath': file.path,
          'line': 1,
          'character': 1,
        }),
      );

      expect(result.status, BashToolExecutionStatus.failed);
      expect(result.command, 'LSP hover');
      expect(result.stderr, isNot(contains('filePath (or file_path)')));
    });

    test('keeps OpenHand file_path argument compatible', () async {
      final file = File('${tempDir.path}/sample.no_lsp_backend')
        ..writeAsStringSync('symbol\n');

      final result = await AiLspTool().execute(
        _context(<String, Object?>{
          'operation': 'hover',
          'file_path': file.path,
          'line': 1,
          'character': 1,
        }),
      );

      expect(result.status, BashToolExecutionStatus.failed);
      expect(result.command, 'LSP hover');
      expect(result.stderr, isNot(contains('filePath (or file_path)')));
    });

    test('reports both accepted file path fields when missing', () async {
      final result = await AiLspTool().execute(
        _context(<String, Object?>{
          'operation': 'hover',
          'line': 1,
          'character': 1,
        }),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.stderr, contains('filePath (or file_path)'));
    });
  });
}

AiToolExecutionContext _context(Map<String, Object?> arguments) {
  return AiToolExecutionContext(
    sessionId: 'lsp-test',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'lsp-call',
      name: 'LSP',
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
