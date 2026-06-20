import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/web/ai_web_search_tool.dart';

void main() {
  group('AiWebSearchTool', () {
    test('blocks target-origin WebSearch URL query for Web Reverse', () async {
      final tool = AiWebSearchTool(
        backgroundChatClient: _ThrowingChatClient(),
        httpClient: _FailingHttpClient(),
      );

      final result = await tool.execute(
        _context(
          arguments: const <String, Object?>{
            'query': 'site:https://linux.do/t/topic/2401043 api json',
          },
          metadata: _liveWebReverseRuntimeMetadata(),
        ),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(
        result.metadata['web_reverse_websearch_blocked_for_cdp_first'],
        true,
      );
      expect(result.stderr, contains('live CDP is available'));
    });

    test(
      'blocks target-origin WebSearch allowed domain from current metadata',
      () async {
        final tool = AiWebSearchTool(
          backgroundChatClient: _ThrowingChatClient(),
          httpClient: _FailingHttpClient(),
        );

        final result = await tool.execute(
          _context(
            arguments: const <String, Object?>{
              'query': 'topic 2401043 json api',
              'allowed_domains': <String>['linux.do'],
            },
            metadata: const <String, Object?>{
              'web_reverse_config': <String, Object?>{
                'target_url': 'https://linux.do/t/topic/2401043/5',
              },
              'web_reverse_cdp_runtime': <String, Object?>{
                'browser_alive': false,
                'last_cdp_port': 9223,
              },
            },
          ),
        );

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(
          result.metadata['web_reverse_websearch_blocked_for_cdp_first'],
          true,
        );
        expect(
          result.metadata['web_reverse_cdp_route'],
          'runtime_unavailable_without_live_cdp',
        );
      },
    );

    test(
      'blocks same target host WebSearch over alternate HTTP scheme',
      () async {
        final tool = AiWebSearchTool(
          backgroundChatClient: _ThrowingChatClient(),
          httpClient: _FailingHttpClient(),
        );

        final result = await tool.execute(
          _context(
            arguments: const <String, Object?>{
              'query': 'site:http://linux.do/t/topic/2401043 api json',
            },
            metadata: _liveWebReverseRuntimeMetadata(),
          ),
        );

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(
          result.metadata['web_reverse_websearch_blocked_for_cdp_first'],
          true,
        );
        expect(
          result.metadata['web_reverse_requested_origin'],
          'http://linux.do',
        );
      },
    );
  });
}

AiToolExecutionContext _context({
  required Map<String, Object?> arguments,
  Map<String, Object?> metadata = const <String, Object?>{},
}) {
  return AiToolExecutionContext(
    sessionId: 'session-web-reverse',
    catalog: _catalog(),
    toolCall: AiToolCall(
      id: 'call-websearch',
      name: 'WebSearch',
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: _model,
    previouslyReadFiles: const <String>{},
    denyCommandRules: const [],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: null,
    metadata: metadata,
  );
}

AiResolvedToolCatalog _catalog() {
  const definition = AiToolDefinition(
    name: 'WebSearch',
    description: 'Search the web and summarize results.',
    parameters: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'query': <String, Object?>{'type': 'string'},
        'allowed_domains': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
      },
      'required': <String>['query'],
    },
  );
  return const AiResolvedToolCatalog(
    definitions: <AiToolDefinition>[definition],
    toolsByName: <String, AiResolvedTool>{
      'WebSearch': AiResolvedTool(
        name: 'WebSearch',
        definition: definition,
        source: AiRuntimeToolSource.builtin,
        builtinKind: AiBuiltinToolKind.webSearch,
      ),
    },
  );
}

Map<String, Object?> _liveWebReverseRuntimeMetadata() {
  return <String, Object?>{
    'web_reverse_runtime': <String, Object?>{
      'cdp_first_required': true,
      'config': <String, Object?>{
        'target_url': 'https://linux.do/t/topic/2401043/5',
      },
      'cdp_runtime': <String, Object?>{'browser_alive': true, 'cdp_port': 9223},
      'cdp_mcp_tool_availability': <String, Object?>{
        'browser_runtime_live': true,
        'current_turn_callable': true,
        'current_turn_callable_names': <String>[
          'mcp__web_reverse_cdp__evaluate_script',
        ],
      },
    },
  };
}

const _model = AiModelConfig(
  id: 'test',
  baseUrl: 'https://example.invalid',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);

class _FailingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError('WebSearch guard did not block before HTTP dispatch.');
  }
}

class _ThrowingChatClient implements AiChatClient {
  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(minutes: 2),
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw StateError('WebSearch guard did not block before background chat.');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(minutes: 2),
    Duration streamIdleTimeout = const Duration(seconds: 30),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw StateError('WebSearch guard did not block before streaming chat.');
  }

  @override
  Future<String> testModel(AiModelConfig model) async => 'ok';

  @override
  void dispose() {}
}
