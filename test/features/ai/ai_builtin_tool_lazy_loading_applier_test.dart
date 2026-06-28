import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_builtin_tool_lazy_loading_applier.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';

void main() {
  test('auto mode uses capped built-in threshold', () {
    expect(
      AiBuiltinToolLazyLoadingApplier.effectiveAutoThresholdTokens(16000),
      AiBuiltinToolLazyLoadingApplier.defaultAutoThresholdTokens,
    );
    expect(
      AiBuiltinToolLazyLoadingApplier.effectiveAutoThresholdTokens(1000),
      1000,
    );
  });

  test('knowledge tools stay loaded when built-in lazy loading is off', () {
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

    expect(
      applied.toolsByName.keys,
      containsAll(<String>[
        'ToolSearch',
        'WebFetch',
        'KnowledgeSearch',
        'KnowledgeRead',
      ]),
    );
    expect(
      applied.toolsByName['ToolSearch']!.toolSearchDeferredToolDefinitions,
      isEmpty,
    );
    expect(applied.notices, isEmpty);
  });

  test('enabled lazy loading defers non force-loaded built-in tools', () {
    final catalog = _catalog(<AiResolvedTool>[
      _builtin(AiBuiltinToolKind.toolSearch, 'ToolSearch'),
      _builtin(AiBuiltinToolKind.webFetch, 'WebFetch'),
      _builtin(AiBuiltinToolKind.knowledgeSearch, 'KnowledgeSearch'),
    ]);

    final applied = AiBuiltinToolLazyLoadingApplier.apply(
      catalog: catalog,
      sourceCatalog: catalog,
      mode: AiBuiltinToolLazyLoadingMode.enabled,
      thresholdTokens: 1 << 30,
      charsPerToken: 4,
    );

    expect(applied.toolsByName, contains('ToolSearch'));
    expect(applied.toolsByName, contains('KnowledgeSearch'));
    expect(applied.toolsByName, isNot(contains('WebFetch')));

    final toolSearch = applied.toolsByName['ToolSearch']!;
    expect(
      toolSearch.toolSearchDeferredToolDefinitions.keys,
      contains('WebFetch'),
    );
    expect(
      toolSearch.toolSearchDeferredToolDefinitions.keys,
      isNot(contains('KnowledgeSearch')),
    );
    expect(
      toolSearch.definition.description,
      contains('## Deferred built-in tools (1)'),
    );
    expect(toolSearch.definition.description, contains('WebFetch'));
  });

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
