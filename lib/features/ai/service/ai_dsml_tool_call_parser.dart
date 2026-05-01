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
    // No tool-call markup at all — fast path, but still strip any leaked
    // ##TOOL_CALL## opening fragment that lacks a closing marker. Operate
    // on the converted form so we only strip true leftovers (the
    // converter has already deleted complete envelopes).
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
    return _stripDanglingHashTagToolCallMarker(
      _convertHashTagToolCalls(value),
    );
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

// 2026-05-03: widened to `[|｜]+` (was `[|｜]\s*` = exactly one) so we
// match doubled-pipe variants like `<｜｜DSML｜｜...>` emitted by some
// fine-tunes (observed: deepseek-style `<｜｜DSML｜｜tool_calls>`,
// `<｜｜DSML｜｜invoke name="…">`, `<｜｜DSML｜｜parameter …>`). Without
// this, canonicalization no-ops on the doubled form and the raw markup
// leaks straight into the user-visible bubble.
final RegExp _dsmlTagPrefixPattern = RegExp(
  r'<\s*(/?)\s*[|｜]+\s*DSML\s*[|｜]+\s*',
  caseSensitive: false,
);
// 2026-05-03: some models emit `<DSML:tool_calls>` instead of the
// canonical `<DSML:function_calls>`. Treat both as identical wrappers.
final RegExp _dsmlToolCallsAliasPattern = RegExp(
  r'<(/?)DSML:tool_calls\b([^>]*)>',
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
  // 2026-04-26: Some weaker models (notably ones that pretend to follow a
  // generic "agent" protocol they were trained on) emit tool calls inside
  // a `##TOOL_CALL## { "name": "...", "input": {...} } ##END_CALL##`
  // envelope instead of using protocol-native tool_calls or our DSML
  // tags. Convert these to canonical DSML *before* anything else so the
  // rest of the pipeline (extraction + sanitization) can swallow them.
  var normalized = _convertHashTagToolCalls(value);
  normalized = normalized
      .replaceAll('<｜DSML｜', '<DSML:')
      .replaceAll('</｜DSML｜', '</DSML:')
      .replaceAll('<｜dsml｜', '<DSML:')
      .replaceAll('</｜dsml｜', '</DSML:')
      // 2026-05-03: doubled fullwidth pipes (deepseek-style envelope).
      .replaceAll('<｜｜DSML｜｜', '<DSML:')
      .replaceAll('</｜｜DSML｜｜', '</DSML:')
      .replaceAll('<｜｜dsml｜｜', '<DSML:')
      .replaceAll('</｜｜dsml｜｜', '</DSML:');
  normalized = normalized.replaceAllMapped(_dsmlTagPrefixPattern, (match) {
    final isClosing = (match.group(1) ?? '').trim().isNotEmpty;
    return isClosing ? '</DSML:' : '<DSML:';
  });
  // 2026-05-03: `<DSML:tool_calls>` -> `<DSML:function_calls>` so the
  // downstream sanitizer / extractor treats it the same as the canonical
  // group wrapper.
  normalized = normalized.replaceAllMapped(_dsmlToolCallsAliasPattern, (m) {
    final slash = m.group(1) ?? '';
    return slash.isNotEmpty
        ? '</DSML:function_calls>'
        : '<DSML:function_calls>';
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

// 2026-04-26: Recognize the `##TOOL_CALL## ... ##END_CALL##` envelope that
// some weak models emit instead of native protocol tool calls or our DSML
// tags. Convert each well-formed envelope into a DSML invoke block so the
// downstream extractor + sanitizer treat it like any other tool call.
//
// Body shape we accept:
//   { "name": "<tool_name>", "input": { <key>: <value>, ... } }
// or  { "tool_name": "...", "parameters": {...} }
// or  { "name": "...", "arguments": {...} }
final RegExp _hashTagToolCallEnvelopePattern = RegExp(
  r'##\s*TOOL[_-]?CALL\s*##([\s\S]*?)##\s*END[_-]?CALL\s*##',
  caseSensitive: false,
);

// Matches a dangling `##TOOL_CALL## ...` opening with no `##END_CALL##`
// terminator (truncated stream / model dropped the closing marker).
// We strip from the opener through end-of-string to keep raw scaffolding
// out of the rendered bubble, mirroring `_trailingIncompleteDsmlPattern`.
final RegExp _hashTagToolCallDanglingPattern = RegExp(
  r'##\s*TOOL[_-]?CALL\s*##[\s\S]*$',
  caseSensitive: false,
);

String _convertHashTagToolCalls(String value) {
  if (!value.contains('##')) {
    return value;
  }
  if (!_hashTagToolCallEnvelopePattern.hasMatch(value)) {
    return value;
  }
  return value.replaceAllMapped(_hashTagToolCallEnvelopePattern, (match) {
    final raw = (match.group(1) ?? '').trim();
    if (raw.isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return '';
      }
      final name = '${decoded['name'] ?? decoded['tool_name'] ?? ''}'.trim();
      if (name.isEmpty) {
        return '';
      }
      final argsRaw = decoded['input'] ??
          decoded['arguments'] ??
          decoded['parameters'] ??
          decoded['args'];
      final argsMap = argsRaw is Map
          ? Map<String, Object?>.from(argsRaw)
          : <String, Object?>{};
      final buffer = StringBuffer()
        ..write('<DSML:invoke name="')
        ..write(_escapeDsmlAttributeValue(name))
        ..write('">');
      argsMap.forEach((key, val) {
        final encoded = val is String ? val : jsonEncode(val);
        buffer
          ..write('<DSML:parameter name="')
          ..write(_escapeDsmlAttributeValue(key))
          ..write('">')
          ..write(encoded)
          ..write('</DSML:parameter>');
      });
      buffer.write('</DSML:invoke>');
      return buffer.toString();
    } catch (_) {
      // Malformed JSON — drop the envelope entirely so it doesn't leak
      // raw scaffolding into the visible bubble. The model will be
      // re-prompted by the runtime when no tool call is dispatched.
      return '';
    }
  });
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
