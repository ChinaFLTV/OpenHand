import 'dart:convert';

import 'package:flutter/foundation.dart';

enum WorkflowNodeKind {
  start('start'),
  condition('condition'),
  loop('loop'),
  iteration('iteration'),
  parameterAssignment('parameter_assignment'),
  listOperation('list_operation'),
  codeExecution('code_execution'),
  humanIntervention('human_intervention'),
  loopExit('loop_exit'),
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

enum WorkflowHumanActionStyle {
  primary('primary'),
  defaultStyle('default'),
  accent('accent'),
  ghost('ghost');

  const WorkflowHumanActionStyle(this.storageValue);

  final String storageValue;

  String get label => switch (this) {
    WorkflowHumanActionStyle.primary => '主要',
    WorkflowHumanActionStyle.defaultStyle => '默认',
    WorkflowHumanActionStyle.accent => '强调',
    WorkflowHumanActionStyle.ghost => '轻量',
  };

  static WorkflowHumanActionStyle fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (style) => style.storageValue == normalized,
      orElse: () => WorkflowHumanActionStyle.defaultStyle,
    );
  }
}

enum WorkflowCodeLanguage {
  python3('python3'),
  javascript('javascript');

  const WorkflowCodeLanguage(this.storageValue);

  final String storageValue;

  String get label => switch (this) {
    WorkflowCodeLanguage.python3 => 'Python 3',
    WorkflowCodeLanguage.javascript => 'JavaScript',
  };

  String get fileExtension => switch (this) {
    WorkflowCodeLanguage.python3 => 'py',
    WorkflowCodeLanguage.javascript => 'js',
  };

  static WorkflowCodeLanguage fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (language) => language.storageValue == normalized,
      orElse: () => WorkflowCodeLanguage.python3,
    );
  }
}

String defaultWorkflowCode(WorkflowCodeLanguage language) => switch (language) {
  WorkflowCodeLanguage.python3 =>
    '''def main():
    return {
        "result": "Hello, OpenHand"
    }''',
  WorkflowCodeLanguage.javascript =>
    '''function main() {
  return {
    result: "Hello, OpenHand"
  }
}''',
};

List<String> workflowCodeFunctionParameters(
  String code,
  WorkflowCodeLanguage language,
) {
  final match = switch (language) {
    WorkflowCodeLanguage.python3 => RegExp(
      r'def\s+main\s*\(([\s\S]*?)\)\s*(?:->[^:]*)?:',
    ).firstMatch(code),
    WorkflowCodeLanguage.javascript => RegExp(
      r'function\s+main\s*\(([\s\S]*?)\)\s*\{',
    ).firstMatch(code),
  };
  var declaration = match?.group(1)?.trim() ?? '';
  if (language == WorkflowCodeLanguage.javascript &&
      declaration.startsWith('{') &&
      declaration.endsWith('}')) {
    declaration = declaration.substring(1, declaration.length - 1);
  }
  final names = <String>{};
  for (final part in declaration.split(',')) {
    var name = part.trim();
    if (name.isEmpty || name.startsWith('...')) continue;
    name = name.split('=').first.trim();
    if (language == WorkflowCodeLanguage.python3) {
      name = name.replaceFirst(RegExp(r'^\*{1,2}'), '').split(':').first.trim();
    } else {
      name = name.split(':').first.trim();
    }
    if (workflowParameterNamePattern.hasMatch(name)) names.add(name);
  }
  return List<String>.unmodifiable(names);
}

List<String> workflowCodeReturnNames(String code) {
  final returnMatch = RegExp(r'\breturn\b').firstMatch(code);
  if (returnMatch == null) return const <String>[];
  final start = code.indexOf('{', returnMatch.end);
  if (start < 0) return const <String>[];
  final names = <String>{};
  var depth = 0;
  var entryStart = start + 1;
  String? quote;
  var escaped = false;
  for (var index = start; index < code.length; index++) {
    final character = code[index];
    if (quote != null) {
      if (escaped) {
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == quote) {
        quote = null;
      }
      continue;
    }
    if (character == '"' || character == "'") {
      quote = character;
      continue;
    }
    if (character == '{') {
      depth += 1;
      continue;
    }
    if (character == '}') {
      if (depth == 1) {
        _addWorkflowCodeReturnName(code, entryStart, index, names);
      }
      depth -= 1;
      if (depth == 0) break;
      continue;
    }
    if (character == ',' && depth == 1) {
      _addWorkflowCodeReturnName(code, entryStart, index, names);
      entryStart = index + 1;
    }
  }
  return List<String>.unmodifiable(names);
}

void _addWorkflowCodeReturnName(
  String code,
  int start,
  int end,
  Set<String> names,
) {
  if (start >= end) return;
  final match = RegExp(
    r'''^\s*(?:["']([A-Za-z_][A-Za-z0-9_]*)["']|([A-Za-z_][A-Za-z0-9_]*))\s*:''',
  ).firstMatch(code.substring(start, end));
  final name = match?.group(1) ?? match?.group(2);
  if (name != null && workflowParameterNamePattern.hasMatch(name)) {
    names.add(name);
  }
}

String workflowCodeWithInputSignature(
  String code,
  WorkflowCodeLanguage language,
  List<WorkflowOutputField> fields,
) {
  final parameters = fields
      .map((field) => field.name.trim())
      .where(workflowParameterNamePattern.hasMatch)
      .toList(growable: false);
  switch (language) {
    case WorkflowCodeLanguage.python3:
      final pattern = RegExp(r'def\s+main\s*\(([\s\S]*?)\)\s*(?:->[^:]*)?:');
      if (!pattern.hasMatch(code)) return code;
      final typed = fields
          .where(
            (field) => workflowParameterNamePattern.hasMatch(field.name.trim()),
          )
          .map(
            (field) => '${field.name.trim()}: ${_pythonCodeType(field.type)}',
          )
          .join(', ');
      return code.replaceFirst(pattern, 'def main($typed):');
    case WorkflowCodeLanguage.javascript:
      final pattern = RegExp(r'function\s+main\s*\(([\s\S]*?)\)\s*\{');
      if (!pattern.hasMatch(code)) return code;
      final signature = parameters.isEmpty
          ? ''
          : '{ ${parameters.join(', ')} }';
      return code.replaceFirst(pattern, 'function main($signature) {');
  }
}

String _pythonCodeType(WorkflowOutputType type) => switch (type) {
  WorkflowOutputType.string => 'str',
  WorkflowOutputType.integer => 'int',
  WorkflowOutputType.number => 'float',
  WorkflowOutputType.boolean => 'bool',
  WorkflowOutputType.object => 'dict',
  WorkflowOutputType.array => 'list',
  WorkflowOutputType.arrayString => 'list[str]',
  WorkflowOutputType.arrayNumber => 'list[float]',
  WorkflowOutputType.arrayObject => 'list[dict]',
  WorkflowOutputType.arrayBoolean => 'list[bool]',
};

enum WorkflowOutputType {
  string('string'),
  integer('integer'),
  number('number'),
  boolean('boolean'),
  object('object'),
  array('array'),
  arrayString('array[string]'),
  arrayNumber('array[number]'),
  arrayObject('array[object]'),
  arrayBoolean('array[boolean]');

  const WorkflowOutputType(this.storageValue);

  final String storageValue;

  String get label => switch (this) {
    WorkflowOutputType.string => 'String',
    WorkflowOutputType.integer => 'Integer',
    WorkflowOutputType.number => 'Number',
    WorkflowOutputType.boolean => 'Boolean',
    WorkflowOutputType.object => 'Object',
    WorkflowOutputType.array => 'Array',
    WorkflowOutputType.arrayString => 'Array[String]',
    WorkflowOutputType.arrayNumber => 'Array[Number]',
    WorkflowOutputType.arrayObject => 'Array[Object]',
    WorkflowOutputType.arrayBoolean => 'Array[Boolean]',
  };

  bool get isArray => switch (this) {
    WorkflowOutputType.array ||
    WorkflowOutputType.arrayString ||
    WorkflowOutputType.arrayNumber ||
    WorkflowOutputType.arrayObject ||
    WorkflowOutputType.arrayBoolean => true,
    _ => false,
  };

  WorkflowOutputType? get arrayItemType => switch (this) {
    WorkflowOutputType.arrayString => WorkflowOutputType.string,
    WorkflowOutputType.arrayNumber => WorkflowOutputType.number,
    WorkflowOutputType.arrayObject => WorkflowOutputType.object,
    WorkflowOutputType.arrayBoolean => WorkflowOutputType.boolean,
    _ => null,
  };

  bool acceptsReferenceType(WorkflowOutputType source) {
    if (this == source) return true;
    return switch (this) {
      WorkflowOutputType.string => true,
      WorkflowOutputType.integer || WorkflowOutputType.number =>
        source == WorkflowOutputType.string ||
            source == WorkflowOutputType.integer ||
            source == WorkflowOutputType.number,
      WorkflowOutputType.boolean ||
      WorkflowOutputType.object => source == WorkflowOutputType.string,
      WorkflowOutputType.array ||
      WorkflowOutputType.arrayString ||
      WorkflowOutputType.arrayNumber ||
      WorkflowOutputType.arrayObject ||
      WorkflowOutputType.arrayBoolean =>
        source == WorkflowOutputType.string || source.isArray,
    };
  }

  static WorkflowOutputType fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (type) => type.storageValue == normalized,
      orElse: () => WorkflowOutputType.string,
    );
  }
}

enum WorkflowValueSource {
  variable('variable'),
  constant('constant');

  const WorkflowValueSource(this.storageValue);

  final String storageValue;

  String get label => switch (this) {
    WorkflowValueSource.variable => '变量',
    WorkflowValueSource.constant => '常量',
  };

  static WorkflowValueSource fromStorage(
    Object? value, {
    String legacyValue = '',
  }) {
    final normalized = '${value ?? ''}'.trim();
    for (final source in values) {
      if (source.storageValue == normalized) return source;
    }
    return workflowTemplatePlaceholderPattern.hasMatch(legacyValue)
        ? WorkflowValueSource.variable
        : WorkflowValueSource.constant;
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

enum WorkflowListOrder {
  ascending('asc'),
  descending('desc');

  const WorkflowListOrder(this.storageValue);

  final String storageValue;

  static WorkflowListOrder fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (order) => order.storageValue == normalized,
      orElse: () => WorkflowListOrder.ascending,
    );
  }
}

final RegExp workflowParameterNamePattern = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]{0,63}$',
);
final RegExp workflowHumanActionIdPattern = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]{0,19}$',
);
final RegExp workflowTemplatePlaceholderPattern = RegExp(
  r'\{\{\s*([A-Za-z_][A-Za-z0-9_.-]*)\s*\}\}',
);

String workflowParameterPlaceholder(String name) => '{{${name.trim()}}}';

String? validateWorkflowSourcedValue(
  WorkflowValueSource source,
  String value, {
  required String label,
}) {
  if (source == WorkflowValueSource.variable &&
      !workflowTemplatePlaceholderPattern.hasMatch(value)) {
    return '$label请选择有效变量。';
  }
  return null;
}

const String workflowContainerStartHandleId = 'container_start';
const int maxWorkflowNestedNodeCount = 128;
const int maxWorkflowListItemCount = 10000;
const int maxWorkflowListLimit = 20;
const int maxWorkflowHumanActionCount = 8;
const int maxWorkflowHumanActionTitleLength = 100;
const String workflowHumanDeliveryMethodInAppDialog = 'in_app_dialog';
const String workflowHumanActionIdOutputName = '__action_id';
const String workflowHumanActionValueOutputName = '__action_value';
const String workflowHumanRenderedContentOutputName = '__rendered_content';
const Set<String> workflowHumanSystemOutputNames = <String>{
  workflowHumanActionIdOutputName,
  workflowHumanActionValueOutputName,
  workflowHumanRenderedContentOutputName,
};

bool isWorkflowContainerKind(WorkflowNodeKind kind) =>
    kind == WorkflowNodeKind.loop || kind == WorkflowNodeKind.iteration;

bool isWorkflowTerminalNodeKind(WorkflowNodeKind kind) =>
    kind == WorkflowNodeKind.end || kind == WorkflowNodeKind.loopExit;

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
  static const String listInput = 'list_input';
  static const String listFilterEnabled = 'list_filter_enabled';
  static const String listFilterKey = 'list_filter_key';
  static const String listFilterOperator = 'list_filter_operator';
  static const String listFilterValue = 'list_filter_value';
  static const String listFilterValueSource = 'list_filter_value_source';
  static const String listExtractEnabled = 'list_extract_enabled';
  static const String listExtractSerial = 'list_extract_serial';
  static const String listOrderEnabled = 'list_order_enabled';
  static const String listOrderKey = 'list_order_key';
  static const String listOrder = 'list_order';
  static const String listLimitEnabled = 'list_limit_enabled';
  static const String listLimitSize = 'list_limit_size';
  static const String codeLanguage = 'code_language';
  static const String code = 'code';
  static const String codeInputFields = 'code_input_fields';
  static const String codeExecutionTimeoutSeconds =
      'code_execution_timeout_seconds';
  static const String humanDeliveryMethod = 'human_delivery_method';
  static const String humanPrompt = 'human_prompt';
  static const String humanInputFields = 'human_input_fields';
  static const String humanActions = 'human_actions';
  static const String containerWidth = 'container_width';
  static const String containerHeight = 'container_height';
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
    this.valueSource = WorkflowValueSource.constant,
  });

  factory WorkflowConditionClause.fromJson(Map<String, Object?> json) {
    final value = '${json['value'] ?? ''}';
    return WorkflowConditionClause(
      id: '${json['id'] ?? ''}'.trim(),
      variable: '${json['variable'] ?? ''}',
      operator: WorkflowConditionOperator.fromStorage(json['operator']),
      value: value,
      valueSource: WorkflowValueSource.fromStorage(
        json['value_source'],
        legacyValue: value,
      ),
    );
  }

  final String id;
  final String variable;
  final WorkflowConditionOperator operator;
  final String value;
  final WorkflowValueSource valueSource;

  WorkflowConditionClause copyWith({
    String? variable,
    WorkflowConditionOperator? operator,
    String? value,
    WorkflowValueSource? valueSource,
  }) {
    return WorkflowConditionClause(
      id: id,
      variable: variable ?? this.variable,
      operator: operator ?? this.operator,
      value: value ?? this.value,
      valueSource: valueSource ?? this.valueSource,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'variable': variable,
    'operator': operator.storageValue,
    'value': value,
    'value_source': valueSource.storageValue,
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
class WorkflowHumanAction {
  const WorkflowHumanAction({
    required this.id,
    required this.title,
    this.style = WorkflowHumanActionStyle.defaultStyle,
  });

  factory WorkflowHumanAction.fromJson(Map<String, Object?> json) {
    return WorkflowHumanAction(
      id: '${json['id'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}',
      style: WorkflowHumanActionStyle.fromStorage(json['button_style']),
    );
  }

  final String id;
  final String title;
  final WorkflowHumanActionStyle style;

  WorkflowHumanAction copyWith({
    String? id,
    String? title,
    WorkflowHumanActionStyle? style,
  }) {
    return WorkflowHumanAction(
      id: id ?? this.id,
      title: title ?? this.title,
      style: style ?? this.style,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'button_style': style.storageValue,
  };
}

@immutable
class WorkflowLoopVariable {
  const WorkflowLoopVariable({
    required this.id,
    this.name = '',
    this.type = WorkflowOutputType.string,
    this.initialValue = '',
    this.valueSource = WorkflowValueSource.constant,
  });

  factory WorkflowLoopVariable.fromJson(Map<String, Object?> json) {
    final initialValue = '${json['initial_value'] ?? ''}';
    return WorkflowLoopVariable(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}',
      type: WorkflowOutputType.fromStorage(json['type']),
      initialValue: initialValue,
      valueSource: WorkflowValueSource.fromStorage(
        json['value_source'],
        legacyValue: initialValue,
      ),
    );
  }

  final String id;
  final String name;
  final WorkflowOutputType type;
  final String initialValue;
  final WorkflowValueSource valueSource;

  WorkflowLoopVariable copyWith({
    String? name,
    WorkflowOutputType? type,
    String? initialValue,
    WorkflowValueSource? valueSource,
  }) {
    return WorkflowLoopVariable(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      initialValue: initialValue ?? this.initialValue,
      valueSource: valueSource ?? this.valueSource,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'type': type.storageValue,
    'initial_value': initialValue,
    'value_source': valueSource.storageValue,
  };
}

@immutable
class WorkflowKeyValueEntry {
  const WorkflowKeyValueEntry({
    required this.id,
    this.key = '',
    this.value = '',
    this.valueSource = WorkflowValueSource.constant,
  });

  factory WorkflowKeyValueEntry.fromJson(Map<String, Object?> json) {
    final value = '${json['value'] ?? ''}';
    return WorkflowKeyValueEntry(
      id: '${json['id'] ?? ''}'.trim(),
      key: '${json['key'] ?? ''}',
      value: value,
      valueSource: WorkflowValueSource.fromStorage(
        json['value_source'],
        legacyValue: value,
      ),
    );
  }

  final String id;
  final String key;
  final String value;
  final WorkflowValueSource valueSource;

  WorkflowKeyValueEntry copyWith({
    String? key,
    String? value,
    WorkflowValueSource? valueSource,
  }) {
    return WorkflowKeyValueEntry(
      id: id,
      key: key ?? this.key,
      value: value ?? this.value,
      valueSource: valueSource ?? this.valueSource,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'key': key,
    'value': value,
    'value_source': valueSource.storageValue,
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
    final sourceError = validateWorkflowSourcedValue(
      entry.valueSource,
      value,
      label: '$label第 ${index + 1} 项',
    );
    if (sourceError != null) return sourceError;
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
    this.valueSource = WorkflowValueSource.constant,
  });

  factory WorkflowOutputField.fromJson(Map<String, Object?> json) {
    final defaultValue = '${json['default_value'] ?? ''}';
    return WorkflowOutputField(
      id: '${json['id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      type: WorkflowOutputType.fromStorage(json['type']),
      required: json['required'] == true,
      defaultValue: defaultValue,
      valueSource: WorkflowValueSource.fromStorage(
        json['value_source'],
        legacyValue: defaultValue,
      ),
    );
  }

  final String id;
  final String name;
  final String description;
  final WorkflowOutputType type;
  final bool required;
  final String defaultValue;
  final WorkflowValueSource valueSource;

  WorkflowOutputField copyWith({
    String? name,
    String? description,
    WorkflowOutputType? type,
    bool? required,
    String? defaultValue,
    WorkflowValueSource? valueSource,
  }) {
    return WorkflowOutputField(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      required: required ?? this.required,
      defaultValue: defaultValue ?? this.defaultValue,
      valueSource: valueSource ?? this.valueSource,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'type': type.storageValue,
    'required': required,
    'default_value': defaultValue,
    'value_source': valueSource.storageValue,
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
    this.parentNodeId,
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
    final parentNodeId = '${json['parent_node_id'] ?? ''}'.trim();
    _clearInactiveWorkflowNodeSettings(kind, settings);
    return WorkflowNode(
      id: id,
      kind: kind,
      title: '${json['title'] ?? ''}'.trim(),
      x: x,
      y: y,
      parentNodeId: parentNodeId.isEmpty ? null : parentNodeId,
      settings: Map<String, Object?>.unmodifiable(settings),
    );
  }

  final String id;
  final WorkflowNodeKind kind;
  final String title;
  final double x;
  final double y;
  final String? parentNodeId;
  final Map<String, Object?> settings;

  bool get isNested => parentNodeId != null;
  bool get isContainer => isWorkflowContainerKind(kind) && !isNested;

  WorkflowNode copyWith({
    String? title,
    double? x,
    double? y,
    String? parentNodeId,
    Map<String, Object?>? settings,
  }) {
    return WorkflowNode(
      id: id,
      kind: kind,
      title: title ?? this.title,
      x: x ?? this.x,
      y: y ?? this.y,
      parentNodeId: parentNodeId ?? this.parentNodeId,
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

  double doubleSetting(String key, double fallback) {
    final value = settings[key];
    return value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? fallback;
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

  List<WorkflowOutputField> codeInputFields() =>
      _fieldsSetting(WorkflowSettingKeys.codeInputFields);

  List<WorkflowOutputField> humanInputFields() =>
      _fieldsSetting(WorkflowSettingKeys.humanInputFields);

  List<WorkflowHumanAction> humanActions() {
    final value = settings[WorkflowSettingKeys.humanActions];
    if (value is! List) return const <WorkflowHumanAction>[];
    return value
        .whereType<Map>()
        .map((item) => WorkflowHumanAction.fromJson(_stringMap(item)))
        .toList(growable: false);
  }

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
    WorkflowNodeKind.humanIntervention => <WorkflowOutputField>[
      ...humanInputFields(),
      WorkflowOutputField(
        id: '$id-human-action-id',
        name: workflowHumanActionIdOutputName,
        description: '用户触发的动作标识',
      ),
      WorkflowOutputField(
        id: '$id-human-action-value',
        name: workflowHumanActionValueOutputName,
        description: '用户触发的动作文本',
      ),
      WorkflowOutputField(
        id: '$id-human-rendered-content',
        name: workflowHumanRenderedContentOutputName,
        description: '展示给用户的内容',
      ),
    ],
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
    if (parentNodeId != null) 'parent_node_id': parentNodeId,
    'settings': settings,
  };
}

String? validateWorkflowParameterNames(List<WorkflowNode> nodes) {
  final owners = <String, WorkflowNode>{};
  for (final node in nodes) {
    if (node.kind == WorkflowNodeKind.humanIntervention) {
      final conflict = node.humanInputFields().where(
        (field) => workflowHumanSystemOutputNames.contains(field.name.trim()),
      );
      if (conflict.isNotEmpty) {
        return '节点“${node.title}”使用了系统保留参数名称“${conflict.first.name.trim()}”。';
      }
    }
    for (final field in node.declaredParameterFields()) {
      final name = field.name.trim();
      if (!workflowParameterNamePattern.hasMatch(name)) {
        return '节点“${node.title}”包含无效参数名称“${field.name}”。';
      }
      final previous = owners[name];
      final sharedHumanSystemOutput =
          workflowHumanSystemOutputNames.contains(name) &&
          node.kind == WorkflowNodeKind.humanIntervention &&
          previous?.kind == WorkflowNodeKind.humanIntervention;
      if (previous != null && !sharedHumanSystemOutput) {
        return '参数名称“$name”在节点“${previous.title}”和“${node.title}”中重复。';
      }
      owners[name] = node;
    }
  }
  return null;
}

String? validateWorkflowHumanActions(List<WorkflowHumanAction> actions) {
  if (actions.isEmpty) return '人工介入节点至少需要一个用户动作。';
  if (actions.length > maxWorkflowHumanActionCount) {
    return '人工介入节点最多支持 $maxWorkflowHumanActionCount 个用户动作。';
  }
  final ids = <String>{};
  for (var index = 0; index < actions.length; index++) {
    final action = actions[index];
    if (!workflowHumanActionIdPattern.hasMatch(action.id)) {
      return '用户动作第 ${index + 1} 项的标识无效。';
    }
    if (!ids.add(action.id)) return '用户动作标识重复：${action.id}。';
    final title = action.title.trim();
    if (title.isEmpty) return '用户动作第 ${index + 1} 项的按钮文字不能为空。';
    if (title.length > maxWorkflowHumanActionTitleLength) {
      return '用户动作“${action.id}”的按钮文字过长。';
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
    if (condition.operator.requiresValue) {
      final sourceError = validateWorkflowSourcedValue(
        condition.valueSource,
        condition.value,
        label: '$label第 ${index + 1} 项的比较值',
      );
      if (sourceError != null) return sourceError;
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
    final sourceError = validateWorkflowSourcedValue(
      variable.valueSource,
      variable.initialValue,
      label: '循环变量“$name”',
    );
    if (sourceError != null) return sourceError;
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
    final nodesById = <String, WorkflowNode>{
      for (final node in nodes) node.id: node,
    };
    for (final node in nodes.where((item) => item.isNested)) {
      final parent = nodesById[node.parentNodeId];
      if (parent == null || !parent.isContainer) {
        throw const FormatException('工作流包含无效的内部节点。');
      }
      if (node.kind == WorkflowNodeKind.start ||
          node.kind == WorkflowNodeKind.end ||
          isWorkflowContainerKind(node.kind)) {
        throw const FormatException('内部工作流包含不支持的节点类型。');
      }
      if (node.kind == WorkflowNodeKind.loopExit &&
          parent.kind != WorkflowNodeKind.loop) {
        throw const FormatException('退出循环节点只能位于循环节点内部。');
      }
    }
    if (nodes.any(
      (node) => node.kind == WorkflowNodeKind.loopExit && !node.isNested,
    )) {
      throw const FormatException('退出循环节点不能位于顶层工作流。');
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
    for (final edge in connections) {
      final source = nodesById[edge.sourceNodeId]!;
      final target = nodesById[edge.targetNodeId]!;
      if (source.kind == WorkflowNodeKind.loopExit) {
        throw const FormatException('退出循环节点不能连接后续内部节点。');
      }
      final internalStart =
          source.isContainer &&
          edge.sourceHandleId == workflowContainerStartHandleId &&
          target.parentNodeId == source.id;
      final sameNestedScope =
          source.parentNodeId != null &&
          source.parentNodeId == target.parentNodeId;
      final topLevel =
          source.parentNodeId == null &&
          target.parentNodeId == null &&
          edge.sourceHandleId != workflowContainerStartHandleId;
      if (!internalStart && !sameNestedScope && !topLevel) {
        throw const FormatException('工作流包含跨作用域连线。');
      }
    }
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
