import 'dart:convert';

import 'ai_protocol_adapter.dart';

class AiDsmlToolCallExtractionResult {
  const AiDsmlToolCallExtractionResult({
    required this.sanitizedText,
    required this.toolCalls,
  });

  final String sanitizedText;
  final List<AiToolCall> toolCalls;
}

AiDsmlToolCallExtractionResult extractDsmlToolCalls(
  String value, {
  String toolCallIdPrefix = 'dsml-tool-call',
}) {
  final canonical = _canonicalizeDsmlMarkup(value);
  if (!canonical.contains('<DSML:')) {
    return AiDsmlToolCallExtractionResult(
      sanitizedText: value,
      toolCalls: const <AiToolCall>[],
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
      final treatAsString =
          (parameterAttributes['string'] ?? '').trim().toLowerCase() != 'false';
      arguments[parameterName] = _decodeDsmlParameterValue(
        parameterMatch.group(2) ?? '',
        treatAsString: treatAsString,
      );
    }
    toolCalls.add(
      AiToolCall(
        id: '$toolCallIdPrefix-${index + 1}',
        name: name,
        arguments: jsonEncode(arguments),
      ),
    );
  }
  return AiDsmlToolCallExtractionResult(
    sanitizedText: sanitizeVisibleDsmlContent(value),
    toolCalls: toolCalls,
  );
}

String sanitizeVisibleDsmlContent(String value) {
  final canonical = _canonicalizeDsmlMarkup(value);
  if (!canonical.contains('<DSML:')) {
    return value;
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
      .replaceAll(_excessiveNewlinePattern, '\n\n')
      .trim();
}

final RegExp _excessiveNewlinePattern = RegExp(r'\n{3,}');
final RegExp _dsmlTagPrefixPattern = RegExp(
  r'<\s*(/?)\s*[|｜]\s*DSML\s*[|｜]\s*',
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
final RegExp _dsmlLooseTagPattern = RegExp(
  r'</?DSML:[^>]+>',
  caseSensitive: false,
);
final RegExp _dsmlAttributePattern = RegExp(
  r"""([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')""",
);

String _canonicalizeDsmlMarkup(String value) {
  final normalized = value
      .replaceAll('<｜DSML｜', '<DSML:')
      .replaceAll('</｜DSML｜', '</DSML:')
      .replaceAll('<｜dsml｜', '<DSML:')
      .replaceAll('</｜dsml｜', '</DSML:');
  return normalized.replaceAllMapped(_dsmlTagPrefixPattern, (match) {
    final isClosing = (match.group(1) ?? '').trim().isNotEmpty;
    return isClosing ? '</DSML:' : '<DSML:';
  });
}

Map<String, String> _parseDsmlAttributes(String rawAttributes) {
  final attributes = <String, String>{};
  for (final match in _dsmlAttributePattern.allMatches(rawAttributes)) {
    final key = (match.group(1) ?? '').trim().toLowerCase();
    if (key.isEmpty) {
      continue;
    }
    attributes[key] = match.group(2) ?? match.group(3) ?? '';
  }
  return attributes;
}

Object? _decodeDsmlParameterValue(
  String rawValue, {
  required bool treatAsString,
}) {
  final trimmed = rawValue.trim();
  if (treatAsString) {
    return trimmed;
  }
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    final normalized = trimmed.toLowerCase();
    if (normalized == 'true' || normalized == 'false') {
      return normalized == 'true';
    }
    final numericValue = num.tryParse(trimmed);
    if (numericValue != null) {
      return numericValue;
    }
    return trimmed;
  }
}
