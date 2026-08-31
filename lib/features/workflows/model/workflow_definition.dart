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

enum WorkflowAnnotationTheme {
  blue('blue'),
  cyan('cyan'),
  green('green'),
  yellow('yellow'),
  pink('pink'),
  violet('violet');

  const WorkflowAnnotationTheme(this.storageValue);

  final String storageValue;

  String get label => switch (this) {
    WorkflowAnnotationTheme.blue => '蓝色',
    WorkflowAnnotationTheme.cyan => '青色',
    WorkflowAnnotationTheme.green => '绿色',
    WorkflowAnnotationTheme.yellow => '黄色',
    WorkflowAnnotationTheme.pink => '粉色',
    WorkflowAnnotationTheme.violet => '紫色',
  };

  int get accentColorValue => switch (this) {
    WorkflowAnnotationTheme.blue => 0xFF2563EB,
    WorkflowAnnotationTheme.cyan => 0xFF0891B2,
    WorkflowAnnotationTheme.green => 0xFF16A34A,
    WorkflowAnnotationTheme.yellow => 0xFFD97706,
    WorkflowAnnotationTheme.pink => 0xFFDB2777,
    WorkflowAnnotationTheme.violet => 0xFF7C3AED,
  };

  int get softColorValue => switch (this) {
    WorkflowAnnotationTheme.blue => 0xFFE8F0FE,
    WorkflowAnnotationTheme.cyan => 0xFFE0F7FA,
    WorkflowAnnotationTheme.green => 0xFFE6F6EA,
    WorkflowAnnotationTheme.yellow => 0xFFFFF4D6,
    WorkflowAnnotationTheme.pink => 0xFFFCE7F3,
    WorkflowAnnotationTheme.violet => 0xFFF0E8FF,
  };

  static WorkflowAnnotationTheme fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (theme) => theme.storageValue == normalized,
      orElse: () => WorkflowAnnotationTheme.blue,
    );
  }
}

const double kWorkflowAnnotationDefaultWidth = 320;
const double kWorkflowAnnotationDefaultHeight = 190;
const double kWorkflowAnnotationMinWidth = 240;
const double kWorkflowAnnotationMinHeight = 140;
const double kWorkflowAnnotationMaxWidth = 720;
const double kWorkflowAnnotationMaxHeight = 520;
const double kWorkflowAnnotationDefaultFontSize = 18;
const double kWorkflowAnnotationMinFontSize = 13;
const double kWorkflowAnnotationMaxFontSize = 30;
const int kWorkflowAnnotationMaxCharacters = 12000;
const int kWorkflowAnnotationMaxStyleRanges = 2048;

@immutable
class WorkflowAnnotationTextStyleRange {
  const WorkflowAnnotationTextStyleRange({
    required this.start,
    required this.end,
    this.fontSize,
    this.bold,
    this.italic,
    this.strikethrough,
  });

  factory WorkflowAnnotationTextStyleRange.fromJson(Map<String, Object?> json) {
    final start = _nonNegativeInt(json['start']);
    final end = _nonNegativeInt(json['end']);
    if (start == null || end == null || end < start) {
      throw const FormatException('工作流注释文本样式范围无效。');
    }
    final rawFontSize = _finiteDouble(json['font_size']);
    return WorkflowAnnotationTextStyleRange(
      start: start,
      end: end,
      fontSize: rawFontSize?.clamp(
        kWorkflowAnnotationMinFontSize,
        kWorkflowAnnotationMaxFontSize,
      ),
      bold: json['bold'] is bool ? json['bold'] as bool : null,
      italic: json['italic'] is bool ? json['italic'] as bool : null,
      strikethrough: json['strikethrough'] is bool
          ? json['strikethrough'] as bool
          : null,
    );
  }

  final int start;
  final int end;
  final double? fontSize;
  final bool? bold;
  final bool? italic;
  final bool? strikethrough;

  WorkflowAnnotationTextStyleRange copyWith({
    int? start,
    int? end,
    double? fontSize,
    bool? bold,
    bool? italic,
    bool? strikethrough,
  }) => WorkflowAnnotationTextStyleRange(
    start: start ?? this.start,
    end: end ?? this.end,
    fontSize: fontSize ?? this.fontSize,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    strikethrough: strikethrough ?? this.strikethrough,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'start': start,
    'end': end,
    if (fontSize != null) 'font_size': fontSize,
    if (bold != null) 'bold': bold,
    if (italic != null) 'italic': italic,
    if (strikethrough != null) 'strikethrough': strikethrough,
  };
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

enum WorkflowHumanTimeoutUnit {
  day('day'),
  hour('hour');

  const WorkflowHumanTimeoutUnit(this.storageValue);

  final String storageValue;

  String get label => switch (this) {
    WorkflowHumanTimeoutUnit.day => '天',
    WorkflowHumanTimeoutUnit.hour => '小时',
  };

  Duration duration(int value) => switch (this) {
    WorkflowHumanTimeoutUnit.day => Duration(days: value),
    WorkflowHumanTimeoutUnit.hour => Duration(hours: value),
  };

  static WorkflowHumanTimeoutUnit fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (unit) => unit.storageValue == normalized,
      orElse: () => WorkflowHumanTimeoutUnit.day,
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

enum WorkflowErrorStrategy {
  terminate('none'),
  defaultValue('default-value'),
  failBranch('fail-branch');

  const WorkflowErrorStrategy(this.storageValue);

  final String storageValue;

  String get label => switch (this) {
    WorkflowErrorStrategy.terminate => '终止工作流',
    WorkflowErrorStrategy.defaultValue => '返回默认值',
    WorkflowErrorStrategy.failBranch => '进入异常分支',
  };

  static WorkflowErrorStrategy fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (strategy) => strategy.storageValue == normalized,
      orElse: () => WorkflowErrorStrategy.terminate,
    );
  }
}

enum WorkflowLlmReasoningFormat {
  tagged('tagged'),
  separated('separated');

  const WorkflowLlmReasoningFormat(this.storageValue);

  final String storageValue;

  static WorkflowLlmReasoningFormat fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (format) => format.storageValue == normalized,
      orElse: () => WorkflowLlmReasoningFormat.tagged,
    );
  }
}

String defaultWorkflowCode(
  WorkflowCodeLanguage language, {
  List<String> inputNames = defaultWorkflowCodeInputNames,
  String outputName = 'result',
}) {
  final firstInput = inputNames.isEmpty ? 'arg1' : inputNames.first;
  final secondInput = inputNames.length < 2 ? firstInput : inputNames[1];
  return switch (language) {
    WorkflowCodeLanguage.python3 =>
      '''def main($firstInput: str, $secondInput: str):
    return {
        "$outputName": $firstInput + $secondInput,
    }''',
    WorkflowCodeLanguage.javascript =>
      '''function main({$firstInput, $secondInput}) {
  return {
    $outputName: $firstInput + $secondInput
  }
}''',
  };
}

const List<String> defaultWorkflowCodeInputNames = <String>['arg1', 'arg2'];

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

String defaultWorkflowErrorValue(WorkflowOutputType type) => switch (type) {
  WorkflowOutputType.string => '',
  WorkflowOutputType.integer || WorkflowOutputType.number => '0',
  WorkflowOutputType.boolean => 'false',
  WorkflowOutputType.object => '{}',
  WorkflowOutputType.array ||
  WorkflowOutputType.arrayString ||
  WorkflowOutputType.arrayNumber ||
  WorkflowOutputType.arrayObject ||
  WorkflowOutputType.arrayBoolean => '[]',
};

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

enum WorkflowValueMode {
  literal('literal'),
  pythonExpression('python_expression'),
  javascriptExpression('javascript_expression');

  const WorkflowValueMode(this.storageValue);

  final String storageValue;

  String get label => switch (this) {
    WorkflowValueMode.literal => '字面量拼接',
    WorkflowValueMode.pythonExpression => 'Python 表达式',
    WorkflowValueMode.javascriptExpression => 'JavaScript 表达式',
  };

  WorkflowCodeLanguage? get language => switch (this) {
    WorkflowValueMode.literal => null,
    WorkflowValueMode.pythonExpression => WorkflowCodeLanguage.python3,
    WorkflowValueMode.javascriptExpression => WorkflowCodeLanguage.javascript,
  };

  static WorkflowValueMode fromStorage(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return values.firstWhere(
      (mode) => mode.storageValue == normalized,
      orElse: () => WorkflowValueMode.literal,
    );
  }
}

bool workflowLiteralValueRequiresString(String value) {
  final matches = workflowTemplatePlaceholderPattern.allMatches(value).toList();
  return matches.isNotEmpty &&
      !(matches.length == 1 &&
          matches.first.start == 0 &&
          matches.first.end == value.length);
}

final RegExp _workflowJsonPathPropertyPattern = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_-]*$',
);

List<Object>? parseWorkflowJsonPath(String path) {
  final source = path.trim();
  if (source.isEmpty || !source.startsWith(r'$')) return null;
  final segments = <Object>[];
  var offset = 1;
  while (offset < source.length) {
    if (source[offset] == '.') {
      final start = ++offset;
      while (offset < source.length &&
          source[offset] != '.' &&
          source[offset] != '[') {
        offset += 1;
      }
      if (offset == start) return null;
      final key = source.substring(start, offset);
      if (!_workflowJsonPathPropertyPattern.hasMatch(key)) return null;
      segments.add(key);
      continue;
    }
    if (source[offset] != '[') return null;
    final close = source.indexOf(']', offset + 1);
    if (close < 0) return null;
    final token = source.substring(offset + 1, close).trim();
    final index = int.tryParse(token);
    if (index != null && index >= 0) {
      segments.add(index);
    } else if (token.length >= 2 &&
        token.startsWith('"') &&
        token.endsWith('"')) {
      try {
        final key = jsonDecode(token);
        if (key is! String || key.isEmpty) return null;
        segments.add(key);
      } on FormatException {
        return null;
      }
    } else if (token.length >= 2 &&
        token.startsWith("'") &&
        token.endsWith("'")) {
      final key = token.substring(1, token.length - 1);
      if (key.isEmpty || key.contains("'")) return null;
      segments.add(key);
    } else {
      return null;
    }
    offset = close + 1;
  }
  return List<Object>.unmodifiable(segments);
}

enum WorkflowHttpBodyFormat {
  none('none'),
  json('json'),
  text('text'),
  formUrlEncoded('form_url_encoded'),
  formData('form_data'),
  binary('binary');

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
final RegExp _workflowDirectReferencePattern = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_.-]*$',
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
const String workflowSuccessHandleId = 'success';
const String workflowFailureHandleId = 'fail-branch';
const String workflowErrorTypeOutputName = 'error_type';
const String workflowErrorMessageOutputName = 'error_message';
const Set<String> workflowErrorSystemOutputNames = <String>{
  workflowErrorTypeOutputName,
  workflowErrorMessageOutputName,
};
const int defaultWorkflowCodeRetryCount = 3;
const int minWorkflowCodeRetryCount = 1;
const int maxWorkflowCodeRetryCount = 10;
const int defaultWorkflowCodeRetryIntervalMs = 1000;
const int minWorkflowCodeRetryIntervalMs = 100;
const int maxWorkflowCodeRetryIntervalMs = 5000;
const int defaultWorkflowHttpConnectTimeoutSeconds = 10;
const int defaultWorkflowHttpReadTimeoutSeconds = 60;
const int defaultWorkflowHttpWriteTimeoutSeconds = 60;
const int minWorkflowHttpTimeoutSeconds = 1;
const int maxWorkflowHttpConnectTimeoutSeconds = 10;
const int maxWorkflowHttpReadTimeoutSeconds = 600;
const int maxWorkflowHttpWriteTimeoutSeconds = 600;
const int defaultWorkflowHttpRetryCount = 3;
const int defaultWorkflowHttpRetryIntervalMs = 100;
const int minWorkflowHttpRetryCount = 1;
const int maxWorkflowHttpRetryCount = 10;
const int minWorkflowHttpRetryIntervalMs = 100;
const int maxWorkflowHttpRetryIntervalMs = 5000;
const int defaultWorkflowLlmRetryCount = 3;
const int minWorkflowLlmRetryCount = 1;
const int maxWorkflowLlmRetryCount = 10;
const int defaultWorkflowLlmRetryIntervalMs = 1000;
const int minWorkflowLlmRetryIntervalMs = 100;
const int maxWorkflowLlmRetryIntervalMs = 5000;
const String workflowLlmTextOutputName = 'text';
const String workflowLlmReasoningOutputName = 'reasoning_content';
const String workflowLlmUsageOutputName = 'usage';
const Set<String> workflowLlmFixedOutputNames = <String>{
  workflowLlmTextOutputName,
  workflowLlmReasoningOutputName,
  workflowLlmUsageOutputName,
};
const String workflowHttpBodyOutputName = 'body';
const String workflowHttpStatusCodeOutputName = 'status_code';
const String workflowHttpHeadersOutputName = 'headers';
const String workflowHttpFilesOutputName = 'files';
const Set<String> workflowHttpFixedOutputNames = <String>{
  workflowHttpBodyOutputName,
  workflowHttpStatusCodeOutputName,
  workflowHttpHeadersOutputName,
  workflowHttpFilesOutputName,
};
const int maxWorkflowNestedNodeCount = 128;
const int maxWorkflowHumanActionCount = 8;
const int maxWorkflowHumanActionTitleLength = 100;
const int defaultWorkflowHumanTimeout = 3;
const String workflowHumanDeliveryMethodInAppDialog = 'in_app_dialog';
const String workflowHumanTimeoutHandleId = '__timeout';
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
  static const String description = 'description';
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
  static const String retryEnabled = 'retry_enabled';
  static const String errorStrategy = 'error_strategy';
  static const String errorDefaultValues = 'error_default_values';
  static const String humanDeliveryMethod = 'human_delivery_method';
  static const String humanPrompt = 'human_prompt';
  static const String humanInputFields = 'human_input_fields';
  static const String humanActions = 'human_actions';
  static const String humanTimeout = 'human_timeout';
  static const String humanTimeoutUnit = 'human_timeout_unit';
  static const String containerWidth = 'container_width';
  static const String containerHeight = 'container_height';
  static const String modelConfigId = 'model_config_id';
  static const String modelId = 'model_id';
  static const String reasoningEffort = 'reasoning_effort';
  static const String reasoningFormat = 'reasoning_format';
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
  static const String systemOutputNames = 'system_output_names';
  static const String retryCount = 'retry_count';
  static const String retryIntervalMs = 'retry_interval_ms';
  static const String url = 'url';
  static const String method = 'method';
  static const String headers = 'headers';
  static const String queryParameters = 'query_parameters';
  static const String body = 'body';
  static const String bodyEntries = 'body_entries';
  static const String bodyFormat = 'body_format';
  static const String verifySsl = 'verify_ssl';
  static const String connectTimeoutSeconds = 'connect_timeout_seconds';
  static const String responseTimeoutSeconds = 'response_timeout_seconds';
  static const String writeTimeoutSeconds = 'write_timeout_seconds';
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
    this.value = '',
    this.valueMode = WorkflowValueMode.literal,
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
      value: '${json['value'] ?? ''}',
      valueMode: WorkflowValueMode.fromStorage(json['value_mode']),
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
  final String value;
  final WorkflowValueMode valueMode;
  final String defaultValue;
  final WorkflowValueSource valueSource;

  WorkflowOutputField copyWith({
    String? name,
    String? description,
    WorkflowOutputType? type,
    bool? required,
    String? value,
    WorkflowValueMode? valueMode,
    String? defaultValue,
    WorkflowValueSource? valueSource,
  }) {
    return WorkflowOutputField(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      required: required ?? this.required,
      value: value ?? this.value,
      valueMode: valueMode ?? this.valueMode,
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
    'value': value,
    'value_mode': valueMode.storageValue,
    'default_value': defaultValue,
    'value_source': valueSource.storageValue,
  };
}

enum WorkflowParameterDirection {
  input,
  output;

  String get label => switch (this) {
    WorkflowParameterDirection.input => '输入参数',
    WorkflowParameterDirection.output => '输出参数',
  };

  String get shortLabel => switch (this) {
    WorkflowParameterDirection.input => '输入',
    WorkflowParameterDirection.output => '输出',
  };
}

@immutable
class WorkflowParameterReference {
  const WorkflowParameterReference({
    required this.nodeId,
    required this.nodeTitle,
    required this.field,
    this.direction = WorkflowParameterDirection.output,
  });

  final String nodeId;
  final String nodeTitle;
  final WorkflowOutputField field;
  final WorkflowParameterDirection direction;

  String get name => field.name.trim();
}

/// 按输入→输出顺序收集节点可引用参数，并通过 [usedNames] 全局去重。
List<WorkflowParameterReference> collectWorkflowParameterReferences(
  WorkflowNode node, {
  required Set<String> usedNames,
  String? nodeTitleOverride,
}) {
  final title =
      nodeTitleOverride ??
      (node.title.trim().isEmpty ? '未命名节点' : node.title.trim());
  final references = <WorkflowParameterReference>[];
  void append(
    List<WorkflowOutputField> fields,
    WorkflowParameterDirection direction,
  ) {
    for (final field in fields) {
      final name = field.name.trim();
      if (!workflowParameterNamePattern.hasMatch(name) ||
          !usedNames.add(name)) {
        continue;
      }
      references.add(
        WorkflowParameterReference(
          nodeId: node.id,
          nodeTitle: title,
          field: field,
          direction: direction,
        ),
      );
    }
  }

  append(node.inputParameterFields(), WorkflowParameterDirection.input);
  append(node.outputParameterFields(), WorkflowParameterDirection.output);
  return references;
}

/// 从 [targetNodeId] 沿入边回溯，返回上游节点到目标的最小跳数（直接上游为 1）。
Map<String, int> workflowUpstreamHopDistances({
  required String targetNodeId,
  required List<WorkflowConnection> connections,
}) {
  if (targetNodeId.isEmpty) return const <String, int>{};
  final distances = <String, int>{targetNodeId: 0};
  final pending = <String>[targetNodeId];
  var cursor = 0;
  while (cursor < pending.length) {
    final current = pending[cursor++];
    final nextDistance = distances[current]! + 1;
    for (final connection in connections) {
      if (connection.targetNodeId != current) continue;
      final sourceId = connection.sourceNodeId;
      if (sourceId.isEmpty ||
          sourceId == targetNodeId ||
          distances.containsKey(sourceId)) {
        continue;
      }
      distances[sourceId] = nextDistance;
      pending.add(sourceId);
    }
  }
  distances.remove(targetNodeId);
  return distances;
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

  bool retryEnabled() => boolSetting(
    WorkflowSettingKeys.retryEnabled,
    intSetting(WorkflowSettingKeys.retryCount, 0) > 0,
  );

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

  Map<String, String> errorDefaultValues() {
    final value = settings[WorkflowSettingKeys.errorDefaultValues];
    if (value is! Map) return const <String, String>{};
    return Map<String, String>.unmodifiable(<String, String>{
      for (final entry in value.entries) '${entry.key}': '${entry.value ?? ''}',
    });
  }

  List<WorkflowOutputField> humanInputFields() =>
      _fieldsSetting(WorkflowSettingKeys.humanInputFields);

  String systemOutputName(String name) {
    final aliases = settings[WorkflowSettingKeys.systemOutputNames];
    if (aliases is! Map) return name;
    final alias = '${aliases[name] ?? ''}'.trim();
    return workflowParameterNamePattern.hasMatch(alias) ? alias : name;
  }

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

  List<WorkflowOutputField> inputParameterFields() => switch (kind) {
    WorkflowNodeKind.start => inputFields(),
    WorkflowNodeKind.codeExecution => codeInputFields(),
    WorkflowNodeKind.humanIntervention => humanInputFields(),
    _ => const <WorkflowOutputField>[],
  };

  List<WorkflowOutputField> outputParameterFields() => switch (kind) {
    WorkflowNodeKind.start => const <WorkflowOutputField>[],
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
    WorkflowNodeKind.codeExecution => <WorkflowOutputField>[
      ...outputFields(),
      if (WorkflowErrorStrategy.fromStorage(
            settings[WorkflowSettingKeys.errorStrategy],
          ) ==
          WorkflowErrorStrategy.failBranch) ...<WorkflowOutputField>[
        WorkflowOutputField(
          id: '$id-code-error-type',
          name: systemOutputName(workflowErrorTypeOutputName),
          description: '代码执行异常类型',
        ),
        WorkflowOutputField(
          id: '$id-code-error-message',
          name: systemOutputName(workflowErrorMessageOutputName),
          description: '代码执行异常信息',
        ),
      ],
    ],
    WorkflowNodeKind.llm => <WorkflowOutputField>[
      ...llmResponseFields(),
      if (WorkflowErrorStrategy.fromStorage(
            settings[WorkflowSettingKeys.errorStrategy],
          ) ==
          WorkflowErrorStrategy.failBranch) ...<WorkflowOutputField>[
        WorkflowOutputField(
          id: '$id-llm-error-type',
          name: systemOutputName(workflowErrorTypeOutputName),
          description: 'LLM 执行异常类型',
        ),
        WorkflowOutputField(
          id: '$id-llm-error-message',
          name: systemOutputName(workflowErrorMessageOutputName),
          description: 'LLM 执行异常信息',
        ),
      ],
    ],
    WorkflowNodeKind.httpRequest => <WorkflowOutputField>[
      ...httpResponseFields(),
      if (WorkflowErrorStrategy.fromStorage(
            settings[WorkflowSettingKeys.errorStrategy],
          ) ==
          WorkflowErrorStrategy.failBranch) ...<WorkflowOutputField>[
        WorkflowOutputField(
          id: '$id-http-error-type',
          name: systemOutputName(workflowErrorTypeOutputName),
          description: 'HTTP 请求异常类型',
        ),
        WorkflowOutputField(
          id: '$id-http-error-message',
          name: systemOutputName(workflowErrorMessageOutputName),
          description: 'HTTP 请求异常信息',
        ),
      ],
    ],
    WorkflowNodeKind.humanIntervention => <WorkflowOutputField>[
      WorkflowOutputField(
        id: '$id-human-action-id',
        name: systemOutputName(workflowHumanActionIdOutputName),
        description: '用户触发的动作标识',
      ),
      WorkflowOutputField(
        id: '$id-human-action-value',
        name: systemOutputName(workflowHumanActionValueOutputName),
        description: '用户触发的动作文本',
      ),
      WorkflowOutputField(
        id: '$id-human-rendered-content',
        name: systemOutputName(workflowHumanRenderedContentOutputName),
        description: '展示给用户的内容',
      ),
    ],
    _ => outputFields(),
  };

  List<WorkflowOutputField> declaredParameterFields() => <WorkflowOutputField>[
    ...inputParameterFields(),
    ...outputParameterFields(),
  ];

  List<WorkflowOutputField> llmResponseFields() =>
      boolSetting(WorkflowSettingKeys.structuredOutput)
      ? outputFields()
      : <WorkflowOutputField>[
          WorkflowOutputField(
            id: '$id-llm-text',
            name: systemOutputName(workflowLlmTextOutputName),
            description: '模型最终回复',
          ),
          WorkflowOutputField(
            id: '$id-llm-reasoning',
            name: systemOutputName(workflowLlmReasoningOutputName),
            description: '模型推理内容',
          ),
          WorkflowOutputField(
            id: '$id-llm-usage',
            name: systemOutputName(workflowLlmUsageOutputName),
            description: '模型令牌用量',
            type: WorkflowOutputType.object,
          ),
        ];

  List<WorkflowOutputField> httpResponseFields() =>
      boolSetting(WorkflowSettingKeys.structuredOutput)
      ? outputFields()
      : <WorkflowOutputField>[
          WorkflowOutputField(
            id: '$id-http-body',
            name: systemOutputName(workflowHttpBodyOutputName),
            description: 'HTTP 响应正文',
          ),
          WorkflowOutputField(
            id: '$id-http-status-code',
            name: systemOutputName(workflowHttpStatusCodeOutputName),
            description: 'HTTP 响应状态码',
            type: WorkflowOutputType.integer,
          ),
          WorkflowOutputField(
            id: '$id-http-headers',
            name: systemOutputName(workflowHttpHeadersOutputName),
            description: 'HTTP 响应头',
            type: WorkflowOutputType.object,
          ),
          WorkflowOutputField(
            id: '$id-http-files',
            name: systemOutputName(workflowHttpFilesOutputName),
            description: 'HTTP 响应文件',
            type: WorkflowOutputType.arrayObject,
          ),
        ];

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

@immutable
class WorkflowAnnotation {
  const WorkflowAnnotation({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    this.width = kWorkflowAnnotationDefaultWidth,
    this.height = kWorkflowAnnotationDefaultHeight,
    this.theme = WorkflowAnnotationTheme.blue,
    this.fontSize = kWorkflowAnnotationDefaultFontSize,
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.styleRanges = const <WorkflowAnnotationTextStyleRange>[],
  });

  factory WorkflowAnnotation.fromJson(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final textValue = json['text'];
    if (textValue != null && textValue is! String) {
      throw const FormatException('工作流注释文本格式无效。');
    }
    final text = textValue as String? ?? '';
    final x = _finiteDouble(json['x']);
    final y = _finiteDouble(json['y']);
    if (id.isEmpty || x == null || y == null) {
      throw const FormatException('工作流注释数据不完整。');
    }
    if (text.runes.length > kWorkflowAnnotationMaxCharacters) {
      throw const FormatException('工作流注释内容过长。');
    }
    final width =
        _finiteDouble(json['width']) ?? kWorkflowAnnotationDefaultWidth;
    final height =
        _finiteDouble(json['height']) ?? kWorkflowAnnotationDefaultHeight;
    final fontSize =
        _finiteDouble(json['font_size']) ?? kWorkflowAnnotationDefaultFontSize;
    final rawRanges = _mapList(json['style_ranges']);
    if (rawRanges.length > kWorkflowAnnotationMaxStyleRanges) {
      throw const FormatException('工作流注释文本样式范围过多。');
    }
    final styleRanges = <WorkflowAnnotationTextStyleRange>[];
    for (final rangeJson in rawRanges) {
      try {
        styleRanges.add(WorkflowAnnotationTextStyleRange.fromJson(rangeJson));
      } on FormatException {
        // 忽略单个无效范围，保留注释正文可用。
      }
    }
    return WorkflowAnnotation(
      id: id,
      text: text,
      x: x,
      y: y,
      width: width.clamp(
        kWorkflowAnnotationMinWidth,
        kWorkflowAnnotationMaxWidth,
      ),
      height: height.clamp(
        kWorkflowAnnotationMinHeight,
        kWorkflowAnnotationMaxHeight,
      ),
      theme: WorkflowAnnotationTheme.fromStorage(json['theme']),
      fontSize: fontSize.clamp(
        kWorkflowAnnotationMinFontSize,
        kWorkflowAnnotationMaxFontSize,
      ),
      bold: json['bold'] == true,
      italic: json['italic'] == true,
      strikethrough: json['strikethrough'] == true,
      styleRanges: _normalizeWorkflowAnnotationStyleRanges(
        styleRanges,
        text.length,
      ),
    );
  }

  final String id;
  final String text;
  final double x;
  final double y;
  final double width;
  final double height;
  final WorkflowAnnotationTheme theme;
  final double fontSize;
  final bool bold;
  final bool italic;
  final bool strikethrough;
  final List<WorkflowAnnotationTextStyleRange> styleRanges;

  WorkflowAnnotation copyWith({
    String? text,
    double? x,
    double? y,
    double? width,
    double? height,
    WorkflowAnnotationTheme? theme,
    double? fontSize,
    bool? bold,
    bool? italic,
    bool? strikethrough,
    List<WorkflowAnnotationTextStyleRange>? styleRanges,
  }) {
    final nextText = text ?? this.text;
    return WorkflowAnnotation(
      id: id,
      text: nextText,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      theme: theme ?? this.theme,
      fontSize: fontSize ?? this.fontSize,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      strikethrough: strikethrough ?? this.strikethrough,
      styleRanges: _normalizeWorkflowAnnotationStyleRanges(
        styleRanges ?? this.styleRanges,
        nextText.length,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'text': text,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'theme': theme.storageValue,
    'font_size': fontSize,
    'bold': bold,
    'italic': italic,
    'strikethrough': strikethrough,
    if (styleRanges.isNotEmpty)
      'style_ranges': styleRanges.map((range) => range.toJson()).toList(),
  };
}

List<WorkflowAnnotationTextStyleRange> _normalizeWorkflowAnnotationStyleRanges(
  Iterable<WorkflowAnnotationTextStyleRange> ranges,
  int textLength,
) {
  final normalized = <WorkflowAnnotationTextStyleRange>[];
  for (final range in ranges) {
    final start = range.start.clamp(0, textLength);
    final end = range.end.clamp(start, textLength);
    if (start == end && range.start != range.end) continue;
    normalized.add(
      range.copyWith(
        start: start,
        end: end,
        fontSize: range.fontSize?.clamp(
          kWorkflowAnnotationMinFontSize,
          kWorkflowAnnotationMaxFontSize,
        ),
      ),
    );
  }
  normalized.sort((a, b) {
    final startOrder = a.start.compareTo(b.start);
    return startOrder != 0 ? startOrder : a.end.compareTo(b.end);
  });
  return List<WorkflowAnnotationTextStyleRange>.unmodifiable(normalized);
}

List<WorkflowNode> normalizeWorkflowSystemOutputNames(
  List<WorkflowNode> nodes,
) {
  final usedNames = <String>{};
  for (final node in nodes) {
    final fields = switch (node.kind) {
      WorkflowNodeKind.start => node.inputFields(),
      WorkflowNodeKind.iteration ||
      WorkflowNodeKind.loop => node.outputParameterFields(),
      WorkflowNodeKind.codeExecution => <WorkflowOutputField>[
        ...node.codeInputFields(),
        ...node.outputFields(),
      ],
      WorkflowNodeKind.llm
          when node.boolSetting(WorkflowSettingKeys.structuredOutput) =>
        node.outputFields(),
      WorkflowNodeKind.httpRequest
          when node.boolSetting(WorkflowSettingKeys.structuredOutput) =>
        node.outputFields(),
      WorkflowNodeKind.humanIntervention => node.humanInputFields(),
      _ => node.outputFields(),
    };
    usedNames.addAll(
      fields
          .map((field) => field.name.trim())
          .where(workflowParameterNamePattern.hasMatch),
    );
  }

  return nodes
      .map((node) {
        final systemNames = <String>[
          if (node.kind == WorkflowNodeKind.llm &&
              !node.boolSetting(WorkflowSettingKeys.structuredOutput))
            ...workflowLlmFixedOutputNames,
          if (node.kind == WorkflowNodeKind.httpRequest &&
              !node.boolSetting(WorkflowSettingKeys.structuredOutput))
            ...workflowHttpFixedOutputNames,
          if (node.kind == WorkflowNodeKind.humanIntervention)
            ...workflowHumanSystemOutputNames,
          if (const <WorkflowNodeKind>{
                WorkflowNodeKind.codeExecution,
                WorkflowNodeKind.llm,
                WorkflowNodeKind.httpRequest,
              }.contains(node.kind) &&
              WorkflowErrorStrategy.fromStorage(
                    node.settings[WorkflowSettingKeys.errorStrategy],
                  ) ==
                  WorkflowErrorStrategy.failBranch)
            ...workflowErrorSystemOutputNames,
        ];
        if (systemNames.isEmpty) return node;

        final stored = node.settings[WorkflowSettingKeys.systemOutputNames];
        final aliases = <String, Object?>{
          if (stored is Map)
            for (final entry in stored.entries) '${entry.key}': entry.value,
        };
        var changed = false;
        for (final base in systemNames) {
          var candidate = '${aliases[base] ?? base}'.trim();
          if (!workflowParameterNamePattern.hasMatch(candidate) ||
              usedNames.contains(candidate)) {
            candidate = base;
            var suffix = 2;
            while (usedNames.contains(candidate)) {
              candidate = '${base}_${suffix++}';
            }
          }
          usedNames.add(candidate);
          if (aliases[base] != candidate) {
            aliases[base] = candidate;
            changed = true;
          }
        }
        if (!changed && stored is Map) return node;
        return node.copyWith(
          settings: <String, Object?>{
            ...node.settings,
            WorkflowSettingKeys.systemOutputNames: aliases,
          },
        );
      })
      .toList(growable: false);
}

String? validateWorkflowParameterNames(List<WorkflowNode> nodes) {
  final owners = <String, WorkflowNode>{};
  for (final node in nodes) {
    if (node.kind == WorkflowNodeKind.codeExecution) {
      final conflict =
          <WorkflowOutputField>[
            ...node.codeInputFields(),
            ...node.outputFields(),
          ].where(
            (field) =>
                workflowErrorSystemOutputNames.contains(field.name.trim()),
          );
      if (conflict.isNotEmpty) {
        return '节点“${node.title}”使用了系统保留参数名称“${conflict.first.name.trim()}”。';
      }
    }
    if (node.kind == WorkflowNodeKind.httpRequest) {
      final conflict = node.outputFields().where(
        (field) =>
            workflowErrorSystemOutputNames.contains(field.name.trim()) ||
            workflowHttpFixedOutputNames.contains(field.name.trim()),
      );
      if (conflict.isNotEmpty) {
        return '节点“${node.title}”使用了 HTTP 系统保留参数名称“${conflict.first.name.trim()}”。';
      }
    }
    if (node.kind == WorkflowNodeKind.llm) {
      final conflict = node.outputFields().where(
        (field) =>
            workflowErrorSystemOutputNames.contains(field.name.trim()) ||
            workflowLlmFixedOutputNames.contains(field.name.trim()),
      );
      if (conflict.isNotEmpty) {
        return '节点“${node.title}”使用了 LLM 系统保留参数名称“${conflict.first.name.trim()}”。';
      }
    }
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
      if (previous != null) {
        return '参数名称“$name”在节点“${previous.title}”和“${node.title}”中重复。';
      }
      owners[name] = node;
    }
  }
  return null;
}

/// 校验参数引用的来源、执行顺序与作用域，避免保存后在运行时才发现失效引用。
String? validateWorkflowParameterReferences(
  List<WorkflowNode> nodes,
  List<WorkflowConnection> connections,
) {
  final nameError = validateWorkflowParameterNames(nodes);
  if (nameError != null) return nameError;
  final nodesById = <String, WorkflowNode>{
    for (final node in nodes) node.id: node,
  };
  final scopes = _workflowParameterScopes(nodes, connections);
  final conditionalNodeIds = nodes
      .where(_workflowNodeHasConditionalBranches)
      .map((node) => node.id)
      .toSet();
  final owners = <String, WorkflowNode>{
    for (final node in nodes)
      for (final field in node.declaredParameterFields())
        if (workflowParameterNamePattern.hasMatch(field.name.trim()))
          field.name.trim(): node,
  };
  for (final target in nodes) {
    if (!scopes.containsKey(target.parentNodeId)) {
      return '节点“${_workflowNodeName(target)}”所属的工作流作用域无效，请将其移至有效容器。';
    }
    final localNames = _workflowLocalParameterNames(target, nodesById);
    for (final usage in _workflowParameterUsages(target)) {
      for (final reference in _workflowReferenceNames(usage)) {
        final name = reference.split('.').first;
        if (localNames.contains(name) || usage.localNames.contains(name)) {
          continue;
        }
        final source = owners[name];
        if (source == null) {
          return '节点“${_workflowNodeName(target)}”的${usage.label}引用了不存在的参数“$reference”。请改用可用参数，或在必经上游节点添加该参数。';
        }
        final availability = _workflowParameterAvailability(
          source: source,
          target: target,
          afterNestedScope: usage.afterNestedScope,
          nodesById: nodesById,
          scopes: scopes,
          conditionalNodeIds: conditionalNodeIds,
        );
        if (availability == _WorkflowParameterAvailability.available) {
          continue;
        }
        final sourceName = _workflowNodeName(source);
        return switch (availability) {
          _WorkflowParameterAvailability.notUpstream =>
            '节点“${_workflowNodeName(target)}”的${usage.label}引用了参数“$reference”，但来源节点“$sourceName”无法推进到当前节点。请恢复有效连线，或改用当前节点的上游参数。',
          _WorkflowParameterAvailability.notGuaranteed =>
            '节点“${_workflowNodeName(target)}”的${usage.label}引用了参数“$reference”，但来源节点“$sourceName”不是当前节点的必经上游，部分分支可能不会生成该参数。请将来源置于所有路径的共同上游，或在每个分支提供该参数。',
          _WorkflowParameterAvailability.invalidScope =>
            '节点“${_workflowNodeName(target)}”的${usage.label}引用了参数“$reference”，但来源节点“$sourceName”位于不可见的嵌套作用域。请改用当前作用域或其上游提供的参数。',
          _WorkflowParameterAvailability.available => '',
        };
      }
    }
  }
  return null;
}

enum _WorkflowParameterAvailability {
  available,
  notUpstream,
  notGuaranteed,
  invalidScope,
}

class _WorkflowParameterUsage {
  const _WorkflowParameterUsage({
    required this.value,
    required this.label,
    this.allowDirectReference = false,
    this.afterNestedScope = false,
    this.localNames = const <String>{},
  });

  final String value;
  final String label;
  final bool allowDirectReference;
  final bool afterNestedScope;
  final Set<String> localNames;
}

class _WorkflowParameterScope {
  _WorkflowParameterScope({
    required Iterable<String> nodeIds,
    required Iterable<String> entryNodeIds,
    required Iterable<WorkflowConnection> connections,
  }) : nodeIds = Set<String>.unmodifiable(nodeIds),
       entryNodeIds = Set<String>.unmodifiable(entryNodeIds),
       _outgoing = _buildOutgoing(connections);

  final Set<String> nodeIds;
  final Set<String> entryNodeIds;
  final Map<String, List<String>> _outgoing;

  /// 普通节点会激活全部出边，条件节点才会按结果选择单条分支。
  bool isGuaranteed(String targetId, Set<String> conditionalNodeIds) {
    if (!nodeIds.contains(targetId) || entryNodeIds.isEmpty) return false;
    final pending = <String>[...entryNodeIds];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      if (current == targetId) {
        return !conditionalNodeIds.contains(current);
      }
      if (conditionalNodeIds.contains(current)) continue;
      pending.addAll(_outgoing[current] ?? const <String>[]);
    }
    return false;
  }

  bool canReach(String sourceId, String targetId) {
    if (!nodeIds.contains(sourceId) || !nodeIds.contains(targetId)) {
      return false;
    }
    final pending = <String>[sourceId];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      if (current == targetId) return true;
      pending.addAll(_outgoing[current] ?? const <String>[]);
    }
    return false;
  }

  bool dominates(String sourceId, String targetId, {bool allowSame = false}) {
    if ((!allowSame && sourceId == targetId) ||
        entryNodeIds.isEmpty ||
        !entryNodeIds.any((entryId) => canReach(entryId, targetId)) ||
        !canReach(sourceId, targetId)) {
      return false;
    }
    final pending = <String>[
      for (final entry in entryNodeIds)
        if (entry != sourceId) entry,
    ];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      if (current == targetId) return false;
      for (final next in _outgoing[current] ?? const <String>[]) {
        if (next != sourceId) pending.add(next);
      }
    }
    return true;
  }

  bool dominatesEveryExit(String sourceId) {
    final exits = nodeIds
        .where((nodeId) => (_outgoing[nodeId] ?? const <String>[]).isEmpty)
        .toList(growable: false);
    return exits.isNotEmpty &&
        exits.every(
          (targetId) => dominates(sourceId, targetId, allowSame: true),
        );
  }

  static Map<String, List<String>> _buildOutgoing(
    Iterable<WorkflowConnection> connections,
  ) {
    final outgoing = <String, List<String>>{};
    for (final connection in connections) {
      (outgoing[connection.sourceNodeId] ??= <String>[]).add(
        connection.targetNodeId,
      );
    }
    return Map<String, List<String>>.unmodifiable(<String, List<String>>{
      for (final entry in outgoing.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
  }
}

Map<String?, _WorkflowParameterScope> _workflowParameterScopes(
  List<WorkflowNode> nodes,
  List<WorkflowConnection> connections,
) {
  final scopes = <String?, _WorkflowParameterScope>{};
  final topLevel = nodes
      .where((node) => node.parentNodeId == null)
      .toList(growable: false);
  final topLevelIds = topLevel.map((node) => node.id).toSet();
  scopes[null] = _WorkflowParameterScope(
    nodeIds: topLevelIds,
    entryNodeIds: topLevel
        .where((node) => node.kind == WorkflowNodeKind.start)
        .map((node) => node.id),
    connections: connections.where(
      (connection) =>
          topLevelIds.contains(connection.sourceNodeId) &&
          topLevelIds.contains(connection.targetNodeId) &&
          connection.sourceHandleId != workflowContainerStartHandleId,
    ),
  );
  for (final container in nodes.where((node) => node.isContainer)) {
    final children = nodes
        .where((node) => node.parentNodeId == container.id)
        .toList(growable: false);
    final childIds = children.map((node) => node.id).toSet();
    scopes[container.id] = _WorkflowParameterScope(
      nodeIds: childIds,
      entryNodeIds: connections
          .where(
            (connection) =>
                connection.sourceNodeId == container.id &&
                connection.sourceHandleId == workflowContainerStartHandleId &&
                childIds.contains(connection.targetNodeId),
          )
          .map((connection) => connection.targetNodeId),
      connections: connections.where(
        (connection) =>
            childIds.contains(connection.sourceNodeId) &&
            childIds.contains(connection.targetNodeId),
      ),
    );
  }
  return Map<String?, _WorkflowParameterScope>.unmodifiable(scopes);
}

_WorkflowParameterAvailability _workflowParameterAvailability({
  required WorkflowNode source,
  required WorkflowNode target,
  required bool afterNestedScope,
  required Map<String, WorkflowNode> nodesById,
  required Map<String?, _WorkflowParameterScope> scopes,
  required Set<String> conditionalNodeIds,
}) {
  if (source.parentNodeId == target.parentNodeId) {
    final scope = scopes[target.parentNodeId];
    if (scope == null) return _WorkflowParameterAvailability.invalidScope;
    if (source.id == target.id) {
      return _WorkflowParameterAvailability.notUpstream;
    }
    if (!scope.canReach(source.id, target.id)) {
      return _WorkflowParameterAvailability.notUpstream;
    }
    return (scope.isGuaranteed(source.id, conditionalNodeIds) ||
            scope.dominates(source.id, target.id))
        ? _WorkflowParameterAvailability.available
        : _WorkflowParameterAvailability.notGuaranteed;
  }
  if (afterNestedScope &&
      target.isContainer &&
      source.parentNodeId == target.id) {
    final scope = scopes[target.id];
    if (scope == null || !scope.canReach(source.id, source.id)) {
      return _WorkflowParameterAvailability.notUpstream;
    }
    return (scope.isGuaranteed(source.id, conditionalNodeIds) ||
            scope.dominatesEveryExit(source.id))
        ? _WorkflowParameterAvailability.available
        : _WorkflowParameterAvailability.notGuaranteed;
  }
  if (source.parentNodeId == null && target.parentNodeId != null) {
    final parent = nodesById[target.parentNodeId];
    final topLevel = scopes[null];
    if (parent == null || topLevel == null) {
      return _WorkflowParameterAvailability.invalidScope;
    }
    if (!topLevel.canReach(source.id, parent.id)) {
      return _WorkflowParameterAvailability.notUpstream;
    }
    return (topLevel.isGuaranteed(source.id, conditionalNodeIds) ||
            topLevel.dominates(source.id, parent.id))
        ? _WorkflowParameterAvailability.available
        : _WorkflowParameterAvailability.notGuaranteed;
  }
  return _WorkflowParameterAvailability.invalidScope;
}

Set<String> _workflowLocalParameterNames(
  WorkflowNode target,
  Map<String, WorkflowNode> nodesById,
) {
  final parent = target.parentNodeId == null
      ? null
      : nodesById[target.parentNodeId];
  if (parent?.kind == WorkflowNodeKind.iteration) {
    return const <String>{'item', 'index', 'length'};
  }
  if (parent?.kind == WorkflowNodeKind.loop) {
    return <String>{
      'loop_index',
      ...parent!.loopVariables().map((variable) => variable.name.trim()),
    };
  }
  return const <String>{};
}

List<_WorkflowParameterUsage> _workflowParameterUsages(WorkflowNode node) {
  final usages = <_WorkflowParameterUsage>[];
  void add(
    String value,
    String label, {
    bool allowDirectReference = false,
    bool afterNestedScope = false,
    Set<String> localNames = const <String>{},
  }) {
    if (value.trim().isEmpty) return;
    usages.add(
      _WorkflowParameterUsage(
        value: value,
        label: label,
        allowDirectReference: allowDirectReference,
        afterNestedScope: afterNestedScope,
        localNames: localNames,
      ),
    );
  }

  void addFields(List<WorkflowOutputField> fields, String fieldLabel) {
    for (final field in fields) {
      final name = field.name.trim();
      final label = name.isEmpty ? fieldLabel : '$fieldLabel“$name”';
      add(field.value, label);
      if (field.valueSource == WorkflowValueSource.variable) {
        add(field.defaultValue, label, allowDirectReference: true);
      }
    }
  }

  addFields(node.inputFields(), '输入参数');
  addFields(node.codeInputFields(), '代码输入参数');
  addFields(node.humanInputFields(), '人工输入参数');
  addFields(node.outputFields(), '输出参数');
  switch (node.kind) {
    case WorkflowNodeKind.llm:
      add(node.stringSetting(WorkflowSettingKeys.prompt), '提示词');
      add(node.stringSetting(WorkflowSettingKeys.inputContent), '输入内容');
    case WorkflowNodeKind.httpRequest:
      add(node.stringSetting(WorkflowSettingKeys.url), '请求地址');
      for (final entry in <WorkflowKeyValueEntry>[
        ...node.keyValueSetting(WorkflowSettingKeys.headers),
        ...node.keyValueSetting(WorkflowSettingKeys.queryParameters),
        ...node.keyValueSetting(WorkflowSettingKeys.bodyEntries),
      ]) {
        if (entry.valueSource == WorkflowValueSource.variable) {
          add(
            entry.value,
            '请求参数“${entry.key.trim()}”',
            allowDirectReference: true,
          );
        }
      }
      final format = WorkflowHttpBodyFormat.fromStorage(
        node.settings[WorkflowSettingKeys.bodyFormat],
      );
      if (format != WorkflowHttpBodyFormat.none && !format.usesFields) {
        add(node.stringSetting(WorkflowSettingKeys.body), '请求体');
      }
    case WorkflowNodeKind.condition:
      final cases = node.conditionCases();
      if (cases.isEmpty) {
        add(node.stringSetting(WorkflowSettingKeys.expression), '条件表达式');
      }
      for (final item in cases) {
        for (final condition in item.conditions) {
          add(condition.variable, '分支条件变量', allowDirectReference: true);
          if (condition.operator.requiresValue &&
              condition.valueSource == WorkflowValueSource.variable) {
            add(condition.value, '分支条件比较值', allowDirectReference: true);
          }
        }
      }
    case WorkflowNodeKind.listOperation:
      add(
        node.stringSetting(WorkflowSettingKeys.listInput),
        '数组输入',
        allowDirectReference: true,
      );
      if (node.boolSetting(WorkflowSettingKeys.listFilterEnabled) &&
          WorkflowValueSource.fromStorage(
                node.settings[WorkflowSettingKeys.listFilterValueSource],
                legacyValue: node.stringSetting(
                  WorkflowSettingKeys.listFilterValue,
                ),
              ) ==
              WorkflowValueSource.variable) {
        add(
          node.stringSetting(WorkflowSettingKeys.listFilterValue),
          '列表筛选比较值',
          allowDirectReference: true,
        );
      }
      if (node.boolSetting(WorkflowSettingKeys.listExtractEnabled)) {
        add(node.stringSetting(WorkflowSettingKeys.listExtractSerial), '提取序号');
      }
    case WorkflowNodeKind.loop:
      for (final variable in node.loopVariables()) {
        if (variable.valueSource == WorkflowValueSource.variable) {
          add(variable.initialValue, '循环变量“${variable.name.trim()}”');
        }
      }
      final localNames = <String>{
        'loop_index',
        ...node.loopVariables().map((variable) => variable.name.trim()),
      };
      for (final condition in node.loopBreakConditions()) {
        add(
          condition.variable,
          '循环退出条件变量',
          allowDirectReference: true,
          afterNestedScope: true,
          localNames: localNames,
        );
        if (condition.operator.requiresValue &&
            condition.valueSource == WorkflowValueSource.variable) {
          add(
            condition.value,
            '循环退出条件比较值',
            allowDirectReference: true,
            afterNestedScope: true,
            localNames: localNames,
          );
        }
      }
    case WorkflowNodeKind.iteration:
      add(
        node.stringSetting(WorkflowSettingKeys.iterationInput),
        '数组输入',
        allowDirectReference: true,
      );
      add(
        node.stringSetting(WorkflowSettingKeys.iterationOutput),
        '输出映射',
        afterNestedScope: true,
        localNames: const <String>{'item', 'index', 'length'},
      );
    case WorkflowNodeKind.humanIntervention:
      add(node.stringSetting(WorkflowSettingKeys.humanPrompt), '请求说明');
    case WorkflowNodeKind.start ||
        WorkflowNodeKind.parameterAssignment ||
        WorkflowNodeKind.codeExecution ||
        WorkflowNodeKind.loopExit ||
        WorkflowNodeKind.end:
      break;
  }
  return List<_WorkflowParameterUsage>.unmodifiable(usages);
}

Iterable<String> _workflowReferenceNames(_WorkflowParameterUsage usage) sync* {
  var foundTemplate = false;
  for (final match in workflowTemplatePlaceholderPattern.allMatches(
    usage.value,
  )) {
    foundTemplate = true;
    yield match.group(1)!;
  }
  if (!foundTemplate &&
      usage.allowDirectReference &&
      _workflowDirectReferencePattern.hasMatch(usage.value.trim())) {
    yield usage.value.trim();
  }
}

String _workflowNodeName(WorkflowNode node) =>
    node.title.trim().isEmpty ? '未命名节点' : node.title.trim();

bool _workflowNodeHasConditionalBranches(WorkflowNode node) {
  if (node.kind == WorkflowNodeKind.condition ||
      node.kind == WorkflowNodeKind.humanIntervention) {
    return true;
  }
  if (const <WorkflowNodeKind>{
    WorkflowNodeKind.codeExecution,
    WorkflowNodeKind.llm,
    WorkflowNodeKind.httpRequest,
  }.contains(node.kind)) {
    return WorkflowErrorStrategy.fromStorage(
          node.settings[WorkflowSettingKeys.errorStrategy],
        ) ==
        WorkflowErrorStrategy.failBranch;
  }
  return false;
}

String? validateWorkflowHumanActions(List<WorkflowHumanAction> actions) {
  if (actions.isEmpty) return '人工介入节点至少需要一个用户动作。';
  if (actions.length > maxWorkflowHumanActionCount) {
    return '人工介入节点最多支持 $maxWorkflowHumanActionCount 个用户动作。';
  }
  final ids = <String>{};
  for (var index = 0; index < actions.length; index++) {
    final action = actions[index];
    if (action.id == workflowHumanTimeoutHandleId) {
      return '用户动作标识“$workflowHumanTimeoutHandleId”已被超时分支保留。';
    }
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
    this.annotations = const <WorkflowAnnotation>[],
  });

  factory WorkflowDefinition.fromJson(Map<String, Object?> json) {
    final id = '${json['id'] ?? ''}'.trim();
    final name = '${json['name'] ?? ''}'.trim();
    final createdAt = DateTime.tryParse('${json['created_at'] ?? ''}')?.toUtc();
    final updatedAt = DateTime.tryParse('${json['updated_at'] ?? ''}')?.toUtc();
    if (id.isEmpty || name.isEmpty || createdAt == null || updatedAt == null) {
      throw const FormatException('工作流数据不完整。');
    }
    final nodes = normalizeWorkflowSystemOutputNames(
      _mapList(
        json['nodes'],
      ).map(WorkflowNode.fromJson).toList(growable: false),
    );
    final nodeIds = nodes.map((node) => node.id).toSet();
    if (nodeIds.length != nodes.length) {
      throw const FormatException('工作流包含重复节点。');
    }
    final nodesById = <String, WorkflowNode>{
      for (final node in nodes) node.id: node,
    };
    final annotationsValue = json['annotations'];
    if (annotationsValue != null && annotationsValue is! List) {
      throw const FormatException('工作流注释列表格式无效。');
    }
    if (annotationsValue is List &&
        annotationsValue.any((annotation) => annotation is! Map)) {
      throw const FormatException('工作流包含无效注释。');
    }
    final annotations = _mapList(
      annotationsValue,
    ).map(WorkflowAnnotation.fromJson).toList(growable: false);
    final annotationIds = annotations
        .map((annotation) => annotation.id)
        .toSet();
    if (annotationIds.length != annotations.length ||
        annotationIds.any(nodeIds.contains)) {
      throw const FormatException('工作流包含重复注释。');
    }
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
      annotations: List<WorkflowAnnotation>.unmodifiable(annotations),
    );
  }

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WorkflowNode> nodes;
  final List<WorkflowConnection> connections;
  final List<WorkflowAnnotation> annotations;

  WorkflowDefinition copyWith({
    String? name,
    DateTime? updatedAt,
    List<WorkflowNode>? nodes,
    List<WorkflowConnection>? connections,
    List<WorkflowAnnotation>? annotations,
  }) {
    return WorkflowDefinition(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      nodes: nodes ?? this.nodes,
      connections: connections ?? this.connections,
      annotations: annotations ?? this.annotations,
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
    'annotations': annotations
        .map((annotation) => annotation.toJson())
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

int? _nonNegativeInt(Object? value) {
  final parsed = value is int ? value : int.tryParse('$value');
  return parsed != null && parsed >= 0 ? parsed : null;
}
