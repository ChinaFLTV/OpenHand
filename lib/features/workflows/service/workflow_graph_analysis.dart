import 'dart:collection';

import '../model/workflow_definition.dart';

/// 工作流有向图的单次分析结果，统一供编辑校验与执行调度复用。
final class WorkflowGraphAnalysis {
  const WorkflowGraphAnalysis({
    required this.reachableNodeIds,
    required this.topologicalNodeIds,
    required this.outgoingConnections,
    required this.nodeCount,
  });

  final Set<String> reachableNodeIds;
  final List<String> topologicalNodeIds;
  final Map<String, List<WorkflowConnection>> outgoingConnections;
  final int nodeCount;

  bool get isAcyclic => topologicalNodeIds.length == nodeCount;

  List<WorkflowConnection> outgoingFor(String nodeId) =>
      outgoingConnections[nodeId] ?? const <WorkflowConnection>[];

  bool canReach(String sourceNodeId, String targetNodeId) {
    if (!outgoingConnections.containsKey(sourceNodeId) ||
        !outgoingConnections.containsKey(targetNodeId)) {
      return false;
    }
    final visited = <String>{};
    final pending = <String>[sourceNodeId];
    while (pending.isNotEmpty) {
      final nodeId = pending.removeLast();
      if (nodeId == targetNodeId) return true;
      if (!visited.add(nodeId)) continue;
      pending.addAll(
        outgoingFor(nodeId).map((connection) => connection.targetNodeId),
      );
    }
    return false;
  }
}

WorkflowGraphAnalysis analyzeWorkflowGraph({
  required Iterable<String> nodeIds,
  required Iterable<WorkflowConnection> connections,
  required Iterable<String> startNodeIds,
}) {
  final ids = nodeIds.toSet();
  final incomingCounts = <String, int>{for (final id in ids) id: 0};
  final outgoing = <String, List<WorkflowConnection>>{
    for (final id in ids) id: <WorkflowConnection>[],
  };
  for (final connection in connections) {
    if (!ids.contains(connection.sourceNodeId) ||
        !ids.contains(connection.targetNodeId)) {
      continue;
    }
    outgoing[connection.sourceNodeId]!.add(connection);
    incomingCounts[connection.targetNodeId] =
        incomingCounts[connection.targetNodeId]! + 1;
  }

  final reachable = <String>{};
  final pending = startNodeIds.where(ids.contains).toList(growable: true);
  while (pending.isNotEmpty) {
    final nodeId = pending.removeLast();
    if (!reachable.add(nodeId)) continue;
    pending.addAll(
      outgoing[nodeId]!.map((connection) => connection.targetNodeId),
    );
  }

  final ready = ListQueue<String>.from(
    ids.where((id) => incomingCounts[id] == 0),
  );
  final topologicalOrder = <String>[];
  while (ready.isNotEmpty) {
    final nodeId = ready.removeFirst();
    topologicalOrder.add(nodeId);
    for (final connection in outgoing[nodeId]!) {
      final targetId = connection.targetNodeId;
      final remaining = incomingCounts[targetId]! - 1;
      incomingCounts[targetId] = remaining;
      if (remaining == 0) ready.add(targetId);
    }
  }

  return WorkflowGraphAnalysis(
    reachableNodeIds: Set<String>.unmodifiable(reachable),
    topologicalNodeIds: List<String>.unmodifiable(topologicalOrder),
    outgoingConnections: Map<String, List<WorkflowConnection>>.unmodifiable({
      for (final entry in outgoing.entries)
        entry.key: List<WorkflowConnection>.unmodifiable(entry.value),
    }),
    nodeCount: ids.length,
  );
}

String? validateWorkflowOutgoingConnections({
  required Iterable<WorkflowNode> nodes,
  required WorkflowGraphAnalysis graph,
}) {
  for (final node in nodes) {
    final outgoing = graph.outgoingFor(node.id);
    if (node.kind == WorkflowNodeKind.end) {
      if (outgoing.isNotEmpty) return '结束节点不能连接后续节点。';
      continue;
    }
    if (!workflowNodeHasBranches(node)) {
      if (outgoing.isEmpty) return '节点“${node.title}”尚未连接后续节点。';
      continue;
    }
    for (final branch in workflowNodeBranches(node)) {
      if (!outgoing.any((edge) => edge.sourceHandleId == branch.id)) {
        return '节点“${node.title}”的“${branch.label}”分支尚未连接后续节点。';
      }
    }
  }
  return null;
}
