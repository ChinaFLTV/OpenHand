import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/silent_log.dart';
import '../../ai/index.dart';
import '../../mcp/index.dart';
import '../model/hardness_phase.dart';
import '../service/hardness_orchestrator.dart';
import '../service/hardness_prompt_builder.dart';
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

String? validateHardnessHandoffDocument(String content) {
  final normalized = content.trim();
  if (normalized.length < 120) {
    return '内容过短';
  }
  final h1Pattern = RegExp(
    r'^#\s+Hardness Engineering\s+(?:交接文档|会话摘要)\s*$',
    multiLine: true,
  );
  if (!h1Pattern.hasMatch(normalized)) {
    return '缺少 # Hardness Engineering 会话摘要';
  }
  final sectionBodyByHeading = _markdownSectionBodies(normalized);
  String? requireSection(String label, List<String> headings) {
    for (final heading in headings) {
      final body = sectionBodyByHeading[heading]?.trim();
      if (body != null && body.length >= 6) {
        return null;
      }
    }
    return '缺少或内容过空：$label';
  }

  return requireSection('原始任务', const <String>['原始任务']) ??
      requireSection('当前状态', const <String>['当前状态', '当前进展']) ??
      requireSection('未解决问题', const <String>[
        '未解决问题',
        '未解决问题（含未闭环的 CLI 失败 / 未确认写命令 / 未读交接）',
        '未完成事项',
      ]) ??
      requireSection('风险与边界情况', const <String>['风险与边界情况', '已知问题与风险']);
}

Map<String, String> _markdownSectionBodies(String content) {
  final headingPattern = RegExp(r'^##\s+(.+?)\s*$', multiLine: true);
  final matches = headingPattern.allMatches(content).toList(growable: false);
  final result = <String, String>{};
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    final heading = match.group(1)?.trim();
    if (heading == null || heading.isEmpty) {
      continue;
    }
    final bodyStart = match.end;
    final bodyEnd = index + 1 < matches.length
        ? matches[index + 1].start
        : content.length;
    result[heading] = content.substring(bodyStart, bodyEnd).trim();
  }
  return result;
}

Map<String, Object?> buildHardnessHandoffFailureRecord({
  required HardnessPhase phase,
  required int sessionIndex,
  required int sourceTurnCount,
  required int sourceCharacters,
  required int contextWindowTokens,
  required int effectiveThresholdCharacters,
  required String modelId,
  required String modelLabel,
  required String failureStage,
  required String reason,
  int? handoffCharacters,
  DateTime? createdAt,
}) {
  return <String, Object?>{
    'schema': 'openhand.hardness_handoff_failure.v1',
    'phase': phase.storageValue,
    'phase_label': phase.displayNameZh,
    'session_index': sessionIndex,
    'source_turn_count': sourceTurnCount,
    'source_characters': sourceCharacters,
    'context_window_tokens': contextWindowTokens,
    'effective_threshold_characters': effectiveThresholdCharacters,
    'handoff_characters': handoffCharacters,
    'model_id': modelId,
    'model_label': modelLabel,
    'failure_stage': failureStage,
    'reason': reason,
    'fallback': 'trim_conversation',
    'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
  };
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
    this.confirmWriteCommand,
    this.onToolSearchLoaded,
    this.onPhaseEnded,
  }) : _chatClient = chatClient,
       _toolRuntimeService = toolRuntimeService,
       _templateRepository = templateRepository;

  final AiChatClient _chatClient;
  final AiToolRuntimeService _toolRuntimeService;
  final AiPromptTemplateRepository _templateRepository;
  final Future<BashCommandApprovalDecision> Function(
    BashCommandApprovalRequest request,
  )?
  confirmWriteCommand;

  /// 当 ToolSearch 在某个 phase 内成功拉取若干 MCP 工具时被回调。
  /// `loadedNames`：本次新加入的完整工具名（已去重，按 ToolSearch 返回顺序）。
  /// `totalLoadedSoFar`：phase 累计已加载工具数。
  /// `phaseSessionId`：所属 phase 会话 id，便于 UI 区分。
  final void Function({
    required String phaseSessionId,
    required List<String> loadedNames,
    required int totalLoadedSoFar,
    required int totalDeferred,
    required String query,
  })?
  onToolSearchLoaded;

  /// 当一个 phase 真正结束（无论 success/failure/cancel）时被回调一次。
  /// 调用方可借此清理与 `phaseSessionId` 相关的 UI 累计缓存（例如
  /// ToolSearch 加载历史时间线），避免长会话累积。
  final void Function({required String phaseSessionId})? onPhaseEnded;

  /// Per-phase-session record of MCP tools that ToolSearch already pulled in,
  /// keyed by `phaseSessionId`. Mirrors `AiSessionController._loadedMcpToolsBySession`.
  final Map<String, Set<String>> _loadedMcpToolsBySession =
      <String, Set<String>>{};

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
  /// 公开入口。在调用真正的 phase 执行体前，先把 `phaseSessionId` 计算
  /// 出来，并以 try/finally 形式保证 `onPhaseEnded` 总会被回调一次（不论
  /// 成功 / 失败 / 异常 / 取消）。调用方可借此清理与该 phase 相关的 UI
  /// 累计缓存（如 ToolSearch 加载历史时间线）。
  Future<HardnessApiPhaseResult> runPhase({
    required AiModelConfig model,
    required HardnessPhase phase,
    required String phasePrompt,
    required AiSessionRuntimeContext runtimeContext,
    required String persistenceDirectory,
    required void Function(String line) onLine,
    required bool requireWriteCommandConfirmation,
    Future<void>? cancelSignal,
  }) async {
    final phaseSessionId = phase == HardnessPhase.reviewing
        ? 'hardness-reviewer-isolated-${DateTime.now().millisecondsSinceEpoch}'
        : 'hardness-phase-${phase.storageValue}';
    return guardedRunPhase<HardnessApiPhaseResult>(
      phaseSessionId: phaseSessionId,
      onPhaseEnded: onPhaseEnded,
      run: () => _runPhaseInner(
        model: model,
        phase: phase,
        phasePrompt: phasePrompt,
        runtimeContext: runtimeContext,
        persistenceDirectory: persistenceDirectory,
        onLine: onLine,
        requireWriteCommandConfirmation: requireWriteCommandConfirmation,
        cancelSignal: cancelSignal,
        phaseSessionId: phaseSessionId,
      ),
    );
  }

  /// 公开的 try/finally 包装：保证 [onPhaseEnded] 会在 [run] 结束时
  /// 被调用一次，无论 [run] 是正常返回还是抛出异常。
  /// 暴露为静态方法主要是为了便于纯单测覆盖 finally 路径，无需构造
  /// 完整的 chatClient / toolRuntimeService 依赖图。
  @visibleForTesting
  static Future<T> guardedRunPhase<T>({
    required String phaseSessionId,
    required Future<T> Function() run,
    required void Function({required String phaseSessionId})? onPhaseEnded,
  }) async {
    try {
      return await run();
    } finally {
      onPhaseEnded?.call(phaseSessionId: phaseSessionId);
    }
  }

  Future<HardnessApiPhaseResult> _runPhaseInner({
    required AiModelConfig model,
    required HardnessPhase phase,
    required String phasePrompt,
    required AiSessionRuntimeContext runtimeContext,
    required String persistenceDirectory,
    required void Function(String line) onLine,
    required bool requireWriteCommandConfirmation,
    Future<void>? cancelSignal,
    required String phaseSessionId,
  }) async {
    _handoffSessionCounter = 0;
    final outputLines = <String>[];
    void emit(String line) {
      outputLines.add(line);
      onLine(line);
    }

    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    final supportsTools = adapter.supportsToolCalls;

    // phaseSessionId is computed by the public `runPhase` wrapper and passed
    // in, so the same id flows to both the inner body and `onPhaseEnded`.

    // Resolve tool catalog (builtin + MCP + skills) — same as default thread.
    final rawToolCatalog = supportsTools
        ? await _toolRuntimeService.resolveCatalog(
            runtimeContext: runtimeContext,
          )
        : const AiResolvedToolCatalog(
            definitions: <AiToolDefinition>[],
            toolsByName: <String, AiResolvedTool>{},
          );

    // Apply MCP lazy-loading policy before phase-affinity filtering, so the
    // deferred list reflects the full server inventory and any subsequent
    // ToolSearch hit becomes immediately callable in this phase.
    final toolCatalog = supportsTools
        ? McpLazyLoadingApplier.apply(
            catalog: rawToolCatalog,
            runtimeContext: runtimeContext,
            toolRuntimeService: _toolRuntimeService,
            alreadyLoadedNames:
                _loadedMcpToolsBySession[phaseSessionId] ??
                const <String>{},
          )
        : rawToolCatalog;

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
    if (runtimeContext.memoryEnabled &&
        runtimeContext.memoryEntries.isNotEmpty) {
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
        ..writeln(
          hardnessPromptBuilder.renderCompactToolCatalog(
            tools: phaseToolCatalog.definitions,
            phase: phase,
          ),
        );
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
      AiChatTurn(role: AiChatRole.system, content: systemContent.toString()),
      AiChatTurn(role: AiChatRole.user, content: phasePrompt),
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

        // Emit reasoning / thinking content as a separate segment so
        // the dashboard renders it as an independent thinking card.
        final reasoning = completion.reasoningContent;
        if (reasoning != null && reasoning.trim().isNotEmpty) {
          emit('');
          emit('thinking');
          for (final line in reasoning.split('\n')) {
            emit(line);
          }
        }

        if (reply.isNotEmpty) {
          // Emit a role marker before the reply so the sub-conversation
          // parser creates a separate card instead of merging the reply
          // into the previous tool-call segment.
          if (toolRound > 0 ||
              (reasoning != null && reasoning.trim().isNotEmpty)) {
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
        conversation.add(
          AiChatTurn(
            role: AiChatRole.assistant,
            content: reply,
            toolCalls: toolCalls,
          ),
        );

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
              emit('  📥 ${const JsonEncoder().convert(argsMap)}');
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
            requireWriteCommandConfirmation: requireWriteCommandConfirmation,
            confirmWriteCommand: confirmWriteCommand,
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

          // Absorb tool_search_loaded_names so subsequent rounds in this
          // phase see the just-pulled MCP tools as live (not deferred).
          final loadedNames =
              result.metadata['tool_search_loaded_names'];
          if (loadedNames is List && loadedNames.isNotEmpty) {
            final bucket = _loadedMcpToolsBySession.putIfAbsent(
              phaseSessionId,
              () => <String>{},
            );
            final addedNames = <String>[];
            for (final name in loadedNames) {
              if (name is String && name.isNotEmpty) {
                bucket.add(name);
                addedNames.add(name);
              }
            }
            final cb = onToolSearchLoaded;
            if (cb != null && addedNames.isNotEmpty) {
              final totalDeferredRaw =
                  result.metadata['tool_search_total_deferred'];
              final queryRaw = result.metadata['tool_search_query'];
              cb(
                phaseSessionId: phaseSessionId,
                loadedNames: List<String>.unmodifiable(addedNames),
                totalLoadedSoFar: bucket.length,
                totalDeferred: totalDeferredRaw is int
                    ? totalDeferredRaw
                    : (totalDeferredRaw is num
                          ? totalDeferredRaw.toInt()
                          : addedNames.length),
                query: queryRaw is String ? queryRaw : '',
              );
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
          emit(
            '  📤 status: $statusLabel | $durLabel$exitLabel$cmdLabel$cwdLabel',
          );

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
          conversation.add(
            AiChatTurn(
              role: AiChatRole.tool,
              content: toolOutput,
              toolCallId: toolCall.id,
            ),
          );
        }

        // If we had to truncate tool calls, note the excess.
        if (toolCalls.length > maxToolCallsPerRound) {
          final skipped = toolCalls.length - maxToolCallsPerRound;
          emit('');
          emit('ℹ 跳过 $skipped 个超出单轮限制的工具调用。');
          // Add error results for skipped tool calls.
          for (var i = maxToolCallsPerRound; i < toolCalls.length; i++) {
            conversation.add(
              AiChatTurn(
                role: AiChatRole.tool,
                content:
                    'Tool call skipped: per-round tool call limit reached.',
                toolCallId: toolCalls[i].id,
              ),
            );
          }
        }
      }
    } catch (e) {
      final safeError = _sanitizeError('$e', model);
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
      final mcpNoticeCount = outputLines
          .where((l) => l.trim().startsWith('ℹ MCP '))
          .length;
      if (mcpNoticeCount > 0) {
        emit('⚠ 检测到 $mcpNoticeCount 条 MCP 服务异常提示，但这不是导致失败的直接原因。');
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

    return HardnessApiPhaseResult(success: true, outputLines: outputLines);
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
        pattern:
            r'^(rm|mv|cp|chmod|chown|ln|install|make|cmake|gradle|cargo|go build|npm run|yarn|pnpm|flutter build)',
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
      calls.add(
        AiToolCall(id: 'xml_tc_$counter', name: name, arguments: params),
      );
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
      RegExp(
        r'[?&](key|token|api_key|apikey|access_token)=[^&\s]+',
        caseSensitive: false,
      ),
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
    emit(
      '📋 上下文接近阈值（${totalChars ~/ 1024}KB / ${effectiveCharThreshold ~/ 1024}KB），正在生成交接文档…',
    );

    // ── Step 1: Generate handoff document via the model ──────────────────
    final handoffPrompt = _buildHandoffPrompt(conversation, phase);
    final handoffConversation = <AiChatTurn>[
      const AiChatTurn(role: AiChatRole.system, content: _handoffSystemPrompt),
      AiChatTurn(role: AiChatRole.user, content: handoffPrompt),
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
      await _recordHandoffFailure(
        phase: phase,
        persistenceDirectory: persistenceDirectory,
        sessionIndex: _handoffSessionCounter + 1,
        sourceTurnCount: conversation.length,
        sourceCharacters: totalChars,
        contextWindowTokens: contextWindowTokens,
        effectiveThresholdCharacters: effectiveCharThreshold,
        model: model,
        failureStage: 'generation_exception',
        reason: safeError,
        emit: emit,
      );
      // Fallback: trim conversation the old way to keep going.
      _trimConversationFallback(
        conversation,
        contextWindowTokens: contextWindowTokens,
      );
      return null;
    }

    if (handoffDocContent.isEmpty) {
      emit('⚠ 交接文档为空 — 退化为截断模式继续执行');
      await _recordHandoffFailure(
        phase: phase,
        persistenceDirectory: persistenceDirectory,
        sessionIndex: _handoffSessionCounter + 1,
        sourceTurnCount: conversation.length,
        sourceCharacters: totalChars,
        contextWindowTokens: contextWindowTokens,
        effectiveThresholdCharacters: effectiveCharThreshold,
        model: model,
        failureStage: 'empty_document',
        reason: 'handoff document is empty',
        handoffCharacters: 0,
        emit: emit,
      );
      _trimConversationFallback(
        conversation,
        contextWindowTokens: contextWindowTokens,
      );
      return null;
    }
    final validationError = validateHardnessHandoffDocument(handoffDocContent);
    if (validationError != null) {
      emit('⚠ 交接文档结构不完整：$validationError — 退化为截断模式继续执行');
      emit(
        '  {"handoff_validation":"failed","reason":${jsonEncode(validationError)}}',
      );
      await _recordHandoffFailure(
        phase: phase,
        persistenceDirectory: persistenceDirectory,
        sessionIndex: _handoffSessionCounter + 1,
        sourceTurnCount: conversation.length,
        sourceCharacters: totalChars,
        contextWindowTokens: contextWindowTokens,
        effectiveThresholdCharacters: effectiveCharThreshold,
        model: model,
        failureStage: 'validation_failed',
        reason: validationError,
        handoffCharacters: handoffDocContent.length,
        emit: emit,
      );
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
      final metadataFile = File('${handoffFile.path}.json');
      final metadata = <String, Object?>{
        'schema_version': 1,
        'phase': phase.storageValue,
        'phase_label': phase.displayNameZh,
        'session_index': _handoffSessionCounter,
        'source_turn_count': conversation.length,
        'source_characters': totalChars,
        'context_window_tokens': contextWindowTokens,
        'effective_threshold_characters': effectiveCharThreshold,
        'handoff_characters': handoffDocContent.length,
        'model_id': model.id,
        'model_label': model.displayName,
        'validation_status': 'passed',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      await metadataFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(metadata),
        flush: true,
      );
      emit('📋 交接文档已保存：${handoffFile.path}');
      emit('📋 交接元数据已保存：${metadataFile.path}');
    } catch (e) {
      emit('⚠ 交接文档保存失败：$e');
    }

    emit('📋 正在启动新会话，载入交接文档…');
    emit('');

    // ── Step 3: Build fresh conversation with handoff context ────────────
    final freshConversation = <AiChatTurn>[
      AiChatTurn(role: AiChatRole.system, content: systemContent),
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

  Future<void> _recordHandoffFailure({
    required HardnessPhase phase,
    required String persistenceDirectory,
    required int sessionIndex,
    required int sourceTurnCount,
    required int sourceCharacters,
    required int contextWindowTokens,
    required int effectiveThresholdCharacters,
    required AiModelConfig model,
    required String failureStage,
    required String reason,
    required void Function(String line) emit,
    int? handoffCharacters,
  }) async {
    final timestamp = DateTime.now().toUtc();
    final ts = timestamp
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final handoffDir = Directory(
      p.join(persistenceDirectory, 'steering', 'handoff'),
    );
    final record = buildHardnessHandoffFailureRecord(
      phase: phase,
      sessionIndex: sessionIndex,
      sourceTurnCount: sourceTurnCount,
      sourceCharacters: sourceCharacters,
      contextWindowTokens: contextWindowTokens,
      effectiveThresholdCharacters: effectiveThresholdCharacters,
      modelId: model.id,
      modelLabel: model.displayName,
      failureStage: failureStage,
      reason: reason,
      handoffCharacters: handoffCharacters,
      createdAt: timestamp,
    );
    try {
      await handoffDir.create(recursive: true);
      final failureFile = File(
        p.join(
          handoffDir.path,
          'handoff-failure-${phase.storageValue}-s$sessionIndex-$ts.json',
        ),
      );
      await failureFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(record),
        flush: true,
      );
      emit('📋 交接失败记录已保存：${failureFile.path}');
      emit(
        '  {"handoff_failure":"recorded","stage":${jsonEncode(failureStage)},"path":${jsonEncode(failureFile.path)}}',
      );
    } catch (e) {
      emit('⚠ 交接失败记录保存失败：$e');
      emit(
        '  {"handoff_failure":"record_failed","stage":${jsonEncode(failureStage)},"reason":${jsonEncode(reason)}}',
      );
    }
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
        sb.writeln(
          '  → 工具调用：${tc.name}(${tc.arguments.length > 200 ? '${tc.arguments.substring(0, 200)}…' : tc.arguments})',
        );
      }
      sb.writeln();
    }

    return sb.toString();
  }

  /// System prompt for the handoff document generation.
  static const String _handoffSystemPrompt = '''
你是 Hardness Engineering 会话的交接摘要器。只输出 Markdown 正文，不调用工具，不输出解释前后缀。

目标：把对话历史压缩为持久化、信息密度高、可接力执行的会话摘要。全文使用简体中文；路径、命令、文件名、CLI 名、模型名、PASS/FAIL、退出码、轮次编号保留原文。

必须保留：原始任务、当前阶段、最近活跃角色、已完成/待完成步骤、所有持久化文件路径、未闭环 CLI 失败、未确认写命令、未读交接、活跃后台进程、风险与边界情况。

请严格使用以下章节顺序；没有事实的章节也要写“暂无已确认事项”，不要省略关键章节：

```markdown
# Hardness Engineering 会话摘要

## 配置
- 工作目录：{path}
- 持久化目录：{path}
- 角色 / CLI / 模型：{已知配置}

## 原始任务
{task description}

## 当前状态
- 阶段：{current_phase}
- 最近活跃角色：{role / agent_id}
- 已完成步骤：{list}
- 待完成步骤：{list}

## 本次会话已创建的持久化文件
- 计划：{paths}
- 反馈：{paths}
- 交接：{paths}
- Lessons：{paths}
- Meta：{paths / status}

## 当前成果
{已完成事项的简要描述}

## 未解决问题（含未闭环的 CLI 失败 / 未确认写命令 / 未读交接）
- {轮次 / 角色 / CLI / 现象 / 状态}

## 活跃后台进程
- {BashBackground id / 命令 / 用途 / stop 状态}

## 风险与边界情况
{已知限制、脆弱假设、需用户介入的开放问题}
```

规则：
1. 稳定事实优先；不要编造。
2. 显式区分“已确认”和“待确认”。
3. 同一事实不要重复表达。
4. 任何写命令、CLI 失败、deny-list 命中事件必须逐条保留。
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
    } catch (error, stack) {
      silentLog(
        'hardness_api_phase_runner',
        'decode JSON payload',
        error,
        stack,
      );
    }
    return const <String, dynamic>{};
  }
}
