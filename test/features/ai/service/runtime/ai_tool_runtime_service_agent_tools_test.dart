import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/data/agents_store.dart';
import 'package:openhand/features/agents/index.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/mcp/index.dart';
import 'package:openhand/features/memory/index.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Agent builtin tool catalog gate', () {
    late Directory tempDir;
    late AgentsController controller;
    late AiToolRuntimeService runtime;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'openhand_agent_tool_catalog_test_',
      );
      controller = AgentsController.uninitialized(
        store: AgentsStore(filePath: p.join(tempDir.path, 'agents.json')),
      );
      await controller.refresh();
      runtime = _runtimeService(() => controller);
    });

    tearDown(() async {
      runtime.dispose();
      controller.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('agent tool descriptions document delegation and polling rules', () {
      final publish = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentTaskPublish,
      )!;
      final progress = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentTaskProgress,
      )!;
      final track = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentTaskTrack,
      )!;
      final result = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentTaskResult,
      )!;

      expect(
        publish.definition.description,
        contains('only when the task matches an agent responsibility'),
      );
      expect(
        publish.definition.description,
        contains('current model and local tools can complete directly'),
      );
      expect(
        publish.definition.description,
        contains('poll AgentTaskProgress or AgentTaskTrack'),
      );
      expect(
        progress.definition.description,
        contains('state.needs_polling is true'),
      );
      expect(track.definition.description, contains('operational summary'));
      expect(
        result.definition.description,
        contains('terminal, requires attention'),
      );
    });

    test('hides agent tools until at least one agent is enabled', () async {
      var catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(catalog.find('AgentList'), isNull);
      expect(catalog.find('AgentTaskPublish'), isNull);

      await controller.saveAgent(_agent(enabled: false));
      catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(catalog.find('AgentList'), isNull);

      await controller.setAgentEnabled('agent-1', enabled: true);
      catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(
        catalog.find('AgentList')?.builtinKind,
        AiBuiltinToolKind.agentList,
      );
      expect(
        catalog.find('AgentTaskPublish')?.builtinKind,
        AiBuiltinToolKind.agentTaskPublish,
      );
      expect(
        catalog.find('AgentTaskComplete')?.builtinKind,
        AiBuiltinToolKind.agentTaskComplete,
      );

      await controller.setAgentEnabled('agent-1', enabled: false);
      catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(catalog.find('AgentList'), isNull);
      expect(catalog.find('AgentTaskPublish'), isNull);
      expect(catalog.find('AgentTaskComplete'), isNull);
    });

    test(
      'filters agent tools by enabled agent builtin tool bindings',
      () async {
        await controller.saveAgent(
          _agent(
            enabled: true,
            builtinToolNames: const <String>['AgentList', 'agent_task_track'],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );

        expect(
          catalog.find('AgentList')?.builtinKind,
          AiBuiltinToolKind.agentList,
        );
        expect(
          catalog.find('AgentTaskTrack')?.builtinKind,
          AiBuiltinToolKind.agentTaskTrack,
        );
        expect(catalog.find('AgentTaskPublish'), isNull);
        expect(catalog.find('AgentTaskComplete'), isNull);
      },
    );

    test('publish tool routes to the best matching enabled agent', () async {
      await controller.saveAgent(
        _agent(
          id: 'finance-agent',
          name: 'Finance Agent',
          enabled: true,
          routeFrontMatter: '''
keywords:
  - invoice
  - reconciliation
domains: finance, cloud billing
''',
          taskLabels: const <String>['finance'],
        ),
      );
      await controller.saveAgent(
        _agent(
          id: 'release-agent',
          name: 'Release Agent',
          enabled: true,
          routeFrontMatter: 'keywords: deploy, rollback, release',
          taskLabels: const <String>['release'],
        ),
      );

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await runtime.execute(
        sessionId: 'session-1',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-1',
          name: 'AgentTaskPublish',
          arguments: jsonEncode(<String, Object?>{
            'title': 'Reconcile cloud invoice',
            'description':
                'Check the finance invoice and reconciliation evidence.',
            'labels': <String>['finance'],
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(result.status, BashToolExecutionStatus.success);
      final publishPayload =
          jsonDecode(result.resultText) as Map<String, Object?>;
      final publishedTask = publishPayload['task'] as Map<String, Object?>;
      final publishedWorker =
          publishedTask['assigned_worker'] as Map<String, Object?>;
      final publishedState = publishedTask['state'] as Map<String, Object?>;
      final financeAgent = controller.agentById('finance-agent')!;
      final releaseAgent = controller.agentById('release-agent')!;
      final assignedWorkerId =
          '${financeAgent.tasks.single.extra['assigned_worker_id']}';
      expect(financeAgent.tasks, hasLength(1));
      expect(releaseAgent.tasks, isEmpty);
      expect(financeAgent.tasks.single.title, 'Reconcile cloud invoice');
      expect(publishedWorker['id'], assignedWorkerId);
      expect(publishedWorker['status'], 'busy');
      expect(publishedState['terminal'], isFalse);
      expect(publishedState['needs_polling'], isTrue);
      expect(
        publishedState['allowed_tools'],
        containsAll(<String>[
          'AgentTaskPause',
          'AgentTaskCancel',
          'AgentTaskTerminate',
          'AgentTaskComplete',
        ]),
      );
      expect(publishedState['recommended_poll_ms'], isPositive);
      expect(financeAgent.tasks.single.extra['agent_route_score'], isPositive);
      expect(
        financeAgent.tasks.single.extra['agent_route_reason'],
        contains('invoice'),
      );

      final progress = await runtime.execute(
        sessionId: 'session-1',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-2',
          name: 'AgentTaskProgress',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'finance-agent',
            'task_id': financeAgent.tasks.single.id,
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );
      final progressPayload =
          jsonDecode(progress.resultText) as Map<String, Object?>;
      final progressWorker =
          progressPayload['assigned_worker'] as Map<String, Object?>;
      final progressState = progressPayload['state'] as Map<String, Object?>;
      expect(progress.status, BashToolExecutionStatus.success);
      expect(progressWorker['id'], assignedWorkerId);
      expect(progressWorker['current_task_id'], financeAgent.tasks.single.id);
      expect(progressState['needs_polling'], isTrue);
    });

    test('complete tool writes task result and releases worker', () async {
      await controller.saveAgent(_agent(enabled: true));
      final task = await controller.publishTaskWithResult(
        'agent-1',
        title: 'Collect release evidence',
      );
      expect(task, isNotNull);
      expect(task!.status, AgentTaskStatus.running);

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await runtime.execute(
        sessionId: 'session-1',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-1',
          name: 'AgentTaskComplete',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'task_id': task.id,
            'result': 'Release evidence collected and verified.',
            'note': 'worker handoff complete',
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(result.status, BashToolExecutionStatus.success);
      final resultPayload =
          jsonDecode(result.resultText) as Map<String, Object?>;
      final resultTask = resultPayload['task'] as Map<String, Object?>;
      final resultState = resultTask['state'] as Map<String, Object?>;
      final resultWorker =
          resultTask['assigned_worker'] as Map<String, Object?>;
      final completed = controller.taskById('agent-1', task.id)!;
      expect(completed.status, AgentTaskStatus.completed);
      expect(completed.progress, 1);
      expect(completed.result, 'Release evidence collected and verified.');
      expect(completed.note, 'worker handoff complete');

      final agent = controller.agentById('agent-1')!;
      final assignedWorkerId = '${task.extra['assigned_worker_id']}';
      expect(agent.workers.single.status, AgentWorkerStatus.idle);
      expect(agent.workers.single.currentTaskId, isEmpty);
      expect(agent.activities.first.kind, 'task_completed');
      expect(agent.auditEvents.first.kind, 'task_completed');
      expect(resultState['terminal'], isTrue);
      expect(resultState['needs_polling'], isFalse);
      expect(resultState['allowed_tools'], isEmpty);
      expect(resultWorker['id'], assignedWorkerId);
      expect(resultWorker['status'], 'idle');
    });

    test(
      'result tool exposes operational audit and resource summary',
      () async {
        await controller.saveAgent(
          _agent(enabled: true).copyWith(
            resourceUsage: const AgentResourceUsage(
              cpuPercent: 0.42,
              memoryBytes: 512,
              diskBytes: 2048,
              persistedBytes: 1024,
              tokenBudget: 1000,
              tokenUsed: 600,
              openHandles: 3,
            ),
          ),
        );
        final task = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Collect audit evidence',
        );
        final assignedWorkerId = '${task!.extra['assigned_worker_id']}';
        final currentAgent = controller.agentById('agent-1')!;
        await controller.saveAgent(
          currentAgent.copyWith(
            auditEvents: <AgentAuditEvent>[
              AgentAuditEvent(
                id: 'audit-token-1',
                kind: 'skill_call',
                summary: 'skill_call: collect evidence',
                toolName: 'SkillRunner',
                tokenUsage: 123,
                requestCount: 2,
                createdAt: DateTime.utc(2026, 7, 4),
                metadata: <String, Object?>{
                  'task_id': task.id,
                  'worker_id': assignedWorkerId,
                },
              ),
              ...currentAgent.auditEvents,
            ],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final result = await runtime.execute(
          sessionId: 'session-1',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-1',
            name: 'AgentTaskResult',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-1',
              'task_id': task.id,
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        expect(result.status, BashToolExecutionStatus.success);
        final payload = jsonDecode(result.resultText) as Map<String, Object?>;
        final summary = payload['operational_summary'] as Map<String, Object?>;
        final taskMetrics = summary['task_metrics'] as Map<String, Object?>;
        final taskStatusCounts =
            taskMetrics['by_status'] as Map<String, Object?>;
        final workerCapacity =
            summary['worker_capacity'] as Map<String, Object?>;
        final auditSummary = summary['audit_summary'] as Map<String, Object?>;
        final toolCounts = auditSummary['tool_counts'] as Map<String, Object?>;
        final resourceUsage = summary['resource_usage'] as Map<String, Object?>;

        expect(taskMetrics['total'], 1);
        expect(taskMetrics['active'], 1);
        expect(taskStatusCounts['running'], 1);
        expect(workerCapacity['busy'], 1);
        expect(workerCapacity['assigned_worker_id'], assignedWorkerId);
        expect(workerCapacity['assigned_worker_status'], 'busy');
        expect(auditSummary['event_count'], 3);
        expect(auditSummary['request_count'], 4);
        expect(auditSummary['token_usage'], 123);
        expect(toolCounts['SkillRunner'], 1);
        expect(toolCounts['AgentTaskDesk'], 2);
        expect(resourceUsage['token_remaining'], 400);
        expect(resourceUsage['token_usage_ratio'], 0.6);
        expect(resourceUsage['open_handles'], 3);
      },
    );

    test('complete tool requires a non-empty result', () async {
      await controller.saveAgent(_agent(enabled: true));
      final task = await controller.publishTaskWithResult(
        'agent-1',
        title: 'Collect missing evidence',
      );

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await runtime.execute(
        sessionId: 'session-1',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-1',
          name: 'AgentTaskComplete',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'task_id': task!.id,
            'result': '   ',
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.resultText, contains('result is required'));
      expect(
        controller.taskById('agent-1', task.id)!.status,
        AgentTaskStatus.running,
      );
    });
  });
}

AiToolRuntimeService _runtimeService(AgentsControllerProvider provider) {
  return AiToolRuntimeService(
    bashToolService: AiBashToolService(),
    hookService: AiNoopClaudeHookService(),
    mcpToolService: _FakeMcpToolDiscoveryService(),
    backgroundChatClient: _FakeAiChatClient(),
    agentsControllerProvider: provider,
  );
}

AiSessionRuntimeContext _runtimeContext() {
  return const AiSessionRuntimeContext(
    localeTag: 'en',
    appVersion: 'test',
    appBuildNumber: '1',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.json',
    compressionThresholdChars: 100000,
    memoryEnabled: false,
    memoryEntries: <UserMemoryEntry>[],
  );
}

AgentProfile _agent({
  String id = 'agent-1',
  String name = 'Ops Agent',
  required bool enabled,
  List<String> builtinToolNames = const <String>[],
  String routeFrontMatter = '',
  List<String> taskLabels = const <String>[],
}) {
  return AgentProfile(
    id: id,
    name: name,
    enabled: enabled,
    builtinToolNames: builtinToolNames,
    routeFrontMatter: routeFrontMatter,
    taskLabels: taskLabels,
    lifecycleState: enabled
        ? AgentLifecycleState.running
        : AgentLifecycleState.stopped,
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

class _FakeMcpToolDiscoveryService implements McpToolDiscoveryService {
  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    return const McpToolCatalog();
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    return const McpServerHealth();
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
    Map<String, String>? customHeaders,
  }) async {
    return const McpToolCallResult(outputText: '');
  }

  @override
  void dispose() {}
}

class _FakeAiChatClient implements AiChatClient {
  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 1),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 1),
    Duration streamIdleTimeout = const Duration(seconds: 1),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> testModel(AiModelConfig model) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
