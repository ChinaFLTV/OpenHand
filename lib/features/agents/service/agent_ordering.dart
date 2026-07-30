import '../model/agent_models.dart';

List<AgentTask> sortedAgentTasksForAttention(
  Iterable<AgentTask> tasks, {
  bool Function(AgentTask task)? test,
  int? limit,
}) {
  return _sortedItems(
    tasks,
    (left, right) {
      final statusCompare = _taskStatusRank(
        left.status,
      ).compareTo(_taskStatusRank(right.status));
      if (statusCompare != 0) return statusCompare;
      return _taskSortTime(right).compareTo(_taskSortTime(left));
    },
    test: test,
    limit: limit,
  );
}

List<AgentTask> recentAgentTasks(
  Iterable<AgentTask> tasks, {
  bool Function(AgentTask task)? test,
  int? limit,
}) {
  return _recentBy(tasks, _taskSortTime, test: test, limit: limit);
}

List<AgentActivityEvent> recentAgentActivities(
  Iterable<AgentActivityEvent> activities, {
  bool Function(AgentActivityEvent event)? test,
  int? limit,
}) {
  return _recentBy(
    activities,
    (event) =>
        event.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    test: test,
    limit: limit,
  );
}

List<AgentAuditEvent> recentAgentAuditEvents(
  Iterable<AgentAuditEvent> events, {
  bool Function(AgentAuditEvent event)? test,
  int? limit,
}) {
  return _recentBy(
    events,
    (event) =>
        event.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    test: test,
    limit: limit,
  );
}

List<AgentApprovalRequest> sortedAgentApprovalsForAttention(
  Iterable<AgentApprovalRequest> approvals, {
  bool Function(AgentApprovalRequest approval)? test,
  int? limit,
}) {
  return _sortedItems(
    approvals,
    (left, right) {
      final pendingCompare = _approvalPendingRank(
        left.status,
      ).compareTo(_approvalPendingRank(right.status));
      if (pendingCompare != 0) return pendingCompare;
      final riskCompare = _approvalRiskRank(
        agentApprovalRiskLevel(right),
      ).compareTo(_approvalRiskRank(agentApprovalRiskLevel(left)));
      if (riskCompare != 0) return riskCompare;
      return _approvalSortTime(right).compareTo(_approvalSortTime(left));
    },
    test: test,
    limit: limit,
  );
}

List<AgentKpiItem> sortedAgentKpisForAttention(
  Iterable<AgentKpiItem> kpis, {
  bool Function(AgentKpiItem item)? test,
  int? limit,
}) {
  return _sortedItems(
    kpis,
    (left, right) {
      final statusCompare = agentKpiStatusRank(
        left.status,
      ).compareTo(agentKpiStatusRank(right.status));
      if (statusCompare != 0) return statusCompare;
      final progressCompare = left.progress.compareTo(right.progress);
      if (progressCompare != 0) return progressCompare;
      return _kpiSortTime(right).compareTo(_kpiSortTime(left));
    },
    test: test,
    limit: limit,
  );
}

List<T> _recentBy<T>(
  Iterable<T> items,
  DateTime Function(T item) timeOf, {
  bool Function(T item)? test,
  int? limit,
}) {
  return _sortedItems(
    items,
    (left, right) => timeOf(right).compareTo(timeOf(left)),
    test: test,
    limit: limit,
  );
}

List<T> _sortedItems<T>(
  Iterable<T> items,
  int Function(T left, T right) compare, {
  bool Function(T item)? test,
  int? limit,
}) {
  if (limit != null && limit <= 0) return <T>[];

  final indexed = <(int, T)>[];
  var index = 0;
  for (final item in items) {
    final currentIndex = index;
    index += 1;
    if (test != null && !test(item)) continue;

    final entry = (currentIndex, item);
    if (limit == null) {
      indexed.add(entry);
      continue;
    }

    if (indexed.length < limit) {
      indexed.add(entry);
      var child = indexed.length - 1;
      while (child > 0) {
        final parent = (child - 1) >> 1;
        if (_compareIndexed(indexed[parent], indexed[child], compare) >= 0) {
          break;
        }
        final swap = indexed[parent];
        indexed[parent] = indexed[child];
        indexed[child] = swap;
        child = parent;
      }
      continue;
    }

    if (_compareIndexed(entry, indexed.first, compare) >= 0) continue;
    indexed[0] = entry;
    var parent = 0;
    while (true) {
      final left = parent * 2 + 1;
      if (left >= indexed.length) break;
      final right = left + 1;
      final child =
          right < indexed.length &&
              _compareIndexed(indexed[right], indexed[left], compare) > 0
          ? right
          : left;
      if (_compareIndexed(indexed[parent], indexed[child], compare) >= 0) {
        break;
      }
      final swap = indexed[parent];
      indexed[parent] = indexed[child];
      indexed[child] = swap;
      parent = child;
    }
  }

  indexed.sort((left, right) => _compareIndexed(left, right, compare));
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

int _compareIndexed<T>(
  (int, T) left,
  (int, T) right,
  int Function(T left, T right) compare,
) {
  final result = compare(left.$2, right.$2);
  if (result != 0) return result;
  return left.$1.compareTo(right.$1);
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

String agentApprovalRiskLevel(AgentApprovalRequest approval) {
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
