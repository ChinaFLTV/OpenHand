const String agentSystemPromptMetadataKey = 'agent_system_prompt';

Map<String, Object?> omitAgentSystemPromptMetadata(
  Map<String, Object?> metadata, {
  String? reason,
}) {
  if (metadata.isEmpty) return const <String, Object?>{};
  final sanitized = Map<String, Object?>.from(metadata);
  final prompt = sanitized.remove(agentSystemPromptMetadataKey);
  if (prompt is String && prompt.isNotEmpty) {
    sanitized[agentSystemPromptMetadataKey] = <String, Object?>{
      'omitted': true,
      'chars': prompt.length,
      if (reason != null) 'reason': reason,
    };
  }
  return sanitized;
}
