import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../model/workflow_definition.dart';
import 'workflow_node_executor.dart';

enum WorkflowDevelopmentParameterSource { startInput, nodeOutput, manual }

@immutable
class WorkflowDevelopmentParameter {
  const WorkflowDevelopmentParameter({
    required this.id,
    required this.field,
    required this.source,
    this.ownerNodeId,
    this.direction = WorkflowParameterDirection.input,
    this.value = '',
  });

  final String id;
  final WorkflowOutputField field;
  final WorkflowDevelopmentParameterSource source;
  final String? ownerNodeId;
  final WorkflowParameterDirection direction;
  final String value;

  String get name => field.name.trim();
  bool get isWorkflowDefined =>
      source != WorkflowDevelopmentParameterSource.manual;
  bool get canDelete => source != WorkflowDevelopmentParameterSource.startInput;

  WorkflowDevelopmentParameter copyWith({
    WorkflowOutputField? field,
    WorkflowParameterDirection? direction,
    String? value,
  }) => WorkflowDevelopmentParameter(
    id: id,
    field: field ?? this.field,
    source: source,
    ownerNodeId: ownerNodeId,
    direction: direction ?? this.direction,
    value: value ?? this.value,
  );
}

List<WorkflowDevelopmentParameter>
synchronizeWorkflowDevelopmentStartParameters({
  required List<WorkflowDevelopmentParameter> parameters,
  required WorkflowNode startNode,
}) {
  final existingInputs = <String, WorkflowDevelopmentParameter>{
    for (final parameter in parameters)
      if (parameter.source == WorkflowDevelopmentParameterSource.startInput)
        _developmentParameterFieldKey(parameter.field): parameter,
  };
  final startParameters = startNode.inputFields().map((field) {
    final existing = existingInputs[_developmentParameterFieldKey(field)];
    if (existing != null) {
      return existing.copyWith(
        field: field,
        direction: WorkflowParameterDirection.input,
      );
    }
    return WorkflowDevelopmentParameter(
      id: 'start-${_developmentParameterFieldKey(field)}',
      field: field,
      source: WorkflowDevelopmentParameterSource.startInput,
      ownerNodeId: startNode.id,
    );
  });
  return List<WorkflowDevelopmentParameter>.unmodifiable(
    <WorkflowDevelopmentParameter>[
      ...startParameters,
      ...parameters.where(
        (parameter) =>
            parameter.source != WorkflowDevelopmentParameterSource.startInput,
      ),
    ],
  );
}

Map<String, Object?> resolveWorkflowDevelopmentParameterValues(
  Iterable<WorkflowDevelopmentParameter> parameters,
) {
  final available = <String, WorkflowDevelopmentParameter>{};
  for (final parameter in parameters) {
    final name = parameter.name;
    if (name.isEmpty || parameter.value.trim().isEmpty) continue;
    if (available.containsKey(name)) {
      throw WorkflowNodeExecutionException('开发环境中存在重复参数“$name”。');
    }
    available[name] = parameter;
  }

  final resolved = <String, Object?>{};
  final resolving = <String>{};

  Object? resolve(String name) {
    if (resolved.containsKey(name)) return resolved[name];
    final parameter = available[name];
    if (parameter == null) {
      throw WorkflowNodeExecutionException('参数“$name”尚未赋值或不可用。');
    }
    if (!resolving.add(name)) {
      throw WorkflowNodeExecutionException('开发环境参数“$name”存在循环引用。');
    }
    try {
      for (final match in workflowTemplatePlaceholderPattern.allMatches(
        parameter.value,
      )) {
        final reference = match.group(1)!;
        final rootName = reference.split('.').first;
        if (!available.containsKey(rootName)) {
          throw WorkflowNodeExecutionException(
            '参数“$name”引用的参数“$reference”尚未赋值或不可用。',
          );
        }
        resolve(rootName);
      }
      final value = resolveWorkflowTemplateValue(parameter.value, resolved);
      final parsed = WorkflowStructuredOutputParser.resolveValues(
        <WorkflowOutputField>[parameter.field],
        <String, Object?>{name: value},
        label: '开发环境参数',
      );
      resolved[name] = parsed[name];
      return resolved[name];
    } finally {
      resolving.remove(name);
    }
  }

  for (final name in available.keys) {
    resolve(name);
  }
  return Map<String, Object?>.unmodifiable(resolved);
}

String workflowDevelopmentParameterValueText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return jsonEncode(value);
  } catch (_) {
    return '$value';
  }
}

String _developmentParameterFieldKey(WorkflowOutputField field) {
  final id = field.id.trim();
  return id.isEmpty ? field.name.trim() : id;
}
