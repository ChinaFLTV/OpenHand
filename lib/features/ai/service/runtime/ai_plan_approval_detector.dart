import '../../../../shared/util/input_value_parsing.dart';
import '../../model/ai_session.dart';

/// 集中管理 Plan 模式的批准、继续、恢复与失败状态判定。
///
/// 控制器与提示词构建器共用同一规则，避免不同调用路径的判定漂移。
abstract final class AiPlanApprovalDetector {
  /// 判断 [content] 是否明确批准最近一次 ExitPlanMode 计划。
  ///
  /// 判定顺序：先标准化内容，再排除否定指令，最后匹配完整短回复或明确长短语。
  /// 短回复必须完整匹配，避免把“继续观察”“OK 但是”等内容误判为批准。
  static bool looksLikePlanApproval(String content) {
    final reply = _normalizeReply(content);
    if (reply == null) return false;
    if (_containsNegativePlanAction(reply.normalized, reply.compact)) {
      return false;
    }
    if (_standaloneApprovalReplies.contains(reply.compact)) {
      return true;
    }
    return _approvalPhrases.any(reply.normalized.contains);
  }

  static bool looksLikePlanExecutionContinuation(String content) {
    final reply = _normalizeReply(content);
    if (reply == null) return false;
    if (_containsNegativePlanAction(reply.normalized, reply.compact)) {
      return false;
    }
    return _executionContinuationPhrases.any(reply.normalized.contains);
  }

  static bool looksLikePlanRecoveryContinuation(
    String content, {
    bool includeGenericContinuations = false,
  }) {
    final reply = _normalizeReply(content);
    if (reply == null) return false;
    if (_containsNegativePlanAction(reply.normalized, reply.compact)) {
      return false;
    }
    if (_recoveryContinuationPhrases.any(reply.normalized.contains)) {
      return true;
    }
    return includeGenericContinuations &&
        _executionContinuationPhrases.any(reply.normalized.contains);
  }

  /// 判断最近一个已结束的工具调用是否为计划恢复所关注的失败状态。
  static bool hasRecentToolFailure(AiSession session) {
    final message = latestSettledAiToolCall(session);
    if (message == null) return false;
    return isAiPlanFailureToolStatus(aiToolExecutionStatusOf(message));
  }

  /// 判断助手或工具文本是否绕过 ExitPlanMode 审批入口请求用户批准计划。
  static bool looksLikePlanApprovalRequest(String content) {
    final reply = _normalizeReply(content);
    if (reply == null) return false;
    if (_negativeApprovalRequestPhrases.any(reply.normalized.contains) ||
        _negativeApprovalRequestCompactFragments.any(reply.compact.contains)) {
      return false;
    }
    return _approvalRequestPhrases.any(reply.normalized.contains);
  }

  static final RegExp _punctuationPattern = RegExp(r'[\s!！。．\.,，、;；:：~～?？]+');

  static ({String normalized, String compact})? _normalizeReply(
    String content,
  ) {
    final normalized = lowercaseStringFromValue(content);
    if (normalized.isEmpty) return null;
    return (
      normalized: normalized,
      compact: normalized.replaceAll(_punctuationPattern, ''),
    );
  }

  static bool _containsNegativePlanAction(
    String normalized,
    String compactReply,
  ) {
    return _negativePlanActionPhrases.any(normalized.contains) ||
        _negativePlanActionCompactFragments.any(compactReply.contains);
  }

  static const List<String> _negativePlanActionPhrases = <String>[
    "don't approve",
    'dont approve',
    'do not approve',
    'not approve',
    'not approved',
    'disapprove',
    "don't proceed",
    'dont proceed',
    'do not proceed',
    "don't continue",
    'dont continue',
    'do not continue',
    "don't start",
    'dont start',
    'do not start',
    "don't implement",
    'dont implement',
    'do not implement',
    'not yet',
    'wait first',
    'hold on',
    'hold off',
    'stop now',
    'stop here',
    'stop execution',
    'cancel it',
    'cancel plan',
    'cancel execution',
  ];

  static const List<String> _negativePlanActionCompactFragments = <String>[
    '不批准',
    '不同意',
    '不通过',
    '不要执行',
    '别执行',
    '先别执行',
    '暂不执行',
    '不要开始',
    '别开始',
    '先别开始',
    '不要实现',
    '别实现',
    '不要写',
    '别写',
    '不要做',
    '别做',
    '别继续',
    '等一下',
    '等等',
    '先等',
    '先暂停',
    '暂停一下',
    '取消计划',
    '取消执行',
  ];

  /// 必须完整匹配的短批准回复。
  static const Set<String> _standaloneApprovalReplies = <String>{
    '确认',
    '继续',
    '好',
    '好的',
    '好嘞',
    '可以',
    '行',
    '中',
    '嗯',
    '嗯嗯',
    '嗯好',
    '同意',
    '批准',
    '通过',
    'ok',
    'okay',
    'k',
    'kk',
    'yes',
    'y',
    'yep',
    'yeah',
    'sure',
    'go',
    'continue',
    'proceed',
  };

  /// 可安全按子串匹配的明确批准短语。
  static const List<String> _approvalPhrases = <String>[
    'approve',
    'approved',
    'go ahead',
    'go for it',
    'proceed',
    'start implementing',
    'begin implementation',
    'continue implementation',
    'confirm execution',
    "let's go",
    "let's do it",
    "let's start",
    'do it',
    'ship it',
    'start now',
    'make it so',
    '确认执行',
    '确认开始',
    '开始执行',
    '继续实施',
    '继续执行',
    '开始吧',
    '执行吧',
    '可以执行',
    '可以开始',
    '去写吧',
    '去做吧',
    '去搞吧',
    '去实现',
    '去实现吧',
    '去干吧',
    '动手吧',
    '写吧',
    '做吧',
    '搞吧',
    '干吧',
    '上吧',
    '撸起来',
    '动手',
  ];

  static const List<String> _executionContinuationPhrases = <String>[
    'continue',
    'continue.',
    'go on',
    'keep going',
    'continue the work',
    'continue working',
    'continue implementation',
    'continue improving',
    'continue optimizing',
    'continue fixing',
    'continue debugging',
    'finish it',
    '继续',
    '继续吧',
    '继续做',
    '继续实施',
    '继续开展',
    '继续完成',
    '继续处理',
    '继续调整',
    '继续排查',
    '继续优化',
    '继续完善',
    '继续改进',
    '继续修复',
    '继续推进',
    '继续跟进',
    '接着',
    '接着做',
  ];

  static const List<String> _recoveryContinuationPhrases = <String>[
    'retry',
    'retry it',
    'retry the step',
    'retry the failed step',
    'resume',
    'resume execution',
    'resume from the failed step',
    'rerun',
    'rerun the step',
    'continue from the failed step',
    'continue after the failure',
    'continue after failure',
    '继续执行',
    '继续执行失败步骤',
    '从失败步骤继续',
    '重试',
    '重试一下',
    '重新执行',
    '重新尝试',
    '重新试',
    '恢复执行',
    '恢复上次执行',
  ];

  static const List<String> _negativeApprovalRequestPhrases = <String>[
    'do not ask for plan approval',
    "don't ask for plan approval",
    'never ask for plan approval',
    'not asking for plan approval',
    'without asking for plan approval',
    'no plan approval question',
  ];

  static const List<String> _negativeApprovalRequestCompactFragments = <String>[
    '不要请求计划批准',
    '不要询问计划批准',
    '不要问计划是否可以',
    '不能用聊天请求计划批准',
    '禁止请求计划批准',
    '禁止询问计划批准',
  ];

  static const List<String> _approvalRequestPhrases = <String>[
    'approve the plan',
    'approve plan',
    'plan approval',
    'is the plan okay',
    'is this plan okay',
    'does the plan look good',
    'should i proceed',
    'should we proceed',
    'can i proceed',
    'may i proceed',
    'proceed with implementation',
    'start implementation',
    'start coding',
    'continue to implementation',
    'go ahead with the plan',
    '批准计划',
    '同意计划',
    '计划可以',
    '计划是否',
    '是否批准',
    '是否继续',
    '可以继续',
    '开始实施',
    '开始实现',
    '开始编码',
    '继续执行',
    '继续实施',
    '执行计划',
    '按计划执行',
    '计划没问题',
    '计划可以吗',
  ];
}
