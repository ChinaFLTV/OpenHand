import 'dart:convert';

import 'package:flutter/foundation.dart';

enum WorkflowNodeKind {
  start('start'),
  condition('condition'),
  loop('loop'),
  iteration('iteration'),
  llm('llm'),
  httpRequest('http_request'),
  end('end');

  const WorkflowNodeKind(this.storageValue);

  final String storageValue;

  static WorkflowNodeKind? fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    for (final kind in values) {
      if (kind.storageValue == normalized) return kind;
    }
    return null;
  }
}

enum WorkflowOutputType {
  string('string'),
  integer('integer'),
  number('number'),
  boolean('boolean'),
  object('object'),
  array('array');

  const WorkflowOutputType(this.storageValue);

  final String storageValue;

  static WorkflowOutputType fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (type) => type.storageValue == normalized,
      orElse: () => WorkflowOutputType.string,
    );
  }
}

enum WorkflowHttpBodyFormat {
  none('none'),
  json('json'),
  text('text'),
  formUrlEncoded('form_url_encoded'),
  formData('form_data');

  const WorkflowHttpBodyFormat(this.storageValue);

  final String storageValue;

  bool get usesFields => switch (this) {
    WorkflowHttpBodyFormat.formUrlEncoded ||
    WorkflowHttpBodyFormat.formData => true,
    _ => false,
  };

  static WorkflowHttpBodyFormat fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (format) => format.storageValue == normalized,
      orElse: () => WorkflowHttpBodyFormat.none,
    );
  }
}

enum WorkflowConditionLogic {
  all('and'),
  any('or');

  const WorkflowConditionLogic(this.storageValue);

  final String storageValue;

  static WorkflowConditionLogic fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (logic) => logic.storageValue == normalized,
      orElse: () => WorkflowConditionLogic.all,
    );
  }
}

enum WorkflowConditionOperator {
  equals('equals'),
  notEquals('not_equals'),
  contains('contains'),
  notContains('not_contains'),
  startsWith('starts_with'),
  endsWith('ends_with'),
  greaterThan('greater_than'),
  lessThan('less_than'),
  greaterThanOrEqual('greater_than_or_equal'),
  lessThanOrEqual('less_than_or_equal'),
  isEmpty('is_empty'),
  isNotEmpty('is_not_empty'),
  isNull('is_null'),
  isNotNull('is_not_null');

  const WorkflowConditionOperator(this.storageValue);

  final String storageValue;

  bool get requiresValue => switch (this) {
    WorkflowConditionOperator.isEmpty ||
    WorkflowConditionOperator.isNotEmpty ||
    WorkflowConditionOperator.isNull ||
    WorkflowConditionOperator.isNotNull => false,
    _ => true,
  };

  static WorkflowConditionOperator fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (operator) => operator.storageValue == normalized,
      orElse: () => WorkflowConditionOperator.equals,
    );
  }
}

enum WorkflowIterationErrorMode {
  stop('stop'),
  continueOnError('continue_on_error'),
  removeFailed('remove_failed');

  const WorkflowIterationErrorMode(this.storageValue);

  final String storageValue;

  static WorkflowIterationErrorMode fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (mode) => mode.storageValue == normalized,
      orElse: () => WorkflowIterationErrorMode.stop,
    );
  }
}

final RegExp workflowParameterNamePattern = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]{0,63}$',
);
final RegExp workflowTemplatePlaceholderPattern = RegExp(
  r'\{\{\s*([A-Za-z_][A-Za-z0-9_.-]*)\s*\}\}',
);

String workflowParameterPlaceholder(String name) => '{{${name.trim()}}}';

abstract final class WorkflowSettingKeys {
  static const String expression = 'expression';
  static const String conditionCases = 'condition_cases';
  static const String maxIterations = 'max_iterations';
  static const String loopVariables = 'loop_variables';
  static const String loopBreakConditions = 'loop_break_conditions';
  static const String loopConditionLogic = 'loop_condition_logic';
  static const String iterationInput = 'iteration_input';
  static const String iterationOutputName = 'iteration_output_name';
  static const String iterationOutput = 'iteration_output';
  static const String iterationParallel = 'iteration_parallel';
  static const String iterationParallelism = 'iteration_parallelism';
  static const String iterationErrorMode = 'iteration_error_mode';
  static const String iterationFlattenOutput = 'iteration_flatten_output';
  static const String modelConfigId = 'model_config_id';
  static const String modelId = 'model_id';
  static const String reasoningEffort = 'reasoning_effort';
  static const String templateId = 'template_id';
  static const String prompt = 'prompt';
  static const String inputContent = 'input_content';
  static const String inputFields = 'input_fields';
  static const String multimodalCapabilities = 'multimodal_capabilities';
  static const String skillNames = 'skill_names';
  static const String memoryIds = 'memory_ids';
  static const String instructionIds = 'instruction_ids';
  static const String knowledgeSourceIds = 'knowledge_source_ids';
  static const String mcpServerNames = 'mcp_server_names';
  static const String structuredOutput = 'structured_output';
  static const String outputFields = 'output_fields';
  static const String retryCount = 'retry_count';
  static const String retryIntervalMs = 'retry_interval_ms';
  static const String url = 'url';
  static const String method = 'method';
  static const String headers = 'headers';
  static const String queryParameters = 'query_parameters';
  static const String body = 'body';
  static const String bodyEntries = 'body_entries';
  static const String bodyFormat = 'body_format';
  static const String connectTimeoutSeconds = 'connect_timeout_seconds';
  static const String responseTimeoutSeconds = 'response_timeout_seconds';
}

@immutable
class WorkflowConditionClause {
  const WorkflowConditionClause({
    required this.id,
    this.variable = '',
    this.operator = WorkflowConditionOperator.equals,
    this.value = '',
  });

  factory WorkflowConditionClause.fromJson(Map<String, Object?> json) {
    return WorkflowConditionClause(
      id: '${json['id'] ?? ''}'.trim(),
      variable: '${json['variable'] ?? ''}',
      operator: WorkflowConditionOperator.fromStorage(json['operator']),
      value: '${json['value'] ?? ''}',
    );
  }

  final String id;
  final String variable;
  final WorkflowConditionOperator operator;
  final String value;

  WorkflowConditionClause copyWith({
    String? variable,
    WorkflowConditionOperator? operator,
    String? value,
  }) {
    return WorkflowConditionClause(
      id: id,
      variable: variable ?? this.variable,
      operator: operator ?? this.operator,
      value: value ?? this.value,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'variable': variable,
    'operator': operator.storageValue,
    'value': value,
  };
}

@immutable
class WorkflowConditionCase {
  const WorkflowConditionCase({
    required this.id,
    this.logic = WorkflowConditionLogic.all,
    this.conditions = const <WorkflowConditionClause>[],
  });

  factory WorkflowConditionCase.fromJson(Map<String, Object?> json) {
    return WorkflowConditionCase(
      id: '${json['id'] ?? ''}'.trim(),
      logic: WorkflowConditionLogic.fromStorage(json['logic']),
      conditions: _mapList(json['conditions'])
          .map(WorkflowConditionClause.fromJson)
          .where((condition) => condition.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  final String id;
  final WorkflowConditionLogic logic;
  final List<WorkflowConditionClause> conditions;

  WorkflowConditionCase copyWith({
    WorkflowConditionLogic? logic,
    List<WorkflowConditionClause>? conditions,
  }) {
    return WorkflowConditionCase(
      id: id,
      logic: logic ?? this.logic,
      conditions: conditions ?? this.conditions,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'logic': logic.storageValue,
    'conditions': conditions
        .map((condition) => condition.toJson())
        .toList(growable: false),
  };
}

@immutable
class WorkflowLoopVariable {
  const WorkflowLoopVariable({
    required this.id,
    this.name = '',
    this.type = WorkflowOutputType.string,
    this.initialValue = '',
  });

  factory WorkflowLoopVariable.fromJson(Map<String, Object?> json) {
    return WorkflowLoopVariable(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}',
      type: WorkflowOutputType.fromStorage(json['type']),
      initialValue: '${json['initial_value'] ?? ''}',
    );
  }

  final String id;
  final String name;
  final WorkflowOutputType type;
  final String initialValue;

  WorkflowLoopVariable copyWith({
    String? name,
    WorkflowOutputType? type,
    String? initialValue,
  }) {
    return WorkflowLoopVariable(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      initialValue: initialValue ?? this.initialValue,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'type': type.storageValue,
    'initial_value': initialValue,
  };
}

@immutable
class WorkflowKeyValueEntry {
  const WorkflowKeyValueEntry({
    required this.id,
    this.key = '',
    this.value = '',
  });

  factory WorkflowKeyValueEntry.fromJson(Map<String, Object?> json) {
    return WorkflowKeyValueEntry(
      id: '${json['id'] ?? ''}'.trim(),
      key: '${json['key'] ?? ''}',
      value: '${json['value'] ?? ''}',
    );
  }

  final String id;
  final String key;
  final String value;

  WorkflowKeyValueEntry copyWith({String? key, String? value}) {
    return WorkflowKeyValueEntry(
      id: id,
      key: key ?? this.key,
      value: value ?? this.value,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'key': key,
    'value': value,
  };
}

final RegExp _workflowHttpHeaderNamePattern = RegExp(
  r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$",
);

String? validateWorkflowKeyValueEntries(
  List<WorkflowKeyValueEntry> entries, {
  required String label,
  bool httpHeaders = false,
}) {
  final keys = <String>{};
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    final key = entry.key.trim();
    final value = entry.value;
    if (key.isEmpty || value.trim().isEmpty) {
      return '$label第 ${index + 1} 项的键和值都不能为空。';
    }
    if (httpHeaders && !_workflowHttpHeaderNamePattern.hasMatch(key)) {
      return '$label第 ${index + 1} 项的键不是有效的 HTTP 请求头名称。';
    }
    if (httpHeaders && !_isValidWorkflowHttpHeaderValue(value)) {
      return '$label第 ${index + 1} 项的值包含无效字符。';
    }
    final normalizedKey = httpHeaders ? key.toLowerCase() : key;
    if (!keys.add(normalizedKey)) {
      return '$label中存在重复的键“$key”。';
    }
  }
  return null;
}

bool _isValidWorkflowHttpHeaderValue(String value) {
  for (final codeUnit in value.codeUnits) {
    if (codeUnit == 0x09) continue;
    if (codeUnit > 0xFF || codeUnit < 0x20 || codeUnit == 0x7F) return false;
  }
  return true;
}

@immutable
class WorkflowOutputField {
  const WorkflowOutputField({
    required this.id,
    this.name = '',
    this.description = '',
    this.type = WorkflowOutputType.string,
    this.required = false,
    this.defaultValue = '',
  });

  factory WorkflowOutputField.fromJson(Map<String, Object?> json) {
    return WorkflowOutputField(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      type: WorkflowOutputType.fromStorage(json['type']),
      required: json['required'] == true,
      defaultValue: '${json['default_value'] ?? ''}',
    );
  }

  final String id;
  final String name;
  final String description;
  final WorkflowOutputType type;
  final bool required;
  final String defaultValue;

  WorkflowOutputField copyWith({
    String? name,
    String? description,
    WorkflowOutputType? type,
    bool? required,
    String? defaultValue,
  }) {
    return WorkflowOutputField(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      required: required ?? this.required,
      defaultValue: defaultValue ?? this.defaultValue,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'type': type.storageValue,
    'required': required,
    'default_value': defaultValue,
  };
}

@immutable
class WorkflowParameterReference {
  const WorkflowParameterReference({
    required this.nodeId,
    required this.nodeTitle,
    required this.field,
  });

  final String nodeId;
  final String nodeTitle;
  final WorkflowOutputField field;

  String get name => field.name.trim();
}

@immutable
class WorkflowNode {
  const WorkflowNode({
    required this.id,
    required this.kind,
    required this.title,
    required this.x,
    required this.y,
    this.settings = const <String, Object?>{},
  });

  factory WorkflowNode.fromJson(Map<String, Object?> json) {
    final kind = WorkflowNodeKind.fromStorage(json['kind']);
    if (kind == null) throw const FormatException('工作流节点类型无效。');
    final id = '${json['id'] ?? ''}'.trim();
    final x = _finiteDouble(json['x']);
    final y = _finiteDouble(json['y']);
    if (id.isEmpty || x == null || y == null) {
      throw const FormatException('工作流节点数据不完整。');
    }
    final settings = _stringMap(json['settings']);
    _clearInactiveWorkflowNodeSettings(kind, settings);
    return WorkflowNode(
      id: id,
      kind: kind,
      title: '${json['title'] ?? ''}'.trim(),
      x: x,
      y: y,
      settings: Map<String, Object?>.unmodifiable(settings),
    );
  }

  final String id;
  final WorkflowNodeKind kind;
  final String title;
  final double x;
  final double y;
  final Map<String, Object?> settings;

  WorkflowNode copyWith({
    String? title,
    double? x,
    double? y,
    Map<String, Object?>? settings,
  }) {
    return WorkflowNode(
      id: id,
      kind: kind,
      title: title ?? this.title,
      x: x ?? this.x,
      y: y ?? this.y,
      settings: settings ?? this.settings,
    );
  }

  String stringSetting(String key, [String fallback = '']) {
    return settings[key] is String ? settings[key] as String : fallback;
  }

  int intSetting(String key, int fallback) {
    final value = settings[key];
    return value is int ? value : int.tryParse('$value') ?? fallback;
  }

  bool boolSetting(String key, [bool fallback = false]) {
    final value = settings[key];
    return value is bool ? value : fallback;
  }

  Set<String> stringSetSetting(String key) {
    final value = settings[key];
    if (value is! List) return <String>{};
    return value
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  List<WorkflowKeyValueEntry> keyValueSetting(String key) {
    final value = settings[key];
    if (value is! List) return const <WorkflowKeyValueEntry>[];
    return value
        .whereType<Map>()
        .map((item) => WorkflowKeyValueEntry.fromJson(_stringMap(item)))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  List<WorkflowOutputField> inputFields() =>
      _fieldsSetting(WorkflowSettingKeys.inputFields);

  List<WorkflowOutputField> outputFields() =>
      _fieldsSetting(WorkflowSettingKeys.outputFields);

  List<WorkflowConditionCase> conditionCases() {
    final value = settings[WorkflowSettingKeys.conditionCases];
    if (value is! List) return const <WorkflowConditionCase>[];
    return value
        .whereType<Map>()
        .map((item) => WorkflowConditionCase.fromJson(_stringMap(item)))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  List<WorkflowLoopVariable> loopVariables() {
    final value = settings[WorkflowSettingKeys.loopVariables];
    if (value is! List) return const <WorkflowLoopVariable>[];
    return value
        .whereType<Map>()
        .map((item) => WorkflowLoopVariable.fromJson(_stringMap(item)))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  List<WorkflowConditionClause> loopBreakConditions() {
    final value = settings[WorkflowSettingKeys.loopBreakConditions];
    if (value is! List) return const <WorkflowConditionClause>[];
    return value
        .whereType<Map>()
        .map((item) => WorkflowConditionClause.fromJson(_stringMap(item)))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  List<WorkflowOutputField> declaredParameterFields() => switch (kind) {
    WorkflowNodeKind.start => inputFields(),
    WorkflowNodeKind.iteration => <WorkflowOutputField>[
      WorkflowOutputField(
        id: '$id-iteration-output',
        name: stringSetting(
          WorkflowSettingKeys.iterationOutputName,
          'iteration_result',
        ),
        description: '迭代结果数组',
        type: WorkflowOutputType.array,
      ),
    ],
    WorkflowNodeKind.loop =>
      loopVariables()
          .map(
            (variable) => WorkflowOutputField(
              id: variable.id,
              name: variable.name,
              description: '循环结束后的变量值',
              type: variable.type,
            ),
          )
          .toList(growable: false),
    _ => outputFields(),
  };

  List<WorkflowOutputField> _fieldsSetting(String key) {
    final value = settings[key];
    if (value is! List) return const <WorkflowOutputField>[];
    return value
        .whereType<Map>()
        .map((item) => WorkflowOutputField.fromJson(_stringMap(item)))
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind.storageValue,
    'title': title,
    'x': x,
    'y': y,
    'settings': settings,
  };
}

String? validateWorkflowParameterNames(List<WorkflowNode> nodes) {
  final owners = <String, WorkflowNode>{};
  for (final node in nodes) {
    for (final field in node.declaredParameterFields()) {
      final name = field.name.trim();
      if (!workflowParameterNamePattern.hasMatch(name)) {
        return '节点“${node.title}”包含无效参数名称“${field.name}”。';
      }
      final previous = owners[name];
      if (previous != null) {
        return '参数名称“$name”在节点“${previous.title}”和“${node.title}”中重复。';
      }
      owners[name] = node;
    }
  }
  return null;
}

String? validateWorkflowConditionClauses(
  List<WorkflowConditionClause> conditions, {
  required String label,
  bool allowEmpty = false,
}) {
  if (conditions.isEmpty && !allowEmpty) return '$label至少需要一个条件。';
  final ids = <String>{};
  for (var index = 0; index < conditions.length; index++) {
    final condition = conditions[index];
    if (condition.id.isEmpty || !ids.add(condition.id)) {
      return '$label第 ${index + 1} 项标识无效。';
    }
    if (condition.variable.trim().isEmpty) {
      return '$label第 ${index + 1} 项缺少变量。';
    }
    if (condition.operator.requiresValue && condition.value.trim().isEmpty) {
      return '$label第 ${index + 1} 项缺少比较值。';
    }
  }
  return null;
}

String? validateWorkflowConditionCases(List<WorkflowConditionCase> cases) {
  if (cases.isEmpty) return '条件分支至少需要一个 IF 分支。';
  final ids = <String>{};
  for (var index = 0; index < cases.length; index++) {
    final item = cases[index];
    if (item.id.isEmpty || !ids.add(item.id)) return '条件分支标识无效。';
    final error = validateWorkflowConditionClauses(
      item.conditions,
      label: index == 0 ? 'IF 分支' : 'ELIF $index 分支',
    );
    if (error != null) return error;
  }
  return null;
}

String? validateWorkflowLoopVariables(List<WorkflowLoopVariable> variables) {
  final ids = <String>{};
  final names = <String>{};
  for (var index = 0; index < variables.length; index++) {
    final variable = variables[index];
    if (variable.id.isEmpty || !ids.add(variable.id)) {
      return '循环变量第 ${index + 1} 项标识无效。';
    }
    final name = variable.name.trim();
    if (!workflowParameterNamePattern.hasMatch(name)) {
      return '循环变量第 ${index + 1} 项名称无效。';
    }
    if (!names.add(name)) return '循环变量名称重复：$name。';
    if (variable.initialValue.trim().isEmpty) {
      return '循环变量“$name”缺少初始值。';
    }
  }
  return null;
}

void _clearInactiveWorkflowNodeSettings(
  WorkflowNodeKind kind,
  Map<String, Object?> settings,
) {
  if (const <WorkflowNodeKind>{
        WorkflowNodeKind.llm,
        WorkflowNodeKind.httpRequest,
      }.contains(kind) &&
      settings[WorkflowSettingKeys.structuredOutput] != true) {
    settings[WorkflowSettingKeys.outputFields] = <Object?>[];
  }
  if (kind != WorkflowNodeKind.httpRequest) return;
  final method = '${settings[WorkflowSettingKeys.method] ?? 'GET'}'
      .trim()
      .toUpperCase();
  if (const <String>{'GET', 'HEAD'}.contains(method)) {
    settings[WorkflowSettingKeys.bodyFormat] =
        WorkflowHttpBodyFormat.none.storageValue;
    settings[WorkflowSettingKeys.body] = '';
    settings[WorkflowSettingKeys.bodyEntries] = <Object?>[];
    return;
  }
  final format = WorkflowHttpBodyFormat.fromStorage(
    settings[WorkflowSettingKeys.bodyFormat],
  );
  if (format == WorkflowHttpBodyFormat.none || format.usesFields) {
    settings[WorkflowSettingKeys.body] = '';
  }
  if (!format.usesFields) {
    settings[WorkflowSettingKeys.bodyEntries] = <Object?>[];
  }
}

@immutable
class WorkflowConnection {
  const WorkflowConnection({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
    this.sourceHandleId,
  });

  factory WorkflowConnection.fromJson(Map<String, Object?> json) {
    return WorkflowConnection(
      id: '${json['id'] ?? ''}'.trim(),
      sourceNodeId: '${json['source_node_id'] ?? ''}'.trim(),
      targetNodeId: '${json['target_node_id'] ?? ''}'.trim(),
      sourceHandleId: '${json['source_handle_id'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['source_handle_id']}'.trim(),
    );
  }

  final String id;
  final String sourceNodeId;
  final String targetNodeId;
  final String? sourceHandleId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'source_node_id': sourceNodeId,
    'target_node_id': targetNodeId,
    if (sourceHandleId != null) 'source_handle_id': sourceHandleId,
  };
}

@immutable
class WorkflowDefinition {
  const WorkflowDefinition({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.nodes = const <WorkflowNode>[],
    this.connections = const <WorkflowConnection>[],
  });

  factory WorkflowDefinition.fromJson(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final name = '${json['name'] ?? ''}'.trim();
    final createdAt = DateTime.tryParse('${json['created_at'] ?? ''}')?.toUtc();
    final updatedAt = DateTime.tryParse('${json['updated_at'] ?? ''}')?.toUtc();
    if (id.isEmpty || name.isEmpty || createdAt == null || updatedAt == null) {
      throw const FormatException('工作流数据不完整。');
    }
    final nodes = _mapList(
      json['nodes'],
    ).map(WorkflowNode.fromJson).toList(growable: false);
    final nodeIds = nodes.map((node) => node.id).toSet();
    if (nodeIds.length != nodes.length) {
      throw const FormatException('工作流包含重复节点。');
    }
    final connections = _mapList(json['connections'])
        .map(WorkflowConnection.fromJson)
        .where(
          (edge) =>
              edge.id.isNotEmpty &&
              edge.sourceNodeId != edge.targetNodeId &&
              nodeIds.contains(edge.sourceNodeId) &&
              nodeIds.contains(edge.targetNodeId),
        )
        .toList(growable: false);
    return WorkflowDefinition(
      id: id,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      nodes: List<WorkflowNode>.unmodifiable(nodes),
      connections: List<WorkflowConnection>.unmodifiable(connections),
    );
  }

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WorkflowNode> nodes;
  final List<WorkflowConnection> connections;

  WorkflowDefinition copyWith({
    String? name,
    DateTime? updatedAt,
    List<WorkflowNode>? nodes,
    List<WorkflowConnection>? connections,
  }) {
    return WorkflowDefinition(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      nodes: nodes ?? this.nodes,
      connections: connections ?? this.connections,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'id': id,
    'name': name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
    'connections': connections
        .map((edge) => edge.toJson())
        .toList(growable: false),
  };

  String encode() => jsonEncode(toJson());
}

Map<String, Object?> _stringMap(Object? value) {
  if (value is! Map) return <String, Object?>{};
  return <String, Object?>{
    for (final entry in value.entries) '${entry.key}': entry.value,
  };
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return value.whereType<Map>().map(_stringMap).toList(growable: false);
}

double? _finiteDouble(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed?.isFinite == true ? parsed : null;
}
