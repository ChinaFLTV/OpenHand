import 'dart:convert';
import 'dart:math' as math;

import '../../model/ai_builtin_tool_config.dart';
import '../../tools/search/ai_tool_search_tool.dart';
import '../chat/ai_protocol_adapter.dart';
import 'ai_tool_runtime_service.dart';

class AiBuiltinToolLazyLoadingApplier {
  const AiBuiltinToolLazyLoadingApplier();

  static const int defaultAutoThresholdTokens = 8000;
  static const int minAutoThresholdTokens = 1000;

  static int effectiveAutoThresholdTokens(int configuredThresholdTokens) {
    if (configuredThresholdTokens <= 0) {
      return defaultAutoThresholdTokens;
    }
    return math.min(
      defaultAutoThresholdTokens,
      math.max(minAutoThresholdTokens, configuredThresholdTokens),
    );
  }

  static bool hasDeferredCandidates({
    required AiResolvedToolCatalog catalog,
    required AiBuiltinToolLazyLoadingMode mode,
    required int thresholdTokens,
    required int charsPerToken,
    Set<String> promotedToolNames = const <String>{},
  }) {
    if (_findToolSearchEntry(catalog) == null) return false;
    return _shouldDeferAllEligible(
          catalog,
          mode: mode,
          thresholdTokens: thresholdTokens,
          charsPerToken: charsPerToken,
        ) &&
        _deferredBuiltinEntries(
          catalog,
          promotedToolNames: promotedToolNames,
        ).isNotEmpty;
  }

  static AiResolvedToolCatalog apply({
    required AiResolvedToolCatalog catalog,
    required AiResolvedToolCatalog sourceCatalog,
    required AiBuiltinToolLazyLoadingMode mode,
    required int thresholdTokens,
    required int charsPerToken,
    AiToolRuntimeService? toolRuntimeService,
    Set<String> promotedToolNames = const <String>{},
  }) {
    final toolSearchEntry =
        _findToolSearchEntry(catalog) ?? _findToolSearchEntry(sourceCatalog);
    if (toolSearchEntry == null) {
      return catalog;
    }
    final deferAllEligible = _shouldDeferAllEligible(
      catalog,
      mode: mode,
      thresholdTokens: thresholdTokens,
      charsPerToken: charsPerToken,
    );
    if (!deferAllEligible) {
      return catalog;
    }

    final deferredEntries = _deferredBuiltinEntries(
      catalog,
      promotedToolNames: promotedToolNames,
    );
    if (deferredEntries.isEmpty) {
      return catalog;
    }

    final deferredNames = deferredEntries.map((entry) => entry.key).toSet();
    final mergedDeferredDefinitions = <String, AiToolDefinition>{
      for (final entry
          in toolSearchEntry.value.toolSearchDeferredToolDefinitions.entries)
        entry.key: stableToolDefinitionForAiRequest(entry.value),
      for (final entry in deferredEntries)
        entry.key: stableToolDefinitionForAiRequest(entry.value.definition),
    };
    final mergedDeferredTools = <String, AiResolvedTool>{
      ...toolSearchEntry.value.toolSearchDeferredTools,
      for (final entry in deferredEntries) entry.key: entry.value,
    };
    final deferredDefinitionEntries = mergedDeferredDefinitions.entries.toList(
      growable: false,
    )..sort((left, right) => compareToolNamesForAiRequest(left.key, right.key));
    final deferredToolEntries = mergedDeferredTools.entries.toList(
      growable: false,
    )..sort((left, right) => compareToolNamesForAiRequest(left.key, right.key));
    final deferredDefinitions = Map<String, AiToolDefinition>.fromEntries(
      deferredDefinitionEntries,
    );
    final deferredTools = Map<String, AiResolvedTool>.fromEntries(
      deferredToolEntries,
    );
    final toolSearchTool = toolRuntimeService?.toolRegistry.getTool(
      AiBuiltinToolKind.toolSearch,
    );
    if (toolSearchTool is AiToolSearchTool) {
      toolSearchTool.setDeferredToolSnapshot(deferredDefinitions);
    }

    final keptEntries = <MapEntry<String, AiResolvedTool>>[];
    var insertedToolSearch = false;
    for (final entry in catalog.toolsByName.entries) {
      if (deferredNames.contains(entry.key)) continue;
      if (_isToolSearch(entry.value)) {
        keptEntries.add(
          MapEntry<String, AiResolvedTool>(
            entry.key,
            entry.value.withToolSearchDeferredTools(
              definitions: deferredDefinitions,
              tools: deferredTools,
            ),
          ),
        );
        insertedToolSearch = true;
      } else {
        keptEntries.add(entry);
      }
    }
    if (!insertedToolSearch) {
      keptEntries.add(
        MapEntry<String, AiResolvedTool>(
          toolSearchEntry.key,
          toolSearchEntry.value.withToolSearchDeferredTools(
            definitions: deferredDefinitions,
            tools: deferredTools,
          ),
        ),
      );
    }

    return AiResolvedToolCatalog(
      definitions: keptEntries
          .map((entry) => entry.value.definition)
          .toList(growable: false),
      toolsByName: Map<String, AiResolvedTool>.fromEntries(keptEntries),
      notices: <String>[
        ...catalog.notices,
        'Built-in tool lazy loading active: ${deferredEntries.length} built-in tool(s) deferred. Search and invoke them through ToolSearch.',
      ],
      mcpServerInstructionsByName: catalog.mcpServerInstructionsByName,
    );
  }

  static MapEntry<String, AiResolvedTool>? _findToolSearchEntry(
    AiResolvedToolCatalog catalog,
  ) {
    for (final entry in catalog.toolsByName.entries) {
      if (_isToolSearch(entry.value)) {
        return entry;
      }
    }
    return null;
  }

  static bool _isToolSearch(AiResolvedTool tool) =>
      tool.source == AiRuntimeToolSource.builtin &&
      tool.builtinKind == AiBuiltinToolKind.toolSearch;

  static bool _shouldDeferAllEligible(
    AiResolvedToolCatalog catalog, {
    required AiBuiltinToolLazyLoadingMode mode,
    required int thresholdTokens,
    required int charsPerToken,
  }) {
    if (mode == AiBuiltinToolLazyLoadingMode.disabled) {
      return false;
    }
    final deferredEntries = _deferredBuiltinEntries(catalog);
    if (deferredEntries.isEmpty) {
      return false;
    }
    if (mode == AiBuiltinToolLazyLoadingMode.enabled) {
      return true;
    }
    return _estimateBuiltinCatalogTokens(
          catalog: catalog,
          charsPerToken: math.max(1, charsPerToken),
        ) >=
        math.max(1, thresholdTokens);
  }

  static List<MapEntry<String, AiResolvedTool>> _deferredBuiltinEntries(
    AiResolvedToolCatalog catalog, {
    Set<String> promotedToolNames = const <String>{},
  }) {
    final entries = catalog.toolsByName.entries
        .where((entry) {
          final tool = entry.value;
          if (promotedToolNames.contains(tool.definition.name)) return false;
          if (tool.source != AiRuntimeToolSource.builtin) return false;
          if (tool.builtinKind == null ||
              tool.builtinKind == AiBuiltinToolKind.toolSearch) {
            return false;
          }
          if (tool.builtinKind!.isMachineTerminalTool) {
            return false;
          }
          final config = tool.builtinConfig;
          final forceLoad =
              config?.forceLoad ??
              AiBuiltinToolConfig.defaultForceLoadForKind(tool.builtinKind!);
          if (forceLoad) {
            return false;
          }
          final strategy =
              tool.builtinConfig?.loadStrategy ??
              AiBuiltinToolConfig.defaultLoadStrategyForKind(tool.builtinKind!);
          return strategy != AiBuiltinToolLoadStrategy.eager;
        })
        .toList(growable: true);
    entries.sort((left, right) {
      final leftConfig = left.value.builtinConfig;
      final rightConfig = right.value.builtinConfig;
      final sortOrderCompare = _sortOrder(left).compareTo(_sortOrder(right));
      if (sortOrderCompare != 0) return sortOrderCompare;
      final priorityCompare = (leftConfig?.priority ?? 100).compareTo(
        rightConfig?.priority ?? 100,
      );
      if (priorityCompare != 0) return priorityCompare;
      return compareToolNamesForAiRequest(left.key, right.key);
    });
    return entries;
  }

  static int _estimateBuiltinCatalogTokens({
    required AiResolvedToolCatalog catalog,
    required int charsPerToken,
  }) {
    var totalChars = 0;
    for (final entry in catalog.toolsByName.entries) {
      final tool = entry.value;
      if (tool.source != AiRuntimeToolSource.builtin ||
          tool.builtinKind == null ||
          tool.builtinKind == AiBuiltinToolKind.toolSearch) {
        continue;
      }
      final definition = tool.definition;
      totalChars += definition.name.length;
      totalChars += definition.description.length;
      try {
        totalChars += jsonEncode(definition.parameters).length;
      } catch (_) {
        totalChars += 256;
      }
    }
    return (totalChars / charsPerToken).ceil();
  }

  static int _sortOrder(MapEntry<String, AiResolvedTool> entry) {
    return entry.value.builtinConfig?.sortOrder ??
        entry.value.builtinKind?.index ??
        0;
  }
}
