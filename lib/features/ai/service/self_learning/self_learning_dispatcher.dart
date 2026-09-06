import 'dart:async';

import 'package:openhand/shared/util/text_normalization.dart';

import '../../../../app/state/settings_controller.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../../../shared/util/bounded_text_buffer.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/input_value_parsing.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../memory/index.dart';
import '../../model/ai_model_catalog.dart';
import '../../model/ai_model_config.dart';
import '../../model/ai_token_usage.dart';
import '../../tools/ai_tool_utils.dart';
import '../../tools/memory/ai_memory_tool.dart';
import '../../tools/skill/ai_skill_manager_tool.dart';
import '../bash/ai_bash_tool_service.dart';
import '../chat/ai_chat_service.dart';
import '../chat/ai_protocol_adapter.dart';
import '../runtime/ai_tool_runtime_service.dart';
import '../usage/ai_usage_tracker.dart';
import 'self_learning_runner.dart';

const int _selfLearningSummaryPreviewMaxChars = 120;
const int _selfLearningMaxToolCallRounds = 16;
const int _selfLearningMaxToolCallsPerRound = 8;
const int _selfLearningMaxTotalToolCalls = 32;
const int _selfLearningMaxToolArgumentsCharacters = 256 * kBytesPerKiB;
const int _selfLearningMaxTurnCharacters = 64 * kBytesPerKiB;
const Duration _selfLearningEventDrainTimeout = Duration(milliseconds: 800);

final RegExp _selfLearningModelSeparatorPattern = RegExp(r'[\s_]+');
final List<RegExp> _unfulfilledIntentNegationPatterns = <RegExp>[
  RegExp(r'无\s*变\s*更'),
  RegExp(r'不\s*需\s*要\s*更新'),
  RegExp(r'本\s*轮\s*放\s*弃'),
  RegExp(r'\bno\s+changes?\b', caseSensitive: false),
  RegExp(r'\bskip(?:ping)?\s+this\s+round\b', caseSensitive: false),
];
final List<RegExp> _unfulfilledIntentPatterns = <RegExp>[
  RegExp('upsert_profile'),
  RegExp(r'memory\s*\(\s*action'),
  RegExp(r'skill[_\s-]?manager'),
  RegExp(r'我\s*(?:将|要|准备|打算|应该|会|需要)\s*(?:调用|更新|新增|追加|删除|patch|edit|create)'),
  RegExp(r'(?:更新|新增|追加|修订|纠正)\s*(?:画像|user_profile|记忆|技能|skill)'),
  RegExp(
    r'\b(?:I\s+(?:will|should|need\s+to)|let\s+me)\s+(?:call|update|append|add|delete|invoke)\b',
    caseSensitive: false,
  ),
];

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
  final preferredId = nullIfBlank(preferredProviderConfigId);
  AiModelConfig? preferred;
  if (preferredId != null) {
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
  final normalized = modelId.toLowerCase().replaceAll(
    _selfLearningModelSeparatorPattern,
    '-',
  );
  // 仅生成图片的模型。
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
  // 仅生成音频的模型。
  const audioPrefixes = <String>['cogtts', 'cogsound', 't2a'];
  for (final prefix in audioPrefixes) {
    if (normalized.startsWith(prefix)) return true;
  }
  // 目录未覆盖时按模型名特征兜底。
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
  final effectiveMaxToolCallRounds = maxToolCallRounds.clamp(
    1,
    _selfLearningMaxToolCallRounds,
  );
  final memoryTool = AiMemoryTool(
    memoryControllerProvider: () => memoryController,
  );
  final skillManagerTool = AiSkillManagerTool(
    skillsDirProvider: () => settingsController.skillsStoragePath,
  );

  return (SelfLearningContext context) async {
    final session = context.session;

    // 解析可用文本模型。
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

    // 自主学习仅允许记忆与技能工具。
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

    // 初始化受限工具循环。
    final turns = <AiChatTurn>[
      AiChatTurn(role: AiChatRole.system, content: context.prompt),
      const AiChatTurn(
        role: AiChatRole.user,
        content:
            '请按系统提示执行本轮自我学习，直接调用 memory / skill_manager '
            '工具完成记忆/画像/技能的持久化。完成后用一段中文简要总结本轮学到的要点。',
      ),
    ];

    final responseBuffer = BoundedTextBuffer(
      maxCharacters: kSelfLearningProgressMaxCharacters,
    );
    final reasoningBuffer = BoundedTextBuffer(
      maxCharacters: kSelfLearningProgressMaxCharacters,
    );
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
    // 把每一次成功的工具调用拆成 {id, summary} 卡片项，分别归类到
    // memory_changes / profile_changes / skill_changes，供 _SelfLearningCard
    // 渲染。仅记录成功的调用——失败的会进 toolCallsLog 但不影响 UI 摘要。
    final memoryChanges = <Map<String, Object?>>[];
    final profileChanges = <Map<String, Object?>>[];
    final skillChanges = <Map<String, Object?>>[];
    var lastReply = '';
    var roundsRun = 0;
    var totalToolCalls = 0;
    var nudgeRecovered = false;
    var terminatedReason = 'completed';

    for (var round = 0; round < effectiveMaxToolCallRounds; round++) {
      roundsRun = round + 1;
      final streaming = await AiUsageTraceContext.runDerived(
        source: AiUsageSource.selfLearning,
        operation: 'self_learning_round',
        metadata: <String, Object?>{'round': roundsRun},
        body: () => chatClient.sendMessageStream(
          model: selected,
          messages: List<AiChatTurn>.unmodifiable(turns),
          tools: toolDefinitions,
          timeout: responseTimeout,
          streamIdleTimeout: responseTimeout,
        ),
      );

      var receivedResponseDelta = false;
      var receivedReasoningDelta = false;
      final subscription = streaming.events.listen((event) {
        switch (event.type) {
          case AiChatStreamEventType.textDelta:
            final delta = event.textDelta;
            if (delta != null && delta.isNotEmpty) {
              receivedResponseDelta = true;
              responseBuffer.append(delta);
              progress?.call(aiResponseDelta: delta);
            }
          case AiChatStreamEventType.reasoningDelta:
            final delta = event.reasoningDelta;
            if (delta != null && delta.isNotEmpty) {
              receivedReasoningDelta = true;
              reasoningBuffer.append(delta);
              progress?.call(aiReasoningDelta: delta);
            }
          case AiChatStreamEventType.toolCallDelta:
          case AiChatStreamEventType.usage:
            break;
        }
      });
      final eventDrain = subscription.asFuture<void>();
      late final AiChatStreamResult result;
      try {
        result = await streaming.result.timeout(
          responseTimeout,
          onTimeout: () =>
              throw TimeoutException('自主学习流式响应超过时限。', responseTimeout),
        );
        try {
          await eventDrain.timeout(_selfLearningEventDrainTimeout);
        } on TimeoutException {
          await cancelStreamSubscriptionBounded<AiChatStreamEvent>(
            subscription,
            onError: (error, stack) => silentLog(
              'self_learning_dispatcher',
              '取消延迟的自主学习事件流',
              error,
              stack,
            ),
          );
        }
      } catch (error, stack) {
        final cancel = streaming.cancel;
        if (cancel != null) {
          await runAsyncCleanupBounded(
            cancel,
            onError: (cancelError, cancelStack) => silentLog(
              'self_learning_dispatcher',
              '取消失败的自主学习响应流',
              cancelError,
              cancelStack,
            ),
          );
        }
        await cancelStreamSubscriptionBounded<AiChatStreamEvent>(
          subscription,
          onError: (cancelError, cancelStack) => silentLog(
            'self_learning_dispatcher',
            '取消失败的自主学习事件流',
            cancelError,
            cancelStack,
          ),
        );
        Error.throwWithStackTrace(error, stack);
      }
      if (result.usage != null) {
        aggregateUsage = aggregateUsage == null
            ? result.usage
            : aggregateUsage.merge(result.usage!);
      }
      lastReply = clipTextWithEllipsis(result.reply.trim(), 160);

      // 兼容仅在流结束时返回完整正文的后端。
      if (!receivedResponseDelta && result.reply.isNotEmpty) {
        responseBuffer.append(result.reply);
        progress?.call(aiResponseDelta: result.reply);
      }
      if (!receivedReasoningDelta && result.reasoning.isNotEmpty) {
        reasoningBuffer.append(result.reasoning);
        progress?.call(aiReasoningDelta: result.reasoning);
      }

      // 未调用工具时最多追加一次纠偏提示。
      if (result.toolCalls.isEmpty) {
        final spokeIntent = _looksLikeUnfulfilledIntent(
          reply: result.reply,
          reasoning: result.reasoning,
        );
        final alreadyNudged = turns.any(
          (t) =>
              t.role == AiChatRole.user &&
              t.content.contains('__SELF_LEARNING_NUDGE__'),
        );
        if (spokeIntent &&
            !alreadyNudged &&
            round + 1 < effectiveMaxToolCallRounds) {
          turns.add(
            AiChatTurn(
              role: AiChatRole.assistant,
              content: _boundedSelfLearningTurn(
                result.reply,
                marker: 'assistant_reply_truncated',
              ),
            ),
          );
          turns.add(
            const AiChatTurn(
              role: AiChatRole.user,
              content:
                  '__SELF_LEARNING_NUDGE__\n'
                  '你描述了变更但未调用工具。立即二选一：\n'
                  '- 需要变更：直接调用 memory / skill_manager，不要解释。\n'
                  '- 不满足 H1–H5：仅回复“无变更”。',
            ),
          );
          const nudgeMarker = '\n\n— 已要求模型执行实际变更 —\n\n';
          responseBuffer.append(nudgeMarker);
          progress?.call(aiResponseDelta: nudgeMarker);
          nudgeRecovered = true;
          continue;
        }
        terminatedReason = 'no_tool_calls';
        break;
      }

      if (result.toolCalls.length > _selfLearningMaxToolCallsPerRound ||
          totalToolCalls + result.toolCalls.length >
              _selfLearningMaxTotalToolCalls) {
        throw StateError('自主学习工具调用数量超过安全上限。');
      }
      if (result.toolCalls.any(
        (call) =>
            call.arguments.length > _selfLearningMaxToolArgumentsCharacters,
      )) {
        throw StateError('自主学习工具参数超过安全上限。');
      }
      totalToolCalls += result.toolCalls.length;

      // 记录助手工具请求，再按顺序执行。
      turns.add(
        AiChatTurn(
          role: AiChatRole.assistant,
          content: _boundedSelfLearningTurn(
            result.reply,
            marker: 'assistant_reply_truncated',
          ),
          toolCalls: result.toolCalls,
        ),
      );

      for (final toolCall in result.toolCalls) {
        final args = AiToolUtils.decodeArguments(toolCall.arguments);
        final normalizedName = lowercaseStringFromValue(toolCall.name);
        String resultText;
        var ok = false;
        try {
          if (normalizedName == 'memory') {
            final action = AiToolUtils.readString(args['action']).toLowerCase();
            if (context.userProfileTruncated && action == 'upsert_profile') {
              resultText = 'status: failed\nerror: 用户画像快照已截断，本轮禁止更新画像。';
              memoryCallsError += 1;
            } else {
              final r = await memoryTool.run(
                args,
                requireUnchangedProfile: action == 'upsert_profile',
                expectedUserProfile: context.userProfileSnapshot,
              );
              resultText = r.resultText;
              ok = r.status == BashToolExecutionStatus.success;
              if (ok) {
                memoryCallsOk += 1;
                final content = '${args['content'] ?? ''}';
                final id = AiToolUtils.readString(args['id']);
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
            }
          } else if (normalizedName == 'skillmanager' ||
              normalizedName == 'skill_manager') {
            final r = await skillManagerTool.run(args);
            resultText = r.resultText;
            ok = r.stderr.isEmpty;
            if (ok) {
              skillCallsOk += 1;
              final action = AiToolUtils.readString(
                args['action'],
              ).toLowerCase();
              final id = AiToolUtils.readFirstString(args, const <String>[
                'name',
                'id',
              ]);
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
                'status: failure\nerror: 不支持工具“${toolCall.name}”，'
                '自主学习仅允许 memory / skill_manager。';
          }
        } catch (error, stack) {
          silentLog(
            'self_learning_dispatcher',
            '执行自主学习工具：${toolCall.name}',
            error,
            stack,
          );
          resultText = 'status: failure\nerror: 工具执行失败：$error';
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
            content: _boundedSelfLearningTurn(
              resultText,
              marker: 'tool_result_truncated',
            ),
            toolCallId: toolCall.id,
          ),
        );
      }

      const separator = '\n\n— 工具已执行，继续下一轮 —\n\n';
      responseBuffer.append(separator);
      progress?.call(aiResponseDelta: separator);
    }

    if (roundsRun >= effectiveMaxToolCallRounds &&
        terminatedReason == 'completed') {
      terminatedReason = 'max_rounds';
    }

    // 空结果保留必要诊断，便于区分后端空流、限流和模型拒答。
    if (responseBuffer.isEmpty &&
        reasoningBuffer.isEmpty &&
        memoryCallsOk == 0 &&
        skillCallsOk == 0 &&
        lastReply.isEmpty) {
      silentLog(
        'self_learning_dispatcher',
        '自我学习轮次为空',
        '模型=${selected.modelId} 提供方=${selected.id} '
            '轮次=$roundsRun 终止原因=$terminatedReason '
            '记忆错误=$memoryCallsError 技能错误=$skillCallsError '
            '用量=${aggregateUsage?.toJson()}',
      );
    }

    final summary = lastReply.isEmpty
        ? (memoryCallsOk + skillCallsOk > 0
              ? '本轮已记录 $memoryCallsOk 条记忆变更、$skillCallsOk 条技能变更。'
              : '模型本轮未调用任何工具，也未产生文本结论。')
        : lastReply;

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
        'tool_call_count': totalToolCalls,
        'terminated_reason': terminatedReason,
        if (responseBuffer.startOffset > 0) 'ai_response_truncated': true,
        if (reasoningBuffer.startOffset > 0) 'ai_reasoning_truncated': true,
        if (nudgeRecovered) 'nudge_recovered': true,
        if (toolCallsLog.isNotEmpty) 'tool_calls': toolCallsLog,
        if (aggregateUsage != null) 'usage': aggregateUsage.toJson(),
      },
      aiResponse: responseBuffer.isEmpty ? null : responseBuffer.text,
      aiReasoning: reasoningBuffer.isEmpty ? null : reasoningBuffer.text,
    );
  };
}

/// 把一次 memory 工具调用的 args 浓缩成一段中文摘要，最多 120 字。
String _summariseMemoryArgs(String action, String content) {
  final preview = _compactSelfLearningPreview(content);
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
  final action = AiToolUtils.readString(args['action']).toLowerCase();
  final desc = '${args['description'] ?? args['summary'] ?? ''}';
  final preview = _compactSelfLearningPreview(desc);
  if (preview.isNotEmpty) return preview;
  return switch (action) {
    'create' => '新增技能',
    'patch' => '细调技能',
    'edit' => '重写技能',
    'delete' => '删除技能',
    _ => action.isEmpty ? '技能操作' : action,
  };
}

String _compactSelfLearningPreview(String value) {
  final flat = value.replaceAll(kInlineWhitespacePattern, ' ').trim();
  return clipTextWithEllipsis(flat, _selfLearningSummaryPreviewMaxChars);
}

String _boundedSelfLearningTurn(String value, {required String marker}) {
  if (value.length <= _selfLearningMaxTurnCharacters) return value;
  return clipTextWithOmissionMarker(
    value,
    maxCodeUnits: _selfLearningMaxTurnCharacters,
    marker: marker,
  ).text;
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
  if (nullIfBlank(combined) == null) return false;
  // 显式说"无变更/无更新"的情况不算光说不做。
  for (final neg in _unfulfilledIntentNegationPatterns) {
    if (neg.hasMatch(combined)) return false;
  }
  for (final pat in _unfulfilledIntentPatterns) {
    if (pat.hasMatch(combined)) return true;
  }
  return false;
}
