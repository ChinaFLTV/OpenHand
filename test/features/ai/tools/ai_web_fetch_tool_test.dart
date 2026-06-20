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
import 'package:openhand/features/ai/service/web_fetch/web_fetch_scrapling_bridge.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/web/ai_web_fetch_tool.dart';

void main() {
  group('AiWebFetchTool', () {
    test(
      'blocks target-origin WebFetch when Web Reverse CDP is live',
      () async {
        final tool = AiWebFetchTool(
          backgroundChatClient: _ThrowingChatClient(),
          httpClient: _FailingHttpClient(),
          scraplingBridge: WebFetchScraplingBridge(),
        );

        final result = await tool.execute(
          AiToolExecutionContext(
            sessionId: 'session-web-reverse',
            catalog: _catalog(),
            toolCall: AiToolCall(
              id: 'call-webfetch',
              name: 'WebFetch',
              arguments: jsonEncode(<String, Object?>{
                'url': 'https://linux.do/t/topic/2401043.json',
                'prompt': 'Summarize the JSON.',
              }),
            ),
            decodedArguments: const <String, Object?>{
              'url': 'https://linux.do/t/topic/2401043.json',
              'prompt': 'Summarize the JSON.',
            },
            model: _model,
            previouslyReadFiles: const <String>{},
            denyCommandRules: const [],
            requireWriteCommandConfirmation: false,
            confirmWriteCommand: null,
            metadata: _liveWebReverseRuntimeMetadata(),
          ),
        );

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(
          result.metadata['web_reverse_webfetch_blocked_for_cdp_first'],
          isTrue,
        );
        expect(result.stderr, contains('live CDP is available'));
      },
    );

    test(
      'blocks target-origin WebFetch from current session metadata',
      () async {
        final tool = AiWebFetchTool(
          backgroundChatClient: _ThrowingChatClient(),
          httpClient: _FailingHttpClient(),
          scraplingBridge: WebFetchScraplingBridge(),
        );

        final result = await tool.execute(
          AiToolExecutionContext(
            sessionId: 'session-web-reverse',
            catalog: _catalog(),
            toolCall: AiToolCall(
              id: 'call-webfetch',
              name: 'WebFetch',
              arguments: jsonEncode(<String, Object?>{
                'url': 'https://linux.do/t/topic/2401043.json',
                'prompt': 'Summarize the JSON.',
              }),
            ),
            decodedArguments: const <String, Object?>{
              'url': 'https://linux.do/t/topic/2401043.json',
              'prompt': 'Summarize the JSON.',
            },
            model: _model,
            previouslyReadFiles: const <String>{},
            denyCommandRules: const [],
            requireWriteCommandConfirmation: false,
            confirmWriteCommand: null,
            metadata: const <String, Object?>{
              'web_reverse_config': <String, Object?>{
                'target_url': 'https://linux.do/t/topic/2401043/5',
              },
              'web_reverse_cdp_runtime': <String, Object?>{
                'browser_alive': true,
                'cdp_port': 9223,
              },
            },
          ),
        );

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(
          result.metadata['web_reverse_webfetch_blocked_for_cdp_first'],
          isTrue,
        );
        expect(
          result.metadata['web_reverse_cdp_route'],
          'runtime_live_without_callable_cdp_tools',
        );
      },
    );

    test(
      'blocks same target host WebFetch over alternate HTTP scheme',
      () async {
        final tool = AiWebFetchTool(
          backgroundChatClient: _ThrowingChatClient(),
          httpClient: _FailingHttpClient(),
          scraplingBridge: WebFetchScraplingBridge(),
        );

        final result = await tool.execute(
          AiToolExecutionContext(
            sessionId: 'session-web-reverse',
            catalog: _catalog(),
            toolCall: AiToolCall(
              id: 'call-webfetch-http',
              name: 'WebFetch',
              arguments: jsonEncode(<String, Object?>{
                'url': 'http://linux.do/t/topic/2401043.json',
                'prompt': 'Summarize the JSON.',
              }),
            ),
            decodedArguments: const <String, Object?>{
              'url': 'http://linux.do/t/topic/2401043.json',
              'prompt': 'Summarize the JSON.',
            },
            model: _model,
            previouslyReadFiles: const <String>{},
            denyCommandRules: const [],
            requireWriteCommandConfirmation: false,
            confirmWriteCommand: null,
            metadata: _liveWebReverseRuntimeMetadata(),
          ),
        );

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(
          result.metadata['web_reverse_webfetch_blocked_for_cdp_first'],
          isTrue,
        );
        expect(
          result.metadata['web_reverse_requested_origin'],
          'http://linux.do',
        );
      },
    );

    test('blocks target site subdomain WebFetch for Web Reverse', () async {
      final tool = AiWebFetchTool(
        backgroundChatClient: _ThrowingChatClient(),
        httpClient: _FailingHttpClient(),
        scraplingBridge: WebFetchScraplingBridge(),
      );

      final result = await tool.execute(
        AiToolExecutionContext(
          sessionId: 'session-web-reverse',
          catalog: _catalog(),
          toolCall: AiToolCall(
            id: 'call-webfetch-subdomain',
            name: 'WebFetch',
            arguments: jsonEncode(<String, Object?>{
              'url': 'https://api.linux.do/t/topic/2401043.json',
              'prompt': 'Summarize the JSON.',
            }),
          ),
          decodedArguments: const <String, Object?>{
            'url': 'https://api.linux.do/t/topic/2401043.json',
            'prompt': 'Summarize the JSON.',
          },
          model: _model,
          previouslyReadFiles: const <String>{},
          denyCommandRules: const [],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: null,
          metadata: _liveWebReverseRuntimeMetadata(),
        ),
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(
        result.metadata['web_reverse_webfetch_blocked_for_cdp_first'],
        isTrue,
      );
      expect(
        result.metadata['web_reverse_requested_origin'],
        'https://api.linux.do',
      );
    });
  });
}

AiResolvedToolCatalog _catalog() {
  const definition = AiToolDefinition(
    name: 'WebFetch',
    description: 'Fetch and summarize a URL.',
    parameters: <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'url': <String, Object?>{'type': 'string'},
        'prompt': <String, Object?>{'type': 'string'},
      },
      'required': <String>['url', 'prompt'],
    },
  );
  return const AiResolvedToolCatalog(
    definitions: <AiToolDefinition>[definition],
    toolsByName: <String, AiResolvedTool>{
      'WebFetch': AiResolvedTool(
        name: 'WebFetch',
        definition: definition,
        source: AiRuntimeToolSource.builtin,
        builtinKind: AiBuiltinToolKind.webFetch,
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
    throw StateError('WebFetch guard did not block before HTTP dispatch.');
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
    throw StateError('WebFetch guard did not block before background chat.');
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
    throw StateError('WebFetch guard did not block before streaming chat.');
  }

  @override
  Future<String> testModel(AiModelConfig model) async => 'ok';

  @override
  void dispose() {}
}
