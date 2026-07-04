import '../model/agent_models.dart';

Map<String, Object?> agentCapabilityBindingsJson(AgentProfile agent) {
  final automationCount = agent.cronIds.length + agent.hookIds.length;
  final agentBuiltinToolCount = agent.builtinToolNames
      .where(_looksLikeAgentBuiltinToolName)
      .length;
  return <String, Object?>{
    'skills': agent.skillNames,
    'knowledge_sources': agent.knowledgeSourceIds,
    'memories': agent.memoryIds,
    'mcp_servers': agent.mcpServerNames,
    'builtin_tools': agent.builtinToolNames,
    'summary': <String, Object?>{
      'skills': agent.skillNames.length,
      'knowledge_sources': agent.knowledgeSourceIds.length,
      'memories': agent.memoryIds.length,
      'mcp_servers': agent.mcpServerNames.length,
      'builtin_tools': agent.builtinToolNames.length,
      'agent_coordination_tools': agentBuiltinToolCount,
      'automations': automationCount,
      'has_external_actions':
          agent.mcpServerNames.isNotEmpty || agent.builtinToolNames.isNotEmpty,
      'has_self_learning_inputs':
          agent.skillNames.isNotEmpty ||
          agent.knowledgeSourceIds.isNotEmpty ||
          agent.memoryIds.isNotEmpty,
    },
  };
}

Map<String, Object?> agentWorkspacePolicyJson(AgentProfile agent) {
  final workspacePath = agent.workspacePath.trim();
  final scopePaths = agent.normalizedWorkspaceScopePaths;
  final allowedRoots = _dedupeNonEmptyStrings(<String>[
    workspacePath,
    ...scopePaths,
  ]);
  return <String, Object?>{
    'allowed_roots': allowedRoots,
    'writes_limited_to_allowed_roots': true,
    'requires_confirmation_when_empty': allowedRoots.isEmpty,
  };
}

bool _looksLikeAgentBuiltinToolName(String name) {
  final normalized = _normalizeToolName(name);
  return normalized == 'agentlist' ||
      normalized == 'agentdetail' ||
      normalized.startsWith('agentactivity') ||
      normalized.startsWith('agentaudit') ||
      normalized.startsWith('agentapproval') ||
      normalized.startsWith('agentkpi') ||
      normalized.startsWith('agentresource') ||
      normalized.startsWith('agentcluster') ||
      normalized.startsWith('agenttask');
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

List<String> _dedupeNonEmptyStrings(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    if (seen.add(value.toLowerCase())) result.add(value);
  }
  return result;
}
