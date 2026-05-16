library;
import 'dart:async';

import '../../../../app/support/silent_log.dart';
import '../../../memory/index.dart';
import '../../ai_session_controller.dart';
import '../../model/ai_session.dart';
import '../../model/ai_session_message.dart';

/// 由 bootstrap 注入的 LLM 驱动回调签名。
///
/// 实现者负责：
/// * 使用 [context] 中的提示词调用 chat 服务（限制 allowedBuiltinTools 为
///   `{memory, skill_manager}`）。
/// * 在工具调用循环中，memory / skill_manager 工具会自动执行并写入存储。
/// * 返回对本轮自我学习的简要中文摘要，用于显示在 `selfLearning` 卡片上。
///
/// 返回值会作为 `selfLearning` 消息的 content；metadata 由运行器附加。
typedef SelfLearningLlmDispatcher =
    Future<SelfLearningOutcome> Function(SelfLearningContext context);

/// 由派发器在流式生成期间调用的进度回调。每次调用都会传入当前**累计**的
/// 文本内容（而非增量），运行器内部会节流持久化到 selfLearning 卡片的
/// metadata['ai_response'] / metadata['ai_reasoning'] 字段以驱动 UI 流式展示。
typedef SelfLearningProgressCallback =
    Future<void> Function({String? aiResponse, String? aiReasoning});

/// 构造给 LLM 子 Agent 的上下文。
class SelfLearningContext {
  const SelfLearningContext({
    required this.session,
    required this.prompt,
    required this.userProfileContent,
    required this.autoLearnedMemoriesSummary,
    required this.conversationSlice,
    this.placeholderMessageId,
    this.onProgress,
  });

  final AiSession session;

  /// 完整的中文系统提示（已经插入了 userProfile / 记忆 / 对话切片占位符）。
  final String prompt;

  /// 当前 user_profile 条目内容（空时为空字符串）。
  final String userProfileContent;

  /// 当前带 '自主学习' 标签的记忆的文本摘要。
  final String autoLearnedMemoriesSummary;

  /// 对话切片纯文本（按 "user: ... / assistant: ..." 逐行拼接）。
  final String conversationSlice;

  /// 由运行器预创建的占位 selfLearning 卡片消息 id，派发器可据此自行
  /// 调用 [AiSessionController.updateSelfLearningMessage] 进行更高级的
  /// 增量更新；通常派发器只需使用 [onProgress] 即可。
  final String? placeholderMessageId;

  /// 进度回调；派发器在收到 textDelta / reasoningDelta 时累计文本并调用
  /// 此回调，运行器会节流写入卡片以驱动 UI 流式展示。
  final SelfLearningProgressCallback? onProgress;
}

/// LLM 子 Agent 执行完成后返回给运行器的结果。
class SelfLearningOutcome {
  const SelfLearningOutcome({
    required this.summary,
    this.mutations = const <String, Object?>{},
    this.aiResponse,
    this.aiReasoning,
  });

  /// 展示在 `selfLearning` 卡片上的中文摘要。
  final String summary;

  /// 额外的结构化元数据（例如 `memory_updates`, `skill_updates` 等）。
  final Map<String, Object?> mutations;

  /// LLM 的最终文本响应（可选）。写入卡片 metadata['ai_response']。
  final String? aiResponse;

  /// LLM 的思考 / 推理内容（可选，deepseek-reasoner 等模型支持）。写入
  /// 卡片 metadata['ai_reasoning']。
  final String? aiReasoning;
}

/// 单个会话的自我学习执行后报告。由 [SelfLearningRunner.runForSession]
/// 在终态时返回，供调度器聚合，最终通过 cron `appContext` 写入历史记录，
/// 用于 Crons UI 在 Hermes Talker 历史卡片里展示"影响了哪些会话 / 改了
/// 哪些画像-记忆-技能 / AI 思考与回复"等富信息。
///
/// 2026-04-25 / Phase 4-Hermes-Talker-history.
class SelfLearningSessionReport {
  const SelfLearningSessionReport({
    required this.sessionId,
    required this.sessionTitle,
    required this.status,
    required this.summary,
    this.mutations = const <String, Object?>{},
    this.aiResponse,
    this.aiReasoning,
    this.error,
  });

  factory SelfLearningSessionReport.fromJson(Map<String, Object?> json) {
    return SelfLearningSessionReport(
      sessionId: '${json['session_id'] ?? ''}',
      sessionTitle: '${json['session_title'] ?? ''}',
      status: '${json['status'] ?? 'ok'}',
      summary: '${json['summary'] ?? ''}',
      mutations: switch (json['mutations']) {
        Map<String, Object?> m => m,
        Map other => other.map((k, v) => MapEntry('$k', v)),
        _ => const <String, Object?>{},
      },
      aiResponse: json['ai_response'] as String?,
      aiReasoning: json['ai_reasoning'] as String?,
      error: json['error'] as String?,
    );
  }

  /// 会话 ID（AiSession.id）。
  final String sessionId;

  /// 会话标题（AiSession.title），可能为空字符串。
  final String sessionTitle;

  /// `'ok'` / `'error'` / `'skipped'`。
  final String status;

  /// 中文摘要（与 selfLearning 卡片同源）。
  final String summary;

  /// dispatcher 返回的结构化变更（memory/profile/skill changes 等）。
  final Map<String, Object?> mutations;

  final String? aiResponse;
  final String? aiReasoning;

  /// 仅在 status='error' 时填充。
  final String? error;

  Map<String, Object?> toJson() => <String, Object?>{
        'session_id': sessionId,
        'session_title': sessionTitle,
        'status': status,
        'summary': summary,
        if (mutations.isNotEmpty) 'mutations': mutations,
        if (aiResponse != null && aiResponse!.isNotEmpty)
          'ai_response': aiResponse,
        if (aiReasoning != null && aiReasoning!.isNotEmpty)
          'ai_reasoning': aiReasoning,
        if (error != null && error!.isNotEmpty) 'error': error,
      };
}

class SelfLearningRunner {
  SelfLearningRunner({
    required this.sessionController,
    required this.memoryController,
    this.llmDispatcher,
    this.minConversationTurns = 4,
    this.autoLearnedMemoriesTag = '自主学习',
  });

  final AiSessionController sessionController;
  final MemoryController memoryController;

  /// 真正驱动 LLM 子 Agent 的回调。为空时只会记录一条 "skipped" 卡片。
  final SelfLearningLlmDispatcher? llmDispatcher;

  final int minConversationTurns;
  final String autoLearnedMemoriesTag;

  /// 流式累计文本写入卡片的最小间隔。设置过小会引起频繁 sqflite 写入；
  /// 设置过大会让 UI 看起来不够丝滑。
  ///
  /// 2026-04-29 — 由 250ms 调高到 600ms 默认值。原值与"用户在自主学习流式
  /// 期间发出新消息"的场景叠加时，会让中段流式卡片每秒重绘 4 次，与
  /// transcript 的 auto-follow 一起把视图反复推到底部，外观上像抽搐。
  /// 设为可由设置面板覆盖（`updateSelfLearningStreamFlushIntervalMs`），
  /// 全局静态字段以避免向 runner 实例传播大量参数。
  static int streamFlushIntervalMs = 600;
  static Duration get _streamFlushInterval =>
      Duration(milliseconds: streamFlushIntervalMs);

  /// 由 [SelfLearningScheduler] 调用。为单个会话执行一次自我学习流程。
  Future<SelfLearningSessionReport?> runForSession(AiSession session) async {
    SelfLearningSessionReport? finalReport;
    // 1) 标记开始。
    await sessionController.updateSessionMetadata(session.id, <String, Object?>{
      'self_learning_in_progress': true,
    });

    try {
      final latest = sessionController.sessionById(session.id) ?? session;

      // 2) 构造上下文。
      final slice = _buildConversationSlice(latest);
      final sliceMessageCount = _countSliceMessages(latest);
      if (sliceMessageCount < minConversationTurns) {
        // 2026-04-25 — BUG fix: 此前会写一条 status='skipped' 的 selfLearning
        // 卡片，但该卡片本身就是一个 selfLearning checkpoint：下一轮
        // [_countSliceMessages] / [_buildConversationSlice] 会把"已写入卡片之
        // 后"作为新的统计起点，于是真实对话没有积累就被这条占位卡片重置，
        // 用户需要再积累 minConversationTurns 轮**之后**才会真正学习一次，
        // 误以为前面的对话都已被认真学习。修复策略：未达到门槛时彻底跳过
        // 任何持久化写入（含 placeholder / 卡片），仅在 debug 日志里留痕，
        // 让真正的对话轮次能持续累积。
        silentLog(
          'self_learning_runner',
          'runForSession.skipped (insufficient turns)',
          'turns=$sliceMessageCount min=$minConversationTurns '
              'session=${session.id}',
        );
        return null;
      }

      final userProfileContent = memoryController.userProfile?.content ?? '';
      final autoLearned = memoryController
          .memoriesWithTag(autoLearnedMemoriesTag)
          .map((e) => '- ${e.content}')
          .join('\n');
      final prompt = _buildPrompt(
        userProfile: userProfileContent,
        autoLearned: autoLearned,
        slice: slice,
      );

      final context = SelfLearningContext(
        session: latest,
        prompt: prompt,
        userProfileContent: userProfileContent,
        autoLearnedMemoriesSummary: autoLearned,
        conversationSlice: slice,
      );

      // 3) 派发给 LLM 驱动层（可选）。
      final dispatcher = llmDispatcher;
      if (dispatcher == null) {
        // 同样的 checkpoint-poisoning 风险：dispatcher 缺失只是配置问题，
        // 不应消费用户的真实对话进度。仅记日志后返回。
        silentLog(
          'self_learning_runner',
          'runForSession.skipped (no dispatcher)',
          'session=${session.id} '
              'profile_present=${userProfileContent.isNotEmpty} '
              'auto_learned=${memoryController.memoriesWithTag(autoLearnedMemoriesTag).length}',
        );
        return null;
      }

      // 4a) 预先创建 status='streaming' 的占位卡片，供派发器流式追加。
      final placeholderId = await sessionController.appendSelfLearningMessage(
        sessionId: session.id,
        content: '正在自我学习…',
        metadata: const <String, Object?>{
          'status': 'streaming',
          'streaming': true,
        },
      );

      // 节流写入：累计文本由 dispatcher 通过 onProgress 提供，运行器
      // 至多每 [_streamFlushInterval] 持久化一次，避免在长文本流式输出
      // 期间写穿 sqflite。
      String? latestResponse;
      String? latestReasoning;
      String? lastFlushedResponse;
      String? lastFlushedReasoning;
      Timer? flushTimer;
      Future<void>? pendingFlush;

      Future<void> doFlush() async {
        if (placeholderId == null) return;
        final response = latestResponse;
        final reasoning = latestReasoning;
        if (response == lastFlushedResponse &&
            reasoning == lastFlushedReasoning) {
          return;
        }
        lastFlushedResponse = response;
        lastFlushedReasoning = reasoning;
        await sessionController.updateSelfLearningMessage(
          sessionId: session.id,
          messageId: placeholderId,
          metadataPatch: <String, Object?>{
            if (response != null && response.isNotEmpty)
              'ai_response': response,
            if (reasoning != null && reasoning.isNotEmpty)
              'ai_reasoning': reasoning,
          },
        );
      }

      Future<void> onProgress({String? aiResponse, String? aiReasoning}) async {
        if (aiResponse != null) latestResponse = aiResponse;
        if (aiReasoning != null) latestReasoning = aiReasoning;
        flushTimer ??= Timer(_streamFlushInterval, () async {
          flushTimer = null;
          pendingFlush = doFlush();
          await pendingFlush;
          pendingFlush = null;
        });
      }

      final streamingContext = SelfLearningContext(
        session: context.session,
        prompt: context.prompt,
        userProfileContent: context.userProfileContent,
        autoLearnedMemoriesSummary: context.autoLearnedMemoriesSummary,
        conversationSlice: context.conversationSlice,
        placeholderMessageId: placeholderId,
        onProgress: placeholderId == null ? null : onProgress,
      );

      try {
        final outcome = await dispatcher(streamingContext);
        finalReport = SelfLearningSessionReport(
          sessionId: session.id,
          sessionTitle: latest.title,
          status: 'ok',
          summary: outcome.summary,
          mutations: outcome.mutations,
          aiResponse: outcome.aiResponse,
          aiReasoning: outcome.aiReasoning,
        );

        // 终态写入：取消任何待执行的节流计时，等待在途写入完成，
        // 然后用最终结果整体替换 metadata。
        flushTimer?.cancel();
        flushTimer = null;
        if (pendingFlush != null) {
          try {
            await pendingFlush;
          } catch (error, stack) {
            silentLog('self_learning_runner', 'await pendingFlush (success path)', error, stack);
          }
        }

        if (placeholderId != null) {
          await sessionController.updateSelfLearningMessage(
            sessionId: session.id,
            messageId: placeholderId,
            content: outcome.summary,
            replaceMetadata: true,
            metadataPatch: <String, Object?>{
              'status': 'ok',
              ...outcome.mutations,
              if (outcome.aiResponse != null) 'ai_response': outcome.aiResponse,
              if (outcome.aiReasoning != null)
                'ai_reasoning': outcome.aiReasoning,
            },
          );
        } else {
          // 占位卡片创建失败的兜底：直接追加一条最终卡片。
          await _writeCard(
            session.id,
            summary: outcome.summary,
            status: 'ok',
            extra: <String, Object?>{
              ...outcome.mutations,
              if (outcome.aiResponse != null) 'ai_response': outcome.aiResponse,
              if (outcome.aiReasoning != null)
                'ai_reasoning': outcome.aiReasoning,
            },
          );
        }
      } catch (error, stack) {
        flushTimer?.cancel();
        flushTimer = null;
        if (pendingFlush != null) {
          try {
            await pendingFlush;
          } catch (flushError, flushStack) {
            silentLog('self_learning_runner', 'await pendingFlush (error path)', flushError, flushStack);
          }
        }
        finalReport = SelfLearningSessionReport(
          sessionId: session.id,
          sessionTitle: latest.title,
          status: 'error',
          summary: '自我学习失败: $error',
          aiResponse: latestResponse,
          aiReasoning: latestReasoning,
          error: '$error',
        );
        if (placeholderId != null) {
          await sessionController.updateSelfLearningMessage(
            sessionId: session.id,
            messageId: placeholderId,
            content: '自我学习失败: $error',
            replaceMetadata: true,
            metadataPatch: <String, Object?>{
              'status': 'error',
              'error': '$error',
              'stack': stack.toString(),
              if (latestResponse != null && latestResponse!.isNotEmpty)
                'ai_response': latestResponse,
              if (latestReasoning != null && latestReasoning!.isNotEmpty)
                'ai_reasoning': latestReasoning,
            },
          );
        } else {
          rethrow;
        }
      }
    } catch (error, stack) {
      finalReport = SelfLearningSessionReport(
        sessionId: session.id,
        sessionTitle: session.title,
        status: 'error',
        summary: '自我学习失败: $error',
        error: '$error',
      );
      await _writeCard(
        session.id,
        summary: '自我学习失败: $error',
        status: 'error',
        extra: <String, Object?>{'error': '$error', 'stack': stack.toString()},
      );
    } finally {
      // 5) 清理 in-progress 标记。
      await sessionController.updateSessionMetadata(
        session.id,
        <String, Object?>{'self_learning_in_progress': false},
      );
    }
    return finalReport;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _writeCard(
    String sessionId, {
    required String summary,
    required String status,
    Map<String, Object?>? extra,
  }) async {
    final metadata = <String, Object?>{
      'status': status,
      if (extra != null) ...extra,
    };
    await sessionController.appendSelfLearningMessage(
      sessionId: sessionId,
      content: summary,
      metadata: metadata,
    );
  }

  /// 仅纳入"纯净对话"——即真正承载用户意图与助手最终回复的两类消息：
  ///   - kind == user
  ///   - kind == assistant
  ///
  /// 显式排除（即使 role 为 user/assistant）：
  ///   - selfLearning：避免把上一轮自主学习卡片当作新素材，造成自我引用循环
  ///   - reasoning / toolCall / tool：模型思考与工具往返与"长期价值"无关，
  ///     混入会让画像记忆被中间过程污染，并显著增长 prompt
  ///   - mcp / skill / hook / status / compressionPoint：纯系统/编排副作用
  ///
  /// 同时只回看到"最近一条 selfLearning 卡片之后"——之前的所有消息都已经
  /// 被那一轮检查点学习过，不应再次喂入。
  bool _shouldIncludeMessageInSlice(AiSessionMessage m) {
    if (m.isDeleted) return false;
    if (m.kind != AiSessionMessageKind.user &&
        m.kind != AiSessionMessageKind.assistant) {
      return false;
    }
    if (m.role != AiSessionMessageRole.user &&
        m.role != AiSessionMessageRole.assistant) {
      return false;
    }
    return true;
  }

  int _sliceStartIndex(AiSession session) {
    for (var i = session.messages.length - 1; i >= 0; i--) {
      final m = session.messages[i];
      if (m.isDeleted) continue;
      if (m.kind == AiSessionMessageKind.selfLearning) {
        return i + 1;
      }
    }
    return 0;
  }

  String _buildConversationSlice(AiSession session) {
    final startIndex = _sliceStartIndex(session);
    final buffer = StringBuffer();
    for (var i = startIndex; i < session.messages.length; i++) {
      final m = session.messages[i];
      if (!_shouldIncludeMessageInSlice(m)) continue;
      final role = m.kind == AiSessionMessageKind.user ? 'user' : 'assistant';
      buffer.writeln('$role: ${m.content}');
    }
    return buffer.toString().trimRight();
  }

  /// Counts pure user/assistant messages after the most recent
  /// `selfLearning` checkpoint. Robust against multi-line message content
  /// (unlike line counting on the rendered slice).
  int _countSliceMessages(AiSession session) {
    final startIndex = _sliceStartIndex(session);
    var count = 0;
    for (var i = startIndex; i < session.messages.length; i++) {
      if (_shouldIncludeMessageInSlice(session.messages[i])) {
        count += 1;
      }
    }
    return count;
  }

  String _buildPrompt({
    required String userProfile,
    required String autoLearned,
    required String slice,
  }) {
    final profileSection = userProfile.isEmpty ? '(空)' : userProfile;
    final autoLearnedSection = autoLearned.isEmpty ? '(空)' : autoLearned;
    return '''
[系统消息: 这是一次自我学习流程,目的是在不打扰用户的情况下,把本次对话中
**真正具有长期价值**的信号沉淀为长期记忆/画像/技能。请按以下流程严格执行。

══════════════════════════════════════════════════════════════════════
【强制硬规则 — 任何一条违反则本轮立即返回 "无变更" 并结束】
══════════════════════════════════════════════════════════════════════
H1. 你**必须真正调用 memory / skill_manager 工具**才能产生任何持久化效果。
    仅在思考或回复中"描述要做什么"是无效的、会被丢弃。
H2. 严禁基于**单次、偶发、临时性**对话片段（如临时心情、随口一句、
    一次性玩笑、玩梗、一次性切换语气）就更新画像或新增记忆。
H3. 严禁与已有画像/记忆**重复、近义、碎片化**的新增 — 必须先逐条对照
    "当前用户画像" 与 "最近的自主学习记忆"，能合并则合并(update)，
    不能合并且不显著则放弃(no-op)。
H4. 严禁删除用户主动写入(非"自主学习"标签)的记忆。删除仅允许针对自己
    历史新增的、已被新条目完全覆盖的过期条目。
H5. 严禁仅凭一次对话就推断出新的"长期偏好/价值观/身份"。需至少看到
    **同一信号在本次对话中清晰出现 ≥ 2 次**（不同上下文/不同表达），
    或与现有画像中的相关条目**形成可解释的强化/修正关系**。

══════════════════════════════════════════════════════════════════════
【执行步骤】
══════════════════════════════════════════════════════════════════════
S1. 信号筛选 — 在思考中先列出本次对话中**候选信号**（最多 5 条），
    然后逐条用 H1–H5 自检；通过自检的才进入 S2。
S2. 画像更新 — 仅当满足下列**全部**条件才调用 memory(action=upsert_profile)：
    (a) 信号强度高（明确陈述 / 重复出现 / 与已有画像存在张力或缺失）；
    (b) 不属于一次性玩笑/网络梗的临时风格；
    (c) **辩证式**修订：保留已有正确部分，只针对真正变化或缺失的字段
        增/改一段最多 80 字的精炼内容；不要重写无关字段；
    (d) 修订后整体长度增长 ≤ 30%（避免画像被无意义铺陈撑大）。
S3. 通用记忆 — 仅当满足下列**全部**条件才调用 memory(action=append/update)
    并使用 '$autoLearnedMemoriesTag' 标签：
    (a) 是可在**未来其他对话中复用**的事实/经验/决策/偏好（不是"刚才聊了 X"）；
    (b) **不可压缩进画像**（否则应走 S2）；
    (c) 与现有同类记忆不重复也不矛盾（重复→update 现有条目，矛盾→update
        并解释取舍；都不行则放弃）；
    (d) **每条 type=user 记忆必须提供 `title` 字段**（≤30 汉字 / ≤80 ASCII），
        update 且原 title 仍准确时可省略。
S4. 技能 — 仅当出现**完整、可复现、非平凡**的工作流时才调用 skill_manager；
    优先 patch 细调，避免 edit 全量重写；默认保存到全局技能目录。
S5. 输出自然、零痕迹 — 不要向用户提及"记忆/画像/技能"这件事。

══════════════════════════════════════════════════════════════════════
【准入门槛速查表 — 拿不准就**放弃**】
══════════════════════════════════════════════════════════════════════
| 类型 | 该做 | 不该做 |
|------|------|--------|
| 画像 upsert | 强信号、重复出现、修正现有缺陷 | 一次性梗、临时心情、本就涵盖 |
| 记忆 append | 可跨对话复用的事实/经验 | 描述本次对话本身 / 已存在 |
| 记忆 update | 已有条目内容过期或不准 | 新增近义条目 |
| 记忆 delete | 仅删自己历史新增的过期条目 | 删用户手写记忆 |

---

## 当前用户画像
$profileSection

## 最近的自主学习记忆
$autoLearnedSection

## 本次需要学习的对话片段
$slice

══════════════════════════════════════════════════════════════════════
完成后不要回复用户，只用一段中文向系统总结本轮"评估了哪些候选信号、
为何接受或放弃"。如果全部信号都被 H1–H5 拒绝，**直接返回"无变更"** —
这本身就是合格的输出，比强行新增更好。]
''';
  }
}
