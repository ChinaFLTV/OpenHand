/// Hermes Talker 自主学习调度器 (Task 17 / 2026-04-25).
///
/// 该调度器会定期（目前由外部 Cron 系统每 5 分钟调用一次 [tick]）
/// 扫描最近 7 天内的 Hermes Talker 会话，为满足触发条件的会话派发
/// 子 Agent 以将对话中的关键结论沉淀到用户记忆 / 技能库。
///
/// 本文件仅实现 **扫描 + 调度骨架 + 信号量并发池**。
/// 真正的子 Agent 派发（`_runForSession`）由任务 18 在运行时注入：
/// 构造 [SelfLearningScheduler] 时提供 [runForSession] 回调即可，
/// 该回调负责针对单个会话执行"自我学习"子 Agent，并持久化
/// `selfLearning` 消息卡片。
///
/// 本模块的职责边界：
/// * 查询候选会话（最近 7 天 + templateId == 'hermes_talker'）。
/// * 排除已有未完成 selfLearning 或正在学习中的会话。
/// * 通过内部 `_Semaphore` 限制最大并发数（默认 5）。
/// * 收集每轮 tick 的统计结果 [SelfLearningTickResult]。
///
/// 故意不持有任何全局可变状态；所有外部依赖通过构造参数注入，
/// 便于在单元测试中打桩。
library;

import 'dart:async';

import '../../../app/state/settings_controller.dart';
import '../data/ai_session_store.dart';
import '../model/ai_session.dart';
import '../model/ai_session_message.dart';
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

  /// 2026-04-25 — 每个被实际运行过的会话的富报告，供 Crons 历史详
  /// 情面板展示"影响了哪些会话 / 改了哪些画像-记忆-技能 / AI 思考与回
  /// 复"。仅包含 dispatcher 调用走完成（成功或失败）的会话，不包含未
  /// 达到 minConversationTurns 门槛而静默跳过的会话。
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
    this.templateId = 'hermes_talker',
    this.minMessagesRequired = 4,
  }) : _semaphore = _Semaphore(concurrency.clamp(1, _maxConcurrency));

  /// 默认并发度（参见 Task 17 计划 §bounded worker pool）。
  static const int _defaultConcurrency = 5;

  /// 并发上限，防止误配置造成超额资源占用。
  static const int _maxConcurrency = 10;

  final AiSessionStore sessionStore;
  final SettingsController settingsController;
  final SelfLearningRunForSession runForSession;
  final Duration lookbackDuration;
  final String templateId;
  final int minMessagesRequired;

  _Semaphore _semaphore;

  /// 调整并发度（例如在用户修改设置时调用）。
  /// 正在运行的任务不会被抢占，但新提交的任务会遵循新的上限。
  void updateConcurrency(int newConcurrency) {
    final clamped = newConcurrency.clamp(1, _maxConcurrency);
    if (clamped == _semaphore.limit) return;
    _semaphore = _Semaphore(clamped);
  }

  /// 扫描候选会话并派发自我学习任务。
  ///
  /// 返回统计结果；无论个别会话成功与否，本方法都不会抛出异常。
  ///
  /// [now] 仅用于测试时注入固定时间；生产代码请使用默认参数。
  Future<SelfLearningTickResult> tick({DateTime? now}) async {
    if (!settingsController.selfLearningEnabled) {
      return const SelfLearningTickResult(
        scanned: 0,
        triggered: 0,
        skipped: 0,
        errors: 0,
      );
    }

    final effectiveNow = now ?? DateTime.now().toUtc();
    final cutoff = effectiveNow.subtract(lookbackDuration);

    List<AiSession> candidates;
    try {
      candidates = await sessionStore.loadSessionsByTemplate(
        templateId: templateId,
        minCreatedAt: cutoff,
      );
    } catch (_) {
      return const SelfLearningTickResult(
        scanned: 0,
        triggered: 0,
        skipped: 0,
        errors: 1,
      );
    }

    int triggered = 0;
    int skipped = 0;
    int errors = 0;
    final reports = <SelfLearningSessionReport>[];

    final futures = <Future<void>>[];
    for (final session in candidates) {
      if (!_isEligible(session)) {
        skipped += 1;
        continue;
      }
      triggered += 1;
      futures.add(
        _dispatch(session).then((report) {
          if (report != null) reports.add(report);
        }).catchError((_) {
          errors += 1;
        }),
      );
    }

    await Future.wait(futures);

    return SelfLearningTickResult(
      scanned: candidates.length,
      triggered: triggered,
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

  Future<SelfLearningSessionReport?> _dispatch(AiSession session) async {
    await _semaphore.acquire();
    try {
      return await runForSession(session);
    } finally {
      _semaphore.release();
    }
  }
}

/// 有界异步信号量。实现最小 FIFO 公平：
/// 当许可用尽时，后续调用会进入等待队列，按 [acquire] 调用顺序依次唤醒。
class _Semaphore {
  _Semaphore(this.limit) : _available = limit {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be >= 1');
    }
  }

  final int limit;
  int _available;
  final _waiters = <Completer<void>>[];

  Future<void> acquire() {
    if (_available > 0) {
      _available -= 1;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      next.complete();
      return;
    }
    if (_available < limit) {
      _available += 1;
    }
  }
}
