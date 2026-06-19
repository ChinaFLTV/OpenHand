import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/search/ai_codebase_search_tool.dart';

void main() {
  group('AiCodebaseSearchTool', () {
    test('uses public path field as the search root', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_codebase_search_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final scopedDir = Directory('${tempDir.path}/scoped');
      await scopedDir.create();
      final scopedFile = File('${scopedDir.path}/NeedleScope.dart');
      await scopedFile.writeAsString('class NeedleScope {}\n');

      final result = await AiCodebaseSearchTool().execute(
        _context(<String, Object?>{
          'query': 'NeedleScope',
          'path': scopedDir.path,
        }),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains(scopedFile.path));
    });

    test('uses public file_pattern field to filter results', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'openhand_codebase_search_filter_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final dartFile = File('${tempDir.path}/NeedlePattern.dart');
      final markdownFile = File('${tempDir.path}/NeedlePattern.md');
      await dartFile.writeAsString('class NeedlePattern {}\n');
      await markdownFile.writeAsString('# NeedlePattern\n');

      final result = await AiCodebaseSearchTool().execute(
        _context(<String, Object?>{
          'query': 'NeedlePattern',
          'path': tempDir.path,
          'file_pattern': '*.dart',
        }),
      );

      expect(result.status.storageValue, 'success');
      expect(result.stdout, contains(dartFile.path));
      expect(result.stdout, isNot(contains(markdownFile.path)));
    });
  });
}

AiToolExecutionContext _context(Map<String, Object?> arguments) {
  return AiToolExecutionContext(
    sessionId: 'test-session',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'codebase-search',
      name: 'CodebaseSearch',
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: _testModel,
    previouslyReadFiles: <String>{},
    denyCommandRules: const <Never>[],
    requireWriteCommandConfirmation: false,
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
