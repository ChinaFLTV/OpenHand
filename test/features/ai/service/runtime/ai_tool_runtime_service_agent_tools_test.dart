import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/agents/agents_controller.dart';
import 'package:openhand/features/agents/data/agents_store.dart';
import 'package:openhand/features/agents/model/agent_models.dart';
import 'package:openhand/features/agents/service/agent_runtime_availability.dart';
import 'package:openhand/features/ai/model/ai_creation_mode.dart';
import 'package:openhand/features/ai/model/ai_deny_command_rule.dart';
import 'package:openhand/features/ai/model/ai_input_cache_runtime_config.dart';
import 'package:openhand/features/ai/model/ai_model_config.dart';
import 'package:openhand/features/ai/model/ai_session_runtime_context.dart';
import 'package:openhand/features/ai/service/bash/ai_bash_tool_service.dart';
import 'package:openhand/features/ai/service/chat/ai_chat_service.dart';
import 'package:openhand/features/ai/service/chat/ai_protocol_adapter.dart';
import 'package:openhand/features/ai/service/hook/ai_claude_hook_service.dart';
import 'package:openhand/features/ai/service/runtime/ai_tool_runtime_service.dart';
import 'package:openhand/features/mcp/index.dart';
import 'package:openhand/features/memory/index.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Agent builtin tool catalog gate', () {
    late Directory tempDir;
    late AgentsController controller;
    late AiToolRuntimeService runtime;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'openhand_agent_tool_catalog_test_',
      );
      controller = AgentsController.uninitialized(
        store: AgentsStore(filePath: p.join(tempDir.path, 'agents.json')),
      );
      await controller.refresh();
      runtime = _runtimeService(() => controller);
    });

    tearDown(() async {
      runtime.dispose();
      controller.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('agent tool descriptions document delegation and polling rules', () {
      final publish = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentTaskPublish,
      )!;
      final progress = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentTaskProgress,
      )!;
      final track = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentTaskTrack,
      )!;
      final activity = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentActivityLog,
      )!;
      final auditReport = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentAuditReport,
      )!;
      final audit = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentAuditRecord,
      )!;
      final approval = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentApprovalRequest,
      )!;
      final kpi = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentKpiUpsert,
      )!;
      final resource = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentResourceUpdate,
      )!;
      final cluster = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentClusterConfigure,
      )!;
      final clusterStatus = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentClusterStatus,
      )!;
      final taskList = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentTaskList,
      )!;
      final result = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentTaskResult,
      )!;

      expect(
        publish.definition.description,
        contains('only when the task matches an agent responsibility'),
      );
      expect(
        publish.definition.description,
        contains('current model and local tools can complete directly'),
      );
      expect(
        publish.definition.description,
        contains('poll AgentTaskProgress or AgentTaskTrack'),
      );
      expect(
        progress.definition.description,
        contains('state.needs_polling is true'),
      );
      expect(track.definition.description, contains('operational summary'));
      expect(track.definition.description, contains('result_available'));
      expect(track.definition.description, contains('handoff'));
      expect(track.definition.description, contains('next_poll'));
      expect(
        track.definition.description,
        contains('next polling or result-handoff action'),
      );
      expect(activity.definition.description, contains('history stream'));
      expect(activity.definition.description, contains('audit trail'));
      expect(
        auditReport.definition.description,
        contains('digital employee audit report'),
      );
      expect(auditReport.definition.description, contains('worker capacity'));
      expect(auditReport.definition.description, contains('worker execution'));
      expect(auditReport.definition.description, contains('capability usage'));
      expect(
        audit.definition.description,
        contains('Record an auditable digital employee capability event'),
      );
      expect(audit.definition.description, contains('request_count'));
      expect(
        approval.definition.description,
        contains('Create an auditable approval request'),
      );
      expect(
        approval.definition.description,
        contains('needs mentor/user permission'),
      );
      expect(
        kpi.definition.description,
        contains('Create or update a digital employee KPI'),
      );
      expect(
        kpi.definition.description,
        contains('updates a matching KPI name before creating a new one'),
      );
      expect(
        resource.definition.description,
        contains('Update one enabled digital employee resource snapshot'),
      );
      expect(resource.definition.description, contains('Omitted fields keep'));
      expect(
        cluster.definition.description,
        contains('Configure one enabled digital employee worker cluster'),
      );
      expect(cluster.definition.description, contains('Omitted fields keep'));
      expect(
        clusterStatus.definition.description,
        contains('Read one digital employee worker cluster status'),
      );
      expect(clusterStatus.definition.description, contains('queue pressure'));
      expect(
        taskList.definition.description,
        contains('List tasks from one digital employee task desk'),
      );
      expect(taskList.definition.description, contains('discover task ids'));
      expect(
        result.definition.description,
        contains('terminal, requires attention'),
      );
      expect(result.definition.description, contains('result_available'));
      expect(result.definition.description, contains('handoff'));
      expect(result.definition.description, contains('next_poll'));
    });

    test('agent task schemas allow task id aliases and update extra', () {
      for (final kind in const <AiBuiltinToolKind>[
        AiBuiltinToolKind.agentTaskTrack,
        AiBuiltinToolKind.agentTaskProgress,
        AiBuiltinToolKind.agentTaskCancel,
        AiBuiltinToolKind.agentTaskPause,
        AiBuiltinToolKind.agentTaskTerminate,
        AiBuiltinToolKind.agentTaskResume,
        AiBuiltinToolKind.agentTaskComplete,
        AiBuiltinToolKind.agentTaskResult,
      ]) {
        final parameters = AiToolRuntimeService.builtinToolDefault(
          kind,
        )!.definition.parameters;
        expect(_schemaAllowsRequired(parameters, 'agent_id'), isTrue);
        expect(_schemaAllowsRequired(parameters, 'agent_name'), isTrue);
        expect(_schemaAllowsRequired(parameters, 'agent'), isTrue);
        expect(_schemaAllowsRequired(parameters, 'task_id'), isTrue);
        expect(_schemaAllowsRequired(parameters, 'id'), isTrue);
        expect(
          _directRequiredFields(parameters),
          isNot(contains('task_id')),
          reason: '$kind should allow id as a task_id alias',
        );
      }

      for (final kind in const <AiBuiltinToolKind>[
        AiBuiltinToolKind.agentApprovalRequest,
        AiBuiltinToolKind.agentTaskPublish,
        AiBuiltinToolKind.agentTaskCancel,
        AiBuiltinToolKind.agentTaskPause,
        AiBuiltinToolKind.agentTaskTerminate,
        AiBuiltinToolKind.agentTaskResume,
        AiBuiltinToolKind.agentTaskComplete,
      ]) {
        final parameters = AiToolRuntimeService.builtinToolDefault(
          kind,
        )!.definition.parameters;
        final properties = parameters['properties'] as Map<String, Object?>;
        expect(properties['extra'], isA<Map<String, Object?>>());
      }

      final completeRequired = _directRequiredFields(
        AiToolRuntimeService.builtinToolDefault(
          AiBuiltinToolKind.agentTaskComplete,
        )!.definition.parameters,
      );
      expect(completeRequired, contains('result'));
      expect(completeRequired, isNot(contains('task_id')));

      final approvalRequired = _directRequiredFields(
        AiToolRuntimeService.builtinToolDefault(
          AiBuiltinToolKind.agentApprovalRequest,
        )!.definition.parameters,
      );
      expect(approvalRequired, contains('title'));

      for (final kind in const <AiBuiltinToolKind>[
        AiBuiltinToolKind.agentActivityLog,
        AiBuiltinToolKind.agentAuditReport,
      ]) {
        final parameters = AiToolRuntimeService.builtinToolDefault(
          kind,
        )!.definition.parameters;
        final properties = parameters['properties'] as Map<String, Object?>;
        final messageType = properties['message_type'] as Map<String, Object?>;
        expect(messageType['enum'], contains('thought'));
        expect(messageType['enum'], contains('tool_call'));
        expect(messageType['enum'], contains('multimedia'));
        expect(properties['activity_type'], isA<Map<String, Object?>>());
      }

      final kpiParameters = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentKpiUpsert,
      )!.definition.parameters;
      expect(_schemaAnyOfAllowsRequired(kpiParameters, 'name'), isTrue);
      expect(_schemaAnyOfAllowsRequired(kpiParameters, 'title'), isTrue);
      expect(_schemaAnyOfAllowsRequired(kpiParameters, 'kpi_id'), isTrue);
      expect(_schemaAnyOfAllowsRequired(kpiParameters, 'id'), isTrue);
      final kpiProperties = kpiParameters['properties'] as Map<String, Object?>;
      final statusSchema = kpiProperties['status'] as Map<String, Object?>;
      expect(statusSchema['enum'], contains('at_risk'));
      expect(kpiProperties['extra'], isA<Map<String, Object?>>());

      final resourceParameters = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentResourceUpdate,
      )!.definition.parameters;
      expect(
        _schemaAnyOfAllowsRequired(resourceParameters, 'agent_id'),
        isTrue,
      );
      expect(
        _schemaAnyOfAllowsRequired(resourceParameters, 'agent_name'),
        isTrue,
      );
      final resourceProperties =
          resourceParameters['properties'] as Map<String, Object?>;
      expect(resourceProperties['cpu_percent'], isA<Map<String, Object?>>());
      expect(resourceProperties['memory_bytes'], isA<Map<String, Object?>>());
      expect(resourceProperties['extra'], isA<Map<String, Object?>>());

      final clusterParameters = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentClusterConfigure,
      )!.definition.parameters;
      expect(_schemaAnyOfAllowsRequired(clusterParameters, 'agent_id'), isTrue);
      final clusterProperties =
          clusterParameters['properties'] as Map<String, Object?>;
      final schedulerSchema =
          clusterProperties['scheduler_policy'] as Map<String, Object?>;
      expect(schedulerSchema['enum'], contains('round_robin'));
      final removalSchema =
          clusterProperties['worker_removal_policy'] as Map<String, Object?>;
      expect(removalSchema['enum'], contains('newest_first'));

      final clusterStatusParameters = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentClusterStatus,
      )!.definition.parameters;
      expect(
        _schemaAnyOfAllowsRequired(clusterStatusParameters, 'agent_id'),
        isTrue,
      );
      final clusterStatusProperties =
          clusterStatusParameters['properties'] as Map<String, Object?>;
      expect(clusterStatusProperties['worker_id'], isA<Map<String, Object?>>());
      expect(
        clusterStatusProperties['include_tasks'],
        isA<Map<String, Object?>>(),
      );
      expect(
        clusterStatusProperties['include_audit'],
        isA<Map<String, Object?>>(),
      );
      final clusterStatusLimit =
          clusterStatusProperties['limit'] as Map<String, Object?>;
      expect(clusterStatusLimit['maximum'], 100);

      final taskListParameters = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentTaskList,
      )!.definition.parameters;
      expect(
        _schemaAnyOfAllowsRequired(taskListParameters, 'agent_id'),
        isTrue,
      );
      final taskListProperties =
          taskListParameters['properties'] as Map<String, Object?>;
      final taskStatusSchema =
          taskListProperties['status'] as Map<String, Object?>;
      expect(taskStatusSchema['enum'], contains('waiting_approval'));
      expect(taskListProperties['worker_id'], isA<Map<String, Object?>>());
      expect(taskListProperties['labels'], isA<Map<String, Object?>>());
      expect(taskListProperties['label'], isA<Map<String, Object?>>());
      final taskLimitSchema =
          taskListProperties['limit'] as Map<String, Object?>;
      expect(taskLimitSchema['maximum'], 200);

      final auditParameters = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentAuditRecord,
      )!.definition.parameters;
      expect(_directRequiredFields(auditParameters), contains('summary'));
      expect(_schemaAnyOfAllowsRequired(auditParameters, 'agent_id'), isTrue);
      final auditProperties =
          auditParameters['properties'] as Map<String, Object?>;
      expect(auditProperties['tool_name'], isA<Map<String, Object?>>());
      expect(auditProperties['metadata'], isA<Map<String, Object?>>());

      final activityParameters = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentActivityLog,
      )!.definition.parameters;
      expect(
        _schemaAnyOfAllowsRequired(activityParameters, 'agent_id'),
        isTrue,
      );
      expect(
        _schemaAnyOfAllowsRequired(activityParameters, 'agent_name'),
        isTrue,
      );
      expect(_schemaAnyOfAllowsRequired(activityParameters, 'agent'), isTrue);
      final activityProperties =
          activityParameters['properties'] as Map<String, Object?>;
      expect(
        activityProperties['include_activities'],
        isA<Map<String, Object?>>(),
      );
      expect(activityProperties['include_audit'], isA<Map<String, Object?>>());
      expect(activityProperties['task_id'], isA<Map<String, Object?>>());
      expect(activityProperties['worker_id'], isA<Map<String, Object?>>());
      expect(activityProperties['tool_name'], isA<Map<String, Object?>>());
      final limitSchema = activityProperties['limit'] as Map<String, Object?>;
      expect(limitSchema['maximum'], 100);

      final reportParameters = AiToolRuntimeService.builtinToolDefault(
        AiBuiltinToolKind.agentAuditReport,
      )!.definition.parameters;
      expect(_schemaAnyOfAllowsRequired(reportParameters, 'agent_id'), isTrue);
      final reportProperties =
          reportParameters['properties'] as Map<String, Object?>;
      expect(reportProperties['task_id'], isA<Map<String, Object?>>());
      expect(reportProperties['worker_id'], isA<Map<String, Object?>>());
      expect(reportProperties['tool_name'], isA<Map<String, Object?>>());
      final reportLimitSchema =
          reportProperties['limit'] as Map<String, Object?>;
      expect(reportLimitSchema['maximum'], 100);
    });

    test('hides agent tools until at least one agent is enabled', () async {
      var catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(catalog.find('AgentList'), isNull);
      expect(catalog.find('AgentTaskPublish'), isNull);

      await controller.saveAgent(_agent(enabled: false));
      catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(catalog.find('AgentList'), isNull);

      await controller.setAgentEnabled('agent-1', enabled: true);
      catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(
        catalog.find('AgentList')?.builtinKind,
        AiBuiltinToolKind.agentList,
      );
      expect(
        catalog.find('AgentTaskPublish')?.builtinKind,
        AiBuiltinToolKind.agentTaskPublish,
      );
      expect(
        catalog.find('AgentAuditRecord')?.builtinKind,
        AiBuiltinToolKind.agentAuditRecord,
      );
      expect(
        catalog.find('AgentActivityLog')?.builtinKind,
        AiBuiltinToolKind.agentActivityLog,
      );
      expect(
        catalog.find('AgentAuditReport')?.builtinKind,
        AiBuiltinToolKind.agentAuditReport,
      );
      expect(
        catalog.find('AgentApprovalRequest')?.builtinKind,
        AiBuiltinToolKind.agentApprovalRequest,
      );
      expect(
        catalog.find('AgentKpiUpsert')?.builtinKind,
        AiBuiltinToolKind.agentKpiUpsert,
      );
      expect(
        catalog.find('AgentResourceUpdate')?.builtinKind,
        AiBuiltinToolKind.agentResourceUpdate,
      );
      expect(
        catalog.find('AgentClusterConfigure')?.builtinKind,
        AiBuiltinToolKind.agentClusterConfigure,
      );
      expect(
        catalog.find('AgentClusterStatus')?.builtinKind,
        AiBuiltinToolKind.agentClusterStatus,
      );
      expect(
        catalog.find('AgentTaskList')?.builtinKind,
        AiBuiltinToolKind.agentTaskList,
      );
      expect(
        catalog.find('AgentTaskComplete')?.builtinKind,
        AiBuiltinToolKind.agentTaskComplete,
      );

      await controller.setAgentEnabled('agent-1', enabled: false);
      catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      expect(catalog.find('AgentList'), isNull);
      expect(catalog.find('AgentTaskPublish'), isNull);
      expect(catalog.find('AgentAuditRecord'), isNull);
      expect(catalog.find('AgentActivityLog'), isNull);
      expect(catalog.find('AgentAuditReport'), isNull);
      expect(catalog.find('AgentApprovalRequest'), isNull);
      expect(catalog.find('AgentKpiUpsert'), isNull);
      expect(catalog.find('AgentResourceUpdate'), isNull);
      expect(catalog.find('AgentClusterConfigure'), isNull);
      expect(catalog.find('AgentClusterStatus'), isNull);
      expect(catalog.find('AgentTaskList'), isNull);
      expect(catalog.find('AgentTaskComplete'), isNull);
    });

    test(
      'returns runtime diagnostics when a stale catalog outlives Hermes availability',
      () async {
        await controller.saveAgent(_agent(enabled: true));
        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        expect(catalog.find('AgentList'), isNotNull);

        controller.setRuntimeAvailabilityProvider(
          () => const AgentRuntimeAvailability(
            isLoading: true,
            isInstalled: true,
            isEnabled: true,
            pluginName: 'Hermes Agent',
          ),
        );

        final result = await _executeAgentList(runtime, catalog);

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(result.resultText, contains('Agent runtime is unavailable'));
        expect(result.resultText, contains('runtime is still loading'));
      },
    );

    test(
      'returns precise diagnostics when a stale catalog has no enabled agents',
      () async {
        await controller.saveAgent(_agent(enabled: true));
        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        expect(catalog.find('AgentList'), isNotNull);

        await controller.setAgentEnabled('agent-1', enabled: false);

        final result = await _executeAgentList(runtime, catalog);

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(result.resultText, contains('No enabled agents are available'));
      },
    );

    test(
      'returns precise diagnostics when a stale catalog has no configured agents',
      () async {
        await controller.saveAgent(_agent(enabled: true));
        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        expect(catalog.find('AgentList'), isNotNull);

        await controller.deleteAgent('agent-1');

        final result = await _executeAgentList(runtime, catalog);

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(result.resultText, contains('No agents are configured'));
      },
    );

    test(
      'filters agent tools by enabled agent builtin tool bindings',
      () async {
        await controller.saveAgent(
          _agent(
            enabled: true,
            builtinToolNames: const <String>[
              'AgentList',
              'agent_task_track',
              'agent_cluster_status',
            ],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );

        expect(
          catalog.find('AgentList')?.builtinKind,
          AiBuiltinToolKind.agentList,
        );
        expect(
          catalog.find('AgentTaskTrack')?.builtinKind,
          AiBuiltinToolKind.agentTaskTrack,
        );
        expect(
          catalog.find('AgentClusterStatus')?.builtinKind,
          AiBuiltinToolKind.agentClusterStatus,
        );
        expect(catalog.find('AgentTaskPublish'), isNull);
        expect(catalog.find('AgentAuditRecord'), isNull);
        expect(catalog.find('AgentActivityLog'), isNull);
        expect(catalog.find('AgentAuditReport'), isNull);
        expect(catalog.find('AgentApprovalRequest'), isNull);
        expect(catalog.find('AgentKpiUpsert'), isNull);
        expect(catalog.find('AgentResourceUpdate'), isNull);
        expect(catalog.find('AgentClusterConfigure'), isNull);
        expect(catalog.find('AgentTaskList'), isNull);
        expect(catalog.find('AgentTaskComplete'), isNull);
      },
    );

    test(
      'does not expose agent tools when an enabled agent only binds non-agent builtins',
      () async {
        await controller.saveAgent(
          _agent(enabled: true, builtinToolNames: const <String>['bash']),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );

        expect(catalog.find('AgentList'), isNull);
        expect(catalog.find('AgentTaskPublish'), isNull);
        expect(catalog.find('AgentAuditRecord'), isNull);
        expect(catalog.find('AgentActivityLog'), isNull);
        expect(catalog.find('AgentAuditReport'), isNull);
        expect(catalog.find('AgentApprovalRequest'), isNull);
        expect(catalog.find('AgentKpiUpsert'), isNull);
        expect(catalog.find('AgentResourceUpdate'), isNull);
        expect(catalog.find('AgentClusterConfigure'), isNull);
        expect(catalog.find('AgentClusterStatus'), isNull);
        expect(catalog.find('AgentTaskList'), isNull);
        expect(catalog.find('AgentTaskResult'), isNull);
        expect(catalog.find('Bash'), isNotNull);
      },
    );

    test(
      'matches agent builtin bindings by enum and display-name aliases',
      () async {
        await controller.saveAgent(
          _agent(
            enabled: true,
            builtinToolNames: const <String>[
              'agentTaskResult',
              'Agent Approval Request',
            ],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );

        expect(
          catalog.find('AgentTaskResult')?.builtinKind,
          AiBuiltinToolKind.agentTaskResult,
        );
        expect(
          catalog.find('AgentApprovalRequest')?.builtinKind,
          AiBuiltinToolKind.agentApprovalRequest,
        );
        expect(catalog.find('AgentTaskPublish'), isNull);
        expect(catalog.find('AgentClusterStatus'), isNull);
      },
    );

    test('agent list exposes normalized bound agent tool groups', () async {
      await controller.saveAgent(
        _agent(
          enabled: true,
          builtinToolNames: const <String>[
            'AgentList',
            'agentTaskResult',
            'Agent Approval Request',
            'Bash',
          ],
        ),
      );

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await _executeAgentList(runtime, catalog);

      expect(result.status, BashToolExecutionStatus.success);
      final payload = jsonDecode(result.resultText) as Map<String, Object?>;
      final agents = payload['agents'] as List<Object?>;
      final agent = agents.single as Map<String, Object?>;
      final agentTools = agent['agent_tools'] as Map<String, Object?>;
      final groups = agentTools['groups'] as Map<String, Object?>;

      expect(agentTools['binding_mode'], 'explicit');
      expect(agentTools['tools'], <Object?>[
        'AgentList',
        'AgentTaskResult',
        'AgentApprovalRequest',
      ]);
      expect(groups['discovery'], <Object?>['AgentList']);
      expect(groups['task_lifecycle'], <Object?>['AgentTaskResult']);
      expect(groups['governance'], <Object?>['AgentApprovalRequest']);
      expect(agentTools['mutation_tools'], <Object?>['AgentApprovalRequest']);
      expect(agentTools['count'], 3);
    });

    test(
      'rejects executing a catalog-exposed agent tool against an unbound target agent',
      () async {
        await controller.saveAgent(
          _agent(
            id: 'agent-publisher',
            name: 'Publisher Agent',
            enabled: true,
            builtinToolNames: const <String>['AgentTaskPublish'],
          ),
        );
        await controller.saveAgent(
          _agent(
            id: 'agent-reader',
            name: 'Reader Agent',
            enabled: true,
            builtinToolNames: const <String>['AgentList'],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        expect(catalog.find('AgentTaskPublish'), isNotNull);

        final result = await runtime.execute(
          sessionId: 'session-agent-binding',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-publish-unbound',
            name: 'AgentTaskPublish',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-reader',
              'title': 'Should not be published',
              'content': 'This target agent did not bind AgentTaskPublish.',
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(result.resultText, contains('has not bound AgentTaskPublish'));
        expect(controller.agentById('agent-reader')!.tasks, isEmpty);
        expect(controller.agentById('agent-publisher')!.tasks, isEmpty);
      },
    );

    test(
      'include disabled lookup still requires the target tool binding',
      () async {
        await controller.saveAgent(
          _agent(
            id: 'agent-detailer',
            name: 'Detail Agent',
            enabled: true,
            builtinToolNames: const <String>['AgentDetail'],
          ),
        );
        await controller.saveAgent(
          _agent(
            id: 'agent-list-only',
            name: 'List Only Agent',
            enabled: true,
            builtinToolNames: const <String>['AgentList'],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        expect(catalog.find('AgentDetail'), isNotNull);

        final result = await runtime.execute(
          sessionId: 'session-agent-include-disabled',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-detail-unbound',
            name: 'AgentDetail',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-list-only',
              'include_disabled': true,
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(result.resultText, contains('has not bound AgentDetail'));
      },
    );

    test('filters task allowed tools by the target agent bindings', () async {
      await controller.saveAgent(
        _agent(
          enabled: true,
          builtinToolNames: const <String>[
            'AgentTaskPublish',
            'AgentTaskProgress',
            'AgentTaskCancel',
          ],
        ),
      );

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final publish = await runtime.execute(
        sessionId: 'session-agent-allowed-tools',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-publish',
          name: 'AgentTaskPublish',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'title': 'Check task state tools',
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(publish.status, BashToolExecutionStatus.success);
      final publishPayload =
          jsonDecode(publish.resultText) as Map<String, Object?>;
      final publishedTask = publishPayload['task'] as Map<String, Object?>;
      final publishedState = publishedTask['state'] as Map<String, Object?>;
      final publishedHandoff = publishedTask['handoff'] as Map<String, Object?>;
      expect(publishedTask['allowed_tools'], <Object?>['AgentTaskCancel']);
      expect(publishedState['allowed_tools'], <Object?>['AgentTaskCancel']);
      expect(publishedHandoff['allowed_tools'], <Object?>['AgentTaskCancel']);

      final progress = await runtime.execute(
        sessionId: 'session-agent-allowed-tools',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-progress',
          name: 'AgentTaskProgress',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'task_id': controller.agentById('agent-1')!.tasks.single.id,
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(progress.status, BashToolExecutionStatus.success);
      final progressPayload =
          jsonDecode(progress.resultText) as Map<String, Object?>;
      final progressState = progressPayload['state'] as Map<String, Object?>;
      expect(progressPayload['allowed_tools'], <Object?>['AgentTaskCancel']);
      expect(progressState['allowed_tools'], <Object?>['AgentTaskCancel']);
    });

    test('approval request tool records pending approval and audit', () async {
      await controller.saveAgent(_agent(enabled: true));

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await runtime.execute(
        sessionId: 'session-approval',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-approval',
          name: 'AgentApprovalRequest',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'title': 'Access production logs',
            'reason': 'Need mentor approval before reading sensitive logs.',
            'requested_action': 'read /var/log/prod/app.log',
            'labels': <String>['ops', 'prod'],
            'extra': <String, Object?>{'risk': 'sensitive_data'},
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(result.status, BashToolExecutionStatus.success);
      final payload = jsonDecode(result.resultText) as Map<String, Object?>;
      final approval = payload['approval'] as Map<String, Object?>;
      final approvalExtra = approval['extra'] as Map<String, Object?>;
      final agentSummary = payload['agent'] as Map<String, Object?>;
      final storedAgent = controller.agentById('agent-1')!;
      final storedApproval = storedAgent.approvals.single;

      expect(approval['id'], storedApproval.id);
      expect(approval['status'], 'pending');
      expect(approval['requested_action'], 'read /var/log/prod/app.log');
      expect(approvalExtra['requested_by_session_id'], 'session-approval');
      expect(approvalExtra['risk'], 'sensitive_data');
      expect(approvalExtra['labels'], <String>['ops', 'prod']);
      expect(payload['pending_approvals'], 1);
      expect(agentSummary['id'], 'agent-1');
      expect(storedApproval.title, 'Access production logs');
      expect(storedApproval.reason, contains('mentor approval'));
      expect(storedAgent.activities.first.kind, 'approval_requested');
      expect(storedAgent.auditEvents.first.kind, 'approval_requested');
      expect(storedAgent.auditEvents.first.toolName, 'AgentApprovalRequest');
      expect(
        storedAgent.auditEvents.first.metadata['approval_id'],
        storedApproval.id,
      );
    });

    test('kpi upsert tool creates and updates by matching name', () async {
      await controller.saveAgent(_agent(enabled: true));

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final created = await runtime.execute(
        sessionId: 'session-kpi',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-kpi-create',
          name: 'AgentKpiUpsert',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'name': 'Weekly incident report',
            'target': 'Publish one reviewed report every Friday.',
            'plan': 'Collect incidents, summarize impact, and send draft.',
            'status': 'tracking',
            'progress': 0.25,
            'labels': <String>['ops', 'report'],
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(created.status, BashToolExecutionStatus.success);
      final createdPayload =
          jsonDecode(created.resultText) as Map<String, Object?>;
      final createdKpi = createdPayload['kpi'] as Map<String, Object?>;
      final createdExtra = createdKpi['extra'] as Map<String, Object?>;
      final kpiId = '${createdKpi['id']}';
      expect(kpiId, isNotEmpty);
      expect(createdKpi['progress'], 0.25);
      expect(createdExtra['updated_by_session_id'], 'session-kpi');
      expect(createdExtra['labels'], <String>['ops', 'report']);
      expect(controller.agentById('agent-1')!.kpis, hasLength(1));
      expect(
        controller.agentById('agent-1')!.auditEvents.first.toolName,
        'AgentKpiUpsert',
      );

      final updated = await runtime.execute(
        sessionId: 'session-kpi',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-kpi-update',
          name: 'AgentKpiUpsert',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'name': 'Weekly incident report',
            'status': 'done',
            'progress': 1,
            'extra': <String, Object?>{'evidence': 'report.md'},
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(updated.status, BashToolExecutionStatus.success);
      final agent = controller.agentById('agent-1')!;
      final saved = agent.kpis.single;
      expect(saved.id, kpiId);
      expect(saved.status, 'done');
      expect(saved.progress, 1);
      expect(saved.target, 'Publish one reviewed report every Friday.');
      expect(saved.extra['evidence'], 'report.md');
      expect(agent.activities.first.kind, 'kpi_updated');
      expect(agent.auditEvents.first.kind, 'kpi_updated');
      expect(agent.auditEvents.first.toolName, 'AgentKpiUpsert');
    });

    test(
      'resource update tool preserves omitted metrics and records audit',
      () async {
        await controller.saveAgent(
          _agent(enabled: true).copyWith(
            resourceUsage: const AgentResourceUsage(
              cpuPercent: 0.2,
              memoryBytes: 2048,
              diskBytes: 4096,
              persistedBytes: 1024,
              tokenBudget: 1000,
              tokenUsed: 200,
              openHandles: 2,
              extra: <String, Object?>{'source': 'initial'},
            ),
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final result = await runtime.execute(
          sessionId: 'session-resource',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-resource',
            name: 'AgentResourceUpdate',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-1',
              'cpu_percent': 1.4,
              'disk_bytes': -1,
              'token_used': 640,
              'open_handles': 5,
              'extra': <String, Object?>{'artifact': 'weekly.md'},
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        expect(result.status, BashToolExecutionStatus.success);
        final payload = jsonDecode(result.resultText) as Map<String, Object?>;
        final usage = payload['resource_usage'] as Map<String, Object?>;
        final summary = payload['resource_summary'] as Map<String, Object?>;
        final agent = controller.agentById('agent-1')!;
        final stored = agent.resourceUsage;

        expect(stored.cpuPercent, 1);
        expect(stored.memoryBytes, 2048);
        expect(stored.diskBytes, 0);
        expect(stored.persistedBytes, 1024);
        expect(stored.tokenBudget, 1000);
        expect(stored.tokenUsed, 640);
        expect(stored.openHandles, 5);
        expect(stored.extra['source'], 'initial');
        expect(stored.extra['artifact'], 'weekly.md');
        expect(stored.extra['updated_by_session_id'], 'session-resource');
        expect(usage['memory_bytes'], 2048);
        expect(summary['token_remaining'], 360);
        expect(summary['token_usage_ratio'], 0.64);
        expect(summary['persisted_remaining_bytes'], isNull);
        expect(summary['persisted_disk_ratio'], 0);
        expect(summary['open_handle_limit'], 128);
        expect(summary['open_handle_ratio'], closeTo(5 / 128, 0.0001));
        expect(summary['max_pressure'], 1);
        expect(summary['pressure_level'], 'high');
        expect(summary['has_pressure'], isTrue);
        expect(agent.activities.first.kind, 'resource_updated');
        expect(agent.auditEvents.first.kind, 'resource_updated');
        expect(agent.auditEvents.first.toolName, 'AgentResourceUpdate');
        expect(agent.auditEvents.first.metadata['token_used'], 640);
      },
    );

    test('audit record tool stores capability metrics and metadata', () async {
      await controller.saveAgent(_agent(enabled: true));

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await runtime.execute(
        sessionId: 'session-audit',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-audit',
          name: 'AgentAuditRecord',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'kind': 'skill_call',
            'summary': 'skill_call: reconcile invoices',
            'tool_name': 'finops-duizhang-expert',
            'token_usage': 321,
            'request_count': 2,
            'task_id': 'task-123',
            'worker_id': 'worker-1',
            'metadata': <String, Object?>{'phase': 'collect'},
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(result.status, BashToolExecutionStatus.success);
      final payload = jsonDecode(result.resultText) as Map<String, Object?>;
      final event = payload['audit_event'] as Map<String, Object?>;
      final metadata = event['metadata'] as Map<String, Object?>;
      final summary = payload['audit_summary'] as Map<String, Object?>;
      final toolCounts = summary['tool_counts'] as Map<String, Object?>;
      final agent = controller.agentById('agent-1')!;

      expect(event['kind'], 'skill_call');
      expect(event['summary'], 'skill_call: reconcile invoices');
      expect(event['tool_name'], 'finops-duizhang-expert');
      expect(event['token_usage'], 321);
      expect(event['request_count'], 2);
      expect(metadata['phase'], 'collect');
      expect(metadata['task_id'], 'task-123');
      expect(metadata['worker_id'], 'worker-1');
      expect(metadata['recorded_by'], 'AgentAuditRecord');
      expect(metadata['recorded_by_session_id'], 'session-audit');
      expect(summary['event_count'], 1);
      expect(summary['token_usage'], 321);
      expect(toolCounts['finops-duizhang-expert'], 1);
      expect(agent.auditEvents.first.kind, 'skill_call');
      expect(agent.activities.first.kind, 'audit_recorded');
    });

    test('activity log tool filters history and audit events', () async {
      await controller.saveAgent(
        _agent(enabled: true).copyWith(
          activities: <AgentActivityEvent>[
            AgentActivityEvent(
              id: 'act-1',
              kind: 'task_assigned',
              title: 'task_assigned',
              content: 'Collect evidence',
              createdAt: DateTime.utc(2026, 7, 4, 1),
              metadata: const <String, Object?>{
                'task_id': 'task-123',
                'worker_id': 'worker-1',
                'tool_name': 'SkillRunner',
              },
            ),
            AgentActivityEvent(
              id: 'act-2',
              kind: 'resource_updated',
              title: 'resource_updated',
              createdAt: DateTime.utc(2026, 7, 4),
              metadata: const <String, Object?>{'task_id': 'other-task'},
            ),
          ],
          auditEvents: <AgentAuditEvent>[
            AgentAuditEvent(
              id: 'audit-1',
              kind: 'skill_call',
              summary: 'skill_call: collect evidence',
              toolName: 'SkillRunner',
              tokenUsage: 128,
              requestCount: 2,
              createdAt: DateTime.utc(2026, 7, 4, 1),
              metadata: const <String, Object?>{
                'task_id': 'task-123',
                'worker_id': 'worker-1',
              },
            ),
            AgentAuditEvent(
              id: 'audit-2',
              kind: 'mcp_call',
              summary: 'mcp_call: unmatched',
              toolName: 'McpTool',
              tokenUsage: 32,
              requestCount: 1,
              createdAt: DateTime.utc(2026, 7, 4),
              metadata: const <String, Object?>{'task_id': 'other-task'},
            ),
          ],
        ),
      );

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await runtime.execute(
        sessionId: 'session-activity',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-activity',
          name: 'AgentActivityLog',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'message_type': 'task',
            'task_id': 'task-123',
            'worker_id': 'worker-1',
            'tool_name': 'SkillRunner',
            'limit': 5,
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(result.status, BashToolExecutionStatus.success);
      final payload = jsonDecode(result.resultText) as Map<String, Object?>;
      final activities = payload['activities'] as List<Object?>;
      final auditEvents = payload['audit_events'] as List<Object?>;
      final activity = activities.single as Map<String, Object?>;
      final audit = auditEvents.single as Map<String, Object?>;
      final filters = payload['filters'] as Map<String, Object?>;
      final activitySummary =
          payload['activity_summary'] as Map<String, Object?>;
      final messageTypeCounts =
          activitySummary['message_type_counts'] as Map<String, Object?>;
      final auditSummary = payload['audit_summary'] as Map<String, Object?>;
      final toolCounts = auditSummary['tool_counts'] as Map<String, Object?>;

      expect(filters['task_id'], 'task-123');
      expect(filters['message_type'], 'task');
      expect(activity['id'], 'act-1');
      expect(activity['kind'], 'task_assigned');
      expect(activity['message_type'], 'task');
      expect(audit['id'], 'audit-1');
      expect(audit['tool_name'], 'SkillRunner');
      expect(activitySummary['event_count'], 1);
      expect(messageTypeCounts['task'], 1);
      expect(auditSummary['event_count'], 1);
      expect(auditSummary['request_count'], 2);
      expect(auditSummary['token_usage'], 128);
      expect(toolCounts['SkillRunner'], 1);
      expect(result.metadata['action'], 'activity_log');
      expect(result.metadata['activity_count'], 1);
      expect(result.metadata['audit_count'], 1);
    });

    test(
      'audit report tool summarizes operations and filtered evidence',
      () async {
        await controller.saveAgent(
          _agent(enabled: true).copyWith(
            scaleSettings: const AgentScaleSettings(
              minWorkers: 0,
              maxWorkers: 2,
            ),
            workers: const <AgentWorker>[
              AgentWorker(
                id: 'worker-1',
                name: 'Worker 1',
                status: AgentWorkerStatus.busy,
                currentTaskId: 'task-1',
                busyScore: 0.75,
                executedTaskCount: 3,
                priority: 4,
              ),
              AgentWorker(id: 'worker-2', name: 'Worker 2'),
            ],
            tasks: <AgentTask>[
              AgentTask(
                id: 'task-1',
                title: 'Collect cloud billing evidence',
                status: AgentTaskStatus.running,
                progress: 0.5,
                createdAt: DateTime.utc(2026, 7, 4, 1),
                extra: const <String, Object?>{
                  'assigned_worker_id': 'worker-1',
                  'labels': <String>['finance'],
                },
              ),
              AgentTask(
                id: 'task-2',
                title: 'Publish weekly report',
                status: AgentTaskStatus.completed,
                progress: 1,
                createdAt: DateTime.utc(2026, 7, 4),
                extra: const <String, Object?>{
                  'assigned_worker_id': 'worker-2',
                },
              ),
            ],
            kpis: const <AgentKpiItem>[
              AgentKpiItem(id: 'kpi-1', name: 'Weekly report', progress: 0.5),
              AgentKpiItem(
                id: 'kpi-2',
                name: 'Incident SLA',
                status: 'at_risk',
                progress: 0.25,
              ),
            ],
            approvals: <AgentApprovalRequest>[
              AgentApprovalRequest(
                id: 'approval-1',
                title: 'Read billing export',
                createdAt: DateTime.utc(2026, 7, 4),
              ),
              AgentApprovalRequest(
                id: 'approval-2',
                title: 'Use cached report',
                status: AgentApprovalStatus.approved,
                createdAt: DateTime.utc(2026, 7, 3),
              ),
            ],
            resourceUsage: const AgentResourceUsage(
              cpuPercent: 0.4,
              memoryBytes: 1024,
              diskBytes: 2048,
              persistedBytes: 512,
              tokenBudget: 1000,
              tokenUsed: 250,
              openHandles: 2,
            ),
            auditEvents: <AgentAuditEvent>[
              AgentAuditEvent(
                id: 'audit-1',
                kind: 'skill_call',
                summary: 'skill_call: collect billing evidence',
                toolName: 'SkillRunner',
                tokenUsage: 100,
                requestCount: 2,
                createdAt: DateTime.utc(2026, 7, 4, 1),
                metadata: const <String, Object?>{
                  'task_id': 'task-1',
                  'worker_id': 'worker-1',
                },
              ),
              AgentAuditEvent(
                id: 'audit-2',
                kind: 'mcp_call',
                summary: 'mcp_call: unrelated',
                toolName: 'McpTool',
                tokenUsage: 50,
                requestCount: 1,
                createdAt: DateTime.utc(2026, 7, 4),
                metadata: const <String, Object?>{
                  'task_id': 'task-2',
                  'worker_id': 'worker-2',
                },
              ),
            ],
            activities: <AgentActivityEvent>[
              AgentActivityEvent(
                id: 'act-1',
                kind: 'task_assigned',
                title: 'task_assigned',
                content: 'Collect cloud billing evidence',
                createdAt: DateTime.utc(2026, 7, 4, 1),
                metadata: const <String, Object?>{
                  'task_id': 'task-1',
                  'worker_id': 'worker-1',
                  'tool_name': 'SkillRunner',
                },
              ),
            ],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final result = await runtime.execute(
          sessionId: 'session-report',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-report',
            name: 'AgentAuditReport',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-1',
              'worker_id': 'worker-1',
              'tool_name': 'SkillRunner',
              'limit': 5,
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        expect(result.status, BashToolExecutionStatus.success);
        final payload = jsonDecode(result.resultText) as Map<String, Object?>;
        final filters = payload['filters'] as Map<String, Object?>;
        final taskMetrics = payload['task_metrics'] as Map<String, Object?>;
        final taskStatusCounts =
            taskMetrics['by_status'] as Map<String, Object?>;
        final worker = payload['worker'] as Map<String, Object?>;
        final capacity = payload['worker_capacity'] as Map<String, Object?>;
        final kpiSummary = payload['kpi_summary'] as Map<String, Object?>;
        final kpiStatusCounts = kpiSummary['by_status'] as Map<String, Object?>;
        final approvalSummary =
            payload['approval_summary'] as Map<String, Object?>;
        final resourceUsage = payload['resource_usage'] as Map<String, Object?>;
        final auditSummary = payload['audit_summary'] as Map<String, Object?>;
        final toolCounts = auditSummary['tool_counts'] as Map<String, Object?>;
        final capabilityUsage =
            payload['capability_usage'] as Map<String, Object?>;
        final capabilityByType =
            capabilityUsage['by_type'] as Map<String, Object?>;
        final topCapabilities =
            capabilityUsage['top_capabilities'] as List<Object?>;
        final workerExecution =
            payload['worker_execution'] as Map<String, Object?>;
        final workerExecutionRows = workerExecution['workers'] as List<Object?>;
        final loadSummary = payload['load_summary'] as Map<String, Object?>;
        final resourcePressure =
            loadSummary['resource_pressure'] as Map<String, Object?>;
        final recentAuditEvents =
            payload['recent_audit_events'] as List<Object?>;
        final pendingApprovals = payload['pending_approvals'] as List<Object?>;
        final tasks = payload['tasks'] as List<Object?>;

        expect(filters['worker_id'], 'worker-1');
        expect(filters['tool_name'], 'SkillRunner');
        expect(taskMetrics['total'], 1);
        expect(taskStatusCounts['running'], 1);
        expect(worker['id'], 'worker-1');
        expect(worker['status'], 'busy');
        expect(capacity['total'], 2);
        expect(kpiSummary['total'], 2);
        expect(kpiStatusCounts['at_risk'], 1);
        expect(kpiSummary['average_progress'], 0.375);
        expect(approvalSummary['pending'], 1);
        expect(pendingApprovals.single, isA<Map<String, Object?>>());
        expect(resourceUsage['token_remaining'], 750);
        expect(resourceUsage['token_usage_ratio'], 0.25);
        expect(resourceUsage['persisted_remaining_bytes'], 1536);
        expect(resourceUsage['persisted_disk_ratio'], 0.25);
        expect(resourceUsage['open_handle_limit'], 128);
        expect(resourceUsage['open_handle_ratio'], closeTo(2 / 128, 0.0001));
        expect(resourceUsage['pressure_level'], 'normal');
        expect(auditSummary['event_count'], 1);
        expect(auditSummary['request_count'], 2);
        expect(auditSummary['token_usage'], 100);
        expect(toolCounts['SkillRunner'], 1);
        expect(capabilityUsage['event_count'], 1);
        expect(capabilityUsage['request_count'], 2);
        expect(capabilityUsage['token_usage'], 100);
        expect(capabilityByType['skill'], 1);
        expect(topCapabilities.single, containsPair('name', 'SkillRunner'));
        expect(topCapabilities.single, containsPair('type', 'skill'));
        expect(workerExecution['total_workers'], 2);
        expect(workerExecution['observed_workers'], 2);
        expect(workerExecution['task_assignment_count'], 1);
        expect(workerExecution['unassigned_task_count'], 0);
        final workerExecutionRow =
            workerExecutionRows.first as Map<String, Object?>;
        expect(workerExecutionRow['id'], 'worker-1');
        expect(workerExecutionRow['status'], 'busy');
        final workerTaskMetrics =
            workerExecutionRow['task_metrics'] as Map<String, Object?>;
        expect(workerTaskMetrics['total'], 1);
        final workerAuditSummary =
            workerExecutionRow['audit_summary'] as Map<String, Object?>;
        expect(workerAuditSummary['token_usage'], 100);
        expect(resourcePressure['has_pressure'], isFalse);
        expect(recentAuditEvents.single, isA<Map<String, Object?>>());
        expect((tasks.single as Map<String, Object?>)['id'], 'task-1');
        expect(result.metadata['action'], 'audit_report');
        expect(result.metadata['audit_count'], 1);
      },
    );

    test(
      'task list tool filters the task desk by status worker and label',
      () async {
        await controller.saveAgent(
          _agent(enabled: true).copyWith(
            scaleSettings: const AgentScaleSettings(
              minWorkers: 0,
              maxWorkers: 2,
            ),
            workers: <AgentWorker>[
              const AgentWorker(
                id: 'worker-1',
                name: 'Worker 1',
                status: AgentWorkerStatus.busy,
                currentTaskId: 'task-1',
                busyScore: 0.8,
                executedTaskCount: 2,
              ),
              const AgentWorker(id: 'worker-2', name: 'Worker 2'),
            ],
            tasks: <AgentTask>[
              AgentTask(
                id: 'task-1',
                title: 'Prepare weekly ops report',
                status: AgentTaskStatus.running,
                progress: 0.4,
                createdAt: DateTime.utc(2026, 7, 4, 1),
                extra: const <String, Object?>{
                  'assigned_worker_id': 'worker-1',
                  'labels': <String>['ops', 'weekly'],
                },
              ),
              AgentTask(
                id: 'task-2',
                title: 'Archive finance result',
                status: AgentTaskStatus.completed,
                progress: 1,
                createdAt: DateTime.utc(2026, 7, 4),
                extra: const <String, Object?>{
                  'assigned_worker_id': 'worker-2',
                  'labels': <String>['finance'],
                },
              ),
            ],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final result = await runtime.execute(
          sessionId: 'session-task-list',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-task-list',
            name: 'AgentTaskList',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-1',
              'status': 'running',
              'worker_id': 'worker-1',
              'label': 'ops',
              'limit': 10,
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        expect(result.status, BashToolExecutionStatus.success);
        final payload = jsonDecode(result.resultText) as Map<String, Object?>;
        final tasks = payload['tasks'] as List<Object?>;
        final task = tasks.single as Map<String, Object?>;
        final filters = payload['filters'] as Map<String, Object?>;
        final metrics = payload['task_metrics'] as Map<String, Object?>;
        final byStatus = metrics['by_status'] as Map<String, Object?>;
        final capacity = payload['worker_capacity'] as Map<String, Object?>;
        final capacityByStatus = capacity['by_status'] as Map<String, Object?>;

        expect(filters['status'], 'running');
        expect(filters['worker_id'], 'worker-1');
        expect(filters['labels'], <Object?>['ops']);
        expect(task['id'], 'task-1');
        expect(task['title'], 'Prepare weekly ops report');
        expect(task['status'], 'running');
        expect(metrics['total'], 2);
        expect(byStatus['running'], 1);
        expect(byStatus['completed'], 1);
        expect(capacity['total'], 2);
        expect(capacity['busy'], 1);
        expect(capacityByStatus['idle'], 1);
        expect(result.metadata['action'], 'list_tasks');
        expect(result.metadata['task_count'], 1);
      },
    );

    test('cluster configure tool updates scale settings and workers', () async {
      await controller.saveAgent(_agent(enabled: true));

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await runtime.execute(
        sessionId: 'session-cluster',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-cluster',
          name: 'AgentClusterConfigure',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'min_workers': 2,
            'max_workers': 3,
            'scale_out_threshold': 0.6,
            'scale_in_threshold': 0.2,
            'scheduler_policy': 'round-robin',
            'worker_removal_policy': 'newest_first',
            'retry_policy': 'none',
            'max_retries': 0,
            'tags': <String>['ops', 'ops', 'urgent'],
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(result.status, BashToolExecutionStatus.success);
      final payload = jsonDecode(result.resultText) as Map<String, Object?>;
      final settings = payload['scale_settings'] as Map<String, Object?>;
      final workers = payload['workers'] as List<Object?>;
      final agent = controller.agentById('agent-1')!;

      expect(settings['min_workers'], 2);
      expect(settings['max_workers'], 3);
      expect(settings['scheduler_policy'], 'round_robin');
      expect(settings['retry_policy'], 'none');
      expect(settings['tags'], <String>['ops', 'urgent']);
      expect(workers, hasLength(2));
      expect(agent.scaleSettings.workerRemovalPolicy, 'newest_first');
      expect(agent.workers, hasLength(2));
      expect(
        agent.workers.every((worker) => worker.labels.length == 2),
        isTrue,
      );
      expect(agent.activities.first.kind, 'cluster_updated');
      expect(agent.auditEvents.first.kind, 'cluster_updated');
      expect(agent.auditEvents.first.toolName, 'AgentClusterConfigure');
    });

    test(
      'cluster status tool reports worker capacity without mutation',
      () async {
        await controller.saveAgent(_agent(enabled: true));
        await controller.saveScaleSettings(
          'agent-1',
          const AgentScaleSettings(maxWorkers: 2),
        );
        final firstTask = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Prepare first report',
        );
        final secondTask = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Prepare second report',
        );
        final thirdTask = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Prepare queued report',
        );
        expect(firstTask, isNotNull);
        expect(secondTask, isNotNull);
        expect(thirdTask, isNotNull);

        final beforeAgent = controller.agentById('agent-1')!;
        final beforeActivityCount = beforeAgent.activities.length;
        final beforeAuditCount = beforeAgent.auditEvents.length;
        final busyWorker = beforeAgent.workers.firstWhere(
          (worker) => worker.status == AgentWorkerStatus.busy,
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final result = await runtime.execute(
          sessionId: 'session-cluster-status',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-cluster-status',
            name: 'AgentClusterStatus',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-1',
              'limit': 10,
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        final afterAgent = controller.agentById('agent-1')!;
        final payload = jsonDecode(result.resultText) as Map<String, Object?>;
        final settings = payload['scale_settings'] as Map<String, Object?>;
        final capacity = payload['worker_capacity'] as Map<String, Object?>;
        final pressure = payload['queue_pressure'] as Map<String, Object?>;
        final workers = payload['workers'] as List<Object?>;
        final firstWorker = workers.first as Map<String, Object?>;
        final workerTask = firstWorker['current_task'] as Map<String, Object?>;
        final auditSummary =
            payload['cluster_audit_summary'] as Map<String, Object?>;
        final auditEvents =
            payload['recent_cluster_audit_events'] as List<Object?>;
        final tasks = payload['tasks'] as List<Object?>;

        expect(result.status, BashToolExecutionStatus.success);
        expect(settings['min_workers'], 1);
        expect(settings['max_workers'], 2);
        expect(capacity['total'], 2);
        expect(capacity['busy'], 2);
        expect(capacity['idle'], 0);
        expect(pressure['ready_tasks'], 1);
        expect(pressure['queued_tasks'], 1);
        expect(pressure['running_tasks'], 2);
        expect(pressure['workers_saturated'], isTrue);
        expect(pressure['can_scale_out'], isFalse);
        expect(workers, hasLength(2));
        expect(firstWorker['status'], 'busy');
        expect(firstWorker['executed_task_count'], 0);
        expect(firstWorker['busy_score'], 1);
        expect(workerTask['status'], 'running');
        expect(tasks, hasLength(3));
        expect(auditSummary['event_count'], greaterThanOrEqualTo(3));
        expect(auditEvents, isNotEmpty);
        expect(result.metadata['action'], 'cluster_status');
        expect(result.metadata['worker_count'], 2);
        expect(afterAgent.activities, hasLength(beforeActivityCount));
        expect(afterAgent.auditEvents, hasLength(beforeAuditCount));
        expect(
          afterAgent.workers.any((worker) => worker.id == busyWorker.id),
          isTrue,
        );
      },
    );

    test('detail tool exposes structured workspace scope paths', () async {
      await controller.saveAgent(
        _agent(enabled: true).copyWith(
          executionMode: AgentExecutionMode.fullAccess,
          skillNames: const <String>['ops-triage'],
          mcpServerNames: const <String>['ops-mcp'],
          builtinToolNames: const <String>[
            'AgentDetail',
            'AgentTaskPublish',
            'Bash',
          ],
          cronIds: const <String>['daily-report'],
          hookIds: const <String>['approval-hook'],
          workspacePath: '/repo',
          workspaceScope: '/legacy/ignored',
          workspaceScopePaths: const <String>[
            '/repo/app',
            '/repo/docs',
            '/repo/app',
          ],
          archive: 'Owns weekly operations reporting.',
          welcomeMessage: 'Ready to coordinate ops work.',
          persona: 'Calm operations lead.',
          responsibilityBoundary: 'Operations reporting and evidence only.',
          metadata: const <String, Object?>{'owner': 'platform', 'tier': 2},
          kpis: const <AgentKpiItem>[
            AgentKpiItem(id: 'kpi-1', name: 'Weekly report', progress: 0.5),
          ],
          approvals: const <AgentApprovalRequest>[
            AgentApprovalRequest(id: 'approval-1', title: 'Read audit log'),
          ],
          workers: const <AgentWorker>[
            AgentWorker(id: 'worker-1', name: 'Worker 1'),
          ],
          tasks: const <AgentTask>[
            AgentTask(
              id: 'task-1',
              title: 'Prepare weekly report',
              status: AgentTaskStatus.ready,
              extra: <String, Object?>{
                'labels': <String>['ops'],
              },
            ),
          ],
          resourceUsage: const AgentResourceUsage(
            cpuPercent: 0.25,
            memoryBytes: 1024,
            tokenBudget: 1000,
            tokenUsed: 250,
          ),
        ),
      );

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await runtime.execute(
        sessionId: 'session-1',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-1',
          name: 'AgentDetail',
          arguments: jsonEncode(<String, Object?>{'agent_id': 'agent-1'}),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(result.status, BashToolExecutionStatus.success);
      final payload = jsonDecode(result.resultText) as Map<String, Object?>;
      final agent = payload['agent'] as Map<String, Object?>;
      expect(agent['archive'], 'Owns weekly operations reporting.');
      expect(agent['welcome_message'], 'Ready to coordinate ops work.');
      expect(agent['persona'], 'Calm operations lead.');
      expect(
        agent['responsibility_boundary'],
        'Operations reporting and evidence only.',
      );
      expect(agent['metadata'], containsPair('owner', 'platform'));
      expect(agent['metadata'], containsPair('tier', 2));
      expect(agent['workspace_path'], '/repo');
      expect(agent['workspace_scope'], '/repo/app\n/repo/docs');
      expect(agent['workspace_scope_paths'], <Object?>[
        '/repo/app',
        '/repo/docs',
      ]);
      final capabilities = agent['capabilities'] as Map<String, Object?>;
      final capabilitySummary = capabilities['summary'] as Map<String, Object?>;
      expect(capabilitySummary['skills'], 1);
      expect(capabilitySummary['mcp_servers'], 1);
      expect(capabilitySummary['builtin_tools'], 3);
      expect(capabilitySummary['agent_coordination_tools'], 2);
      expect(capabilitySummary['automations'], 2);
      expect(capabilitySummary['has_external_actions'], isTrue);
      expect(capabilitySummary['has_self_learning_inputs'], isTrue);
      final workspacePolicy = agent['workspace_policy'] as Map<String, Object?>;
      expect(workspacePolicy['allowed_roots'], <Object?>[
        '/repo',
        '/repo/app',
        '/repo/docs',
      ]);
      expect(workspacePolicy['writes_limited_to_allowed_roots'], isTrue);
      expect(workspacePolicy['requires_confirmation_when_empty'], isFalse);
      final approvalPolicy = agent['approval_policy'] as Map<String, Object?>;
      expect(approvalPolicy['mode'], 'full_access');
      expect(approvalPolicy['routine_actions_auto_allowed'], isTrue);
      expect(
        approvalPolicy['approval_required_before_privileged_actions'],
        isFalse,
      );
      expect(
        approvalPolicy['approval_required_when'],
        contains('credential_or_secret_access'),
      );
      final operationalSummary =
          agent['operational_summary'] as Map<String, Object?>;
      final taskMetrics =
          operationalSummary['task_metrics'] as Map<String, Object?>;
      final workerCapacity =
          operationalSummary['worker_capacity'] as Map<String, Object?>;
      final queuePressure =
          operationalSummary['queue_pressure'] as Map<String, Object?>;
      final approvalSummary =
          operationalSummary['approval_summary'] as Map<String, Object?>;
      final kpiSummary =
          operationalSummary['kpi_summary'] as Map<String, Object?>;
      final resourceSummary =
          operationalSummary['resource_summary'] as Map<String, Object?>;
      expect(taskMetrics['total'], 1);
      expect(workerCapacity['idle'], 1);
      expect(queuePressure['ready_tasks'], 1);
      expect(approvalSummary['pending'], 1);
      expect(kpiSummary['total'], 1);
      expect(resourceSummary['token_remaining'], 750);
      expect(agent['task_metrics'], taskMetrics);
      expect(agent['worker_capacity'], workerCapacity);
      expect(agent['queue_pressure'], queuePressure);
      expect(agent['resource_summary'], resourceSummary);
    });

    test(
      'list tool exposes routing summaries for delegation decisions',
      () async {
        await controller.saveAgent(
          _agent(
            enabled: true,
            builtinToolNames: const <String>[
              'AgentList',
              'agentTaskResult',
              'Bash',
            ],
            routeFrontMatter: 'keywords: deploy, release',
            taskLabels: const <String>['release'],
          ).copyWith(
            skillNames: const <String>['release-checklist'],
            mcpServerNames: const <String>['deploy-mcp'],
            workspacePath: '/repo',
            workspaceScopePaths: const <String>['/repo/app'],
            tasks: const <AgentTask>[
              AgentTask(
                id: 'task-1',
                title: 'Deploy release',
                status: AgentTaskStatus.running,
              ),
            ],
            workers: const <AgentWorker>[
              AgentWorker(
                id: 'worker-1',
                name: 'Worker 1',
                status: AgentWorkerStatus.busy,
                currentTaskId: 'task-1',
              ),
            ],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final result = await runtime.execute(
          sessionId: 'session-1',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-1',
            name: 'AgentList',
            arguments: jsonEncode(<String, Object?>{}),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        expect(result.status, BashToolExecutionStatus.success);
        final payload = jsonDecode(result.resultText) as Map<String, Object?>;
        final agents = payload['agents'] as List<Object?>;
        final agent = agents.single as Map<String, Object?>;
        final capabilities = agent['capabilities'] as Map<String, Object?>;
        final capabilitySummary =
            capabilities['summary'] as Map<String, Object?>;
        final workspacePolicy =
            agent['workspace_policy'] as Map<String, Object?>;
        final routing = agent['routing'] as Map<String, Object?>;
        final operationalSummary =
            agent['operational_summary'] as Map<String, Object?>;
        final taskMetrics =
            operationalSummary['task_metrics'] as Map<String, Object?>;
        final taskStatusCounts =
            taskMetrics['by_status'] as Map<String, Object?>;
        final workerCapacity =
            operationalSummary['worker_capacity'] as Map<String, Object?>;

        expect(capabilitySummary['skills'], 1);
        expect(capabilitySummary['mcp_servers'], 1);
        expect(capabilitySummary['agent_coordination_tools'], 2);
        expect(capabilitySummary['has_external_actions'], isTrue);
        expect(workspacePolicy['allowed_roots'], <Object?>[
          '/repo',
          '/repo/app',
        ]);
        expect(routing['keywords'], contains('deploy'));
        expect(routing['keywords'], contains('release-checklist'));
        expect(taskStatusCounts['running'], 1);
        expect(workerCapacity['busy'], 1);
      },
    );

    test('publish tool routes to the best matching enabled agent', () async {
      await controller.saveAgent(
        _agent(
          id: 'finance-agent',
          name: 'Finance Agent',
          enabled: true,
          routeFrontMatter: '''
keywords:
  - invoice
  - reconciliation
domains: finance, cloud billing
''',
          taskLabels: const <String>['finance'],
        ),
      );
      await controller.saveAgent(
        _agent(
          id: 'release-agent',
          name: 'Release Agent',
          enabled: true,
          routeFrontMatter: 'keywords: deploy, rollback, release',
          taskLabels: const <String>['release'],
        ),
      );

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await runtime.execute(
        sessionId: 'session-1',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-1',
          name: 'AgentTaskPublish',
          arguments: jsonEncode(<String, Object?>{
            'title': 'Reconcile cloud invoice',
            'description':
                'Check the finance invoice and reconciliation evidence.',
            'labels': <String>['finance'],
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(result.status, BashToolExecutionStatus.success);
      final publishPayload =
          jsonDecode(result.resultText) as Map<String, Object?>;
      final publishedTask = publishPayload['task'] as Map<String, Object?>;
      final publishedWorker =
          publishedTask['assigned_worker'] as Map<String, Object?>;
      final publishedState = publishedTask['state'] as Map<String, Object?>;
      final financeAgent = controller.agentById('finance-agent')!;
      final releaseAgent = controller.agentById('release-agent')!;
      final assignedWorkerId =
          '${financeAgent.tasks.single.extra['assigned_worker_id']}';
      expect(financeAgent.tasks, hasLength(1));
      expect(releaseAgent.tasks, isEmpty);
      expect(financeAgent.tasks.single.title, 'Reconcile cloud invoice');
      expect(publishedWorker['id'], assignedWorkerId);
      expect(publishedWorker['status'], 'busy');
      expect(publishedState['terminal'], isFalse);
      expect(publishedState['needs_polling'], isTrue);
      expect(publishedState['next_action'], 'poll');
      expect(publishedTask['next_action'], 'poll');
      expect(publishedTask['result_available'], isFalse);
      expect(publishedTask['handoff'], isA<Map<String, Object?>>());
      expect(publishedTask['next_poll'], isA<Map<String, Object?>>());
      expect(
        publishedTask['allowed_tools'],
        containsAll(<String>[
          'AgentTaskPause',
          'AgentTaskCancel',
          'AgentTaskTerminate',
          'AgentTaskComplete',
        ]),
      );
      expect(publishedState['recommended_poll_ms'], isPositive);
      expect(financeAgent.tasks.single.extra['agent_route_score'], isPositive);
      expect(
        financeAgent.tasks.single.extra['agent_route_reason'],
        contains('invoice'),
      );

      final progress = await runtime.execute(
        sessionId: 'session-1',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-2',
          name: 'AgentTaskProgress',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'finance-agent',
            'task_id': financeAgent.tasks.single.id,
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );
      final progressPayload =
          jsonDecode(progress.resultText) as Map<String, Object?>;
      final progressWorker =
          progressPayload['assigned_worker'] as Map<String, Object?>;
      final progressState = progressPayload['state'] as Map<String, Object?>;
      expect(progress.status, BashToolExecutionStatus.success);
      expect(progressWorker['id'], assignedWorkerId);
      expect(progressWorker['current_task_id'], financeAgent.tasks.single.id);
      expect(progressState['needs_polling'], isTrue);
      expect(progressState['next_action'], 'poll');
      expect(progressPayload['next_action'], 'poll');
      expect(
        progressPayload['allowed_tools'],
        containsAll(<String>[
          'AgentTaskPause',
          'AgentTaskCancel',
          'AgentTaskTerminate',
          'AgentTaskComplete',
        ]),
      );

      final track = await runtime.execute(
        sessionId: 'session-1',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-3',
          name: 'AgentTaskTrack',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'finance-agent',
            'task_id': financeAgent.tasks.single.id,
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );
      final trackPayload = jsonDecode(track.resultText) as Map<String, Object?>;
      final trackState = trackPayload['state'] as Map<String, Object?>;
      final trackHandoff = trackPayload['handoff'] as Map<String, Object?>;
      final trackNextPoll = trackPayload['next_poll'] as Map<String, Object?>;
      final trackWorker =
          trackPayload['assigned_worker'] as Map<String, Object?>;
      expect(track.status, BashToolExecutionStatus.success);
      expect(trackPayload['result_available'], isFalse);
      expect(trackState['needs_polling'], isTrue);
      expect(trackState['next_action'], 'poll');
      expect(trackPayload['next_action'], 'poll');
      expect(
        trackPayload['allowed_tools'],
        containsAll(<String>[
          'AgentTaskPause',
          'AgentTaskCancel',
          'AgentTaskTerminate',
          'AgentTaskComplete',
        ]),
      );
      expect(trackHandoff['message'], 'result_not_ready_poll');
      expect(trackHandoff['next_action'], 'poll');
      expect(trackNextPoll['tool'], 'AgentTaskProgress');
      expect(trackNextPoll['result_tool'], 'AgentTaskResult');
      expect(trackWorker['id'], assignedWorkerId);
    });

    test(
      'routable write tools return candidate diagnostics when routing is ambiguous',
      () async {
        await controller.saveAgent(
          _agent(
            id: 'finance-a',
            name: 'Finance Alpha',
            enabled: true,
            routeFrontMatter: 'keywords: finance, reconciliation',
            taskLabels: const <String>['finance'],
          ),
        );
        await controller.saveAgent(
          _agent(
            id: 'finance-b',
            name: 'Finance Beta',
            enabled: true,
            routeFrontMatter: 'keywords: finance, reconciliation',
            taskLabels: const <String>['finance'],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );

        for (final call
            in <({String name, Map<String, Object?> args, String kind})>[
              (
                name: 'AgentTaskPublish',
                kind: 'task',
                args: <String, Object?>{
                  'title': 'Finance reconciliation',
                  'description': 'Prepare the finance reconciliation packet.',
                  'labels': <String>['finance'],
                },
              ),
              (
                name: 'AgentApprovalRequest',
                kind: 'approval',
                args: <String, Object?>{
                  'title': 'Finance reconciliation approval',
                  'reason': 'Need approval before publishing finance evidence.',
                  'labels': <String>['finance'],
                },
              ),
              (
                name: 'AgentKpiUpsert',
                kind: 'kpi',
                args: <String, Object?>{
                  'name': 'Finance reconciliation KPI',
                  'target': 'Complete weekly finance reconciliation.',
                  'labels': <String>['finance'],
                },
              ),
            ]) {
          final result = await runtime.execute(
            sessionId: 'session-route-diagnostics',
            catalog: catalog,
            toolCall: AiToolCall(
              id: 'call-${call.name}',
              name: call.name,
              arguments: jsonEncode(call.args),
            ),
            model: _model(),
            previouslyReadFiles: const <String>{},
            denyCommandRules: const <AiDenyCommandRule>[],
            requireWriteCommandConfirmation: false,
            confirmWriteCommand: (request) async =>
                BashCommandApprovalDecision.approved,
          );

          expect(result.status, BashToolExecutionStatus.invalidArguments);
          expect(result.metadata['action'], 'agent_routing_required');
          expect(result.metadata['context_kind'], call.kind);
          final payload = jsonDecode(result.resultText) as Map<String, Object?>;
          final diagnostics =
              payload['routing_diagnostics'] as Map<String, Object?>;
          final candidates = diagnostics['candidates'] as List<Object?>;
          final first = candidates[0] as Map<String, Object?>;
          final second = candidates[1] as Map<String, Object?>;

          expect(payload['context_kind'], call.kind);
          expect(payload['next_action'], 'select_agent_id');
          expect(diagnostics['ambiguous'], isTrue);
          expect(diagnostics['reason'], 'ambiguous_top_score');
          expect(candidates, hasLength(2));
          expect(first['score'], second['score']);
          expect(first['agent_id'], 'finance-a');
          expect(second['agent_id'], 'finance-b');
          expect(first['routing_keywords'], contains('finance'));
          expect(first['task_labels'], contains('finance'));
        }
      },
    );

    test(
      'routing diagnostics exclude agents that have not bound the write tool',
      () async {
        await controller.saveAgent(
          _agent(
            id: 'finance-publisher-a',
            name: 'Finance Publisher A',
            enabled: true,
            routeFrontMatter: 'keywords: finance, reconciliation',
            taskLabels: const <String>['finance'],
            builtinToolNames: const <String>['AgentTaskPublish'],
          ),
        );
        await controller.saveAgent(
          _agent(
            id: 'finance-publisher-b',
            name: 'Finance Publisher B',
            enabled: true,
            routeFrontMatter: 'keywords: finance, reconciliation',
            taskLabels: const <String>['finance'],
            builtinToolNames: const <String>['AgentTaskPublish'],
          ),
        );
        await controller.saveAgent(
          _agent(
            id: 'finance-approval-only',
            name: 'Finance Approval Only',
            enabled: true,
            routeFrontMatter: 'keywords: finance, reconciliation',
            taskLabels: const <String>['finance'],
            builtinToolNames: const <String>['AgentApprovalRequest'],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final result = await runtime.execute(
          sessionId: 'session-route-binding',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-route-binding',
            name: 'AgentTaskPublish',
            arguments: jsonEncode(<String, Object?>{
              'title': 'Finance reconciliation',
              'description': 'Prepare the finance reconciliation packet.',
              'labels': <String>['finance'],
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        expect(result.status, BashToolExecutionStatus.invalidArguments);
        final payload = jsonDecode(result.resultText) as Map<String, Object?>;
        final diagnostics =
            payload['routing_diagnostics'] as Map<String, Object?>;
        final candidates = diagnostics['candidates'] as List<Object?>;
        final candidateIds = candidates
            .map((item) => (item as Map<String, Object?>)['agent_id'])
            .toList(growable: false);
        final firstCandidate = candidates.first as Map<String, Object?>;
        final firstAgentTools =
            firstCandidate['agent_tools'] as Map<String, Object?>;

        expect(diagnostics['ambiguous'], isTrue);
        expect(candidateIds, <Object?>[
          'finance-publisher-a',
          'finance-publisher-b',
        ]);
        expect(firstAgentTools['tools'], <Object?>['AgentTaskPublish']);
        expect(firstAgentTools['groups'], <String, Object?>{
          'task_lifecycle': <Object?>['AgentTaskPublish'],
        });
        expect(candidateIds, isNot(contains('finance-approval-only')));
      },
    );

    test('complete tool writes task result and releases worker', () async {
      await controller.saveAgent(_agent(enabled: true));
      final task = await controller.publishTaskWithResult(
        'agent-1',
        title: 'Collect release evidence',
      );
      expect(task, isNotNull);
      expect(task!.status, AgentTaskStatus.running);

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await runtime.execute(
        sessionId: 'session-1',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-1',
          name: 'AgentTaskComplete',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'task_id': task.id,
            'result': 'Release evidence collected and verified.',
            'note': 'worker handoff complete',
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(result.status, BashToolExecutionStatus.success);
      final resultPayload =
          jsonDecode(result.resultText) as Map<String, Object?>;
      final resultTask = resultPayload['task'] as Map<String, Object?>;
      final resultState = resultTask['state'] as Map<String, Object?>;
      final resultWorker =
          resultTask['assigned_worker'] as Map<String, Object?>;
      final completed = controller.taskById('agent-1', task.id)!;
      expect(completed.status, AgentTaskStatus.completed);
      expect(completed.progress, 1);
      expect(completed.result, 'Release evidence collected and verified.');
      expect(completed.note, 'worker handoff complete');

      final agent = controller.agentById('agent-1')!;
      final assignedWorkerId = '${task.extra['assigned_worker_id']}';
      expect(agent.workers.single.status, AgentWorkerStatus.idle);
      expect(agent.workers.single.currentTaskId, isEmpty);
      expect(agent.activities.first.kind, 'task_completed');
      expect(agent.auditEvents.first.kind, 'task_completed');
      expect(resultState['terminal'], isTrue);
      expect(resultState['needs_polling'], isFalse);
      expect(resultState['next_action'], 'read_result');
      expect(resultState['terminal_reason'], 'completed');
      expect(resultState['allowed_tools'], isEmpty);
      expect(resultTask['next_action'], 'read_result');
      expect(resultTask['terminal_reason'], 'completed');
      expect(resultTask['result_available'], isTrue);
      expect(resultTask['allowed_tools'], isEmpty);
      expect(resultWorker['id'], assignedWorkerId);
      expect(resultWorker['status'], 'idle');

      final taskResult = await runtime.execute(
        sessionId: 'session-1',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-2',
          name: 'AgentTaskResult',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'task_id': task.id,
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );
      final taskResultPayload =
          jsonDecode(taskResult.resultText) as Map<String, Object?>;
      final handoff = taskResultPayload['handoff'] as Map<String, Object?>;
      expect(taskResult.status, BashToolExecutionStatus.success);
      expect(taskResultPayload['result_available'], isTrue);
      expect(taskResultPayload['next_action'], 'read_result');
      expect(taskResultPayload['terminal_reason'], 'completed');
      expect(taskResultPayload['allowed_tools'], isEmpty);
      expect(handoff['result_available'], isTrue);
      expect(handoff['message'], 'result_ready');
      expect(handoff['next_action'], 'read_result');
      expect(handoff['result'], 'Release evidence collected and verified.');
    });

    test(
      'track tool marks completed tasks without result as missing result',
      () async {
        await controller.saveAgent(
          _agent(
            enabled: true,
            builtinToolNames: const <String>['AgentTaskTrack'],
          ).copyWith(
            tasks: <AgentTask>[
              AgentTask(
                id: 'task-1',
                title: 'Completed without handoff',
                status: AgentTaskStatus.completed,
                progress: 1,
                createdAt: DateTime.utc(2026, 7, 4),
              ),
            ],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final result = await runtime.execute(
          sessionId: 'session-1',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-track-missing-result',
            name: 'AgentTaskTrack',
            arguments: jsonEncode(const <String, Object?>{
              'agent_id': 'agent-1',
              'task_id': 'task-1',
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        expect(result.status, BashToolExecutionStatus.success);
        final payload = jsonDecode(result.resultText) as Map<String, Object?>;
        final task = payload['task'] as Map<String, Object?>;
        final state = task['state'] as Map<String, Object?>;
        final handoff = task['handoff'] as Map<String, Object?>;
        expect(task['result_available'], isFalse);
        expect(task['next_action'], 'inspect_missing_result');
        expect(state['next_action'], 'inspect_missing_result');
        expect(handoff['message'], 'completed_without_result');
        expect(handoff['next_action'], 'inspect_missing_result');
      },
    );

    test(
      'progress and result tools expose retry state without stale failure result',
      () async {
        await controller.saveAgent(_agent(enabled: true));
        final task = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Retry transient operation',
        );
        expect(task, isNotNull);

        final retried = await controller.updateTaskState(
          'agent-1',
          task!.id,
          status: AgentTaskStatus.failed,
          result: 'transient network failure',
          note: 'first attempt timed out',
          activityKind: 'task_failed',
          activityTitle: 'task_failed',
        );
        expect(retried, isNotNull);
        expect(retried!.status, AgentTaskStatus.running);

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final progress = await runtime.execute(
          sessionId: 'session-1',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-progress',
            name: 'AgentTaskProgress',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-1',
              'task_id': task.id,
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );
        final progressPayload =
            jsonDecode(progress.resultText) as Map<String, Object?>;
        final progressState = progressPayload['state'] as Map<String, Object?>;
        final progressRetry = progressState['retry'] as Map<String, Object?>;

        expect(progress.status, BashToolExecutionStatus.success);
        expect(progressPayload['result_available'], isFalse);
        expect(progressState['needs_polling'], isTrue);
        expect(progressRetry['retry_count'], 1);
        expect(
          progressRetry['last_failure_result'],
          'transient network failure',
        );
        expect(progressRetry['last_failure_note'], 'first attempt timed out');

        final taskResult = await runtime.execute(
          sessionId: 'session-1',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-result',
            name: 'AgentTaskResult',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-1',
              'task_id': task.id,
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );
        final resultPayload =
            jsonDecode(taskResult.resultText) as Map<String, Object?>;
        final resultState = resultPayload['state'] as Map<String, Object?>;
        final resultRetry = resultState['retry'] as Map<String, Object?>;
        final handoff = resultPayload['handoff'] as Map<String, Object?>;
        final handoffRetry = handoff['retry'] as Map<String, Object?>;

        expect(taskResult.status, BashToolExecutionStatus.success);
        expect(resultPayload['result'], isEmpty);
        expect(resultPayload['note'], isEmpty);
        expect(resultPayload['result_available'], isFalse);
        expect(resultRetry['retry_count'], 1);
        expect(handoff['message'], 'result_not_ready_poll');
        expect(
          handoffRetry['last_failure_result'],
          'transient network failure',
        );
      },
    );

    test(
      'terminate tool marks task terminal and tells the model to stop',
      () async {
        await controller.saveAgent(_agent(enabled: true));
        final task = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Stop unsafe execution',
        );
        expect(task, isNotNull);
        final assignedWorkerId = '${task!.extra['assigned_worker_id']}';

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final result = await runtime.execute(
          sessionId: 'session-1',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-1',
            name: 'AgentTaskTerminate',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-1',
              'task_id': task.id,
              'note': 'operator requested termination',
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        expect(result.status, BashToolExecutionStatus.success);
        final payload = jsonDecode(result.resultText) as Map<String, Object?>;
        final resultTask = payload['task'] as Map<String, Object?>;
        final resultState = resultTask['state'] as Map<String, Object?>;
        final resultWorker =
            resultTask['assigned_worker'] as Map<String, Object?>;
        final terminated = controller.taskById('agent-1', task.id)!;
        final agent = controller.agentById('agent-1')!;

        expect(terminated.status, AgentTaskStatus.failed);
        expect(terminated.note, 'operator requested termination');
        expect(terminated.extra['tool_action'], 'task_terminated');
        expect(resultState['terminal'], isTrue);
        expect(resultState['needs_polling'], isFalse);
        expect(resultState['next_action'], 'stop');
        expect(resultState['terminal_reason'], 'terminated');
        expect(resultState['allowed_tools'], isEmpty);
        expect(resultWorker['id'], assignedWorkerId);
        expect(resultWorker['status'], 'idle');
        expect(agent.workers.single.currentTaskId, isEmpty);
        expect(agent.activities.first.kind, 'task_terminated');
        expect(agent.auditEvents.first.kind, 'task_terminated');
      },
    );

    test(
      'result tool exposes operational audit and resource summary',
      () async {
        await controller.saveAgent(
          _agent(enabled: true).copyWith(
            resourceUsage: const AgentResourceUsage(
              cpuPercent: 0.42,
              memoryBytes: 512,
              diskBytes: 2048,
              persistedBytes: 1024,
              tokenBudget: 1000,
              tokenUsed: 600,
              openHandles: 3,
            ),
          ),
        );
        final task = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Collect audit evidence',
          extra: const <String, Object?>{'handoff': 'metadata'},
        );
        final assignedWorkerId = '${task!.extra['assigned_worker_id']}';
        final currentAgent = controller.agentById('agent-1')!;
        await controller.saveAgent(
          currentAgent.copyWith(
            auditEvents: <AgentAuditEvent>[
              AgentAuditEvent(
                id: 'audit-token-1',
                kind: 'skill_call',
                summary: 'skill_call: collect evidence',
                toolName: 'SkillRunner',
                tokenUsage: 123,
                requestCount: 2,
                createdAt: DateTime.utc(2026, 7, 4),
                metadata: <String, Object?>{
                  'task_id': task.id,
                  'worker_id': assignedWorkerId,
                },
              ),
              ...currentAgent.auditEvents,
            ],
          ),
        );

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final result = await runtime.execute(
          sessionId: 'session-1',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-1',
            name: 'AgentTaskResult',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-1',
              'task_id': task.id,
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        expect(result.status, BashToolExecutionStatus.success);
        final payload = jsonDecode(result.resultText) as Map<String, Object?>;
        final resultExtra = payload['extra'] as Map<String, Object?>;
        final resultState = payload['state'] as Map<String, Object?>;
        final handoff = payload['handoff'] as Map<String, Object?>;
        final nextPoll = payload['next_poll'] as Map<String, Object?>;
        final summary = payload['operational_summary'] as Map<String, Object?>;
        final taskMetrics = summary['task_metrics'] as Map<String, Object?>;
        final taskStatusCounts =
            taskMetrics['by_status'] as Map<String, Object?>;
        final workerCapacity =
            summary['worker_capacity'] as Map<String, Object?>;
        final auditSummary = summary['audit_summary'] as Map<String, Object?>;
        final toolCounts = auditSummary['tool_counts'] as Map<String, Object?>;
        final resourceUsage = summary['resource_usage'] as Map<String, Object?>;

        expect(taskMetrics['total'], 1);
        expect(taskMetrics['active'], 1);
        expect(taskStatusCounts['running'], 1);
        expect(workerCapacity['busy'], 1);
        expect(workerCapacity['assigned_worker_id'], assignedWorkerId);
        expect(workerCapacity['assigned_worker_status'], 'busy');
        expect(auditSummary['event_count'], 3);
        expect(auditSummary['request_count'], 4);
        expect(auditSummary['token_usage'], 123);
        expect(toolCounts['SkillRunner'], 1);
        expect(toolCounts['AgentTaskDesk'], 2);
        expect(resourceUsage['token_remaining'], 400);
        expect(resourceUsage['token_usage_ratio'], 0.6);
        expect(resourceUsage['persisted_remaining_bytes'], 1024);
        expect(resourceUsage['persisted_disk_ratio'], 0.5);
        expect(resourceUsage['open_handles'], 3);
        expect(resourceUsage['open_handle_limit'], 128);
        expect(resourceUsage['pressure_level'], 'normal');
        expect(resultExtra['handoff'], 'metadata');
        expect(resultExtra['assigned_worker_id'], assignedWorkerId);
        expect(payload['result_available'], isFalse);
        expect(resultState['needs_polling'], isTrue);
        expect(payload['next_action'], 'poll');
        expect(
          payload['allowed_tools'],
          containsAll(<String>[
            'AgentTaskPause',
            'AgentTaskCancel',
            'AgentTaskTerminate',
            'AgentTaskComplete',
          ]),
        );
        expect(handoff['message'], 'result_not_ready_poll');
        expect(handoff['result_available'], isFalse);
        expect(handoff['next_action'], 'poll');
        expect(handoff['next_poll'], isA<Map<String, Object?>>());
        expect(nextPoll['tool'], 'AgentTaskProgress');
        expect(nextPoll['result_tool'], 'AgentTaskResult');
        expect(nextPoll['recommended_poll_ms'], isPositive);
      },
    );

    test('complete tool requires a non-empty result', () async {
      await controller.saveAgent(_agent(enabled: true));
      final task = await controller.publishTaskWithResult(
        'agent-1',
        title: 'Collect missing evidence',
      );

      final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
        runtimeContext: _runtimeContext(),
      );
      final result = await runtime.execute(
        sessionId: 'session-1',
        catalog: catalog,
        toolCall: AiToolCall(
          id: 'call-1',
          name: 'AgentTaskComplete',
          arguments: jsonEncode(<String, Object?>{
            'agent_id': 'agent-1',
            'task_id': task!.id,
            'result': '   ',
          }),
        ),
        model: _model(),
        previouslyReadFiles: const <String>{},
        denyCommandRules: const <AiDenyCommandRule>[],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: (request) async =>
            BashCommandApprovalDecision.approved,
      );

      expect(result.status, BashToolExecutionStatus.invalidArguments);
      expect(result.resultText, contains('result is required'));
      expect(
        controller.taskById('agent-1', task.id)!.status,
        AgentTaskStatus.running,
      );
    });

    test(
      'status tools reject terminal tasks without mutating audit state',
      () async {
        await controller.saveAgent(_agent(enabled: true));
        final task = await controller.publishTaskWithResult(
          'agent-1',
          title: 'Finalize immutable handoff',
        );
        expect(task, isNotNull);
        final completed = await controller.updateTaskState(
          'agent-1',
          task!.id,
          status: AgentTaskStatus.completed,
          result: 'done',
          activityKind: 'task_completed',
          activityTitle: 'task_completed',
        );
        expect(completed, isNotNull);

        final beforeAgent = controller.agentById('agent-1')!;
        final beforeActivityCount = beforeAgent.activities.length;
        final beforeAuditCount = beforeAgent.auditEvents.length;
        final beforeWorker = beforeAgent.workers.single;

        final catalog = runtime.resolveCatalogFromRuntimeSnapshot(
          runtimeContext: _runtimeContext(),
        );
        final result = await runtime.execute(
          sessionId: 'session-1',
          catalog: catalog,
          toolCall: AiToolCall(
            id: 'call-1',
            name: 'AgentTaskCancel',
            arguments: jsonEncode(<String, Object?>{
              'agent_id': 'agent-1',
              'task_id': task.id,
              'note': 'late cancellation should be rejected',
            }),
          ),
          model: _model(),
          previouslyReadFiles: const <String>{},
          denyCommandRules: const <AiDenyCommandRule>[],
          requireWriteCommandConfirmation: false,
          confirmWriteCommand: (request) async =>
              BashCommandApprovalDecision.approved,
        );

        final afterAgent = controller.agentById('agent-1')!;
        final afterTask = controller.taskById('agent-1', task.id)!;
        expect(result.status, BashToolExecutionStatus.invalidArguments);
        expect(result.resultText, contains('AgentTaskCancel is not allowed'));
        expect(result.resultText, contains('status is completed'));
        expect(result.resultText, contains('allowed_tools: none'));
        expect(afterTask.status, AgentTaskStatus.completed);
        expect(afterTask.note, isEmpty);
        expect(afterAgent.activities, hasLength(beforeActivityCount));
        expect(afterAgent.auditEvents, hasLength(beforeAuditCount));
        expect(afterAgent.workers.single.status, beforeWorker.status);
        expect(afterAgent.workers.single.executedTaskCount, 1);
      },
    );
  });
}

List<String> _directRequiredFields(Map<String, Object?> parameters) {
  final required = parameters['required'];
  if (required is! List) return const <String>[];
  return required.map((item) => '$item').toList(growable: false);
}

bool _schemaAllowsRequired(Map<String, Object?> parameters, String field) {
  final allOf = parameters['allOf'];
  if (allOf is! List) return false;
  for (final block in allOf) {
    if (block is! Map) continue;
    final anyOf = block['anyOf'];
    if (anyOf is! List) continue;
    for (final candidate in anyOf) {
      if (candidate is! Map) continue;
      final required = candidate['required'];
      if (required is List && required.contains(field)) return true;
    }
  }
  return false;
}

bool _schemaAnyOfAllowsRequired(Map<String, Object?> parameters, String field) {
  final anyOf = parameters['anyOf'];
  if (anyOf is! List) return false;
  for (final candidate in anyOf) {
    if (candidate is! Map) continue;
    final required = candidate['required'];
    if (required is List && required.contains(field)) return true;
  }
  return false;
}

AiToolRuntimeService _runtimeService(AgentsControllerProvider provider) {
  return AiToolRuntimeService(
    bashToolService: AiBashToolService(),
    hookService: AiNoopClaudeHookService(),
    mcpToolService: _FakeMcpToolDiscoveryService(),
    backgroundChatClient: _FakeAiChatClient(),
    agentsControllerProvider: provider,
  );
}

Future<AiToolExecutionResult> _executeAgentList(
  AiToolRuntimeService runtime,
  AiResolvedToolCatalog catalog,
) {
  return runtime.execute(
    sessionId: 'session-agent-diagnostics',
    catalog: catalog,
    toolCall: AiToolCall(
      id: 'call-agent-list',
      name: 'AgentList',
      arguments: jsonEncode(const <String, Object?>{}),
    ),
    model: _model(),
    previouslyReadFiles: const <String>{},
    denyCommandRules: const <AiDenyCommandRule>[],
    requireWriteCommandConfirmation: false,
    confirmWriteCommand: (request) async =>
        BashCommandApprovalDecision.approved,
  );
}

AiSessionRuntimeContext _runtimeContext() {
  return const AiSessionRuntimeContext(
    localeTag: 'en',
    appVersion: 'test',
    appBuildNumber: '1',
    settingsFilePath: '/tmp/settings.json',
    skillsStoragePath: '/tmp/skills',
    mcpServersFilePath: '/tmp/mcp.json',
    userMemoryFilePath: '/tmp/memory.json',
    compressionThresholdChars: 100000,
    memoryEnabled: false,
    memoryEntries: <UserMemoryEntry>[],
  );
}

AgentProfile _agent({
  String id = 'agent-1',
  String name = 'Ops Agent',
  required bool enabled,
  List<String> builtinToolNames = const <String>[],
  String routeFrontMatter = '',
  List<String> taskLabels = const <String>[],
}) {
  return AgentProfile(
    id: id,
    name: name,
    enabled: enabled,
    builtinToolNames: builtinToolNames,
    routeFrontMatter: routeFrontMatter,
    taskLabels: taskLabels,
    lifecycleState: enabled
        ? AgentLifecycleState.running
        : AgentLifecycleState.stopped,
  );
}

AiModelConfig _model() {
  return const AiModelConfig(
    id: 'model-1',
    baseUrl: 'https://example.invalid',
    authScheme: AiAuthScheme.bearer,
    token: 'test-token',
    modelId: 'test-model',
    protocolType: AiProtocolType.openai,
    maxTokens: 1024,
  );
}

class _FakeMcpToolDiscoveryService implements McpToolDiscoveryService {
  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    return const McpToolCatalog();
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    return const McpServerHealth();
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
    Map<String, String>? customHeaders,
  }) async {
    return const McpToolCallResult(outputText: '');
  }

  @override
  void dispose() {}
}

class _FakeAiChatClient implements AiChatClient {
  @override
  Future<AiChatCompletion> sendMessage({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 1),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AiChatStreamingResponse> sendMessageStream({
    required AiModelConfig model,
    required List<AiChatTurn> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    List<String> responseModalities = const <String>[],
    AiCreationRequest creationRequest = AiCreationRequest.none,
    Duration timeout = const Duration(seconds: 1),
    Duration streamIdleTimeout = const Duration(seconds: 1),
    Future<void>? cancelSignal,
    AiInputCacheRuntimeConfig? inputCacheConfig,
    void Function(AiChatRequestTelemetry telemetry)? onRequestStarted,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> testModel(AiModelConfig model) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
