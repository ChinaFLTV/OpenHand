import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  test(
    'auto mode honors the configured threshold without a hidden low cap',
    () {
      final threshold =
          AiBuiltinToolLazyLoadingApplier.effectiveAutoThresholdTokens(16000);
      final catalog = _builtinCatalog(descriptionCharsPerTool: 4000);

      final result = AiBuiltinToolLazyLoadingApplier.apply(
        catalog: catalog,
        sourceCatalog: catalog,
        mode: AiBuiltinToolLazyLoadingMode.auto,
        thresholdTokens: threshold,
        charsPerToken: 4,
      );

      expect(threshold, 16000);
      expect(_toolNames(result), containsAll(_lazyToolNames));
      expect(
        _toolSearchDescription(result),
        isNot(contains('Deferred built-in')),
      );
    },
  );

  test('enabled mode still defers eligible built-ins explicitly', () {
    final catalog = _builtinCatalog(descriptionCharsPerTool: 4000);

    final result = AiBuiltinToolLazyLoadingApplier.apply(
      catalog: catalog,
      sourceCatalog: catalog,
      mode: AiBuiltinToolLazyLoadingMode.enabled,
      thresholdTokens: 16000,
      charsPerToken: 4,
    );

    expect(_toolNames(result), isNot(contains(_lazyToolNames.first)));
    expect(_toolSearchDescription(result), contains('Deferred built-in tools'));
  });
}

const List<String> _lazyToolNames = <String>[
  'BashBackground',
  'TaskOutput',
  'TaskStop',
  'MultiEdit',
  'ApplyFileDiffs',
];

AiResolvedToolCatalog _builtinCatalog({required int descriptionCharsPerTool}) {
  final description = 'x' * descriptionCharsPerTool;
  final entries = <MapEntry<String, AiResolvedTool>>[
    _entry(
      name: 'ToolSearch',
      kind: AiBuiltinToolKind.toolSearch,
      description: 'Load deferred tool schemas.',
    ),
    _entry(
      name: _lazyToolNames[0],
      kind: AiBuiltinToolKind.bashBackground,
      description: description,
    ),
    _entry(
      name: _lazyToolNames[1],
      kind: AiBuiltinToolKind.taskOutput,
      description: description,
    ),
    _entry(
      name: _lazyToolNames[2],
      kind: AiBuiltinToolKind.taskStop,
      description: description,
    ),
    _entry(
      name: _lazyToolNames[3],
      kind: AiBuiltinToolKind.multiEdit,
      description: description,
    ),
    _entry(
      name: _lazyToolNames[4],
      kind: AiBuiltinToolKind.applyFileDiffs,
      description: description,
    ),
  ];
  return AiResolvedToolCatalog(
    definitions: entries
        .map((entry) => entry.value.definition)
        .toList(growable: false),
    toolsByName: Map<String, AiResolvedTool>.fromEntries(entries),
  );
}

MapEntry<String, AiResolvedTool> _entry({
  required String name,
  required AiBuiltinToolKind kind,
  required String description,
}) {
  final definition = AiToolDefinition(
    name: name,
    description: description,
    parameters: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  );
  return MapEntry<String, AiResolvedTool>(
    name,
    AiResolvedTool(
      name: name,
      definition: definition,
      source: AiRuntimeToolSource.builtin,
      builtinKind: kind,
    ),
  );
}

List<String> _toolNames(AiResolvedToolCatalog catalog) {
  return catalog.definitions.map((tool) => tool.name).toList(growable: false);
}

String _toolSearchDescription(AiResolvedToolCatalog catalog) {
  return catalog.toolsByName['ToolSearch']?.definition.description ?? '';
}
