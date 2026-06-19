import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/mcp/index.dart';

void main() {
  group('AiToolRuntimeService retry policy', () {
    test(
      'does not retry side-effect builtin Bash even when retry is enabled',
      () async {
        final marker = File(
          '/tmp/openhand-retry-suppression-${DateTime.now().microsecondsSinceEpoch}.txt',
        );
        if (marker.existsSync()) {
          marker.deleteSync();
        }
        addTearDown(() {
          if (marker.existsSync()) marker.deleteSync();
        });

        final runtime = AiToolRuntimeService(
          bashToolService: AiBashToolService(),
          hookService: AiNoopClaudeHookService(),
          mcpToolService: _FakeMcpToolDiscoveryService(),
          backgroundChatClient: _FakeChatClient(),
        );
        const retryConfig = AiBuiltinToolConfig(
          kind: AiBuiltinToolKind.bash,
          retryOnFailure: true,
          maxRetries: 3,
          retryBackoffMs: 0,
        );
        const definition = AiToolDefinition(
          name: 'Bash',
          description: 'Run bash',
          parameters: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'cmd': <String, Object?>{'type': 'string'},
              'working_directory': <String, Object?>{'type': 'string'},
            },
            'required': <String>['cmd'],
            'additionalProperties': false,
          },
        );
        const catalog = AiResolvedToolCatalog(
          definitions: <AiToolDefinition>[definition],
          toolsByName: <String, AiResolvedTool>{
            'Bash': AiResolvedTool(
              name: 'Bash',
              definition: definition,
              source: AiRuntimeToolSource.builtin,
              builtinKind: AiBuiltinToolKind.bash,
              builtinConfig: retryConfig,
            ),
          },
        );
        final result = await runtime.execute(
          sessionId: 'runtime-retry-test',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-1',
            name: 'Bash',
            arguments: jsonEncode(<String, Object?>{
              'cmd':
                  "printf x >> '${marker.path.replaceAll("'", "'\\''")}'; false",
              'working_directory': '/tmp',
            }),
          ),
          model: _testModel,
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: null,
        );

        expect(result.status, BashToolExecutionStatus.failed);
        expect(result.exitCode, 1);
        expect(result.metadata['retry_suppressed'], isTrue);
        expect(
          result.metadata['retry_suppressed_reason'],
          'builtin_tool_may_have_side_effects',
        );
        expect(marker.readAsStringSync(), 'x');
      },
    );
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

class _FakeChatClient implements AiChatClient {
  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 60),
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) async {
    return const AiChatCompletion(reply: '');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 60),
    Duration streamIdleTimeout = const Duration(seconds: 60),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> testModel(AiModelConfig model) async => 'OK';

  @override
  void dispose() {}
}

class _FakeMcpToolDiscoveryService implements McpToolDiscoveryService {
  @override
  Future<McpServerHealth> checkHealth(McpServer server) {
    throw UnimplementedError();
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
    Map<String, String>? customHeaders,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
