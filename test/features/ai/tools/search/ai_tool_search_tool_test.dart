import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/search/ai_tool_search_tool.dart';

void main() {
  group('AiToolSearchTool', () {
    test(
      'direct select is case-insensitive, deduplicated, and bounded',
      () async {
        final tool = AiToolSearchTool()
          ..setDeferredToolSnapshot(<String, AiToolDefinition>{
            'Read': _definition('Read', 'Read a file.'),
            'Edit': _definition('Edit', 'Edit a file.'),
            'MultiEdit': _definition('MultiEdit', 'Apply multiple edits.'),
          });

        final result = await tool.execute(
          _context(query: 'select:read,Edit,Read,MultiEdit', maxResults: 2),
        );

        expect(result.status, BashToolExecutionStatus.success);
        expect(result.metadata['tool_search_loaded_names'], <String>[
          'Read',
          'Edit',
        ]);
        expect(result.stdout, contains('loaded: Read, Edit'));
        expect(result.stdout, contains('next model request onward'));
        expect(result.stdout, isNot(contains('"name":"MultiEdit"')));
      },
    );

    test('keyword search keeps deferred tools hidden on no match', () async {
      final tool = AiToolSearchTool()
        ..setDeferredToolSnapshot(<String, AiToolDefinition>{
          'NotebookEdit': _definition('NotebookEdit', 'Edit notebook cells.'),
        });

      final result = await tool.execute(_context(query: 'slack send'));

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.metadata['tool_search_loaded_names'], isEmpty);
      expect(result.stdout, contains('matched 0'));
      expect(result.stdout, contains('select:NAME'));
    });
  });
}

AiToolDefinition _definition(String name, String description) {
  return AiToolDefinition(
    name: name,
    description: description,
    parameters: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
      'additionalProperties': false,
    },
  );
}

AiToolExecutionContext _context({required String query, int? maxResults}) {
  final arguments = <String, Object?>{
    'query': query,
    if (maxResults != null) 'max_results': maxResults,
  };
  return AiToolExecutionContext(
    sessionId: 'session-1',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'tool-call-1',
      name: 'ToolSearch',
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
