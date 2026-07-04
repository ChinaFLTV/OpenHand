import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        skillNames: <String>['release-checklist'],
        mcpServerNames: <String>['deploy-mcp'],
        builtinToolNames: <String>['AgentTaskPublish', 'Bash'],
        cronIds: <String>['weekly-release-report'],
        hookIds: <String>['release-hook'],
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

    expect(snapshot.version, '1.2.13');
    expect(routing['has_route'], isTrue);
    expect(routing['keywords'], <Object?>[
      'release',
      'deploy',
      'release-checklist',
    ]);
    expect(profile['metadata'], <String, Object?>{
      'cost_center': 'release-platform',
    });
    expect(snapshot.renderedPrompt, contains('"routing"'));
    expect(snapshot.renderedPrompt, contains('"metadata"'));
    expect(snapshot.renderedPrompt, contains('"active_tasks"'));
    expect(snapshot.renderedPrompt, contains('"kpi_state"'));
    expect(snapshot.renderedPrompt, contains('"workspace_scope_paths"'));
    expect(snapshot.renderedPrompt, contains('"workspace_policy"'));
    expect(snapshot.renderedPrompt, contains('"agent_coordination_tools"'));
    expect(snapshot.renderedPrompt, contains('AgentTaskPublish'));
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
    final capabilities =
        snapshot.metadataJson()['capabilities'] as Map<String, Object?>;
    final capabilitySummary = capabilities['summary'] as Map<String, Object?>;
    expect(capabilitySummary['skills'], 1);
    expect(capabilitySummary['mcp_servers'], 1);
    expect(capabilitySummary['builtin_tools'], 2);
    expect(capabilitySummary['agent_coordination_tools'], 1);
    expect(capabilitySummary['agent_coordination_tool_groups'], <String, int>{
      'task_lifecycle': 1,
    });
    expect(capabilitySummary['automations'], 2);
    expect(capabilitySummary['has_external_actions'], isTrue);
    expect(capabilitySummary['has_self_learning_inputs'], isTrue);
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
    final workspacePolicy =
        runtimePolicy['workspace_policy'] as Map<String, Object?>;
    expect(workspacePolicy['allowed_roots'], <Object?>[
      '/repo',
      '/repo/app',
      '/repo/docs',
    ]);
    expect(workspacePolicy['writes_limited_to_allowed_roots'], isTrue);
    expect(workspacePolicy['requires_confirmation_when_empty'], isFalse);
    expect(activeTasks, hasLength(2));
    expect(blockedTasks, hasLength(1));
    expect(terminalTasks, hasLength(1));
    expect(kpiState, hasLength(1));
    expect(recentActivity, hasLength(1));
    expect(
      (recentActivity.single as Map<String, Object?>)['message_type'],
      'thought',
    );
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

  test(
    'prompt renderer bounds long task context while preserving summaries',
    () async {
      final longContent = List<String>.filled(260, '云账单对账证据-').join();
      final longResult = List<String>.filled(260, '处理结果明细-').join();
      final longExtra = List<String>.filled(180, '额外上下文-').join();
      final snapshot =
          await AgentPromptRenderer(
            loader: (_) async => '''
<operational_state>
{{OPERATIONAL_STATE_JSON}}
</operational_state>
''',
          ).render(
            agent: AgentProfile(
              id: 'agent-long',
              name: 'Long Context Agent',
              tasks: <AgentTask>[
                AgentTask(
                  id: 'task-long',
                  title: 'Long context task',
                  content: longContent,
                  result: longResult,
                  note: List<String>.filled(360, '备注-').join(),
                  status: AgentTaskStatus.running,
                  extra: <String, Object?>{
                    'large_payload': longExtra,
                    'nested': <String, Object?>{
                      'items': List<String>.generate(
                        45,
                        (index) => 'item-$index',
                      ),
                    },
                    'agent_system_prompt': 'hidden prompt text',
                  },
                ),
              ],
            ),
          );

      final operationalState =
          snapshot.metadataJson()['operational_state'] as Map<String, Object?>;
      final activeTasks = operationalState['active_tasks'] as List<Object?>;
      final task = activeTasks.single as Map<String, Object?>;
      final extra = task['extra'] as Map<String, Object?>;
      final nested = extra['nested'] as Map<String, Object?>;
      final items = nested['items'] as List<Object?>;
      final omittedPrompt =
          extra['agent_system_prompt'] as Map<String, Object?>;

      expect(snapshot.version, '1.2.13');
      expect(task['content'], isA<String>());
      expect(task['content'], contains('[truncated:'));
      expect(task['content'], isNot(longContent));
      expect(task['result'], contains('[truncated:'));
      expect(task['note'], contains('[truncated:'));
      expect(extra['large_payload'], contains('[truncated:'));
      expect(items, hasLength(41));
      expect(items.last, <String, Object?>{'_truncated_items': 5});
      expect(omittedPrompt['omitted'], isTrue);
      expect(snapshot.renderedPrompt, isNot(contains('hidden prompt text')));
      expect(snapshot.renderedPrompt, isNot(contains(longContent)));
      expect(snapshot.renderedPrompt, isNot(contains(longResult)));
      expect(snapshot.renderedPrompt, isNot(contains(longExtra)));
    },
  );

  test('prompt renderer bounds activity and audit metadata', () async {
    final largeMetadata = List<String>.filled(180, '工具输出片段-').join();
    final largeActivityContent = List<String>.filled(180, '活动正文片段-').join();
    final largeAuditSummary = List<String>.filled(180, '审计摘要片段-').join();
    final hiddenPrompt = List<String>.filled(
      120,
      'hidden-system-prompt-',
    ).join();
    final snapshot =
        await AgentPromptRenderer(
          loader: (_) async => '''
<operational_state>
{{OPERATIONAL_STATE_JSON}}
</operational_state>
''',
        ).render(
          agent: AgentProfile(
            id: 'agent-metadata',
            name: 'Metadata Agent',
            activities: <AgentActivityEvent>[
              AgentActivityEvent(
                id: 'activity-large',
                kind: 'tool_call',
                title: 'Read tool output',
                content: largeActivityContent,
                metadata: <String, Object?>{
                  'tool_output': largeMetadata,
                  'rendered_prompt': hiddenPrompt,
                },
              ),
            ],
            auditEvents: <AgentAuditEvent>[
              AgentAuditEvent(
                id: 'audit-large',
                kind: 'mcp_call',
                summary: largeAuditSummary,
                metadata: <String, Object?>{
                  'raw_payload': largeMetadata,
                  'agent_system_prompt': hiddenPrompt,
                },
              ),
            ],
          ),
        );

    final operationalState =
        snapshot.metadataJson()['operational_state'] as Map<String, Object?>;
    final activity =
        (operationalState['recent_activity'] as List<Object?>).single
            as Map<String, Object?>;
    final audit =
        (operationalState['recent_audit_events'] as List<Object?>).single
            as Map<String, Object?>;
    final activityMetadata = activity['metadata'] as Map<String, Object?>;
    final auditMetadata = audit['metadata'] as Map<String, Object?>;
    final renderedPrompt =
        activityMetadata['rendered_prompt'] as Map<String, Object?>;
    final agentSystemPrompt =
        auditMetadata['agent_system_prompt'] as Map<String, Object?>;

    expect(snapshot.version, '1.2.13');
    expect(activity['content'], contains('[truncated:'));
    expect(audit['summary'], contains('[truncated:'));
    expect(activityMetadata['tool_output'], contains('[truncated:'));
    expect(auditMetadata['raw_payload'], contains('[truncated:'));
    expect(renderedPrompt['omitted'], isTrue);
    expect(agentSystemPrompt['omitted'], isTrue);
    expect(snapshot.renderedPrompt, isNot(contains(largeActivityContent)));
    expect(snapshot.renderedPrompt, isNot(contains(largeAuditSummary)));
    expect(snapshot.renderedPrompt, isNot(contains(largeMetadata)));
    expect(snapshot.renderedPrompt, isNot(contains(hiddenPrompt)));
  });

  test(
    'prompt renderer bounds external task context and preserves task priority',
    () async {
      final longIncomingContent = List<String>.filled(260, '外部任务上下文片段-').join();
      final hiddenPrompt = List<String>.filled(100, 'hidden-prompt-').join();
      final snapshot =
          await AgentPromptRenderer(
            loader: (_) async => '''
<task_context>
{{TASK_CONTEXT_JSON}}
</task_context>
''',
          ).render(
            agent: const AgentProfile(
              id: 'agent-context',
              name: 'Context Agent',
            ),
            task: const AgentTask(
              id: 'task-explicit',
              title: 'Explicit task wins',
              content: 'Use this explicit task.',
            ),
            taskContext: <String, Object?>{
              'task': <String, Object?>{
                'id': 'task-overridden',
                'title': 'External task should not override',
              },
              'incoming_task': <String, Object?>{
                'title': 'Long incoming task',
                'content': longIncomingContent,
                'rendered_prompt': hiddenPrompt,
              },
            },
          );

      final incomingTask =
          snapshot.taskContext['incoming_task'] as Map<String, Object?>;
      final explicitTask = snapshot.taskContext['task'] as Map<String, Object?>;
      final omittedPrompt =
          incomingTask['rendered_prompt'] as Map<String, Object?>;

      expect(snapshot.version, '1.2.13');
      expect(explicitTask['id'], 'task-explicit');
      expect(explicitTask['title'], 'Explicit task wins');
      expect(incomingTask['content'], contains('[truncated:'));
      expect(omittedPrompt['omitted'], isTrue);
      expect(snapshot.renderedPrompt, isNot(contains(longIncomingContent)));
      expect(snapshot.renderedPrompt, isNot(contains(hiddenPrompt)));
      expect(snapshot.renderedPrompt, isNot(contains('task-overridden')));
    },
  );

  test(
    'prompt renderer keeps full structured fallback when asset is empty',
    () async {
      final renderer = AgentPromptRenderer(loader: (_) async => '');

      final snapshot = await renderer.render(
        agent: const AgentProfile(
          id: 'agent-fallback',
          name: 'Fallback Agent',
          position: 'Ops Partner',
          responsibilityBoundary: 'Handle safe operational checks.',
        ),
      );

      expect(snapshot.version, '1.2.13');
      expect(snapshot.renderedPrompt, contains('<operating_contract>'));
      expect(snapshot.renderedPrompt, contains('<task_dispatch>'));
      expect(snapshot.renderedPrompt, contains('<agent_coordination_tools>'));
      expect(snapshot.renderedPrompt, contains('AgentTaskResult'));
      expect(snapshot.renderedPrompt, contains('<approval_and_risk>'));
      expect(
        snapshot.renderedPrompt,
        contains('<tool_and_capability_discipline>'),
      );
      expect(snapshot.renderedPrompt, contains('<self_learning>'));
      expect(snapshot.renderedPrompt, contains('<stop_condition>'));
      expect(snapshot.renderedPrompt, contains('"name": "Fallback Agent"'));
      expect(
        snapshot.renderedPrompt,
        isNot(contains('{{AGENT_PROFILE_JSON}}')),
      );
      expect(snapshot.renderedPrompt, isNot(contains('{{TASK_CONTEXT_JSON}}')));
    },
  );

  test(
    'prompt renderer omits concrete agent tools when coordination tools are cleared',
    () async {
      final snapshot = await AgentPromptRenderer().render(
        agent: const AgentProfile(
          id: 'agent-no-coordination-tools',
          name: 'No Coordination Agent',
          builtinToolNames: <String>['Bash', agentNoCoordinationToolsBinding],
        ),
      );

      expect(snapshot.version, '1.2.13');
      expect(snapshot.renderedPrompt, contains('<agent_coordination_tools>'));
      expect(
        snapshot.renderedPrompt,
        contains('No Agent coordination tools are bound.'),
      );
      expect(snapshot.renderedPrompt, contains('"builtin_tools": ['));
      expect(snapshot.renderedPrompt, contains('"Bash"'));
      expect(snapshot.renderedPrompt, isNot(contains('AgentTaskPublish')));
      expect(snapshot.renderedPrompt, isNot(contains('AgentTaskResult')));
      expect(
        snapshot.renderedPrompt,
        isNot(contains(agentNoCoordinationToolsBinding)),
      );
    },
  );

  test('prompt renderer lists only bound follow-up task tools', () async {
    final snapshot = await AgentPromptRenderer().render(
      agent: const AgentProfile(
        id: 'agent-track-only',
        name: 'Track Only Agent',
        builtinToolNames: <String>['AgentTaskTrack'],
      ),
    );

    expect(snapshot.version, '1.2.13');
    expect(snapshot.renderedPrompt, contains('<agent_coordination_tools>'));
    expect(snapshot.renderedPrompt, contains('AgentTaskTrack'));
    expect(snapshot.renderedPrompt, isNot(contains('AgentTaskProgress')));
    expect(snapshot.renderedPrompt, isNot(contains('AgentTaskResult')));
    expect(
      snapshot.renderedPrompt,
      contains('use only returned next_poll tools and intervals'),
    );
  });

  test(
    'bundled digital employee prompt stays structured and compact',
    () async {
      final snapshot = await AgentPromptRenderer().render(
        agent: const AgentProfile(
          id: 'agent-bundled',
          name: 'Bundled Agent',
          responsibilityBoundary: 'Handle delegated operations tasks.',
        ),
      );

      expect(snapshot.assetPath, AgentPromptRenderer.defaultAssetPath);
      expect(snapshot.version, '1.2.13');
      expect(snapshot.renderedPrompt, contains('<identity>'));
      expect(snapshot.renderedPrompt, contains('<task_dispatch>'));
      expect(snapshot.renderedPrompt, contains('<agent_coordination_tools>'));
      expect(snapshot.renderedPrompt, contains('AgentTaskResult'));
      expect(snapshot.renderedPrompt, contains('<approval_and_risk>'));
      expect(snapshot.renderedPrompt, contains('<self_learning>'));
      expect(
        snapshot.renderedPrompt,
        contains('Do not turn every user request into a delegated task.'),
      );
      expect(snapshot.renderedPrompt, contains('"name": "Bundled Agent"'));
      expect(
        snapshot.renderedPrompt,
        isNot(contains('{{AGENT_PROFILE_JSON}}')),
      );
      expect(snapshot.renderedPrompt, isNot(contains('{{TASK_CONTEXT_JSON}}')));
      expect(snapshot.renderedPrompt.length, lessThan(7500));
    },
  );
}
