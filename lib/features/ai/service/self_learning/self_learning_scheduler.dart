/// Hermes Talker 自主学习调度器。
///
/// 该调度器会定期（目前由外部 Cron 系统每 5 分钟调用一次 [tick]）
/// 扫描最近 7 天内的 Hermes Talker 会话，为满足触发条件的会话派发
/// 子 Agent 以将对话中的关键结论沉淀到用户记忆 / 技能库。
///
/// 本文件仅实现 **扫描 + 调度骨架 + 有界并发派发**。
/// 真正的子 Agent 派发由 [runForSession] 在运行时注入，负责针对单个
/// 会话执行"自我学习"子 Agent，并持久化 `selfLearning` 消息卡片。
///
/// 本模块的职责边界：
/// * 查询候选会话（最近 7 天 + Hermes Talker 模板）。
/// * 排除已有未完成 selfLearning 或正在学习中的会话。
/// * 按稳定游标分批水合候选，避免历史增长导致单轮内存无上限。
/// * 通过共享 FIFO 信号量限制最大并发数（默认 5）。
/// * 收集每轮 tick 的统计结果 [SelfLearningTickResult]。
///
/// 不持有全局可变状态；外部依赖通过构造参数注入。
library;

import 'dart:async';

import '../../../../app/state/settings_controller.dart';
import '../../../../app/support/silent_log.dart';
import '../../../../shared/util/async_concurrency.dart';
import '../../data/ai_session_store.dart';
import '../../model/ai_session.dart';
import '../../model/ai_session_message.dart';
import '../prompt/ai_prompt_template_assembly.dart';
import 'self_learning_runner.dart' show SelfLearningSessionReport;

/// 单轮 [SelfLearningScheduler.tick] 执行结果。
class SelfLearningTickResult {
  const SelfLearningTickResult({
    required this.scanned,
    required this.triggered,
    required this.skipped,
    required this.errors,
    this.reports = const <SelfLearningSessionReport>[],
  });

  /// 扫描命中的候选会话总数（未过滤前）。
  final int scanned;

  /// 实际派发了自我学习任务的会话数量。
  final int triggered;

  /// 由于"正在学习中"或"最近一条消息已经是 selfLearning"等原因跳过的数量。
  final int skipped;

  /// 派发过程中抛出的异常数量（内部已吞异常，记录为错误计数）。
  final int errors;

  /// 每个被实际运行过的会话的富报告，供 Crons 历史详情面板展示影响范围。
  /// 仅包含 dispatcher 调用已完成（成功或失败）的会话。
  final List<SelfLearningSessionReport> reports;

  @override
  String toString() =>
      'SelfLearningTickResult(scanned=$scanned, triggered=$triggered, '
      'skipped=$skipped, errors=$errors, reports=${reports.length})';
}

/// 单个会话的自我学习执行回调签名。
///
/// 由调用方（通常是 bootstrap 阶段）注入。调度器负责：
/// * 获取信号量
/// * 调用本回调
/// * 无论成功失败都释放信号量
///
/// 回调自身应负责：
/// * 构造子 Agent 的 prompt（包含对话切片、user_profile、记忆）
/// * 调用 [AiSessionController] / chat 服务运行受限工具集的子 Agent
/// * 收集变更并写入 `selfLearning` 消息卡片
/// * 清理 `metadata['self_learning_in_progress']` 标记
typedef SelfLearningRunForSession =
    Future<SelfLearningSessionReport?> Function(AiSession session);

class SelfLearningScheduler {
  SelfLearningScheduler({
    required this.sessionStore,
    required this.settingsController,
    required this.runForSession,
    int concurrency = _defaultConcurrency,
    this.lookbackDuration = const Duration(days: 7),
    this.templateId = AiPromptTemplatePolicies.hermesTalkerTemplateId,
    this.minMessagesRequired = 4,
  }) : _semaphore = OpenHandAsyncSemaphore(
         _normalizeConcurrency(concurrency),
         maxAllowedPermits: _maxConcurrency,
       );

  /// 默认并发度。
  static const int _defaultConcurrency = 5;

  /// 并发上限，防止误配置造成超额资源占用。
  static const int _maxConcurrency = 10;

  static int _normalizeConcurrency(int value) {
    if (value < 1) return 1;
    return value > _maxConcurrency ? _maxConcurrency : value;
  }

  final AiSessionStore sessionStore;
  final SettingsController settingsController;
  final SelfLearningRunForSession runForSession;
  final Duration lookbackDuration;
  final String templateId;
  final int minMessagesRequired;

  OpenHandAsyncSemaphore _semaphore;
  AiSessionTemplateCursor? _nextCandidateCursor;
  Future<SelfLearningTickResult>? _tickInFlight;

  /// 调整并发度（例如在用户修改设置时调用）。
  /// 正在运行的任务不会被抢占，但新提交的任务会遵循新的上限。
  void updateConcurrency(int newConcurrency) {
    final clamped = _normalizeConcurrency(newConcurrency);
    if (clamped == _semaphore.maxPermits) return;
    _semaphore = OpenHandAsyncSemaphore(
      clamped,
      maxAllowedPermits: _maxConcurrency,
    );
  }

  /// 扫描候选会话并派发自我学习任务。
  ///
  /// 返回统计结果；无论个别会话成功与否，本方法都不会抛出异常。
  Future<SelfLearningTickResult> tick() {
    final active = _tickInFlight;
    if (active != null) return active;
    late final Future<SelfLearningTickResult> current;
    current = _runTick().whenComplete(() {
      if (identical(_tickInFlight, current)) {
        _tickInFlight = null;
      }
    });
    _tickInFlight = current;
    return current;
  }

  Future<SelfLearningTickResult> _runTick() async {
    if (!settingsController.selfLearningEnabled) {
      return const SelfLearningTickResult(
        scanned: 0,
        triggered: 0,
        skipped: 0,
        errors: 0,
      );
    }

    final cutoff = DateTime.now().toUtc().subtract(lookbackDuration);

    AiSessionTemplatePage candidatePage;
    try {
      final activeCursor = _nextCandidateCursor;
      candidatePage = await sessionStore.loadSessionPageByTemplate(
        templateId: templateId,
        minCreatedAt: cutoff,
        after: activeCursor,
      );
      if (activeCursor != null &&
          candidatePage.sessions.isEmpty &&
          candidatePage.nextCursor == null) {
        candidatePage = await sessionStore.loadSessionPageByTemplate(
          templateId: templateId,
          minCreatedAt: cutoff,
        );
      }
    } catch (error, stack) {
      silentLog('self_learning_scheduler', '加载自主学习候选会话', error, stack);
      return const SelfLearningTickResult(
        scanned: 0,
        triggered: 0,
        skipped: 0,
        errors: 1,
      );
    }
    _nextCandidateCursor = candidatePage.nextCursor;
    final candidates = candidatePage.sessions;

    var skipped = 0;
    final futures = <Future<_SelfLearningDispatchOutcome>>[];
    for (final session in candidates) {
      if (!_isEligible(session)) {
        skipped += 1;
        continue;
      }
      futures.add(_dispatchSafely(session));
    }

    final outcomes = await Future.wait(futures);
    final reports = <SelfLearningSessionReport>[
      for (final outcome in outcomes)
        if (outcome.report != null) outcome.report!,
    ];
    final errors = outcomes.where((outcome) => outcome.failed).length;

    return SelfLearningTickResult(
      scanned: candidates.length,
      triggered: futures.length,
      skipped: skipped,
      errors: errors,
      reports: List<SelfLearningSessionReport>.unmodifiable(reports),
    );
  }

  bool _isEligible(AiSession session) {
    if (session.messages.length < minMessagesRequired) return false;

    // 正在学习中 → 跳过。
    final inProgress = session.metadata['self_learning_in_progress'];
    if (inProgress == true) return false;

    // 最近一条消息已经是 selfLearning → 跳过。
    AiSessionMessage? latest;
    for (var i = session.messages.length - 1; i >= 0; i--) {
      final m = session.messages[i];
      if (m.isDeleted) continue;
      latest = m;
      break;
    }
    if (latest == null) return false;
    if (latest.kind == AiSessionMessageKind.selfLearning) return false;

    return true;
  }

  Future<_SelfLearningDispatchOutcome> _dispatchSafely(
    AiSession session,
  ) async {
    final semaphore = _semaphore;
    try {
      return (
        report: await semaphore.withPermit(() => runForSession(session)),
        failed: false,
      );
    } catch (error, stack) {
      silentLog(
        'self_learning_scheduler',
        '执行会话自主学习：${session.id}',
        error,
        stack,
      );
      return (report: null, failed: true);
    }
  }
}

typedef _SelfLearningDispatchOutcome = ({
  SelfLearningSessionReport? report,
  bool failed,
});
