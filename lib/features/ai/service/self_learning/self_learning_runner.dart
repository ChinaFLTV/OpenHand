library;

import 'dart:async';

import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/bounded_line_budget.dart';
import '../../../../shared/util/bounded_text_buffer.dart';
import '../../../../shared/util/byte_size_format.dart';
import '../../../../shared/util/text_clip.dart';
import '../../../../shared/util/timer_safety.dart';
import '../../../memory/index.dart';
import '../../ai_session_controller.dart';
import '../../model/ai_session.dart';
import '../../model/ai_session_message.dart';

const int _selfLearningProfileMaxCharacters = 8 * kBytesPerKiB;
const int _selfLearningHistoryMaxCharacters = 16 * kBytesPerKiB;
const int _selfLearningHistoryMaxEntries = 64;
const int _selfLearningHistoryEntryMaxCharacters = 2 * kBytesPerKiB;
const int _selfLearningConversationMaxMessages = 48;
const int _selfLearningConversationMessageMaxCharacters = 4 * kBytesPerKiB;
const String _selfLearningProfileTruncatedWarning = '[画像已截断：本轮禁止修改或删除画像。]';
const int kSelfLearningProgressMaxCharacters = 512 * kBytesPerKiB;

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

/// 由派发器在流式生成期间调用的增量进度回调。运行器会合并、限长并节流持久化
/// 到 selfLearning 卡片，避免每个令牌都复制累计全文。
typedef SelfLearningProgressCallback =
    void Function({String? aiResponseDelta, String? aiReasoningDelta});

/// 构造给 LLM 子 Agent 的上下文。
class SelfLearningContext {
  const SelfLearningContext({
    required this.session,
    required this.prompt,
    required this.userProfileSnapshot,
    required this.userProfileTruncated,
    this.placeholderMessageId,
    this.onProgress,
  });

  final AiSession session;

  /// 完整的中文系统提示（已经插入了 userProfile / 记忆 / 对话切片占位符）。
  final String prompt;

  final UserMemoryEntry? userProfileSnapshot;
  final bool userProfileTruncated;

  /// 由运行器预创建的占位 selfLearning 卡片消息 id，派发器可据此自行
  /// 调用 [AiSessionController.updateSelfLearningMessage] 进行更高级的
  /// 增量更新；通常派发器只需使用 [onProgress] 即可。
  final String? placeholderMessageId;

  /// 增量进度回调；运行器负责累计、限长并节流写入卡片。
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
    if (aiResponse != null && aiResponse!.isNotEmpty) 'ai_response': aiResponse,
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
  /// 由 250ms 调高到 600ms 默认值。原值与"用户在自主学习流式
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
      var latest = sessionController.sessionById(session.id) ?? session;

      // 2) 构造上下文。
      final sliceMessageCount = _countSliceMessages(latest);
      if (sliceMessageCount < minConversationTurns) {
        // 门槛未满足时不得写入占位卡片，否则它会成为新的 checkpoint，
        // 提前截断仍在累积的真实对话窗口。
        silentLog(
          'self_learning_runner',
          '跳过会话自我学习（轮次不足）',
          '对话轮次=$sliceMessageCount 最低轮次=$minConversationTurns '
              '会话=${session.id}',
        );
        return null;
      }

      final dispatcher = llmDispatcher;
      if (dispatcher == null) {
        silentLog(
          'self_learning_runner',
          '跳过会话自我学习（调度器不可用）',
          '会话=${session.id}',
        );
        return null;
      }

      if (!await memoryController.ensureLoaded()) {
        silentLog(
          'self_learning_runner',
          '跳过会话自我学习（记忆不可用）',
          '会话=${session.id}',
        );
        return null;
      }

      latest = sessionController.sessionById(session.id) ?? latest;
      final refreshedSliceMessageCount = _countSliceMessages(latest);
      if (refreshedSliceMessageCount < minConversationTurns) {
        silentLog(
          'self_learning_runner',
          '跳过会话自我学习（对话已变更）',
          '对话轮次=$refreshedSliceMessageCount 最低轮次=$minConversationTurns '
              '会话=${session.id}',
        );
        return null;
      }

      final userProfileEntry = memoryController.userProfile;
      final rawUserProfileContent = userProfileEntry?.content ?? '';
      final autoLearnedEntries =
          memoryController
              .memoriesWithTag(autoLearnedMemoriesTag)
              .where((entry) => entry.type == UserMemoryEntry.userType)
              .toList(growable: false)
            ..sort((left, right) {
              final createdAtCompare = right.createdAt.compareTo(
                left.createdAt,
              );
              if (createdAtCompare != 0) return createdAtCompare;
              return left.id.compareTo(right.id);
            });

      final profileNeedsTruncation =
          rawUserProfileContent.trim().length >
          _selfLearningProfileMaxCharacters;
      final profileBudget = profileNeedsTruncation
          ? _selfLearningProfileMaxCharacters -
                _selfLearningProfileTruncatedWarning.length -
                1
          : _selfLearningProfileMaxCharacters;
      final profileSnapshot = clipTextWithOmissionMarker(
        rawUserProfileContent,
        maxCodeUnits: profileBudget,
        marker: 'user_profile_truncated',
      );
      final userProfileContent = profileSnapshot.text;
      final autoLearned = _renderBoundedAutoLearnedHistory(autoLearnedEntries);
      final slice = _buildConversationSlice(latest);
      final prompt = _buildPrompt(
        userProfile: userProfileContent,
        userProfileTruncated: profileSnapshot.truncated,
        autoLearned: autoLearned,
        slice: slice,
      );

      final context = SelfLearningContext(
        session: latest,
        prompt: prompt,
        userProfileSnapshot: userProfileEntry,
        userProfileTruncated: profileSnapshot.truncated,
      );

      // 3) 派发给 LLM 驱动层（可选）。
      // 4a) 预先创建 status='streaming' 的占位卡片，供派发器流式追加。
      final placeholderId = await sessionController.appendSelfLearningMessage(
        sessionId: session.id,
        content: '正在自我学习…',
        metadata: const <String, Object?>{
          'status': 'streaming',
          'streaming': true,
        },
      );

      // 增量文本统一限长，定时合并写入，避免长流式响应反复复制累计全文。
      final responseProgress = BoundedTextBuffer(
        maxCharacters: kSelfLearningProgressMaxCharacters,
      );
      final reasoningProgress = BoundedTextBuffer(
        maxCharacters: kSelfLearningProgressMaxCharacters,
      );
      String? lastFlushedResponse;
      String? lastFlushedReasoning;
      Timer? flushTimer;
      Future<void>? pendingFlush;
      var flushRequested = false;

      Future<void> doFlush() async {
        if (placeholderId == null) return;
        final response = responseProgress.isEmpty
            ? null
            : responseProgress.text;
        final reasoning = reasoningProgress.isEmpty
            ? null
            : reasoningProgress.text;
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

      Future<void> flushLatest() {
        flushRequested = true;
        final active = pendingFlush;
        if (active != null) return active;
        late final Future<void> current;
        current =
            (() async {
              do {
                flushRequested = false;
                await doFlush();
              } while (flushRequested);
            })().whenComplete(() {
              if (identical(pendingFlush, current)) pendingFlush = null;
            });
        pendingFlush = current;
        return current;
      }

      void onProgress({String? aiResponseDelta, String? aiReasoningDelta}) {
        if (aiResponseDelta != null) responseProgress.append(aiResponseDelta);
        if (aiReasoningDelta != null) {
          reasoningProgress.append(aiReasoningDelta);
        }
        flushTimer ??= startSafeTimer(
          _streamFlushInterval,
          () async {
            flushTimer = null;
            await flushLatest();
          },
          onError: (error, stack) {
            silentLog('self_learning_runner', '流刷新定时器', error, stack);
          },
        );
      }

      final streamingContext = SelfLearningContext(
        session: context.session,
        prompt: context.prompt,
        userProfileSnapshot: context.userProfileSnapshot,
        userProfileTruncated: context.userProfileTruncated,
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
            silentLog('self_learning_runner', '等待待处理刷新（成功路径）', error, stack);
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
            silentLog(
              'self_learning_runner',
              '等待待处理刷新（异常路径）',
              flushError,
              flushStack,
            );
          }
        }
        finalReport = SelfLearningSessionReport(
          sessionId: session.id,
          sessionTitle: latest.title,
          status: 'error',
          summary: '自我学习失败: $error',
          aiResponse: responseProgress.isEmpty ? null : responseProgress.text,
          aiReasoning: reasoningProgress.isEmpty
              ? null
              : reasoningProgress.text,
          error: '$error',
        );
        if (placeholderId != null) {
          final latestResponse = responseProgress.isEmpty
              ? null
              : responseProgress.text;
          final latestReasoning = reasoningProgress.isEmpty
              ? null
              : reasoningProgress.text;
          await sessionController.updateSelfLearningMessage(
            sessionId: session.id,
            messageId: placeholderId,
            content: '自我学习失败: $error',
            replaceMetadata: true,
            metadataPatch: <String, Object?>{
              'status': 'error',
              'error': '$error',
              'stack': stack.toString(),
              if (latestResponse != null && latestResponse.isNotEmpty)
                'ai_response': latestResponse,
              if (latestReasoning != null && latestReasoning.isNotEmpty)
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
    final messageCount = _countSliceMessages(session);
    final omitted = messageCount > _selfLearningConversationMaxMessages
        ? messageCount - _selfLearningConversationMaxMessages
        : 0;
    final buffer = StringBuffer();
    if (omitted > 0) buffer.writeln('[已省略更早的 $omitted 条对话]');
    var remainingToSkip = omitted;
    for (var i = startIndex; i < session.messages.length; i++) {
      final m = session.messages[i];
      if (!_shouldIncludeMessageInSlice(m)) continue;
      if (remainingToSkip > 0) {
        remainingToSkip -= 1;
        continue;
      }
      final role = m.kind == AiSessionMessageKind.user ? 'user' : 'assistant';
      final content = clipTextWithOmissionMarker(
        m.content,
        maxCodeUnits: _selfLearningConversationMessageMaxCharacters,
        marker: 'conversation_message_truncated',
      ).text;
      buffer.writeln('$role: $content');
    }
    return buffer.toString().trimRight();
  }

  /// 统计最近一次自主学习检查点后的纯用户/助手消息，不受多行正文影响。
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
    required bool userProfileTruncated,
    required String autoLearned,
    required String slice,
  }) {
    final profileSection = userProfile.isEmpty ? '(空)' : userProfile;
    final autoLearnedSection = autoLearned.isEmpty ? '(空)' : autoLearned;
    return '''
# 自主学习

目标：仅沉淀可跨对话复用的长期信息，不打扰用户。拿不准时放弃变更。

## 硬规则

- H1：仅 `memory` / `skill_manager` 工具调用会持久化；描述计划不算执行。
- H2：忽略临时心情、随口表达、玩笑、网络梗和一次性语气变化。
- H3：禁止重复、近义或碎片化新增；优先更新现有条目，否则放弃。
- H4：禁止删除用户手写记忆；仅可删除自主学习创建且已被替代的过期条目。
- H5：新增长期偏好、价值观或身份，必须在本段对话中独立出现至少两次，
  或能明确强化、修正现有画像。

## 执行

1. 筛选最多 5 个候选信号，逐项检查 H1–H5。
2. 画像：仅处理明确、稳定且现有画像缺失或不准的信息。保留正确内容，
   单处修改不超过 80 字，整体增长不超过 30%；画像已截断时禁止更新。
3. 记忆：仅保存不可归入画像的可复用事实、经验、决策或偏好，使用
   `$autoLearnedMemoriesTag` 标签。重复或冲突时更新现有条目。用户记忆需提供
   `title`（不超过 30 个汉字或 80 个 ASCII 字符），原标题准确时可省略。
4. 技能：仅保存完整、可复现、非平凡的工作流；优先 `patch`，避免全量重写。

## 上下文

### 当前用户画像
$profileSection
${userProfileTruncated ? _selfLearningProfileTruncatedWarning : ''}

### 最近的自主学习记忆
$autoLearnedSection

### 本次对话片段
$slice

## 输出

完成后仅用简短中文总结候选信号及取舍理由，不解释内部机制。没有合格变更时
仅输出“无变更”。
''';
  }

  static String _renderBoundedAutoLearnedHistory(
    List<UserMemoryEntry> entries,
  ) {
    final rendered = renderLinesWithinBudget<UserMemoryEntry>(
      items: entries,
      maxItems: _selfLearningHistoryMaxEntries,
      maxCharacters: _selfLearningHistoryMaxCharacters,
      lineBuilder: (entry) {
        final content = clipTextWithOmissionMarker(
          entry.content,
          maxCodeUnits: _selfLearningHistoryEntryMaxCharacters - 2,
          marker: 'memory_content_truncated',
        ).text;
        return '- $content';
      },
      omissionMarkerBuilder: (omitted) =>
          '[auto_learned_memories_omitted: $omitted entries]',
    ).text;
    assert(rendered.length <= _selfLearningHistoryMaxCharacters);
    return rendered;
  }
}
