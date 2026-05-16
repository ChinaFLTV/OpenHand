library;
import '../../../../app/state/settings_controller.dart';
import '../../../../app/support/silent_log.dart';
import '../../../memory/index.dart';
import '../../model/ai_model_catalog.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../../tools/ai_tool_utils.dart';
import '../../tools/memory/ai_memory_tool.dart';
import '../../tools/skill/ai_skill_manager_tool.dart';
import '../chat/ai_chat_service.dart';
import '../chat/ai_protocol_adapter.dart';
import '../runtime/ai_tool_runtime_service.dart';
import 'self_learning_runner.dart';

class SelfLearningModelSelection {
  const SelfLearningModelSelection({
    required this.model,
    required this.source,
    this.skippedPreferredModelId,
    this.skippedPreferredProviderId,
  });

  final AiModelConfig? model;
  final String source;
  final String? skippedPreferredModelId;
  final String? skippedPreferredProviderId;
}

SelfLearningModelSelection selectSelfLearningModel({
  required List<AiModelConfig> models,
  AiModelConfig? selectedModel,
  String? preferredProviderConfigId,
}) {
  final preferredId = preferredProviderConfigId?.trim();
  AiModelConfig? preferred;
  if (preferredId != null && preferredId.isNotEmpty) {
    for (final candidate in models) {
      if (candidate.id == preferredId) {
        preferred = candidate;
        break;
      }
    }
  }

  String? skippedModelId;
  String? skippedProviderId;
  if (preferred != null) {
    if (_isSelfLearningTextModel(preferred)) {
      return SelfLearningModelSelection(model: preferred, source: 'last_used');
    }
    skippedModelId = preferred.modelId;
    skippedProviderId = preferred.id;
  }

  if (selectedModel != null && _isSelfLearningTextModel(selectedModel)) {
    return SelfLearningModelSelection(
      model: selectedModel,
      source: 'selected',
      skippedPreferredModelId: skippedModelId,
      skippedPreferredProviderId: skippedProviderId,
    );
  }

  for (final candidate in models) {
    if (_isSelfLearningTextModel(candidate)) {
      return SelfLearningModelSelection(
        model: candidate,
        source: 'first_available',
        skippedPreferredModelId: skippedModelId,
        skippedPreferredProviderId: skippedProviderId,
      );
    }
  }

  return SelfLearningModelSelection(
    model: null,
    source: 'none',
    skippedPreferredModelId: skippedModelId,
    skippedPreferredProviderId: skippedProviderId,
  );
}

bool _isSelfLearningTextModel(AiModelConfig model) {
  final modelId = model.modelId.trim();
  if (modelId.isEmpty) return false;

  final profile = model.profileFor(modelId);
  if (_hasMediaGenerationCapability(profile.capabilities)) return false;

  final catalog = AiModelCatalog.lookup(modelId, model.protocolType);
  if (catalog != null) {
    return !_hasMediaGenerationCapability(catalog.capabilities);
  }

  return !_looksLikeDedicatedMediaGenerationModel(modelId);
}

bool _hasMediaGenerationCapability(Set<AiModelCapability> capabilities) {
  return capabilities.contains(AiModelCapability.imageGeneration) ||
      capabilities.contains(AiModelCapability.videoGeneration) ||
      capabilities.contains(AiModelCapability.audioGeneration);
}

bool _looksLikeDedicatedMediaGenerationModel(String modelId) {
  final normalized = modelId.toLowerCase().replaceAll(RegExp(r'[\s_]+'), '-');
  // ── Image-only generators ────────────────────────────────────────────
  const imagePrefixes = <String>[
    'sora',
    'dall-e',
    'gpt-image',
    'wan',
    'seedream',
    'cogview',
    'flux',
    'imagen',
    'midjourney',
    'ideogram',
    'kandinsky',
    'qwen-image',
  ];
  for (final prefix in imagePrefixes) {
    if (normalized.startsWith(prefix)) return true;
  }
  // ── Audio-only generators ────────────────────────────────────────────
  const audioPrefixes = <String>['cogtts', 'cogsound', 't2a'];
  for (final prefix in audioPrefixes) {
    if (normalized.startsWith(prefix)) return true;
  }
  // ── Substring fallbacks ──────────────────────────────────────────────
  return normalized.contains('grok-imagine') ||
      normalized.contains('grok-2-image') ||
      normalized.contains('image-generation') ||
      normalized.contains('video-generation') ||
      normalized.contains('audio-generation') ||
      normalized.contains('seedance') ||
      normalized.contains('cogvideo') ||
      normalized.contains('cogvideox') ||
      normalized.contains('kling') ||
      normalized.contains('hailuo') ||
      normalized.contains('veo') ||
      normalized.contains('vidu') ||
      normalized.contains('pika-') ||
      normalized.contains('runway-') ||
      normalized.contains('tts') ||
      normalized.contains('speech') ||
      normalized.contains('cosyvoice') ||
      normalized.contains('stable-audio') ||
      normalized.contains('musicgen');
}

/// 构造生产用 Hermes Talker 自主学习 dispatcher。
SelfLearningLlmDispatcher buildSelfLearningDispatcher({
  required AiChatService chatClient,
  required SettingsController settingsController,
  required MemoryController memoryController,
  int maxToolCallRounds = 8,
}) {
  final memoryTool = AiMemoryTool(
    memoryControllerProvider: () => memoryController,
  );
  final skillManagerTool = AiSkillManagerTool(
    skillsDirProvider: () => settingsController.skillsStoragePath,
  );

  return (SelfLearningContext context) async {
    final session = context.session;

    // ---------- Resolve model ----------
    final models = settingsController.aiModels;
    final selection = selectSelfLearningModel(
      models: models,
      selectedModel: settingsController.selectedAiModel,
      preferredProviderConfigId: session.lastUsedModelId,
    );
    final selected = selection.model;
    if (selected == null) {
      return SelfLearningOutcome(
        summary: '未找到可用于自主学习的文本 AI 模型配置，已跳过本轮自主学习。',
        mutations: <String, Object?>{
          'status_detail': 'no_text_model',
          'model_selection': selection.source,
          if (selection.skippedPreferredModelId != null)
            'skipped_preferred_model_id': selection.skippedPreferredModelId,
          if (selection.skippedPreferredProviderId != null)
            'skipped_preferred_provider_id':
                selection.skippedPreferredProviderId,
        },
      );
    }

    // ---------- Tool catalog (restricted to memory + skill_manager) ----------
    final memoryDef = AiToolRuntimeService.builtinToolDefault(
      AiBuiltinToolKind.memory,
    )?.definition;
    final skillManagerDef = AiToolRuntimeService.builtinToolDefault(
      AiBuiltinToolKind.skillManager,
    )?.definition;
    final toolDefinitions = <AiToolDefinition>[
      if (memoryDef != null) memoryDef,
      if (skillManagerDef != null) skillManagerDef,
    ];

    // ---------- Loop state ----------
    final turns = <AiChatTurn>[
      AiChatTurn(role: AiChatRole.system, content: context.prompt),
      const AiChatTurn(
        role: AiChatRole.user,
        content:
            '请按系统提示执行本轮自我学习，直接调用 memory / skill_manager '
            '工具完成记忆/画像/技能的持久化。完成后用一段中文简要总结本轮学到的要点。',
      ),
    ];

    final responseBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final progress = context.onProgress;
    final responseTimeout = Duration(
      seconds: settingsController.aiResponseTimeoutSeconds,
    );

    AiTokenUsage? aggregateUsage;
    var memoryCallsOk = 0;
    var memoryCallsError = 0;
    var skillCallsOk = 0;
    var skillCallsError = 0;
    final toolCallsLog = <Map<String, Object?>>[];
    // 2026-04-25: 把每一次成功的工具调用拆成 {id, summary} 卡片项，分别归类到
    // memory_changes / profile_changes / skill_changes，供 _SelfLearningCard
    // 渲染。仅记录成功的调用——失败的会进 toolCallsLog 但不影响 UI 摘要。
    final memoryChanges = <Map<String, Object?>>[];
    final profileChanges = <Map<String, Object?>>[];
    final skillChanges = <Map<String, Object?>>[];
    var lastReply = '';
    var roundsRun = 0;
    var nudgeRecovered = false;
    var terminatedReason = 'completed';

    for (var round = 0; round < maxToolCallRounds; round++) {
      roundsRun = round + 1;
      final streaming = await chatClient.sendMessageStream(
        model: selected,
        messages: List<AiChatTurn>.unmodifiable(turns),
        tools: toolDefinitions,
        timeout: responseTimeout,
      );

      final roundResponse = StringBuffer();
      final roundReasoning = StringBuffer();

      await streaming.events.listen((event) {
        switch (event.type) {
          case AiChatStreamEventType.textDelta:
            if (event.textDelta != null) {
              roundResponse.write(event.textDelta);
              responseBuffer.write(event.textDelta);
              if (progress != null) {
                progress(aiResponse: responseBuffer.toString());
              }
            }
            break;
          case AiChatStreamEventType.reasoningDelta:
            if (event.reasoningDelta != null) {
              roundReasoning.write(event.reasoningDelta);
              reasoningBuffer.write(event.reasoningDelta);
              if (progress != null) {
                progress(aiReasoning: reasoningBuffer.toString());
              }
            }
            break;
          case AiChatStreamEventType.toolCallDelta:
          case AiChatStreamEventType.usage:
            break;
        }
      }).asFuture<void>();

      final result = await streaming.result;
      if (result.usage != null) {
        aggregateUsage = aggregateUsage == null
            ? result.usage
            : aggregateUsage.merge(result.usage!);
      }
      lastReply = result.reply.trim();

      // 2026-04-25 — Streaming fallback. 部分后端（或部分模型，例如关闭了
      // streaming / 用 buffered SSE 的 OpenAI 兼容代理）只在最后一帧给出
      // 完整 reply / reasoning，并不会发出 textDelta / reasoningDelta 事件。
      // 此时 roundResponse / roundReasoning 会保持为空，导致卡片完全没有
      // "AI 思考 / AI 响应" 内容，看起来像 BUG。这里在每轮 stream 结束后
      // 用 result.reply / result.reasoning 做兜底回填，保证最终 metadata
      // 一定包含模型实际输出。
      if (roundResponse.isEmpty && result.reply.isNotEmpty) {
        roundResponse.write(result.reply);
        responseBuffer.write(result.reply);
        if (progress != null) {
          progress(aiResponse: responseBuffer.toString());
        }
      }
      if (roundReasoning.isEmpty && result.reasoning.isNotEmpty) {
        roundReasoning.write(result.reasoning);
        reasoningBuffer.write(result.reasoning);
        if (progress != null) {
          progress(aiReasoning: reasoningBuffer.toString());
        }
      }

      // No tool calls → done.
      if (result.toolCalls.isEmpty) {
        // 2026-04-29 — Recovery: 若模型在思考/回复里明显**描述**了要更新画像
        // /记忆/技能（出现 upsert_profile / append / memory / skill_manager
        // 等关键词）但**没有**真正发起工具调用，认定为"光说不做"。给模型
        // 追加一条强提醒并再跑一轮，让它实际动手。最多重试 1 次以避免循环。
        final spokeIntent = _looksLikeUnfulfilledIntent(
          reply: result.reply,
          reasoning: result.reasoning,
        );
        final alreadyNudged = turns.any(
          (t) =>
              t.role == AiChatRole.user &&
              t.content.contains('__SELF_LEARNING_NUDGE__'),
        );
        if (spokeIntent && !alreadyNudged && round + 1 < maxToolCallRounds) {
          turns.add(
            AiChatTurn(
              role: AiChatRole.assistant,
              content: result.reply,
            ),
          );
          turns.add(
            const AiChatTurn(
              role: AiChatRole.user,
              content:
                  '__SELF_LEARNING_NUDGE__\n'
                  '你刚才详细描述了要更新画像/记忆/技能，但并没有**实际调用**'
                  ' memory / skill_manager 工具——这意味着没有任何持久化发生。\n\n'
                  '请立刻执行以下两件事之一：\n'
                  '(A) 如果你确认那些更新值得做：直接发起对应的 memory / '
                  'skill_manager 工具调用（标准 tool_call 格式），不要再描述、'
                  '不要再思考、不要写"我将"，直接调用；\n'
                  '(B) 如果对照系统提示中的硬规则 H1–H5，那些信号其实没达到'
                  '准入门槛：返回一段一句话说明"无变更"，然后结束本轮。\n\n'
                  '请二选一，立即给出结果。',
            ),
          );
          if (progress != null) {
            const nudgeMarker = '\n\n— 检测到光说不做，已要求实际动手 —\n\n';
            responseBuffer.write(nudgeMarker);
            progress(aiResponse: responseBuffer.toString());
          }
          nudgeRecovered = true;
          continue;
        }
        terminatedReason = 'no_tool_calls';
        break;
      }

      // Model invoked tools → append assistant turn then execute each.
      turns.add(
        AiChatTurn(
          role: AiChatRole.assistant,
          content: result.reply,
          toolCalls: result.toolCalls,
        ),
      );

      for (final toolCall in result.toolCalls) {
        final args = AiToolUtils.decodeArguments(toolCall.arguments);
        final normalizedName = toolCall.name.trim().toLowerCase();
        String resultText;
        var ok = false;
        try {
          if (normalizedName == 'memory') {
            final r = await memoryTool.run(args);
            resultText = r.resultText;
            ok = r.stderr.isEmpty;
            if (ok) {
              memoryCallsOk += 1;
              final action = '${args['action'] ?? ''}'.trim().toLowerCase();
              final content = '${args['content'] ?? ''}';
              final id = '${args['id'] ?? ''}'.trim();
              final summary = _summariseMemoryArgs(action, content);
              if (action == 'upsert_profile') {
                profileChanges.add(<String, Object?>{
                  'id': id.isEmpty ? 'user_profile' : id,
                  'summary': summary,
                  'action': action,
                });
              } else if (action == 'append' ||
                  action == 'update' ||
                  action == 'delete') {
                memoryChanges.add(<String, Object?>{
                  'id': id.isEmpty
                      ? (action == 'append' ? '(new)' : '(unknown)')
                      : id,
                  'summary': summary,
                  'action': action,
                });
              }
            } else {
              memoryCallsError += 1;
            }
          } else if (normalizedName == 'skillmanager' ||
              normalizedName == 'skill_manager') {
            final r = await skillManagerTool.run(args);
            resultText = r.resultText;
            ok = r.stderr.isEmpty;
            if (ok) {
              skillCallsOk += 1;
              final action = '${args['action'] ?? ''}'.trim().toLowerCase();
              final id = '${args['name'] ?? args['id'] ?? ''}'.trim();
              final summary = _summariseSkillArgs(args);
              skillChanges.add(<String, Object?>{
                'id': id.isEmpty ? '(unnamed)' : id,
                'summary': summary,
                'action': action,
              });
            } else {
              skillCallsError += 1;
            }
          } else {
            resultText =
                'status: failure\nerror: unknown tool '
                '"${toolCall.name}" — only memory / skill_manager are allowed '
                'in the self-learning sub-agent.';
          }
        } catch (error, stack) {
          resultText = 'status: failure\nerror: $error\n$stack';
          if (normalizedName == 'memory') {
            memoryCallsError += 1;
          } else if (normalizedName == 'skillmanager' ||
              normalizedName == 'skill_manager') {
            skillCallsError += 1;
          }
        }

        toolCallsLog.add(<String, Object?>{
          'round': round,
          'tool': toolCall.name,
          'action': args['action'],
          'ok': ok,
        });

        turns.add(
          AiChatTurn(
            role: AiChatRole.tool,
            content: resultText,
            toolCallId: toolCall.id,
          ),
        );
      }

      // Drop a visual separator in the streamed response so the user can see
      // each round's final summary gets interleaved with tool-call rounds.
      if (progress != null) {
        const separator = '\n\n— 工具已执行，继续下一轮 —\n\n';
        responseBuffer.write(separator);
        progress(aiResponse: responseBuffer.toString());
      }
    }

    if (roundsRun >= maxToolCallRounds && terminatedReason == 'completed') {
      terminatedReason = 'max_rounds';
    }

    // 2026-04-25 — diagnostic: 当一整轮跑完，模型既没产出任何文本/思考，
    // 也未调用任何工具时（responseBuffer + reasoningBuffer 全空、
    // memoryCallsOk + skillCallsOk == 0、lastReply 也空），把
    // model/usage/terminated_reason 等关键状态打印到 silentLog，便于
    // 后续排查"自我学习卡片为空"是后端 buffered SSE / finish_reason / 限流
    // 还是模型本身拒答。仅 debug 构建有效，release 树摇移除。
    if (responseBuffer.isEmpty &&
        reasoningBuffer.isEmpty &&
        memoryCallsOk == 0 &&
        skillCallsOk == 0 &&
        lastReply.isEmpty) {
      silentLog(
        'self_learning_dispatcher',
        'empty self-learning round',
        'model=${selected.modelId} provider=${selected.id} '
            'rounds=$roundsRun terminated=$terminatedReason '
            'memory_errors=$memoryCallsError skill_errors=$skillCallsError '
            'usage=${aggregateUsage?.toJson()}',
      );
    }

    final finalReply = lastReply;
    final summary = finalReply.isEmpty
        ? (memoryCallsOk + skillCallsOk > 0
              ? '本轮已记录 $memoryCallsOk 条记忆变更、$skillCallsOk 条技能变更。'
              : '模型本轮未调用任何工具，也未产生文本结论。')
        : (finalReply.length <= 160
              ? finalReply
              : '${finalReply.substring(0, 157)}…');

    return SelfLearningOutcome(
      summary: summary,
      mutations: <String, Object?>{
        'model_id': selected.modelId,
        'provider_id': selected.id,
        'model_selection': selection.source,
        if (selection.skippedPreferredModelId != null)
          'skipped_preferred_model_id': selection.skippedPreferredModelId,
        if (selection.skippedPreferredProviderId != null)
          'skipped_preferred_provider_id': selection.skippedPreferredProviderId,
        'memory_updates': memoryCallsOk,
        'memory_errors': memoryCallsError,
        'skill_updates': skillCallsOk,
        'skill_errors': skillCallsError,
        'memory_changes': memoryChanges,
        'profile_changes': profileChanges,
        'skill_changes': skillChanges,
        'tool_call_rounds': roundsRun,
        'terminated_reason': terminatedReason,
        if (nudgeRecovered) 'nudge_recovered': true,
        if (toolCallsLog.isNotEmpty) 'tool_calls': toolCallsLog,
        if (aggregateUsage != null) 'usage': aggregateUsage.toJson(),
      },
      aiResponse: responseBuffer.isEmpty ? null : responseBuffer.toString(),
      aiReasoning: reasoningBuffer.isEmpty ? null : reasoningBuffer.toString(),
    );
  };
}

/// 把一次 memory 工具调用的 args 浓缩成一段中文摘要，最多 120 字。
String _summariseMemoryArgs(String action, String content) {
  final flat = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  final preview = flat.length <= 120 ? flat : '${flat.substring(0, 117)}…';
  return switch (action) {
    'append' => preview.isEmpty ? '追加一条记忆' : preview,
    'update' => preview.isEmpty ? '更新记忆内容' : preview,
    'delete' => '删除该条记忆',
    'upsert_profile' => preview.isEmpty ? '更新用户画像' : preview,
    _ => preview,
  };
}

/// 把一次 skill_manager 工具调用的 args 浓缩成一段中文摘要。
String _summariseSkillArgs(Map<String, Object?> args) {
  final action = '${args['action'] ?? ''}'.trim().toLowerCase();
  final desc = '${args['description'] ?? args['summary'] ?? ''}';
  final flat = desc.replaceAll(RegExp(r'\s+'), ' ').trim();
  final preview = flat.length <= 120 ? flat : '${flat.substring(0, 117)}…';
  if (preview.isNotEmpty) return preview;
  return switch (action) {
    'create' => '新增技能',
    'patch' => '细调技能',
    'edit' => '重写技能',
    'delete' => '删除技能',
    _ => action.isEmpty ? '技能操作' : action,
  };
}

/// 启发式：当模型在 reply / reasoning 中提到了要做的更新动作（中文/英文/工具
/// 名都覆盖），但**没有**实际发起 tool_call 时，认为它"光说不做"，需要在
/// 下一轮强制提醒它真正调用工具。门槛刻意取较松：宁可多触发一次保险提醒，
/// 也不要让一轮真正想更新但忘了调用工具的自学习被白白丢弃。
bool _looksLikeUnfulfilledIntent({
  required String reply,
  required String reasoning,
}) {
  final combined = '$reply\n$reasoning';
  if (combined.trim().isEmpty) return false;
  // 显式说"无变更/无更新"的情况不算光说不做。
  final negationPatterns = <RegExp>[
    RegExp(r'无\s*变\s*更'),
    RegExp(r'不\s*需\s*要\s*更新'),
    RegExp(r'本\s*轮\s*放\s*弃'),
    RegExp(r'\bno\s+changes?\b', caseSensitive: false),
    RegExp(r'\bskip(?:ping)?\s+this\s+round\b', caseSensitive: false),
  ];
  for (final neg in negationPatterns) {
    if (neg.hasMatch(combined)) return false;
  }
  final intentPatterns = <RegExp>[
    RegExp(r'upsert_profile'),
    RegExp(r'memory\s*\(\s*action'),
    RegExp(r'skill[_\s-]?manager'),
    RegExp(r'我\s*(?:将|要|准备|打算|应该|会|需要)\s*(?:调用|更新|新增|追加|删除|patch|edit|create)'),
    RegExp(r'(?:更新|新增|追加|修订|纠正)\s*(?:画像|user_profile|记忆|技能|skill)'),
    RegExp(r'\b(?:I\s+(?:will|should|need\s+to)|let\s+me)\s+(?:call|update|append|add|delete|invoke)\b',
        caseSensitive: false),
  ];
  for (final pat in intentPatterns) {
    if (pat.hasMatch(combined)) return true;
  }
  return false;
}
