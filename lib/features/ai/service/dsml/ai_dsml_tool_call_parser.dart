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

  /// True when the input text contained an opening DSML/tool-call tag that
  /// was never closed — a strong signal that the model output was truncated
  /// mid–tool call.
  final bool hasTrailingIncompleteMarkup;
}

AiDsmlToolCallExtractionResult extractDsmlToolCalls(
  String value, {
  String toolCallIdPrefix = 'dsml-tool-call',
}) {
  final canonical = canonicalizeDsmlMarkup(value);
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
      arguments[parameterName] = decodeDsmlParameterValue(
        parameterMatch.group(2) ?? '',
        treatAsString: dsmlParameterTreatsValueAsString(parameterAttributes),
      );
    }
    // Fallback — when the model produced `<DSML:invoke ...>`
    // wrappers but populated parameters with raw `<key>value</whatever>`
    // tags (mismatched closing tags), salvage them by scanning the invoke
    // body for any open-tag/close-tag pair and treating the open-tag name
    // as the parameter key. This avoids surfacing useless `_raw` blobs
    // to downstream tools.
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

/// Matches an opening `<DSML:invoke` or `<DSML:function_calls` tag that
/// appears after the last successfully matched complete invoke block.
/// Presence of this pattern indicates the model was truncated mid–tool call.
final RegExp _trailingIncompleteDsmlPattern = RegExp(
  r'<DSML:(?:invoke|function_calls)\b',
  caseSensitive: false,
);

// widened to `[|｜]+` (was `[|｜]\s*` = exactly one) so we
// match doubled-pipe variants like `<｜｜DSML｜｜...>` emitted by some
// fine-tunes (observed: deepseek-style `<｜｜DSML｜｜tool_calls>`,
// `<｜｜DSML｜｜invoke name="…">`, `<｜｜DSML｜｜parameter …>`). Without
// this, canonicalization no-ops on the doubled form and the raw markup
// leaks straight into the user-visible bubble.
final RegExp _dsmlTagPrefixPattern = RegExp(
  r'<\s*(/?)\s*[|｜]+\s*DSML\s*[|｜]+\s*',
  caseSensitive: false,
);
// full-width / multi-bracket DSML wrappers used by some weak
// fine-tunes that don't produce protocol-native tool calls. Treat any
// run of bracket-like opening characters (`<<`, `[`, `(`, `《`, `【`,
// `「`, `『`, `〔`, `〘`) followed by `DSML` followed by closing
// brackets as our prefix. The text *after* the closing bracket (which
// may be `tool_calls`, `function_calls`, `invoke ...`, `parameter ...`)
// is preserved by the caller.
final RegExp _dsmlBracketWrapPattern = RegExp(
  r'<\s*(/?)\s*[\[(《【「『〔〘<]+\s*DSML\s*[\])》】」』〕〙>]+\s*',
  caseSensitive: false,
);
// some models emit `<DSML:tool_calls>` instead of the
// canonical `<DSML:function_calls>`. Treat both as identical wrappers.
final RegExp _dsmlToolCallsAliasPattern = RegExp(
  r'<(/?)DSML:tool_calls\b([^>]*)>',
  caseSensitive: false,
);
// namespace-prefixed invoke/function_calls/parameter tags.
// Covers `<functions.invoke …>`, `<tools.invoke …>`,
// `<openai.invoke …>`, `<anthropic:invoke …>` and the like — anything
// of the form `<{ns}{sep}{kind}>` where `kind` is one of our known
// kinds and `ns` is an arbitrary identifier (case-insensitive).
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
// Tolerant pattern for salvaging parameters whose closing
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
  // tolerate unquoted attribute values
  // (e.g. `<DSML:invoke name=Bash>`). Tries quoted forms first, then
  // a bareword fallback that stops at whitespace / `>`.
  r"""([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))""",
);

/// Public so streaming code paths (e.g.
/// `ai_dsml_partial_stream_scanner.dart`) can apply the same normalization
/// before scanning a still-growing buffer. All variants the post-stream
/// extractor handles — fullwidth pipes (`<｜DSML｜...>`), ASCII pipes
/// (`<|DSML|...>`), bracket wrappers (`<<DSML>>`, `<【DSML】>`),
/// namespaced (`<functions.invoke …>`, `<invoke …>`) and the
/// `##TOOL_CALL## … ##END_CALL##` envelope — are all canonicalized to
/// `<DSML:invoke …>` / `<DSML:parameter …>` / `<DSML:function_calls>`.
String canonicalizeDsmlMarkup(String value) => _canonicalizeDsmlMarkup(value);

String _canonicalizeDsmlMarkup(String value) {
  // Some weaker models (notably ones that pretend to follow a
  // generic "agent" protocol they were trained on) emit tool calls inside
  // a `##TOOL_CALL## { "name": "...", "input": {...} } ##END_CALL##`
  // envelope instead of using protocol-native tool_calls or our DSML
  // tags. Convert these to canonical DSML *before* anything else so the
  // rest of the pipeline (extraction + sanitization) can swallow them.
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
      // doubled fullwidth pipes (deepseek-style envelope).
      .replaceAll('<｜｜DSML｜｜', '<DSML:')
      .replaceAll('</｜｜DSML｜｜', '</DSML:')
      .replaceAll('<｜｜dsml｜｜', '<DSML:')
      .replaceAll('</｜｜dsml｜｜', '</DSML:');
  normalized = normalized.replaceAllMapped(_dsmlTagPrefixPattern, (match) {
    final isClosing = (match.group(1) ?? '').trim().isNotEmpty;
    return isClosing ? '</DSML:' : '<DSML:';
  });
  // full-width / multi-bracket DSML wrappers (e.g.
  // `<【DSML】invoke …>`, `《DSML》tool_calls`, `<<DSML>>parameter …>`).
  // Apply *before* the alias step so the suffix (`tool_calls`/etc.) is
  // already canonicalized to `DSML:`.
  normalized = normalized.replaceAllMapped(_dsmlBracketWrapPattern, (match) {
    final isClosing = (match.group(1) ?? '').trim().isNotEmpty;
    return isClosing ? '</DSML:' : '<DSML:';
  });
  // `<DSML:tool_calls>` -> `<DSML:function_calls>` so the
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
  // namespace-prefixed forms — `<functions.invoke …>`,
  // `<tools:invoke …>`, `<openai.parameter …>`, etc. — get folded into
  // canonical DSML so the same extractor / sanitizer pipeline applies.
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
  // sweep up stray pipe characters (`|` / `｜`) that some
  // weak fine-tunes leave between the last attribute (or element name)
  // and the closing `>` of *any* DSML tag — observed pattern is the
  // model wrapping every node in `<|DSML|name|>...</|DSML|name|>`. The
  // leading prefix already gets converted by `_dsmlTagPrefixPattern`,
  // but the trailing `|>` survives because the regex only consumes the
  // opener side. Without this sweep, `<DSML:parameter name="todos"|>`
  // / `</DSML:parameter|>` look malformed to the partial-stream scanner
  // (which expects `>` not `|>`), and tool-call cards stall in
  // "参数构造中" forever even after stream end.
  normalized = normalized.replaceAllMapped(_strayTrailingPipePattern, (m) {
    return '${m.group(1)}>';
  });
  return normalized;
}

final RegExp _directDsmlPrefixPattern = RegExp(
  r'<\s*(/?)\s*DSML\s*:\s*',
  caseSensitive: false,
);

// Match any DSML tag (open or close) that has one or more stray pipe
// characters immediately before the closing `>`. Capture everything up
// to (but excluding) the run of pipes so we can rewrite it as `…>`.
final RegExp _strayTrailingPipePattern = RegExp(
  r'(<\s*/?\s*DSML:[A-Za-z_][\w:.\-]*[^>|｜]*?)\s*[|｜]+\s*>',
  caseSensitive: false,
);

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
  // strip <![CDATA[ ... ]]> wrappers up front. Some weaker
  // models emit CDATA inside DSML parameters which would otherwise be
  // treated as opaque text and confuse downstream tools.
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

// Recognize the `##TOOL_CALL## ... ##END_CALL##` envelope that
// some weak models emit instead of native protocol tool calls or our DSML
// tags. Convert each well-formed envelope into a DSML invoke block so the
// downstream extractor + sanitizer treat it like any other tool call.
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

// additional JSON-envelope variants that surface in weaker
// model output. Each pattern's group(1) captures the JSON body.
//   - [TOOL_CALL] {...} [/TOOL_CALL]
//   - [OPENAI_FN] {...} [/OPENAI_FN]
//   - [TOOL_USE] {...} [/TOOL_USE]
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

// Tag-wrapped JSON: <tool>{...}</tool>, <tool_call>{...}</tool_call>,
// <function_call>{...}</function_call>, <openai_fn>{...}</openai_fn>,
// <tool_use>{...}</tool_use>. Conservative: requires a balanced opening
// and closing pair of the same name and a JSON object body.
final RegExp _tagWrappedJsonEnvelopePattern = RegExp(
  r'<\s*(tool_call|tool_use|tool|function_call|openai_fn|fn_call)\s*>\s*(\{[\s\S]*?\})\s*</\s*\1\s*>',
  caseSensitive: false,
);

// Code-fence envelope: ```dsml / ```tool_call / ```tool_use /
// ```openai_fn / ```function_call. We deliberately do NOT match
// generic ```json fences — that would clobber legitimate JSON the
// user is reading. Only fences whose info-string explicitly names a
// tool envelope kind get converted.
final RegExp _codeFenceEnvelopePattern = RegExp(
  r'```\s*(?:dsml|tool[_-]?call|tool[_-]?use|openai[_-]?fn|function[_-]?call)[^\n]*\n([\s\S]*?)```',
  caseSensitive: false,
);

// YAML code-fence envelope (```yaml ...```). Conservative:
// the body MUST contain a top-level `name:` / `tool_name:` /
// `function:` line; otherwise we leave the fence untouched (it's
// almost certainly the user's own YAML content). The actual decode +
// safety check happens in `_convertHashTagToolCalls`.
final RegExp _codeFenceYamlEnvelopePattern = RegExp(
  r'```\s*yaml[^\n]*\n([\s\S]*?)```',
  caseSensitive: false,
);
final RegExp _yamlEnvelopeNameKeyPattern = RegExp(
  r'^\s*(?:name|tool_name|function)\s*:',
  multiLine: true,
);

// multi-segment hash envelope —
//   ##invoke## name: Bash ##args## command: ls ##end##
// The body contains an `##args##` separator (case-insensitive). We
// rebuild it as YAML (`name: Bash\nargs:\n  command: ls`) and let the
// renderer's YAML fallback take over.
final RegExp _multiSegmentHashEnvelopePattern = RegExp(
  r'##\s*invoke\s*##([\s\S]*?)##\s*end\s*##',
  caseSensitive: false,
);
final RegExp _multiSegmentArgsSplitter = RegExp(
  r'##\s*(?:args|arguments|parameters|input)\s*##',
  caseSensitive: false,
);

// Line-prefix envelope: `TOOL_USE: {json}` / `OPENAI_FN: {json}` /
// `TOOL_CALL: {json}` at the start of a line (or after a newline).
// We capture a single brace-balanced JSON object that starts on the
// same line. Greedy `\{...\}` is unsafe; use a counted alternative.
final RegExp _linePrefixEnvelopePattern = RegExp(
  r'(?:^|\n)[ \t]*(?:TOOL[_-]?USE|OPENAI[_-]?FN|TOOL[_-]?CALL|FUNCTION[_-]?CALL)\s*[:=]\s*(\{[\s\S]*?\})(?=\s*(?:\n[ \t]*\n|\n[A-Za-z<#`]|$))',
  multiLine: true,
  caseSensitive: false,
);

String _convertHashTagToolCalls(String value) {
  // extended from `##TOOL_CALL##` only to a family of
  // envelope conventions emitted by weaker fine-tunes that haven't
  // learned protocol-native tool calls.
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
  // YAML fence — convert ONLY when the body looks like an
  // envelope (top-level `name`/`tool_name`/`function` key). Otherwise
  // leave the original fence verbatim so we don't clobber unrelated
  // YAML content.
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
  // multi-segment hash envelope (`##invoke## ... ##end##`).
  // Rebuild as YAML so the YAML fallback parser handles the body.
  if (current.contains('##invoke##') ||
      RegExp(r'##\s*invoke\s*##', caseSensitive: false).hasMatch(current)) {
    current = current.replaceAllMapped(_multiSegmentHashEnvelopePattern, (m) {
      final body = (m.group(1) ?? '').trim();
      if (body.isEmpty) return '';
      final yamlBody = _multiSegmentBodyToYaml(body);
      final dsml = _renderEnvelopeAsDsml(yamlBody);
      return dsml; // falls through to '' on parse failure
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

/// Convert a multi-segment-hash envelope body
/// (`name: Bash ##args## command: ls`) into canonical YAML
/// (`name: Bash\nargs:\n  command: ls`) so `_renderEnvelopeAsDsml`'s
/// YAML fallback can parse it.
String _multiSegmentBodyToYaml(String body) {
  final split = body.split(_multiSegmentArgsSplitter);
  if (split.length <= 1) {
    // No args section — emit the body as-is (likely just `name: Bash`).
    return body.trim();
  }
  final headPart = split.first.trim();
  final argsPart = split.skip(1).join('\n').trim();
  if (argsPart.isEmpty) {
    return headPart;
  }
  // Indent each non-empty line of argsPart by two spaces so YAML reads
  // it as a nested mapping under `args:`.
  final indented = argsPart
      .split(RegExp(r'\r?\n'))
      .map((line) => line.isEmpty ? '' : '  $line')
      .join('\n');
  return '$headPart\nargs:\n$indented';
}

/// Decode a JSON envelope body and emit it as canonical
/// `<DSML:invoke>...</DSML:invoke>` markup. Returns an empty string when
/// the body is unparseable or missing a tool name (so the scaffolding
/// is dropped from user-visible text rather than leaked).
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
  // fall back to YAML when JSON fails — covers YAML-shaped
  // envelopes (`name: Bash\nargs:\n  command: ls`) emitted by some
  // weaker fine-tunes. Only proceed when the YAML decode yields a Map
  // with a `name`/`tool_name`/`function` key (otherwise we'd silently
  // eat unrelated YAML content the user is showing).
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

/// Normalize fullwidth JSON punctuation (`"` `"` `'` `'` `：` `，` `｛` `｝`)
/// to ASCII so a `jsonDecode` first-pass can succeed. Conservative: only
/// touches characters that have a deterministic ASCII equivalent and
/// only inside contexts where the substitution can't break unicode
/// strings (we apply to the *whole* body — string content with
/// fullwidth quotes is already corrupted by the model and the
/// substitution is the user's intent).
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

/// `loadYaml` returns `YamlMap`/`YamlList` proxies; convert to a plain
/// `Map<String, Object?>` / `List<Object?>` tree so existing
/// `argsRaw is Map` checks succeed.
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
