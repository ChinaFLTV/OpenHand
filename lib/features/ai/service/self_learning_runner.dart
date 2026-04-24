/// Hermes Talker 自主学习执行器 (Task 18 / 2026-04-25).
///
/// 本类负责为单个 Hermes Talker 会话派发一次"自我学习"流程：
///
/// 1. 将会话元数据 `self_learning_in_progress` 置为 `true`，防止并发重入。
/// 2. 构造子 Agent 上下文：当前用户画像 + 自主学习记忆 + 最近一条
///    `selfLearning` 消息之后的对话切片。
/// 3. 当可选的 [llmDispatcher] 回调存在时，将上下文交给外部 LLM 驱动的
///    子 Agent 执行（该回调可调用 memory / skill_manager 工具）；否则
///    仅记录一条 status='skipped' 的 `selfLearning` 消息。
/// 4. 将执行结果持久化为 `selfLearning` 消息卡片。
/// 5. 清理 `self_learning_in_progress` 标记。
///
/// 错误处理：任何异常都会被捕获并写入一条 `status='error'` 的
/// `selfLearning` 消息；`self_learning_in_progress` 始终会被清理。
library;

import '../../memory/memory_controller.dart';
import '../ai_session_controller.dart';
import '../model/ai_session.dart';
import '../model/ai_session_message.dart';

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

/// 构造给 LLM 子 Agent 的上下文。
class SelfLearningContext {
  const SelfLearningContext({
    required this.session,
    required this.prompt,
    required this.userProfileContent,
    required this.autoLearnedMemoriesSummary,
    required this.conversationSlice,
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
}

/// LLM 子 Agent 执行完成后返回给运行器的结果。
class SelfLearningOutcome {
  const SelfLearningOutcome({
    required this.summary,
    this.mutations = const <String, Object?>{},
  });

  /// 展示在 `selfLearning` 卡片上的中文摘要。
  final String summary;

  /// 额外的结构化元数据（例如 `memory_updates`, `skill_updates` 等）。
  final Map<String, Object?> mutations;
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

  /// 由 [SelfLearningScheduler] 调用。为单个会话执行一次自我学习流程。
  Future<void> runForSession(AiSession session) async {
    // 1) 标记开始。
    await sessionController.updateSessionMetadata(
      session.id,
      <String, Object?>{'self_learning_in_progress': true},
    );

    try {
      final latest =
          sessionController.sessionById(session.id) ?? session;

      // 2) 构造上下文。
      final slice = _buildConversationSlice(latest);
      final sliceMessageCount = _countSliceMessages(latest);
      if (sliceMessageCount < minConversationTurns) {
        await _writeCard(
          session.id,
          summary: '对话轮次不足 ($minConversationTurns)，跳过本轮自我学习。',
          status: 'skipped',
          extra: <String, Object?>{
            'conversation_turns': sliceMessageCount,
          },
        );
        return;
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
        await _writeCard(
          session.id,
          summary:
              '未配置 LLM 自主学习分发器（llmDispatcher），本轮仅记录上下文快照。',
          status: 'skipped',
          extra: <String, Object?>{
            'user_profile_present': userProfileContent.isNotEmpty,
            'auto_learned_count':
                memoryController.memoriesWithTag(autoLearnedMemoriesTag).length,
            'conversation_turns': sliceMessageCount,
          },
        );
        return;
      }

      final outcome = await dispatcher(context);

      // 4) 写入 selfLearning 消息卡片。
      await _writeCard(
        session.id,
        summary: outcome.summary,
        status: 'ok',
        extra: outcome.mutations,
      );
    } catch (error, stack) {
      await _writeCard(
        session.id,
        summary: '自我学习失败: $error',
        status: 'error',
        extra: <String, Object?>{
          'error': '$error',
          'stack': stack.toString(),
        },
      );
    } finally {
      // 5) 清理 in-progress 标记。
      await sessionController.updateSessionMetadata(
        session.id,
        <String, Object?>{'self_learning_in_progress': false},
      );
    }
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

  String _buildConversationSlice(AiSession session) {
    int startIndex = 0;
    for (var i = session.messages.length - 1; i >= 0; i--) {
      final m = session.messages[i];
      if (m.isDeleted) continue;
      if (m.kind == AiSessionMessageKind.selfLearning) {
        startIndex = i + 1;
        break;
      }
    }
    final buffer = StringBuffer();
    for (var i = startIndex; i < session.messages.length; i++) {
      final m = session.messages[i];
      if (m.isDeleted) continue;
      final role = switch (m.role) {
        AiSessionMessageRole.user => 'user',
        AiSessionMessageRole.assistant => 'assistant',
        _ => null,
      };
      if (role == null) continue;
      buffer.writeln('$role: ${m.content}');
    }
    return buffer.toString().trimRight();
  }

  /// Counts non-deleted user/assistant messages after the most recent
  /// `selfLearning` checkpoint. Robust against multi-line message content
  /// (unlike line counting on the rendered slice).
  int _countSliceMessages(AiSession session) {
    int startIndex = 0;
    for (var i = session.messages.length - 1; i >= 0; i--) {
      final m = session.messages[i];
      if (m.isDeleted) continue;
      if (m.kind == AiSessionMessageKind.selfLearning) {
        startIndex = i + 1;
        break;
      }
    }
    var count = 0;
    for (var i = startIndex; i < session.messages.length; i++) {
      final m = session.messages[i];
      if (m.isDeleted) continue;
      if (m.role == AiSessionMessageRole.user ||
          m.role == AiSessionMessageRole.assistant) {
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
[系统消息: 这是一次自我学习流程,目的是在不打扰用户的情况下,将本次对话
中沉淀下来的价值信息持久化为长期记忆或技能。请按以下步骤执行:

1. 审视下方对话,提炼出:
   - 用户画像更新 (偏好/角色/关注点/习惯)
   - 通用价值记忆 (不属于画像的经验/事实/决策)
   - 可复用技能 (若本次解决了非平凡的可复现任务)
2. 调用 memory 工具:
   - 对 type=user_profile 的记忆,使用 upsert 而非新建 (全库只允许一条
     user_profile 记忆);在已有画像基础上纠正/精炼,而不是覆盖无关字段。
   - 对 type=user 的自主学习记忆,使用 '$autoLearnedMemoriesTag' 标签;优先更新已有相
     关条目,而不是无限新增。
3. 调用 skill_manager 工具 (仅在出现可复用工作流时):
   - 优先使用 patch 细调,而非 edit 全量重写。
   - 默认保存到用户全局设置中的技能目录。
4. 输出自然、零痕迹;不要向用户提及记忆/画像这件事。

---

## 当前用户画像
$profileSection

## 最近的自主学习记忆
$autoLearnedSection

## 本次需要学习的对话片段
$slice

完成后不要回复用户,只需调用工具并结束本轮。]
''';
  }
}
