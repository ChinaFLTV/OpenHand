import 'dart:convert';

import 'ai_dsml_tool_call_parser.dart'
    show
        canonicalizeDsmlMarkup,
        decodeDsmlParameterValue,
        dsmlParameterTreatsValueAsString;

/// Partial DSML invoke parsed from a still-streaming text buffer.
class PartialDsmlInvoke {
  const PartialDsmlInvoke({
    required this.index,
    required this.id,
    required this.name,
    required this.argumentsJson,
    required this.isComplete,
    this.isPreparing = false,
  });

  /// 0-based ordinal across the buffer. Matches `extractDsmlToolCalls`
  /// final ordering so post-stream IDs (`dsml-tool-call-${index+1}`) line
  /// up exactly between preview and committed messages.
  final int index;

  /// Stable ID matching the post-stream extraction: `dsml-tool-call-N`.
  final String id;

  final String name;

  /// JSON-encoded arguments object. May be partial if `isComplete` is
  /// false (only parameters parsed so far are included).
  final String argumentsJson;

  /// True once the closing `</DSML:invoke>` has been seen for this block.
  final bool isComplete;

  /// True when a `<DSML:invoke` opener has been observed but the closing
  /// `>` of the opening tag has not yet arrived — i.e. we don't even know
  /// the tool name yet. Used to render a generic "preparing" placeholder
  /// before the first real frame of state.
  final bool isPreparing;
}

final RegExp _invokeOpenPattern = RegExp(
  r'<DSML:invoke\b([^>]*)>',
  caseSensitive: false,
);
final RegExp _invokeClosePattern = RegExp(
  r'</DSML:invoke>',
  caseSensitive: false,
);
final RegExp _parameterPattern = RegExp(
  r'<DSML:parameter\b([^>]*)>([\s\S]*?)</DSML:parameter>',
  caseSensitive: false,
);
final RegExp _attrPattern = RegExp(
  r'''([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''',
);

Map<String, String> _parseAttributes(String raw) {
  final out = <String, String>{};
  for (final m in _attrPattern.allMatches(raw)) {
    final key = m.group(1)!.toLowerCase();
    final value = m.group(2) ?? m.group(3) ?? m.group(4) ?? '';
    out[key] = value;
  }
  return out;
}

/// Scan [buffer] for DSML invoke blocks, including a possibly-partial
/// trailing one. Cheap enough to call on every text delta.
///
/// now applies the same canonicalization the post-stream
/// extractor uses (`canonicalizeDsmlMarkup`) BEFORE scanning, so weak
/// fine-tunes that emit ASCII-pipe (`<|DSML|invoke …>`), fullwidth-pipe
/// (`<｜DSML｜invoke …>`), bracket-wrapped (`<<DSML>>`, `<【DSML】>`),
/// namespaced (`<functions.invoke …>`), antml-prefixed
/// (`<invoke …>`), or raw (`<invoke …>` / `<function_calls>`)
/// variants all surface as a partial preview card during streaming
/// instead of waiting for stream-end. The cheap `buffer.contains('DSML')`
/// (or raw `<invoke`) early-out keeps the hot path nearly free for
/// pure-text deltas.
List<PartialDsmlInvoke> scanPartialDsmlInvokes(String buffer) {
  // Cheap pre-filter: if the buffer cannot possibly contain a tool-call
  // marker we know about, skip canonicalization entirely.
  if (!_mayContainToolCallMarker(buffer)) {
    return const <PartialDsmlInvoke>[];
  }
  final canonical = canonicalizeDsmlMarkup(buffer);
  if (!canonical.contains('<DSML:invoke')) {
    return const <PartialDsmlInvoke>[];
  }
  final invokes = <PartialDsmlInvoke>[];
  var cursor = 0;
  var ordinal = 0;
  while (cursor < canonical.length) {
    final openMatch = _invokeOpenPattern.firstMatch(
      canonical.substring(cursor),
    );
    if (openMatch == null) {
      break;
    }
    final absoluteOpenEnd = cursor + openMatch.end;
    final attributes = _parseAttributes(openMatch.group(1) ?? '');
    final name = (attributes['name'] ?? '').trim();
    final closeMatch = _invokeClosePattern.firstMatch(
      canonical.substring(absoluteOpenEnd),
    );
    final body = closeMatch == null
        ? canonical.substring(absoluteOpenEnd)
        : canonical.substring(
            absoluteOpenEnd,
            absoluteOpenEnd + closeMatch.start,
          );
    final args = <String, Object?>{};
    for (final pm in _parameterPattern.allMatches(body)) {
      final pAttrs = _parseAttributes(pm.group(1) ?? '');
      final key = (pAttrs['name'] ?? '').trim();
      if (key.isEmpty) continue;
      args[key] = decodeDsmlParameterValue(
        pm.group(2) ?? '',
        treatAsString: dsmlParameterTreatsValueAsString(pAttrs),
      );
    }
    if (name.isNotEmpty) {
      ordinal += 1;
      invokes.add(
        PartialDsmlInvoke(
          index: ordinal - 1,
          id: 'dsml-tool-call-$ordinal',
          name: name,
          argumentsJson: jsonEncode(args),
          isComplete: closeMatch != null,
        ),
      );
    }
    if (closeMatch == null) {
      break; // trailing partial — nothing more to scan
    }
    cursor = absoluteOpenEnd + closeMatch.end;
  }
  // Trailing "preparing" placeholder: if there is an unclosed
  // `<DSML:invoke` token after the last fully-scanned position AND no
  // partial invoke was already emitted for it (name still empty), emit a
  // sentinel preparing entry so the UI can show a generic card before
  // the tool name lands.
  final tail = canonical.substring(cursor);
  if (_unclosedInvokeOpenerPattern.hasMatch(tail) &&
      (invokes.isEmpty || invokes.last.isComplete)) {
    final pendingOrdinal = ordinal + 1;
    invokes.add(
      PartialDsmlInvoke(
        index: pendingOrdinal - 1,
        id: 'dsml-tool-call-$pendingOrdinal',
        name: '',
        argumentsJson: '{}',
        isComplete: false,
        isPreparing: true,
      ),
    );
  }
  return invokes;
}

/// Cheap pre-filter to skip canonicalization on pure-text deltas.
///
/// Returns true if [buffer] *might* contain something the full
/// canonicalizer would normalize into a DSML invoke. Conservative:
/// false-positives are fine (we just pay one regex pass), but
/// false-negatives would silently drop the partial preview.
bool _mayContainToolCallMarker(String buffer) {
  final lower = buffer.toLowerCase();
  // Already-canonical form.
  if (lower.contains('<dsml:invoke')) return true;
  // Bracket-pipe wrappers (ASCII + fullwidth + doubled).
  if (lower.contains('<|dsml') ||
      lower.contains('<｜dsml') ||
      lower.contains('<｜｜dsml') ||
      lower.contains('<||dsml')) {
    return true;
  }
  // Bracket-style wrappers used by some weak fine-tunes.
  if (lower.contains('<<dsml') ||
      lower.contains('<【dsml') ||
      lower.contains('<《dsml') ||
      lower.contains('<[dsml') ||
      lower.contains('<「dsml') ||
      lower.contains('<『dsml')) {
    return true;
  }
  // Raw or namespaced invoke / function_calls openers.
  if (lower.contains('<invoke') ||
      lower.contains('<function_calls') ||
      lower.contains('<tool_calls') ||
      lower.contains('.invoke') ||
      lower.contains(':invoke')) {
    return true;
  }
  // JSON/YAML envelope variants recognized by the final extractor.
  if (lower.contains('##tool_call##') ||
      lower.contains('[tool_call]') ||
      lower.contains('[tool_use]') ||
      lower.contains('[openai_fn]') ||
      lower.contains('[function_call]') ||
      lower.contains('<tool_call') ||
      lower.contains('<tool_use') ||
      lower.contains('<function_call') ||
      lower.contains('<openai_fn') ||
      lower.contains('<fn_call') ||
      lower.contains('```tool') ||
      lower.contains('```dsml') ||
      lower.contains('```openai') ||
      lower.contains('tool_call:') ||
      lower.contains('tool_use:') ||
      lower.contains('function_call:') ||
      lower.contains('openai_fn:')) {
    return true;
  }
  return false;
}

/// Matches an opening `<DSML:invoke` whose `>` has not yet arrived. Used
/// to detect a fresh, name-less invoke at the tail of a streaming buffer.
final RegExp _unclosedInvokeOpenerPattern = RegExp(
  r'<DSML:invoke\b[^>]*$',
  caseSensitive: false,
);
