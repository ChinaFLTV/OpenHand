import 'dart:async';
import 'dart:convert';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../service/bash/ai_bash_tool_service.dart';
import '../../service/chat/ai_chat_service.dart';
import '../../service/chat/ai_protocol_adapter.dart';
import '../../service/hook/ai_claude_hook_service.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

class AiTaskTool extends AiTool {
  AiTaskTool({
    required AiChatClient backgroundChatClient,
    required AiClaudeHookService hookService,
  }) : _backgroundChatClient = backgroundChatClient,
       _hookService = hookService;

  static const int _maxToolRounds = 6;
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

  static const Set<AiBuiltinToolKind> _readOnlyBuiltinKinds =
      <AiBuiltinToolKind>{
        AiBuiltinToolKind.glob,
        AiBuiltinToolKind.grep,
        AiBuiltinToolKind.ls,
        AiBuiltinToolKind.read,
        AiBuiltinToolKind.webFetch,
        AiBuiltinToolKind.webSearch,
        AiBuiltinToolKind.lsp,
        AiBuiltinToolKind.codebaseSearch,
        AiBuiltinToolKind.git,
        AiBuiltinToolKind.readLints,
      };

  static const Set<AiBuiltinToolKind> _verifyBuiltinKinds = <AiBuiltinToolKind>{
    ..._readOnlyBuiltinKinds,
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
        'Unsupported Claude Agent parameter(s): ${unsupportedClaudeAgentParameters.join(', ')}. '
        'OpenHand Task currently runs isolated foreground sub-agents only; omit these fields or use the supported subagent_type profiles.',
      );
    }
    if (description.isEmpty || prompt.isEmpty) {
      return AiToolUtils.invalidResult(
        _displayToolName(context),
        '${_displayToolName(context)} requires non-empty description and prompt.',
      );
    }
    final canonicalSubagentType = resolveSubagentTypeFromArguments(args);
    if (canonicalSubagentType == null) {
      return AiToolUtils.invalidResult(
        _displayToolName(context),
        'Unsupported subagent_type "$subagentType". Available types: ${subagentDescriptions.keys.join(', ')}',
      );
    }
    if (_isBlockedPlanModeSubagent(
      metadata: context.metadata,
      subagentType: canonicalSubagentType,
    )) {
      return AiToolUtils.withMergedMetadata(
        AiToolUtils.invalidResult(
          _toolName,
          'Plan mode before execution approval allows Task only with read-only subagent_type values: ${readOnlyParallelSubagentTypes.join(', ')}. '
          'Use a read-only subagent now, or run "$canonicalSubagentType" after the plan is approved.',
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
    // Track cancellation without awaiting the signal so we can bail early
    // between sub-tool calls. Any uncaught error on cancelSignal is ignored.
    var cancelled = false;
    context.cancelSignal?.then<void>(
      (_) => cancelled = true,
      onError: (Object _, StackTrace _) {
        cancelled = true;
      },
    );
    final subagentSessionId =
        '${context.sessionId}/task/${_normalizeToken(context.toolCall.id.trim().isEmpty ? canonicalSubagentType : context.toolCall.id)}';
    final subagentStartHookResult = await _runAuxiliaryHook(
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
    );
    if (subagentStartHookResult.blocked) {
      return AiToolExecutionResult(
        status: BashToolExecutionStatus.failed,
        command: '$_toolName $description',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr:
            subagentStartHookResult.blockReason ?? 'Blocked by subagent hook.',
        durationMs: startedAt.elapsedMilliseconds,
        resultText:
            'status: failed\nerror: ${subagentStartHookResult.blockReason ?? 'Blocked by subagent hook.'}',
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
    for (var round = 0; round < _maxToolRounds; round++) {
      final AiChatCompletion? completion;
      try {
        completion = await AiToolUtils.awaitWithCancellation<AiChatCompletion>(
          _backgroundChatClient.sendMessage(
            model: context.model,
            messages: turns,
            tools: subagentCatalog.definitions,
          ),
          cancelSignal: context.cancelSignal,
        );
      } catch (error, stack) {
        silentLog('ai_task_tool', 'send subagent completion', error, stack);
        final subagentStopHookResult = await _runSubagentStopHook(
          sessionId: subagentSessionId,
          subagentType: canonicalSubagentType,
          description: description,
          status: 'failed',
          error: '$error',
        );
        return _failedTaskResult(
          description: description,
          error: 'Background sub-agent failed: $error',
          durationMs: startedAt.elapsedMilliseconds,
          subagentType: canonicalSubagentType,
          toolCount: subagentCatalog.definitions.length,
          rounds: round,
          systemReminders: _hookSystemReminders(
            subagentStartHookResult,
            subagentStopHookResult,
          ),
        );
      }
      if (completion == null) {
        final subagentStopHookResult = await _runSubagentStopHook(
          sessionId: subagentSessionId,
          subagentType: canonicalSubagentType,
          description: description,
          status: 'cancelled',
        );
        return AiToolUtils.cancelledResult(
          command: '$_toolName $description',
          durationMs: startedAt.elapsedMilliseconds,
          metadata: _subagentMetadata(
            subagentType: canonicalSubagentType,
            toolCount: subagentCatalog.definitions.length,
            rounds: round,
            terminalStatus: 'cancelled',
            systemReminders: _hookSystemReminders(
              subagentStartHookResult,
              subagentStopHookResult,
            ),
          ),
        );
      }
      final reply = completion.reply.trim();
      if (completion.toolCalls.isEmpty) {
        final output = reply.isEmpty
            ? 'The background task completed without additional output.'
            : reply;
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
      turns.add(
        AiChatTurn(
          role: AiChatRole.assistant,
          content: reply,
          toolCalls: completion.toolCalls,
        ),
      );
      // Delegate sub-tool calls via a re-assembled context
      for (var index = 0; index < completion.toolCalls.length; index++) {
        // Honor cancellation between sub-tool calls so that a user cancel
        // after the first tool in a batch does not keep dispatching the
        // remaining tools.
        if (cancelled) {
          final subagentStopHookResult = await _runSubagentStopHook(
            sessionId: subagentSessionId,
            subagentType: canonicalSubagentType,
            description: description,
            status: 'cancelled',
          );
          return AiToolUtils.cancelledResult(
            command: '$_toolName $description',
            durationMs: startedAt.elapsedMilliseconds,
            metadata: _subagentMetadata(
              subagentType: canonicalSubagentType,
              toolCount: subagentCatalog.definitions.length,
              rounds: round,
              terminalStatus: 'cancelled',
              systemReminders: _hookSystemReminders(
                subagentStartHookResult,
                subagentStopHookResult,
              ),
            ),
          );
        }
        final toolCall = completion.toolCalls[index];
        final decodedArguments = _decodeArguments(toolCall.arguments);
        final writeViolation = _subagentWriteViolation(
          catalog: subagentCatalog,
          toolCall: toolCall,
          decodedArguments: decodedArguments,
        );
        if (writeViolation != null) {
          final subagentStopHookResult = await _runSubagentStopHook(
            sessionId: subagentSessionId,
            subagentType: canonicalSubagentType,
            description: description,
            status: 'failed',
            error: writeViolation.reason,
          );
          return _failedTaskResult(
            description: description,
            error:
                'Sub-agent attempted a write-like Bash command. '
                'Task sub-agents are read-only; the parent agent must run '
                'write commands itself when appropriate.\n'
                'command: ${writeViolation.command}\n'
                'reason: ${writeViolation.reason}',
            durationMs: startedAt.elapsedMilliseconds,
            subagentType: canonicalSubagentType,
            toolCount: subagentCatalog.definitions.length,
            rounds: round + 1,
            systemReminders: _hookSystemReminders(
              subagentStartHookResult,
              subagentStopHookResult,
            ),
            extraMetadata: <String, Object?>{
              'subagent_write_blocked': true,
              'subagent_blocked_command': writeViolation.command,
              'subagent_blocked_write_reason': writeViolation.reason,
            },
          );
        }
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
          cancelSignal: context.cancelSignal,
          metadata: context.metadata,
        );
        // NOTE: subagent tool execution is dispatched back through AiToolRuntimeService
        // via a provided callback to avoid circular dependency. The callback is injected
        // at registration time by AiToolRegistry.withServiceDependencies().
        final AiToolExecutionResult toolResult;
        try {
          toolResult = await _executeSubTool(context, subContext);
        } catch (error, stack) {
          silentLog('ai_task_tool', 'execute subagent tool', error, stack);
          final subagentStopHookResult = await _runSubagentStopHook(
            sessionId: subagentSessionId,
            subagentType: canonicalSubagentType,
            description: description,
            status: 'failed',
            error: '$error',
          );
          return _failedTaskResult(
            description: description,
            error: 'Sub-agent tool "${toolCall.name}" failed: $error',
            durationMs: startedAt.elapsedMilliseconds,
            subagentType: canonicalSubagentType,
            toolCount: subagentCatalog.definitions.length,
            rounds: round + 1,
            systemReminders: _hookSystemReminders(
              subagentStartHookResult,
              subagentStopHookResult,
            ),
          );
        }
        final readFilePath = '${toolResult.metadata['read_file_path'] ?? ''}'
            .trim();
        if (readFilePath.isNotEmpty) readFiles.add(readFilePath);
        turns.add(
          AiChatTurn(
            role: AiChatRole.tool,
            toolCallId: toolCall.id,
            content: toolResult.toToolOutput(),
          ),
        );
      }
    }
    final subagentStopHookResult = await _runSubagentStopHook(
      sessionId: subagentSessionId,
      subagentType: canonicalSubagentType,
      description: description,
      status: 'failed',
      error: 'Exceeded the maximum tool rounds.',
    );
    return _failedTaskResult(
      description: description,
      error: 'The background task exceeded the maximum tool rounds.',
      durationMs: startedAt.elapsedMilliseconds,
      subagentType: canonicalSubagentType,
      toolCount: subagentCatalog.definitions.length,
      rounds: _maxToolRounds,
      systemReminders: _hookSystemReminders(
        subagentStartHookResult,
        subagentStopHookResult,
      ),
      extraMetadata: const <String, Object?>{
        'task_tool_round_limit': _maxToolRounds,
      },
    );
  }

  // Sub-tool execution delegates back to the parent execute loop.
  // This is satisfied by a callback injected in AiTaskTool.withExecutor().
  Future<AiToolExecutionResult> _executeSubTool(
    AiToolExecutionContext parentContext,
    AiToolExecutionContext subContext,
  ) async {
    final executor = _subToolExecutor;
    if (executor != null) return executor(parentContext, subContext);
    // Fallback: only works for non-recursive tools; Task subtasks are rare edge case.
    return AiToolUtils.invalidResult(
      subContext.toolCall.name,
      'Sub-tool executor not configured for Task tool.',
    );
  }

  AiSubToolExecutor? _subToolExecutor;

  /// Factory-style setExecutor for AiToolRegistry injection.
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
    return _normalizedToolCallName(context.toolCall.name) == 'agent'
        ? 'Agent'
        : _toolName;
  }

  String _normalizedToolCallName(String value) {
    final buffer = StringBuffer();
    for (final code in value.codeUnits) {
      if ((code >= 0x30 && code <= 0x39) ||
          (code >= 0x41 && code <= 0x5A) ||
          (code >= 0x61 && code <= 0x7A)) {
        buffer.writeCharCode(code | 0x20);
      }
    }
    return buffer.toString();
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
      _ => _readOnlyBuiltinKinds,
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
    return (command: command, reason: analysis.reason);
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

  Map<String, Object?> _decodeArguments(String rawArguments) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map) return stringKeyedMapFromValue(decoded);
    } catch (error, stack) {
      silentLog('ai_task_tool', 'decode task tool arguments', error, stack);
    }
    return const <String, Object?>{};
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
    } catch (error) {
      return AiClaudeHookInvocationResult(
        systemReminders: <String>['Hook event $eventName failed: $error'],
      );
    }
  }
}

typedef AiSubToolExecutor =
    Future<AiToolExecutionResult> Function(
      AiToolExecutionContext parentContext,
      AiToolExecutionContext subContext,
    );
