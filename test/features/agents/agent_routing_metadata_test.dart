import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/index.dart';

void main() {
  test('parses yaml front matter and builds stable routing keywords', () {
    const agent = AgentProfile(
      id: 'agent-1',
      name: 'Finance Agent',
      routeFrontMatter: '''
---
route: finance
priority: 20
keywords:
  - invoice
  - reconciliation
domains: cloud, finops
---
''',
      taskLabels: <String>['finance', 'audit'],
      skillNames: <String>['invoice'],
    );

    final routing = AgentRoutingMetadata.fromAgent(agent);

    expect(routing.hasRoute, isTrue);
    expect(routing.frontMatter['route'], 'finance');
    expect(routing.frontMatter['priority'], 20);
    expect(routing.keywords, <String>[
      'invoice',
      'reconciliation',
      'cloud',
      'finops',
      'finance',
      'audit',
    ]);
  });

  test('parses json routing metadata', () {
    final parsed = parseAgentRouteFrontMatter(
      '{"intents":["deploy","rollback"],"priority":10}',
    );

    expect(parsed['intents'], <Object?>['deploy', 'rollback']);
    expect(parsed['priority'], 10);
  });

  test('normalizes structured workspace scope paths with legacy fallback', () {
    final legacy = AgentProfile.fromJson(<String, Object?>{
      'id': 'agent-legacy',
      'name': 'Legacy Agent',
      'workspace_scope': '/repo/app\n/repo/docs\n/repo/app',
    });
    final structured = AgentProfile.fromJson(<String, Object?>{
      'id': 'agent-structured',
      'name': 'Structured Agent',
      'workspace_scope': '/legacy/ignored',
      'workspace_scope_paths': <String>[
        '/repo/app',
        '/repo/docs',
        '/repo/app',
        ' ',
      ],
    });

    expect(legacy.normalizedWorkspaceScopePaths, <String>[
      '/repo/app',
      '/repo/docs',
    ]);
    expect(structured.normalizedWorkspaceScopePaths, <String>[
      '/repo/app',
      '/repo/docs',
    ]);
    expect(structured.workspaceScopeText, '/repo/app\n/repo/docs');
    expect(structured.toJson()['workspace_scope_paths'], <String>[
      '/repo/app',
      '/repo/docs',
    ]);
    expect(
      structured.approvalPolicy['approval_required_before_privileged_actions'],
      isTrue,
    );
  });

  test('prompt metadata exposes structured routing profile', () async {
    final renderer = AgentPromptRenderer(
      loader: (_) async => '''
<agent_profile>
{{AGENT_PROFILE_JSON}}
</agent_profile>
<capability_bindings>
{{CAPABILITY_BINDINGS_JSON}}
</capability_bindings>
<runtime_policy>
{{RUNTIME_POLICY_JSON}}
</runtime_policy>
<operational_state>
{{OPERATIONAL_STATE_JSON}}
</operational_state>
<task_context>
{{TASK_CONTEXT_JSON}}
</task_context>
''',
    );

    final snapshot = await renderer.render(
      agent: const AgentProfile(
        id: 'agent-1',
        name: 'Release Agent',
        routeFrontMatter: 'keywords: release, deploy',
        workspacePath: '/repo',
        workspaceScopePaths: <String>['/repo/app', '/repo/docs'],
        taskLabels: <String>['release'],
        metadata: <String, Object?>{'cost_center': 'release-platform'},
        approvals: <AgentApprovalRequest>[
          AgentApprovalRequest(
            id: 'approval-1',
            title: 'Deploy production',
            requestedAction: 'deploy',
          ),
        ],
        workers: <AgentWorker>[
          AgentWorker(
            id: 'worker-1',
            status: AgentWorkerStatus.busy,
            currentTaskId: 'task-1',
          ),
        ],
        tasks: <AgentTask>[
          AgentTask(
            id: 'task-1',
            title: 'Deploy release',
            content: 'Roll out the release after approval.',
            status: AgentTaskStatus.running,
            progress: 0.35,
            extra: <String, Object?>{
              'assigned_worker_id': 'worker-1',
              'agent_system_prompt': 'hidden system prompt body',
            },
          ),
          AgentTask(
            id: 'task-2',
            title: 'Wait for security sign-off',
            status: AgentTaskStatus.paused,
          ),
          AgentTask(
            id: 'task-3',
            title: 'Publish release notes',
            status: AgentTaskStatus.completed,
            result: 'Release notes published.',
          ),
        ],
        kpis: <AgentKpiItem>[
          AgentKpiItem(
            id: 'kpi-1',
            name: 'Weekly release quality',
            target: 'Keep failed rollbacks at zero',
            progress: 0.6,
            plan: 'Verify release evidence before rollout.',
          ),
        ],
        activities: <AgentActivityEvent>[
          AgentActivityEvent(
            id: 'activity-1',
            kind: 'thought',
            title: 'Review rollout risk',
          ),
        ],
        auditEvents: <AgentAuditEvent>[
          AgentAuditEvent(
            id: 'audit-1',
            kind: 'mcp_call',
            summary: 'Checked deployment status',
            toolName: 'DeployMcp',
            tokenUsage: 42,
            requestCount: 1,
          ),
        ],
      ),
    );

    final profile = snapshot.metadataJson()['profile'] as Map<String, Object?>;
    final routing = profile['routing'] as Map<String, Object?>;
    final operationalState =
        snapshot.metadataJson()['operational_state'] as Map<String, Object?>;
    final stateFlags = operationalState['state_flags'] as Map<String, Object?>;
    final workerCapacity =
        operationalState['worker_capacity'] as Map<String, Object?>;
    final activeTasks = operationalState['active_tasks'] as List<Object?>;
    final blockedTasks = operationalState['blocked_tasks'] as List<Object?>;
    final terminalTasks =
        operationalState['recent_terminal_tasks'] as List<Object?>;
    final kpiState = operationalState['kpi_state'] as List<Object?>;
    final recentActivity = operationalState['recent_activity'] as List<Object?>;
    final recentAudit =
        operationalState['recent_audit_events'] as List<Object?>;

    expect(snapshot.version, '1.2.3');
    expect(routing['has_route'], isTrue);
    expect(routing['keywords'], <Object?>['release', 'deploy']);
    expect(profile['metadata'], <String, Object?>{
      'cost_center': 'release-platform',
    });
    expect(snapshot.renderedPrompt, contains('"routing"'));
    expect(snapshot.renderedPrompt, contains('"metadata"'));
    expect(snapshot.renderedPrompt, contains('"active_tasks"'));
    expect(snapshot.renderedPrompt, contains('"kpi_state"'));
    expect(snapshot.renderedPrompt, contains('"workspace_scope_paths"'));
    expect(snapshot.renderedPrompt, contains('<operational_state>'));
    expect(
      snapshot.renderedPrompt,
      isNot(contains('hidden system prompt body')),
    );
    expect(operationalState['pending_approvals'], isNotEmpty);
    expect(operationalState['workers'], isNotEmpty);
    expect(stateFlags['has_pending_approvals'], isTrue);
    expect(stateFlags['workers_saturated'], isTrue);
    expect(stateFlags['has_blocked_tasks'], isTrue);
    expect(workerCapacity['busy'], 1);
    final runtimePolicy =
        snapshot.metadataJson()['runtime_policy'] as Map<String, Object?>;
    final approvalPolicy =
        runtimePolicy['approval_policy'] as Map<String, Object?>;
    expect(approvalPolicy['mode'], 'normal');
    expect(
      approvalPolicy['approval_required_before_privileged_actions'],
      isTrue,
    );
    expect(
      approvalPolicy['approval_required_when'],
      contains('privileged_capability_use'),
    );
    expect(runtimePolicy['workspace_scope_paths'], <Object?>[
      '/repo/app',
      '/repo/docs',
    ]);
    expect(activeTasks, hasLength(2));
    expect(blockedTasks, hasLength(1));
    expect(terminalTasks, hasLength(1));
    expect(kpiState, hasLength(1));
    expect(recentActivity, hasLength(1));
    expect(recentAudit, hasLength(1));
    expect(
      (activeTasks.first as Map<String, Object?>)['extra'],
      containsPair('assigned_worker_id', 'worker-1'),
    );
    final activeTaskExtra =
        (activeTasks.first as Map<String, Object?>)['extra']
            as Map<String, Object?>;
    final omittedPrompt =
        activeTaskExtra['agent_system_prompt'] as Map<String, Object?>;
    expect(omittedPrompt['omitted'], isTrue);
    expect(omittedPrompt['chars'], 25);
    expect(
      (terminalTasks.single as Map<String, Object?>)['result'],
      'Release notes published.',
    );
    expect(
      (recentAudit.single as Map<String, Object?>)['tool_name'],
      'DeployMcp',
    );
  });
}
