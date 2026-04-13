import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../ai/model/ai_deny_command_rule.dart';
import '../ai/model/ai_model_config.dart';
import '../ai/model/ai_session_runtime_context.dart';
import '../ai/service/ai_chat_service.dart';
import '../ai/service/ai_prompt_template_repository.dart';
import '../ai/service/ai_protocol_adapter.dart';
import '../ai/service/ai_tool_runtime_service.dart';
import 'hardness_orchestrator.dart';
import 'hardness_prompt_builder.dart';
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
///
/// When the conversation context approaches the compression threshold,
/// instead of discarding middle turns (as the default thread does), the
/// runner generates a structured **handoff document**, persists it to
/// the steering/handoff directory, then starts a **new session** with the
/// handoff document injected as context — enabling seamless relay
/// execution across context windows.
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

  /// Handoff session counter for unique naming.
  int _handoffSessionCounter = 0;

  /// Executes a hardness phase via API call with full tool loop.
  ///
  /// [model] is the AiModelConfig from settings.
  /// [phasePrompt] is the full phase prompt built by the orchestrator.
  /// [phase] identifies the execution phase for constraint enforcement.
  /// [runtimeContext] provides memory, skills, MCP, and environment.
  /// [persistenceDirectory] is the session persistence root for handoff docs.
  /// [onLine] streams output lines for real-time display.
  /// [cancelSignal] can be used to abort the execution.
  Future<HardnessApiPhaseResult> runPhase({
    required AiModelConfig model,
    required HardnessPhase phase,
    required String phasePrompt,
    required AiSessionRuntimeContext runtimeContext,
    required String persistenceDirectory,
    required void Function(String line) onLine,
    Future<void>? cancelSignal,
  }) async {
    _handoffSessionCounter = 0;
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

    // Filter tools based on phase constraints using HE-specific affinity.
    final phaseToolCatalog = hardnessPromptBuilder.filterToolsForPhase(
      phase: phase,
      catalog: toolCatalog,
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

    // Build conversation context with HE-optimized structure.
    final systemContent = StringBuffer()
      ..writeln('# [0] System Instructions')
      ..writeln()
      ..writeln(templateBundle.systemInstructions)
      ..writeln()
      ..writeln('# [1] Developer Instructions')
      ..writeln()
      ..writeln(templateBundle.developerInstructions)
      ..writeln()
      ..writeln('# 运行时环境')
      ..writeln()
      ..writeln('工作目录：${runtimeContext.workingDirectory}')
      ..writeln('平台：${runtimeContext.platformName}')
      ..writeln('日期：${runtimeContext.todayLocalDate}')
      ..writeln('时区：${runtimeContext.timeZoneName}');

    // Inject memory if enabled.
    if (runtimeContext.memoryEnabled && runtimeContext.memoryEntries.isNotEmpty) {
      systemContent
        ..writeln()
        ..writeln('# 用户记忆')
        ..writeln();
      for (final entry in runtimeContext.memoryEntries) {
        systemContent.writeln('- ${entry.preview}');
      }
    }

    // Render compressed tool catalog for HE phases.
    if (phaseToolCatalog.definitions.isNotEmpty) {
      systemContent
        ..writeln()
        ..writeln(hardnessPromptBuilder.renderCompactToolCatalog(
          tools: phaseToolCatalog.definitions,
          phase: phase,
        ));
    }

    // Inject compact XML tool instructions only if the model doesn't
    // support native tool calls (e.g., CLI mode fallback).
    if (hardnessPromptBuilder.shouldInjectXmlInstructions(adapter)) {
      systemContent
        ..writeln()
        ..writeln(hardnessPromptBuilder.compactXmlToolInstructions);
    }

    // ── Reviewer isolation reinforcement ──────────────────────────────────
    // When executing the reviewing phase via API, inject an explicit
    // isolation statement into the system prompt to combat self-evaluation
    // bias (the model reviewing its own work tends to score higher).
    if (phase == HardnessPhase.reviewing) {
      systemContent
        ..writeln()
        ..writeln('# 代理隔离声明')
        ..writeln()
        ..writeln(
          '你正在作为 **独立的验收代理** 运行。'
          '本会话与实施代理 **没有任何共享状态**。'
          '你必须仅基于执行计划、原始需求和代码库的真实状态进行评估。'
          '**不要假设任何实施步骤已正确完成** — 请逐一独立验证。',
        );
    }

    // Inject workspace instruction documents (same as default thread).
    if (runtimeContext.workspaceInstructionDocuments.isNotEmpty) {
      systemContent
        ..writeln()
        ..writeln('# Workspace Instructions')
        ..writeln();
      for (final doc in runtimeContext.workspaceInstructionDocuments) {
        systemContent
          ..writeln('## ${doc.name}')
          ..writeln(doc.content)
          ..writeln();
      }
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
    // Use a unique session ID for each phase execution. For the reviewing
    // phase, append a random suffix to guarantee full isolation from any
    // prior implementing phase — preventing implicit state leakage that
    // could lead to self-evaluation bias.
    final phaseSessionId = phase == HardnessPhase.reviewing
        ? 'hardness-reviewer-isolated-${DateTime.now().millisecondsSinceEpoch}'
        : 'hardness-phase-${phase.storageValue}';

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

        // Handoff if approaching context window limit: generate a handoff
        // document and restart the session instead of simple truncation.
        final handoffResult = await _handoffIfNeeded(
          conversation,
          model: model,
          phase: phase,
          phasePrompt: phasePrompt,
          runtimeContext: runtimeContext,
          persistenceDirectory: persistenceDirectory,
          contextWindowTokens: contextWindowTokens,
          systemContent: systemContent.toString(),
          emit: emit,
          cancelSignal: cancelSignal,
        );
        if (handoffResult != null) {
          // Replace conversation with fresh session seeded with handoff.
          conversation
            ..clear()
            ..addAll(handoffResult);
        }

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
        // When the model provides native tool_calls alongside inline XML,
        // strip the duplicate XML.  When native tool_calls is empty but
        // the text contains <tool_calls> XML, parse the XML to recover
        // the tool calls instead of discarding them.
        var toolCalls = completion.toolCalls;
        String reply;
        if (toolCalls.isNotEmpty) {
          // Native tool calls present — strip duplicate XML from text.
          reply = _stripInlineToolCallsXml(completion.reply.trim());
        } else {
          // No native tool calls — try parsing XML tool calls from text.
          final rawReply = completion.reply.trim();
          final parsedXmlCalls = _parseXmlToolCalls(rawReply);
          if (parsedXmlCalls.isNotEmpty) {
            toolCalls = parsedXmlCalls;
            reply = _stripInlineToolCallsXml(rawReply);
            emit('');
            emit('ℹ 从模型文本回复中解析出 ${parsedXmlCalls.length} 个 XML 工具调用。');
          } else {
            reply = rawReply;
          }
        }

        if (reply.isNotEmpty) {
          // Emit a role marker before the reply so the sub-conversation
          // parser creates a separate card instead of merging the reply
          // into the previous tool-call segment.
          if (toolRound > 0) {
            emit('');
            emit('assistant');
          }
          for (final line in reply.split('\n')) {
            emit(line);
          }
        }

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

          // Emit structured tool arguments so the phase card can render
          // them separately from the tool output.
          final argsMap = _tryDecodeJsonMap(toolCall.arguments);
          if (argsMap.isNotEmpty) {
            try {
              emit(
                '  📥 ${const JsonEncoder().convert(argsMap)}',
              );
            } catch (_) {
              emit('  📥 ${toolCall.arguments.trim()}');
            }
          }

          final result = await _toolRuntimeService.execute(
            sessionId: phaseSessionId,
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
            final args = argsMap.isNotEmpty
                ? argsMap
                : _tryDecodeJsonMap(toolCall.arguments);
            final filePath = args['file_path'] ?? args['path'];
            if (filePath is String && filePath.isNotEmpty) {
              previouslyReadFiles.add(filePath);
            }
          }

          // Emit structured status metadata for the phase card.
          final statusLabel = result.status.storageValue;
          final durLabel = '${result.durationMs}ms';
          final exitLabel = result.exitCode != null
              ? ' | exit: ${result.exitCode}'
              : '';
          final cmdLabel = result.command.isNotEmpty
              ? ' | cmd: ${result.command}'
              : '';
          final cwdLabel = result.workingDirectory.isNotEmpty
              ? ' | cwd: ${result.workingDirectory}'
              : '';
          emit('  📤 status: $statusLabel | $durLabel$exitLabel$cmdLabel$cwdLabel');

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

    // 2026-04-13 Enhanced substantive output detection:
    // - Tool execution outputs (indented with "  ") count as substantive
    // - Pure status lines (ℹ, ⚙, ⚠) alone do not count
    // - Empty or whitespace-only lines do not count
    // - Any other text from the model counts as substantive
    final hasSubstantiveOutput = outputLines.any((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return false;
      // System status markers are not substantive on their own
      if (trimmed.startsWith('ℹ ') ||
          trimmed.startsWith('⚙ ') ||
          trimmed.startsWith('⚠ ') ||
          trimmed.startsWith('✓ ') ||
          trimmed.startsWith('✗ ')) {
        return false;
      }
      // Tool execution output (indented) containing actual content counts
      if (line.startsWith('  ')) {
        return trimmed.isNotEmpty;
      }
      // Regular model text output is substantive
      return true;
    });

    if (!hasSubstantiveOutput) {
      emit('');
      // 2026-04-13 Enhanced diagnostic message
      final mcpNoticeCount =
          outputLines.where((l) => l.trim().startsWith('ℹ MCP ')).length;
      if (mcpNoticeCount > 0) {
        emit(
            '⚠ 检测到 $mcpNoticeCount 条 MCP 服务异常提示，但这不是导致失败的直接原因。');
      }
      emit('✗ API 会话未产生有效输出。可能原因：');
      emit('  • 模型配置无效或 API 密钥过期');
      emit('  • 网络连接问题或 API 端点不可达');
      emit('  • 模型响应超时或返回了空内容');
      emit('  • 检查上方日志获取更多诊断信息');
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

  /// Returns deny rules appropriate for the phase.
  /// Read-only phases deny destructive/modifying bash commands that could
  /// alter the project codebase. Safe operations like `mkdir` and `touch`
  /// are allowed since they don't destroy existing content and may be
  /// needed to create steering directory structures.
  List<AiDenyCommandRule> _denyRulesForPhase(HardnessPhase phase) {
    if (phase == HardnessPhase.implementing) {
      return const <AiDenyCommandRule>[];
    }
    // Read-only phases: deny destructive/code-modifying commands.
    // Allow mkdir/touch for creating steering directory structure.
    return const <AiDenyCommandRule>[
      AiDenyCommandRule(
        id: 'hardness_readonly_phase',
        pattern: r'^(rm|mv|cp|chmod|chown|ln|install|make|cmake|gradle|cargo|go build|npm run|yarn|pnpm|flutter build)',
        matchMode: AiDenyCommandMatchMode.regex,
        note: '当前阶段为只读阶段，不允许执行修改文件系统的命令。',
      ),
    ];
  }

  static final RegExp _inlineToolCallsXmlPattern = RegExp(
    r'<tool_calls>\s*[\s\S]*?</tool_calls>',
    multiLine: true,
  );

  /// Strips `<tool_calls>…</tool_calls>` XML blocks from the model's text
  /// reply.  These are duplicate representations of tool calls that are
  /// already available via the native `tool_calls` array and should not be
  /// rendered as visible text.
  static String _stripInlineToolCallsXml(String text) {
    if (!text.contains('<tool_calls>')) return text;
    return text
        .replaceAll(_inlineToolCallsXmlPattern, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// XML tool call item pattern: matches individual `<tool_call>` blocks.
  static final RegExp _xmlToolCallItemPattern = RegExp(
    r'<tool_call>\s*<tool_name>\s*(.*?)\s*</tool_name>\s*<parameters>\s*([\s\S]*?)\s*</parameters>\s*</tool_call>',
    multiLine: true,
  );

  /// Parses `<tool_calls>` XML from the model's text reply into a list of
  /// [AiToolCall] objects.  Returns an empty list if no valid XML tool
  /// calls are found.
  ///
  /// This is the fallback path for models that emit tool calls as XML text
  /// rather than through the native function-calling API.
  static List<AiToolCall> _parseXmlToolCalls(String text) {
    if (!text.contains('<tool_calls>')) return const <AiToolCall>[];
    final calls = <AiToolCall>[];
    var counter = 0;
    for (final match in _xmlToolCallItemPattern.allMatches(text)) {
      final name = match.group(1)?.trim() ?? '';
      final params = match.group(2)?.trim() ?? '{}';
      if (name.isEmpty) continue;
      counter++;
      calls.add(AiToolCall(
        id: 'xml_tc_$counter',
        name: name,
        arguments: params,
      ));
    }
    return calls;
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

  /// Checks whether context has grown past the compression threshold and, if
  /// so, triggers a handoff: asks the model to produce a structured handoff
  /// document, persists it, then returns a fresh conversation seeded with
  /// the handoff as context.
  ///
  /// Returns `null` when the context is still within budget (no handoff).
  Future<List<AiChatTurn>?> _handoffIfNeeded(
    List<AiChatTurn> conversation, {
    required AiModelConfig model,
    required HardnessPhase phase,
    required String phasePrompt,
    required AiSessionRuntimeContext runtimeContext,
    required String persistenceDirectory,
    required int contextWindowTokens,
    required String systemContent,
    required void Function(String line) emit,
    Future<void>? cancelSignal,
  }) async {
    if (conversation.length <= _minConversationTurns) return null;

    // Use the configurable compression threshold (from global AI settings)
    // as the primary trigger, but also honour the model's context window.
    final compressionThresholdChars = runtimeContext.compressionThresholdChars;
    final modelCharBudget = contextWindowTokens * _estimatedCharsPerToken;
    final effectiveCharThreshold = math.min(
      compressionThresholdChars,
      modelCharBudget,
    );

    // Estimate current conversation size in characters.
    var totalChars = 0;
    for (final turn in conversation) {
      totalChars += turn.content.length;
      for (final tc in turn.toolCalls) {
        totalChars += tc.name.length + tc.arguments.length;
      }
    }

    // Only trigger handoff when we've exceeded the threshold.
    // Use 85% of threshold as trigger point to leave room for one more
    // exchange before hitting the hard limit.
    if (totalChars < (effectiveCharThreshold * 0.85).round()) return null;

    emit('');
    emit('📋 上下文接近阈值（${totalChars ~/ 1024}KB / ${effectiveCharThreshold ~/ 1024}KB），正在生成交接文档…');

    // ── Step 1: Generate handoff document via the model ──────────────────
    final handoffPrompt = _buildHandoffPrompt(conversation, phase);
    final handoffConversation = <AiChatTurn>[
      const AiChatTurn(
        role: AiChatRole.system,
        content: _handoffSystemPrompt,
      ),
      AiChatTurn(
        role: AiChatRole.user,
        content: handoffPrompt,
      ),
    ];

    String handoffDocContent;
    try {
      final completion = await _chatClient.sendMessage(
        model: model,
        messages: handoffConversation,
        tools: const <AiToolDefinition>[],
        timeout: const Duration(minutes: 5),
      );
      handoffDocContent = completion.reply.trim();
    } catch (e) {
      final safeError = _sanitizeError('$e', model);
      emit('⚠ 交接文档生成失败：$safeError — 退化为截断模式继续执行');
      // Fallback: trim conversation the old way to keep going.
      _trimConversationFallback(
        conversation,
        contextWindowTokens: contextWindowTokens,
      );
      return null;
    }

    if (handoffDocContent.isEmpty) {
      emit('⚠ 交接文档为空 — 退化为截断模式继续执行');
      _trimConversationFallback(
        conversation,
        contextWindowTokens: contextWindowTokens,
      );
      return null;
    }

    // ── Step 2: Persist the handoff document ─────────────────────────────
    _handoffSessionCounter++;
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final handoffFileName =
        'handoff-${phase.storageValue}-s$_handoffSessionCounter-$ts.md';
    final handoffDir = Directory(
      p.join(persistenceDirectory, 'steering', 'handoff'),
    );
    try {
      await handoffDir.create(recursive: true);
      final handoffFile = File(p.join(handoffDir.path, handoffFileName));
      await handoffFile.writeAsString(handoffDocContent, flush: true);
      emit('📋 交接文档已保存：${handoffFile.path}');
    } catch (e) {
      emit('⚠ 交接文档保存失败：$e');
    }

    emit('📋 正在启动新会话，载入交接文档…');
    emit('');

    // ── Step 3: Build fresh conversation with handoff context ────────────
    final freshConversation = <AiChatTurn>[
      AiChatTurn(
        role: AiChatRole.system,
        content: systemContent,
      ),
      AiChatTurn(
        role: AiChatRole.user,
        content: _buildHandoffResumePrompt(
          phasePrompt: phasePrompt,
          handoffContent: handoffDocContent,
          phase: phase,
        ),
      ),
    ];

    emit('📋 交接完成！新会话已就绪，继续执行 ${phase.displayNameZh} 阶段。');
    emit('');

    return freshConversation;
  }

  /// Builds the prompt sent to the model to generate a handoff document.
  String _buildHandoffPrompt(
    List<AiChatTurn> conversation,
    HardnessPhase phase,
  ) {
    final sb = StringBuffer()
      ..writeln('请根据以下对话历史生成一份结构化的交接文档。')
      ..writeln()
      ..writeln('当前阶段：${phase.displayNameZh}')
      ..writeln()
      ..writeln('## 对话历史')
      ..writeln();

    // Include conversation content, with tool calls summarized.
    for (final turn in conversation) {
      final role = turn.role == AiChatRole.system
          ? '系统'
          : turn.role == AiChatRole.user
              ? '用户'
              : turn.role == AiChatRole.assistant
                  ? '助手'
                  : '工具';
      sb.writeln('### [$role]');

      // Truncate very long tool result contents to keep the prompt manageable.
      final content = turn.content;
      if (turn.role == AiChatRole.tool && content.length > 2000) {
        sb.writeln('${content.substring(0, 2000)}… (${content.length} chars)');
      } else {
        sb.writeln(content);
      }

      for (final tc in turn.toolCalls) {
        sb.writeln('  → 工具调用：${tc.name}(${tc.arguments.length > 200 ? '${tc.arguments.substring(0, 200)}…' : tc.arguments})');
      }
      sb.writeln();
    }

    return sb.toString();
  }

  /// System prompt for the handoff document generation.
  static const String _handoffSystemPrompt = '''
你是一个专门生成交接文档的助手。你的任务是将对话历史压缩为一份结构化的交接文档，以便下一个会话能够无缝接力完成工作。

## 输出格式要求

请使用以下模板输出交接文档（全文简体中文，技术标识保留原文）：

```markdown
# Hardness Engineering 交接文档

## 原始任务
{从对话中提取的原始任务描述}

## 已完成工作
{已完成的具体步骤和成果，按时间顺序列出}

## 当前进展
- 当前阶段：{阶段名称}
- 最后一次操作：{描述}
- 进度评估：{百分比或描述}

## 关键发现与决策
{重要的技术发现、设计决策、约束条件}

## 已修改/创建的文件
{列出所有已修改或创建的文件路径}

## 工具调用结果摘要
{重要的工具调用及其结果}

## 未完成事项
{仍需完成的步骤和注意事项}

## 已知问题与风险
{已发现的问题、失败的尝试、潜在风险}
```

## 关键原则
1. **不丢失关键信息**：所有重要的技术决策、文件路径、代码变更必须保留
2. **简洁高效**：去除冗余对话和重复内容，保留核心事实
3. **可操作性**：下一个会话读到交接文档后应能立即继续工作
4. **准确性**：不得编造对话中不存在的信息
''';

  /// Builds the resume prompt for the new session after handoff.
  String _buildHandoffResumePrompt({
    required String phasePrompt,
    required String handoffContent,
    required HardnessPhase phase,
  }) {
    return '''# 会话接力 — ${phase.displayNameZh}阶段

**重要：这是一个接力会话。** 前一个会话因上下文窗口接近上限而生成了交接文档。
你必须基于交接文档中的工作进展继续完成任务，不要重新从头开始。

## 交接文档

$handoffContent

## 原始阶段提示

$phasePrompt

## 继续执行指令

1. 仔细阅读交接文档，理解已完成的工作和当前进度
2. 从交接文档记录的"未完成事项"继续推进
3. 不要重复已完成的工作
4. 如果交接文档提到了已知问题，请优先处理
5. 完成所有剩余步骤后，按照原始阶段提示的要求输出最终结果
''';
  }

  /// Simple fallback: trim old turns when handoff generation fails.
  void _trimConversationFallback(
    List<AiChatTurn> conversation, {
    required int contextWindowTokens,
  }) {
    if (conversation.length <= _minConversationTurns) return;
    final budget = contextWindowTokens - _responseReserveTokens;
    if (budget <= 0) return;

    var estimatedTokens = _estimateConversationTokens(conversation);
    if (estimatedTokens <= budget) return;

    while (conversation.length > _minConversationTurns &&
        estimatedTokens > budget) {
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
