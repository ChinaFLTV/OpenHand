import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/index.dart';

void main() {
  test('summarizes agent capabilities with agent-tool aliases', () {
    const agent = AgentProfile(
      id: 'agent-1',
      name: 'Ops Agent',
      skillNames: <String>['ops-triage'],
      knowledgeSourceIds: <String>['kb-1'],
      memoryIds: <String>['memory-1'],
      mcpServerNames: <String>['ops-mcp'],
      builtinToolNames: <String>[
        'AgentList',
        'agentTaskResult',
        'AgentApprovalRequest',
        'agent_resource_update',
        'agentClusterStatus',
        'Bash',
      ],
      cronIds: <String>['daily-report'],
      hookIds: <String>['approval-hook'],
    );

    final summary =
        agentCapabilityBindingsJson(agent)['summary'] as Map<String, Object?>;

    expect(summary['skills'], 1);
    expect(summary['knowledge_sources'], 1);
    expect(summary['memories'], 1);
    expect(summary['mcp_servers'], 1);
    expect(summary['builtin_tools'], 6);
    expect(summary['agent_coordination_tools'], 5);
    expect(summary['agent_coordination_tool_groups'], <String, int>{
      'discovery': 1,
      'task_lifecycle': 1,
      'governance': 1,
      'operations': 1,
      'cluster': 1,
    });
    expect(summary['automations'], 2);
    expect(summary['has_external_actions'], isTrue);
    expect(summary['has_self_learning_inputs'], isTrue);
  });

  test(
    'omits explicit empty agent-tool binding sentinel from capabilities',
    () {
      const agent = AgentProfile(
        id: 'agent-1',
        name: 'Ops Agent',
        builtinToolNames: <String>['Bash', agentNoCoordinationToolsBinding],
      );

      final bindings = agentCapabilityBindingsJson(agent);
      final summary = bindings['summary'] as Map<String, Object?>;

      expect(bindings['builtin_tools'], <String>['Bash']);
      expect(summary['builtin_tools'], 1);
      expect(summary['agent_coordination_tools'], 0);
      expect(summary['agent_coordination_tool_groups'], isEmpty);
      expect(summary['has_external_actions'], isTrue);
    },
  );

  test(
    'does not count unknown agent-prefixed builtin names as coordination',
    () {
      const agent = AgentProfile(
        id: 'agent-1',
        name: 'Ops Agent',
        builtinToolNames: <String>['AgentTaskFoo', 'AgentList'],
      );

      final bindings = agentCapabilityBindingsJson(agent);
      final summary = bindings['summary'] as Map<String, Object?>;

      expect(bindings['builtin_tools'], <String>['AgentTaskFoo', 'AgentList']);
      expect(summary['builtin_tools'], 2);
      expect(summary['agent_coordination_tools'], 1);
      expect(summary['agent_coordination_tool_groups'], <String, int>{
        'discovery': 1,
      });
    },
  );

  test('filters capabilities by callable agent tools', () {
    const explicit = AgentProfile(
      id: 'agent-1',
      name: 'Ops Agent',
      builtinToolNames: <String>[
        'AgentTaskPublish',
        'AgentTaskProgress',
        'AgentTaskResult',
        'Bash',
      ],
    );
    const defaultAll = AgentProfile(id: 'agent-2', name: 'Default Agent');

    final explicitBindings = agentCapabilityBindingsJson(
      explicit,
      callableAgentToolNames: const <String>{
        'AgentTaskPublish',
        'agent_task_progress',
      },
    );
    final explicitSummary = explicitBindings['summary'] as Map<String, Object?>;
    final defaultBindings = agentCapabilityBindingsJson(
      defaultAll,
      callableAgentToolNames: const <String>{'AgentList', 'agent_detail'},
    );
    final defaultSummary = defaultBindings['summary'] as Map<String, Object?>;

    expect(explicitBindings['builtin_tools'], <String>[
      'AgentTaskPublish',
      'AgentTaskProgress',
      'Bash',
    ]);
    expect(explicitSummary['builtin_tools'], 3);
    expect(explicitSummary['agent_coordination_tools'], 2);
    expect(explicitSummary['agent_coordination_tool_groups'], <String, int>{
      'task_lifecycle': 2,
    });
    expect(defaultBindings['builtin_tools'], <String>[
      'AgentList',
      'AgentDetail',
    ]);
    expect(defaultSummary['agent_coordination_tools'], 2);
    expect(defaultSummary['agent_coordination_tool_groups'], <String, int>{
      'discovery': 2,
    });
  });

  test('builds workspace policy from workspace path and scoped roots', () {
    const scoped = AgentProfile(
      id: 'agent-1',
      name: 'Ops Agent',
      workspacePath: '/repo',
      workspaceScopePaths: <String>['/repo/app', '/repo/docs'],
    );
    const empty = AgentProfile(id: 'agent-2', name: 'Empty Agent');

    expect(agentWorkspacePolicyJson(scoped), <String, Object?>{
      'allowed_roots': <String>['/repo', '/repo/app', '/repo/docs'],
      'writes_limited_to_allowed_roots': true,
      'requires_confirmation_when_empty': false,
    });
    expect(agentWorkspacePolicyJson(empty), <String, Object?>{
      'allowed_roots': <String>[],
      'writes_limited_to_allowed_roots': true,
      'requires_confirmation_when_empty': true,
    });
  });
}
