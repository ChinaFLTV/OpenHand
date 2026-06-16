import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';
import 'package:openhand/features/ai/service/runtime/ai_builtin_tool_lazy_loading_applier.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';

void main() {
  group('AiBuiltinToolConfig defaults', () {
    test('keep core tools eager and defer heavier tools by default', () {
      final configs = {
        for (final config in AiBuiltinToolConfig.defaults())
          config.kind: config,
      };

      expect(
        configs[AiBuiltinToolKind.read]!.loadStrategy,
        AiBuiltinToolLoadStrategy.eager,
      );
      expect(
        configs[AiBuiltinToolKind.bash]!.loadStrategy,
        AiBuiltinToolLoadStrategy.eager,
      );
      expect(
        configs[AiBuiltinToolKind.toolSearch]!.loadStrategy,
        AiBuiltinToolLoadStrategy.eager,
      );
      expect(
        configs[AiBuiltinToolKind.webSearch]!.loadStrategy,
        AiBuiltinToolLoadStrategy.lazy,
      );
      expect(
        configs[AiBuiltinToolKind.applyFileDiffs]!.loadStrategy,
        AiBuiltinToolLoadStrategy.lazy,
      );
    });

    test('detects untouched legacy all-eager defaults for migration', () {
      final legacyDefaults = AiBuiltinToolKind.values
          .map(
            (kind) => AiBuiltinToolConfig(
              kind: kind,
              sortOrder: kind.index,
              webSearchSettings: kind == AiBuiltinToolKind.webSearch
                  ? AiWebSearchSettings.defaults()
                  : null,
              webFetchSettings: kind == AiBuiltinToolKind.webFetch
                  ? AiWebFetchSettings.defaults()
                  : null,
            ),
          )
          .toList(growable: false);

      expect(
        AiBuiltinToolConfig.looksLikeLegacyEagerDefaults(legacyDefaults),
        isTrue,
      );

      final customized = List<AiBuiltinToolConfig>.from(legacyDefaults);
      final readIndex = customized.indexWhere(
        (config) => config.kind == AiBuiltinToolKind.read,
      );
      customized[readIndex] = customized[readIndex].copyWith(
        promptOverride: 'custom read prompt',
      );

      expect(
        AiBuiltinToolConfig.looksLikeLegacyEagerDefaults(customized),
        isFalse,
      );
    });
  });

  group('AiBuiltinToolLazyLoadingApplier', () {
    test('defers lazy built-in tool schemas through ToolSearch', () {
      final catalog = _catalogWith(<AiResolvedTool>[
        _configuredBuiltin(AiBuiltinToolKind.toolSearch),
        _configuredBuiltin(AiBuiltinToolKind.read),
        _configuredBuiltin(
          AiBuiltinToolKind.webSearch,
          loadStrategy: AiBuiltinToolLoadStrategy.lazy,
        ),
        _configuredBuiltin(
          AiBuiltinToolKind.write,
          loadStrategy: AiBuiltinToolLoadStrategy.lazy,
        ),
      ]);

      final result = AiBuiltinToolLazyLoadingApplier.apply(
        catalog: catalog,
        sourceCatalog: catalog,
      );

      expect(result.find('Read'), isNotNull);
      expect(result.find('WebSearch'), isNull);
      expect(result.find('Write'), isNull);
      expect(result.notices.single, contains('2 built-in tool(s) deferred'));

      final toolSearch = result.find('ToolSearch');
      expect(toolSearch, isNotNull);
      expect(
        toolSearch!.definition.description,
        contains('## Deferred built-in tools (2)'),
      );
      expect(
        toolSearch.toolSearchDeferredToolDefinitions.keys,
        containsAll(<String>['WebSearch', 'Write']),
      );
    });

    test('keeps already loaded lazy built-in tools visible', () {
      final catalog = _catalogWith(<AiResolvedTool>[
        _configuredBuiltin(AiBuiltinToolKind.toolSearch),
        _configuredBuiltin(
          AiBuiltinToolKind.webSearch,
          loadStrategy: AiBuiltinToolLoadStrategy.lazy,
        ),
        _configuredBuiltin(
          AiBuiltinToolKind.write,
          loadStrategy: AiBuiltinToolLoadStrategy.lazy,
        ),
      ]);

      final result = AiBuiltinToolLazyLoadingApplier.apply(
        catalog: catalog,
        sourceCatalog: catalog,
        alreadyLoadedNames: const <String>{'WebSearch'},
      );

      expect(result.find('WebSearch'), isNotNull);
      expect(result.find('Write'), isNull);
      expect(
        result.find('ToolSearch')!.toolSearchDeferredToolDefinitions.keys,
        isNot(contains('WebSearch')),
      );
      expect(
        result.find('ToolSearch')!.toolSearchDeferredToolDefinitions.keys,
        contains('Write'),
      );
    });

    test('uses default load strategies when builtin configs are absent', () {
      final catalog = _catalogWith(<AiResolvedTool>[
        AiToolRuntimeService.builtinToolDefault(AiBuiltinToolKind.toolSearch)!,
        AiToolRuntimeService.builtinToolDefault(AiBuiltinToolKind.read)!,
        AiToolRuntimeService.builtinToolDefault(AiBuiltinToolKind.webSearch)!,
      ]);

      final result = AiBuiltinToolLazyLoadingApplier.apply(
        catalog: catalog,
        sourceCatalog: catalog,
      );

      expect(result.find('Read'), isNotNull);
      expect(result.find('WebSearch'), isNull);
      expect(
        result.find('ToolSearch')!.toolSearchDeferredToolDefinitions.keys,
        contains('WebSearch'),
      );
    });

    test('does not hide tools when ToolSearch is unavailable', () {
      final catalog = _catalogWith(<AiResolvedTool>[
        _configuredBuiltin(
          AiBuiltinToolKind.webSearch,
          loadStrategy: AiBuiltinToolLoadStrategy.lazy,
        ),
      ]);

      final result = AiBuiltinToolLazyLoadingApplier.apply(
        catalog: catalog,
        sourceCatalog: catalog,
      );

      expect(result, same(catalog));
      expect(result.find('WebSearch'), isNotNull);
    });
  });
}

AiResolvedToolCatalog _catalogWith(List<AiResolvedTool> tools) {
  return AiResolvedToolCatalog(
    definitions: tools.map((tool) => tool.definition).toList(growable: false),
    toolsByName: <String, AiResolvedTool>{
      for (final tool in tools) tool.name: tool,
    },
  );
}

AiResolvedTool _configuredBuiltin(
  AiBuiltinToolKind kind, {
  AiBuiltinToolLoadStrategy? loadStrategy,
}) {
  final base = AiToolRuntimeService.builtinToolDefault(kind)!;
  return AiResolvedTool(
    name: base.name,
    definition: base.definition,
    source: base.source,
    builtinKind: base.builtinKind,
    builtinConfig: AiBuiltinToolConfig(
      kind: kind,
      sortOrder: kind.index,
      loadStrategy:
          loadStrategy ?? AiBuiltinToolConfig.defaultLoadStrategyForKind(kind),
    ),
  );
}
