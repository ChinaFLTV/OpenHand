import '../../../../shared/util/input_value_parsing.dart';
import '../runtime/ai_tool_runtime_service.dart';

class McpReverseToolSearchText {
  const McpReverseToolSearchText({
    required this.identity,
    required this.descriptive,
    required this.launchIdentity,
  });

  final String identity;
  final String descriptive;
  final String launchIdentity;
}

Set<String> forceVisibleMcpToolNames(
  AiResolvedToolCatalog catalog,
  bool Function(McpReverseToolSearchText text) shouldInclude,
) {
  final names = <String>{};
  for (final entry in catalog.toolsByName.entries) {
    final tool = entry.value;
    if (tool.source != AiRuntimeToolSource.mcp) continue;
    final text = mcpReverseToolSearchText(tool, catalogName: entry.key);
    if (shouldInclude(text)) names.add(entry.key);
  }
  return names;
}

McpReverseToolSearchText mcpReverseToolSearchText(
  AiResolvedTool tool, {
  required String catalogName,
}) {
  final server = tool.mcpServer;
  final mcpTool = tool.mcpTool;
  final identity = joinMcpToolSearchParts(<Object?>[
    catalogName,
    tool.name,
    tool.definition.name,
    server?.name,
    server?.summary,
    server?.command,
    if (server != null) ...server.args,
    server?.url,
    mcpTool?.id,
    mcpTool?.name,
  ]);
  return McpReverseToolSearchText(
    identity: identity,
    descriptive: joinMcpToolSearchParts(<Object?>[
      identity,
      tool.definition.description,
      mcpTool?.description,
      mcpTool?.outputDescription,
      mcpTool?.annotations,
      mcpTool?.execution,
      mcpTool?.rawMetadata,
    ]),
    launchIdentity: joinMcpToolSearchParts(<Object?>[
      server?.command,
      if (server != null) ...server.args,
      server?.url,
    ]),
  );
}

bool mcpToolSearchTextContainsAny(String value, Iterable<String> needles) {
  for (final needle in needles) {
    if (value.contains(needle)) return true;
  }
  return false;
}

String joinMcpToolSearchParts(Iterable<Object?> parts) {
  return trimmedNonEmptyStrings(parts).join('\n').toLowerCase();
}
