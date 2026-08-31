import 'dart:async';
import 'dart:convert';

import '../../../workflows/index.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../ai_tool.dart';
import '../ai_tool_execution_context.dart';
import '../ai_tool_utils.dart';

typedef WorkflowDefinitionsProvider = List<WorkflowDefinition> Function();
typedef WorkflowResourcesProvider =
    Future<WorkflowExecutionResources?> Function(
      WorkflowDefinition workflow,
      AiToolExecutionContext context,
    );

const String workflowDefinitionsProviderMetadataKey =
    'workflow_definitions_provider';
const String workflowResourcesProviderMetadataKey =
    'workflow_resources_provider';

/// 工作流执行记录中心。记录数量和生命周期均有界，避免后台会话长期运行时
/// 内存无限增长；执行完成后仍保留一段时间供模型查询结果。
class WorkflowExecutionCoordinator {
  WorkflowExecutionCoordinator({
    this.maxRecords = 128,
    this.recordTtl = const Duration(hours: 1),
  });

  final int maxRecords;
  final Duration recordTtl;
  final Map<String, _WorkflowExecutionRecord> _records =
      <String, _WorkflowExecutionRecord>{};
  int _serial = 0;

  Future<Map<String, Object?>> start({
    required WorkflowDefinition workflow,
    required AiToolExecutionContext context,
    required WorkflowResourcesProvider resourcesProvider,
    Map<String, Object?> inputs = const <String, Object?>{},
  }) async {
    _prune();
    final executionId =
        'wf-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';
    final record = _WorkflowExecutionRecord(
      id: executionId,
      workflowId: workflow.id,
      workflowName: workflow.name,
      totalSteps: workflow.nodes.length,
      startedAt: DateTime.now().toUtc(),
    );
    _records[executionId] = record;
    unawaited(
      _run(
        record: record,
        workflow: workflow,
        context: context,
        resourcesProvider: resourcesProvider,
        inputs: inputs,
      ),
    );
    return record.snapshot();
  }

  Map<String, Object?>? status(String executionId) {
    _prune();
    return _records[executionId.trim()]?.snapshot();
  }

  Future<void> _run({
    required _WorkflowExecutionRecord record,
    required WorkflowDefinition workflow,
    required AiToolExecutionContext context,
    required WorkflowResourcesProvider resourcesProvider,
    required Map<String, Object?> inputs,
  }) async {
    try {
      final resources = await resourcesProvider(workflow, context);
      if (resources == null) {
        throw StateError('工作流执行资源不可用。');
      }
      final executor = WorkflowNodeExecutor();
      try {
        final result = await executor.executeWorkflow(
          nodes: workflow.nodes,
          connections: workflow.connections,
          resources: resources.withNodeExecutionListener((event) {
            if (event.phase == WorkflowNodeExecutionPhase.succeeded ||
                event.phase == WorkflowNodeExecutionPhase.warning) {
              record.executedSteps = (record.executedSteps + 1).clamp(
                0,
                record.totalSteps,
              );
            }
          }),
          inputs: inputs,
        );
        record.status = 'succeeded';
        record.result = <String, Object?>{
          'output': result.output,
          'variables': result.variables,
          'duration_ms': result.duration.inMilliseconds,
          'executed_steps': result.executedSteps,
          'warning_steps': result.warningSteps,
        };
      } finally {
        executor.dispose();
      }
    } catch (error) {
      record.status = 'failed';
      record.error = '$error';
    } finally {
      record.finishedAt = DateTime.now().toUtc();
    }
  }

  void _prune() {
    final cutoff = DateTime.now().toUtc().subtract(recordTtl);
    _records.removeWhere(
      (_, record) =>
          record.finishedAt != null && record.finishedAt!.isBefore(cutoff),
    );
    if (_records.length <= maxRecords) return;
    final entries = _records.entries.toList()
      ..sort((a, b) => a.value.startedAt.compareTo(b.value.startedAt));
    final removeCount = _records.length - maxRecords;
    for (var i = 0; i < removeCount; i += 1) {
      _records.remove(entries[i].key);
    }
  }
}

class _WorkflowExecutionRecord {
  _WorkflowExecutionRecord({
    required this.id,
    required this.workflowId,
    required this.workflowName,
    required this.totalSteps,
    required this.startedAt,
  });

  final String id;
  final String workflowId;
  final String workflowName;
  final int totalSteps;
  final DateTime startedAt;
  String status = 'running';
  int executedSteps = 0;
  DateTime? finishedAt;
  Map<String, Object?>? result;
  String? error;

  Map<String, Object?> snapshot() => <String, Object?>{
    'execution_id': id,
    'workflow_id': workflowId,
    'workflow_name': workflowName,
    'status': status,
    'progress': <String, Object?>{
      'executed_steps': executedSteps,
      'total_steps': totalSteps,
    },
    'started_at': startedAt.toIso8601String(),
    if (finishedAt != null) 'finished_at': finishedAt!.toIso8601String(),
    if (result != null) 'result': result,
    if (error != null) 'error': error,
  };
}

abstract class _WorkflowTool extends AiTool {
  _WorkflowTool({WorkflowExecutionCoordinator? coordinator})
    : coordinator = coordinator ?? WorkflowExecutionCoordinator();

  final WorkflowExecutionCoordinator coordinator;

  List<WorkflowDefinition> _enabledWorkflows(AiToolExecutionContext context) {
    final provider = context.metadata[workflowDefinitionsProviderMetadataKey];
    final values = provider is WorkflowDefinitionsProvider
        ? provider()
        : const <WorkflowDefinition>[];
    return values.where((workflow) => workflow.enabled).toList(growable: false);
  }

  WorkflowDefinition? _findWorkflow(
    AiToolExecutionContext context,
    Map<String, Object?> args,
  ) {
    final id = AiToolUtils.readString(args['workflow_id']);
    final name = AiToolUtils.readString(args['name']);
    final query = AiToolUtils.readString(args['query']).toLowerCase();
    if (id.isEmpty && name.isEmpty && query.isEmpty) return null;
    final candidates = _enabledWorkflows(context);
    return candidates.where((workflow) {
      if (id.isNotEmpty && workflow.id == id) return true;
      if (name.isNotEmpty && workflow.name == name) return true;
      if (query.isNotEmpty) {
        final haystack =
            '${workflow.id}\n${workflow.name}\n'
                    '${workflow.description}\n${workflow.tags.join(' ')}'
                .toLowerCase();
        return haystack.contains(query);
      }
      return false;
    }).firstOrNull;
  }

  AiToolExecutionResult jsonSuccess(
    String command,
    Object value,
    Stopwatch sw,
  ) {
    final output = const JsonEncoder.withIndent('  ').convert(value);
    return AiToolUtils.simpleSuccessResult(
      command: command,
      output: output,
      durationMs: sw.elapsedMilliseconds,
      metadata: const <String, Object?>{'tool_source': 'workflow'},
    );
  }
}

class AiWorkflowListTool extends _WorkflowTool {
  AiWorkflowListTool({super.coordinator});

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.workflowList;

  @override
  List<String> get aliases => const <String>['workflow_list'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final sw = Stopwatch()..start();
    final workflows = _enabledWorkflows(context);
    return jsonSuccess(
      'WorkflowList',
      workflows
          .map(
            (workflow) => <String, Object?>{
              'id': workflow.id,
              'name': workflow.name,
              'description': workflow.description,
              'tags': workflow.tags,
            },
          )
          .toList(growable: false),
      sw,
    );
  }
}

class AiWorkflowDetailTool extends _WorkflowTool {
  AiWorkflowDetailTool({super.coordinator});

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.workflowDetail;

  @override
  List<String> get aliases => const <String>['workflow_detail', 'workflow_get'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final sw = Stopwatch()..start();
    final workflow = _findWorkflow(context, context.decodedArguments);
    if (workflow == null) {
      return AiToolUtils.invalidResult('WorkflowDetail', '未找到处于启用状态的工作流。');
    }
    return jsonSuccess('WorkflowDetail', workflow.toJson(), sw);
  }
}

class AiWorkflowExecuteTool extends _WorkflowTool {
  AiWorkflowExecuteTool({super.coordinator});

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.workflowExecute;

  @override
  bool get isDestructive => true;

  @override
  List<String> get aliases => const <String>['workflow_execute'];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final sw = Stopwatch()..start();
    final workflow = _findWorkflow(context, context.decodedArguments);
    if (workflow == null) {
      return AiToolUtils.invalidResult('WorkflowExecute', '未找到处于启用状态的工作流。');
    }
    final provider = context.metadata[workflowResourcesProviderMetadataKey];
    if (provider is! WorkflowResourcesProvider) {
      return AiToolUtils.invalidResult('WorkflowExecute', '当前会话未提供工作流执行资源。');
    }
    final rawInputs = context.decodedArguments['inputs'];
    final inputs = rawInputs is Map
        ? <String, Object?>{
            for (final entry in rawInputs.entries) '${entry.key}': entry.value,
          }
        : const <String, Object?>{};
    final snapshot = await coordinator.start(
      workflow: workflow,
      context: context,
      resourcesProvider: provider,
      inputs: inputs,
    );
    return jsonSuccess('WorkflowExecute', snapshot, sw);
  }
}

class AiWorkflowExecutionStatusTool extends _WorkflowTool {
  AiWorkflowExecutionStatusTool({super.coordinator});

  @override
  AiBuiltinToolKind get kind => AiBuiltinToolKind.workflowExecutionStatus;

  @override
  List<String> get aliases => const <String>[
    'workflow_execution_status',
    'workflow_status',
  ];

  @override
  Future<AiToolExecutionResult> execute(AiToolExecutionContext context) async {
    final sw = Stopwatch()..start();
    final id = AiToolUtils.readString(context.decodedArguments['execution_id']);
    if (id.isEmpty) {
      return AiToolUtils.invalidResult(
        'WorkflowExecutionStatus',
        '必须提供 execution_id。',
      );
    }
    final snapshot = coordinator.status(id);
    if (snapshot == null) {
      return AiToolUtils.invalidResult(
        'WorkflowExecutionStatus',
        '未找到该工作流执行记录。',
      );
    }
    return jsonSuccess('WorkflowExecutionStatus', snapshot, sw);
  }
}
