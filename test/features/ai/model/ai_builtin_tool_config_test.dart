import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/model/agent_models.dart';
import 'package:openhand/features/ai/model/ai_builtin_tool_config.dart';
import 'package:openhand/features/ai/util/agent_builtin_tool_display.dart';

void main() {
  group('AiBuiltinToolKind agent metadata', () {
    test('classifies all agent coordination tools', () {
      final agentTools = AiBuiltinToolKind.values
          .where((kind) => kind.name.startsWith('agent'))
          .toSet();

      expect(agentTools, isNotEmpty);
      expect(agentTools.every((kind) => kind.isAgentCoordinationTool), isTrue);
      expect(agentTools.every((kind) => kind.agentToolGroup != null), isTrue);
      expect(AiBuiltinToolKind.bash.isAgentCoordinationTool, isFalse);
      expect(AiBuiltinToolKind.bash.agentToolGroup, isNull);
      expect(AiBuiltinToolKind.webSearch.isAgentCoordinationTool, isFalse);
    });

    test('groups agent tools by user-facing capability area', () {
      expect(
        AiBuiltinToolKind.agentList.agentToolGroup,
        AiAgentBuiltinToolGroup.discovery,
      );
      expect(
        AiBuiltinToolKind.agentDetail.agentToolGroup,
        AiAgentBuiltinToolGroup.discovery,
      );
      expect(
        AiBuiltinToolKind.agentTaskPublish.agentToolGroup,
        AiAgentBuiltinToolGroup.taskLifecycle,
      );
      expect(
        AiBuiltinToolKind.agentTaskResult.agentToolGroup,
        AiAgentBuiltinToolGroup.taskLifecycle,
      );
      expect(
        AiBuiltinToolKind.agentActivityLog.agentToolGroup,
        AiAgentBuiltinToolGroup.governance,
      );
      expect(
        AiBuiltinToolKind.agentApprovalRequest.agentToolGroup,
        AiAgentBuiltinToolGroup.governance,
      );
      expect(
        AiBuiltinToolKind.agentKpiUpsert.agentToolGroup,
        AiAgentBuiltinToolGroup.operations,
      );
      expect(
        AiBuiltinToolKind.agentResourceUpdate.agentToolGroup,
        AiAgentBuiltinToolGroup.operations,
      );
      expect(
        AiBuiltinToolKind.agentClusterStatus.agentToolGroup,
        AiAgentBuiltinToolGroup.cluster,
      );
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

    test('keeps agent profile builtin normalization in sync', () {
      final agentTools = AiBuiltinToolKind.values.where(
        (kind) => kind.isAgentCoordinationTool,
      );

      for (final kind in agentTools) {
        final canonical = agentBuiltinToolCanonicalName(kind);
        expect(
          isAgentCoordinationBuiltinToolName(canonical),
          isTrue,
          reason: '$canonical should be recognized from canonical name',
        );
        expect(
          isAgentCoordinationBuiltinToolName(kind.name),
          isTrue,
          reason: '${kind.name} should be recognized from enum name',
        );
        expect(
          isAgentCoordinationBuiltinToolName(_snakeCase(canonical)),
          isTrue,
          reason: '$canonical should be recognized from snake_case alias',
        );
      }

      expect(isAgentCoordinationBuiltinToolName('bash'), isFalse);
      expect(isAgentCoordinationBuiltinToolName('web_search'), isFalse);
      expect(
        normalizeAgentBuiltinToolNames(<String>[
          'Bash',
          agentBuiltinToolCanonicalName(AiBuiltinToolKind.agentTaskPublish),
          agentNoCoordinationToolsBinding,
          _snakeCase(
            agentBuiltinToolCanonicalName(AiBuiltinToolKind.agentList),
          ),
        ]),
        <String>['Bash', agentNoCoordinationToolsBinding],
      );
      expect(
        normalizeAgentBuiltinToolNames(<String>[
          'AgentTaskPublish',
          'agentTaskPublish',
          'agent_task_publish',
          'AgentTaskFoo',
          'agenttaskfoo',
        ]),
        <String>['AgentTaskPublish', 'AgentTaskFoo'],
      );
    });
  });
}

String _snakeCase(String value) {
  final buffer = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    final code = value.codeUnitAt(i);
    final isUpper = code >= 0x41 && code <= 0x5A;
    if (isUpper && i > 0) buffer.write('_');
    buffer.writeCharCode(isUpper ? code | 0x20 : code);
  }
  return buffer.toString();
}
