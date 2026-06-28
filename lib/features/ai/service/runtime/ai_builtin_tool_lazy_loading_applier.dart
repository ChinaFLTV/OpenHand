import 'dart:convert';
import 'dart:math' as math;

import '../../model/ai_builtin_tool_config.dart';
import '../../tools/search/ai_tool_search_tool.dart';
import '../chat/ai_protocol_adapter.dart';
import 'ai_tool_runtime_service.dart';

class AiBuiltinToolLazyLoadingApplier {
  const AiBuiltinToolLazyLoadingApplier();

  static const int _deferredPreviewLimit = 80;
  static const int _deferredPreviewDescriptionChars = 140;

  static bool hasDeferredCandidates({
    required AiResolvedToolCatalog catalog,
    required AiBuiltinToolLazyLoadingMode mode,
    required int thresholdTokens,
    required int charsPerToken,
    Set<String> alreadyLoadedNames = const <String>{},
  }) {
    if (_findToolSearchEntry(catalog) == null) return false;
    return _shouldDeferAllEligible(
      catalog,
      mode: mode,
      thresholdTokens: thresholdTokens,
      charsPerToken: charsPerToken,
      alreadyLoadedNames: alreadyLoadedNames,
    );
  }

  static AiResolvedToolCatalog apply({
    required AiResolvedToolCatalog catalog,
    required AiResolvedToolCatalog sourceCatalog,
    required AiBuiltinToolLazyLoadingMode mode,
    required int thresholdTokens,
    required int charsPerToken,
    AiToolRuntimeService? toolRuntimeService,
    Set<String> alreadyLoadedNames = const <String>{},
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
      alreadyLoadedNames: alreadyLoadedNames,
    );
    if (!deferAllEligible) {
      return catalog;
    }

    final deferredEntries = _deferredBuiltinEntries(
      catalog,
      alreadyLoadedNames: alreadyLoadedNames,
    );
    if (deferredEntries.isEmpty) {
      return catalog;
    }

    final deferredNames = deferredEntries.map((entry) => entry.key).toSet();
    final deferredDefinitions = <String, AiToolDefinition>{
      ...toolSearchEntry.value.toolSearchDeferredToolDefinitions,
      for (final entry in deferredEntries) entry.key: entry.value.definition,
    };
    final deferredTools = <String, AiResolvedTool>{
      ...toolSearchEntry.value.toolSearchDeferredTools,
      for (final entry in deferredEntries) entry.key: entry.value,
    };
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
            _augmentToolSearchDefinition(
              entry.value,
              deferredEntries: deferredEntries,
              deferredDefinitions: deferredDefinitions,
              deferredTools: deferredTools,
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
          _augmentToolSearchDefinition(
            toolSearchEntry.value,
            deferredEntries: deferredEntries,
            deferredDefinitions: deferredDefinitions,
            deferredTools: deferredTools,
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
        'Built-in tool lazy loading active: ${deferredEntries.length} built-in tool(s) deferred. Use ToolSearch to load them on demand.',
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
    required Set<String> alreadyLoadedNames,
  }) {
    if (mode == AiBuiltinToolLazyLoadingMode.disabled) {
      return false;
    }
    final deferredEntries = _deferredBuiltinEntries(
      catalog,
      alreadyLoadedNames: alreadyLoadedNames,
    );
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
    required Set<String> alreadyLoadedNames,
  }) {
    final entries = catalog.toolsByName.entries
        .where((entry) {
          final tool = entry.value;
          if (tool.source != AiRuntimeToolSource.builtin) return false;
          if (tool.builtinKind == null ||
              tool.builtinKind == AiBuiltinToolKind.toolSearch) {
            return false;
          }
          if (alreadyLoadedNames.contains(entry.key) ||
              alreadyLoadedNames.contains(tool.name) ||
              alreadyLoadedNames.contains(tool.definition.name)) {
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
      return left.key.compareTo(right.key);
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

  static AiResolvedTool _augmentToolSearchDefinition(
    AiResolvedTool original, {
    required List<MapEntry<String, AiResolvedTool>> deferredEntries,
    required Map<String, AiToolDefinition> deferredDefinitions,
    required Map<String, AiResolvedTool> deferredTools,
  }) {
    final lines = <String>[
      '',
      '## Deferred built-in tools (${deferredEntries.length})',
    ];
    for (final entry in deferredEntries.take(_deferredPreviewLimit)) {
      final firstLine = entry.value.definition.description
          .split('\n')
          .first
          .trim();
      final clipped = firstLine.length > _deferredPreviewDescriptionChars
          ? '${firstLine.substring(0, _deferredPreviewDescriptionChars - 3)}...'
          : firstLine;
      lines.add('- ${entry.key}${clipped.isEmpty ? '' : ' - $clipped'}');
    }
    if (deferredEntries.length > _deferredPreviewLimit) {
      lines.add(
        '- ... and ${deferredEntries.length - _deferredPreviewLimit} more.',
      );
    }
    return AiResolvedTool(
      name: original.name,
      definition: AiToolDefinition(
        name: original.definition.name,
        description: '${original.definition.description}\n${lines.join('\n')}',
        parameters: original.definition.parameters,
      ),
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
}
