/// Centralised heuristics for detecting when a user message endorses a
/// pending Plan-mode proposal.
///
/// Both [AiSessionController] and [AiPromptBuilder] need to make this
/// judgement in subtly different code paths. Keeping the truth-table in a
/// single file prevents the two copies from drifting (a known regression
/// vector — bare "继续" was missing from the controller copy on
/// 2026-04-28, which left the next turn's tool catalog empty and made the
/// model hallucinate `Write` / `TodoWrite` calls).
abstract final class AiPlanApprovalDetector {
  /// Returns `true` when the trimmed [content] should be interpreted as the
  /// user explicitly approving the most recent ExitPlanMode proposal.
  ///
  /// Detection happens in two stages:
  ///  1. Strip whitespace + common ASCII/CJK punctuation → `compactReply`.
  ///     If that exact token matches a known short standalone approval
  ///     ("继续", "好", "OK", "yes", …), return `true`. Exact matching is
  ///     critical here — `contains` would let "继续观察" or "OK 但是…" be
  ///     misclassified as approval.
  ///  2. Otherwise scan for any longer phrase ("do it", "去写吧", …) via
  ///     `contains`, where the surrounding context is unambiguous enough to
  ///     tolerate substring matching.
  static bool looksLikePlanApproval(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    final compactReply = normalized.replaceAll(_punctuationPattern, '');
    if (_standaloneApprovalReplies.contains(compactReply)) {
      return true;
    }
    return _approvalPhrases.any(normalized.contains);
  }

  static bool looksLikePlanExecutionContinuation(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return _executionContinuationPhrases.any(normalized.contains);
  }

  static bool looksLikePlanRecoveryContinuation(
    String content, {
    bool includeGenericContinuations = false,
  }) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    if (_recoveryContinuationPhrases.any(normalized.contains)) {
      return true;
    }
    return includeGenericContinuations &&
        _executionContinuationPhrases.any(normalized.contains);
  }

  static final RegExp _punctuationPattern = RegExp(r'[\s!！。．\.,，、;；:：~～?？]+');

  /// Bare-equality approvals. Must match the FULL compact reply.
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

  /// Substring approvals — phrases long enough that incidental occurrence
  /// in a non-approval message is vanishingly unlikely.
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
}
