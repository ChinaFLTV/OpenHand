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
        expect(result.metadata['task_blocked_plan_mode_subagent'], isTrue);
        expect(
          result.metadata['task_block_reason'],
          'plan_mode_execution_unapproved',
        );
        expect(result.metadata['subagent_type'], 'verify');
        expect(
          result.metadata['allowed_subagent_types_before_approval'],
          unorderedEquals(<String>['research', 'summarize', 'advice']),
        );
        expect(result.metadata['plan_mode_active'], isTrue);
        expect(
          result.metadata['plan_mode_execution_approved_for_send'],
          isFalse,
        );
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

    test('research subagents receive only read-only builtin tools', () async {
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
          metadata: const <String, Object?>{},
          catalog: _mixedCatalog(),
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(
        chatClient.lastToolNames,
        unorderedEquals(<String>['Read', 'Git']),
      );
    });

    test('verify subagents receive Bash but not parent-thread tools', () async {
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
          catalog: _mixedCatalog(),
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      expect(
        chatClient.lastToolNames,
        unorderedEquals(<String>['Read', 'Git', 'Bash']),
      );
    });
  });
}

AiToolExecutionContext _context({
  required String subagentType,
  required Map<String, Object?> metadata,
  AiResolvedToolCatalog catalog = const AiResolvedToolCatalog(
    definitions: <AiToolDefinition>[],
    toolsByName: <String, AiResolvedTool>{},
  ),
}) {
  final arguments = <String, Object?>{
    'description': 'Inspect task behavior',
    'prompt': 'Inspect behavior and return a concise result.',
    'subagent_type': subagentType,
  };
  return AiToolExecutionContext(
    sessionId: 'session-1',
    catalog: catalog,
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

AiResolvedToolCatalog _mixedCatalog() {
  final tools = <AiResolvedTool>[
    _builtinTool('Read', AiBuiltinToolKind.read),
    _builtinTool('Git', AiBuiltinToolKind.git),
    _builtinTool('Bash', AiBuiltinToolKind.bash),
    _builtinTool('TodoWrite', AiBuiltinToolKind.todoWrite),
    _builtinTool('ExitPlanMode', AiBuiltinToolKind.exitPlanMode),
    _builtinTool('AskUserChoice', AiBuiltinToolKind.askUserChoice),
    _builtinTool('Memory', AiBuiltinToolKind.memory),
    _builtinTool('ToolSearch', AiBuiltinToolKind.toolSearch),
    _runtimeTool('mcp__repo_lookup', AiRuntimeToolSource.mcp),
    _runtimeTool('skill__flutter', AiRuntimeToolSource.skill),
  ];
  return AiResolvedToolCatalog(
    definitions: tools.map((tool) => tool.definition).toList(growable: false),
    toolsByName: <String, AiResolvedTool>{
      for (final tool in tools) tool.name: tool,
    },
  );
}

AiResolvedTool _builtinTool(String name, AiBuiltinToolKind kind) {
  return AiResolvedTool(
    name: name,
    definition: _toolDefinition(name),
    source: AiRuntimeToolSource.builtin,
    builtinKind: kind,
  );
}

AiResolvedTool _runtimeTool(String name, AiRuntimeToolSource source) {
  return AiResolvedTool(
    name: name,
    definition: _toolDefinition(name),
    source: source,
  );
}

AiToolDefinition _toolDefinition(String name) {
  return AiToolDefinition(
    name: name,
    description: 'Test tool $name',
    parameters: const <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
    },
  );
}

class _FakeChatClient implements AiChatClient {
  _FakeChatClient({required this.completion});

  final AiChatCompletion completion;
  int sendMessageCalls = 0;
  List<AiToolDefinition> lastTools = const <AiToolDefinition>[];

  List<String> get lastToolNames {
    return lastTools.map((tool) => tool.name).toList(growable: false);
  }

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
    lastTools = List<AiToolDefinition>.from(tools);
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
