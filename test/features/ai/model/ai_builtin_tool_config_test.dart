import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';

void main() {
  group('agent builtin tool metadata', () {
    test('keeps ordered kind list aligned with metadata table', () {
      expect(
        aiAgentBuiltinToolMetadataByKind.keys.toList(growable: false),
        aiAgentBuiltinToolKinds,
      );
    });

    test('resolves canonical names from the shared metadata table', () {
      expect(
        agentBuiltinToolCanonicalName(AiBuiltinToolKind.agentList),
        'AgentList',
      );
      expect(
        agentBuiltinToolCanonicalName(AiBuiltinToolKind.agentTaskResult),
        'AgentTaskResult',
      );
      expect(
        agentBuiltinToolCanonicalName(AiBuiltinToolKind.webFetch),
        'WebFetch',
      );
    });

    test('centralizes agent grouping and mutation flags', () {
      expect(AiBuiltinToolKind.agentList.isAgentCoordinationTool, isTrue);
      expect(AiBuiltinToolKind.webFetch.isAgentCoordinationTool, isFalse);
      expect(
        AiBuiltinToolKind.agentKpiUpsert.agentToolGroup,
        AiAgentBuiltinToolGroup.operations,
      );
      expect(
        AiBuiltinToolKind.agentTaskCancel.agentToolGroup,
        AiAgentBuiltinToolGroup.taskLifecycle,
      );
      expect(AiBuiltinToolKind.webFetch.agentToolGroup, isNull);
      expect(AiBuiltinToolKind.agentTaskPublish.isAgentMutationTool, isTrue);
      expect(AiBuiltinToolKind.agentTaskTrack.isAgentMutationTool, isFalse);
    });

    test('keeps only core coordination tools eagerly loaded by default', () {
      final coreKinds = aiAgentBuiltinToolKinds
          .where((kind) => kind.isAgentCoreCoordinationTool)
          .toSet();

      expect(coreKinds, const <AiBuiltinToolKind>{
        AiBuiltinToolKind.agentList,
        AiBuiltinToolKind.agentTaskPublish,
        AiBuiltinToolKind.agentTaskTrack,
        AiBuiltinToolKind.agentTaskResult,
      });
      for (final kind in aiAgentBuiltinToolKinds) {
        expect(
          AiBuiltinToolConfig.defaultLoadStrategyForKind(kind),
          kind.isAgentCoreCoordinationTool
              ? AiBuiltinToolLoadStrategy.eager
              : AiBuiltinToolLoadStrategy.lazy,
          reason: kind.name,
        );
      }
    });
  });
}
