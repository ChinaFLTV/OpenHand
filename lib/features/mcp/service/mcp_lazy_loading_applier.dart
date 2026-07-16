import 'dart:convert';
import 'dart:math' as math;

import '../../ai/index.dart';
import '../model/mcp_lazy_loading_mode.dart';

class McpLazyLoadingApplier {
  const McpLazyLoadingApplier();

  static const int _autoModeToolCountThreshold = 40;

  static AiResolvedToolCatalog apply({
    required AiResolvedToolCatalog catalog,
    required AiSessionRuntimeContext runtimeContext,
    AiToolRuntimeService? toolRuntimeService,
    bool keepToolSearchWhenIdle = false,
  }) {
    final mode = runtimeContext.mcpLazyLoadingMode;
    final mcpEntries = catalog.toolsByName.entries
        .where((entry) => entry.value.source == AiRuntimeToolSource.mcp)
        .toList(growable: false);
    final hasToolSearch = catalog.toolsByName.values.any(
      (tool) => tool.builtinKind == AiBuiltinToolKind.toolSearch,
    );

    final shouldLazy =
        hasToolSearch &&
        switch (mode) {
          McpLazyLoadingMode.disabled => false,
          McpLazyLoadingMode.enabled => mcpEntries.isNotEmpty,
          McpLazyLoadingMode.auto =>
            mcpEntries.isNotEmpty &&
                (mcpEntries.length >= _autoModeToolCountThreshold ||
                    _estimateMcpCatalogTokens(
                          mcpEntries: mcpEntries,
                          charsPerToken: math.max(
                            1,
                            runtimeContext.estimatedCharactersPerToken,
                          ),
                        ) >=
                        runtimeContext.mcpLazyLoadingThresholdTokens),
        };

    final toolSearchTool = toolRuntimeService?.toolRegistry.getTool(
      AiBuiltinToolKind.toolSearch,
    );

    if (!shouldLazy) {
      if (toolSearchTool is AiToolSearchTool && !keepToolSearchWhenIdle) {
        toolSearchTool.clearDeferredToolSnapshot();
      }
      return keepToolSearchWhenIdle ? catalog : _stripToolSearch(catalog);
    }

    final deferredEntries = mcpEntries.toList(growable: true)
      ..sort((a, b) => compareToolNamesForAiRequest(a.key, b.key));
    final deferredDefinitions = <String, AiToolDefinition>{
      for (final entry in deferredEntries)
        entry.key: stableToolDefinitionForAiRequest(entry.value.definition),
    };
    final deferredTools = <String, AiResolvedTool>{
      for (final entry in deferredEntries) entry.key: entry.value,
    };
    if (toolSearchTool is AiToolSearchTool) {
      toolSearchTool.setDeferredToolSnapshot(deferredDefinitions);
    }
    if (deferredEntries.isEmpty) {
      return keepToolSearchWhenIdle ? catalog : _stripToolSearch(catalog);
    }

    final deferredKeys = deferredEntries.map((entry) => entry.key).toSet();
    final keptEntries = <MapEntry<String, AiResolvedTool>>[];
    for (final entry in catalog.toolsByName.entries) {
      if (deferredKeys.contains(entry.key)) continue;
      if (entry.value.builtinKind == AiBuiltinToolKind.toolSearch) {
        keptEntries.add(
          MapEntry<String, AiResolvedTool>(
            entry.key,
            _attachDeferredTools(
              entry.value,
              deferredDefinitions: deferredDefinitions,
              deferredTools: deferredTools,
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
        'deferred. Search and invoke them through ToolSearch.';
    return AiResolvedToolCatalog(
      definitions: keptEntries
          .map((entry) => entry.value.definition)
          .toList(growable: false),
      toolsByName: Map<String, AiResolvedTool>.fromEntries(keptEntries),
      notices: <String>[...catalog.notices, notice],
      mcpServerInstructionsByName: catalog.mcpServerInstructionsByName,
    );
  }

  static AiResolvedTool _attachDeferredTools(
    AiResolvedTool original, {
    required Map<String, AiToolDefinition> deferredDefinitions,
    required Map<String, AiResolvedTool> deferredTools,
  }) {
    return AiResolvedTool(
      name: original.name,
      definition: original.definition,
      source: original.source,
      builtinKind: original.builtinKind,
      mcpServer: original.mcpServer,
      mcpTool: original.mcpTool,
      skill: original.skill,
      builtinConfig: original.builtinConfig,
      toolSearchDeferredToolDefinitions:
          Map<String, AiToolDefinition>.unmodifiable(deferredDefinitions),
      toolSearchDeferredTools: Map<String, AiResolvedTool>.unmodifiable(
        deferredTools,
      ),
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
