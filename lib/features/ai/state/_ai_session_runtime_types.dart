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
    this.toolDetails = const <String, AiRuntimeToolPreviewDetail>{},
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
  final Map<String, AiRuntimeToolPreviewDetail> toolDetails;

  int get toolCount => toolNames.length;

  AiRuntimeToolPreviewDetail? detailFor(String name) => toolDetails[name];
}

class AiRuntimeToolPreviewDetail {
  const AiRuntimeToolPreviewDetail({
    required this.name,
    required this.source,
    this.displayName = '',
    this.description = '',
    this.serverName = '',
    this.parameters = const <AiRuntimeToolParameterPreview>[],
    this.parameterTotalCount = 0,
  });

  final String name;
  final AiRuntimeToolSource source;
  final String displayName;
  final String description;
  final String serverName;
  final List<AiRuntimeToolParameterPreview> parameters;
  final int parameterTotalCount;

  String get title {
    final labeled = displayName.trim();
    return labeled.isEmpty ? name : labeled;
  }
}

class AiRuntimeToolParameterPreview {
  const AiRuntimeToolParameterPreview({
    required this.name,
    required this.typeLabel,
    required this.required,
    this.description = '',
  });

  final String name;
  final String typeLabel;
  final bool required;
  final String description;
}

class AiSessionDeletionNotice {
  const AiSessionDeletionNotice({
    required this.sessionId,
    required this.sessionTitle,
    required this.deletedByLabel,
    required this.source,
    required this.wasCurrentSession,
  });

  final String sessionId;
  final String sessionTitle;
  final String deletedByLabel;
  final String source;
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
