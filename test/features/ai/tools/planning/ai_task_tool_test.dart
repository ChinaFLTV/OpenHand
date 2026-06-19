import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/ai/tools/ai_tool_execution_context.dart';
import 'package:openhand/features/ai/tools/planning/ai_task_tool.dart';

void main() {
  group('AiTaskTool', () {
    test(
      'blocks command-capable subagent types while plan execution is unapproved',
      () async {
        final chatClient = _FakeChatClient(
          completion: const AiChatCompletion(reply: 'should not run'),
        );
        final tool = AiTaskTool(
          backgroundChatClient: chatClient,
          hookService: AiNoopClaudeHookService(),
        );

        final result = await tool.execute(
          _context(
            subagentType: 'verify',
            metadata: const <String, Object?>{
              'plan_mode_active': true,
              'plan_mode_execution_approved_for_send': false,
            },
          ),
        );

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(result.stderr, contains('Plan mode before execution approval'));
        expect(chatClient.sendMessageCalls, 0);
      },
    );

    test('allows read-only subagent types while planning', () async {
      final chatClient = _FakeChatClient(
        completion: const AiChatCompletion(reply: 'research done'),
      );
      final tool = AiTaskTool(
        backgroundChatClient: chatClient,
        hookService: AiNoopClaudeHookService(),
      );

      final result = await tool.execute(
        _context(
          subagentType: 'research',
          metadata: const <String, Object?>{
            'plan_mode_active': true,
            'plan_mode_execution_approved_for_send': false,
          },
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, 'research done');
      expect(chatClient.sendMessageCalls, 1);
    });

    test('allows verify subagents after plan execution approval', () async {
      final chatClient = _FakeChatClient(
        completion: const AiChatCompletion(reply: 'verify done'),
      );
      final tool = AiTaskTool(
        backgroundChatClient: chatClient,
        hookService: AiNoopClaudeHookService(),
      );

      final result = await tool.execute(
        _context(
          subagentType: 'verify',
          metadata: const <String, Object?>{
            'plan_mode_active': true,
            'plan_mode_execution_approved_for_send': true,
          },
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(result.stdout, 'verify done');
      expect(chatClient.sendMessageCalls, 1);
    });
  });
}

AiToolExecutionContext _context({
  required String subagentType,
  required Map<String, Object?> metadata,
}) {
  final arguments = <String, Object?>{
    'description': 'Inspect task behavior',
    'prompt': 'Inspect behavior and return a concise result.',
    'subagent_type': subagentType,
  };
  return AiToolExecutionContext(
    sessionId: 'session-1',
    catalog: const AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[],
      toolsByName: <String, AiResolvedTool>{},
    ),
    toolCall: AiToolCall(
      id: 'tool-call-1',
      name: 'Task',
      arguments: jsonEncode(arguments),
    ),
    decodedArguments: arguments,
    model: _testModel,
    previouslyReadFiles: const <String>{},
    denyCommandRules: const <AiDenyCommandRule>[],
    requireWriteCommandConfirmation: true,
    confirmWriteCommand: null,
    metadata: metadata,
  );
}

class _FakeChatClient implements AiChatClient {
  _FakeChatClient({required this.completion});

  final AiChatCompletion completion;
  int sendMessageCalls = 0;

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
    sendMessageCalls += 1;
    return completion;
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

const AiModelConfig _testModel = AiModelConfig(
  id: 'test',
  baseUrl: 'http://localhost',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'test-model',
  protocolType: AiProtocolType.openai,
);
