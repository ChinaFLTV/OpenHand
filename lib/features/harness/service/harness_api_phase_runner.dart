import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:openhand/shared/util/text_normalization.dart';
import 'package:path/path.dart' as p;

import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart';
import '../../mcp/index.dart';
import '../model/harness_phase.dart';
import '../service/harness_prompt_builder.dart';

const String _harnessTemplateId =
    AiPromptTemplatePolicies.harnessEngineeringTemplateId;

class HarnessApiPhaseResult {
  const HarnessApiPhaseResult.success() : success = true, errorMessage = null;

  const HarnessApiPhaseResult.failure(this.errorMessage) : success = false;

  final bool success;
  final String? errorMessage;
}

String? validateHarnessHandoffDocument(String content) {
  final normalized = content.trim();
  if (normalized.length < 120) {
    return '内容过短';
  }
  final h1Pattern = RegExp(
    r'^#\s+Harness Engineering\s+(?:交接文档|会话摘要)\s*$',
    multiLine: true,
  );
  if (!h1Pattern.hasMatch(normalized)) {
    return '缺少 # Harness Engineering 会话摘要';
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

Map<String, Object?> buildHarnessHandoffFailureRecord({
  required HarnessPhase phase,
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
    'schema': 'openhand.harness_handoff_failure.v1',
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

/// 通过标准 AI 会话基础设施执行单个 Harness Engineering 阶段。
/// 上下文接近压缩阈值时生成并持久化交接文档，再由新会话接力执行。
class HarnessApiPhaseRunner {
  HarnessApiPhaseRunner({
    required this._chatClient,
    required this._toolRuntimeService,
    required this._toolUsagePromotionStore,
    required this._templateRepository,
    required this.usageSessionId,
    this.confirmWriteCommand,
    this.onToolSearchLoaded,
    this.onPhaseEnded,
  });

  final AiChatClient _chatClient;
  final AiToolRuntimeService _toolRuntimeService;
  final AiToolUsagePromotionStore _toolUsagePromotionStore;
  final AiPromptTemplateRepository _templateRepository;
  final String usageSessionId;
  final Future<BashCommandApprovalDecision> Function(
    BashCommandApprovalRequest request,
  )?
  confirmWriteCommand;

  /// ToolSearch 在当前阶段新增匹配工具时回调。
  final void Function({
    required String phaseSessionId,
    required List<String> loadedNames,
    required int totalLoadedSoFar,
    required int totalDeferred,
    required String query,
  })?
  onToolSearchLoaded;

  /// 阶段结束时回调一次，供调用方清理对应 UI 缓存。
  final void Function({required String phaseSessionId})? onPhaseEnded;

  /// 按 phaseSessionId 记录 ToolSearch 已匹配的工具名，仅用于 UI 统计。
  final Map<String, Set<String>> _matchedToolsBySession =
      <String, Set<String>>{};

  /// 上下文 Token 粗略估算参数。
  static const int _estimatedCharsPerToken = 4;
  static const int _responseReserveTokens = 4096;
  static const int _minConversationTurns = 4;
  static const int _maxToolRoundsPerPhase = 64;
  static const int _maxToolCallsPerRound = 64;
  static const int _maxToolCallsPerPhase = 256;
  static const int _maxToolArgumentsCharacters = 256 * kBytesPerKiB;
  static const int _maxErrorCharacters = 2000;

  /// 交接会话编号，用于生成唯一文件名。
  int _handoffSessionCounter = 0;

  /// 执行阶段并保证结束回调始终触发。
  Future<HarnessApiPhaseResult> runPhase({
    required AiModelConfig model,
    required HarnessPhase phase,
    required String phasePrompt,
    required AiSessionRuntimeContext runtimeContext,
    required String persistenceDirectory,
    required void Function(String line) onLine,
    required bool requireWriteCommandConfirmation,
    Future<void>? cancelSignal,
  }) async {
    final phaseSessionId =
        'harness-phase-${phase.storageValue}-${DateTime.now().microsecondsSinceEpoch}';
    try {
      return await _runPhaseInner(
        model: model,
        phase: phase,
        phasePrompt: phasePrompt,
        runtimeContext: runtimeContext,
        persistenceDirectory: persistenceDirectory,
        onLine: onLine,
        requireWriteCommandConfirmation: requireWriteCommandConfirmation,
        cancelSignal: cancelSignal,
        phaseSessionId: phaseSessionId,
      );
    } finally {
      _matchedToolsBySession.remove(phaseSessionId);
      onPhaseEnded?.call(phaseSessionId: phaseSessionId);
    }
  }

  Future<HarnessApiPhaseResult> _runPhaseInner({
    required AiModelConfig model,
    required HarnessPhase phase,
    required String phasePrompt,
    required AiSessionRuntimeContext runtimeContext,
    required String persistenceDirectory,
    required void Function(String line) onLine,
    required bool requireWriteCommandConfirmation,
    Future<void>? cancelSignal,
    required String phaseSessionId,
  }) async {
    _handoffSessionCounter = 0;
    var hasSubstantiveOutput = false;
    var mcpNoticeCount = 0;
    void emit(String line) {
      final trimmed = line.trim();
      if (trimmed.startsWith('ℹ MCP ')) mcpNoticeCount += 1;
      if (trimmed.isNotEmpty &&
          trimmed != 'thinking' &&
          trimmed != 'assistant' &&
          !trimmed.startsWith('ℹ ') &&
          !trimmed.startsWith('⚙ ') &&
          !trimmed.startsWith('⚠ ') &&
          !trimmed.startsWith('✓ ') &&
          !trimmed.startsWith('✗ ')) {
        hasSubstantiveOutput = true;
      }
      onLine(line);
    }

    final adapter = AiProtocolRegistry.adapterFor(model.protocolType);
    final supportsNativeToolCalls = adapter.supportsToolCalls;

    // 原生工具调用和 XML 降级共用同一工具目录。
    final rawToolCatalog = await _toolRuntimeService.resolveCatalog(
      runtimeContext: runtimeContext,
      templateId: _harnessTemplateId,
    );

    // 先统一折叠延迟工具，再按阶段权限过滤；延迟工具始终通过固定网关执行。
    AiResolvedToolCatalog applyRuntimeLazyLoadingForPhase() {
      final builtinLazyLoadingThresholdTokens =
          AiBuiltinToolLazyLoadingApplier.effectiveAutoThresholdTokens(
            runtimeContext.mcpLazyLoadingThresholdTokens,
          );
      final keepToolSearchForBuiltins =
          AiBuiltinToolLazyLoadingApplier.hasDeferredCandidates(
            catalog: rawToolCatalog,
            mode: runtimeContext.builtinToolLazyLoadingMode,
            thresholdTokens: builtinLazyLoadingThresholdTokens,
            charsPerToken: runtimeContext.estimatedCharactersPerToken,
          );
      final mcpCatalog = McpLazyLoadingApplier.apply(
        catalog: rawToolCatalog,
        runtimeContext: runtimeContext,
        toolRuntimeService: _toolRuntimeService,
        keepToolSearchWhenIdle:
            runtimeContext.mcpLazyLoadingMode != McpLazyLoadingMode.disabled ||
            keepToolSearchForBuiltins,
      );
      return AiBuiltinToolLazyLoadingApplier.apply(
        catalog: mcpCatalog,
        sourceCatalog: rawToolCatalog,
        mode: runtimeContext.builtinToolLazyLoadingMode,
        thresholdTokens: builtinLazyLoadingThresholdTokens,
        charsPerToken: runtimeContext.estimatedCharactersPerToken,
        toolRuntimeService: _toolRuntimeService,
      );
    }

    AiResolvedToolCatalog filterToolsForCurrentPhase(
      AiResolvedToolCatalog catalog,
    ) {
      return harnessPromptBuilder.filterToolsForPhase(
        phase: phase,
        catalog: catalog,
      );
    }

    var toolCatalog = applyRuntimeLazyLoadingForPhase();
    var phaseToolCatalog = filterToolsForCurrentPhase(toolCatalog);

    if (toolCatalog.notices.isNotEmpty) {
      for (final notice in toolCatalog.notices) {
        emit('ℹ $notice');
      }
      emit('');
    }

    // 加载 Harness 模板中的系统和开发者指令。
    final templateBundle = await _templateRepository.loadBundle(
      _harnessTemplateId,
    );

    String buildSystemContent(AiResolvedToolCatalog currentPhaseToolCatalog) {
      final systemContent = StringBuffer()
        ..writeln('# 系统指令')
        ..writeln()
        ..writeln(templateBundle.systemInstructions)
        ..writeln()
        ..writeln('# 开发者指令')
        ..writeln()
        ..writeln(templateBundle.developerInstructions)
        ..writeln()
        ..writeln('# 运行时环境')
        ..writeln()
        ..writeln('工作目录：${runtimeContext.workingDirectory}')
        ..writeln('平台：${runtimeContext.platformName}')
        ..writeln('日期：${runtimeContext.todayLocalDate}')
        ..writeln('时区：${runtimeContext.timeZoneName}');

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

      if (currentPhaseToolCatalog.definitions.isNotEmpty) {
        systemContent
          ..writeln()
          ..writeln(
            harnessPromptBuilder.renderCompactToolCatalog(
              tools: currentPhaseToolCatalog.definitions,
            ),
          );
      }

      // 不支持原生工具调用时注入紧凑 XML 协议。
      if (harnessPromptBuilder.shouldInjectXmlInstructions(adapter)) {
        systemContent
          ..writeln()
          ..writeln(harnessPromptBuilder.compactXmlToolInstructions);
      }

      // 验收阶段不继承实施者结论，必须以工作区事实独立核验。
      if (phase == HarnessPhase.reviewing) {
        systemContent
          ..writeln()
          ..writeln('# 验收规则')
          ..writeln()
          ..writeln(
            '仅依据原始需求、执行计划和当前工作区验收。'
            '不要依赖实施者的解释或结论；逐项验证后再判定。',
          );
      }

      // 注入工作区指令文档。
      if (runtimeContext.workspaceInstructionDocuments.isNotEmpty) {
        systemContent
          ..writeln()
          ..writeln('# 工作区指令')
          ..writeln();
        for (final doc in runtimeContext.workspaceInstructionDocuments) {
          systemContent
            ..writeln('## ${doc.name}')
            ..writeln(doc.content)
            ..writeln();
        }
      }

      return systemContent.toString();
    }

    var currentSystemContent = buildSystemContent(phaseToolCatalog);

    final conversation = <AiChatTurn>[
      AiChatTurn(role: AiChatRole.system, content: currentSystemContent),
      AiChatTurn(role: AiChatRole.user, content: phasePrompt),
    ];

    // 阶段执行保留用户配置，同时设置不可突破的资源边界。
    final maxToolRounds = math.min(
      _maxToolRoundsPerPhase,
      math.max(1, runtimeContext.sequentialToolRoundLimit),
    );
    final maxToolCallsPerRound = math.min(
      _maxToolCallsPerRound,
      math.max(1, runtimeContext.singleRoundToolCallLimit),
    );
    final contextWindowTokens = (model.maxContextTokens ?? 0) > 0
        ? model.maxContextTokens!
        : kInferredModelContextWindowTokens;
    final estimatedCharactersPerToken = math.max(
      1,
      runtimeContext.estimatedCharactersPerToken,
    );
    final effectiveContextWindowTokens = math.max(
      1,
      contextWindowTokens - _responseReserveTokens,
    );
    var toolRound = 0;
    var totalToolCalls = 0;
    final previouslyReadFiles = <String>{};
    final denyRules = _denyRulesForPhase(phase);

    try {
      while (true) {
        if (await isCancelSignalCompleted(cancelSignal)) {
          emit('');
          emit('⚠ 已中止');
          return const HarnessApiPhaseResult.failure('执行被用户中止。');
        }

        final handoffResult = await _handoffIfNeeded(
          conversation,
          model: model,
          phase: phase,
          phasePrompt: phasePrompt,
          runtimeContext: runtimeContext,
          persistenceDirectory: persistenceDirectory,
          contextWindowTokens: contextWindowTokens,
          systemContent: currentSystemContent,
          emit: emit,
          cancelSignal: cancelSignal,
        );
        if (handoffResult != null) {
          conversation
            ..clear()
            ..addAll(handoffResult);
        }

        final AiChatCompletion completion;
        try {
          completion = await AiUsageTraceContext.runDerived(
            source: AiUsageSource.harness,
            operation: 'phase_execution',
            sessionId: usageSessionId,
            threadTemplateId: 'harness_engineering',
            metadata: <String, Object?>{
              'phase': phase.name,
              aiContextUsedTokensMetadataKey: _estimateConversationTokens(
                conversation,
                charactersPerToken: estimatedCharactersPerToken,
              ),
              aiContextWindowTokensMetadataKey: effectiveContextWindowTokens,
            },
            body: () => _chatClient.sendMessage(
              model: model,
              messages: conversation,
              tools: supportsNativeToolCalls
                  ? phaseToolCatalog.definitions
                  : const <AiToolDefinition>[],
              timeout: const Duration(minutes: 10),
              cancelSignal: cancelSignal,
            ),
          );
        } catch (e, stack) {
          silentLog('harness_api_phase_runner', 'API 请求', e, stack);
          final safeError = _sanitizeError('$e', model);
          emit('');
          emit('✗ API 请求失败：$safeError');
          return HarnessApiPhaseResult.failure('API 请求失败：$safeError');
        }

        // 原生调用优先；仅在原生调用缺失时解析文本中的 XML 调用。
        var toolCalls = completion.toolCalls;
        String reply;
        if (toolCalls.isNotEmpty) {
          reply = _stripInlineToolCallsXml(completion.reply.trim());
        } else {
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

        // 推理内容单独成段，供面板渲染为独立卡片。
        final reasoning = completion.reasoningContent;
        if (reasoning != null && reasoning.trim().isNotEmpty) {
          emit('');
          emit('thinking');
          for (final line in reasoning.split('\n')) {
            emit(line);
          }
        }

        if (reply.isNotEmpty) {
          // 角色标记用于阻止回复与上一工具调用卡片合并。
          if (toolRound > 0 ||
              (reasoning != null && reasoning.trim().isNotEmpty)) {
            emit('');
            emit('assistant');
          }
          for (final line in reply.split('\n')) {
            emit(line);
          }
        }

        // 没有工具调用，当前阶段完成。
        if (toolCalls.isEmpty) {
          break;
        }

        // 在写入上下文和执行工具前统一校验阶段资源边界。
        toolRound++;
        if (toolRound > maxToolRounds) {
          emit('');
          emit('✗ 已达到最大工具轮次限制（$maxToolRounds），阶段尚未完成。');
          return const HarnessApiPhaseResult.failure('达到最大工具轮次限制，阶段尚未完成。');
        }
        if (toolCalls.any(
          (call) => call.arguments.length > _maxToolArgumentsCharacters,
        )) {
          emit('');
          emit('✗ 工具参数超过安全上限，阶段已停止。');
          return const HarnessApiPhaseResult.failure('工具参数超过安全上限。');
        }
        if (totalToolCalls + toolCalls.length > _maxToolCallsPerPhase) {
          emit('');
          emit('✗ 工具调用总数超过安全上限（$_maxToolCallsPerPhase），阶段已停止。');
          return const HarnessApiPhaseResult.failure('工具调用总数超过安全上限。');
        }
        totalToolCalls += toolCalls.length;

        conversation.add(
          AiChatTurn(
            role: AiChatRole.assistant,
            content: reply,
            toolCalls: toolCalls,
          ),
        );

        final effectiveToolCalls = toolCalls.length > maxToolCallsPerRound
            ? toolCalls.sublist(0, maxToolCallsPerRound)
            : toolCalls;

        for (final toolCall in effectiveToolCalls) {
          emit('');
          emit('⚙ 工具调用：${toolCall.name}');

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
            metadata: const <String, Object?>{
              'template_id': _harnessTemplateId,
            },
          );
          try {
            await _toolUsagePromotionStore.recordToolCall(
              sessionId: phaseSessionId,
              catalog: phaseToolCatalog,
              toolCall: toolCall,
              result: result,
            );
          } catch (error, stack) {
            silentLog('harness_api_phase_runner', '记录工具调用统计失败', error, stack);
          }

          if (toolCall.name.toLowerCase().contains('read')) {
            final args = argsMap.isNotEmpty
                ? argsMap
                : _tryDecodeJsonMap(toolCall.arguments);
            final filePath = args['file_path'] ?? args['path'];
            if (filePath is String && filePath.isNotEmpty) {
              previouslyReadFiles.add(filePath);
            }
          }

          // 记录 ToolSearch 匹配结果供 UI 展示，工具目录保持不变。
          final loadedNames = result.metadata['tool_search_loaded_names'];
          if (loadedNames is List && loadedNames.isNotEmpty) {
            final bucket = _matchedToolsBySession.putIfAbsent(
              phaseSessionId,
              () => <String>{},
            );
            final addedNames = <String>[];
            for (final name in loadedNames) {
              if (name is String && name.isNotEmpty) {
                if (bucket.add(name)) {
                  addedNames.add(name);
                }
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
          // 日志仅展示有界工具输出，完整结果仍进入会话。
          final outputPreview = clipTextByCodeUnits(
            toolOutput,
            500,
            suffix: '…（共 ${toolOutput.length} 个字符）',
          );
          if (outputPreview.isNotEmpty) {
            for (final line in outputPreview.split('\n')) {
              emit('  $line');
            }
          }

          conversation.add(
            AiChatTurn(
              role: AiChatRole.tool,
              content: toolOutput,
              toolCallId: toolCall.id,
            ),
          );
        }

        if (toolCalls.length > maxToolCallsPerRound) {
          final skipped = toolCalls.length - maxToolCallsPerRound;
          emit('');
          emit('ℹ 跳过 $skipped 个超出单轮限制的工具调用。');
          for (var i = maxToolCallsPerRound; i < toolCalls.length; i++) {
            conversation.add(
              AiChatTurn(
                role: AiChatRole.tool,
                content: '工具调用已跳过：达到单轮工具调用上限。',
                toolCallId: toolCalls[i].id,
              ),
            );
          }
        }
      }
    } catch (e, stack) {
      silentLog('harness_api_phase_runner', '执行阶段', e, stack);
      final safeError = _sanitizeError('$e', model);
      emit('');
      emit('✗ 执行错误：$safeError');
      return HarnessApiPhaseResult.failure(safeError);
    }

    if (!hasSubstantiveOutput) {
      emit('');
      if (mcpNoticeCount > 0) {
        emit('⚠ 检测到 $mcpNoticeCount 条 MCP 服务异常提示，但这不是导致失败的直接原因。');
      }
      emit('✗ API 会话未产生有效输出。可能原因：');
      emit('  • 模型配置无效或 API 密钥过期');
      emit('  • 网络连接问题或 API 端点不可达');
      emit('  • 模型响应超时或返回了空内容');
      emit('  • 检查上方日志获取更多诊断信息');
      return const HarnessApiPhaseResult.failure('API 会话未产生有效输出。');
    }

    return const HarnessApiPhaseResult.success();
  }

  /// 返回当前阶段的命令拒绝规则；只读阶段允许创建引导目录。
  List<AiDenyCommandRule> _denyRulesForPhase(HarnessPhase phase) {
    if (phase == HarnessPhase.implementing) {
      return const <AiDenyCommandRule>[];
    }
    return const <AiDenyCommandRule>[
      AiDenyCommandRule(
        id: 'harness_readonly_phase',
        pattern:
            r'^(rm|mv|cp|chmod|chown|ln|install|make|cmake|gradle|cargo|go build|npm run|yarn|pnpm|flutter build)',
        matchMode: AiCommandMatchMode.regex,
        note: '当前阶段为只读阶段，不允许执行修改文件系统的命令。',
      ),
    ];
  }

  static final RegExp _inlineToolCallsXmlPattern = RegExp(
    r'<tool_calls>\s*[\s\S]*?</tool_calls>',
    multiLine: true,
  );

  /// 移除模型文本中与原生工具调用重复的 XML 块。
  static String _stripInlineToolCallsXml(String text) {
    if (!text.contains('<tool_calls>')) return text;
    return text
        .replaceAll(_inlineToolCallsXmlPattern, '')
        .replaceAll(kExcessiveNewlinesPattern, '\n\n')
        .trim();
  }

  static final RegExp _xmlToolCallItemPattern = RegExp(
    r'<tool_call>\s*<tool_name>\s*(.*?)\s*</tool_name>\s*<parameters>\s*([\s\S]*?)\s*</parameters>\s*</tool_call>',
    multiLine: true,
  );

  /// 将模型文本中的 XML 工具调用解析为原生调用对象。
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

  /// 屏蔽错误信息中可能泄漏的认证令牌和 API 密钥。
  String _sanitizeError(String raw, AiModelConfig model) {
    var sanitized = raw;
    final token = model.token;
    if (token.isNotEmpty && token.length >= 8) {
      sanitized = sanitized.replaceAll(token, '****');
    }
    sanitized = sanitized.replaceAll(
      RegExp(
        r'[?&](key|token|api_key|apikey|access_token)=[^&\s]+',
        caseSensitive: false,
      ),
      '',
    );
    return clipTextWithEllipsis(sanitized, _maxErrorCharacters);
  }

  /// 估算会话占用的 Token 数量。
  int _estimateConversationTokens(
    List<AiChatTurn> conversation, {
    int charactersPerToken = _estimatedCharsPerToken,
  }) {
    var totalChars = 0;
    for (final turn in conversation) {
      totalChars += turn.content.length;
      for (final tc in turn.toolCalls) {
        totalChars += tc.name.length + tc.arguments.length;
      }
    }
    return totalChars ~/ math.max(1, charactersPerToken);
  }

  /// 上下文接近阈值时生成交接文档，并返回接力会话；无需交接时返回 `null`。
  Future<List<AiChatTurn>?> _handoffIfNeeded(
    List<AiChatTurn> conversation, {
    required AiModelConfig model,
    required HarnessPhase phase,
    required String phasePrompt,
    required AiSessionRuntimeContext runtimeContext,
    required String persistenceDirectory,
    required int contextWindowTokens,
    required String systemContent,
    required void Function(String line) emit,
    Future<void>? cancelSignal,
  }) async {
    if (conversation.length <= _minConversationTurns) return null;

    final compressionThresholdChars = runtimeContext.compressionThresholdChars;
    final modelCharBudget = contextWindowTokens * _estimatedCharsPerToken;
    final effectiveCharThreshold = math.min(
      compressionThresholdChars,
      modelCharBudget,
    );

    var totalChars = 0;
    for (final turn in conversation) {
      totalChars += turn.content.length;
      for (final tc in turn.toolCalls) {
        totalChars += tc.name.length + tc.arguments.length;
      }
    }

    // 提前预留一轮交互空间，避免触及模型硬限制。
    if (totalChars < (effectiveCharThreshold * 0.85).round()) return null;

    emit('');
    emit(
      '📋 上下文接近阈值（${totalChars ~/ kBytesPerKiB}KB / ${effectiveCharThreshold ~/ kBytesPerKiB}KB），正在生成交接文档…',
    );

    final handoffPrompt = _buildHandoffPrompt(conversation, phase);
    final handoffConversation = <AiChatTurn>[
      const AiChatTurn(role: AiChatRole.system, content: _handoffSystemPrompt),
      AiChatTurn(role: AiChatRole.user, content: handoffPrompt),
    ];

    String handoffDocContent;
    try {
      final completion = await AiUsageTraceContext.runDerived(
        source: AiUsageSource.harness,
        operation: 'context_handoff',
        sessionId: usageSessionId,
        threadTemplateId: 'harness_engineering',
        metadata: <String, Object?>{
          'phase': phase.name,
          aiContextUsedTokensMetadataKey: _estimateConversationTokens(
            handoffConversation,
            charactersPerToken: runtimeContext.estimatedCharactersPerToken,
          ),
          aiContextWindowTokensMetadataKey: math.max(
            1,
            contextWindowTokens - _responseReserveTokens,
          ),
        },
        body: () => _chatClient.sendMessage(
          model: model,
          messages: handoffConversation,
          tools: const <AiToolDefinition>[],
          timeout: const Duration(minutes: 5),
          cancelSignal: cancelSignal,
        ),
      );
      handoffDocContent = completion.reply.trim();
    } catch (e, stack) {
      silentLog('harness_api_phase_runner', '交接文档生成', e, stack);
      final safeError = _sanitizeError('$e', model);
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
    final validationError = validateHarnessHandoffDocument(handoffDocContent);
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
      final handoffFile = File(p.join(handoffDir.path, handoffFileName));
      await writeFileAtomically(handoffFile, handoffDocContent);
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
      await writeFileAtomically(metadataFile, prettyPrintJson(metadata));
      emit('📋 交接文档已保存：${handoffFile.path}');
      emit('📋 交接元数据已保存：${metadataFile.path}');
    } catch (e, stack) {
      silentLog('harness_api_phase_runner', '交接文档保存', e, stack);
      emit('⚠ 交接文档保存失败：$e');
    }

    emit('📋 正在启动新会话，载入交接文档…');
    emit('');

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
    required HarnessPhase phase,
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
    final record = buildHarnessHandoffFailureRecord(
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
      final failureFile = File(
        p.join(
          handoffDir.path,
          'handoff-failure-${phase.storageValue}-s$sessionIndex-$ts.json',
        ),
      );
      await writeFileAtomically(failureFile, prettyPrintJson(record));
      emit('📋 交接失败记录已保存：${failureFile.path}');
      emit(
        '  {"handoff_failure":"recorded","stage":${jsonEncode(failureStage)},"path":${jsonEncode(failureFile.path)}}',
      );
    } catch (e, stack) {
      silentLog('harness_api_phase_runner', '交接失败记录保存', e, stack);
      emit('⚠ 交接失败记录保存失败：$e');
      emit(
        '  {"handoff_failure":"record_failed","stage":${jsonEncode(failureStage)},"reason":${jsonEncode(reason)}}',
      );
    }
  }

  /// 构建交接摘要请求，工具结果只保留必要前缀。
  String _buildHandoffPrompt(
    List<AiChatTurn> conversation,
    HarnessPhase phase,
  ) {
    final sb = StringBuffer()
      ..writeln('请根据以下对话历史生成一份结构化的交接文档。')
      ..writeln()
      ..writeln('当前阶段：${phase.displayNameZh}')
      ..writeln()
      ..writeln('## 对话历史')
      ..writeln();

    for (final turn in conversation) {
      final role = turn.role == AiChatRole.system
          ? '系统'
          : turn.role == AiChatRole.user
          ? '用户'
          : turn.role == AiChatRole.assistant
          ? '助手'
          : '工具';
      sb.writeln('### [$role]');

      final content = turn.content;
      if (turn.role == AiChatRole.tool && content.length > 2000) {
        sb.writeln(
          clipTextByCodeUnits(
            content,
            2000,
            suffix: '…（共 ${content.length} 个字符）',
          ),
        );
      } else {
        sb.writeln(content);
      }

      for (final tc in turn.toolCalls) {
        sb.writeln(
          '  → 工具调用：${tc.name}(${clipTextWithEllipsis(tc.arguments, 200)})',
        );
      }
      sb.writeln();
    }

    return sb.toString();
  }

  /// 交接摘要系统提示词。
  static const String _handoffSystemPrompt = '''
你负责压缩 Harness Engineering 会话，供下一会话直接接力。

规则：
- 只输出简体中文 Markdown 正文，不调用工具，不添加前后缀。
- 保留路径、命令、技术标识、PASS/FAIL、退出码和轮次编号原文。
- 只写可确认事实，区分“已确认”与“待确认”，不重复、不推测。
- 逐条保留写命令、CLI 失败、拒绝规则命中、未确认操作和活跃后台进程。
- 章节顺序固定；无内容时写“暂无已确认事项”。

输出结构：
# Harness Engineering 会话摘要

## 配置
工作目录、持久化目录、角色、CLI 与模型。

## 原始任务
完整保留目标与硬约束。

## 当前状态
当前阶段、最近活跃角色、已完成和待完成步骤。

## 本次会话已创建的持久化文件
按计划、反馈、交接、Lessons、Meta 分类列出路径和状态。

## 当前成果
简述已确认成果。

## 未解决问题（含未闭环的 CLI 失败 / 未确认写命令 / 未读交接）
逐项记录轮次、角色、CLI、现象和状态。

## 活跃后台进程
列出进程 ID、命令、用途和停止状态。

## 风险与边界情况
列出已知限制、脆弱假设和需用户介入的问题。
''';

  /// 构建接力会话提示词。
  String _buildHandoffResumePrompt({
    required String phasePrompt,
    required String handoffContent,
    required HarnessPhase phase,
  }) {
    return '''# 接力执行：${phase.displayNameZh}阶段

根据交接摘要继续未完成事项。不要重做已确认完成的工作；优先处理未解决问题和风险，完成后按原始阶段任务输出。

## 交接摘要

$handoffContent

## 原始阶段任务

$phasePrompt
''';
  }

  /// 交接失败时裁剪旧会话以继续执行。
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

  Map<String, Object?> _tryDecodeJsonMap(String raw) {
    try {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed == '{}') {
        return const <String, Object?>{};
      }
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return stringKeyedMapFromValue(decoded);
    } catch (error, stack) {
      silentLog('harness_api_phase_runner', '解码 JSON 载荷', error, stack);
    }
    return const <String, Object?>{};
  }
}
