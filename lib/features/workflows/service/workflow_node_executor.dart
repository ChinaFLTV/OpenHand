import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../app/support/system_proxy.dart';
import '../../../shared/net/bounded_http_request.dart';
import '../../../shared/net/http_methods.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_base64.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart'
    show
        AiChatClient,
        AiChatCompletion,
        AiChatRole,
        AiChatService,
        AiChatTurn,
        AiModelConfig,
        AiModelProfile,
        AiPromptTemplateRepository,
        AiToolDefinition;
import '../../instructions/index.dart' show UserInstructionEntry;
import '../../knowledge_base/index.dart'
    show KnowledgeBaseController, KnowledgeRetrievalHit;
import '../../mcp/index.dart' show McpServer, McpTool;
import '../../memory/index.dart' show UserMemoryEntry;
import '../../skills/index.dart' show LocalSkill;
import '../model/workflow_definition.dart';
import 'workflow_code_executor.dart';
import 'workflow_graph_analysis.dart';

const int _maxWorkflowHttpRequestBytes = 4 * 1024 * 1024;
const int _maxWorkflowHttpResponseBytes = 4 * 1024 * 1024;
const String _workflowHttpRequestTooLargeMessage = 'HTTP 请求体超过 4 MiB 上限。';
const int _maxWorkflowPromptCharacters = 256 * 1024;
const int _maxWorkflowResourceCharacters = 96 * 1024;
const int _maxWorkflowMcpTools = 64;
const Duration _humanInterventionTimeoutGrace = Duration(seconds: 1);
const int _maxWorkflowToolRounds = 8;
const int _maxWorkflowToolCalls = 32;
const int _maxWorkflowToolOutputCharacters = 128 * 1024;

final RegExp _workflowBase64DataUrlPattern = RegExp(
  r'^data:[^;,]+;base64,(.*)$',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _workflowMultipartNameUnsafePattern = RegExp(r'["\r\n]');

typedef WorkflowMcpToolInvoker =
    Future<WorkflowMcpToolInvocationResult> Function({
      required String serverName,
      required String toolName,
      required Map<String, Object?> arguments,
      required String toolCallId,
      Future<void>? cancelSignal,
    });

typedef WorkflowLlmConversationListener =
    void Function(WorkflowLlmConversation conversation);

typedef WorkflowNodeExecutionListener =
    void Function(WorkflowNodeExecutionEvent event);

typedef WorkflowHumanInterventionHandler =
    Future<WorkflowHumanInterventionResponse> Function(
      WorkflowHumanInterventionRequest request,
    );

class WorkflowHumanInterventionRequest {
  const WorkflowHumanInterventionRequest({
    required this.nodeId,
    required this.nodeTitle,
    required this.content,
    required this.fields,
    required this.initialValues,
    required this.actions,
    required this.timeout,
    this.cancelSignal,
  });

  final String nodeId;
  final String nodeTitle;
  final String content;
  final List<WorkflowOutputField> fields;
  final Map<String, Object?> initialValues;
  final List<WorkflowHumanAction> actions;
  final Duration timeout;
  final Future<void>? cancelSignal;
}

class WorkflowHumanInterventionResponse {
  const WorkflowHumanInterventionResponse({
    required this.actionId,
    this.inputs = const <String, Object?>{},
  });

  final String actionId;
  final Map<String, Object?> inputs;

  bool get timedOut => actionId == workflowHumanTimeoutHandleId;
}

enum WorkflowLlmConversationStatus { running, succeeded, failed }

enum WorkflowNodeExecutionPhase {
  pending,
  running,
  succeeded,
  warning,
  failed,
  skipped,
}

class WorkflowNodeExecutionEvent {
  const WorkflowNodeExecutionEvent({
    required this.nodeId,
    required this.phase,
    this.duration = Duration.zero,
    this.attempts = 0,
    this.resolvedInputs = const <String, Object?>{},
    this.output,
    this.error,
  });

  final String nodeId;
  final WorkflowNodeExecutionPhase phase;
  final Duration duration;
  final int attempts;
  final Map<String, Object?> resolvedInputs;
  final Object? output;
  final String? error;
}

enum WorkflowLlmMessageKind { user, reasoning, assistant, toolCall, toolResult }

class WorkflowLlmConversationMessage {
  const WorkflowLlmConversationMessage({
    required this.id,
    required this.kind,
    required this.content,
    required this.createdAt,
    this.toolName,
    this.toolCallId,
    this.isError = false,
  });

  final String id;
  final WorkflowLlmMessageKind kind;
  final String content;
  final DateTime createdAt;
  final String? toolName;
  final String? toolCallId;
  final bool isError;
}

class WorkflowLlmConversation {
  const WorkflowLlmConversation({
    required this.nodeId,
    required this.modelConfigId,
    required this.modelId,
    required this.modelLabel,
    required this.startedAt,
    required this.duration,
    required this.attempts,
    required this.status,
    required this.messages,
    this.endedAt,
    this.error,
  });

  final String nodeId;
  final String modelConfigId;
  final String modelId;
  final String modelLabel;
  final DateTime startedAt;
  final DateTime? endedAt;
  final Duration duration;
  final int attempts;
  final WorkflowLlmConversationStatus status;
  final List<WorkflowLlmConversationMessage> messages;
  final String? error;
}

class WorkflowMcpToolInvocationResult {
  const WorkflowMcpToolInvocationResult({
    required this.output,
    required this.isError,
  });

  final String output;
  final bool isError;
}

class WorkflowNodeExecutionException implements Exception {
  const WorkflowNodeExecutionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class WorkflowNodeExecutionCancelledException implements Exception {
  const WorkflowNodeExecutionCancelledException();

  @override
  String toString() => '节点测试已停止。';
}

class WorkflowExecutionCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const WorkflowNodeExecutionCancelledException();
  }

  Future<T> race<T>(Future<T> operation) async {
    throwIfCancelled();
    final result = await Future.any<T>(<Future<T>>[
      operation,
      whenCancelled.then<T>(
        (_) => throw const WorkflowNodeExecutionCancelledException(),
      ),
    ]);
    throwIfCancelled();
    return result;
  }

  Future<void> delay(Duration duration) async {
    throwIfCancelled();
    if (duration <= Duration.zero) return;
    final cancelled = await Future.any<bool>(<Future<bool>>[
      Future<bool>.delayed(duration, () => false),
      whenCancelled.then<bool>((_) => true),
    ]);
    if (cancelled) throw const WorkflowNodeExecutionCancelledException();
  }
}

Future<T> _awaitWorkflowOperation<T>(
  WorkflowExecutionCancellationToken? cancellation,
  Future<T> Function() operation,
) {
  if (cancellation == null) return operation();
  return cancellation.race(Future<T>.sync(operation));
}

Future<void> _waitForWorkflowRetry(
  Duration interval,
  WorkflowExecutionCancellationToken? cancellation,
) => cancellation?.delay(interval) ?? Future<void>.delayed(interval);

class _WorkflowLoopExitSignal implements Exception {
  const _WorkflowLoopExitSignal([this.variables = const <String, Object?>{}]);

  final Map<String, Object?> variables;
}

class WorkflowExecutionResources {
  const WorkflowExecutionResources({
    required this.models,
    required this.templateRepository,
    this.skills = const <LocalSkill>[],
    this.memories = const <UserMemoryEntry>[],
    this.instructions = const <UserInstructionEntry>[],
    this.knowledgeBaseController,
    this.mcpServers = const <McpServer>[],
    this.mcpTools = const <String, List<McpTool>>{},
    this.codeRuntimes = const <WorkflowCodeLanguage, WorkflowCodeRuntime>{},
    this.mcpToolInvoker,
    this.onLlmConversation,
    this.onHumanIntervention,
    this.onNodeExecution,
    this.cancellation,
  });

  final List<AiModelConfig> models;
  final AiPromptTemplateRepository templateRepository;
  final List<LocalSkill> skills;
  final List<UserMemoryEntry> memories;
  final List<UserInstructionEntry> instructions;
  final KnowledgeBaseController? knowledgeBaseController;
  final List<McpServer> mcpServers;
  final Map<String, List<McpTool>> mcpTools;
  final Map<WorkflowCodeLanguage, WorkflowCodeRuntime> codeRuntimes;
  final WorkflowMcpToolInvoker? mcpToolInvoker;
  final WorkflowLlmConversationListener? onLlmConversation;
  final WorkflowHumanInterventionHandler? onHumanIntervention;
  final WorkflowNodeExecutionListener? onNodeExecution;
  final WorkflowExecutionCancellationToken? cancellation;

  WorkflowExecutionResources withNodeExecutionListener(
    WorkflowNodeExecutionListener listener,
  ) => WorkflowExecutionResources(
    models: models,
    templateRepository: templateRepository,
    skills: skills,
    memories: memories,
    instructions: instructions,
    knowledgeBaseController: knowledgeBaseController,
    mcpServers: mcpServers,
    mcpTools: mcpTools,
    codeRuntimes: codeRuntimes,
    mcpToolInvoker: mcpToolInvoker,
    onLlmConversation: onLlmConversation,
    onHumanIntervention: onHumanIntervention,
    onNodeExecution: listener,
    cancellation: cancellation,
  );

  WorkflowExecutionResources withCancellation(
    WorkflowExecutionCancellationToken value,
  ) => WorkflowExecutionResources(
    models: models,
    templateRepository: templateRepository,
    skills: skills,
    memories: memories,
    instructions: instructions,
    knowledgeBaseController: knowledgeBaseController,
    mcpServers: mcpServers,
    mcpTools: mcpTools,
    codeRuntimes: codeRuntimes,
    mcpToolInvoker: mcpToolInvoker,
    onLlmConversation: onLlmConversation,
    onHumanIntervention: onHumanIntervention,
    onNodeExecution: onNodeExecution,
    cancellation: value,
  );
}

class WorkflowNodeExecutionResult {
  const WorkflowNodeExecutionResult({
    required this.output,
    required this.attempts,
    required this.duration,
    this.resolvedInputs = const <String, Object?>{},
    this.rawOutput = '',
    this.conversation,
    this.selectedBranchId,
    this.recoveredFromError = false,
  });

  final Object? output;
  final Map<String, Object?> resolvedInputs;
  final String rawOutput;
  final int attempts;
  final Duration duration;
  final WorkflowLlmConversation? conversation;
  final String? selectedBranchId;
  final bool recoveredFromError;
}

class WorkflowExecutionResult {
  const WorkflowExecutionResult({
    required this.output,
    required this.variables,
    required this.duration,
    required this.executedSteps,
    required this.warningSteps,
  });

  final Object? output;
  final Map<String, Object?> variables;
  final Duration duration;
  final int executedSteps;
  final int warningSteps;
}

class WorkflowNodeExecutor {
  WorkflowNodeExecutor({AiChatClient? chatClient})
    : _chatClient = chatClient ?? AiChatService(),
      _ownsChatClient = chatClient == null,
      _proxyRevision = SystemProxyResolver.instance.revision.value;

  AiChatClient _chatClient;
  final bool _ownsChatClient;
  int _proxyRevision;
  static const WorkflowCodeExecutor _codeExecutor = WorkflowCodeExecutor();

  void _refreshProxyAwareChatClient() {
    if (!_ownsChatClient) return;
    final revision = SystemProxyResolver.instance.revision.value;
    if (revision == _proxyRevision) return;
    _chatClient.dispose();
    _chatClient = AiChatService();
    _proxyRevision = revision;
  }

  Future<WorkflowNodeExecutionResult> execute({
    required WorkflowNode node,
    required WorkflowExecutionResources resources,
    Map<String, Object?> variables = const <String, Object?>{},
    List<WorkflowNode> workflowNodes = const <WorkflowNode>[],
    List<WorkflowConnection> workflowConnections = const <WorkflowConnection>[],
    bool preferProvidedInputValues = false,
  }) async {
    resources.cancellation?.throwIfCancelled();
    final stopwatch = Stopwatch()..start();
    resources.onNodeExecution?.call(
      WorkflowNodeExecutionEvent(
        nodeId: node.id,
        phase: WorkflowNodeExecutionPhase.running,
      ),
    );
    try {
      final result = await _awaitWorkflowOperation(
        resources.cancellation,
        () => switch (node.kind) {
          WorkflowNodeKind.start => Future<WorkflowNodeExecutionResult>.value(
            _executeParameterNode(
              fields: node.inputFields(),
              variables: variables,
              label: '输入参数',
            ),
          ),
          WorkflowNodeKind.llm => _executeLlm(node, resources, variables),
          WorkflowNodeKind.httpRequest => _executeHttp(
            node,
            resources,
            variables,
          ),
          WorkflowNodeKind.condition => _executeCondition(node, variables),
          WorkflowNodeKind.loop => _executeLoop(
            node,
            resources,
            variables,
            workflowNodes,
            workflowConnections,
          ),
          WorkflowNodeKind.iteration => _executeIteration(
            node,
            resources,
            variables,
            workflowNodes,
            workflowConnections,
          ),
          WorkflowNodeKind.parameterAssignment =>
            _executeConfiguredParameterNode(
              fields: node.outputFields(),
              resources: resources,
              variables: variables,
              label: '赋值参数',
            ),
          WorkflowNodeKind.listOperation => _executeListOperation(
            node,
            variables,
          ),
          WorkflowNodeKind.codeExecution => _executeCode(
            node,
            resources,
            variables,
            preferProvidedInputValues: preferProvidedInputValues,
          ),
          WorkflowNodeKind.humanIntervention => _executeHumanIntervention(
            node,
            resources,
            variables,
          ),
          WorkflowNodeKind.loopExit =>
            Future<WorkflowNodeExecutionResult>.error(
              const _WorkflowLoopExitSignal(),
            ),
          WorkflowNodeKind.end => _executeConfiguredParameterNode(
            fields: node.outputFields(),
            resources: resources,
            variables: variables,
            label: '输出参数',
          ),
        },
      );
      resources.onNodeExecution?.call(
        WorkflowNodeExecutionEvent(
          nodeId: node.id,
          phase: result.recoveredFromError
              ? WorkflowNodeExecutionPhase.warning
              : WorkflowNodeExecutionPhase.succeeded,
          duration: result.duration,
          attempts: result.attempts,
          resolvedInputs: Map<String, Object?>.unmodifiable(
            result.resolvedInputs.isNotEmpty
                ? result.resolvedInputs
                : variables,
          ),
          output: result.output,
        ),
      );
      return result;
    } catch (error) {
      resources.onNodeExecution?.call(
        WorkflowNodeExecutionEvent(
          nodeId: node.id,
          phase: WorkflowNodeExecutionPhase.failed,
          duration: stopwatch.elapsed,
          error: _executionErrorText(error),
        ),
      );
      rethrow;
    }
  }

  Future<WorkflowExecutionResult> executeWorkflow({
    required List<WorkflowNode> nodes,
    required List<WorkflowConnection> connections,
    required WorkflowExecutionResources resources,
    Map<String, Object?> inputs = const <String, Object?>{},
  }) async {
    resources.cancellation?.throwIfCancelled();
    if (nodes.length > maxWorkflowNodeCount ||
        connections.length > maxWorkflowConnectionCount) {
      throw const WorkflowNodeExecutionException('工作流规模超过执行安全上限。');
    }
    final parameterError = validateWorkflowParameters(nodes, connections);
    if (parameterError != null) {
      throw WorkflowNodeExecutionException(parameterError);
    }
    final topLevelNodes = nodes
        .where((node) => node.parentNodeId == null)
        .toList(growable: false);
    final starts = topLevelNodes
        .where((node) => node.kind == WorkflowNodeKind.start)
        .toList(growable: false);
    final ends = topLevelNodes
        .where((node) => node.kind == WorkflowNodeKind.end)
        .toList(growable: false);
    if (starts.length != 1 || ends.length != 1) {
      throw const WorkflowNodeExecutionException('工作流必须且只能包含一个开始节点和一个结束节点。');
    }
    final nodesById = <String, WorkflowNode>{
      for (final node in topLevelNodes) node.id: node,
    };
    final edges = connections
        .where(
          (edge) =>
              nodesById.containsKey(edge.sourceNodeId) &&
              nodesById.containsKey(edge.targetNodeId) &&
              edge.sourceHandleId != workflowContainerStartHandleId,
        )
        .toList(growable: false);
    final graph = analyzeWorkflowGraph(
      nodeIds: nodesById.keys,
      connections: edges,
      startNodeIds: <String>[starts.single.id],
    );
    if (graph.reachableNodeIds.length != topLevelNodes.length) {
      throw const WorkflowNodeExecutionException('工作流包含无法从开始节点到达的节点。');
    }
    if (!graph.isAcyclic) {
      throw const WorkflowNodeExecutionException('工作流包含循环连线，无法开始测试。');
    }
    final connectionError = validateWorkflowOutgoingConnections(
      nodes: topLevelNodes,
      graph: graph,
    );
    if (connectionError != null) {
      throw WorkflowNodeExecutionException(connectionError);
    }

    var executedSteps = 0;
    var warningSteps = 0;
    final observedResources = resources.withNodeExecutionListener((event) {
      if (event.phase == WorkflowNodeExecutionPhase.running) {
        executedSteps += 1;
      } else if (event.phase == WorkflowNodeExecutionPhase.warning) {
        warningSteps += 1;
      }
      resources.onNodeExecution?.call(event);
    });
    final variables = <String, Object?>{...inputs};
    final activeNodeIds = <String>{starts.single.id};
    Object? output;
    var reachedEnd = false;
    final stopwatch = Stopwatch()..start();
    for (final nodeId in graph.topologicalNodeIds) {
      resources.cancellation?.throwIfCancelled();
      if (!activeNodeIds.contains(nodeId)) continue;
      final node = nodesById[nodeId];
      if (node == null) continue;
      final result = await execute(
        node: node,
        resources: observedResources,
        variables: variables,
        workflowNodes: nodes,
        workflowConnections: connections,
      );
      _mergeNodeOutput(node, result, variables);
      if (node.kind == WorkflowNodeKind.end) {
        output = result.output;
        reachedEnd = true;
      }
      for (final edge in edges) {
        if (edge.sourceNodeId != node.id) continue;
        if (result.selectedBranchId != null &&
            edge.sourceHandleId != result.selectedBranchId) {
          continue;
        }
        activeNodeIds.add(edge.targetNodeId);
      }
    }
    stopwatch.stop();
    if (!reachedEnd) {
      throw const WorkflowNodeExecutionException('当前执行分支未到达结束节点。');
    }
    return WorkflowExecutionResult(
      output: output,
      variables: Map<String, Object?>.unmodifiable(variables),
      duration: stopwatch.elapsed,
      executedSteps: executedSteps,
      warningSteps: warningSteps,
    );
  }

  void dispose() {
    if (_ownsChatClient) _chatClient.dispose();
  }

  WorkflowNodeExecutionResult _executeParameterNode({
    required List<WorkflowOutputField> fields,
    required Map<String, Object?> variables,
    required String label,
  }) {
    final output = WorkflowStructuredOutputParser.resolveValues(
      fields,
      variables,
      label: label,
    );
    String rawOutput;
    try {
      rawOutput = jsonEncode(output);
    } on JsonUnsupportedObjectError catch (error) {
      throw WorkflowNodeExecutionException('$label包含无法序列化的值。', cause: error);
    }
    return WorkflowNodeExecutionResult(
      output: output,
      rawOutput: rawOutput,
      attempts: 1,
      duration: Duration.zero,
    );
  }

  Future<WorkflowNodeExecutionResult> _executeConfiguredParameterNode({
    required List<WorkflowOutputField> fields,
    required WorkflowExecutionResources resources,
    required Map<String, Object?> variables,
    required String label,
  }) async {
    final output = await _resolveConfiguredFieldValues(
      fields: fields,
      resources: resources,
      variables: variables,
      label: label,
    );
    try {
      return WorkflowNodeExecutionResult(
        output: output,
        rawOutput: jsonEncode(output),
        attempts: 1,
        duration: Duration.zero,
      );
    } on JsonUnsupportedObjectError catch (error) {
      throw WorkflowNodeExecutionException('$label包含无法序列化的值。', cause: error);
    }
  }

  Future<WorkflowNodeExecutionResult> _executeCode(
    WorkflowNode node,
    WorkflowExecutionResources resources,
    Map<String, Object?> variables, {
    bool preferProvidedInputValues = false,
  }) async {
    resources.cancellation?.throwIfCancelled();
    final language = WorkflowCodeLanguage.fromStorage(
      node.settings[WorkflowSettingKeys.codeLanguage],
    );
    final runtime = resources.codeRuntimes[language];
    if (runtime == null || !runtime.isAvailable) {
      throw WorkflowNodeExecutionException(
        runtime?.unavailableReason ?? '${language.label} 运行时不可用，请先在插件板块安装并启用。',
      );
    }
    final inputFields = node.codeInputFields();
    WorkflowStructuredOutputParser.validateFields(
      inputFields,
      label: '代码输入参数',
      allowEmpty: true,
    );
    final inputs = await _resolveConfiguredFieldValues(
      fields: inputFields,
      resources: resources,
      variables: variables,
      label: '代码输入参数',
      preferProvidedInputValues: preferProvidedInputValues,
    );
    resources.cancellation?.throwIfCancelled();
    final outputFields = node.outputFields();
    WorkflowStructuredOutputParser.validateFields(
      outputFields,
      label: '代码输出参数',
    );
    final errorStrategy = WorkflowErrorStrategy.fromStorage(
      node.settings[WorkflowSettingKeys.errorStrategy],
    );
    final retryCount = node.retryEnabled()
        ? node
              .intSetting(
                WorkflowSettingKeys.retryCount,
                defaultWorkflowCodeRetryCount,
              )
              .clamp(minWorkflowCodeRetryCount, maxWorkflowCodeRetryCount)
              .toInt()
        : 0;
    final retryInterval = Duration(
      milliseconds: node
          .intSetting(
            WorkflowSettingKeys.retryIntervalMs,
            defaultWorkflowCodeRetryIntervalMs,
          )
          .clamp(minWorkflowCodeRetryIntervalMs, maxWorkflowCodeRetryIntervalMs)
          .toInt(),
    );
    final timeout = Duration(
      seconds: node
          .intSetting(
            WorkflowSettingKeys.codeExecutionTimeoutSeconds,
            defaultWorkflowCodeTimeoutSeconds,
          )
          .clamp(minWorkflowCodeTimeoutSeconds, maxWorkflowCodeTimeoutSeconds),
    );
    final stopwatch = Stopwatch()..start();
    WorkflowNodeExecutionException? latestError;
    var latestErrorType = 'WorkflowCodeExecutionException';
    var attempts = 0;
    for (var attempt = 0; attempt <= retryCount; attempt++) {
      resources.cancellation?.throwIfCancelled();
      attempts = attempt + 1;
      try {
        final result = await _codeExecutor.execute(
          runtime: runtime,
          code: node.stringSetting(WorkflowSettingKeys.code),
          inputs: inputs,
          timeout: timeout,
          cancelSignal: resources.cancellation?.whenCancelled,
        );
        resources.cancellation?.throwIfCancelled();
        final output = WorkflowStructuredOutputParser.resolveValues(
          outputFields,
          result.output,
          label: '代码输出参数',
          defaultVariables: variables,
        );
        return WorkflowNodeExecutionResult(
          output: output,
          resolvedInputs: inputs,
          rawOutput: jsonEncode(output),
          attempts: attempts,
          duration: stopwatch.elapsed,
          selectedBranchId: errorStrategy == WorkflowErrorStrategy.failBranch
              ? workflowSuccessHandleId
              : null,
        );
      } catch (error) {
        if (resources.cancellation?.isCancelled == true) {
          throw const WorkflowNodeExecutionCancelledException();
        }
        if (error is WorkflowCodeExecutionException) {
          latestErrorType = 'WorkflowCodeExecutionException';
          latestError = WorkflowNodeExecutionException(
            error.message,
            cause: error.cause ?? error,
          );
        } else if (error is WorkflowNodeExecutionException) {
          latestErrorType = 'WorkflowNodeExecutionException';
          latestError = error;
        } else {
          rethrow;
        }
      }
      if (attempt < retryCount) {
        await _waitForWorkflowRetry(retryInterval, resources.cancellation);
      }
    }

    final failure =
        latestError ?? const WorkflowNodeExecutionException('代码执行失败。');
    if (errorStrategy == WorkflowErrorStrategy.terminate) throw failure;
    if (errorStrategy == WorkflowErrorStrategy.defaultValue) {
      final defaults = node.errorDefaultValues();
      try {
        final output = WorkflowStructuredOutputParser.resolveValues(
          outputFields,
          <String, Object?>{
            for (final field in outputFields)
              field.name.trim():
                  defaults[field.id] ?? defaultWorkflowErrorValue(field.type),
          },
          label: '代码异常默认值',
        );
        return WorkflowNodeExecutionResult(
          output: output,
          resolvedInputs: inputs,
          rawOutput: jsonEncode(output),
          attempts: attempts,
          duration: stopwatch.elapsed,
          recoveredFromError: true,
        );
      } on WorkflowNodeExecutionException catch (error) {
        throw WorkflowNodeExecutionException(
          '代码异常默认值无效：${error.message}',
          cause: error,
        );
      }
    }
    final output = <String, Object?>{
      node.systemOutputName(workflowErrorTypeOutputName): latestErrorType,
      node.systemOutputName(workflowErrorMessageOutputName): failure.message,
    };
    return WorkflowNodeExecutionResult(
      output: Map<String, Object?>.unmodifiable(output),
      resolvedInputs: inputs,
      rawOutput: jsonEncode(output),
      attempts: attempts,
      duration: stopwatch.elapsed,
      selectedBranchId: workflowFailureHandleId,
      recoveredFromError: true,
    );
  }

  Future<WorkflowNodeExecutionResult> _executeLlm(
    WorkflowNode node,
    WorkflowExecutionResources resources,
    Map<String, Object?> variables,
  ) async {
    resources.cancellation?.throwIfCancelled();
    _refreshProxyAwareChatClient();
    final modelConfigId = node
        .stringSetting(WorkflowSettingKeys.modelConfigId)
        .trim();
    final provider = resources.models
        .where((item) => item.id == modelConfigId)
        .firstOrNull;
    if (provider == null) {
      throw const WorkflowNodeExecutionException('请选择可用模型。');
    }
    final storedModelId = node
        .stringSetting(WorkflowSettingKeys.modelId)
        .trim();
    final modelId = storedModelId.isEmpty ? provider.modelId : storedModelId;
    if (modelId.isEmpty || !provider.allModelIds.contains(modelId)) {
      throw const WorkflowNodeExecutionException('所选模型已不可用，请重新选择。');
    }
    var model = provider.copyWith(modelId: modelId);
    final reasoningEffort = node
        .stringSetting(WorkflowSettingKeys.reasoningEffort)
        .trim();
    if (reasoningEffort.isNotEmpty) {
      final supported =
          model.resolvedReasoningEffortControlEnabled &&
          model.resolvedReasoningEffortOptions.any(
            (option) =>
                option.isSelectable &&
                option.value.toLowerCase() == reasoningEffort.toLowerCase(),
          );
      if (!supported) {
        throw const WorkflowNodeExecutionException('所选模型不支持当前推理强度。');
      }
      final profiles = Map<String, AiModelProfile>.from(model.modelProfiles);
      profiles[modelId] = (profiles[modelId] ?? const AiModelProfile())
          .copyWith(
            reasoningEffortControlEnabled: true,
            reasoningEffort: reasoningEffort,
          );
      model = model.copyWith(modelProfiles: profiles);
    }
    final prompt = renderWorkflowTemplate(
      node.stringSetting(WorkflowSettingKeys.prompt),
      variables,
    ).trim();
    if (prompt.isEmpty) {
      throw const WorkflowNodeExecutionException('提示词不能为空。');
    }
    final inputContent = renderWorkflowTemplate(
      node.stringSetting(WorkflowSettingKeys.inputContent),
      variables,
    ).trim();
    final userPrompt = inputContent.isEmpty
        ? prompt
        : '$prompt\n\n<WorkflowInput>\n$inputContent\n</WorkflowInput>';
    if (userPrompt.length > _maxWorkflowPromptCharacters) {
      throw const WorkflowNodeExecutionException('提示词与输入内容超过长度上限。');
    }

    final templateId = node
        .stringSetting(WorkflowSettingKeys.templateId)
        .trim();
    final bundle = await _awaitWorkflowOperation(
      resources.cancellation,
      () => resources.templateRepository.loadBundle(
        templateId.isEmpty ? 'default' : templateId,
      ),
    );
    final resourcePrompt = await _awaitWorkflowOperation(
      resources.cancellation,
      () => _buildResourcePrompt(
        node: node,
        resources: resources,
        query: userPrompt,
      ),
    );
    final outputFields = node.outputFields();
    final structured = node.boolSetting(WorkflowSettingKeys.structuredOutput);
    final responseFields = node.llmResponseFields();
    if (structured) {
      WorkflowStructuredOutputParser.validateFields(
        outputFields,
        label: 'LLM 输出参数',
      );
    }
    final reasoningFormat = WorkflowLlmReasoningFormat.fromStorage(
      node.settings[WorkflowSettingKeys.reasoningFormat],
    );
    final errorStrategy = WorkflowErrorStrategy.fromStorage(
      node.settings[WorkflowSettingKeys.errorStrategy],
    );
    final systemPrompt = <String>[
      bundle.systemInstructions.trim(),
      bundle.developerInstructions.trim(),
      resourcePrompt,
      if (structured)
        WorkflowStructuredOutputParser.schemaPrompt(
          outputFields,
          variables: variables,
        ),
    ].where((part) => part.isNotEmpty).join('\n\n');
    final mcpBindings = _resolveMcpBindings(node, resources);

    final retries = node.retryEnabled()
        ? node
              .intSetting(
                WorkflowSettingKeys.retryCount,
                defaultWorkflowLlmRetryCount,
              )
              .clamp(minWorkflowLlmRetryCount, maxWorkflowLlmRetryCount)
        : 0;
    final interval = Duration(
      milliseconds: node
          .intSetting(
            WorkflowSettingKeys.retryIntervalMs,
            defaultWorkflowLlmRetryIntervalMs,
          )
          .clamp(minWorkflowLlmRetryIntervalMs, maxWorkflowLlmRetryIntervalMs),
    );
    final startedAt = DateTime.now().toUtc();
    final conversationId = startedAt.microsecondsSinceEpoch;
    final stopwatch = Stopwatch()..start();
    var attempts = 0;
    Object? lastError;
    var lastMessages = const <WorkflowLlmConversationMessage>[];
    while (attempts <= retries) {
      resources.cancellation?.throwIfCancelled();
      attempts += 1;
      final messages = <WorkflowLlmConversationMessage>[
        WorkflowLlmConversationMessage(
          id: '$conversationId-${node.id}-$attempts-user',
          kind: WorkflowLlmMessageKind.user,
          content: userPrompt,
          createdAt: DateTime.now().toUtc(),
        ),
      ];
      lastMessages = messages;
      WorkflowLlmConversation snapshot(
        WorkflowLlmConversationStatus status, {
        DateTime? endedAt,
        String? error,
      }) {
        return WorkflowLlmConversation(
          nodeId: node.id,
          modelConfigId: modelConfigId,
          modelId: modelId,
          modelLabel: provider.providerLabel,
          startedAt: startedAt,
          endedAt: endedAt,
          duration: stopwatch.elapsed,
          attempts: attempts,
          status: status,
          messages: List<WorkflowLlmConversationMessage>.unmodifiable(messages),
          error: error,
        );
      }

      void publishRunning() => resources.onLlmConversation?.call(
        snapshot(WorkflowLlmConversationStatus.running),
      );

      publishRunning();
      try {
        final completion = await _sendLlmWithTools(
          model: model,
          systemPrompt: systemPrompt,
          prompt: userPrompt,
          bindings: mcpBindings,
          invoker: resources.mcpToolInvoker,
          conversationMessages: messages,
          reasoningFormat: reasoningFormat,
          onConversationChanged: publishRunning,
          cancellation: resources.cancellation,
        );
        resources.cancellation?.throwIfCancelled();
        final raw = completion.reply.trim();
        if (raw.isEmpty) {
          throw const WorkflowNodeExecutionException('模型返回内容为空。');
        }
        final separated = _separateLlmReasoning(raw, reasoningFormat);
        final reasoning = <String>[
          completion.reasoningContent?.trim() ?? '',
          separated.reasoning,
        ].where((item) => item.isNotEmpty).toSet().join('\n\n');
        final output = structured
            ? WorkflowStructuredOutputParser.parse(
                separated.text,
                outputFields,
                variables: variables,
              )
            : <String, Object?>{
                node.systemOutputName(workflowLlmTextOutputName):
                    separated.text,
                node.systemOutputName(workflowLlmReasoningOutputName):
                    reasoning,
                node.systemOutputName(workflowLlmUsageOutputName):
                    completion.usage?.toJson() ?? <String, Object?>{},
              };
        stopwatch.stop();
        final endedAt = DateTime.now().toUtc();
        final conversation = snapshot(
          WorkflowLlmConversationStatus.succeeded,
          endedAt: endedAt,
        );
        resources.onLlmConversation?.call(conversation);
        return WorkflowNodeExecutionResult(
          output: output,
          rawOutput: raw,
          attempts: attempts,
          duration: stopwatch.elapsed,
          conversation: conversation,
          selectedBranchId: errorStrategy == WorkflowErrorStrategy.failBranch
              ? workflowSuccessHandleId
              : null,
        );
      } catch (error) {
        if (resources.cancellation?.isCancelled == true) {
          throw const WorkflowNodeExecutionCancelledException();
        }
        lastError = error;
        if (attempts > retries) break;
        await _waitForWorkflowRetry(interval, resources.cancellation);
      }
    }
    stopwatch.stop();
    final message = 'LLM 节点执行失败：${_executionErrorText(lastError)}';
    final failedConversation = WorkflowLlmConversation(
      nodeId: node.id,
      modelConfigId: modelConfigId,
      modelId: modelId,
      modelLabel: provider.providerLabel,
      startedAt: startedAt,
      endedAt: DateTime.now().toUtc(),
      duration: stopwatch.elapsed,
      attempts: attempts,
      status: WorkflowLlmConversationStatus.failed,
      messages: List<WorkflowLlmConversationMessage>.unmodifiable(lastMessages),
      error: message,
    );
    resources.onLlmConversation?.call(failedConversation);
    final failure = WorkflowNodeExecutionException(message, cause: lastError);
    if (errorStrategy == WorkflowErrorStrategy.terminate) throw failure;
    if (errorStrategy == WorkflowErrorStrategy.defaultValue) {
      try {
        final defaults = node.errorDefaultValues();
        final output = WorkflowStructuredOutputParser.resolveValues(
          responseFields,
          <String, Object?>{
            for (final field in responseFields)
              field.name.trim():
                  defaults[field.id] ?? defaultWorkflowErrorValue(field.type),
          },
          label: 'LLM 异常默认值',
        );
        return WorkflowNodeExecutionResult(
          output: output,
          rawOutput: jsonEncode(output),
          attempts: attempts,
          duration: stopwatch.elapsed,
          conversation: failedConversation,
          recoveredFromError: true,
        );
      } on WorkflowNodeExecutionException catch (error) {
        throw WorkflowNodeExecutionException(
          'LLM 异常默认值无效：${error.message}',
          cause: error,
        );
      }
    }
    final output = <String, Object?>{
      node.systemOutputName(workflowErrorTypeOutputName): _llmErrorType(
        lastError,
      ),
      node.systemOutputName(workflowErrorMessageOutputName): failure.message,
    };
    return WorkflowNodeExecutionResult(
      output: Map<String, Object?>.unmodifiable(output),
      rawOutput: jsonEncode(output),
      attempts: attempts,
      duration: stopwatch.elapsed,
      conversation: failedConversation,
      selectedBranchId: workflowFailureHandleId,
      recoveredFromError: true,
    );
  }

  Future<AiChatCompletion> _sendLlmWithTools({
    required AiModelConfig model,
    required String systemPrompt,
    required String prompt,
    required List<_WorkflowMcpBinding> bindings,
    required WorkflowMcpToolInvoker? invoker,
    required List<WorkflowLlmConversationMessage> conversationMessages,
    required WorkflowLlmReasoningFormat reasoningFormat,
    required void Function() onConversationChanged,
    required WorkflowExecutionCancellationToken? cancellation,
  }) async {
    final messages = <AiChatTurn>[
      AiChatTurn(role: AiChatRole.system, content: systemPrompt),
      AiChatTurn(role: AiChatRole.user, content: prompt),
    ];
    final tools = bindings
        .map(
          (binding) => AiToolDefinition(
            name: binding.callName,
            description: binding.tool.description.trim().isEmpty
                ? '调用 ${binding.server.name} 的 ${binding.tool.name} 工具。'
                : binding.tool.description.trim(),
            parameters: binding.tool.inputSchema,
          ),
        )
        .toList(growable: false);
    final bindingsByName = <String, _WorkflowMcpBinding>{
      for (final binding in bindings) binding.callName: binding,
    };
    var totalToolCalls = 0;
    for (var round = 0; round <= _maxWorkflowToolRounds; round++) {
      cancellation?.throwIfCancelled();
      final completion = await _chatClient.sendMessage(
        model: model,
        messages: messages,
        tools: tools,
        timeout: const Duration(seconds: 120),
        cancelSignal: cancellation?.whenCancelled,
      );
      cancellation?.throwIfCancelled();
      _appendLlmCompletionMessages(
        conversationMessages,
        completion,
        reasoningFormat,
      );
      onConversationChanged();
      if (completion.toolCalls.isEmpty) return completion;
      if (invoker == null || bindings.isEmpty) {
        throw const WorkflowNodeExecutionException('MCP 工具执行器不可用。');
      }
      if (round == _maxWorkflowToolRounds) {
        throw const WorkflowNodeExecutionException('MCP 工具调用超过轮次上限。');
      }
      totalToolCalls += completion.toolCalls.length;
      if (totalToolCalls > _maxWorkflowToolCalls) {
        throw const WorkflowNodeExecutionException('MCP 工具调用数量超过上限。');
      }
      messages.add(
        AiChatTurn(
          role: AiChatRole.assistant,
          content: completion.reply,
          toolCalls: completion.toolCalls,
          reasoningContent: completion.reasoningContent,
        ),
      );
      for (final call in completion.toolCalls) {
        final binding = bindingsByName[call.name];
        if (binding == null) {
          throw WorkflowNodeExecutionException('模型请求了未授权工具：${call.name}');
        }
        final arguments = _decodeToolArguments(call.arguments, call.name);
        final result = await _awaitWorkflowOperation(
          cancellation,
          () =>
              invoker(
                serverName: binding.server.name,
                toolName: binding.tool.id,
                arguments: arguments,
                toolCallId: call.id,
                cancelSignal: cancellation?.whenCancelled,
              ).timeout(
                const Duration(seconds: 120),
                onTimeout: () => throw TimeoutException('MCP 工具调用超时。'),
              ),
        );
        final output = _boundedToolOutput(result.output);
        messages.add(
          AiChatTurn(
            role: AiChatRole.tool,
            toolCallId: call.id,
            content: result.isError ? '工具执行失败：$output' : output,
          ),
        );
        final createdAt = DateTime.now().toUtc();
        conversationMessages.add(
          WorkflowLlmConversationMessage(
            id: '${createdAt.microsecondsSinceEpoch}-tool-result-${call.id}',
            kind: WorkflowLlmMessageKind.toolResult,
            content: output,
            createdAt: createdAt,
            toolName: call.name,
            toolCallId: call.id,
            isError: result.isError,
          ),
        );
        onConversationChanged();
      }
    }
    throw const WorkflowNodeExecutionException('LLM 工具调用未能完成。');
  }

  void _appendLlmCompletionMessages(
    List<WorkflowLlmConversationMessage> messages,
    AiChatCompletion completion,
    WorkflowLlmReasoningFormat reasoningFormat,
  ) {
    void add(
      WorkflowLlmMessageKind kind,
      String? content, {
      String? toolName,
      String? toolCallId,
    }) {
      final text = content?.trim() ?? '';
      if (text.isEmpty) return;
      final createdAt = DateTime.now().toUtc();
      messages.add(
        WorkflowLlmConversationMessage(
          id: '${createdAt.microsecondsSinceEpoch}-${kind.name}-${toolCallId ?? ''}',
          kind: kind,
          content: text,
          createdAt: createdAt,
          toolName: toolName,
          toolCallId: toolCallId,
        ),
      );
    }

    final separated = _separateLlmReasoning(completion.reply, reasoningFormat);
    final reasoning = <String>{
      completion.reasoningContent?.trim() ?? '',
      separated.reasoning,
    }..remove('');
    for (final content in reasoning) {
      add(WorkflowLlmMessageKind.reasoning, content);
    }
    add(WorkflowLlmMessageKind.assistant, separated.text);
    for (final call in completion.toolCalls) {
      add(
        WorkflowLlmMessageKind.toolCall,
        _boundedToolOutput(call.arguments),
        toolName: call.name,
        toolCallId: call.id,
      );
    }
  }

  List<_WorkflowMcpBinding> _resolveMcpBindings(
    WorkflowNode node,
    WorkflowExecutionResources resources,
  ) {
    final selectedNames = node.stringSetSetting(
      WorkflowSettingKeys.mcpServerNames,
    );
    if (selectedNames.isEmpty) return const <_WorkflowMcpBinding>[];
    final bindings = <_WorkflowMcpBinding>[];
    final usedNames = <String>{};
    for (final server in resources.mcpServers) {
      if (!server.enabled || !selectedNames.contains(server.name)) continue;
      for (final tool in resources.mcpTools[server.name] ?? const <McpTool>[]) {
        if (bindings.length >= _maxWorkflowMcpTools) {
          return List<_WorkflowMcpBinding>.unmodifiable(bindings);
        }
        bindings.add(
          _WorkflowMcpBinding(
            callName: _workflowMcpToolName(server.name, tool.id, usedNames),
            server: server,
            tool: tool,
          ),
        );
      }
    }
    return List<_WorkflowMcpBinding>.unmodifiable(bindings);
  }

  Future<String> _buildResourcePrompt({
    required WorkflowNode node,
    required WorkflowExecutionResources resources,
    required String query,
  }) async {
    resources.cancellation?.throwIfCancelled();
    final sections = <String>[];
    final skillNames = node.stringSetSetting(WorkflowSettingKeys.skillNames);
    final skills = resources.skills.where(
      (item) => skillNames.contains(item.name),
    );
    if (skills.isNotEmpty) {
      sections.add(
        '<WorkflowSkills>\n${skills.map((skill) {
          final guidance = skill.defaultPrompt?.trim();
          return '- ${skill.name}: ${guidance?.isNotEmpty == true ? guidance : skill.description.trim()}';
        }).join('\n')}\n</WorkflowSkills>',
      );
    }

    final memoryIds = node.stringSetSetting(WorkflowSettingKeys.memoryIds);
    final memories = resources.memories.where(
      (item) => memoryIds.contains(item.id),
    );
    if (memories.isNotEmpty) {
      sections.add(
        '<WorkflowMemory>\n${memories.map((item) => item.content.trim()).join('\n\n')}\n</WorkflowMemory>',
      );
    }

    final instructionIds = node.stringSetSetting(
      WorkflowSettingKeys.instructionIds,
    );
    final instructions = resources.instructions.where(
      (item) => item.enabled && instructionIds.contains(item.id),
    );
    if (instructions.isNotEmpty) {
      sections.add(
        '<WorkflowInstructions>\n${instructions.map((item) => item.body.trim()).join('\n\n')}\n</WorkflowInstructions>',
      );
    }

    final mcpNames = node.stringSetSetting(WorkflowSettingKeys.mcpServerNames);
    final mcpServers = resources.mcpServers.where(
      (item) => item.enabled && mcpNames.contains(item.name),
    );
    if (mcpServers.isNotEmpty) {
      sections.add(
        '<WorkflowMcpScope>\n${mcpServers.map((server) {
          final tools = resources.mcpTools[server.name] ?? const <McpTool>[];
          final suffix = tools.isEmpty ? '' : '；工具：${tools.take(24).map((tool) => tool.name).join('、')}';
          return '- ${server.name}（${server.type.transportValue}）$suffix';
        }).join('\n')}\n</WorkflowMcpScope>',
      );
    }

    final capabilityNames = node.stringSetSetting(
      WorkflowSettingKeys.multimodalCapabilities,
    );
    if (capabilityNames.isNotEmpty) {
      sections.add(
        '<WorkflowMultimodalCapabilities>${capabilityNames.join(', ')}</WorkflowMultimodalCapabilities>',
      );
    }

    final knowledgeIds = node.stringSetSetting(
      WorkflowSettingKeys.knowledgeSourceIds,
    );
    final knowledge = resources.knowledgeBaseController;
    if (knowledge != null && knowledgeIds.isNotEmpty) {
      try {
        final retrieved = await _awaitWorkflowOperation(
          resources.cancellation,
          () => knowledge.retrieveForTool(
            query: query,
            topK: 20,
            models: resources.models,
          ),
        );
        resources.cancellation?.throwIfCancelled();
        if (retrieved != null) {
          final hits = retrieved.result.hits
              .where((hit) => knowledgeIds.contains(hit.source.id))
              .take(12)
              .toList(growable: false);
          final context = _knowledgePrompt(hits);
          if (context.isNotEmpty) sections.add(context);
        }
      } catch (_) {
        if (resources.cancellation?.isCancelled == true) {
          throw const WorkflowNodeExecutionCancelledException();
        }
        throw const WorkflowNodeExecutionException('检索所选知识库失败。');
      }
    }
    final joined = sections.join('\n\n');
    if (joined.length <= _maxWorkflowResourceCharacters) return joined;
    return joined.substring(0, _maxWorkflowResourceCharacters);
  }

  String _knowledgePrompt(List<KnowledgeRetrievalHit> hits) {
    if (hits.isEmpty) return '';
    final buffer = StringBuffer()
      ..writeln('<WorkflowKnowledge>')
      ..writeln('仅在相关时使用以下本地知识，不得虚构引用。');
    for (var index = 0; index < hits.length; index++) {
      final hit = hits[index];
      buffer
        ..writeln('[KB-${index + 1}] ${hit.source.title}')
        ..writeln(hit.chunk.content.trim())
        ..writeln();
    }
    buffer.write('</WorkflowKnowledge>');
    return buffer.toString();
  }

  Future<WorkflowNodeExecutionResult> _executeHttp(
    WorkflowNode node,
    WorkflowExecutionResources resources,
    Map<String, Object?> variables,
  ) async {
    resources.cancellation?.throwIfCancelled();
    final rawUrl = renderWorkflowTemplate(
      node.stringSetting(WorkflowSettingKeys.url),
      variables,
    ).trim();
    final parsedUrl = Uri.tryParse(rawUrl);
    if (parsedUrl == null ||
        !parsedUrl.hasScheme ||
        !const <String>{'http', 'https'}.contains(parsedUrl.scheme) ||
        parsedUrl.host.isEmpty) {
      throw const WorkflowNodeExecutionException('请输入有效的 HTTP 或 HTTPS 地址。');
    }
    final params = <String, String>{
      ...parsedUrl.queryParameters,
      ..._resolvedKeyValues(
        node.keyValueSetting(WorkflowSettingKeys.queryParameters),
        variables,
        label: '请求参数',
      ),
    };
    final headers = _resolvedKeyValues(
      node.keyValueSetting(WorkflowSettingKeys.headers),
      variables,
      label: '请求头',
      httpHeaders: true,
    );
    final uri = parsedUrl.replace(
      queryParameters: params.isEmpty ? null : params,
    );
    final method = node
        .stringSetting(WorkflowSettingKeys.method, 'GET')
        .trim()
        .toUpperCase();
    if (!kStandardHttpMethods.contains(method)) {
      throw const WorkflowNodeExecutionException('HTTP 请求方式无效。');
    }
    final structured = node.boolSetting(WorkflowSettingKeys.structuredOutput);
    final responseFields = node.httpResponseFields();
    if (structured) {
      WorkflowStructuredOutputParser.validateFields(
        responseFields,
        label: 'HTTP 输出参数',
      );
    }
    final errorStrategy = WorkflowErrorStrategy.fromStorage(
      node.settings[WorkflowSettingKeys.errorStrategy],
    );
    final requestBody = kWorkflowHttpMethodsWithoutBody.contains(method)
        ? null
        : _prepareHttpRequestBody(node, variables);
    final retries = node.retryEnabled()
        ? node
              .intSetting(
                WorkflowSettingKeys.retryCount,
                defaultWorkflowHttpRetryCount,
              )
              .clamp(minWorkflowHttpRetryCount, maxWorkflowHttpRetryCount)
        : 0;
    final interval = Duration(
      milliseconds: node
          .intSetting(
            WorkflowSettingKeys.retryIntervalMs,
            defaultWorkflowHttpRetryIntervalMs,
          )
          .clamp(
            minWorkflowHttpRetryIntervalMs,
            maxWorkflowHttpRetryIntervalMs,
          ),
    );
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    var lastErrorType = 'HTTPExecutionError';
    var attempts = 0;
    while (attempts <= retries) {
      resources.cancellation?.throwIfCancelled();
      attempts += 1;
      try {
        final response = await _sendHttpRequest(
          node: node,
          method: method,
          uri: uri,
          headers: headers,
          requestBody: requestBody,
          cancellation: resources.cancellation,
        );
        resources.cancellation?.throwIfCancelled();
        final output = structured
            ? await _resolveHttpResponseFields(
                response: response,
                fields: responseFields,
                resources: resources,
                variables: variables,
              )
            : <String, Object?>{
                node.systemOutputName(workflowHttpBodyOutputName):
                    response.body,
                node.systemOutputName(workflowHttpStatusCodeOutputName):
                    response.statusCode,
                node.systemOutputName(workflowHttpHeadersOutputName):
                    response.headers,
                node.systemOutputName(workflowHttpFilesOutputName):
                    response.files,
              };
        stopwatch.stop();
        return WorkflowNodeExecutionResult(
          output: output,
          rawOutput: response.body,
          attempts: attempts,
          duration: stopwatch.elapsed,
          selectedBranchId: errorStrategy == WorkflowErrorStrategy.failBranch
              ? workflowSuccessHandleId
              : null,
        );
      } catch (error) {
        if (resources.cancellation?.isCancelled == true) {
          throw const WorkflowNodeExecutionCancelledException();
        }
        if (error is! WorkflowNodeExecutionException &&
            error is! TimeoutException &&
            error is! IOException) {
          rethrow;
        }
        lastError = error;
        lastErrorType = _httpErrorType(error);
        if (attempts > retries) break;
        await _waitForWorkflowRetry(interval, resources.cancellation);
      }
    }
    stopwatch.stop();
    final failure = WorkflowNodeExecutionException(
      'HTTP 节点执行失败：${_executionErrorText(lastError)}',
      cause: lastError,
    );
    if (errorStrategy == WorkflowErrorStrategy.terminate) throw failure;
    if (errorStrategy == WorkflowErrorStrategy.defaultValue) {
      try {
        final defaults = node.errorDefaultValues();
        final output = WorkflowStructuredOutputParser.resolveValues(
          responseFields,
          <String, Object?>{
            for (final field in responseFields)
              field.name.trim():
                  defaults[field.id] ?? defaultWorkflowErrorValue(field.type),
          },
          label: 'HTTP 异常默认值',
        );
        return WorkflowNodeExecutionResult(
          output: output,
          rawOutput: jsonEncode(output),
          attempts: attempts,
          duration: stopwatch.elapsed,
          recoveredFromError: true,
        );
      } on WorkflowNodeExecutionException catch (error) {
        throw WorkflowNodeExecutionException(
          'HTTP 异常默认值无效：${error.message}',
          cause: error,
        );
      }
    }
    final output = <String, Object?>{
      node.systemOutputName(workflowErrorTypeOutputName): lastErrorType,
      node.systemOutputName(workflowErrorMessageOutputName): failure.message,
    };
    return WorkflowNodeExecutionResult(
      output: Map<String, Object?>.unmodifiable(output),
      rawOutput: jsonEncode(output),
      attempts: attempts,
      duration: stopwatch.elapsed,
      selectedBranchId: workflowFailureHandleId,
      recoveredFromError: true,
    );
  }

  Future<_WorkflowHttpResponse> _sendHttpRequest({
    required WorkflowNode node,
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required _WorkflowHttpRequestBody? requestBody,
    required WorkflowExecutionCancellationToken? cancellation,
  }) async {
    final connectSeconds = node
        .intSetting(
          WorkflowSettingKeys.connectTimeoutSeconds,
          defaultWorkflowHttpConnectTimeoutSeconds,
        )
        .clamp(
          minWorkflowHttpTimeoutSeconds,
          maxWorkflowHttpConnectTimeoutSeconds,
        );
    final responseSeconds = node
        .intSetting(
          WorkflowSettingKeys.responseTimeoutSeconds,
          defaultWorkflowHttpReadTimeoutSeconds,
        )
        .clamp(
          minWorkflowHttpTimeoutSeconds,
          maxWorkflowHttpReadTimeoutSeconds,
        );
    final writeSeconds = node
        .intSetting(
          WorkflowSettingKeys.writeTimeoutSeconds,
          defaultWorkflowHttpWriteTimeoutSeconds,
        )
        .clamp(
          minWorkflowHttpTimeoutSeconds,
          maxWorkflowHttpWriteTimeoutSeconds,
        );
    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: Duration(seconds: connectSeconds),
      userAgent: 'OpenHand-Workflow/1.0',
    );
    if (!node.boolSetting(WorkflowSettingKeys.verifySsl, true)) {
      client.badCertificateCallback = (_, _, _) => true;
    }
    HttpClientRequest? activeRequest;
    void abortRequest() {
      final request = activeRequest;
      if (request != null) {
        abortHttpClientRequest(
          request,
          reason: const WorkflowNodeExecutionCancelledException(),
        );
      }
      client.close(force: true);
    }

    if (cancellation != null) {
      unawaited(cancellation.whenCancelled.then<void>((_) => abortRequest()));
    }
    try {
      cancellation?.throwIfCancelled();
      final request = await openHttpClientRequestBounded(
        () => client.openUrl(method, uri),
        timeout: Duration(seconds: connectSeconds),
        timeoutMessage: 'HTTP 连接超时。',
      );
      activeRequest = request;
      cancellation?.throwIfCancelled();
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (requestBody != null) {
        if (requestBody.forceContentType) {
          request.headers.contentType = requestBody.contentType;
        } else {
          request.headers.contentType ??= requestBody.contentType;
        }
        request.add(requestBody.bytes);
        await request.flush().timeout(
          Duration(seconds: writeSeconds),
          onTimeout: () {
            request.abort(TimeoutException('HTTP 请求体写入超时。'));
            throw TimeoutException('HTTP 请求体写入超时。');
          },
        );
        cancellation?.throwIfCancelled();
      }
      final responseTimeout = Duration(seconds: responseSeconds);
      final responseDeadline = MonotonicDeadline(
        responseTimeout,
        timeoutMessage: 'HTTP 响应超过总时限。',
      );
      late final HttpClientResponse response;
      late final Uint8List responseBytes;
      try {
        response = await closeHttpClientRequestBounded(
          request,
          timeout: responseDeadline.remaining(),
        );
        cancellation?.throwIfCancelled();
        final remaining = responseDeadline.remaining();
        responseBytes = await readBoundedHttpResponseBytes(
          response,
          maxBytes: _maxWorkflowHttpResponseBytes,
          idleTimeout: remaining < responseTimeout
              ? remaining
              : responseTimeout,
          totalTimeout: remaining,
        );
      } on ByteStreamSizeLimitException {
        throw const WorkflowNodeExecutionException('HTTP 响应超过 4 MiB 上限。');
      } finally {
        responseDeadline.stop();
      }
      cancellation?.throwIfCancelled();
      final body = utf8.decode(responseBytes, allowMalformed: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final preview = body.length > 500 ? '${body.substring(0, 500)}…' : body;
        throw WorkflowNodeExecutionException(
          'HTTP ${response.statusCode}${preview.trim().isEmpty ? '' : '：$preview'}',
        );
      }
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });
      return _WorkflowHttpResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        body: body,
        files: _httpResponseFiles(response, responseBytes, uri),
      );
    } finally {
      client.close(force: true);
    }
  }

  _WorkflowHttpRequestBody? _prepareHttpRequestBody(
    WorkflowNode node,
    Map<String, Object?> variables,
  ) {
    final format = WorkflowHttpBodyFormat.fromStorage(
      node.settings[WorkflowSettingKeys.bodyFormat],
    );
    final body = renderWorkflowTemplate(
      node.stringSetting(WorkflowSettingKeys.body),
      variables,
    );
    Never bodyTooLarge() => throw const WorkflowNodeExecutionException(
      _workflowHttpRequestTooLargeMessage,
    );

    List<int> encodeText(String value) {
      if (value.length > _maxWorkflowHttpRequestBytes) bodyTooLarge();
      final bytes = utf8.encode(value);
      if (bytes.length > _maxWorkflowHttpRequestBytes) bodyTooLarge();
      return bytes;
    }

    _WorkflowHttpRequestBody prepared(
      List<int> bytes,
      ContentType contentType, {
      bool forceContentType = false,
    }) {
      if (bytes.length > _maxWorkflowHttpRequestBytes) bodyTooLarge();
      return _WorkflowHttpRequestBody(
        bytes: bytes,
        contentType: contentType,
        forceContentType: forceContentType,
      );
    }

    switch (format) {
      case WorkflowHttpBodyFormat.none:
        return null;
      case WorkflowHttpBodyFormat.json:
        if (body.length > _maxWorkflowHttpRequestBytes) bodyTooLarge();
        try {
          return prepared(
            encodeText(jsonEncode(jsonDecode(body))),
            ContentType.json,
          );
        } on FormatException {
          throw const WorkflowNodeExecutionException('请求体不是有效 JSON。');
        }
      case WorkflowHttpBodyFormat.text:
        return prepared(encodeText(body), ContentType.text);
      case WorkflowHttpBodyFormat.formUrlEncoded:
        final values = _bodyEntries(node, variables);
        return prepared(
          encodeText(Uri(queryParameters: values).query),
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8'),
        );
      case WorkflowHttpBodyFormat.formData:
        final boundary = 'openhand-${DateTime.now().microsecondsSinceEpoch}';
        final buffer = StringBuffer();
        for (final entry in _bodyEntries(node, variables).entries) {
          buffer
            ..write('--$boundary\r\n')
            ..write(
              'Content-Disposition: form-data; name="${_escapeMultipartName(entry.key)}"\r\n\r\n',
            )
            ..write(entry.value)
            ..write('\r\n');
        }
        buffer.write('--$boundary--\r\n');
        return prepared(
          encodeText(buffer.toString()),
          ContentType(
            'multipart',
            'form-data',
            parameters: <String, String>{'boundary': boundary},
          ),
          forceContentType: true,
        );
      case WorkflowHttpBodyFormat.binary:
        return prepared(_binaryHttpBody(node, variables), ContentType.binary);
    }
  }

  List<int> _binaryHttpBody(WorkflowNode node, Map<String, Object?> variables) {
    final source = node.stringSetting(WorkflowSettingKeys.body);
    final resolved = resolveWorkflowTemplateValue(source, variables);
    if (resolved is Uint8List) {
      if (resolved.length > _maxWorkflowHttpRequestBytes) {
        throw const WorkflowNodeExecutionException(
          _workflowHttpRequestTooLargeMessage,
        );
      }
      return Uint8List.fromList(resolved);
    }
    if (resolved is List) {
      if (resolved.length > _maxWorkflowHttpRequestBytes) {
        throw const WorkflowNodeExecutionException(
          _workflowHttpRequestTooLargeMessage,
        );
      }
      final bytes = <int>[];
      for (final value in resolved) {
        if (value is! int || value < 0 || value > 255) {
          throw const WorkflowNodeExecutionException('二进制请求体的字节数组无效。');
        }
        bytes.add(value);
      }
      return bytes;
    }
    final text = '$resolved';
    final trimmed = text.trim();
    final dataUrl = _workflowBase64DataUrlPattern.firstMatch(trimmed);
    final encoded =
        dataUrl?.group(1) ??
        (trimmed.startsWith('base64:')
            ? trimmed.substring('base64:'.length)
            : null);
    if (encoded == null) return utf8.encode(text);
    try {
      return decodeFlexibleBase64Bounded(
        encoded,
        maxDecodedBytes: _maxWorkflowHttpRequestBytes,
      );
    } on BoundedBase64SizeException {
      throw const WorkflowNodeExecutionException(
        _workflowHttpRequestTooLargeMessage,
      );
    } on BoundedBase64FormatException {
      throw const WorkflowNodeExecutionException('二进制请求体包含无效的 Base64 内容。');
    }
  }

  Map<String, String> _bodyEntries(
    WorkflowNode node,
    Map<String, Object?> variables,
  ) {
    return _resolvedKeyValues(
      node.keyValueSetting(WorkflowSettingKeys.bodyEntries),
      variables,
      label: '请求体字段',
    );
  }

  Map<String, String> _resolvedKeyValues(
    List<WorkflowKeyValueEntry> entries,
    Map<String, Object?> variables, {
    required String label,
    bool httpHeaders = false,
  }) {
    final resolved = entries
        .map(
          (entry) => WorkflowKeyValueEntry(
            id: entry.id,
            key: renderWorkflowTemplate(entry.key, variables).trim(),
            value: entry.valueSource == WorkflowValueSource.variable
                ? renderWorkflowTemplate(entry.value, variables)
                : entry.value,
            valueSource: entry.valueSource,
          ),
        )
        .toList(growable: false);
    final error = validateWorkflowKeyValueEntries(
      resolved,
      label: label,
      httpHeaders: httpHeaders,
    );
    if (error != null) throw WorkflowNodeExecutionException(error);
    return <String, String>{
      for (final entry in resolved) entry.key: entry.value,
    };
  }

  String _escapeMultipartName(String value) =>
      value.replaceAll(_workflowMultipartNameUnsafePattern, '_');

  Future<WorkflowNodeExecutionResult> _executeCondition(
    WorkflowNode node,
    Map<String, Object?> variables,
  ) async {
    final cases = node.conditionCases();
    if (cases.isNotEmpty) {
      final validationError = validateWorkflowConditionCases(cases);
      if (validationError != null) {
        throw WorkflowNodeExecutionException(validationError);
      }
      WorkflowConditionCase? matched;
      for (final item in cases) {
        if (_matchesConditions(item.conditions, item.logic, variables)) {
          matched = item;
          break;
        }
      }
      final branchId = matched?.id ?? 'else';
      final output = <String, Object?>{
        'matched': matched != null,
        'branch_id': branchId,
        'branch': matched == null
            ? 'ELSE'
            : cases.indexOf(matched) == 0
            ? 'IF'
            : 'ELIF ${cases.indexOf(matched)}',
      };
      return WorkflowNodeExecutionResult(
        output: output,
        rawOutput: jsonEncode(output),
        attempts: 1,
        duration: Duration.zero,
        selectedBranchId: branchId,
      );
    }

    final expression = renderWorkflowTemplate(
      node.stringSetting(WorkflowSettingKeys.expression),
      variables,
    ).trim();
    if (expression.isEmpty) {
      throw const WorkflowNodeExecutionException('条件表达式不能为空。');
    }
    final match = RegExp(
      r'^(.+?)\s*(==|!=|>=|<=|>|<|contains)\s*(.+)$',
    ).firstMatch(expression);
    if (match == null) {
      throw const WorkflowNodeExecutionException('条件表达式格式无效。');
    }
    final left = _literalValue(match.group(1)!.trim());
    final right = _literalValue(match.group(3)!.trim());
    final operator = match.group(2)!;
    final result = switch (operator) {
      '==' => left == right || '$left' == '$right',
      '!=' => left != right && '$left' != '$right',
      'contains' => '$left'.contains('$right'),
      '>' => _number(left) > _number(right),
      '<' => _number(left) < _number(right),
      '>=' => _number(left) >= _number(right),
      '<=' => _number(left) <= _number(right),
      _ => false,
    };
    return WorkflowNodeExecutionResult(
      output: result,
      rawOutput: '$result',
      attempts: 1,
      duration: Duration.zero,
      selectedBranchId: result ? 'legacy-if' : 'else',
    );
  }

  Future<WorkflowNodeExecutionResult> _executeHumanIntervention(
    WorkflowNode node,
    WorkflowExecutionResources resources,
    Map<String, Object?> variables,
  ) async {
    resources.cancellation?.throwIfCancelled();
    final handler = resources.onHumanIntervention;
    if (handler == null) {
      throw const WorkflowNodeExecutionException('当前执行环境不支持应用内人工介入。');
    }
    if (node.stringSetting(
          WorkflowSettingKeys.humanDeliveryMethod,
          workflowHumanDeliveryMethodInAppDialog,
        ) !=
        workflowHumanDeliveryMethodInAppDialog) {
      throw const WorkflowNodeExecutionException('人工介入节点的提交方式不受支持。');
    }
    final actions = node.humanActions();
    final actionError = validateWorkflowHumanActions(actions);
    if (actionError != null) throw WorkflowNodeExecutionException(actionError);
    final timeoutValue = node.intSetting(
      WorkflowSettingKeys.humanTimeout,
      defaultWorkflowHumanTimeout,
    );
    if (timeoutValue < 1) {
      throw const WorkflowNodeExecutionException('人工介入超时时长必须大于等于 1。');
    }
    final timeout = WorkflowHumanTimeoutUnit.fromStorage(
      node.settings[WorkflowSettingKeys.humanTimeoutUnit],
    ).duration(timeoutValue);
    final fields = node.humanInputFields();
    WorkflowStructuredOutputParser.validateFields(
      fields,
      label: '人工输入参数',
      allowEmpty: true,
    );
    if (fields.any(
      (field) => workflowHumanSystemOutputNames.contains(field.name.trim()),
    )) {
      throw const WorkflowNodeExecutionException('人工输入参数使用了系统保留名称。');
    }
    final content = renderWorkflowTemplate(
      node.stringSetting(WorkflowSettingKeys.humanPrompt),
      variables,
    ).trim();
    if (content.isEmpty) {
      throw const WorkflowNodeExecutionException('人工介入内容不能为空。');
    }
    final initialValues = <String, Object?>{};
    for (final field in fields) {
      if (field.defaultValue.trim().isEmpty) continue;
      initialValues[field.name.trim()] = _configuredValue(
        field.defaultValue,
        variables,
        valueSource: field.valueSource,
      );
    }
    final stopwatch = Stopwatch()..start();
    final response =
        await handler(
          WorkflowHumanInterventionRequest(
            nodeId: node.id,
            nodeTitle: node.title,
            content: content,
            fields: List<WorkflowOutputField>.unmodifiable(fields),
            initialValues: Map<String, Object?>.unmodifiable(initialValues),
            actions: List<WorkflowHumanAction>.unmodifiable(actions),
            timeout: timeout,
            cancelSignal: resources.cancellation?.whenCancelled,
          ),
        ).timeout(
          timeout + _humanInterventionTimeoutGrace,
          onTimeout: () => const WorkflowHumanInterventionResponse(
            actionId: workflowHumanTimeoutHandleId,
          ),
        );
    resources.cancellation?.throwIfCancelled();
    if (response.timedOut) {
      final output = <String, Object?>{
        node.systemOutputName(workflowHumanActionIdOutputName):
            workflowHumanTimeoutHandleId,
        node.systemOutputName(workflowHumanActionValueOutputName): '超时',
        node.systemOutputName(workflowHumanRenderedContentOutputName): content,
      };
      return WorkflowNodeExecutionResult(
        output: Map<String, Object?>.unmodifiable(output),
        rawOutput: jsonEncode(output),
        attempts: 1,
        duration: stopwatch.elapsed,
        selectedBranchId: workflowHumanTimeoutHandleId,
      );
    }
    final action = actions
        .where((item) => item.id == response.actionId)
        .firstOrNull;
    if (action == null) {
      throw const WorkflowNodeExecutionException('人工介入返回了无效的用户动作。');
    }
    final inputs = WorkflowStructuredOutputParser.resolveValues(
      fields,
      <String, Object?>{...variables, ...response.inputs},
      label: '人工输入参数',
    );
    final output = <String, Object?>{
      ...inputs,
      node.systemOutputName(workflowHumanActionIdOutputName): action.id,
      node.systemOutputName(workflowHumanActionValueOutputName): action.title
          .trim(),
      node.systemOutputName(workflowHumanRenderedContentOutputName): content,
    };
    return WorkflowNodeExecutionResult(
      output: Map<String, Object?>.unmodifiable(output),
      rawOutput: jsonEncode(output),
      attempts: 1,
      duration: stopwatch.elapsed,
      selectedBranchId: action.id,
    );
  }

  Future<WorkflowNodeExecutionResult> _executeListOperation(
    WorkflowNode node,
    Map<String, Object?> variables,
  ) async {
    final stopwatch = Stopwatch()..start();
    final input = node.stringSetting(WorkflowSettingKeys.listInput).trim();
    if (input.isEmpty) {
      throw const WorkflowNodeExecutionException('列表操作的数组输入不能为空。');
    }
    final resolved = resolveWorkflowTemplateValue(input, variables);
    final directValue = resolved == input && variables.containsKey(input)
        ? variables[input]
        : resolved;
    final decodedValue = directValue is String
        ? _tryDecodeList(directValue) ?? directValue
        : directValue;
    if (decodedValue is! List) {
      throw const WorkflowNodeExecutionException('列表操作的输入必须是数组。');
    }
    var items = decodedValue.cast<Object?>();

    if (node.boolSetting(WorkflowSettingKeys.listFilterEnabled)) {
      final key = node.stringSetting(WorkflowSettingKeys.listFilterKey).trim();
      final operator = WorkflowConditionOperator.fromStorage(
        node.settings[WorkflowSettingKeys.listFilterOperator],
      );
      final valueSource = WorkflowValueSource.fromStorage(
        node.settings[WorkflowSettingKeys.listFilterValueSource],
        legacyValue: node.stringSetting(WorkflowSettingKeys.listFilterValue),
      );
      final right = operator.requiresValue
          ? _configuredValue(
              node.stringSetting(WorkflowSettingKeys.listFilterValue),
              variables,
              valueSource: valueSource,
            )
          : null;
      items = items
          .where((item) {
            final selected = _listItemValue(item, key);
            if (!selected.found) {
              throw WorkflowNodeExecutionException('列表项中不存在属性“$key”。');
            }
            try {
              return _compareWorkflowValues(selected.value, operator, right);
            } on FormatException {
              throw const WorkflowNodeExecutionException('列表筛选的数值比较参数无效。');
            }
          })
          .toList(growable: true);
    }

    if (node.boolSetting(WorkflowSettingKeys.listExtractEnabled)) {
      final serialSource = node
          .stringSetting(WorkflowSettingKeys.listExtractSerial, '0')
          .trim();
      final serialValue = resolveWorkflowTemplateValue(serialSource, variables);
      final serial = serialValue is int
          ? serialValue
          : int.tryParse('$serialValue'.trim());
      if (serial == null || serial < 0 || serial >= items.length) {
        throw WorkflowNodeExecutionException(
          items.isEmpty ? '列表为空，无法按序号提取。' : '提取序号必须在 0–${items.length - 1} 之间。',
        );
      }
      items = <Object?>[items[serial]];
    }

    if (node.boolSetting(WorkflowSettingKeys.listOrderEnabled)) {
      final key = node.stringSetting(WorkflowSettingKeys.listOrderKey).trim();
      final order = WorkflowListOrder.fromStorage(
        node.settings[WorkflowSettingKeys.listOrder],
      );
      final indexed = items.indexed.toList(growable: true);
      indexed.sort((left, right) {
        final leftValue = _listItemValue(left.$2, key);
        final rightValue = _listItemValue(right.$2, key);
        if (!leftValue.found || !rightValue.found) {
          throw WorkflowNodeExecutionException('列表项中不存在排序属性“$key”。');
        }
        final compared = _compareListValues(leftValue.value, rightValue.value);
        if (compared != 0) {
          return order == WorkflowListOrder.ascending ? compared : -compared;
        }
        return left.$1.compareTo(right.$1);
      });
      items = indexed.map((item) => item.$2).toList(growable: true);
    }

    if (node.boolSetting(WorkflowSettingKeys.listLimitEnabled)) {
      final limit = node.intSetting(WorkflowSettingKeys.listLimitSize, 10);
      if (limit < 1) {
        throw const WorkflowNodeExecutionException('列表限制数量必须大于等于 1。');
      }
      if (limit < items.length) {
        items = items.take(limit).toList(growable: true);
      }
    }

    final outputFields = node.outputFields();
    if (outputFields.length != 3) {
      throw const WorkflowNodeExecutionException('列表操作必须包含三个输出参数。');
    }
    WorkflowStructuredOutputParser.validateFields(
      outputFields,
      label: '列表输出参数',
    );
    final output = <String, Object?>{
      outputFields[0].name.trim(): List<Object?>.unmodifiable(items),
      outputFields[1].name.trim(): items.firstOrNull,
      outputFields[2].name.trim(): items.lastOrNull,
    };
    String rawOutput;
    try {
      rawOutput = jsonEncode(output);
    } on JsonUnsupportedObjectError catch (error) {
      throw WorkflowNodeExecutionException('列表结果包含无法序列化的值。', cause: error);
    }
    return WorkflowNodeExecutionResult(
      output: Map<String, Object?>.unmodifiable(output),
      rawOutput: rawOutput,
      attempts: 1,
      duration: stopwatch.elapsed,
    );
  }

  Future<WorkflowNodeExecutionResult> _executeLoop(
    WorkflowNode node,
    WorkflowExecutionResources resources,
    Map<String, Object?> variables,
    List<WorkflowNode> workflowNodes,
    List<WorkflowConnection> workflowConnections,
  ) async {
    final stopwatch = Stopwatch()..start();
    final count = node
        .intSetting(WorkflowSettingKeys.maxIterations, 10)
        .clamp(1, 1000);
    final loopVariables = node.loopVariables();
    final variableError = validateWorkflowLoopVariables(loopVariables);
    if (variableError != null) {
      throw WorkflowNodeExecutionException(variableError);
    }
    final resolvedVariables = Map<String, Object?>.of(
      WorkflowStructuredOutputParser.resolveValues(
        loopVariables
            .map(
              (variable) => WorkflowOutputField(
                id: variable.id,
                name: variable.name,
                type: variable.type,
                required: true,
                defaultValue: variable.initialValue,
                valueSource: variable.valueSource,
              ),
            )
            .toList(growable: false),
        variables,
        label: '循环变量',
      ),
    );
    final breakConditions = node.loopBreakConditions();
    final conditionError = validateWorkflowConditionClauses(
      breakConditions,
      label: '退出条件',
      allowEmpty: true,
    );
    if (conditionError != null) {
      throw WorkflowNodeExecutionException(conditionError);
    }
    final conditionLogic = WorkflowConditionLogic.fromStorage(
      node.settings[WorkflowSettingKeys.loopConditionLogic],
    );
    var didBreak = false;
    var iterations = 0;
    for (var index = 0; index < count; index++) {
      resources.cancellation?.throwIfCancelled();
      late final Map<String, Object?> graphVariables;
      try {
        graphVariables = await _executeNestedGraph(
          parent: node,
          resources: resources,
          variables: <String, Object?>{
            ...variables,
            ...resolvedVariables,
            'loop_index': index,
          },
          workflowNodes: workflowNodes,
          workflowConnections: workflowConnections,
        );
      } on _WorkflowLoopExitSignal catch (signal) {
        for (final name in resolvedVariables.keys) {
          if (signal.variables.containsKey(name)) {
            resolvedVariables[name] = signal.variables[name];
          }
        }
        iterations = index + 1;
        didBreak = true;
        break;
      }
      for (final name in resolvedVariables.keys) {
        if (graphVariables.containsKey(name)) {
          resolvedVariables[name] = graphVariables[name];
        }
      }
      iterations = index + 1;
      didBreak =
          breakConditions.isNotEmpty &&
          _matchesConditions(breakConditions, conditionLogic, <String, Object?>{
            ...variables,
            ...graphVariables,
            ...resolvedVariables,
            'loop_index': index,
          });
      if (didBreak) break;
    }
    final output = <String, Object?>{
      ...resolvedVariables,
      'iterations': iterations,
      'did_break': didBreak,
    };
    return WorkflowNodeExecutionResult(
      output: output,
      rawOutput: jsonEncode(output),
      attempts: 1,
      duration: stopwatch.elapsed,
    );
  }

  Future<WorkflowNodeExecutionResult> _executeIteration(
    WorkflowNode node,
    WorkflowExecutionResources resources,
    Map<String, Object?> variables,
    List<WorkflowNode> workflowNodes,
    List<WorkflowConnection> workflowConnections,
  ) async {
    final stopwatch = Stopwatch()..start();
    final input = node.stringSetting(WorkflowSettingKeys.iterationInput).trim();
    final rendered = resolveWorkflowTemplateValue(input, variables);
    final raw = rendered == input && variables.containsKey(input)
        ? variables[input]
        : rendered;
    final items = raw is List
        ? List<Object?>.from(raw)
        : raw is String
        ? _tryDecodeList(raw)
        : null;
    if (items == null) {
      throw const WorkflowNodeExecutionException('迭代输入必须是数组。');
    }
    final outputTemplate = node
        .stringSetting(WorkflowSettingKeys.iterationOutput, '{{item}}')
        .trim();
    if (outputTemplate.isEmpty) {
      throw const WorkflowNodeExecutionException('迭代输出不能为空。');
    }
    final outputName = node
        .stringSetting(
          WorkflowSettingKeys.iterationOutputName,
          'iteration_result',
        )
        .trim();
    if (!workflowParameterNamePattern.hasMatch(outputName)) {
      throw const WorkflowNodeExecutionException('迭代输出参数名称无效。');
    }
    final parallel = node.boolSetting(WorkflowSettingKeys.iterationParallel);
    final parallelism = node.intSetting(
      WorkflowSettingKeys.iterationParallelism,
      10,
    );
    if (parallel && (parallelism < 1 || parallelism > 10)) {
      throw const WorkflowNodeExecutionException('迭代并行度必须在 1–10 之间。');
    }
    final errorMode = WorkflowIterationErrorMode.fromStorage(
      node.settings[WorkflowSettingKeys.iterationErrorMode],
    );
    final output = <Object?>[];
    final boundedItems = items.take(1000).toList(growable: false);
    Future<({bool include, Object? value})> process(int index) async {
      resources.cancellation?.throwIfCancelled();
      try {
        final graphVariables = await _executeNestedGraph(
          parent: node,
          resources: resources,
          variables: <String, Object?>{
            ...variables,
            'item': boundedItems[index],
            'index': index,
            'length': boundedItems.length,
          },
          workflowNodes: workflowNodes,
          workflowConnections: workflowConnections,
        );
        return (
          include: true,
          value: resolveWorkflowTemplateValue(outputTemplate, graphVariables),
        );
      } catch (error) {
        return switch (errorMode) {
          WorkflowIterationErrorMode.stop =>
            throw WorkflowNodeExecutionException(
              '迭代第 ${index + 1} 项处理失败：${_executionErrorText(error)}',
              cause: error,
            ),
          WorkflowIterationErrorMode.continueOnError => (
            include: true,
            value: <String, Object?>{
              'index': index,
              'error': _executionErrorText(error),
            },
          ),
          WorkflowIterationErrorMode.removeFailed => (
            include: false,
            value: null,
          ),
        };
      }
    }

    if (parallel) {
      for (
        var offset = 0;
        offset < boundedItems.length;
        offset += parallelism
      ) {
        resources.cancellation?.throwIfCancelled();
        final end = math.min(offset + parallelism, boundedItems.length);
        final batch = await Future.wait(
          <Future<({bool include, Object? value})>>[
            for (var index = offset; index < end; index++) process(index),
          ],
        );
        output.addAll(
          batch.where((item) => item.include).map((item) => item.value),
        );
      }
    } else {
      for (var index = 0; index < boundedItems.length; index++) {
        resources.cancellation?.throwIfCancelled();
        final item = await process(index);
        if (item.include) output.add(item.value);
      }
    }
    final flatten = node.boolSetting(
      WorkflowSettingKeys.iterationFlattenOutput,
      true,
    );
    final normalizedOutput = flatten && output.every((item) => item is List)
        ? output.expand((item) => item! as List).toList(growable: false)
        : output;
    final result = <String, Object?>{
      outputName: List<Object?>.unmodifiable(normalizedOutput),
    };
    return WorkflowNodeExecutionResult(
      output: Map<String, Object?>.unmodifiable(result),
      rawOutput: jsonEncode(result),
      attempts: 1,
      duration: stopwatch.elapsed,
    );
  }

  Future<Map<String, Object?>> _executeNestedGraph({
    required WorkflowNode parent,
    required WorkflowExecutionResources resources,
    required Map<String, Object?> variables,
    required List<WorkflowNode> workflowNodes,
    required List<WorkflowConnection> workflowConnections,
  }) async {
    final children = workflowNodes
        .where((node) => node.parentNodeId == parent.id)
        .toList(growable: false);
    if (children.isEmpty) {
      throw WorkflowNodeExecutionException('节点“${parent.title}”缺少内部执行节点。');
    }
    if (children.length > maxWorkflowNestedNodeCount) {
      throw const WorkflowNodeExecutionException('内部工作流节点数量超过执行上限。');
    }
    final childrenById = <String, WorkflowNode>{
      for (final child in children) child.id: child,
    };
    final internalEdges = workflowConnections
        .where(
          (edge) =>
              (edge.sourceNodeId == parent.id &&
                  edge.sourceHandleId == workflowContainerStartHandleId &&
                  childrenById.containsKey(edge.targetNodeId)) ||
              (childrenById.containsKey(edge.sourceNodeId) &&
                  childrenById.containsKey(edge.targetNodeId)),
        )
        .toList(growable: false);
    final activeNodeIds = internalEdges
        .where(
          (edge) =>
              edge.sourceNodeId == parent.id &&
              edge.sourceHandleId == workflowContainerStartHandleId,
        )
        .map((edge) => edge.targetNodeId)
        .toSet();
    if (activeNodeIds.isEmpty) {
      throw WorkflowNodeExecutionException('节点“${parent.title}”的内部起点尚未连接。');
    }
    final childEdges = internalEdges
        .where((edge) => childrenById.containsKey(edge.sourceNodeId))
        .toList(growable: false);
    final graph = analyzeWorkflowGraph(
      nodeIds: childrenById.keys,
      connections: childEdges,
      startNodeIds: activeNodeIds,
    );
    if (graph.reachableNodeIds.length != children.length) {
      throw WorkflowNodeExecutionException('节点“${parent.title}”包含未连接的内部节点。');
    }
    if (!graph.isAcyclic) {
      throw WorkflowNodeExecutionException('节点“${parent.title}”的内部工作流存在循环连线。');
    }
    final resolvedVariables = <String, Object?>{...variables};
    for (final nodeId in graph.topologicalNodeIds) {
      resources.cancellation?.throwIfCancelled();
      if (!activeNodeIds.contains(nodeId)) continue;
      final child = childrenById[nodeId];
      if (child == null) continue;
      if (child.kind == WorkflowNodeKind.loopExit) {
        resources.onNodeExecution?.call(
          WorkflowNodeExecutionEvent(
            nodeId: child.id,
            phase: WorkflowNodeExecutionPhase.running,
          ),
        );
        resources.onNodeExecution?.call(
          WorkflowNodeExecutionEvent(
            nodeId: child.id,
            phase: WorkflowNodeExecutionPhase.succeeded,
            attempts: 1,
          ),
        );
        throw _WorkflowLoopExitSignal(
          Map<String, Object?>.unmodifiable(resolvedVariables),
        );
      }
      final result = await execute(
        node: child,
        resources: resources,
        variables: resolvedVariables,
        workflowNodes: workflowNodes,
        workflowConnections: workflowConnections,
      );
      _mergeNodeOutput(child, result, resolvedVariables);
      final selectedBranch = result.selectedBranchId;
      for (final edge in childEdges) {
        if (edge.sourceNodeId != child.id) continue;
        if (selectedBranch != null && edge.sourceHandleId != selectedBranch) {
          continue;
        }
        activeNodeIds.add(edge.targetNodeId);
      }
    }
    return Map<String, Object?>.unmodifiable(resolvedVariables);
  }

  void _mergeNodeOutput(
    WorkflowNode node,
    WorkflowNodeExecutionResult result,
    Map<String, Object?> variables,
  ) {
    variables.addAll(result.resolvedInputs);
    final output = result.output;
    if (output case final Map values) {
      for (final entry in values.entries) {
        variables['${entry.key}'] = entry.value;
      }
      return;
    }
    final fields = node.declaredParameterFields();
    if (fields.length == 1) {
      variables[fields.first.name.trim()] = output;
    }
  }

  Future<Map<String, Object?>> _resolveConfiguredFieldValues({
    required List<WorkflowOutputField> fields,
    required WorkflowExecutionResources resources,
    required Map<String, Object?> variables,
    required String label,
    Map<String, Object?> initialValues = const <String, Object?>{},
    bool preferProvidedInputValues = false,
  }) async {
    WorkflowStructuredOutputParser.validateFields(
      fields,
      label: label,
      allowEmpty: true,
    );
    final values = <String, Object?>{...variables, ...initialValues};
    final preservedValues = <String, Object?>{};
    final expressions = <WorkflowCodeLanguage, Map<String, String>>{};
    final expressionVariables = <WorkflowCodeLanguage, Map<String, Object?>>{};
    var aliasIndex = 0;

    for (final field in fields) {
      final name = field.name.trim();
      final providedValue = variables[name];
      final hasProvidedValue =
          preferProvidedInputValues &&
          variables.containsKey(name) &&
          providedValue != null &&
          (providedValue is! String || providedValue.trim().isNotEmpty);
      if (hasProvidedValue) {
        values[name] = providedValue;
        continue;
      }
      final configured = field.value;
      if (configured.trim().isEmpty) continue;
      if (field.valueMode == WorkflowValueMode.literal) {
        for (final match in workflowTemplatePlaceholderPattern.allMatches(
          configured,
        )) {
          final reference = match.group(1)!;
          if (!_lookupWorkflowVariable(reference, variables).found) {
            throw WorkflowNodeExecutionException(
              '$label“$name”引用的参数“$reference”不可用。',
            );
          }
        }
        final resolved = resolveWorkflowTemplateValue(configured, variables);
        values[name] = resolved;
        final match = workflowTemplatePlaceholderPattern.firstMatch(configured);
        if (match != null &&
            match.start == 0 &&
            match.end == configured.length &&
            resolved != null) {
          preservedValues[name] = resolved;
        }
        continue;
      }

      final language = field.valueMode.language!;
      final scope = expressionVariables.putIfAbsent(
        language,
        () => <String, Object?>{...variables},
      );
      final buffer = StringBuffer();
      var offset = 0;
      for (final match in workflowTemplatePlaceholderPattern.allMatches(
        configured,
      )) {
        buffer.write(configured.substring(offset, match.start));
        final reference = match.group(1)!;
        final resolved = _lookupWorkflowVariable(reference, variables);
        if (!resolved.found) {
          throw WorkflowNodeExecutionException(
            '$label“$name”引用的参数“$reference”不可用。',
          );
        }
        final alias = '__openhand_reference_${aliasIndex++}';
        scope[alias] = resolved.value;
        buffer.write(alias);
        offset = match.end;
      }
      buffer.write(configured.substring(offset));
      (expressions[language] ??= <String, String>{})[field.id] = buffer
          .toString();
    }

    for (final entry in expressions.entries) {
      resources.cancellation?.throwIfCancelled();
      final runtime = resources.codeRuntimes[entry.key];
      if (runtime == null || !runtime.isAvailable) {
        throw WorkflowNodeExecutionException(
          runtime?.unavailableReason ?? '${entry.key.label} 运行时不可用，无法评估参数表达式。',
        );
      }
      try {
        final evaluated = await _codeExecutor.evaluateExpressions(
          runtime: runtime,
          expressions: entry.value,
          variables: expressionVariables[entry.key]!,
          cancelSignal: resources.cancellation?.whenCancelled,
        );
        resources.cancellation?.throwIfCancelled();
        for (final field in fields.where(
          (field) => field.valueMode.language == entry.key,
        )) {
          final value = evaluated[field.id];
          values[field.name.trim()] = value;
          if (value != null) preservedValues[field.name.trim()] = value;
        }
      } on WorkflowCodeExecutionException catch (error) {
        throw WorkflowNodeExecutionException(
          '$label的${entry.key.label}表达式评估失败：${error.message}',
          cause: error,
        );
      }
    }

    final resolved = WorkflowStructuredOutputParser.resolveValues(
      fields
          .where((field) => !preservedValues.containsKey(field.name.trim()))
          .toList(growable: false),
      values,
      label: label,
      defaultVariables: variables,
    );
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final field in fields)
        field.name.trim():
            preservedValues[field.name.trim()] ?? resolved[field.name.trim()],
    });
  }

  Future<Map<String, Object?>> _resolveHttpResponseFields({
    required _WorkflowHttpResponse response,
    required List<WorkflowOutputField> fields,
    required WorkflowExecutionResources resources,
    required Map<String, Object?> variables,
  }) async {
    Object? decodedBody;
    try {
      decodedBody = jsonDecode(response.body);
    } on FormatException {
      decodedBody = response.body;
    }
    final context = <String, Object?>{
      ...variables,
      'response': decodedBody,
      workflowHttpBodyOutputName: response.body,
      workflowHttpStatusCodeOutputName: response.statusCode,
      workflowHttpHeadersOutputName: response.headers,
      workflowHttpFilesOutputName: response.files,
    };
    final values = <String, Object?>{};
    final normalizedFields = <WorkflowOutputField>[];
    for (final field in fields) {
      if (field.valueMode != WorkflowValueMode.literal) {
        normalizedFields.add(field);
        continue;
      }
      final path = field.value.trim();
      if (path.isEmpty) {
        if (decodedBody is Map && decodedBody.containsKey(field.name.trim())) {
          values[field.name.trim()] = decodedBody[field.name.trim()];
        }
        normalizedFields.add(field);
        continue;
      }
      final segments = parseWorkflowJsonPath(path);
      if (segments == null) {
        throw WorkflowNodeExecutionException(
          'HTTP 输出参数“${field.name.trim()}”的响应路径无效。',
        );
      }
      Object? current = decodedBody;
      for (final segment in segments) {
        if (segment is String &&
            current is Map &&
            current.containsKey(segment)) {
          current = current[segment];
        } else if (segment is int &&
            current is List &&
            segment < current.length) {
          current = current[segment];
        } else {
          throw WorkflowNodeExecutionException('HTTP 响应中不存在路径“$path”。');
        }
      }
      values[field.name.trim()] = current;
      normalizedFields.add(field.copyWith(value: ''));
    }
    return _resolveConfiguredFieldValues(
      fields: normalizedFields,
      resources: resources,
      variables: context,
      initialValues: values,
      label: 'HTTP 输出参数',
    );
  }

  bool _matchesConditions(
    List<WorkflowConditionClause> conditions,
    WorkflowConditionLogic logic,
    Map<String, Object?> variables,
  ) {
    bool matches(WorkflowConditionClause condition) {
      final left = _configuredValue(condition.variable, variables);
      final right = condition.operator.requiresValue
          ? _configuredValue(
              condition.value,
              variables,
              valueSource: condition.valueSource,
            )
          : null;
      try {
        return _compareWorkflowValues(left, condition.operator, right);
      } on FormatException {
        throw const WorkflowNodeExecutionException('条件中的数值比较参数无效。');
      }
    }

    return logic == WorkflowConditionLogic.all
        ? conditions.every(matches)
        : conditions.any(matches);
  }

  Object? _configuredValue(
    String source,
    Map<String, Object?> variables, {
    WorkflowValueSource valueSource = WorkflowValueSource.variable,
  }) {
    final value = source.trim();
    if (valueSource == WorkflowValueSource.constant) {
      return _literalValue(value);
    }
    final resolved = resolveWorkflowTemplateValue(value, variables);
    if (resolved != value) return resolved;
    final lookup = _lookupWorkflowVariable(value, variables);
    return lookup.found ? lookup.value : resolved;
  }

  ({bool found, Object? value}) _listItemValue(Object? item, String path) {
    if (path.isEmpty) return (found: true, value: item);
    Object? value = item;
    for (final segment in path.split('.')) {
      if (value is Map && value.containsKey(segment)) {
        value = value[segment];
        continue;
      }
      final index = int.tryParse(segment);
      if (value is List &&
          index != null &&
          index >= 0 &&
          index < value.length) {
        value = value[index];
        continue;
      }
      return (found: false, value: null);
    }
    return (found: true, value: value);
  }

  int _compareListValues(Object? left, Object? right) {
    if (identical(left, right) || left == right) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    if (left is num && right is num) return left.compareTo(right);
    if (left is bool && right is bool) {
      return (left ? 1 : 0).compareTo(right ? 1 : 0);
    }
    return '$left'.toLowerCase().compareTo('$right'.toLowerCase());
  }
}

abstract final class WorkflowStructuredOutputParser {
  static void validateFields(
    List<WorkflowOutputField> fields, {
    String label = '输出参数',
    bool allowEmpty = false,
  }) {
    if (fields.isEmpty && !allowEmpty) {
      throw WorkflowNodeExecutionException('$label至少需要一个参数。');
    }
    final names = <String>{};
    for (final field in fields) {
      final name = field.name.trim();
      if (!workflowParameterNamePattern.hasMatch(name)) {
        throw WorkflowNodeExecutionException('$label名称无效：${field.name}');
      }
      if (!names.add(name)) {
        throw WorkflowNodeExecutionException('$label名称重复：$name');
      }
      if (field.valueMode != WorkflowValueMode.literal &&
          field.value.trim().isEmpty) {
        throw WorkflowNodeExecutionException('$label“$name”缺少表达式。');
      }
      if (field.valueMode == WorkflowValueMode.literal &&
          workflowLiteralValueRequiresString(field.value) &&
          field.type != WorkflowOutputType.string) {
        throw WorkflowNodeExecutionException(
          '$label“$name”混合了参数引用与文本，类型必须为 String。',
        );
      }
      if (field.defaultValue.trim().isNotEmpty) {
        final sourceError = validateWorkflowSourcedValue(
          field.valueSource,
          field.defaultValue,
          label: '$label“$name”',
        );
        if (sourceError != null) {
          throw WorkflowNodeExecutionException(sourceError);
        }
        if (field.valueSource == WorkflowValueSource.constant) {
          _coerce(field.defaultValue, field.type, fieldName: name);
        }
      }
    }
  }

  static Map<String, Object?> resolveValues(
    List<WorkflowOutputField> fields,
    Map<String, Object?> values, {
    required String label,
    Map<String, Object?>? defaultVariables,
  }) {
    validateFields(fields, label: label, allowEmpty: true);
    final result = <String, Object?>{};
    final fallbackVariables = defaultVariables ?? values;
    for (final field in fields) {
      final name = field.name.trim();
      final hasValue = values.containsKey(name) && values[name] != null;
      if (hasValue) {
        result[name] = _coerce(values[name], field.type, fieldName: name);
      } else if (field.defaultValue.trim().isNotEmpty) {
        result[name] = _coerce(
          _resolveSourcedValue(field, fallbackVariables),
          field.type,
          fieldName: name,
        );
      } else if (field.required) {
        throw WorkflowNodeExecutionException('$label缺少必需参数：$name');
      } else {
        result[name] = null;
      }
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  static Map<String, Object?> parse(
    String raw,
    List<WorkflowOutputField> fields, {
    Map<String, Object?> variables = const <String, Object?>{},
  }) {
    validateFields(fields);
    final decoded = _decodeObject(raw);
    if (decoded == null) {
      throw const WorkflowNodeExecutionException('无法从响应中解析结构化 JSON 对象。');
    }
    final result = <String, Object?>{};
    for (final field in fields) {
      final name = field.name.trim();
      final hasValue = decoded.containsKey(name) && decoded[name] != null;
      if (!hasValue) {
        if (field.defaultValue.trim().isNotEmpty) {
          result[name] = _coerce(
            _resolveSourcedValue(field, variables),
            field.type,
            fieldName: name,
          );
          continue;
        }
        if (field.required) {
          throw WorkflowNodeExecutionException('响应缺少必需参数：$name');
        }
        result[name] = null;
        continue;
      }
      result[name] = _coerce(decoded[name], field.type, fieldName: name);
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  static Map<String, Object?> jsonSchema(
    List<WorkflowOutputField> fields, {
    Map<String, Object?> variables = const <String, Object?>{},
  }) {
    validateFields(fields);
    return <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'properties': <String, Object?>{
        for (final field in fields)
          field.name.trim(): <String, Object?>{
            'type': field.type.isArray ? 'array' : field.type.storageValue,
            if (field.type.arrayItemType case final itemType?)
              'items': <String, Object?>{'type': itemType.storageValue},
            if (field.description.trim().isNotEmpty)
              'description': field.description.trim(),
            if (field.defaultValue.trim().isNotEmpty &&
                (field.valueSource == WorkflowValueSource.constant ||
                    variables.isNotEmpty))
              'default': _coerce(
                _resolveSourcedValue(field, variables),
                field.type,
                fieldName: field.name.trim(),
              ),
          },
      },
      'required': fields
          .where((field) => field.required)
          .map((field) => field.name.trim())
          .toList(growable: false),
    };
  }

  static String schemaPrompt(
    List<WorkflowOutputField> fields, {
    Map<String, Object?> variables = const <String, Object?>{},
  }) {
    final schema = const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonSchema(fields, variables: variables));
    return '''# 响应格式
仅返回一个符合下列 JSON Schema 的 JSON 对象，不要添加 Markdown、解释或额外字段。

$schema''';
  }

  static Map<String, Object?>? _decodeObject(String raw) {
    final candidates = <String>[raw.trim()];
    final fencePattern = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    candidates.addAll(
      fencePattern.allMatches(raw).map((match) => match.group(1)?.trim() ?? ''),
    );
    final balanced = _firstBalancedObject(raw);
    if (balanced != null) candidates.add(balanced);
    for (final candidate in candidates.where((item) => item.isNotEmpty)) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map) {
          return <String, Object?>{
            for (final entry in decoded.entries) '${entry.key}': entry.value,
          };
        }
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  static String? _firstBalancedObject(String raw) {
    var start = -1;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = 0; index < raw.length; index++) {
      final char = raw[index];
      if (start < 0) {
        if (char == '{') {
          start = index;
          depth = 1;
        }
        continue;
      }
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\' && inString) {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (char == '{') depth += 1;
      if (char == '}') depth -= 1;
      if (depth == 0) return raw.substring(start, index + 1);
    }
    return null;
  }

  static Object? _coerce(
    Object? value,
    WorkflowOutputType type, {
    required String fieldName,
  }) {
    try {
      return switch (type) {
        WorkflowOutputType.string =>
          value is String ? value : jsonEncode(value),
        WorkflowOutputType.integer =>
          value is int
              ? value
              : value is num && value == value.roundToDouble()
              ? value.toInt()
              : int.parse('$value'.trim()),
        WorkflowOutputType.number => _numberValue(value),
        WorkflowOutputType.boolean => _boolValue(value),
        WorkflowOutputType.object => _objectValue(value),
        WorkflowOutputType.array => _arrayValue(value),
        WorkflowOutputType.arrayString => _typedArrayValue(
          value,
          WorkflowOutputType.string,
          fieldName,
        ),
        WorkflowOutputType.arrayNumber => _typedArrayValue(
          value,
          WorkflowOutputType.number,
          fieldName,
        ),
        WorkflowOutputType.arrayObject => _typedArrayValue(
          value,
          WorkflowOutputType.object,
          fieldName,
        ),
        WorkflowOutputType.arrayBoolean => _typedArrayValue(
          value,
          WorkflowOutputType.boolean,
          fieldName,
        ),
      };
    } catch (_) {
      throw WorkflowNodeExecutionException(
        '参数 $fieldName 无法转换为 ${type.label}。',
      );
    }
  }

  static bool _boolValue(Object? value) {
    if (value is bool) return value;
    final normalized = '$value'.trim().toLowerCase();
    if (const <String>{'true', '1', 'yes', '是'}.contains(normalized)) {
      return true;
    }
    if (const <String>{'false', '0', 'no', '否'}.contains(normalized)) {
      return false;
    }
    throw const FormatException();
  }

  static num _numberValue(Object? value) {
    final parsed = value is num ? value : num.parse('$value'.trim());
    if (!parsed.isFinite) throw const FormatException();
    return parsed;
  }

  static Map<String, Object?> _objectValue(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! Map) throw const FormatException();
    return <String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    };
  }

  static List<Object?> _arrayValue(Object? value) {
    final decoded = value is String ? jsonDecode(value) : value;
    if (decoded is! List) throw const FormatException();
    return List<Object?>.unmodifiable(decoded);
  }

  static List<Object?> _typedArrayValue(
    Object? value,
    WorkflowOutputType itemType,
    String fieldName,
  ) {
    return List<Object?>.unmodifiable(
      _arrayValue(
        value,
      ).map((item) => _coerce(item, itemType, fieldName: '$fieldName[]')),
    );
  }

  static Object? _resolveSourcedValue(
    WorkflowOutputField field,
    Map<String, Object?> variables,
  ) {
    if (field.valueSource == WorkflowValueSource.constant) {
      return field.defaultValue;
    }
    for (final match in workflowTemplatePlaceholderPattern.allMatches(
      field.defaultValue,
    )) {
      final reference = match.group(1)!;
      if (!_lookupWorkflowVariable(reference, variables).found) {
        throw WorkflowNodeExecutionException(
          '参数 ${field.name.trim()} 引用的参数“$reference”不可用。',
        );
      }
    }
    return resolveWorkflowTemplateValue(field.defaultValue, variables);
  }
}

String renderWorkflowTemplate(String template, Map<String, Object?> variables) {
  if (template.isEmpty || variables.isEmpty) return template;
  return template.replaceAllMapped(workflowTemplatePlaceholderPattern, (match) {
    final resolved = _lookupWorkflowVariable(match.group(1)!, variables);
    if (!resolved.found) return match.group(0)!;
    return resolved.value is String
        ? resolved.value! as String
        : jsonEncode(resolved.value);
  });
}

Object? resolveWorkflowTemplateValue(
  String template,
  Map<String, Object?> variables,
) {
  final match = workflowTemplatePlaceholderPattern.firstMatch(template);
  if (match != null && match.start == 0 && match.end == template.length) {
    final resolved = _lookupWorkflowVariable(match.group(1)!, variables);
    if (resolved.found) return resolved.value;
  }
  return renderWorkflowTemplate(template, variables);
}

({bool found, Object? value}) _lookupWorkflowVariable(
  String path,
  Map<String, Object?> variables,
) {
  Object? value = variables;
  for (final segment in path.split('.')) {
    if (value is Map && value.containsKey(segment)) {
      value = value[segment];
    } else {
      return (found: false, value: null);
    }
  }
  return (found: true, value: value);
}

class _WorkflowMcpBinding {
  const _WorkflowMcpBinding({
    required this.callName,
    required this.server,
    required this.tool,
  });

  final String callName;
  final McpServer server;
  final McpTool tool;
}

String _workflowMcpToolName(
  String serverName,
  String toolName,
  Set<String> usedNames,
) {
  var base = 'mcp_${serverName}_$toolName'
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (base.isEmpty) base = 'mcp_tool';
  if (RegExp(r'^[0-9]').hasMatch(base)) base = 'mcp_$base';
  base = clipTextByCodeUnits(base, 56, suffix: '');
  var candidate = base;
  var suffix = 2;
  while (!usedNames.add(candidate)) {
    candidate = '${clipTextByCodeUnits(base, 52, suffix: '')}_${suffix++}';
  }
  return candidate;
}

Map<String, Object?> _decodeToolArguments(String raw, String toolName) {
  if (raw.length > 256 * 1024) {
    throw WorkflowNodeExecutionException('工具 $toolName 的参数超过长度上限。');
  }
  try {
    final decoded = jsonDecode(raw.trim().isEmpty ? '{}' : raw);
    if (decoded is! Map) throw const FormatException();
    return <String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    };
  } on FormatException {
    throw WorkflowNodeExecutionException('工具 $toolName 的参数不是有效 JSON 对象。');
  }
}

String _boundedToolOutput(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return '工具未返回内容。';
  return clipTextByCodeUnits(
    normalized,
    _maxWorkflowToolOutputCharacters,
    suffix: '\n…（工具输出已截断）',
  );
}

class _WorkflowHttpResponse {
  const _WorkflowHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.files,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final List<Map<String, Object?>> files;
}

class _WorkflowHttpRequestBody {
  const _WorkflowHttpRequestBody({
    required this.bytes,
    required this.contentType,
    required this.forceContentType,
  });

  final List<int> bytes;
  final ContentType contentType;
  final bool forceContentType;
}

List<Map<String, Object?>> _httpResponseFiles(
  HttpClientResponse response,
  Uint8List bytes,
  Uri uri,
) {
  if (bytes.isEmpty) return const <Map<String, Object?>>[];
  final contentType = response.headers.contentType;
  final mimeType = contentType?.mimeType ?? 'application/octet-stream';
  final disposition = response.headers.value('content-disposition') ?? '';
  final encodedName = RegExp(
    r"filename\*=UTF-8''([^;]+)",
    caseSensitive: false,
  ).firstMatch(disposition)?.group(1);
  final regularName = RegExp(
    r'filename\s*=\s*"?([^";]+)',
    caseSensitive: false,
  ).firstMatch(disposition)?.group(1);
  final isTextResponse =
      mimeType.startsWith('text/') ||
      mimeType.contains('json') ||
      mimeType.contains('xml') ||
      mimeType.contains('javascript') ||
      mimeType.contains('x-www-form-urlencoded');
  if (!disposition.toLowerCase().contains('attachment') &&
      encodedName == null &&
      regularName == null &&
      isTextResponse) {
    return const <Map<String, Object?>>[];
  }
  var name = encodedName ?? regularName ?? '';
  if (name.isNotEmpty) {
    try {
      name = Uri.decodeComponent(name);
    } on FormatException {
      name = name.trim();
    }
  }
  if (name.isEmpty && uri.pathSegments.isNotEmpty) {
    name = uri.pathSegments.last.trim();
  }
  if (name.isEmpty) name = 'response.bin';
  return <Map<String, Object?>>[
    <String, Object?>{
      'name': name,
      'mime_type': mimeType,
      'size': bytes.length,
      'data_base64': base64Encode(bytes),
    },
  ];
}

String _httpErrorType(Object error) {
  if (error is TimeoutException) return 'HTTPTimeoutError';
  if (error is HandshakeException) return 'HTTPTlsError';
  if (error is SocketException) return 'HTTPConnectionError';
  if (error is HttpException) return 'HTTPProtocolError';
  if (error is WorkflowNodeExecutionException) {
    return error.message.startsWith('HTTP ')
        ? 'HTTPStatusError'
        : 'HTTPResponseError';
  }
  return 'HTTPExecutionError';
}

String _llmErrorType(Object? error) {
  if (error is TimeoutException) return 'LLMTimeoutError';
  if (error is IOException) return 'LLMConnectionError';
  if (error is WorkflowNodeExecutionException) return 'LLMResponseError';
  return 'LLMExecutionError';
}

({String text, String reasoning}) _separateLlmReasoning(
  String text,
  WorkflowLlmReasoningFormat format,
) {
  if (format != WorkflowLlmReasoningFormat.separated) {
    return (text: text, reasoning: '');
  }
  final pattern = RegExp(
    r'<think\b[^>]*>([\s\S]*?)<\/think\s*>',
    caseSensitive: false,
  );
  final reasoning = pattern
      .allMatches(text)
      .map((match) => match.group(1)?.trim() ?? '')
      .where((item) => item.isNotEmpty)
      .join('\n\n');
  return (text: text.replaceAll(pattern, '').trim(), reasoning: reasoning);
}

String _executionErrorText(Object? error) {
  if (error is WorkflowNodeExecutionException) return error.message;
  if (error is TimeoutException) return error.message ?? '请求超时。';
  final text = '$error'.trim();
  return text.isEmpty ? '未知错误。' : text;
}

Object? _literalValue(String value) {
  final normalized = value.trim();
  if ((normalized.startsWith('"') && normalized.endsWith('"')) ||
      (normalized.startsWith("'") && normalized.endsWith("'"))) {
    return normalized.substring(1, normalized.length - 1);
  }
  if (normalized == 'true') return true;
  if (normalized == 'false') return false;
  return num.tryParse(normalized) ?? normalized;
}

num _number(Object? value) {
  if (value is num) return value;
  return num.parse('$value'.trim());
}

bool _compareWorkflowValues(
  Object? left,
  WorkflowConditionOperator operator,
  Object? right,
) {
  final empty =
      left == null ||
      left is String && left.isEmpty ||
      left is Iterable && left.isEmpty ||
      left is Map && left.isEmpty;
  return switch (operator) {
    WorkflowConditionOperator.isEmpty => empty,
    WorkflowConditionOperator.isNotEmpty => !empty,
    WorkflowConditionOperator.isNull => left == null,
    WorkflowConditionOperator.isNotNull => left != null,
    WorkflowConditionOperator.equals => left == right || '$left' == '$right',
    WorkflowConditionOperator.notEquals => left != right && '$left' != '$right',
    WorkflowConditionOperator.contains => switch (left) {
      String value => value.contains('$right'),
      Iterable value => value.contains(right),
      Map value => value.containsKey(right) || value.containsValue(right),
      _ => '$left'.contains('$right'),
    },
    WorkflowConditionOperator.notContains => !_compareWorkflowValues(
      left,
      WorkflowConditionOperator.contains,
      right,
    ),
    WorkflowConditionOperator.startsWith => '$left'.startsWith('$right'),
    WorkflowConditionOperator.endsWith => '$left'.endsWith('$right'),
    WorkflowConditionOperator.greaterThan => _number(left) > _number(right),
    WorkflowConditionOperator.lessThan => _number(left) < _number(right),
    WorkflowConditionOperator.greaterThanOrEqual =>
      _number(left) >= _number(right),
    WorkflowConditionOperator.lessThanOrEqual =>
      _number(left) <= _number(right),
  };
}

List<Object?>? _tryDecodeList(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is List ? List<Object?>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}
