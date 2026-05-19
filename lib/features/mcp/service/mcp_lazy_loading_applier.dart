import 'dart:convert';
import 'dart:math' as math;

import '../../ai/index.dart';
import '../model/mcp_lazy_loading_mode.dart';

class McpLazyLoadingApplier {
  const McpLazyLoadingApplier();

  static AiResolvedToolCatalog apply({
    required AiResolvedToolCatalog catalog,
    required AiSessionRuntimeContext runtimeContext,
    required AiToolRuntimeService toolRuntimeService,
    Set<String> alreadyLoadedNames = const <String>{},
    Set<String> forceVisibleNames = const <String>{},
  }) {
    final mode = runtimeContext.mcpLazyLoadingMode;
    final mcpEntries = catalog.toolsByName.entries
        .where((entry) => entry.value.source == AiRuntimeToolSource.mcp)
        .toList(growable: false);

    final shouldLazy = switch (mode) {
      McpLazyLoadingMode.disabled => false,
      McpLazyLoadingMode.enabled => mcpEntries.isNotEmpty,
      McpLazyLoadingMode.auto =>
        mcpEntries.isNotEmpty &&
            _estimateMcpCatalogTokens(
                  mcpEntries: mcpEntries,
                  charsPerToken: math.max(
                    1,
                    runtimeContext.estimatedCharactersPerToken,
                  ),
                ) >=
                runtimeContext.mcpLazyLoadingThresholdTokens,
    };

    final toolSearchTool = toolRuntimeService.toolRegistry.getTool(
      AiBuiltinToolKind.toolSearch,
    );

    if (!shouldLazy) {
      if (toolSearchTool is AiToolSearchTool) {
        toolSearchTool.deferredToolNames = const <String>[];
        toolSearchTool.deferredToolDefinitions =
            const <String, AiToolDefinition>{};
      }
      return _stripToolSearch(catalog);
    }

    final deferredEntries = mcpEntries
        .where(
          (entry) =>
              !alreadyLoadedNames.contains(entry.key) &&
              !forceVisibleNames.contains(entry.key),
        )
        .toList(growable: false);
    if (toolSearchTool is AiToolSearchTool) {
      toolSearchTool.deferredToolNames = deferredEntries
          .map((entry) => entry.key)
          .toList(growable: false);
      toolSearchTool.deferredToolDefinitions = <String, AiToolDefinition>{
        for (final entry in deferredEntries) entry.key: entry.value.definition,
      };
    }
    if (deferredEntries.isEmpty) {
      return _stripToolSearch(catalog);
    }

    final deferredKeys = deferredEntries.map((entry) => entry.key).toSet();
    final keptEntries = <MapEntry<String, AiResolvedTool>>[];
    for (final entry in catalog.toolsByName.entries) {
      if (deferredKeys.contains(entry.key)) continue;
      if (entry.value.builtinKind == AiBuiltinToolKind.toolSearch) {
        keptEntries.add(
          MapEntry<String, AiResolvedTool>(
            entry.key,
            _augmentToolSearchDefinition(
              entry.value,
              deferredEntries: deferredEntries,
            ),
          ),
        );
      } else {
        keptEntries.add(entry);
      }
    }
    final notice =
        'MCP tool lazy loading active (${mode.storageValue}): '
        '${deferredEntries.length} of ${mcpEntries.length} MCP tool(s) '
        'deferred. Use ToolSearch to load them on demand.';
    return AiResolvedToolCatalog(
      definitions: keptEntries
          .map((entry) => entry.value.definition)
          .toList(growable: false),
      toolsByName: Map<String, AiResolvedTool>.fromEntries(keptEntries),
      notices: <String>[...catalog.notices, notice],
      mcpServerInstructionsByName: catalog.mcpServerInstructionsByName,
    );
  }

  static AiResolvedTool _augmentToolSearchDefinition(
    AiResolvedTool original, {
    required List<MapEntry<String, AiResolvedTool>> deferredEntries,
  }) {
    final lines = <String>[
      '',
      '## Deferred MCP tools (${deferredEntries.length})',
    ];
    final sample = deferredEntries.take(80);
    for (final entry in sample) {
      final summary = entry.value.definition.description;
      final firstLine = summary.split('\n').first.trim();
      final clipped = firstLine.length > 140
          ? '${firstLine.substring(0, 137)}...'
          : firstLine;
      lines.add('- ${entry.key} — $clipped');
    }
    if (deferredEntries.length > 80) {
      lines.add('- … and ${deferredEntries.length - 80} more.');
    }
    final newDescription =
        '${original.definition.description}\n${lines.join('\n')}';
    return AiResolvedTool(
      name: original.name,
      definition: AiToolDefinition(
        name: original.definition.name,
        description: newDescription,
        parameters: original.definition.parameters,
      ),
      source: original.source,
      builtinKind: original.builtinKind,
      mcpServer: original.mcpServer,
      mcpTool: original.mcpTool,
      skill: original.skill,
      builtinConfig: original.builtinConfig,
    );
  }

  static AiResolvedToolCatalog _stripToolSearch(AiResolvedToolCatalog catalog) {
    final filteredEntries = catalog.toolsByName.entries
        .where(
          (entry) => entry.value.builtinKind != AiBuiltinToolKind.toolSearch,
        )
        .toList(growable: false);
    if (filteredEntries.length == catalog.toolsByName.length) {
      return catalog;
    }
    return AiResolvedToolCatalog(
      definitions: filteredEntries
          .map((entry) => entry.value.definition)
          .toList(growable: false),
      toolsByName: Map<String, AiResolvedTool>.fromEntries(filteredEntries),
      notices: catalog.notices,
      mcpServerInstructionsByName: catalog.mcpServerInstructionsByName,
    );
  }

  static int _estimateMcpCatalogTokens({
    required List<MapEntry<String, AiResolvedTool>> mcpEntries,
    required int charsPerToken,
  }) {
    var totalChars = 0;
    for (final entry in mcpEntries) {
      final def = entry.value.definition;
      totalChars += def.name.length;
      totalChars += def.description.length;
      try {
        totalChars += jsonEncode(def.parameters).length;
      } catch (_) {
        totalChars += 256;
      }
    }
    return (totalChars / charsPerToken).ceil();
  }
}
