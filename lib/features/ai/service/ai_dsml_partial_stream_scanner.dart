import 'dart:convert';

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
  r'''(\w+)\s*=\s*("([^"]*)"|'([^']*)')''',
);

Map<String, String> _parseAttributes(String raw) {
  final out = <String, String>{};
  for (final m in _attrPattern.allMatches(raw)) {
    final key = m.group(1)!.toLowerCase();
    final value = m.group(3) ?? m.group(4) ?? '';
    out[key] = value;
  }
  return out;
}

/// Scan [buffer] for DSML invoke blocks, including a possibly-partial
/// trailing one. Cheap enough to call on every text delta.
///
/// The scanner only needs to detect `<DSML:invoke ...>` opens and parse the
/// `name=` attribute + any complete `<DSML:parameter ...>...</DSML:parameter>`
/// bodies seen so far. It does NOT do full canonicalization (no full-width
/// bracket variants, no `##TOOL_CALL##` envelope conversion); those edge
/// cases keep falling through to the post-stream extractor and will surface
/// as a brand-new card at stream end.
List<PartialDsmlInvoke> scanPartialDsmlInvokes(String buffer) {
  if (!buffer.contains('<DSML:invoke')) {
    return const <PartialDsmlInvoke>[];
  }
  final invokes = <PartialDsmlInvoke>[];
  var cursor = 0;
  var ordinal = 0;
  while (cursor < buffer.length) {
    final openMatch = _invokeOpenPattern.firstMatch(
      buffer.substring(cursor),
    );
    if (openMatch == null) {
      break;
    }
    final absoluteOpenStart = cursor + openMatch.start;
    final absoluteOpenEnd = cursor + openMatch.end;
    final attributes = _parseAttributes(openMatch.group(1) ?? '');
    final name = (attributes['name'] ?? '').trim();
    final closeMatch = _invokeClosePattern.firstMatch(
      buffer.substring(absoluteOpenEnd),
    );
    final body = closeMatch == null
        ? buffer.substring(absoluteOpenEnd)
        : buffer.substring(
            absoluteOpenEnd,
            absoluteOpenEnd + closeMatch.start,
          );
    final args = <String, Object?>{};
    for (final pm in _parameterPattern.allMatches(body)) {
      final pAttrs = _parseAttributes(pm.group(1) ?? '');
      final key = (pAttrs['name'] ?? '').trim();
      if (key.isEmpty) continue;
      args[key] = pm.group(2) ?? '';
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
    // Use absoluteOpenStart to keep analyzer happy about field unused.
    assert(absoluteOpenStart >= 0);
  }
  // Trailing "preparing" placeholder: if there is an unclosed
  // `<DSML:invoke` token after the last fully-scanned position AND no
  // partial invoke was already emitted for it (name still empty), emit a
  // sentinel preparing entry so the UI can show a generic card before
  // the tool name lands.
  final tail = buffer.substring(cursor);
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

/// Matches an opening `<DSML:invoke` whose `>` has not yet arrived. Used
/// to detect a fresh, name-less invoke at the tail of a streaming buffer.
final RegExp _unclosedInvokeOpenerPattern = RegExp(
  r'<DSML:invoke\b[^>]*$',
  caseSensitive: false,
);
