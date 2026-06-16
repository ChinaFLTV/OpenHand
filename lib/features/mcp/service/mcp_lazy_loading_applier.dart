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
    required AiToolRuntimeService toolRuntimeService,
    Set<String> alreadyLoadedNames = const <String>{},
    Set<String> forceVisibleNames = const <String>{},
    bool keepToolSearchWhenIdle = false,
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

    final toolSearchTool = toolRuntimeService.toolRegistry.getTool(
      AiBuiltinToolKind.toolSearch,
    );

    if (!shouldLazy) {
      if (toolSearchTool is AiToolSearchTool && !keepToolSearchWhenIdle) {
        toolSearchTool.clearDeferredToolSnapshot();
      }
      return keepToolSearchWhenIdle ? catalog : _stripToolSearch(catalog);
    }

    // 2026-05-24 — 强可见名单按字典序排序，避免 MCP 服务器重连或
    // 控制器刷新导致 `forceVisibleNames` 的 Set 迭代顺序漂移，进而让
    // notice 文案在轮次间字节不一致、撕裂前缀缓存。
    final forceVisibleEntryNames =
        mcpEntries
            .where((entry) => forceVisibleNames.contains(entry.key))
            .map((entry) => entry.key)
            .toList(growable: true)
          ..sort();
    final forceVisibleNotice = forceVisibleEntryNames.isEmpty
        ? null
        : 'MCP lazy loading policy kept ${forceVisibleEntryNames.length} MCP tool(s) directly visible: ${forceVisibleEntryNames.join(', ')}.';
    // 2026-05-24 — `deferredEntries` 直接喂给 ToolSearch 的 description
    // 渲染（见 _augmentToolSearchDefinition），其遍历顺序决定了 [2] Tool
    // Catalog 整段文本。改用按工具名字典序排列，确保即便上游 MCP catalog
    // 的 Map 插入顺序漂移（服务器异步重连、刷新、单工具增删），描述区文本
    // 仍然字节一致，前缀缓存命中率不会被这条隐藏漂移点踩破。
    final deferredEntries =
        mcpEntries
            .where(
              (entry) =>
                  !alreadyLoadedNames.contains(entry.key) &&
                  !forceVisibleNames.contains(entry.key),
            )
            .toList(growable: true)
          ..sort((a, b) => a.key.compareTo(b.key));
    final deferredDefinitions = <String, AiToolDefinition>{
      for (final entry in deferredEntries) entry.key: entry.value.definition,
    };
    if (toolSearchTool is AiToolSearchTool) {
      toolSearchTool.setDeferredToolSnapshot(deferredDefinitions);
    }
    if (deferredEntries.isEmpty) {
      final strippedCatalog = keepToolSearchWhenIdle
          ? catalog
          : _stripToolSearch(catalog);
      if (forceVisibleNotice == null) {
        return strippedCatalog;
      }
      return AiResolvedToolCatalog(
        definitions: strippedCatalog.definitions,
        toolsByName: strippedCatalog.toolsByName,
        notices: <String>[...strippedCatalog.notices, forceVisibleNotice],
        mcpServerInstructionsByName:
            strippedCatalog.mcpServerInstructionsByName,
      );
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
              deferredDefinitions: deferredDefinitions,
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
      notices: <String>[
        ...catalog.notices,
        notice,
        if (forceVisibleNotice != null) forceVisibleNotice,
      ],
      mcpServerInstructionsByName: catalog.mcpServerInstructionsByName,
    );
  }

  static AiResolvedTool _augmentToolSearchDefinition(
    AiResolvedTool original, {
    required List<MapEntry<String, AiResolvedTool>> deferredEntries,
    required Map<String, AiToolDefinition> deferredDefinitions,
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
      toolSearchDeferredToolDefinitions:
          Map<String, AiToolDefinition>.unmodifiable(deferredDefinitions),
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
