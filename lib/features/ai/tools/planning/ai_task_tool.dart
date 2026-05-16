import 'dart:async';
import 'dart:convert';

import '../../../../app/support/silent_log.dart';
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

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.task;

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final args = context.decodedArguments;
    final startedAt = Stopwatch()..start();
    final description = '${args['description'] ?? ''}'.trim();
    final prompt = '${args['prompt'] ?? ''}'.trim();
    final subagentType = '${args['subagent_type'] ?? ''}'.trim();
    if (description.isEmpty || prompt.isEmpty || subagentType.isEmpty) {
      return AiToolUtils.invalidResult(
        'Task',
        'Task requires description, prompt, and subagent_type.',
      );
    }
    final canonicalSubagentType = _canonical(subagentType);
    if (canonicalSubagentType == null) {
      return AiToolUtils.invalidResult(
        'Task',
        'Unsupported subagent_type "$subagentType". Available types: ${subagentDescriptions.keys.join(', ')}',
      );
    }
    final subagentProfile =
        subagentDescriptions[canonicalSubagentType] ??
        'Focused background agent.';
    final subagentToolEntries = context.catalog.toolsByName.entries
        .where(
          (entry) =>
              entry.key != 'Task' &&
              entry.key != 'ExitPlanMode' &&
              entry.key != 'bash',
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
        content:
            'You are a focused "$canonicalSubagentType" background sub-agent for OpenHand. $subagentProfile This Task invocation is stateless and isolated from other Task calls. Complete the assigned subtask directly. Use tools when they materially help. Do not call Task or ExitPlanMode. Return only the useful result for the parent agent.',
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
    final subagentStartHookResult = await _hookService.runHooks(
      eventName: 'SubagentStart',
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
        command: 'Task $description',
        workingDirectory: AiToolUtils.defaultWorkingDirectory(),
        stdout: '',
        stderr:
            subagentStartHookResult.blockReason ?? 'Blocked by subagent hook.',
        durationMs: startedAt.elapsedMilliseconds,
        resultText:
            'status: failed\nerror: ${subagentStartHookResult.blockReason ?? 'Blocked by subagent hook.'}',
        metadata: <String, Object?>{
          'subagent_type': canonicalSubagentType,
          'subagent_session_isolated': true,
          'hook_blocked': true,
          'hook_event_name': 'SubagentStart',
          if (subagentStartHookResult.systemReminders.isNotEmpty)
            aiHookSystemRemindersMetadataKey:
                subagentStartHookResult.systemReminders,
        },
      );
    }
    for (var round = 0; round < 6; round++) {
      final completion =
          await AiToolUtils.awaitWithCancellation<AiChatCompletion>(
            _backgroundChatClient.sendMessage(
              model: context.model,
              messages: turns,
              tools: subagentCatalog.definitions,
            ),
            cancelSignal: context.cancelSignal,
          );
      if (completion == null) {
        return AiToolUtils.cancelledResult(
          command: 'Task $description',
          durationMs: startedAt.elapsedMilliseconds,
          metadata: <String, Object?>{
            'subagent_type': canonicalSubagentType,
            'subagent_session_isolated': true,
          },
        );
      }
      final reply = completion.reply.trim();
      if (completion.toolCalls.isEmpty) {
        final output = reply.isEmpty
            ? 'The background task completed without additional output.'
            : reply;
        final subagentStopHookResult = await _runAuxiliaryHook(
          eventName: 'SubagentStop',
          sessionId: subagentSessionId,
          matcherValue: canonicalSubagentType,
          cwd: AiToolUtils.defaultWorkingDirectory(),
          payload: <String, Object?>{
            'subagent_type': canonicalSubagentType,
            'subagentType': canonicalSubagentType,
            'description': description,
            'status': 'completed',
            'stateless': true,
          },
        );
        return AiToolUtils.simpleSuccessResult(
          command: 'Task $description',
          output: output,
          durationMs: startedAt.elapsedMilliseconds,
          metadata: <String, Object?>{
            'subagent_type': canonicalSubagentType,
            'subagent_session_isolated': true,
            'task_tool_rounds': round,
            if (subagentStartHookResult.systemReminders.isNotEmpty ||
                subagentStopHookResult.systemReminders.isNotEmpty)
              aiHookSystemRemindersMetadataKey: <String>[
                ...subagentStartHookResult.systemReminders,
                ...subagentStopHookResult.systemReminders,
              ],
          },
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
          return AiToolUtils.cancelledResult(
            command: 'Task $description',
            durationMs: startedAt.elapsedMilliseconds,
            metadata: <String, Object?>{
              'subagent_type': canonicalSubagentType,
              'subagent_session_isolated': true,
            },
          );
        }
        final toolCall = completion.toolCalls[index];
        final subContext = AiToolExecutionContext(
          sessionId: subagentSessionId,
          catalog: subagentCatalog,
          toolCall: toolCall,
          decodedArguments: _decodeArguments(toolCall.arguments),
          model: context.model,
          previouslyReadFiles: readFiles,
          denyCommandRules: context.denyCommandRules,
          requireWriteCommandConfirmation:
              context.requireWriteCommandConfirmation,
          confirmWriteCommand: context.confirmWriteCommand,
          cancelSignal: context.cancelSignal,
        );
        // NOTE: subagent tool execution is dispatched back through AiToolRuntimeService
        // via a provided callback to avoid circular dependency. The callback is injected
        // at registration time by AiToolRegistry.withServiceDependencies().
        final toolResult = await _executeSubTool(context, subContext);
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
    return AiToolExecutionResult(
      status: BashToolExecutionStatus.failed,
      command: 'Task $description',
      workingDirectory: AiToolUtils.defaultWorkingDirectory(),
      stdout: '',
      stderr: 'The background task exceeded the maximum tool rounds.',
      durationMs: startedAt.elapsedMilliseconds,
      resultText:
          'status: failed\nerror: The background task exceeded the maximum tool rounds.',
      metadata: <String, Object?>{
        'subagent_type': canonicalSubagentType,
        'subagent_session_isolated': true,
        if (subagentStartHookResult.systemReminders.isNotEmpty)
          aiHookSystemRemindersMetadataKey:
              subagentStartHookResult.systemReminders,
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

  String? _canonical(String rawType) {
    final normalized = rawType.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    return subagentDescriptions.containsKey(normalized) ? normalized : null;
  }

  Map<String, Object?> _decodeArguments(String rawArguments) {
    try {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) return Map<String, Object?>.from(decoded);
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
