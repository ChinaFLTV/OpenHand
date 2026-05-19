import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
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
  test('Task subagent does not receive ToolSearch', () async {
    final chatClient = _RecordingChatClient();
    final taskTool = AiTaskTool(
      backgroundChatClient: chatClient,
      hookService: AiNoopClaudeHookService(),
    );
    final result = await taskTool.execute(
      AiToolExecutionContext(
        sessionId: 'session-1',
        catalog: _catalog(),
        toolCall: AiToolCall(
          id: 'task-1',
          name: 'Task',
          arguments: jsonEncode(<String, Object?>{
            'description': 'inspect available tools',
            'prompt': 'Report what tools you can use.',
            'subagent_type': 'research',
          }),
        ),
        decodedArguments: <String, Object?>{
          'description': 'inspect available tools',
          'prompt': 'Report what tools you can use.',
          'subagent_type': 'research',
        },
        model: _model,
        previouslyReadFiles: <String>{},
        denyCommandRules: const <Never>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
      ),
    );

    expect(result.status, BashToolExecutionStatus.success);
    expect(chatClient.lastTools.map((tool) => tool.name), contains('Read'));
    expect(
      chatClient.lastTools.map((tool) => tool.name),
      isNot(contains('ToolSearch')),
    );
  });
}

const _model = AiModelConfig(
  id: 'test-model',
  baseUrl: 'http://localhost/v1',
  authScheme: AiAuthScheme.none,
  token: '',
  modelId: 'openhand-test-model',
  protocolType: AiProtocolType.openai,
);

AiResolvedToolCatalog _catalog() {
  final task = _definition('Task');
  final toolSearch = _definition('ToolSearch');
  final read = _definition('Read');
  return AiResolvedToolCatalog(
    definitions: <AiToolDefinition>[task, toolSearch, read],
    toolsByName: <String, AiResolvedTool>{
      'Task': AiResolvedTool(
        name: 'Task',
        definition: task,
        source: AiRuntimeToolSource.builtin,
        builtinKind: AiBuiltinToolKind.task,
      ),
      'ToolSearch': AiResolvedTool(
        name: 'ToolSearch',
        definition: toolSearch,
        source: AiRuntimeToolSource.builtin,
        builtinKind: AiBuiltinToolKind.toolSearch,
      ),
      'Read': AiResolvedTool(
        name: 'Read',
        definition: read,
        source: AiRuntimeToolSource.builtin,
        builtinKind: AiBuiltinToolKind.read,
      ),
    },
  );
}

AiToolDefinition _definition(String name) {
  return AiToolDefinition(
    name: name,
    description: 'Description for $name',
    parameters: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  );
}

class _RecordingChatClient implements AiChatClient {
  List<AiToolDefinition> lastTools = const <AiToolDefinition>[];

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
  }) async {
    lastTools = tools;
    return const AiChatCompletion(reply: 'done');
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(minutes: 2),
    Duration streamIdleTimeout = const Duration(seconds: 45),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> testModel(AiModelConfig model) async => 'ok';

  @override
  void dispose() {}
}
