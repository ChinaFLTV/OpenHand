import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_builtin_tool_lazy_loading_applier.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';

void main() {
  test(
    'knowledge tools use dynamic catalog even when built-in lazy loading is off',
    () {
      final catalog = _catalog(<AiResolvedTool>[
        _builtin(AiBuiltinToolKind.toolSearch, 'ToolSearch'),
        _builtin(AiBuiltinToolKind.webFetch, 'WebFetch'),
        _builtin(AiBuiltinToolKind.knowledgeSearch, 'KnowledgeSearch'),
        _builtin(AiBuiltinToolKind.knowledgeRead, 'KnowledgeRead'),
      ]);

      final applied = AiBuiltinToolLazyLoadingApplier.apply(
        catalog: catalog,
        sourceCatalog: catalog,
        mode: AiBuiltinToolLazyLoadingMode.disabled,
        thresholdTokens: 1 << 30,
        charsPerToken: 4,
      );

      expect(applied.toolsByName, contains('ToolSearch'));
      expect(applied.toolsByName, contains('WebFetch'));
      expect(applied.toolsByName, isNot(contains('KnowledgeSearch')));
      expect(applied.toolsByName, isNot(contains('KnowledgeRead')));

      final toolSearch = applied.toolsByName['ToolSearch']!;
      expect(
        toolSearch.toolSearchDeferredToolDefinitions.keys,
        containsAll(<String>['KnowledgeSearch', 'KnowledgeRead']),
      );
      expect(
        toolSearch.toolSearchDeferredToolDefinitions.keys,
        isNot(contains('WebFetch')),
      );
      expect(
        toolSearch.definition.description,
        contains('## Deferred built-in tools (2)'),
      );
      expect(toolSearch.definition.description, contains('KnowledgeSearch'));
      expect(toolSearch.definition.description, contains('KnowledgeRead'));
    },
  );

  test('disabled knowledge tools stay out of the dynamic catalog', () {
    final catalog = _catalog(<AiResolvedTool>[
      _builtin(AiBuiltinToolKind.toolSearch, 'ToolSearch'),
      _builtin(AiBuiltinToolKind.webFetch, 'WebFetch'),
    ]);

    final applied = AiBuiltinToolLazyLoadingApplier.apply(
      catalog: catalog,
      sourceCatalog: catalog,
      mode: AiBuiltinToolLazyLoadingMode.disabled,
      thresholdTokens: 1 << 30,
      charsPerToken: 4,
    );

    expect(
      applied.toolsByName.keys,
      containsAll(<String>['ToolSearch', 'WebFetch']),
    );
    expect(
      applied.toolsByName['ToolSearch']!.toolSearchDeferredToolDefinitions,
      isEmpty,
    );
    expect(applied.notices, isEmpty);
  });
}

AiResolvedToolCatalog _catalog(List<AiResolvedTool> tools) {
  return AiResolvedToolCatalog(
    definitions: tools.map((tool) => tool.definition).toList(growable: false),
    toolsByName: <String, AiResolvedTool>{
      for (final tool in tools) tool.name: tool,
    },
  );
}

AiResolvedTool _builtin(AiBuiltinToolKind kind, String name) {
  return AiResolvedTool(
    name: name,
    definition: AiToolDefinition(
      name: name,
      description: '$name test tool.',
      parameters: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      },
    ),
    source: AiRuntimeToolSource.builtin,
    builtinKind: kind,
    builtinConfig: _defaultConfig(kind),
  );
}

AiBuiltinToolConfig _defaultConfig(AiBuiltinToolKind kind) {
  return AiBuiltinToolConfig.defaults().firstWhere(
    (config) => config.kind == kind,
  );
}
