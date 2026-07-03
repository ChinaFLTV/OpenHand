import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_builtin_tool_lazy_loading_applier.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';

void main() {
  test('builtin lazy deferred sidecar is canonicalized and ordered', () {
    final result = AiBuiltinToolLazyLoadingApplier.apply(
      catalog: _catalog(<MapEntry<String, AiResolvedTool>>[
        MapEntry<String, AiResolvedTool>(
          'ToolSearch',
          _builtinTool(
            'ToolSearch',
            AiBuiltinToolKind.toolSearch,
            deferredDefinitions: <String, AiToolDefinition>{
              'AlphaExisting': _definition('AlphaExisting'),
            },
          ),
        ),
        MapEntry<String, AiResolvedTool>(
          'Read_File',
          _builtinTool(
            'Read_File',
            AiBuiltinToolKind.webSearch,
            config: _lazyConfig(AiBuiltinToolKind.webSearch),
            properties: <String, Object?>{
              'zeta': const <String, Object?>{'type': 'string'},
              'alpha': const <String, Object?>{'type': 'string'},
            },
            required: const <String>['zeta', 'alpha'],
          ),
        ),
        MapEntry<String, AiResolvedTool>(
          'Read-File',
          _builtinTool(
            'Read-File',
            AiBuiltinToolKind.webFetch,
            config: _lazyConfig(AiBuiltinToolKind.webFetch),
            properties: <String, Object?>{
              'zeta': const <String, Object?>{'type': 'string'},
              'alpha': const <String, Object?>{'type': 'string'},
            },
            required: const <String>['zeta', 'alpha'],
          ),
        ),
      ]),
      sourceCatalog: _catalog(<MapEntry<String, AiResolvedTool>>[
        MapEntry<String, AiResolvedTool>(
          'ToolSearch',
          _builtinTool('ToolSearch', AiBuiltinToolKind.toolSearch),
        ),
      ]),
      mode: AiBuiltinToolLazyLoadingMode.enabled,
      thresholdTokens: 1,
      charsPerToken: 4,
    );

    final toolSearch = result.find('ToolSearch')!;
    final deferredDefinitions = toolSearch.toolSearchDeferredToolDefinitions;

    expect(deferredDefinitions.keys.toList(), <String>[
      'AlphaExisting',
      'Read-File',
      'Read_File',
    ]);
    expect(
      jsonEncode(deferredDefinitions['Read-File']!.parameters),
      '{"properties":{"alpha":{"type":"string"},"zeta":{"type":"string"}},"required":["alpha","zeta"],"type":"object"}',
    );
    expect(
      toolSearch.definition.description.indexOf('- Read-File'),
      lessThan(toolSearch.definition.description.indexOf('- Read_File')),
    );
  });
}

AiResolvedToolCatalog _catalog(List<MapEntry<String, AiResolvedTool>> entries) {
  return AiResolvedToolCatalog(
    definitions: entries
        .map((entry) => entry.value.definition)
        .toList(growable: false),
    toolsByName: Map<String, AiResolvedTool>.fromEntries(entries),
  );
}

AiResolvedTool _builtinTool(
  String name,
  AiBuiltinToolKind kind, {
  AiBuiltinToolConfig? config,
  Map<String, Object?> properties = const <String, Object?>{},
  List<String> required = const <String>[],
  Map<String, AiToolDefinition> deferredDefinitions =
      const <String, AiToolDefinition>{},
}) {
  return AiResolvedTool(
    name: name,
    definition: _definition(name, properties: properties, required: required),
    source: AiRuntimeToolSource.builtin,
    builtinKind: kind,
    builtinConfig: config,
    toolSearchDeferredToolDefinitions: deferredDefinitions,
  );
}

AiBuiltinToolConfig _lazyConfig(AiBuiltinToolKind kind) {
  return AiBuiltinToolConfig(
    kind: kind,
    sortOrder: 10,
    priority: 10,
    loadStrategy: AiBuiltinToolLoadStrategy.lazy,
  );
}

AiToolDefinition _definition(
  String name, {
  Map<String, Object?> properties = const <String, Object?>{},
  List<String> required = const <String>[],
}) {
  return AiToolDefinition(
    name: name,
    description: '$name description.',
    parameters: <String, Object?>{
      'type': 'object',
      'required': required,
      'properties': properties,
    },
  );
}
