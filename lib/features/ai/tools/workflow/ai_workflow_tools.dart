import 'dart:async';
import 'dart:convert';

import '../../../workflows/index.dart';
import '../../service/runtime/ai_tool_runtime_service.dart';
import '../../service/usage/ai_usage_tracker.dart';
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
const String workflowCallSourceMetadataKey = 'workflow_call_source';

/// 工作流执行记录中心。记录数量和生命周期均有界，避免后台会话长期运行时
/// 内存无限增长；执行完成后仍保留一段时间供模型查询结果。
class WorkflowExecutionCoordinator {
  WorkflowExecutionCoordinator({
    this.maxRecords = 128,
    this.maxConcurrentExecutions = 8,
    this.recordTtl = const Duration(hours: 1),
  }) : assert(maxRecords > 0),
       assert(maxConcurrentExecutions > 0);

  final int maxRecords;
  final int maxConcurrentExecutions;
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
      source: _executionSource(context),
      inputs: Map<String, Object?>.unmodifiable(inputs),
      environment: <String, Object?>{
        'model_id': context.model.modelId,
        'provider': context.model.providerLabel,
        'protocol': context.model.protocolType.storageValue,
        if (context.metadata['working_directory'] is String)
          'working_directory': context.metadata['working_directory'],
      },
    );
    _records[executionId] = record;
    if (_records.values.where((item) => item.finishedAt == null).length >
        maxConcurrentExecutions) {
      record.status = 'failed';
      record.error = '工作流并发执行数量已达上限。';
      record.finishedAt = DateTime.now().toUtc();
      return record.snapshot();
    }
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
      final loadedResources = await resourcesProvider(workflow, context);
      if (loadedResources == null) {
        throw StateError('工作流执行资源不可用。');
      }
      var resources = loadedResources;
      final cancelSignal = context.cancelSignal;
      if (cancelSignal != null) {
        final cancellation =
            resources.cancellation ?? WorkflowExecutionCancellationToken();
        resources = resources.withCancellation(cancellation);
        unawaited(
          cancelSignal.then<void>(
            (_) => cancellation.cancel(),
            onError: (_, _) => cancellation.cancel(),
          ),
        );
      }
      final executor = WorkflowNodeExecutor();
      try {
        final result = await AiUsageTraceContext.runDerived(
          source: record.source,
          operation: 'workflow',
          sessionId: context.sessionId,
          metadata: <String, Object?>{
            'workflow_id': workflow.id,
            'workflow_name': workflow.name,
            'workflow_execution_id': record.id,
          },
          body: () => executor.executeWorkflow(
            nodes: workflow.nodes,
            connections: workflow.connections,
            resources: resources.withNodeExecutionListener((event) {
              record.captureNodeEvent(event);
              if (event.phase == WorkflowNodeExecutionPhase.succeeded ||
                  event.phase == WorkflowNodeExecutionPhase.warning) {
                record.executedSteps = (record.executedSteps + 1).clamp(
                  0,
                  record.totalSteps,
                );
              }
            }),
            inputs: inputs,
          ),
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

  String _executionSource(AiToolExecutionContext context) {
    final explicit = '${context.metadata[workflowCallSourceMetadataKey] ?? ''}'
        .trim();
    if (explicit.isNotEmpty) return explicit;
    return '${context.metadata['created_via'] ?? ''}' == 'dingtalk_gateway'
        ? 'dingtalk'
        : 'thread';
  }

  void _prune() {
    final cutoff = DateTime.now().toUtc().subtract(recordTtl);
    _records.removeWhere(
      (_, record) =>
          record.finishedAt != null && record.finishedAt!.isBefore(cutoff),
    );
    if (_records.length <= maxRecords) return;
    final entries =
        _records.entries
            .where((entry) => entry.value.finishedAt != null)
            .toList(growable: false)
          ..sort((a, b) => a.value.startedAt.compareTo(b.value.startedAt));
    final removeCount = (_records.length - maxRecords).clamp(0, entries.length);
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
    required this.source,
    required this.inputs,
    required this.environment,
  });

  final String id;
  final String workflowId;
  final String workflowName;
  final int totalSteps;
  final DateTime startedAt;
  final String source;
  final Map<String, Object?> inputs;
  final Map<String, Object?> environment;
  String status = 'running';
  int executedSteps = 0;
  DateTime? finishedAt;
  Map<String, Object?>? result;
  String? error;
  final List<Map<String, Object?>> nodeExecutions = <Map<String, Object?>>[];

  void captureNodeEvent(WorkflowNodeExecutionEvent event) {
    if (nodeExecutions.length >= 256) return;
    nodeExecutions.add(<String, Object?>{
      'node_id': event.nodeId,
      'phase': event.phase.name,
      'duration_ms': event.duration.inMilliseconds,
      'attempts': event.attempts,
      if (event.resolvedInputs.isNotEmpty)
        'inputs': _boundedJsonValue(event.resolvedInputs),
      if (event.output != null) 'output': _boundedJsonValue(event.output),
      if (event.error != null && event.error!.trim().isNotEmpty)
        'error': _clip(event.error!),
    });
  }

  Map<String, Object?> snapshot() => <String, Object?>{
    'execution_id': id,
    'workflow_id': workflowId,
    'workflow_name': workflowName,
    'source': source,
    'inputs': inputs,
    'environment': environment,
    'status': status,
    'progress': <String, Object?>{
      'executed_steps': executedSteps,
      'total_steps': totalSteps,
    },
    'started_at': startedAt.toIso8601String(),
    if (finishedAt != null) 'finished_at': finishedAt!.toIso8601String(),
    if (result != null) 'result': result,
    if (error != null) 'error': error,
    'node_executions': List<Map<String, Object?>>.unmodifiable(nodeExecutions),
  };
}

String _clip(String value, [int max = 1200]) {
  final normalized = value.trim();
  return normalized.length <= max
      ? normalized
      : '${normalized.substring(0, max - 1)}…';
}

Object _boundedJsonValue(Object? value) {
  try {
    final encoded = jsonEncode(value);
    final clipped = _clip(encoded);
    return clipped == encoded ? value ?? '' : clipped;
  } catch (_) {
    return _clip('$value');
  }
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

  String _workflowSource(AiToolExecutionContext context) {
    final explicit = '${context.metadata[workflowCallSourceMetadataKey] ?? ''}'
        .trim();
    if (explicit.isNotEmpty) return explicit;
    return '${context.metadata['created_via'] ?? ''}' == 'dingtalk_gateway'
        ? 'dingtalk'
        : 'thread';
  }

  AiToolExecutionResult jsonSuccess(
    String command,
    Object value,
    Stopwatch sw, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final output = const JsonEncoder.withIndent('  ').convert(value);
    return AiToolUtils.simpleSuccessResult(
      command: command,
      output: output,
      durationMs: sw.elapsedMilliseconds,
      metadata: <String, Object?>{'tool_source': 'workflow', ...metadata},
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
    return jsonSuccess(
      'WorkflowDetail',
      workflow.toJson(),
      sw,
      metadata: <String, Object?>{
        'workflow_id': workflow.id,
        'workflow_name': workflow.name,
      },
    );
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
    return jsonSuccess(
      'WorkflowExecute',
      snapshot,
      sw,
      metadata: <String, Object?>{
        'workflow_id': workflow.id,
        'workflow_name': workflow.name,
        'execution_id': snapshot['execution_id'],
        'workflow_status': snapshot['status'],
        'workflow_source': _workflowSource(context),
      },
    );
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
    return jsonSuccess(
      'WorkflowExecutionStatus',
      snapshot,
      sw,
      metadata: <String, Object?>{
        'workflow_id': snapshot['workflow_id'],
        'workflow_name': snapshot['workflow_name'],
        'execution_id': snapshot['execution_id'],
        'workflow_status': snapshot['status'],
        'workflow_source': _workflowSource(context),
      },
    );
  }
}
