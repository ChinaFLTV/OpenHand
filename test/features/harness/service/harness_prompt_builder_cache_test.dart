import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/harness/model/harness_phase.dart';
import 'package:openhand/features/harness/service/harness_prompt_builder.dart';

void main() {
  test('compact tool catalog is stable across tool and schema order', () {
    final first = harnessPromptBuilder.renderCompactToolCatalog(
      phase: HarnessPhase.reading,
      tools: <AiToolDefinition>[
        _tool('Read_File', required: const <String>['zeta', 'alpha']),
        _tool('Read-File', required: const <String>['alpha', 'zeta']),
      ],
    );
    final second = harnessPromptBuilder.renderCompactToolCatalog(
      phase: HarnessPhase.reading,
      tools: <AiToolDefinition>[
        _tool('Read-File', required: const <String>['zeta', 'alpha']),
        _tool('Read_File', required: const <String>['alpha', 'zeta']),
      ],
    );

    expect(first, second);
    expect(
      first.indexOf('- Read-File:'),
      lessThan(first.indexOf('- Read_File:')),
    );
    expect(first, contains('[alpha, zeta]'));
  });

  test('phase-filtered catalog is stable across source catalog order', () {
    final first = harnessPromptBuilder.filterToolsForPhase(
      phase: HarnessPhase.reading,
      catalog: _catalog(<MapEntry<String, AiResolvedTool>>[
        MapEntry<String, AiResolvedTool>(
          'Grep',
          _resolvedBuiltin('Grep', AiBuiltinToolKind.grep),
        ),
        MapEntry<String, AiResolvedTool>(
          'Read',
          _resolvedBuiltin('Read', AiBuiltinToolKind.read),
        ),
      ]),
    );
    final second = harnessPromptBuilder.filterToolsForPhase(
      phase: HarnessPhase.reading,
      catalog: _catalog(<MapEntry<String, AiResolvedTool>>[
        MapEntry<String, AiResolvedTool>(
          'Read',
          _resolvedBuiltin('Read', AiBuiltinToolKind.read),
        ),
        MapEntry<String, AiResolvedTool>(
          'Grep',
          _resolvedBuiltin('Grep', AiBuiltinToolKind.grep),
        ),
      ]),
    );

    expect(first.definitions.map((tool) => tool.name), <String>[
      'Grep',
      'Read',
    ]);
    expect(
      first.definitions.map((tool) => tool.name).toList(growable: false),
      second.definitions.map((tool) => tool.name).toList(growable: false),
    );
  });
}

AiToolDefinition _tool(
  String name, {
  List<String> required = const <String>[],
}) {
  return AiToolDefinition(
    name: name,
    description: '$name description.',
    parameters: <String, Object?>{
      'type': 'object',
      'required': required,
      'properties': <String, Object?>{
        'zeta': const <String, Object?>{'type': 'string'},
        'alpha': const <String, Object?>{'type': 'string'},
      },
    },
  );
}

AiResolvedToolCatalog _catalog(List<MapEntry<String, AiResolvedTool>> entries) {
  return AiResolvedToolCatalog(
    definitions: entries
        .map((entry) => entry.value.definition)
        .toList(growable: false),
    toolsByName: Map<String, AiResolvedTool>.fromEntries(entries),
  );
}

AiResolvedTool _resolvedBuiltin(String name, AiBuiltinToolKind kind) {
  return AiResolvedTool(
    name: name,
    definition: _tool(name),
    source: AiRuntimeToolSource.builtin,
    builtinKind: kind,
  );
}
