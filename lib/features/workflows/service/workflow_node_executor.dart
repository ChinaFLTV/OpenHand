import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../app/support/system_proxy.dart';
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

const int _maxWorkflowHttpResponseBytes = 4 * 1024 * 1024;
const int _maxWorkflowPromptCharacters = 256 * 1024;
const int _maxWorkflowResourceCharacters = 96 * 1024;
const int _maxWorkflowRetries = 10;
const int _maxWorkflowRetryIntervalMs = 60 * 1000;
const int _maxWorkflowMcpTools = 64;
const Duration _humanInterventionTimeoutGrace = Duration(seconds: 1);
const int _maxWorkflowToolRounds = 8;
const int _maxWorkflowToolCalls = 32;
const int _maxWorkflowToolOutputCharacters = 128 * 1024;

typedef WorkflowMcpToolInvoker =
    Future<WorkflowMcpToolInvocationResult> Function({
      required String serverName,
      required String toolName,
      required Map<String, Object?> arguments,
      required String toolCallId,
    });

typedef WorkflowLlmConversationListener =
    void Function(WorkflowLlmConversation conversation);

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
  });

  final String nodeId;
  final String nodeTitle;
  final String content;
  final List<WorkflowOutputField> fields;
  final Map<String, Object?> initialValues;
  final List<WorkflowHumanAction> actions;
  final Duration timeout;
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
}

class WorkflowNodeExecutionResult {
  const WorkflowNodeExecutionResult({
    required this.output,
    required this.attempts,
    required this.duration,
    this.rawOutput = '',
    this.conversation,
    this.selectedBranchId,
  });

  final Object? output;
  final String rawOutput;
  final int attempts;
  final Duration duration;
  final WorkflowLlmConversation? conversation;
  final String? selectedBranchId;
}

class WorkflowNodeExecutor {
  WorkflowNodeExecutor({AiChatClient? chatClient})
    : _chatClient = chatClient ?? AiChatService(),
      _ownsChatClient = chatClient == null;

  final AiChatClient _chatClient;
  final bool _ownsChatClient;
  static const WorkflowCodeExecutor _codeExecutor = WorkflowCodeExecutor();

  Future<WorkflowNodeExecutionResult> execute({
    required WorkflowNode node,
    required WorkflowExecutionResources resources,
    Map<String, Object?> variables = const <String, Object?>{},
    List<WorkflowNode> workflowNodes = const <WorkflowNode>[],
    List<WorkflowConnection> workflowConnections = const <WorkflowConnection>[],
  }) {
    return switch (node.kind) {
      WorkflowNodeKind.start => Future<WorkflowNodeExecutionResult>.value(
        _executeParameterNode(
          fields: node.inputFields(),
          variables: variables,
          label: '输入参数',
        ),
      ),
      WorkflowNodeKind.llm => _executeLlm(node, resources, variables),
      WorkflowNodeKind.httpRequest => _executeHttp(node, variables),
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
        Future<WorkflowNodeExecutionResult>.value(
          _executeParameterNode(
            fields: node.outputFields(),
            variables: variables,
            label: '赋值参数',
          ),
        ),
      WorkflowNodeKind.listOperation => _executeListOperation(node, variables),
      WorkflowNodeKind.codeExecution => _executeCode(
        node,
        resources,
        variables,
      ),
      WorkflowNodeKind.humanIntervention => _executeHumanIntervention(
        node,
        resources,
        variables,
      ),
      WorkflowNodeKind.loopExit => Future<WorkflowNodeExecutionResult>.error(
        const _WorkflowLoopExitSignal(),
      ),
      WorkflowNodeKind.end => Future<WorkflowNodeExecutionResult>.value(
        _executeParameterNode(
          fields: node.outputFields(),
          variables: variables,
          label: '输出参数',
        ),
      ),
    };
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

  Future<WorkflowNodeExecutionResult> _executeCode(
    WorkflowNode node,
    WorkflowExecutionResources resources,
    Map<String, Object?> variables,
  ) async {
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
      label: '代码输入变量',
      allowEmpty: true,
    );
    final configuredInputs = <String, Object?>{...variables};
    for (final field in inputFields) {
      final name = field.name.trim();
      if (field.defaultValue.trim().isEmpty) {
        throw WorkflowNodeExecutionException('代码输入变量“$name”缺少取值。');
      }
      if (field.valueSource == WorkflowValueSource.variable) {
        for (final match in workflowTemplatePlaceholderPattern.allMatches(
          field.defaultValue,
        )) {
          if (!_lookupWorkflowVariable(match.group(1)!, variables).found) {
            throw WorkflowNodeExecutionException(
              '代码输入变量“$name”引用的参数“${match.group(1)}”不可用。',
            );
          }
        }
        configuredInputs[name] = resolveWorkflowTemplateValue(
          field.defaultValue,
          variables,
        );
      } else {
        configuredInputs[name] = field.defaultValue;
      }
    }
    final inputs = WorkflowStructuredOutputParser.resolveValues(
      inputFields,
      configuredInputs,
      label: '代码输入变量',
    );
    final outputFields = node.outputFields();
    WorkflowStructuredOutputParser.validateFields(
      outputFields,
      label: '代码输出变量',
    );
    final errorStrategy = WorkflowCodeErrorStrategy.fromStorage(
      node.settings[WorkflowSettingKeys.errorStrategy],
    );
    final retryCount = node.boolSetting(WorkflowSettingKeys.retryEnabled)
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
      attempts = attempt + 1;
      try {
        final result = await _codeExecutor.execute(
          runtime: runtime,
          code: node.stringSetting(WorkflowSettingKeys.code),
          inputs: inputs,
          timeout: timeout,
        );
        for (final field in outputFields) {
          final name = field.name.trim();
          if (!result.output.containsKey(name)) {
            throw WorkflowNodeExecutionException('代码返回结果缺少输出变量：$name');
          }
        }
        final output = WorkflowStructuredOutputParser.resolveValues(
          outputFields,
          result.output,
          label: '代码输出变量',
        );
        return WorkflowNodeExecutionResult(
          output: output,
          rawOutput: jsonEncode(output),
          attempts: attempts,
          duration: stopwatch.elapsed,
          selectedBranchId:
              errorStrategy == WorkflowCodeErrorStrategy.failBranch
              ? workflowCodeSuccessHandleId
              : null,
        );
      } catch (error) {
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
        await Future<void>.delayed(retryInterval);
      }
    }

    final failure =
        latestError ?? const WorkflowNodeExecutionException('代码执行失败。');
    if (errorStrategy == WorkflowCodeErrorStrategy.terminate) throw failure;
    if (errorStrategy == WorkflowCodeErrorStrategy.defaultValue) {
      final defaults = node.codeErrorDefaultValues();
      try {
        final output = WorkflowStructuredOutputParser.resolveValues(
          outputFields,
          <String, Object?>{
            for (final field in outputFields)
              field.name.trim():
                  defaults[field.id] ??
                  defaultWorkflowCodeErrorValue(field.type),
          },
          label: '代码异常默认值',
        );
        return WorkflowNodeExecutionResult(
          output: output,
          rawOutput: jsonEncode(output),
          attempts: attempts,
          duration: stopwatch.elapsed,
        );
      } on WorkflowNodeExecutionException catch (error) {
        throw WorkflowNodeExecutionException(
          '代码异常默认值无效：${error.message}',
          cause: error,
        );
      }
    }
    final output = <String, Object?>{
      workflowCodeErrorTypeOutputName: latestErrorType,
      workflowCodeErrorMessageOutputName: failure.message,
    };
    return WorkflowNodeExecutionResult(
      output: Map<String, Object?>.unmodifiable(output),
      rawOutput: jsonEncode(output),
      attempts: attempts,
      duration: stopwatch.elapsed,
      selectedBranchId: workflowCodeFailureHandleId,
    );
  }

  Future<WorkflowNodeExecutionResult> _executeLlm(
    WorkflowNode node,
    WorkflowExecutionResources resources,
    Map<String, Object?> variables,
  ) async {
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
    final bundle = await resources.templateRepository.loadBundle(
      templateId.isEmpty ? 'default' : templateId,
    );
    final resourcePrompt = await _buildResourcePrompt(
      node: node,
      resources: resources,
      query: userPrompt,
    );
    final outputFields = node.outputFields();
    final structured = node.boolSetting(WorkflowSettingKeys.structuredOutput);
    if (structured) WorkflowStructuredOutputParser.validateFields(outputFields);
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

    final retries = _boundedRetryCount(node);
    final interval = _boundedRetryInterval(node);
    final startedAt = DateTime.now().toUtc();
    final conversationId = startedAt.microsecondsSinceEpoch;
    final stopwatch = Stopwatch()..start();
    var attempts = 0;
    Object? lastError;
    var lastMessages = const <WorkflowLlmConversationMessage>[];
    while (attempts <= retries) {
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
          onConversationChanged: publishRunning,
        );
        final raw = completion.reply.trim();
        if (raw.isEmpty) {
          throw const WorkflowNodeExecutionException('模型返回内容为空。');
        }
        final output = structured
            ? WorkflowStructuredOutputParser.parse(
                raw,
                outputFields,
                variables: variables,
              )
            : raw;
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
        );
      } catch (error) {
        lastError = error;
        if (attempts > retries) break;
        await Future<void>.delayed(interval);
      }
    }
    stopwatch.stop();
    final message = 'LLM 节点执行失败：${_executionErrorText(lastError)}';
    resources.onLlmConversation?.call(
      WorkflowLlmConversation(
        nodeId: node.id,
        modelConfigId: modelConfigId,
        modelId: modelId,
        modelLabel: provider.providerLabel,
        startedAt: startedAt,
        endedAt: DateTime.now().toUtc(),
        duration: stopwatch.elapsed,
        attempts: attempts,
        status: WorkflowLlmConversationStatus.failed,
        messages: List<WorkflowLlmConversationMessage>.unmodifiable(
          lastMessages,
        ),
        error: message,
      ),
    );
    throw WorkflowNodeExecutionException(message, cause: lastError);
  }

  Future<AiChatCompletion> _sendLlmWithTools({
    required AiModelConfig model,
    required String systemPrompt,
    required String prompt,
    required List<_WorkflowMcpBinding> bindings,
    required WorkflowMcpToolInvoker? invoker,
    required List<WorkflowLlmConversationMessage> conversationMessages,
    required void Function() onConversationChanged,
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
      final completion = await _chatClient.sendMessage(
        model: model,
        messages: messages,
        tools: tools,
        timeout: const Duration(seconds: 120),
      );
      _appendLlmCompletionMessages(conversationMessages, completion);
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
        final result =
            await invoker(
              serverName: binding.server.name,
              toolName: binding.tool.id,
              arguments: arguments,
              toolCallId: call.id,
            ).timeout(
              const Duration(seconds: 120),
              onTimeout: () => throw TimeoutException('MCP 工具调用超时。'),
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

    add(WorkflowLlmMessageKind.reasoning, completion.reasoningContent);
    add(WorkflowLlmMessageKind.assistant, completion.reply);
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
        final retrieved = await knowledge.retrieveForTool(
          query: query,
          topK: 20,
          models: resources.models,
        );
        if (retrieved != null) {
          final hits = retrieved.result.hits
              .where((hit) => knowledgeIds.contains(hit.source.id))
              .take(12)
              .toList(growable: false);
          final context = _knowledgePrompt(hits);
          if (context.isNotEmpty) sections.add(context);
        }
      } catch (_) {
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
    Map<String, Object?> variables,
  ) async {
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
    if (!const <String>{
      'GET',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
      'HEAD',
    }.contains(method)) {
      throw const WorkflowNodeExecutionException('HTTP 请求方式无效。');
    }
    final retries = _boundedRetryCount(node);
    final interval = _boundedRetryInterval(node);
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    var attempts = 0;
    while (attempts <= retries) {
      attempts += 1;
      try {
        final response = await _sendHttpRequest(
          node: node,
          method: method,
          uri: uri,
          headers: headers,
          variables: variables,
        );
        final structured = node.boolSetting(
          WorkflowSettingKeys.structuredOutput,
        );
        final fields = node.outputFields();
        final output = structured
            ? WorkflowStructuredOutputParser.parse(
                response.body,
                fields,
                variables: variables,
              )
            : <String, Object?>{
                'status_code': response.statusCode,
                'headers': response.headers,
                'body': response.body,
              };
        stopwatch.stop();
        return WorkflowNodeExecutionResult(
          output: output,
          rawOutput: response.body,
          attempts: attempts,
          duration: stopwatch.elapsed,
        );
      } catch (error) {
        lastError = error;
        if (attempts > retries) break;
        await Future<void>.delayed(interval);
      }
    }
    stopwatch.stop();
    throw WorkflowNodeExecutionException(
      'HTTP 节点执行失败：${_executionErrorText(lastError)}',
      cause: lastError,
    );
  }

  Future<_WorkflowHttpResponse> _sendHttpRequest({
    required WorkflowNode node,
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, Object?> variables,
  }) async {
    final connectSeconds = node
        .intSetting(WorkflowSettingKeys.connectTimeoutSeconds, 15)
        .clamp(1, 120);
    final responseSeconds = node
        .intSetting(WorkflowSettingKeys.responseTimeoutSeconds, 60)
        .clamp(1, 600);
    final client = SystemProxyResolver.instance.createRawHttpClient(
      connectionTimeout: Duration(seconds: connectSeconds),
      userAgent: 'OpenHand-Workflow/1.0',
    );
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(
            Duration(seconds: connectSeconds),
            onTimeout: () => throw TimeoutException('HTTP 连接超时。'),
          );
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (!const <String>{'GET', 'HEAD'}.contains(method)) {
        _writeHttpBody(request, node, variables);
      }
      final response = await request.close().timeout(
        Duration(seconds: responseSeconds),
        onTimeout: () {
          request.abort(TimeoutException('HTTP 响应超时。'));
          throw TimeoutException('HTTP 响应超时。');
        },
      );
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(
        Duration(seconds: responseSeconds),
      )) {
        if (bytes.length + chunk.length > _maxWorkflowHttpResponseBytes) {
          throw const WorkflowNodeExecutionException('HTTP 响应超过 4 MiB 上限。');
        }
        bytes.add(chunk);
      }
      final body = utf8.decode(bytes.takeBytes(), allowMalformed: true);
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
      );
    } finally {
      client.close(force: true);
    }
  }

  void _writeHttpBody(
    HttpClientRequest request,
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
    switch (format) {
      case WorkflowHttpBodyFormat.none:
        return;
      case WorkflowHttpBodyFormat.json:
        try {
          request.add(utf8.encode(jsonEncode(jsonDecode(body))));
        } on FormatException {
          throw const WorkflowNodeExecutionException('请求体不是有效 JSON。');
        }
        request.headers.contentType = ContentType.json;
        return;
      case WorkflowHttpBodyFormat.text:
        request.headers.contentType = ContentType.text;
        request.add(utf8.encode(body));
        return;
      case WorkflowHttpBodyFormat.formUrlEncoded:
        final values = _bodyEntries(node, variables);
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.add(utf8.encode(Uri(queryParameters: values).query));
        return;
      case WorkflowHttpBodyFormat.formData:
        final boundary = 'openhand-${DateTime.now().microsecondsSinceEpoch}';
        request.headers.contentType = ContentType(
          'multipart',
          'form-data',
          parameters: <String, String>{'boundary': boundary},
        );
        final buffer = StringBuffer();
        for (final entry in _bodyEntries(node, variables).entries) {
          buffer
            ..writeln('--$boundary')
            ..writeln(
              'Content-Disposition: form-data; name="${_escapeMultipartName(entry.key)}"',
            )
            ..writeln()
            ..writeln(entry.value);
        }
        buffer.write('--$boundary--\r\n');
        request.add(utf8.encode(buffer.toString().replaceAll('\n', '\r\n')));
        return;
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
      value.replaceAll(RegExp(r'["\r\n]'), '_');

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
          ),
        ).timeout(
          timeout + _humanInterventionTimeoutGrace,
          onTimeout: () => const WorkflowHumanInterventionResponse(
            actionId: workflowHumanTimeoutHandleId,
          ),
        );
    if (response.timedOut) {
      final output = <String, Object?>{
        workflowHumanActionIdOutputName: workflowHumanTimeoutHandleId,
        workflowHumanActionValueOutputName: '超时',
        workflowHumanRenderedContentOutputName: content,
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
      workflowHumanActionIdOutputName: action.id,
      workflowHumanActionValueOutputName: action.title.trim(),
      workflowHumanRenderedContentOutputName: content,
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
    final incomingCounts = <String, int>{
      for (final child in children) child.id: 0,
    };
    for (final edge in childEdges) {
      incomingCounts[edge.targetNodeId] =
          incomingCounts[edge.targetNodeId]! + 1;
    }
    final ready = ListQueue<String>.from(
      children
          .where((child) => incomingCounts[child.id] == 0)
          .map((child) => child.id),
    );
    final executionOrder = <String>[];
    while (ready.isNotEmpty) {
      final nodeId = ready.removeFirst();
      executionOrder.add(nodeId);
      for (final edge in childEdges) {
        if (edge.sourceNodeId != nodeId) continue;
        final remaining = incomingCounts[edge.targetNodeId]! - 1;
        incomingCounts[edge.targetNodeId] = remaining;
        if (remaining == 0) ready.add(edge.targetNodeId);
      }
    }
    if (executionOrder.length != children.length) {
      throw WorkflowNodeExecutionException('节点“${parent.title}”的内部工作流存在循环连线。');
    }
    final resolvedVariables = <String, Object?>{...variables};
    for (final nodeId in executionOrder) {
      if (!activeNodeIds.contains(nodeId)) continue;
      final child = childrenById[nodeId];
      if (child == null) continue;
      if (child.kind == WorkflowNodeKind.loopExit) {
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
      if (result.output case final Map output) {
        for (final entry in output.entries) {
          resolvedVariables['${entry.key}'] = entry.value;
        }
      } else {
        final fields = child.declaredParameterFields();
        if (fields.length == 1) {
          resolvedVariables[fields.first.name.trim()] = result.output;
        }
      }
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

  int _boundedRetryCount(WorkflowNode node) => node
      .intSetting(WorkflowSettingKeys.retryCount, 0)
      .clamp(0, _maxWorkflowRetries);

  Duration _boundedRetryInterval(WorkflowNode node) => Duration(
    milliseconds: node
        .intSetting(WorkflowSettingKeys.retryIntervalMs, 1000)
        .clamp(0, _maxWorkflowRetryIntervalMs),
  );
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
  }) {
    validateFields(fields, label: label, allowEmpty: true);
    final result = <String, Object?>{};
    for (final field in fields) {
      final name = field.name.trim();
      final hasValue = values.containsKey(name) && values[name] != null;
      if (hasValue) {
        result[name] = _coerce(values[name], field.type, fieldName: name);
      } else if (field.defaultValue.trim().isNotEmpty) {
        result[name] = _coerce(
          _resolveSourcedValue(field, values),
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
    return field.valueSource == WorkflowValueSource.variable
        ? resolveWorkflowTemplateValue(field.defaultValue, variables)
        : field.defaultValue;
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
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
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
