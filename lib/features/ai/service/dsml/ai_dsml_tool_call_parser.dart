import 'dart:convert';

import 'package:openhand/shared/util/text_normalization.dart';
import 'package:yaml/yaml.dart';

import '../../../../shared/util/input_value_parsing.dart';
import '../chat/ai_protocol_adapter.dart';

class AiDsmlToolCallExtractionResult {
  const AiDsmlToolCallExtractionResult({
    required this.sanitizedText,
    required this.toolCalls,
    this.hasTrailingIncompleteMarkup = false,
  });

  final String sanitizedText;
  final List<AiToolCall> toolCalls;

  /// 是否存在未闭合的工具调用标记，通常表示模型输出被截断。
  final bool hasTrailingIncompleteMarkup;
}

AiDsmlToolCallExtractionResult extractDsmlToolCalls(
  String value, {
  String toolCallIdPrefix = 'dsml-tool-call',
}) {
  final canonical = canonicalizeDsmlMarkup(value);
  if (!canonical.contains('<DSML:')) {
    // 完整信封已被转换，仅清理剩余的未闭合工具调用标记。
    final converted = _convertHashTagToolCalls(value);
    final fastSanitized = _stripDanglingHashTagToolCallMarker(converted);
    return AiDsmlToolCallExtractionResult(
      sanitizedText: fastSanitized,
      toolCalls: const <AiToolCall>[],
      hasTrailingIncompleteMarkup: fastSanitized.length != converted.length,
    );
  }
  final toolCalls = <AiToolCall>[];
  final invokeMatches = _dsmlInvokePattern
      .allMatches(canonical)
      .toList(growable: false);
  for (var index = 0; index < invokeMatches.length; index += 1) {
    final match = invokeMatches[index];
    final attributes = _parseDsmlAttributes(match.group(1) ?? '');
    final name = (attributes['name'] ?? '').trim();
    if (name.isEmpty) {
      continue;
    }
    final arguments = <String, Object?>{};
    final body = match.group(2) ?? '';
    for (final parameterMatch in _dsmlParameterPattern.allMatches(body)) {
      final parameterAttributes = _parseDsmlAttributes(
        parameterMatch.group(1) ?? '',
      );
      final parameterName = (parameterAttributes['name'] ?? '').trim();
      if (parameterName.isEmpty) {
        continue;
      }
      arguments[parameterName] = decodeDsmlParameterValue(
        parameterMatch.group(2) ?? '',
        treatAsString: dsmlParameterTreatsValueAsString(parameterAttributes),
      );
    }
    // 兼容参数闭合标签错误的模型输出，避免向工具传递无意义的 `_raw` 数据。
    if (arguments.isEmpty) {
      for (final loose in _looseInvokeBodyTagPattern.allMatches(body)) {
        final paramKey = (loose.group(1) ?? '').trim();
        if (paramKey.isEmpty || paramKey.toLowerCase() == 'dsml:parameter') {
          continue;
        }
        final paramValue = _stripCdataWrappers((loose.group(2) ?? '').trim());
        arguments.putIfAbsent(paramKey, () => paramValue);
      }
    }
    toolCalls.add(
      AiToolCall(
        id: '$toolCallIdPrefix-${index + 1}',
        name: name,
        arguments: jsonEncode(arguments),
      ),
    );
  }
  // 检测流式输出末尾未闭合的 DSML 标记。
  final lastMatchEnd = invokeMatches.isEmpty ? 0 : invokeMatches.last.end;
  final remaining = canonical.substring(lastMatchEnd);
  final hasTrailingIncomplete = _trailingIncompleteDsmlPattern.hasMatch(
    remaining,
  );

  return AiDsmlToolCallExtractionResult(
    sanitizedText: sanitizeVisibleDsmlContent(value),
    toolCalls: toolCalls,
    hasTrailingIncompleteMarkup: hasTrailingIncomplete,
  );
}

String sanitizeVisibleDsmlContent(String value) {
  final canonical = canonicalizeDsmlMarkup(value);
  if (!canonical.contains('<DSML:')) {
    return _stripDanglingHashTagToolCallMarker(_convertHashTagToolCalls(value));
  }
  var sanitized = canonical
      .replaceAll(_dsmlFunctionCallsPattern, '')
      .replaceAll(_dsmlInvokePattern, '')
      .replaceAll(_dsmlLooseTagPattern, '');
  final trailingStartIndex = sanitized.indexOf('<DSML:');
  if (trailingStartIndex >= 0) {
    sanitized = sanitized.substring(0, trailingStartIndex);
  }
  return sanitized
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(kExcessiveNewlinesPattern, '\n\n')
      .trim();
}

/// 匹配最后一个完整调用后的未闭合 DSML 调用标记。
final RegExp _trailingIncompleteDsmlPattern = RegExp(
  r'<DSML:(?:invoke|function_calls)\b',
  caseSensitive: false,
);

// 同时兼容单、双竖线 DSML 前缀，避免原始标记泄漏到消息气泡。
final RegExp _dsmlTagPrefixPattern = RegExp(
  r'<\s*(/?)\s*[|｜]+\s*DSML\s*[|｜]+\s*',
  caseSensitive: false,
);
// 兼容弱模型生成的全角或多括号 DSML 外壳。
final RegExp _dsmlBracketWrapPattern = RegExp(
  r'<\s*(/?)\s*[\[(《【「『〔〘<]+\s*DSML\s*[\])》】」』〕〙>]+\s*',
  caseSensitive: false,
);
// 将 `<DSML:tool_calls>` 视为标准的 `<DSML:function_calls>`。
final RegExp _dsmlToolCallsAliasPattern = RegExp(
  r'<(/?)DSML:tool_calls\b([^>]*)>',
  caseSensitive: false,
);
// 兼容 functions、tools、openai 等命名空间前缀。
final RegExp _namespacedInvokePattern = RegExp(
  r'<\s*(/?)\s*[A-Za-z_][\w-]*\s*[.:]\s*invoke\b([^>]*)>',
  caseSensitive: false,
);
final RegExp _namespacedFunctionCallsPattern = RegExp(
  r'<\s*(/?)\s*[A-Za-z_][\w-]*\s*[.:]\s*(?:function_calls|tool_calls)\s*>',
  caseSensitive: false,
);
final RegExp _namespacedParameterPattern = RegExp(
  r'<\s*(/?)\s*[A-Za-z_][\w-]*\s*[.:]\s*parameter\b([^>]*)>',
  caseSensitive: false,
);
final RegExp _dsmlFunctionCallsPattern = RegExp(
  r'<DSML:function_calls\b[^>]*>[\s\S]*?</DSML:function_calls>',
  caseSensitive: false,
);
final RegExp _dsmlInvokePattern = RegExp(
  r'<DSML:invoke\b([^>]*)>([\s\S]*?)</DSML:invoke>',
  caseSensitive: false,
);
final RegExp _dsmlParameterPattern = RegExp(
  r'<DSML:parameter\b([^>]*)>([\s\S]*?)</DSML:parameter>',
  caseSensitive: false,
);
// 严格解析无结果时，兜底提取闭合标签名称不一致的参数。
final RegExp _looseInvokeBodyTagPattern = RegExp(
  r'<\s*([A-Za-z_][\w:-]*)\s*>([\s\S]*?)</\s*[A-Za-z_][\w:-]*\s*>',
);
final RegExp _dsmlLooseTagPattern = RegExp(
  r'</?DSML:[^>]+>',
  caseSensitive: false,
);
final RegExp _dsmlAttributePattern = RegExp(
  // 优先匹配引号值，同时兼容未加引号的属性。
  r"""([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))""",
);

/// 将竖线、括号、命名空间及哈希信封等变体统一为标准 DSML，供流式与完整解析复用。
String canonicalizeDsmlMarkup(String value) => _canonicalizeDsmlMarkup(value);

String _canonicalizeDsmlMarkup(String value) {
  // 先转换哈希信封，后续解析和清理只处理标准 DSML。
  var normalized = _convertHashTagToolCalls(value);
  normalized = normalized.replaceAllMapped(_directDsmlPrefixPattern, (match) {
    final isClosing = (match.group(1) ?? '').trim().isNotEmpty;
    return isClosing ? '</DSML:' : '<DSML:';
  });
  normalized = normalized
      .replaceAll('<｜DSML｜', '<DSML:')
      .replaceAll('</｜DSML｜', '</DSML:')
      .replaceAll('<｜dsml｜', '<DSML:')
      .replaceAll('</｜dsml｜', '</DSML:')
      // 兼容双全角竖线信封。
      .replaceAll('<｜｜DSML｜｜', '<DSML:')
      .replaceAll('</｜｜DSML｜｜', '</DSML:')
      .replaceAll('<｜｜dsml｜｜', '<DSML:')
      .replaceAll('</｜｜dsml｜｜', '</DSML:');
  normalized = normalized.replaceAllMapped(_dsmlTagPrefixPattern, (match) {
    final isClosing = (match.group(1) ?? '').trim().isNotEmpty;
    return isClosing ? '</DSML:' : '<DSML:';
  });
  // 先规范括号外壳，再处理工具调用别名。
  normalized = normalized.replaceAllMapped(_dsmlBracketWrapPattern, (match) {
    final isClosing = (match.group(1) ?? '').trim().isNotEmpty;
    return isClosing ? '</DSML:' : '<DSML:';
  });
  normalized = normalized.replaceAllMapped(_dsmlToolCallsAliasPattern, (m) {
    final slash = m.group(1) ?? '';
    return slash.isNotEmpty
        ? '</DSML:function_calls>'
        : '<DSML:function_calls>';
  });
  // 规范缺少 DSML 前缀的原始调用标签。
  normalized = normalized
      .replaceAllMapped(_rawFunctionCallsTagPattern, (m) {
        final slash = m.group(1) ?? '';
        return slash.isNotEmpty
            ? '</DSML:function_calls>'
            : '<DSML:function_calls>';
      })
      .replaceAllMapped(_rawInvokeTagPattern, (m) {
        final slash = m.group(1) ?? '';
        final attrs = m.group(2) ?? '';
        return slash.isNotEmpty ? '</DSML:invoke>' : '<DSML:invoke$attrs>';
      })
      .replaceAllMapped(_rawParameterTagPattern, (m) {
        final slash = m.group(1) ?? '';
        final attrs = m.group(2) ?? '';
        return slash.isNotEmpty
            ? '</DSML:parameter>'
            : '<DSML:parameter$attrs>';
      });
  // 规范部分 Claude 模型使用的 antml 变体。
  normalized = normalized
      .replaceAllMapped(_antmlFunctionCallsTagPattern, (m) {
        final slash = m.group(1) ?? '';
        return slash.isNotEmpty
            ? '</DSML:function_calls>'
            : '<DSML:function_calls>';
      })
      .replaceAllMapped(_antmlInvokeTagPattern, (m) {
        final slash = m.group(1) ?? '';
        final attrs = m.group(2) ?? '';
        return slash.isNotEmpty ? '</DSML:invoke>' : '<DSML:invoke$attrs>';
      })
      .replaceAllMapped(_antmlParameterTagPattern, (m) {
        final slash = m.group(1) ?? '';
        final attrs = m.group(2) ?? '';
        return slash.isNotEmpty
            ? '</DSML:parameter>'
            : '<DSML:parameter$attrs>';
      });
  // 将带命名空间的标签并入同一解析流程。
  normalized = normalized
      .replaceAllMapped(_namespacedFunctionCallsPattern, (m) {
        final slash = m.group(1) ?? '';
        return slash.isNotEmpty
            ? '</DSML:function_calls>'
            : '<DSML:function_calls>';
      })
      .replaceAllMapped(_namespacedInvokePattern, (m) {
        final slash = m.group(1) ?? '';
        final attrs = m.group(2) ?? '';
        return slash.isNotEmpty ? '</DSML:invoke>' : '<DSML:invoke$attrs>';
      })
      .replaceAllMapped(_namespacedParameterPattern, (m) {
        final slash = m.group(1) ?? '';
        final attrs = m.group(2) ?? '';
        return slash.isNotEmpty
            ? '</DSML:parameter>'
            : '<DSML:parameter$attrs>';
      });
  // 清理闭合尖括号前残留的竖线，避免流式扫描器一直等待参数结束。
  normalized = normalized.replaceAllMapped(_strayTrailingPipePattern, (m) {
    return '${m.group(1)}>';
  });
  return normalized;
}

final RegExp _directDsmlPrefixPattern = RegExp(
  r'<\s*(/?)\s*DSML\s*:\s*',
  caseSensitive: false,
);

// 捕获闭合尖括号前带多余竖线的 DSML 标签。
final RegExp _strayTrailingPipePattern = RegExp(
  r'(<\s*/?\s*DSML:[A-Za-z_][\w:.\-]*[^>|｜]*?)\s*[|｜]+\s*>',
  caseSensitive: false,
);

// 仅匹配无命名空间且尚未规范化的原始调用标签。
final RegExp _rawFunctionCallsTagPattern = RegExp(
  r'<\s*(/?)\s*function_calls\s*>',
  caseSensitive: false,
);
final RegExp _rawInvokeTagPattern = RegExp(
  r'<\s*(/?)\s*invoke\b([^>]*)>',
  caseSensitive: false,
);
final RegExp _rawParameterTagPattern = RegExp(
  r'<\s*(/?)\s*parameter\b([^>]*)>',
  caseSensitive: false,
);

// antml 调用标签变体。
final RegExp _antmlFunctionCallsTagPattern = RegExp(
  r'<\s*(/?)\s*antml:function_calls\s*>',
  caseSensitive: false,
);
final RegExp _antmlInvokeTagPattern = RegExp(
  r'<\s*(/?)\s*antml:invoke\b([^>]*)>',
  caseSensitive: false,
);
final RegExp _antmlParameterTagPattern = RegExp(
  r'<\s*(/?)\s*antml:parameter\b([^>]*)>',
  caseSensitive: false,
);

Map<String, String> _parseDsmlAttributes(String rawAttributes) {
  final attributes = <String, String>{};
  for (final match in _dsmlAttributePattern.allMatches(rawAttributes)) {
    final key = lowercaseStringFromValue(match.group(1));
    if (key.isEmpty) {
      continue;
    }
    attributes[key] = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
  }
  return attributes;
}

bool dsmlParameterTreatsValueAsString(Map<String, String> attributes) {
  return boolFromValue(attributes['string'], defaultValue: true);
}

Object? decodeDsmlParameterValue(
  String rawValue, {
  required bool treatAsString,
}) {
  // 先移除 CDATA 外壳，避免下游工具收到不透明文本。
  final unwrapped = _stripCdataWrappers(rawValue);
  final trimmed = unwrapped.trim();
  if (treatAsString) {
    final cdataOnlyRemainder = rawValue.replaceAll(_cdataPattern, '').trim();
    if (cdataOnlyRemainder.isEmpty && _cdataPattern.hasMatch(rawValue)) {
      return _cdataPattern
          .allMatches(rawValue)
          .map((match) => match.group(1) ?? '')
          .join();
    }
    return trimmed;
  }

  if (trimmed.isEmpty) {
    return null;
  }
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    final boolValue = optionalBoolFromValue(trimmed);
    if (boolValue != null) return boolValue;
    final numericValue = num.tryParse(trimmed);
    if (numericValue != null) {
      return numericValue;
    }
    return trimmed;
  }
}

final RegExp _cdataPattern = RegExp(
  r'<!\[CDATA\[([\s\S]*?)\]\]>',
  caseSensitive: false,
);

String _stripCdataWrappers(String value) {
  if (!value.contains('<![CDATA[') && !value.contains('<![cdata[')) {
    return value;
  }
  return value.replaceAllMapped(_cdataPattern, (m) => m.group(1) ?? '');
}

// 识别哈希工具调用信封，并转换为标准 DSML 调用块。
final RegExp _hashTagToolCallEnvelopePattern = RegExp(
  r'##\s*TOOL[_-]?CALL\s*##([\s\S]*?)##\s*END[_-]?CALL\s*##',
  caseSensitive: false,
);

// 匹配流式输出中缺少结束标记的哈希工具调用。
final RegExp _hashTagToolCallDanglingPattern = RegExp(
  r'##\s*TOOL[_-]?CALL\s*##[\s\S]*$',
  caseSensitive: false,
);

// 兼容方括号包裹的 JSON 工具调用信封。
final List<RegExp> _bracketEnvelopePatterns = <RegExp>[
  RegExp(
    r'\[\s*TOOL[_-]?CALL\s*\]([\s\S]*?)\[\s*/\s*TOOL[_-]?CALL\s*\]',
    caseSensitive: false,
  ),
  RegExp(
    r'\[\s*OPENAI[_-]?FN\s*\]([\s\S]*?)\[\s*/\s*OPENAI[_-]?FN\s*\]',
    caseSensitive: false,
  ),
  RegExp(
    r'\[\s*TOOL[_-]?USE\s*\]([\s\S]*?)\[\s*/\s*TOOL[_-]?USE\s*\]',
    caseSensitive: false,
  ),
  RegExp(
    r'\[\s*FUNCTION[_-]?CALL\s*\]([\s\S]*?)\[\s*/\s*FUNCTION[_-]?CALL\s*\]',
    caseSensitive: false,
  ),
];

// 仅转换标签成对且正文为 JSON 对象的工具调用信封。
final RegExp _tagWrappedJsonEnvelopePattern = RegExp(
  r'<\s*(tool_call|tool_use|tool|function_call|openai_fn|fn_call)\s*>\s*(\{[\s\S]*?\})\s*</\s*\1\s*>',
  caseSensitive: false,
);

// 仅转换明确标记为工具调用的代码块，保留普通 JSON 代码块。
final RegExp _codeFenceEnvelopePattern = RegExp(
  r'```\s*(?:dsml|tool[_-]?call|tool[_-]?use|openai[_-]?fn|function[_-]?call)[^\n]*\n([\s\S]*?)```',
  caseSensitive: false,
);

// YAML 代码块必须包含顶层工具名称，防止误改用户内容。
final RegExp _codeFenceYamlEnvelopePattern = RegExp(
  r'```\s*yaml[^\n]*\n([\s\S]*?)```',
  caseSensitive: false,
);
final RegExp _yamlEnvelopeNameKeyPattern = RegExp(
  r'^\s*(?:name|tool_name|function)\s*:',
  multiLine: true,
);

// 将多段哈希信封重组为 YAML 后交给统一渲染逻辑。
final RegExp _multiSegmentHashEnvelopePattern = RegExp(
  r'##\s*invoke\s*##([\s\S]*?)##\s*end\s*##',
  caseSensitive: false,
);
final RegExp _multiSegmentArgsSplitter = RegExp(
  r'##\s*(?:args|arguments|parameters|input)\s*##',
  caseSensitive: false,
);

// 匹配行首工具调用前缀及其单个 JSON 对象。
final RegExp _linePrefixEnvelopePattern = RegExp(
  r'(?:^|\n)[ \t]*(?:TOOL[_-]?USE|OPENAI[_-]?FN|TOOL[_-]?CALL|FUNCTION[_-]?CALL)\s*[:=]\s*(\{[\s\S]*?\})(?=\s*(?:\n[ \t]*\n|\n[A-Za-z<#`]|$))',
  multiLine: true,
  caseSensitive: false,
);

String _convertHashTagToolCalls(String value) {
  var current = value;
  if (current.contains('##') &&
      _hashTagToolCallEnvelopePattern.hasMatch(current)) {
    current = current.replaceAllMapped(
      _hashTagToolCallEnvelopePattern,
      (m) => _renderEnvelopeAsDsml(m.group(1) ?? ''),
    );
  }
  if (current.contains('[')) {
    for (final pattern in _bracketEnvelopePatterns) {
      if (pattern.hasMatch(current)) {
        current = current.replaceAllMapped(
          pattern,
          (m) => _renderEnvelopeAsDsml(m.group(1) ?? ''),
        );
      }
    }
  }
  if (current.contains('<') &&
      _tagWrappedJsonEnvelopePattern.hasMatch(current)) {
    current = current.replaceAllMapped(
      _tagWrappedJsonEnvelopePattern,
      (m) => _renderEnvelopeAsDsml(m.group(2) ?? ''),
    );
  }
  if (current.contains('```') && _codeFenceEnvelopePattern.hasMatch(current)) {
    current = current.replaceAllMapped(
      _codeFenceEnvelopePattern,
      (m) => _renderEnvelopeAsDsml(m.group(1) ?? ''),
    );
  }
  // 仅转换含顶层工具名称的 YAML 信封。
  if (current.contains('```') &&
      _codeFenceYamlEnvelopePattern.hasMatch(current)) {
    current = current.replaceAllMapped(_codeFenceYamlEnvelopePattern, (m) {
      final body = m.group(1) ?? '';
      if (!_yamlEnvelopeNameKeyPattern.hasMatch(body)) {
        return m.group(0)!;
      }
      final dsml = _renderEnvelopeAsDsml(body);
      return dsml.isEmpty ? m.group(0)! : dsml;
    });
  }
  // 多段哈希信封先重组为 YAML。
  if (current.contains('##invoke##') ||
      RegExp(r'##\s*invoke\s*##', caseSensitive: false).hasMatch(current)) {
    current = current.replaceAllMapped(_multiSegmentHashEnvelopePattern, (m) {
      final body = (m.group(1) ?? '').trim();
      if (body.isEmpty) return '';
      final yamlBody = _multiSegmentBodyToYaml(body);
      final dsml = _renderEnvelopeAsDsml(yamlBody);
      return dsml;
    });
  }
  if (current.contains(':') || current.contains('=')) {
    if (_linePrefixEnvelopePattern.hasMatch(current)) {
      current = current.replaceAllMapped(
        _linePrefixEnvelopePattern,
        (m) => '\n${_renderEnvelopeAsDsml(m.group(1) ?? '')}',
      );
    }
  }
  return current;
}

/// 将多段哈希信封转换为标准 YAML。
String _multiSegmentBodyToYaml(String body) {
  final split = body.split(_multiSegmentArgsSplitter);
  if (split.length <= 1) {
    return body.trim();
  }
  final headPart = split.first.trim();
  final argsPart = split.skip(1).join('\n').trim();
  if (argsPart.isEmpty) {
    return headPart;
  }
  // 参数缩进两格，作为 `args` 的嵌套映射。
  final indented = argsPart
      .split(RegExp(r'\r?\n'))
      .map((line) => line.isEmpty ? '' : '  $line')
      .join('\n');
  return '$headPart\nargs:\n$indented';
}

/// 将 JSON 或 YAML 信封转换为标准 DSML；无效信封返回空字符串。
String _renderEnvelopeAsDsml(String rawBody) {
  final raw = _normalizeFullwidthJsonPunctuation(rawBody.trim());
  if (raw.isEmpty) {
    return '';
  }
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    decoded = null;
  }
  // JSON 解析失败时尝试 YAML，后续仍校验映射结构和工具名称。
  if (decoded == null) {
    try {
      final yamlValue = loadYaml(raw);
      decoded = _coerceYamlToPlain(yamlValue);
    } catch (_) {
      decoded = null;
    }
  }
  if (decoded is! Map) {
    return '';
  }
  final name =
      '${decoded['name'] ?? decoded['tool_name'] ?? decoded['function'] ?? ''}'
          .trim();
  if (name.isEmpty) {
    return '';
  }
  final argsRaw =
      decoded['input'] ??
      decoded['arguments'] ??
      decoded['parameters'] ??
      decoded['args'] ??
      decoded['inputs'];
  final argsMap = stringKeyedMapFromValue(argsRaw);
  final buffer = StringBuffer()
    ..write('<DSML:invoke name="')
    ..write(_escapeDsmlAttributeValue(name))
    ..write('">');
  argsMap.forEach((key, val) {
    final isString = val is String;
    final encoded = isString
        ? _renderCdataValue(val)
        : _jsonEncodeForDsmlParameter(val);
    buffer
      ..write('<DSML:parameter name="')
      ..write(_escapeDsmlAttributeValue(key))
      ..write('"');
    if (!isString) {
      buffer.write(' string="false"');
    }
    buffer
      ..write('>')
      ..write(encoded)
      ..write('</DSML:parameter>');
  });
  buffer.write('</DSML:invoke>');
  return buffer.toString();
}

String _renderCdataValue(String value) {
  if (value.isEmpty) return '';
  return '<![CDATA[${value.replaceAll(']]>', ']]]]><![CDATA[>')}]]>';
}

String _jsonEncodeForDsmlParameter(Object? value) {
  return jsonEncode(
    value,
  ).replaceAll('<', r'\u003C').replaceAll('>', r'\u003E');
}

/// 将具有确定对应关系的全角 JSON 标点转换为半角字符。
String _normalizeFullwidthJsonPunctuation(String value) {
  if (value.isEmpty) return value;
  return value
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('„', '"')
      .replaceAll('‟', '"')
      .replaceAll('＂', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('＇', "'")
      .replaceAll('：', ':')
      .replaceAll('，', ',')
      .replaceAll('｛', '{')
      .replaceAll('｝', '}')
      .replaceAll('［', '[')
      .replaceAll('］', ']');
}

/// 将 YAML 代理对象递归转换为普通 Map/List。
Object? _coerceYamlToPlain(Object? value) {
  if (value is YamlMap) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _coerceYamlToPlain(entry.value),
    };
  }
  if (value is YamlList) {
    return <Object?>[for (final item in value) _coerceYamlToPlain(item)];
  }
  return value;
}

String _escapeDsmlAttributeValue(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String _stripDanglingHashTagToolCallMarker(String value) {
  if (!value.contains('##')) {
    return value;
  }
  if (!_hashTagToolCallDanglingPattern.hasMatch(value)) {
    return value;
  }
  return value.replaceAll(_hashTagToolCallDanglingPattern, '').trimRight();
}
