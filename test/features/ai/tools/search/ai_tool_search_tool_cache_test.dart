import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/search/ai_tool_search_tool.dart';

void main() {
  test(
    'ToolSearch output is stable across deferred schema map order',
    () async {
      final alpha = _tool(
        'AlphaTool',
        properties: <String, Object?>{
          'zeta': const <String, Object?>{'type': 'string'},
          'alpha': const <String, Object?>{'type': 'string'},
        },
        required: const <String>['zeta', 'alpha'],
      );
      final beta = _tool(
        'BetaTool',
        properties: <String, Object?>{
          'beta': const <String, Object?>{'type': 'string'},
        },
        required: const <String>['beta'],
      );

      final first = await _executeToolSearch(
        query: 'select:BetaTool,AlphaTool',
        deferredDefinitions: <String, AiToolDefinition>{
          beta.name: beta,
          alpha.name: alpha,
        },
      );
      final second = await _executeToolSearch(
        query: 'select:AlphaTool,BetaTool',
        deferredDefinitions: <String, AiToolDefinition>{
          alpha.name: alpha,
          beta.name: beta,
        },
      );

      expect(first.resultText, second.resultText);
      expect(first.metadata['tool_search_loaded_names'], <String>[
        'AlphaTool',
        'BetaTool',
      ]);
      expect(first.resultText, contains('loaded: AlphaTool, BetaTool'));
      expect(first.resultText, contains('"required":["alpha","zeta"]'));
      expect(
        first.resultText.indexOf('"alpha"'),
        lessThan(first.resultText.indexOf('"zeta"')),
      );
    },
  );

  test('ToolSearch ranking ties are stable across catalog order', () async {
    final alpha = _tool('Read-File', description: 'read file');
    final beta = _tool('Read_File', description: 'read file');

    final first = await _executeToolSearch(
      query: 'read file',
      deferredDefinitions: <String, AiToolDefinition>{
        beta.name: beta,
        alpha.name: alpha,
      },
    );
    final second = await _executeToolSearch(
      query: 'read file',
      deferredDefinitions: <String, AiToolDefinition>{
        alpha.name: alpha,
        beta.name: beta,
      },
    );

    expect(first.resultText, second.resultText);
    expect(first.metadata['tool_search_loaded_names'], <String>[
      'Read-File',
      'Read_File',
    ]);
  });

  test('ToolSearch deferred snapshot stores names in stable order', () {
    final alpha = _tool('AlphaTool');
    final beta = _tool('BetaTool');
    final tool = AiToolSearchTool();

    tool.setDeferredToolSnapshot(<String, AiToolDefinition>{
      beta.name: beta,
      alpha.name: alpha,
    });

    expect(tool.deferredToolNames, <String>['AlphaTool', 'BetaTool']);
    expect(tool.deferredToolDefinitions.keys.toList(), <String>[
      'AlphaTool',
      'BetaTool',
    ]);
  });
}

Future<AiToolExecutionResult> _executeToolSearch({
  required String query,
  required Map<String, AiToolDefinition> deferredDefinitions,
}) {
  final tool = AiToolSearchTool();
  final catalog = AiResolvedToolCatalog(
    definitions: const <AiToolDefinition>[],
    toolsByName: <String, AiResolvedTool>{
      'ToolSearch': AiResolvedTool(
        name: 'ToolSearch',
        definition: const AiToolDefinition(
          name: 'ToolSearch',
          description: 'Search deferred tools.',
          parameters: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
          },
        ),
        source: AiRuntimeToolSource.builtin,
        builtinKind: AiBuiltinToolKind.toolSearch,
        toolSearchDeferredToolDefinitions: deferredDefinitions,
      ),
    },
  );
  return tool.execute(
    AiToolExecutionContext(
      sessionId: 'session-1',
      catalog: catalog,
      toolCall: const AiToolCall(
        id: 'call-1',
        name: 'ToolSearch',
        arguments: '{}',
      ),
      decodedArguments: <String, Object?>{'query': query, 'max_results': 10},
      model: _model(),
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: (BashCommandApprovalRequest request) async =>
          BashCommandApprovalDecision.approved,
    ),
  );
}

AiToolDefinition _tool(
  String name, {
  String description = 'Tool schema order probe.',
  Map<String, Object?> properties = const <String, Object?>{},
  List<String> required = const <String>[],
}) {
  return AiToolDefinition(
    name: name,
    description: description,
    parameters: <String, Object?>{
      'type': 'object',
      'required': required,
      'properties': properties,
    },
  );
}

AiModelConfig _model() {
  return const AiModelConfig(
    id: 'model-1',
    baseUrl: 'https://example.invalid',
    authScheme: AiAuthScheme.bearer,
    token: 'test-token',
    modelId: 'test-model',
    protocolType: AiProtocolType.openai,
    maxTokens: 1024,
  );
}
