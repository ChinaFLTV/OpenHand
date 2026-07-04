import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';

void main() {
  group('AiBuiltinToolKind agent metadata', () {
    test('classifies all agent coordination tools', () {
      final agentTools = AiBuiltinToolKind.values
          .where((kind) => kind.name.startsWith('agent'))
          .toSet();

      expect(agentTools, isNotEmpty);
      expect(agentTools.every((kind) => kind.isAgentCoordinationTool), isTrue);
      expect(AiBuiltinToolKind.bash.isAgentCoordinationTool, isFalse);
      expect(AiBuiltinToolKind.webSearch.isAgentCoordinationTool, isFalse);
    });

    test('marks only state-changing agent tools as mutations', () {
      expect(AiBuiltinToolKind.agentList.isAgentMutationTool, isFalse);
      expect(AiBuiltinToolKind.agentDetail.isAgentMutationTool, isFalse);
      expect(AiBuiltinToolKind.agentActivityLog.isAgentMutationTool, isFalse);
      expect(AiBuiltinToolKind.agentTaskProgress.isAgentMutationTool, isFalse);
      expect(AiBuiltinToolKind.agentTaskResult.isAgentMutationTool, isFalse);

      expect(AiBuiltinToolKind.agentTaskPublish.isAgentMutationTool, isTrue);
      expect(
        AiBuiltinToolKind.agentApprovalRequest.isAgentMutationTool,
        isTrue,
      );
      expect(AiBuiltinToolKind.agentKpiUpsert.isAgentMutationTool, isTrue);
      expect(AiBuiltinToolKind.agentResourceUpdate.isAgentMutationTool, isTrue);
      expect(
        AiBuiltinToolKind.agentClusterConfigure.isAgentMutationTool,
        isTrue,
      );
      expect(AiBuiltinToolKind.agentTaskCancel.isAgentMutationTool, isTrue);
      expect(AiBuiltinToolKind.agentTaskPause.isAgentMutationTool, isTrue);
      expect(AiBuiltinToolKind.agentTaskTerminate.isAgentMutationTool, isTrue);
      expect(AiBuiltinToolKind.agentTaskResume.isAgentMutationTool, isTrue);
      expect(AiBuiltinToolKind.agentTaskComplete.isAgentMutationTool, isTrue);

      expect(AiBuiltinToolKind.bash.isAgentMutationTool, isFalse);
    });
  });
}
