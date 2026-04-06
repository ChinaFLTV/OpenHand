import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../ai/model/ai_deny_command_rule.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/model/ai_session_runtime_context.dart';
import '../ai/service/ai_chat_service.dart';
import '../ai/service/ai_prompt_template_repository.dart';
import '../ai/service/ai_protocol_adapter.dart';
import '../ai/service/ai_tool_runtime_service.dart';
import 'hardness_orchestrator.dart';
import 'model/hardness_phase.dart';

/// Result of a single API-based Hardness phase execution.
class HardnessApiPhaseResult {
  const HardnessApiPhaseResult({
    required this.success,
    required this.outputLines,
    this.changedFiles = const <HardnessChangedFile>[],
    this.errorMessage,
  });

  final bool success;
  final List<String> outputLines;
  final List<HardnessChangedFile> changedFiles;
  final String? errorMessage;
}

/// Executes a single Hardness Engineering phase using an API-based model
/// (URL mode) instead of a CLI tool. This bridges the gap between the
/// Hardness phase orchestration protocol and the standard AI session
/// infrastructure (chat service, protocol adapters, tool runtime, MCP,
/// memory, skills).
///
/// The runner performs an iterative agentic loop:
///   1. Send the phase prompt + tool catalog to the model
///   2. Parse the response for text and tool calls
///   3. Execute tool calls (file I/O, bash, MCP, skills)
///   4. Feed tool results back to the model
///   5. Repeat until the model returns only text (no tool calls)
///      or the round limit is reached
class HardnessApiPhaseRunner {
  HardnessApiPhaseRunner({
    required AiChatClient chatClient,
    required AiToolRuntimeService toolRuntimeService,
    required AiPromptTemplateRepository templateRepository,
  }) : _chatClient = chatClient,
       _toolRuntimeService = toolRuntimeService,
       _templateRepository = templateRepository;

  final AiChatClient _chatClient;
  final AiToolRuntimeService _toolRuntimeService;
  final AiPromptTemplateRepository _templateRepository;

  /// Rough characters-per-token estimate for context size tracking.
  static const int _estimatedCharsPerToken = 4;

  /// Reserve tokens for the model's response.
  static const int _responseReserveTokens = 4096;

  /// Minimum conversation turns to keep (system + user + at least 1 exchange).
  static const int _minConversationTurns = 4;

  /// Executes a hardness phase via API call with full tool loop.
  ///
  /// [model] is the AiModelConfig from settings.
  /// [phasePrompt] is the full phase prompt built by the orchestrator.
  /// [phase] identifies the execution phase for constraint enforcement.
  /// [runtimeContext] provides memory, skills, MCP, and environment.
  /// [onLine] streams output lines for real-time display.
  /// [cancelSignal] can be used to abort the execution.
  Future<HardnessApiPhaseResult> runPhase({
    required AiModelConfig model,
    required HardnessPhase phase,
    required String phasePrompt,
    required AiSessionRuntimeContext runtimeContext,
    required void Function(String line) onLine,
    Future<void>? cancelSignal,
  }) async {
    final outputLines = <String>[];
    void emit(String line) {
      outputLines.add(line);
      onLine(line);
    }

    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    final supportsTools = adapter.supportsToolCalls;

    // Resolve tool catalog (builtin + MCP + skills) — same as default thread.
    final toolCatalog = supportsTools
        ? await _toolRuntimeService.resolveCatalog(
            runtimeContext: runtimeContext,
          )
        : const AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[],
            toolsByName: <String, AiResolvedTool>{},
          );

    // Filter tools based on phase constraints.
    final phaseToolCatalog = _filterToolsForPhase(
      phase: phase,
      baseCatalog: toolCatalog,
    );

    if (toolCatalog.notices.isNotEmpty) {
      for (final notice in toolCatalog.notices) {
        emit('ℹ $notice');
      }
      emit('');
    }

    // Load the HE template bundle for system/developer instructions.
    final templateBundle = await _templateRepository.loadBundle(
      'hardness_engineering',
    );

    // Build conversation context.
    final systemContent = StringBuffer()
      ..writeln('# [0] System Instructions')
      ..writeln()
      ..writeln(templateBundle.systemInstructions)
      ..writeln()
      ..writeln('# [1] Developer Instructions')
      ..writeln()
      ..writeln(templateBundle.developerInstructions)
      ..writeln()
      ..writeln('# Runtime Environment')
      ..writeln()
      ..writeln('Working directory: ${runtimeContext.workingDirectory}')
      ..writeln('Platform: ${runtimeContext.platformName}')
      ..writeln('Today: ${runtimeContext.todayLocalDate}')
      ..writeln('Time zone: ${runtimeContext.timeZoneName}');

    // Inject memory if enabled.
    if (runtimeContext.memoryEnabled && runtimeContext.memoryEntries.isNotEmpty) {
      systemContent
        ..writeln()
        ..writeln('# User Memory (long-term facts)')
        ..writeln();
      for (final entry in runtimeContext.memoryEntries) {
        systemContent.writeln('- ${entry.preview}');
      }
    }

    // Available tool catalog description for the model.
    if (phaseToolCatalog.definitions.isNotEmpty) {
      systemContent
        ..writeln()
        ..writeln('# Available Tools')
        ..writeln()
        ..writeln(
          'You have ${phaseToolCatalog.definitions.length} tools available. '
          'Use them to complete your assigned phase task.',
        );
    }

    final conversation = <AiChatTurn>[
      AiChatTurn(
        role: AiChatRole.system,
        content: systemContent.toString(),
      ),
      AiChatTurn(
        role: AiChatRole.user,
        content: phasePrompt,
      ),
    ];

    // Agentic tool loop — mirrors AiSessionController._runAssistantConversation.
    final maxToolRounds = math.max(1, runtimeContext.sequentialToolRoundLimit);
    final maxToolCallsPerRound = math.max(
      1,
      runtimeContext.singleRoundToolCallLimit,
    );
    final contextWindowTokens = (model.maxContextTokens ?? 0) > 0
        ? model.maxContextTokens!
        : 128000; // sensible default
    var toolRound = 0;
    final previouslyReadFiles = <String>{};
    // Phase-specific deny rules: read-only phases should not allow file writes.
    final denyRules = _denyRulesForPhase(phase);

    try {
      while (true) {
        // Check cancellation.
        if (cancelSignal != null) {
          try {
            await cancelSignal.timeout(Duration.zero);
            // If the signal has already completed, we're cancelled.
            emit('');
            emit('⚠ 已中止');
            return HardnessApiPhaseResult(
              success: false,
              outputLines: outputLines,
              errorMessage: '执行被用户中止。',
            );
          } on TimeoutException {
            // Not yet cancelled — continue.
          }
        }

        // Trim conversation history if approaching context window limit.
        _trimConversationIfNeeded(
          conversation,
          contextWindowTokens: contextWindowTokens,
        );

        // Send API request.
        final AiChatCompletion completion;
        try {
          completion = await _chatClient.sendMessage(
            model: model,
            messages: conversation,
            tools: phaseToolCatalog.definitions,
            timeout: const Duration(minutes: 10),
          );
        } catch (e) {
          final safeError = _sanitizeError('$e', model);
          emit('');
          emit('✗ API 请求失败：$safeError');
          return HardnessApiPhaseResult(
            success: false,
            outputLines: outputLines,
            errorMessage: 'API 请求失败：$safeError',
          );
        }

        // Emit the model's text reply.
        final reply = completion.reply.trim();
        if (reply.isNotEmpty) {
          for (final line in reply.split('\n')) {
            emit(line);
          }
        }

        final toolCalls = completion.toolCalls;

        // No tool calls → phase complete.
        if (toolCalls.isEmpty) {
          break;
        }

        // Round limit check.
        toolRound++;
        if (toolRound > maxToolRounds) {
          emit('');
          emit('ℹ 已达到最大工具轮次限制（$maxToolRounds），停止工具调用循环。');
          break;
        }

        // Add assistant message (text + tool calls) to conversation.
        conversation.add(AiChatTurn(
          role: AiChatRole.assistant,
          content: reply,
          toolCalls: toolCalls,
        ));

        // Execute tool calls.
        final effectiveToolCalls = toolCalls.length > maxToolCallsPerRound
            ? toolCalls.sublist(0, maxToolCallsPerRound)
            : toolCalls;

        for (final toolCall in effectiveToolCalls) {
          emit('');
          emit('⚙ 工具调用：${toolCall.name}');

          final result = await _toolRuntimeService.execute(
            sessionId: 'hardness-phase-${phase.storageValue}',
            catalog: phaseToolCatalog,
            toolCall: toolCall,
            model: model,
            previouslyReadFiles: previouslyReadFiles,
            denyCommandRules: denyRules,
            requireWriteCommandConfirmation: false,
            confirmWriteCommand: null,
            cancelSignal: cancelSignal,
          );

          // Track read files for deduplication.
          if (toolCall.name.toLowerCase().contains('read')) {
            final args = _tryDecodeJsonMap(toolCall.arguments);
            final filePath = args['file_path'] ?? args['path'];
            if (filePath is String && filePath.isNotEmpty) {
              previouslyReadFiles.add(filePath);
            }
          }

          final toolOutput = result.toToolOutput();
          // Show abbreviated tool output in the log.
          final outputPreview = toolOutput.length > 500
              ? '${toolOutput.substring(0, 500)}… (${toolOutput.length} chars)'
              : toolOutput;
          if (outputPreview.isNotEmpty) {
            for (final line in outputPreview.split('\n')) {
              emit('  $line');
            }
          }

          // Add tool result to conversation.
          conversation.add(AiChatTurn(
            role: AiChatRole.tool,
            content: toolOutput,
            toolCallId: toolCall.id,
          ));
        }

        // If we had to truncate tool calls, note the excess.
        if (toolCalls.length > maxToolCallsPerRound) {
          final skipped = toolCalls.length - maxToolCallsPerRound;
          emit('');
          emit('ℹ 跳过 $skipped 个超出单轮限制的工具调用。');
          // Add error results for skipped tool calls.
          for (var i = maxToolCallsPerRound; i < toolCalls.length; i++) {
            conversation.add(AiChatTurn(
              role: AiChatRole.tool,
              content: 'Tool call skipped: per-round tool call limit reached.',
              toolCallId: toolCalls[i].id,
            ));
          }
        }
      }
    } catch (e, st) {
      final safeError = _sanitizeError('$e', model);
      debugPrint('HardnessApiPhaseRunner error: $safeError');
      debugPrint('Stack trace: $st');
      emit('');
      emit('✗ 执行错误：$safeError');
      return HardnessApiPhaseResult(
        success: false,
        outputLines: outputLines,
        errorMessage: safeError,
      );
    }

    // If no meaningful output was produced, treat as failure.
    final hasSubstantiveOutput = outputLines.any((line) {
      final trimmed = line.trim();
      return trimmed.isNotEmpty &&
          !trimmed.startsWith('ℹ ') &&
          !trimmed.startsWith('⚙ ') &&
          !trimmed.startsWith('⚠ ');
    });

    if (!hasSubstantiveOutput) {
      emit('');
      emit('✗ API 会话未产生有效输出。请检查模型配置与 API 连接状态。');
      return HardnessApiPhaseResult(
        success: false,
        outputLines: outputLines,
        errorMessage: 'API 会话未产生有效输出。',
      );
    }

    return HardnessApiPhaseResult(
      success: true,
      outputLines: outputLines,
    );
  }

  /// Filters the tool catalog based on phase constraints.
  /// Read-only phases (reading, planning, reviewing, metaCollection) exclude
  /// file-writing tools to prevent premature implementation.
  AiResolvedToolCatalog _filterToolsForPhase({
    required HardnessPhase phase,
    required AiResolvedToolCatalog baseCatalog,
  }) {
    // Implementing phase gets full tool access.
    if (phase == HardnessPhase.implementing) {
      return baseCatalog;
    }

    // Other phases only get read-only tools + bash (with deny rules for writes).
    final readOnlyExcludeBuiltins = <AiBuiltinToolKind>{
      AiBuiltinToolKind.edit,
      AiBuiltinToolKind.multiEdit,
      AiBuiltinToolKind.write,
      AiBuiltinToolKind.notebookEdit,
    };

    final filteredDefinitions = <AiToolDefinition>[];
    final filteredToolsByName = <String, AiResolvedTool>{};

    for (final entry in baseCatalog.toolsByName.entries) {
      final tool = entry.value;
      if (tool.source == AiRuntimeToolSource.builtin &&
          readOnlyExcludeBuiltins.contains(tool.builtinKind)) {
        continue;
      }
      filteredToolsByName[entry.key] = tool;
      filteredDefinitions.add(tool.definition);
    }

    return AiResolvedToolCatalog(
      definitions: filteredDefinitions,
      toolsByName: filteredToolsByName,
      notices: baseCatalog.notices,
    );
  }

  /// Returns deny rules appropriate for the phase.
  /// Read-only phases deny all write-like bash commands.
  List<AiDenyCommandRule> _denyRulesForPhase(HardnessPhase phase) {
    if (phase == HardnessPhase.implementing) {
      return const <AiDenyCommandRule>[];
    }
    // Read-only phases: deny file-modifying commands.
    return const <AiDenyCommandRule>[
      AiDenyCommandRule(
        id: 'hardness_readonly_phase',
        pattern: r'^(rm|mv|cp|mkdir|touch|chmod|chown|ln|install|make|cmake|gradle|cargo|go build|npm run|yarn|pnpm|flutter build)',
        matchMode: AiDenyCommandMatchMode.regex,
        note: '当前阶段为只读阶段，不允许执行修改文件系统的命令。',
      ),
    ];
  }

  /// Sanitizes an error message by masking any auth tokens or API keys that
  /// might have leaked into error strings (e.g. from HTTP 401 responses).
  String _sanitizeError(String raw, AiModelConfig model) {
    var sanitized = raw;
    final token = model.token;
    if (token.isNotEmpty && token.length >= 8) {
      sanitized = sanitized.replaceAll(token, '****');
    }
    // Mask query params that might contain keys (e.g. ?key=...).
    sanitized = sanitized.replaceAll(
      RegExp(r'[?&](key|token|api_key|apikey|access_token)=[^&\s]+',
          caseSensitive: false),
      '',
    );
    return sanitized;
  }

  /// Estimates the total token count of the conversation.
  int _estimateConversationTokens(List<AiChatTurn> conversation) {
    var totalChars = 0;
    for (final turn in conversation) {
      totalChars += turn.content.length;
      for (final tc in turn.toolCalls) {
        totalChars += tc.name.length + tc.arguments.length;
      }
    }
    return totalChars ~/ _estimatedCharsPerToken;
  }

  /// Trims old conversation turns (keeping system + initial user message) if
  /// the estimated context size exceeds the model's context window.
  void _trimConversationIfNeeded(
    List<AiChatTurn> conversation, {
    required int contextWindowTokens,
  }) {
    if (conversation.length <= _minConversationTurns) return;
    final budget = contextWindowTokens - _responseReserveTokens;
    if (budget <= 0) return;

    var estimatedTokens = _estimateConversationTokens(conversation);
    if (estimatedTokens <= budget) return;

    // Remove turns from the middle (after system + user, before the last
    // exchange) until we're under budget.
    // Keep: [0]=system, [1]=user, ... last 2 turns (latest exchange).
    while (conversation.length > _minConversationTurns &&
        estimatedTokens > budget) {
      // Remove the oldest mid-conversation turn (index 2).
      final removed = conversation.removeAt(2);
      var removedChars = removed.content.length;
      for (final tc in removed.toolCalls) {
        removedChars += tc.name.length + tc.arguments.length;
      }
      estimatedTokens -= removedChars ~/ _estimatedCharsPerToken;
    }
  }

  Map<String, dynamic> _tryDecodeJsonMap(String raw) {
    try {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed == '{}') {
        return const <String, dynamic>{};
      }
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const <String, dynamic>{};
  }
}
