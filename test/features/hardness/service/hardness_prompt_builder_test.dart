import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';
import 'package:openhand/features/hardness/model/hardness_phase.dart';
import 'package:openhand/features/hardness/service/hardness_prompt_builder.dart';

void main() {
  test(
    'phase filtering preserves MCP server context and ToolSearch sidecar',
    () {
      final deferredDefinition = _definition('mcp__browser__inspect');
      final toolSearchDefinition = _definition('ToolSearch');
      final catalog = AiResolvedToolCatalog(
        definitions: <AiToolDefinition>[
          toolSearchDefinition,
          _definition('Read'),
          deferredDefinition,
        ],
        toolsByName: <String, AiResolvedTool>{
          'ToolSearch': AiResolvedTool(
            name: 'ToolSearch',
            definition: toolSearchDefinition,
            source: AiRuntimeToolSource.builtin,
            builtinKind: AiBuiltinToolKind.toolSearch,
            toolSearchDeferredToolDefinitions: <String, AiToolDefinition>{
              deferredDefinition.name: deferredDefinition,
            },
          ),
          'Read': _builtin('Read', AiBuiltinToolKind.read),
          deferredDefinition.name: AiResolvedTool(
            name: deferredDefinition.name,
            definition: deferredDefinition,
            source: AiRuntimeToolSource.mcp,
          ),
        },
        notices: const <String>['lazy loading active'],
        mcpServerInstructionsByName: const <String, String>{
          'browser': 'Prefer CDP-backed browser inspection.',
        },
      );

      final filtered = const HardnessPromptBuilder().filterToolsForPhase(
        phase: HardnessPhase.reviewing,
        catalog: catalog,
      );

      expect(filtered.notices, contains('lazy loading active'));
      expect(
        filtered.mcpServerInstructionsByName['browser'],
        'Prefer CDP-backed browser inspection.',
      );
      expect(filtered.toolsByName, contains('ToolSearch'));
      expect(filtered.toolsByName, contains('Read'));
      expect(filtered.toolsByName, isNot(contains(deferredDefinition.name)));
      expect(
        filtered.toolsByName['ToolSearch']!.toolSearchDeferredToolDefinitions,
        contains(deferredDefinition.name),
      );

      final loadedFiltered = const HardnessPromptBuilder().filterToolsForPhase(
        phase: HardnessPhase.reviewing,
        catalog: catalog,
        loadedMcpToolNames: <String>{deferredDefinition.name},
      );

      expect(loadedFiltered.toolsByName, contains(deferredDefinition.name));
    },
  );
}

AiToolDefinition _definition(String name) {
  return AiToolDefinition(
    name: name,
    description: 'Description for $name',
    parameters: const <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  );
}

AiResolvedTool _builtin(String name, AiBuiltinToolKind kind) {
  return AiResolvedTool(
    name: name,
    definition: _definition(name),
    source: AiRuntimeToolSource.builtin,
    builtinKind: kind,
  );
}
