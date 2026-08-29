import 'dart:convert';

import 'package:flutter/foundation.dart';

enum WorkflowNodeKind {
  condition('condition'),
  loop('loop'),
  iteration('iteration'),
  llm('llm'),
  httpRequest('http_request');

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

  static WorkflowHttpBodyFormat fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (format) => format.storageValue == normalized,
      orElse: () => WorkflowHttpBodyFormat.none,
    );
  }
}

abstract final class WorkflowSettingKeys {
  static const String expression = 'expression';
  static const String maxIterations = 'max_iterations';
  static const String iterationInput = 'iteration_input';
  static const String modelConfigId = 'model_config_id';
  static const String templateId = 'template_id';
  static const String prompt = 'prompt';
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
class WorkflowKeyValueEntry {
  const WorkflowKeyValueEntry({
    required this.id,
    this.key = '',
    this.value = '',
    this.enabled = true,
  });

  factory WorkflowKeyValueEntry.fromJson(Map<String, Object?> json) {
    return WorkflowKeyValueEntry(
      id: '${json['id'] ?? ''}'.trim(),
      key: '${json['key'] ?? ''}',
      value: '${json['value'] ?? ''}',
      enabled: json['enabled'] != false,
    );
  }

  final String id;
  final String key;
  final String value;
  final bool enabled;

  WorkflowKeyValueEntry copyWith({String? key, String? value, bool? enabled}) {
    return WorkflowKeyValueEntry(
      id: id,
      key: key ?? this.key,
      value: value ?? this.value,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'key': key,
    'value': value,
    'enabled': enabled,
  };
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
    return WorkflowNode(
      id: id,
      kind: kind,
      title: '${json['title'] ?? ''}'.trim(),
      x: x,
      y: y,
      settings: Map<String, Object?>.unmodifiable(_stringMap(json['settings'])),
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

  WorkflowNode withSetting(String key, Object? value) {
    return copyWith(settings: <String, Object?>{...settings, key: value});
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

  List<WorkflowOutputField> outputFields() {
    final value = settings[WorkflowSettingKeys.outputFields];
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

@immutable
class WorkflowConnection {
  const WorkflowConnection({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
  });

  factory WorkflowConnection.fromJson(Map<String, Object?> json) {
    return WorkflowConnection(
      id: '${json['id'] ?? ''}'.trim(),
      sourceNodeId: '${json['source_node_id'] ?? ''}'.trim(),
      targetNodeId: '${json['target_node_id'] ?? ''}'.trim(),
    );
  }

  final String id;
  final String sourceNodeId;
  final String targetNodeId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'source_node_id': sourceNodeId,
    'target_node_id': targetNodeId,
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
