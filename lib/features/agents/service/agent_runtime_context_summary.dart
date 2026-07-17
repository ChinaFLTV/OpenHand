import '../../../shared/util/text_normalization.dart';
import '../model/agent_models.dart';

const List<(String normalized, String display)>
agentCoordinationToolDisplayNames = <(String, String)>[
  ('agentlist', 'AgentList'),
  ('agentdetail', 'AgentDetail'),
  ('agentactivitylog', 'AgentActivityLog'),
  ('agentauditreport', 'AgentAuditReport'),
  ('agentauditrecord', 'AgentAuditRecord'),
  ('agentapprovalrequest', 'AgentApprovalRequest'),
  ('agentkpiupsert', 'AgentKpiUpsert'),
  ('agentresourceupdate', 'AgentResourceUpdate'),
  ('agentclusterconfigure', 'AgentClusterConfigure'),
  ('agentclusterstatus', 'AgentClusterStatus'),
  ('agenttasklist', 'AgentTaskList'),
  ('agenttaskpublish', 'AgentTaskPublish'),
  (agentTaskTrackToolLookupKey, agentTaskTrackToolName),
  (agentTaskProgressToolLookupKey, agentTaskProgressToolName),
  ('agenttaskcancel', 'AgentTaskCancel'),
  ('agenttaskpause', 'AgentTaskPause'),
  ('agenttaskterminate', 'AgentTaskTerminate'),
  ('agenttaskresume', 'AgentTaskResume'),
  ('agenttaskcomplete', 'AgentTaskComplete'),
  (agentTaskResultToolLookupKey, agentTaskResultToolName),
];

Map<String, Object?> agentCapabilityBindingsJson(
  AgentProfile agent, {
  Set<String>? callableAgentToolNames,
}) {
  final normalizedCallableAgentToolNames = callableAgentToolNames == null
      ? null
      : agentNormalizedCallableToolNames(callableAgentToolNames);
  final automationCount = agent.cronIds.length + agent.hookIds.length;
  final promptConstraintCount = agent.instructionIds.length;
  final configured = normalizeAgentBuiltinToolNames(agent.builtinToolNames);
  final sourceBuiltinToolNames =
      normalizedCallableAgentToolNames != null &&
          configured.isEmpty &&
          !agentHasNoCoordinationToolsBinding(configured)
      ? agentCoordinationToolDisplayNames.map((tool) => tool.$2)
      : agentVisibleBuiltinToolNames(configured);
  final builtinToolNames = sourceBuiltinToolNames
      .where((name) {
        if (normalizedCallableAgentToolNames == null ||
            !isAgentCoordinationBuiltinToolName(name)) {
          return true;
        }
        return normalizedCallableAgentToolNames.contains(
          _normalizeToolName(name),
        );
      })
      .toList(growable: false);
  final agentBuiltinToolCount = builtinToolNames
      .where(isAgentCoordinationBuiltinToolName)
      .length;
  final agentToolGroups = _agentBuiltinToolGroupCounts(builtinToolNames);
  return <String, Object?>{
    'skills': agent.skillNames,
    'knowledge_sources': agent.knowledgeSourceIds,
    'memories': agent.memoryIds,
    'mcp_servers': agent.mcpServerNames,
    'builtin_tools': builtinToolNames,
    'cron_ids': agent.cronIds,
    'hook_ids': agent.hookIds,
    'instruction_ids': agent.instructionIds,
    'summary': <String, Object?>{
      'skills': agent.skillNames.length,
      'knowledge_sources': agent.knowledgeSourceIds.length,
      'memories': agent.memoryIds.length,
      'mcp_servers': agent.mcpServerNames.length,
      'builtin_tools': builtinToolNames.length,
      'agent_coordination_tools': agentBuiltinToolCount,
      'agent_coordination_tool_groups': agentToolGroups,
      'automations': automationCount,
      'prompt_constraints': promptConstraintCount,
      'has_external_actions':
          agent.mcpServerNames.isNotEmpty || builtinToolNames.isNotEmpty,
      'has_self_learning_inputs':
          agent.skillNames.isNotEmpty ||
          agent.knowledgeSourceIds.isNotEmpty ||
          agent.memoryIds.isNotEmpty ||
          promptConstraintCount > 0,
    },
  };
}

Set<String> agentNormalizedCallableToolNames(Iterable<String> names) {
  final result = <String>{};
  for (final name in names) {
    final normalized = _normalizeToolName(name);
    if (normalized.isNotEmpty) result.add(normalized);
  }
  return result;
}

Map<String, int> _agentBuiltinToolGroupCounts(Iterable<String> names) {
  final counts = <String, int>{
    'discovery': 0,
    'task_lifecycle': 0,
    'governance': 0,
    'operations': 0,
    'cluster': 0,
  };
  for (final name in names) {
    final group = _agentBuiltinToolGroupName(name);
    if (group == null) continue;
    counts[group] = (counts[group] ?? 0) + 1;
  }
  counts.removeWhere((_, count) => count <= 0);
  return counts;
}

String? _agentBuiltinToolGroupName(String name) {
  if (!isAgentCoordinationBuiltinToolName(name)) return null;
  final normalized = _normalizeToolName(name);
  if (normalized == 'agentlist' || normalized == 'agentdetail') {
    return 'discovery';
  }
  if (normalized.startsWith('agenttask')) return 'task_lifecycle';
  if (normalized.startsWith('agentactivity') ||
      normalized.startsWith('agentaudit') ||
      normalized.startsWith('agentapproval')) {
    return 'governance';
  }
  if (normalized.startsWith('agentkpi') ||
      normalized.startsWith('agentresource')) {
    return 'operations';
  }
  if (normalized.startsWith('agentcluster')) return 'cluster';
  return null;
}

Map<String, Object?> agentWorkspacePolicyJson(AgentProfile agent) {
  final workspacePath = agent.workspacePath.trim();
  final scopePaths = agent.normalizedWorkspaceScopePaths;
  final allowedRoots = dedupeNonEmptyStrings(<String>[
    workspacePath,
    ...scopePaths,
  ]);
  return <String, Object?>{
    'allowed_roots': allowedRoots,
    'writes_limited_to_allowed_roots': true,
    'requires_confirmation_when_empty': allowedRoots.isEmpty,
  };
}

String _normalizeToolName(String value) {
  final buffer = StringBuffer();
  for (final code in value.codeUnits) {
    if ((code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A)) {
      buffer.writeCharCode(code | 0x20);
    }
  }
  return buffer.toString();
}
