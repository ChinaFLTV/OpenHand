import 'dart:convert';

import 'ai_protocol_adapter.dart';

class AiDsmlToolCallExtractionResult {
  const AiDsmlToolCallExtractionResult({
    required this.sanitizedText,
    required this.toolCalls,
    this.hasTrailingIncompleteMarkup = false,
  });

  final String sanitizedText;
  final List<AiToolCall> toolCalls;

  /// True when the input text contained an opening DSML/tool-call tag that
  /// was never closed — a strong signal that the model output was truncated
  /// mid–tool call.
  final bool hasTrailingIncompleteMarkup;
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
    // 2026-04-26: Fallback — when the model produced `<DSML:invoke ...>`
    // wrappers but populated parameters with raw `<key>value</whatever>`
    // tags (mismatched closing tags), salvage them by scanning the invoke
    // body for any open-tag/close-tag pair and treating the open-tag name
    // as the parameter key. This avoids surfacing useless `_raw` blobs
    // to downstream tools.
    if (arguments.isEmpty) {
      for (final loose in _looseInvokeBodyTagPattern.allMatches(body)) {
        final paramKey = (loose.group(1) ?? '').trim();
        if (paramKey.isEmpty ||
            paramKey.toLowerCase() == 'dsml:parameter') {
          continue;
        }
        final paramValue = _stripCdataWrappers(
          (loose.group(2) ?? '').trim(),
        );
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
  // Detect trailing incomplete DSML markup (opening tag without matching close).
  // This happens when the model output is truncated mid–tool call.
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

/// Matches an opening `<DSML:invoke` or `<DSML:function_calls` tag that
/// appears after the last successfully matched complete invoke block.
/// Presence of this pattern indicates the model was truncated mid–tool call.
final RegExp _trailingIncompleteDsmlPattern = RegExp(
  r'<DSML:(?:invoke|function_calls)\b',
  caseSensitive: false,
);

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
// 2026-04-26: Tolerant pattern for salvaging parameters whose closing
// tag does not match the opening tag (e.g. `<query>foo</path>`). Only
// used as a fallback inside an invoke body when the strict parameter
// extraction yielded nothing.
final RegExp _looseInvokeBodyTagPattern = RegExp(
  r'<\s*([A-Za-z_][\w:-]*)\s*>([\s\S]*?)</\s*[A-Za-z_][\w:-]*\s*>',
);
final RegExp _dsmlLooseTagPattern = RegExp(
  r'</?DSML:[^>]+>',
  caseSensitive: false,
);
final RegExp _dsmlAttributePattern = RegExp(
  r"""([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')""",
);

String _canonicalizeDsmlMarkup(String value) {
  var normalized = value
      .replaceAll('<｜DSML｜', '<DSML:')
      .replaceAll('</｜DSML｜', '</DSML:')
      .replaceAll('<｜dsml｜', '<DSML:')
      .replaceAll('</｜dsml｜', '</DSML:');
  normalized = normalized.replaceAllMapped(_dsmlTagPrefixPattern, (match) {
    final isClosing = (match.group(1) ?? '').trim().isNotEmpty;
    return isClosing ? '</DSML:' : '<DSML:';
  });
  // Canonicalize raw (non-DSML) function_calls / invoke / parameter tags that
  // low-intelligence models sometimes emit verbatim instead of using the DSML
  // prefix or producing proper protocol-native tool_calls.
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
  // Also canonicalize the antml variant used by some Claude-based models.
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
  return normalized;
}

// Raw function_calls/invoke/parameter tags (without any namespace prefix).
// Only match standalone XML element names — not already canonicalized DSML: forms.
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

// antml:function_calls / antml:invoke / antml:parameter variants.
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
  // 2026-04-26: strip <![CDATA[ ... ]]> wrappers up front. Some weaker
  // models emit CDATA inside DSML parameters which would otherwise be
  // treated as opaque text and confuse downstream tools.
  final unwrapped = _stripCdataWrappers(rawValue);
  final trimmed = unwrapped.trim();
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
