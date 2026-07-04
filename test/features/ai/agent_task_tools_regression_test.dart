import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/data/agents_store.dart';
import 'package:openhand/features/agents/index.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/ai/tools/agents/ai_agent_tools.dart';
import 'package:openhand/features/instructions/model/user_instruction_entry.dart';

void main() {
  test('AgentTaskPublish runs worker and writes back result', () async {
    final harness = await _AgentToolHarness.create(
      chatReply: '公开信息摘要：暂无权威公开恋情确认。',
    );
    addTearDown(harness.dispose);

    final tool = harness.tool(AiBuiltinToolKind.agentTaskPublish);
    final result = await tool.execute(
      harness.context(
        toolName: 'AgentTaskPublish',
        arguments: const <String, Object?>{
          'agent_id': 'agent-1',
          'title': '查询公开信息',
          'content': '查询公开信息并输出结论。',
        },
      ),
    );

    expect(result.status, BashToolExecutionStatus.success);
    final payload = jsonDecode(result.stdout) as Map<String, Object?>;
    final task = payload['task'] as Map<String, Object?>;
    final worker = payload['worker_execution'] as Map<String, Object?>;
    expect(worker['status'], 'completed');
    expect(task['status'], AgentTaskStatus.completed.storageValue);
    expect(task['result'], contains('暂无权威公开恋情确认'));
    expect(
      harness.controller.agentById('agent-1')!.tasks.single.result,
      contains('暂无权威公开恋情确认'),
    );
    final resource = harness.controller.agentById('agent-1')!.resourceUsage;
    expect(resource.tokenUsed, greaterThanOrEqualTo(12));
    expect(resource.persistedBytes, greaterThan(0));
  });

  test('AgentTaskPublish refreshes resource usage snapshot', () async {
    final harness = await _AgentToolHarness.create();
    addTearDown(harness.dispose);

    final task = await harness.controller.publishTaskWithResult(
      'agent-1',
      title: '资源统计任务',
      description: '验证资源面板不会保持空统计。',
      content: '写入任务内容，让 token 和持久化占用都能被估算。',
    );

    expect(task, isNotNull);
    final agent = harness.controller.agentById('agent-1')!;
    expect(agent.tasks.single.status, AgentTaskStatus.running);
    expect(agent.resourceUsage.cpuPercent, greaterThan(0));
    expect(agent.resourceUsage.memoryBytes, greaterThan(0));
    expect(agent.resourceUsage.persistedBytes, greaterThan(0));
    expect(agent.resourceUsage.tokenUsed, greaterThan(0));
    expect(agent.resourceUsage.openHandles, greaterThan(0));
    expect(agent.resourceUsage.publicExtra['task_count'], 1);
    expect(agent.resourceUsage.publicExtra['active_task_count'], 1);
  });

  test('Agent audit tokens are folded into resource usage', () async {
    final harness = await _AgentToolHarness.create();
    addTearDown(harness.dispose);

    final event = await harness.controller.recordAuditEvent(
      'agent-1',
      kind: 'model_request',
      summary: '模型请求完成',
      tokenUsage: 88,
      requestCount: 1,
    );

    expect(event, isNotNull);
    final resource = harness.controller.agentById('agent-1')!.resourceUsage;
    expect(resource.tokenUsed, 88);
    expect(resource.publicExtra['audit_token_usage'], 88);
  });

  test('Agent prompt renderer injects enabled bound instructions', () async {
    final now = DateTime.utc(2026);
    final renderer = AgentPromptRenderer(loader: (_) async => _promptTemplate);

    final snapshot = await renderer.render(
      agent: const AgentProfile(
        id: 'agent-1',
        name: '资料员',
        instructionIds: <String>['instruction-1', 'instruction-disabled'],
      ),
      boundInstructions: <UserInstructionEntry>[
        UserInstructionEntry(
          id: 'instruction-1',
          name: '核查输出',
          description: '输出必须包含核查依据。',
          body: '优先输出核查依据，再给出结论。',
          applyTo: '公开资料核查',
          createdAt: now,
          updatedAt: now,
          sortOrder: 1,
        ),
        UserInstructionEntry(
          id: 'instruction-disabled',
          name: '停用指令',
          body: '这条停用指令不应注入。',
          enabled: false,
          createdAt: now,
          updatedAt: now,
          sortOrder: 2,
        ),
      ],
    );

    expect(snapshot.capabilities['instruction_ids'], <String>[
      'instruction-1',
      'instruction-disabled',
    ]);
    final instructions = snapshot.capabilities['instructions'] as List<Object?>;
    expect(instructions, hasLength(1));
    expect(
      instructions.single as Map<String, Object?>,
      containsPair('body', '优先输出核查依据，再给出结论。'),
    );
    expect(snapshot.renderedPrompt, contains('优先输出核查依据'));
    expect(snapshot.renderedPrompt, isNot(contains('这条停用指令不应注入')));
  });

  test('AgentTaskPublish bounds automatic worker wait time', () async {
    final harness = await _AgentToolHarness.create(
      chatReply: '过晚的结果',
      chatDelay: const Duration(milliseconds: 200),
    );
    addTearDown(harness.dispose);

    final tool = harness.tool(AiBuiltinToolKind.agentTaskPublish);
    final result = await tool.execute(
      harness.context(
        toolName: 'AgentTaskPublish',
        arguments: const <String, Object?>{
          'agent_id': 'agent-1',
          'title': '短等待任务',
          'wait_ms': 20,
        },
      ),
    );

    expect(result.status, BashToolExecutionStatus.success);
    final payload = jsonDecode(result.stdout) as Map<String, Object?>;
    final task = payload['task'] as Map<String, Object?>;
    final worker = payload['worker_execution'] as Map<String, Object?>;
    expect(worker['status'], 'timeout');
    expect(task['status'], AgentTaskStatus.failed.storageValue);
    expect(
      harness.controller.agentById('agent-1')!.tasks.single.note,
      contains('TimeoutException'),
    );
  });

  test(
    'AgentTaskTrack recovers a wrong task id for read-only tracking',
    () async {
      final harness = await _AgentToolHarness.create();
      addTearDown(harness.dispose);
      final task = await harness.controller.publishTaskWithResult(
        'agent-1',
        title: '同会话任务',
        extra: const <String, Object?>{'published_by_session_id': 'session-1'},
      );
      expect(task, isNotNull);

      final tool = harness.tool(AiBuiltinToolKind.agentTaskTrack);
      final result = await tool.execute(
        harness.context(
          toolName: 'AgentTaskTrack',
          arguments: const <String, Object?>{
            'agent_id': 'agent-1',
            'task_id': 'missing-task-id',
          },
        ),
      );

      expect(result.status, BashToolExecutionStatus.success);
      final payload = jsonDecode(result.stdout) as Map<String, Object?>;
      expect(payload['task'], isA<Map<String, Object?>>());
      expect((payload['task'] as Map<String, Object?>)['id'], task!.id);
      final resolution = payload['resolution'] as Map<String, Object?>;
      expect(resolution['recovered'], true);
      expect(resolution['requested_task_id'], 'missing-task-id');
      expect(resolution['resolved_task_id'], task.id);
    },
  );

  test('AgentTaskResult waits for a running task to complete', () async {
    final harness = await _AgentToolHarness.create();
    addTearDown(harness.dispose);
    final task = await harness.controller.publishTaskWithResult(
      'agent-1',
      title: '等待结果任务',
    );
    expect(task, isNotNull);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 120), () async {
        await harness.controller.updateTaskState(
          'agent-1',
          task!.id,
          status: AgentTaskStatus.completed,
          progress: 1,
          result: '任务完成结果',
          activityKind: 'task_completed',
          activityTitle: 'task_completed',
        );
      }),
    );

    final tool = harness.tool(AiBuiltinToolKind.agentTaskResult);
    final result = await tool.execute(
      harness.context(
        toolName: 'AgentTaskResult',
        arguments: <String, Object?>{
          'agent_id': 'agent-1',
          'task_id': task!.id,
          'wait_ms': 1200,
          'poll_ms': 100,
        },
      ),
    );

    expect(result.status, BashToolExecutionStatus.success);
    final payload = jsonDecode(result.stdout) as Map<String, Object?>;
    expect(payload['result_available'], true);
    expect(payload['result'], '任务完成结果');
    final wait = payload['wait'] as Map<String, Object?>;
    expect(wait['completed_during_wait'], true);
  });
}

class _AgentToolHarness {
  _AgentToolHarness({
    required this.tempDir,
    required this.controller,
    required this.tools,
    required this.model,
  });

  final Directory tempDir;
  final AgentsController controller;
  final List<AiAgentTool> tools;
  final AiModelConfig model;

  static Future<_AgentToolHarness> create({
    String chatReply = '完成。',
    Duration chatDelay = Duration.zero,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'openhand-agent-tools-test-',
    );
    final controller = AgentsController.uninitialized(
      store: AgentsStore(filePath: '${tempDir.path}/agents.json'),
    );
    await controller.refresh();
    final model = _model();
    await controller.saveAgent(
      const AgentProfile(
        id: 'agent-1',
        name: '资料员',
        enabled: true,
        lifecycleState: AgentLifecycleState.running,
        executionMode: AgentExecutionMode.fullAccess,
      ),
    );
    final tools = AiAgentTool.all(
      agentsControllerProvider: () => controller,
      backgroundChatClient: _FakeChatClient(chatReply, delay: chatDelay),
      aiModelsProvider: () => <AiModelConfig>[model],
      promptRenderer: AgentPromptRenderer(loader: (_) async => _promptTemplate),
    );
    for (final tool in tools) {
      tool.withExecutor((_, subContext) async {
        return AiToolUtils.invalidResult(
          subContext.toolCall.name,
          'No subtools are expected in this regression test.',
        );
      });
    }
    return _AgentToolHarness(
      tempDir: tempDir,
      controller: controller,
      tools: tools,
      model: model,
    );
  }

  AiAgentTool tool(AiBuiltinToolKind kind) {
    return tools.firstWhere((tool) => tool.kind == kind);
  }

  AiToolExecutionContext context({
    required String toolName,
    required Map<String, Object?> arguments,
  }) {
    return AiToolExecutionContext(
      sessionId: 'session-1',
      catalog: _catalog(tools),
      toolCall: AiToolCall(
        id: 'call-1',
        name: toolName,
        arguments: jsonEncode(arguments),
      ),
      decodedArguments: arguments,
      model: model,
      previouslyReadFiles: const <String>{},
      denyCommandRules: const <AiDenyCommandRule>[],
      requireWriteCommandConfirmation: false,
      confirmWriteCommand: null,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

class _FakeChatClient implements AiChatClient {
  const _FakeChatClient(this.reply, {this.delay = Duration.zero});

  final String reply;
  final Duration delay;

  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 60),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return AiChatCompletion(
      reply: reply,
      usage: const AiTokenUsage(totalTokens: 12),
    );
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

AiResolvedToolCatalog _catalog(List<AiAgentTool> tools) {
  final resolved = tools
      .map(
        (tool) => AiResolvedTool(
          name: tool.aliases.first,
          definition: AiToolDefinition(
            name: tool.aliases.first,
            description: '${tool.aliases.first} description',
            parameters: const <String, Object?>{'type': 'object'},
          ),
          source: AiRuntimeToolSource.builtin,
          builtinKind: tool.kind,
        ),
      )
      .toList(growable: false);
  return AiResolvedToolCatalog(
    definitions: resolved.map((tool) => tool.definition).toList(),
    toolsByName: <String, AiResolvedTool>{
      for (final tool in resolved) tool.name: tool,
    },
  );
}

AiModelConfig _model() {
  return const AiModelConfig(
    id: 'model-config',
    baseUrl: 'http://localhost',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: 'test-model',
    protocolType: AiProtocolType.openai,
  );
}

const String _promptTemplate = '''
<identity>{{AGENT_PROFILE_JSON}}</identity>
<capability_bindings>{{CAPABILITY_BINDINGS_JSON}}</capability_bindings>
<runtime_policy>{{RUNTIME_POLICY_JSON}}</runtime_policy>
<operational_state>{{OPERATIONAL_STATE_JSON}}</operational_state>
<task_context>{{TASK_CONTEXT_JSON}}</task_context>
{{AGENT_COORDINATION_GUIDANCE}}
''';
