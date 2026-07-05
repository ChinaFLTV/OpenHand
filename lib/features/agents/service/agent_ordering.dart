import '../model/agent_models.dart';

List<AgentTask> sortedAgentTasksForAttention(Iterable<AgentTask> tasks) {
  final indexed = tasks.indexed.toList(growable: false);
  indexed.sort((left, right) {
    final statusCompare = _taskStatusRank(
      left.$2.status,
    ).compareTo(_taskStatusRank(right.$2.status));
    if (statusCompare != 0) return statusCompare;
    final timeCompare = _taskSortTime(
      right.$2,
    ).compareTo(_taskSortTime(left.$2));
    if (timeCompare != 0) return timeCompare;
    return left.$1.compareTo(right.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

List<AgentTask> recentAgentTasks(Iterable<AgentTask> tasks) {
  return _recentBy(tasks, _taskSortTime);
}

List<AgentActivityEvent> recentAgentActivities(
  Iterable<AgentActivityEvent> activities,
) {
  return _recentBy(
    activities,
    (event) =>
        event.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

List<AgentAuditEvent> recentAgentAuditEvents(Iterable<AgentAuditEvent> events) {
  return _recentBy(
    events,
    (event) =>
        event.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

List<AgentApprovalRequest> sortedAgentApprovalsForAttention(
  Iterable<AgentApprovalRequest> approvals,
) {
  final indexed = approvals.indexed.toList(growable: false);
  indexed.sort((left, right) {
    final pendingCompare = _approvalPendingRank(
      left.$2.status,
    ).compareTo(_approvalPendingRank(right.$2.status));
    if (pendingCompare != 0) return pendingCompare;
    final riskCompare = _approvalRiskRank(
      _approvalRiskLevel(right.$2),
    ).compareTo(_approvalRiskRank(_approvalRiskLevel(left.$2)));
    if (riskCompare != 0) return riskCompare;
    final timeCompare = _approvalSortTime(
      right.$2,
    ).compareTo(_approvalSortTime(left.$2));
    if (timeCompare != 0) return timeCompare;
    return left.$1.compareTo(right.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

List<AgentKpiItem> sortedAgentKpisForAttention(Iterable<AgentKpiItem> kpis) {
  final indexed = kpis.indexed.toList(growable: false);
  indexed.sort((left, right) {
    final statusCompare = agentKpiStatusRank(
      left.$2.status,
    ).compareTo(agentKpiStatusRank(right.$2.status));
    if (statusCompare != 0) return statusCompare;
    final progressCompare = left.$2.progress.compareTo(right.$2.progress);
    if (progressCompare != 0) return progressCompare;
    final timeCompare = _kpiSortTime(right.$2).compareTo(_kpiSortTime(left.$2));
    if (timeCompare != 0) return timeCompare;
    return left.$1.compareTo(right.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

List<T> _recentBy<T>(Iterable<T> items, DateTime Function(T item) timeOf) {
  final indexed = items.indexed.toList(growable: false);
  indexed.sort((left, right) {
    final timeCompare = timeOf(right.$2).compareTo(timeOf(left.$2));
    if (timeCompare != 0) return timeCompare;
    return left.$1.compareTo(right.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

int _taskStatusRank(AgentTaskStatus status) {
  return switch (status) {
    AgentTaskStatus.waitingApproval => 0,
    AgentTaskStatus.running => 1,
    AgentTaskStatus.ready => 2,
    AgentTaskStatus.backlog => 3,
    AgentTaskStatus.paused => 4,
    AgentTaskStatus.completed => 5,
    AgentTaskStatus.failed => 6,
    AgentTaskStatus.canceled => 7,
  };
}

DateTime _taskSortTime(AgentTask task) {
  return task.updatedAt ??
      task.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

int _approvalPendingRank(AgentApprovalStatus status) {
  return status == AgentApprovalStatus.pending ? 0 : 1;
}

String _approvalRiskLevel(AgentApprovalRequest approval) {
  final raw =
      approval.extra['risk_level'] ??
      approval.extra['riskLevel'] ??
      approval.extra['risk'];
  return '$raw'.trim().toLowerCase();
}

int _approvalRiskRank(String riskLevel) {
  return switch (riskLevel) {
    'critical' || 'destructive' => 4,
    'high' => 3,
    'medium' => 2,
    'low' => 1,
    _ => 0,
  };
}

DateTime _approvalSortTime(AgentApprovalRequest approval) {
  return approval.resolvedAt ??
      approval.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

DateTime _kpiSortTime(AgentKpiItem item) {
  return item.updatedAt ??
      item.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
