part of '../ai_session_controller.dart';

enum AiSendPhase {
  idle,
  compressing,
  sendingMessage,
  responding,
  awaitingApproval,
}

class AiRuntimeToolPreview {
  const AiRuntimeToolPreview({
    required this.sessionMode,
    required this.fullAccessPermission,
    required this.awaitingPlanApproval,
    required this.planRecoveryInspectionRequired,
    required this.planExecutionApproved,
    required this.toolNames,
    required this.notices,
    required this.gateReason,
    this.supportsToolCalls = true,
  });

  final AiSessionMode sessionMode;
  final bool fullAccessPermission;
  final bool awaitingPlanApproval;
  final bool planRecoveryInspectionRequired;
  final bool planExecutionApproved;
  final List<String> toolNames;
  final List<String> notices;
  final String gateReason;
  final bool supportsToolCalls;

  int get toolCount => toolNames.length;
}

class AiSessionDeletionNotice {
  const AiSessionDeletionNotice({
    required this.sessionId,
    required this.sessionTitle,
    required this.deletedByLabel,
    required this.source,
    required this.deletedAt,
    required this.wasCurrentSession,
  });

  final String sessionId;
  final String sessionTitle;
  final String deletedByLabel;
  final String source;
  final DateTime deletedAt;
  final bool wasCurrentSession;
}

/// 手动压缩调用的结果——成功 / 各类拒绝原因，UI 用来吐 toast。
enum AiManualCompactionStatus {
  success,
  notNeeded,
  cooldown,
  inflight,
  circuitBreaker,
  sessionBusy,
  failed,
  noSession,
}

class AiManualCompactionResult {
  const AiManualCompactionResult({
    required this.status,
    this.message,
    this.retryAfter,
  });

  final AiManualCompactionStatus status;
  final String? message;
  final Duration? retryAfter;

  bool get ok => status == AiManualCompactionStatus.success;
}
