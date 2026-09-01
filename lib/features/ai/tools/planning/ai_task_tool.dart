import 'dart:async';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/text_normalization.dart';
import '../../model/ai_builtin_tool_config.dart'
    show kAiReadOnlyBuiltinToolKinds;
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/chat/ai_chat_service.dart';
import '../../service/chat/ai_protocol_adapter.dart';
import '../../service/hook/ai_claude_hook_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../../service/usage/ai_usage_tracker.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiTaskTool extends AiTool {
  AiTaskTool({required this._backgroundChatClient, required this._hookService});

  static const int _maxToolRounds = 6;
  static const int _maxToolCallsPerRound = 8;
  static const int _maxTotalToolCalls = 32;
  static const int _maxToolArgumentCharacters = 256 * kBytesPerKiB;
  static const int _maxToolOutputCharacters = 64 * kBytesPerKiB;
  static const int _maxTotalToolOutputCharacters = 256 * kBytesPerKiB;
  static const int _maxResultCharacters = 24000;
  static const Duration _maxExecutionDuration = Duration(minutes: 10);
  static const Duration _chatTurnTimeout = Duration(seconds: 75);
  static const String _toolName = 'Task';
  static const String _subagentStartEvent = 'SubagentStart';
  static const String _subagentStopEvent = 'SubagentStop';
  static const String defaultSubagentType = 'general-purpose';
  static const Set<String> _unsupportedClaudeAgentParameterKeys = <String>{
    'run_in_background',
    'model',
    'name',
    'team_name',
    'mode',
    'isolation',
    'cwd',
  };
  static final AiBashToolService _bashWriteAnalyzer = AiBashToolService();

  final AiChatClient _backgroundChatClient;
  final AiClaudeHookService _hookService;

  static const Map<String, String> subagentDescriptions = <String, String>{
    'general-purpose':
        'General-purpose agent for researching complex questions, searching for code, and executing multi-step tasks.',
    'research':
        'Read-only exploration agent. Use to map unfamiliar code, follow references, or gather facts across many files. Avoid writes; report findings.',
    'verify':
        'Verification agent. Run tests / lints / type checks / builds and return concise pass/fail with the smallest reproducer. Do not edit source files.',
    'summarize':
        'Summarization agent. Compress large outputs, transcripts, or multi-file reads into a structured digest preserving the parent agent\'s decision-relevant facts.',
    'advice':
        'Advice agent. Compare design alternatives, weigh trade-offs, and recommend an approach with explicit risks. Read-only.',
  };

  static const Set<String> readOnlyParallelSubagentTypes = <String>{
    'research',
    'summarize',
    'advice',
  };

  static const Set<AiBuiltinToolKind> _verifyBuiltinKinds = <AiBuiltinToolKind>{
    ...kAiReadOnlyBuiltinToolKinds,
    AiBuiltinToolKind.bash,
  };

  static const Set<AiBuiltinToolKind> _generalPurposeBuiltinKinds =
      <AiBuiltinToolKind>{..._verifyBuiltinKinds};

  static String? canonicalSubagentType(String rawType) {
    final normalized = lowercaseStringFromValue(rawType);
    if (normalized.isEmpty) return null;
    return subagentDescriptions.containsKey(normalized) ? normalized : null;
  }

  static String requestedSubagentTypeFromArguments(
    Map<Object?, Object?> arguments,
  ) {
    final rawSubagentType =
        optionalStringFromValue(arguments['subagent_type']) ??
        optionalStringFromValue(arguments['subagentType']) ??
        '';
    return rawSubagentType.isEmpty ? defaultSubagentType : rawSubagentType;
  }

  static String? resolveSubagentTypeFromArguments(
    Map<Object?, Object?> arguments,
  ) {
    return canonicalSubagentType(requestedSubagentTypeFromArguments(arguments));
  }

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.task;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final description = AiToolUtils.readString(args['description']);
    final prompt = AiToolUtils.readString(args['prompt']);
    final subagentType = requestedSubagentTypeFromArguments(args);
    final unsupportedClaudeAgentParameters = _unsupportedClaudeAgentParameters(
      args,
    );
    if (unsupportedClaudeAgentParameters.isNotEmpty) {
      return AiToolUtils.invalidResult(
        _displayToolName(context),
        '不支持以下 Claude Agent 参数：${unsupportedClaudeAgentParameters.join(', ')}。'
        'Task 仅运行隔离的前台子智能体，请移除这些字段或使用受支持的 subagent_type。',
      );
    }
    if (description.isEmpty || prompt.isEmpty) {
      return AiToolUtils.invalidResult(
        _displayToolName(context),
        '${_displayToolName(context)} 需要非空的 description 和 prompt。',
      );
    }
    if (description.length > kAiTaskDescriptionMaxCharacters) {
      return AiToolUtils.invalidResult(
        _displayToolName(context),
        'description 不能超过 $kAiTaskDescriptionMaxCharacters 个字符。',
      );
    }
    if (prompt.length > kAiTaskPromptMaxCharacters) {
      return AiToolUtils.invalidResult(
        _displayToolName(context),
        'prompt 不能超过 $kAiTaskPromptMaxCharacters 个字符。',
      );
    }
    final canonicalSubagentType = resolveSubagentTypeFromArguments(args);
    if (canonicalSubagentType == null) {
      return AiToolUtils.invalidResult(
        _displayToolName(context),
        '不支持 subagent_type“$subagentType”，可用类型：${subagentDescriptions.keys.join(', ')}。',
      );
    }
    if (_isBlockedPlanModeSubagent(
      metadata: context.metadata,
      subagentType: canonicalSubagentType,
    )) {
      return AiToolUtils.withMergedMetadata(
        AiToolUtils.invalidResult(
          _toolName,
          '计划执行获批前，Task 仅允许只读 subagent_type：${readOnlyParallelSubagentTypes.join(', ')}。'
          '请改用只读子智能体，或在计划获批后运行“$canonicalSubagentType”。',
        ),
        <String, Object?>{
          'task_blocked_plan_mode_subagent': true,
          'task_block_reason': 'plan_mode_execution_unapproved',
          'subagent_type': canonicalSubagentType,
          'allowed_subagent_types_before_approval':
              readOnlyParallelSubagentTypes.toList(growable: false),
          'plan_mode_active': context.metadata['plan_mode_active'] == true,
          'plan_mode_execution_approved_for_send':
              context.metadata['plan_mode_execution_approved_for_send'] == true,
        },
      );
    }
    final subagentProfile =
        subagentDescriptions[canonicalSubagentType] ??
        'Focused background agent.';
    final subagentToolEntries = context.catalog.toolsByName.entries
        .where(
          (entry) => _isAllowedSubagentTool(
            entry.value,
            subagentType: canonicalSubagentType,
          ),
        )
        .toList(growable: false);
    final subagentCatalog = AiResolvedToolCatalog(
      definitions: subagentToolEntries
          .map((entry) => entry.value.definition)
          .toList(growable: false),
      toolsByName: Map<String, AiResolvedTool>.fromEntries(subagentToolEntries),
    );
    final turns = <AiChatTurn>[
      AiChatTurn(
        role: AiChatRole.system,
        content: _subagentSystemPrompt(
          subagentType: canonicalSubagentType,
          subagentProfile: subagentProfile,
          toolCount: subagentCatalog.definitions.length,
        ),
      ),
      AiChatTurn(
        role: AiChatRole.user,
        content:
            'Description: $description\nSubagent type: $canonicalSubagentType\n\nTask:\n$prompt',
      ),
    ];
    final readFiles = <String>{};
    // 异步记录取消状态，确保一批子工具执行期间也能及时停止后续调用。
    var cancelled = false;
    context.cancelSignal?.then<void>(
      (_) => cancelled = true,
      onError: (Object _, StackTrace _) {
        cancelled = true;
      },
    );
    final subagentSessionId =
        '${context.sessionId}/task/${_normalizeToken(context.toolCall.id.trim().isEmpty ? canonicalSubagentType : context.toolCall.id)}';
    final subagentStartHookResult = await AiToolUtils.awaitWithCancellation(
      _runAuxiliaryHook(
        eventName: _subagentStartEvent,
        sessionId: subagentSessionId,
        matcherValue: canonicalSubagentType,
        cwd: AiToolUtils.defaultWorkingDirectory(),
        payload: <String, Object?>{
          'subagent_type': canonicalSubagentType,
          'subagentType': canonicalSubagentType,
          'description': description,
          'stateless': true,
        },
      ),
      cancelSignal: context.cancelSignal,
    );
    if (subagentStartHookResult == null) {
      return AiToolUtils.cancelledResult(
        command: '$_toolName $description',
        durationMs: startedAt.elapsedMilliseconds,
        metadata: _subagentMetadata(
          subagentType: canonicalSubagentType,
          toolCount: subagentCatalog.definitions.length,
          rounds: 0,
          terminalStatus: 'cancelled',
        ),
      );
    }
    Future<AiToolExecutionResult> cancelledResult(int rounds) {
      return _cancelledTaskResult(
        startedAt: startedAt,
        description: description,
        sessionId: subagentSessionId,
        subagentType: canonicalSubagentType,
        toolCount: subagentCatalog.definitions.length,
        rounds: rounds,
        startHookResult: subagentStartHookResult,
      );
    }

    Future<AiToolExecutionResult> failedResult(
      String error, {
      required int rounds,
      String? hookError,
      Map<String, Object?> extraMetadata = const <String, Object?>{},
    }) async {
      final stopHookResult = await _runSubagentStopHook(
        sessionId: subagentSessionId,
        subagentType: canonicalSubagentType,
        description: description,
        status: 'failed',
        error: hookError ?? error,
      );
      return _failedTaskResult(
        description: description,
        error: error,
        durationMs: startedAt.elapsedMilliseconds,
        subagentType: canonicalSubagentType,
        toolCount: subagentCatalog.definitions.length,
        rounds: rounds,
        systemReminders: _hookSystemReminders(
          subagentStartHookResult,
          stopHookResult,
        ),
        extraMetadata: extraMetadata,
      );
    }

    if (cancelled || await isCancelSignalCompleted(context.cancelSignal)) {
      return cancelledResult(0);
    }
    if (subagentStartHookResult.blocked) {
      final blockReason =
          subagentStartHookResult.blockReason ?? '子智能体钩子已阻止任务执行。';
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: '$_toolName $description',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr: blockReason,
        durationMs: startedAt.elapsedMilliseconds,
        resultText: 'status: failed\nerror: $blockReason',
        metadata: _subagentMetadata(
          subagentType: canonicalSubagentType,
          toolCount: subagentCatalog.definitions.length,
          terminalStatus: 'blocked',
          systemReminders: _hookSystemReminders(subagentStartHookResult),
          extra: <String, Object?>{
            'hook_blocked': true,
            'hook_event_name': _subagentStartEvent,
          },
        ),
      );
    }
    var totalToolCalls = 0;
    var totalToolOutputCharacters = 0;
    String boundedToolOutput(String value) {
      final remaining =
          _maxTotalToolOutputCharacters - totalToolOutputCharacters;
      if (remaining <= 0) return '[工具输出已省略：累计输出达到上限]';
      final limit = remaining < _maxToolOutputCharacters
          ? remaining
          : _maxToolOutputCharacters;
      final bounded = clipTextByCodeUnits(
        value,
        limit,
        suffix: '\n\n[工具输出已截断]',
      );
      totalToolOutputCharacters += bounded.length;
      return bounded;
    }

    for (var round = 0; round < _maxToolRounds; round++) {
      final remaining = _maxExecutionDuration - startedAt.elapsed;
      if (remaining <= Duration.zero) {
        return failedResult(
          '后台任务超过 ${_maxExecutionDuration.inMinutes} 分钟时限。',
          rounds: round,
        );
      }
      final turnTimeout = remaining < _chatTurnTimeout
          ? remaining
          : _chatTurnTimeout;
      final AiChatCompletion? completion;
      try {
        completion = await AiToolUtils.awaitWithCancellation<AiChatCompletion>(
          AiUsageTraceContext.runDerived(
            source: AiUsageSource.subagent,
            operation: 'subagent_round',
            metadata: <String, Object?>{
              'subagent_type': canonicalSubagentType,
              'round': round + 1,
            },
            body: () => _backgroundChatClient
                .sendMessage(
                  model: context.model,
                  messages: turns,
                  tools: subagentCatalog.definitions,
                  timeout: turnTimeout,
                  cancelSignal: context.cancelSignal,
                )
                .timeout(turnTimeout),
          ),
          cancelSignal: context.cancelSignal,
        );
      } catch (error, stack) {
        if (cancelled || await isCancelSignalCompleted(context.cancelSignal)) {
          return cancelledResult(round);
        }
        silentLog('ai_task_tool', '请求子智能体模型', error, stack);
        final failureMessage = error is TimeoutException
            ? '子智能体模型请求超时。'
            : '子智能体执行失败。';
        return failedResult(failureMessage, rounds: round);
      }
      if (completion == null) {
        return cancelledResult(round);
      }
      final reply = completion.reply.trim();
      if (completion.toolCalls.isEmpty) {
        final output = reply.isEmpty
            ? '后台任务已完成，但未返回额外内容。'
            : _boundedSubagentResult(reply);
        final subagentStopHookResult = await _runSubagentStopHook(
          sessionId: subagentSessionId,
          subagentType: canonicalSubagentType,
          description: description,
          status: 'completed',
        );
        return AiToolUtils.simpleSuccessResult(
          command: '$_toolName $description',
          output: output,
          durationMs: startedAt.elapsedMilliseconds,
          metadata: _subagentMetadata(
            subagentType: canonicalSubagentType,
            toolCount: subagentCatalog.definitions.length,
            rounds: round,
            terminalStatus: 'completed',
            systemReminders: _hookSystemReminders(
              subagentStartHookResult,
              subagentStopHookResult,
            ),
          ),
        );
      }
      if (completion.toolCalls.length > _maxToolCallsPerRound ||
          totalToolCalls + completion.toolCalls.length > _maxTotalToolCalls) {
        return failedResult('子智能体工具调用次数超过安全上限。', rounds: round + 1);
      }
      if (completion.toolCalls.any(
        (call) => call.arguments.length > _maxToolArgumentCharacters,
      )) {
        return failedResult('子智能体工具参数超过安全上限。', rounds: round + 1);
      }
      totalToolCalls += completion.toolCalls.length;
      turns.add(
        AiChatTurn(
          role: AiChatRole.assistant,
          content: _boundedSubagentResult(reply),
          toolCalls: completion.toolCalls,
        ),
      );
      // 通过重建的上下文调用子工具，并在每次分发前检查取消状态。
      for (var index = 0; index < completion.toolCalls.length; index++) {
        if (cancelled || await isCancelSignalCompleted(context.cancelSignal)) {
          return cancelledResult(round);
        }
        final toolCall = completion.toolCalls[index];
        final toolTimeout = _maxExecutionDuration - startedAt.elapsed;
        if (toolTimeout <= Duration.zero) {
          return failedResult(
            '后台任务超过 ${_maxExecutionDuration.inMinutes} 分钟时限。',
            rounds: round + 1,
          );
        }
        final decodedArguments = AiToolUtils.decodeArguments(
          toolCall.arguments,
        );
        final writeViolation = _subagentWriteViolation(
          catalog: subagentCatalog,
          toolCall: toolCall,
          decodedArguments: decodedArguments,
        );
        if (writeViolation != null) {
          return failedResult(
            '子智能体尝试执行写入型 Bash 命令。Task 子智能体只读，'
            '需要写入时应由父智能体执行。\n'
            '命令：${writeViolation.command}\n'
            '原因：${writeViolation.reason}',
            rounds: round + 1,
            hookError: writeViolation.reason,
            extraMetadata: <String, Object?>{
              'subagent_write_blocked': true,
              'subagent_blocked_command': writeViolation.command,
              'subagent_blocked_write_reason': writeViolation.reason,
            },
          );
        }
        final timeoutCancellation = Completer<void>();
        final subContext = AiToolExecutionContext(
          sessionId: subagentSessionId,
          catalog: subagentCatalog,
          toolCall: toolCall,
          decodedArguments: decodedArguments,
          model: context.model,
          previouslyReadFiles: readFiles,
          denyCommandRules: context.denyCommandRules,
          requireWriteCommandConfirmation:
              context.requireWriteCommandConfirmation,
          confirmWriteCommand: context.confirmWriteCommand,
          cancelSignal: combineCancelSignals(<Future<void>?>[
            context.cancelSignal,
            timeoutCancellation.future,
          ]),
          onBashUpdate: context.onBashUpdate,
          metadata: context.metadata,
        );
        // 通过注册时注入的回调执行子代理工具，避免运行时服务循环依赖。
        final AiToolExecutionResult toolResult;
        try {
          final result = await AiToolUtils.awaitWithCancellation(
            _executeSubTool(context, subContext).timeout(
              toolTimeout,
              onTimeout: () {
                if (!timeoutCancellation.isCompleted) {
                  timeoutCancellation.complete();
                }
                throw TimeoutException('子智能体工具执行超时。', toolTimeout);
              },
            ),
            cancelSignal: context.cancelSignal,
          );
          if (result == null) {
            return await cancelledResult(round);
          }
          toolResult = result;
        } catch (error, stack) {
          if (cancelled ||
              await isCancelSignalCompleted(context.cancelSignal)) {
            return cancelledResult(round);
          }
          silentLog('ai_task_tool', '执行子智能体工具', error, stack);
          final failureMessage = error is TimeoutException
              ? '子智能体工具“${toolCall.name}”执行超时。'
              : '子智能体工具“${toolCall.name}”执行失败。';
          return failedResult(failureMessage, rounds: round + 1);
        }
        final readFilePath = '${toolResult.metadata['read_file_path'] ?? ''}'
            .trim();
        if (readFilePath.isNotEmpty) readFiles.add(readFilePath);
        turns.add(
          AiChatTurn(
            role: AiChatRole.tool,
            toolCallId: toolCall.id,
            content: boundedToolOutput(toolResult.toToolOutput()),
          ),
        );
      }
    }
    return failedResult(
      '后台任务超过最大工具轮次。',
      rounds: _maxToolRounds,
      hookError: '子智能体工具轮次超过上限。',
      extraMetadata: const <String, Object?>{
        'task_tool_round_limit': _maxToolRounds,
      },
    );
  }

  // 子工具通过注入的回调交回父执行循环，避免运行时服务循环依赖。
  Future<AiToolExecutionResult> _executeSubTool(
    AiToolExecutionContext parentContext,
    AiToolExecutionContext subContext,
  ) async {
    final executor = _subToolExecutor;
    if (executor != null) return executor(parentContext, subContext);
    return AiToolUtils.invalidResult(
      subContext.toolCall.name,
      'Task 工具未配置子工具执行器。',
    );
  }

  AiSubToolExecutor? _subToolExecutor;

  /// 注入工具注册表提供的子工具执行器。
  AiTaskTool withExecutor(AiSubToolExecutor executor) {
    _subToolExecutor = executor;
    return this;
  }

  List<String> _unsupportedClaudeAgentParameters(Map<String, Object?> args) {
    final result = <String>[];
    for (final key in _unsupportedClaudeAgentParameterKeys) {
      if (!args.containsKey(key)) continue;
      final rawValue = args[key];
      if (rawValue == null) continue;
      if (rawValue is String && nullIfBlank(rawValue) == null) continue;
      result.add(key);
    }
    return result;
  }

  String _displayToolName(AiToolExecutionContext context) {
    return normalizeAsciiLookupKey(context.toolCall.name) == 'agent'
        ? 'Agent'
        : _toolName;
  }

  bool _isAllowedSubagentTool(
    AiResolvedTool tool, {
    required String subagentType,
  }) {
    if (tool.source != AiRuntimeToolSource.builtin) {
      return false;
    }
    final kind = tool.builtinKind;
    if (kind == null) {
      return false;
    }
    final allowedKinds = switch (subagentType) {
      'verify' => _verifyBuiltinKinds,
      'general-purpose' => _generalPurposeBuiltinKinds,
      _ => kAiReadOnlyBuiltinToolKinds,
    };
    return allowedKinds.contains(kind);
  }

  bool _isBlockedPlanModeSubagent({
    required Map<String, Object?> metadata,
    required String subagentType,
  }) {
    final planModeActive = metadata['plan_mode_active'] == true;
    final executionApproved =
        metadata['plan_mode_execution_approved_for_send'] == true;
    return planModeActive &&
        !executionApproved &&
        !readOnlyParallelSubagentTypes.contains(subagentType);
  }

  ({String command, String reason})? _subagentWriteViolation({
    required AiResolvedToolCatalog catalog,
    required AiToolCall toolCall,
    required Map<String, Object?> decodedArguments,
  }) {
    final resolvedTool = catalog.find(toolCall.name);
    if (resolvedTool?.builtinKind != AiBuiltinToolKind.bash) {
      return null;
    }
    final command =
        '${decodedArguments['cmd'] ?? decodedArguments['command'] ?? ''}'
            .trim();
    if (command.isEmpty) {
      return null;
    }
    final analysis = _bashWriteAnalyzer.analyzeWriteCommand(command);
    if (!analysis.isWrite) {
      return null;
    }
    return (command: command, reason: 'Bash 命令被识别为写操作。');
  }

  String _subagentSystemPrompt({
    required String subagentType,
    required String subagentProfile,
    required int toolCount,
  }) {
    final toolGuidance = toolCount <= 0
        ? 'No sub-tools are available in this invocation; answer from the provided task context only.'
        : 'Your available tools are restricted for this subagent type.';
    return 'You are a focused "$subagentType" background sub-agent for OpenHand. '
        '$subagentProfile This Task invocation is stateless and isolated from '
        'other Task calls. $toolGuidance Do not edit source files, update '
        'parent todos, open UI dialogs, call Task, or request plan approval. '
        'Complete the assigned subtask directly. Use tools only when they '
        'materially help. Return only the useful result for the parent agent.';
  }

  String _boundedSubagentResult(String value) {
    return clipTextByCodeUnits(
      value.trim(),
      _maxResultCharacters,
      suffix: '\n\n[结果已截断]',
    );
  }

  AiToolExecutionResult _failedTaskResult({
    required String description,
    required String error,
    required int durationMs,
    required String subagentType,
    required int toolCount,
    int? rounds,
    List<String> systemReminders = const <String>[],
    Map<String, Object?> extraMetadata = const <String, Object?>{},
  }) {
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: '$_toolName $description',
      workingDirectory: AiToolUtils.defaultWorkingDirectory(),
      stdout: '',
      stderr: error,
      durationMs: durationMs,
      resultText: 'status: failed\nerror: $error',
      metadata: _subagentMetadata(
        subagentType: subagentType,
        toolCount: toolCount,
        rounds: rounds,
        terminalStatus: 'failed',
        systemReminders: systemReminders,
        extra: extraMetadata,
      ),
    );
  }

  Future<AiToolExecutionResult> _cancelledTaskResult({
    required Stopwatch startedAt,
    required String description,
    required String sessionId,
    required String subagentType,
    required int toolCount,
    required int rounds,
    required AiClaudeHookInvocationResult startHookResult,
  }) async {
    final stopHookResult = await _runSubagentStopHook(
      sessionId: sessionId,
      subagentType: subagentType,
      description: description,
      status: 'cancelled',
    );
    return AiToolUtils.cancelledResult(
      command: '$_toolName $description',
      durationMs: startedAt.elapsedMilliseconds,
      metadata: _subagentMetadata(
        subagentType: subagentType,
        toolCount: toolCount,
        rounds: rounds,
        terminalStatus: 'cancelled',
        systemReminders: _hookSystemReminders(startHookResult, stopHookResult),
      ),
    );
  }

  Map<String, Object?> _subagentMetadata({
    required String subagentType,
    required int toolCount,
    int? rounds,
    String? terminalStatus,
    List<String> systemReminders = const <String>[],
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return <String, Object?>{
      'subagent_type': subagentType,
      'subagent_session_isolated': true,
      'subagent_tool_count': toolCount,
      'subagent_tools_restricted': true,
      if (rounds != null) 'task_tool_rounds': rounds,
      if (terminalStatus != null) 'subagent_terminal_status': terminalStatus,
      if (systemReminders.isNotEmpty)
        aiHookSystemRemindersMetadataKey: systemReminders,
      ...extra,
    };
  }

  List<String> _hookSystemReminders(
    AiClaudeHookInvocationResult first, [
    AiClaudeHookInvocationResult? second,
  ]) {
    return <String>[
      ...first.systemReminders,
      if (second != null) ...second.systemReminders,
    ];
  }

  String _normalizeToken(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return sanitized.isEmpty ? 'tool' : sanitized;
  }

  Future<AiClaudeHookInvocationResult> _runSubagentStopHook({
    required String sessionId,
    required String subagentType,
    required String description,
    required String status,
    String? error,
  }) {
    return _runAuxiliaryHook(
      eventName: _subagentStopEvent,
      sessionId: sessionId,
      matcherValue: subagentType,
      cwd: AiToolUtils.defaultWorkingDirectory(),
      payload: <String, Object?>{
        'subagent_type': subagentType,
        'subagentType': subagentType,
        'description': description,
        'status': status,
        'stateless': true,
        if (error != null && error.trim().isNotEmpty) 'error': error.trim(),
      },
    );
  }

  Future<AiClaudeHookInvocationResult> _runAuxiliaryHook({
    required String eventName,
    required String sessionId,
    required Map<String, Object?> payload,
    String? matcherValue,
    String? cwd,
  }) async {
    try {
      return await _hookService.runHooks(
        eventName: eventName,
        sessionId: sessionId,
        matcherValue: matcherValue,
        cwd: cwd,
        payload: payload,
      );
    } catch (error, stack) {
      silentLog('ai_task_tool', '执行 $eventName 钩子', error, stack);
      return AiClaudeHookInvocationResult(
        systemReminders: <String>['子智能体钩子“$eventName”执行失败。'],
      );
    }
  }
}

typedef AiSubToolExecutor =
    Future<AiToolExecutionResult> Function(
      AiToolExecutionContext parentContext,
      AiToolExecutionContext subContext,
    );
