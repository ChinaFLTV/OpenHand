part of '../ai_session_controller.dart';

extension AiSessionControllerManualCompaction on AiSessionController {
  /// 用户主动触发的会话历史压缩。
  ///
  /// 与发送消息时自动压缩复用同一条管线（[_compressIfNeeded]）：
  ///   * 走 [_enqueueOperation] 串行化以确保不会与 sendMessage / refresh 并发；
  ///   * 通过 [_lastManualCompactionAt] / [AiSessionController._manualCompactionDebounce]
  ///     做去抖；通过 [_manualCompactionInflight] 做并发互斥；
  ///   * 上下文窗口占用不超过 20% 时直接拒绝；
  ///   * 触发熔断（[_compressionFailureCountsBySession] 已超阈值）也拒绝。
  ///
  /// 调用方典型流程：
  ///   1. 在 UI 中拼好 [AiSessionRuntimeContext]；
  ///   2. await 本方法；
  ///   3. 根据 [AiManualCompactionResult.status] 弹 toast / 日志。
  Future<AiManualCompactionResult> requestManualCompaction({
    required String sessionId,
    required AiModelConfig model,
    required AiSessionRuntimeContext runtimeContext,
  }) async {
    final normalizedId = sessionId.trim();
    if (normalizedId.isEmpty) {
      return const AiManualCompactionResult(
        status: AiManualCompactionStatus.noSession,
      );
    }
    final session = _sessionsById[normalizedId];
    if (session == null) {
      return const AiManualCompactionResult(
        status: AiManualCompactionStatus.noSession,
      );
    }
    if (sendPhaseForSession(normalizedId) != AiSendPhase.idle) {
      return const AiManualCompactionResult(
        status: AiManualCompactionStatus.sessionBusy,
        message: 'session_busy',
      );
    }
    if (_manualCompactionInflight.contains(normalizedId)) {
      return const AiManualCompactionResult(
        status: AiManualCompactionStatus.inflight,
        message: 'inflight',
      );
    }
    final lastAt = _lastManualCompactionAt[normalizedId];
    if (lastAt != null) {
      final elapsed = DateTime.now().difference(lastAt);
      if (elapsed < AiSessionController._manualCompactionDebounce) {
        return AiManualCompactionResult(
          status: AiManualCompactionStatus.cooldown,
          retryAfter: AiSessionController._manualCompactionDebounce - elapsed,
        );
      }
    }
    final consecutiveFailures =
        _compressionFailureCountsBySession[normalizedId] ?? 0;
    if (consecutiveFailures >=
        AiSessionController._maxConsecutiveCompressionFailures) {
      return const AiManualCompactionResult(
        status: AiManualCompactionStatus.circuitBreaker,
        message: 'circuit_breaker',
      );
    }
    final contextUsage = AiContextWindowUsage.fromMetadata(
      session.lastPromptMetadata,
    );
    if (!contextUsage.canManuallyCompact) {
      return const AiManualCompactionResult(
        status: AiManualCompactionStatus.notNeeded,
        message: 'usage_too_low',
      );
    }
    _manualCompactionInflight.add(normalizedId);
    try {
      return await _enqueueOperation<AiManualCompactionResult>(() async {
        // 串行化进入临界区后重新读取最新 session（可能在排队期间被修改）。
        final freshSession = _sessionsById[normalizedId];
        if (freshSession == null) {
          return const AiManualCompactionResult(
            status: AiManualCompactionStatus.noSession,
          );
        }
        if (sendPhaseForSession(normalizedId) != AiSendPhase.idle) {
          return const AiManualCompactionResult(
            status: AiManualCompactionStatus.sessionBusy,
            message: 'session_busy',
          );
        }
        if (!_shouldCompressSessionHistory(
          freshSession,
          runtimeContext,
          model,
        )) {
          return const AiManualCompactionResult(
            status: AiManualCompactionStatus.notNeeded,
            message: 'nothing_to_compress',
          );
        }
        _setSessionSendPhase(normalizedId, AiSendPhase.compressing);
        notifyListeners();
        try {
          _captureLatestRuntimeContext(runtimeContext);
          final previousCheckpointId =
              freshSession.latestCompressionCheckpointMessageId;
          final updated = await _compressIfNeeded(
            session: freshSession,
            model: model,
            runtimeContext: runtimeContext,
          );
          if (updated.latestCompressionCheckpointMessageId ==
              previousCheckpointId) {
            return const AiManualCompactionResult(
              status: AiManualCompactionStatus.failed,
              message: 'no_change',
            );
          }
          _lastManualCompactionAt[normalizedId] = DateTime.now();
          return const AiManualCompactionResult(
            status: AiManualCompactionStatus.success,
          );
        } finally {
          _clearSessionSendPhase(normalizedId);
          notifyListeners();
        }
      });
    } finally {
      _manualCompactionInflight.remove(normalizedId);
    }
  }
}
