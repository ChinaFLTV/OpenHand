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
    // 用带起始下标的 allMatches 而不是先 substring 再 firstMatch：后者每轮
    // 都要整尾拷贝一次，在长回复上叠成 O(n²)。allMatches 是惰性的，取 first
    // 就会在命中后停止扫描。
    final openMatch = _firstMatchFrom(_invokeOpenPattern, canonical, cursor);
    if (openMatch == null) {
      break;
    }
    final absoluteOpenEnd = openMatch.end;
    final attributes = _parseAttributes(openMatch.group(1) ?? '');
    final name = (attributes['name'] ?? '').trim();
    final closeMatch = _firstMatchFrom(
      _invokeClosePattern,
      canonical,
      absoluteOpenEnd,
    );
    final body = closeMatch == null
        ? canonical.substring(absoluteOpenEnd)
        : canonical.substring(absoluteOpenEnd, closeMatch.start);
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
    cursor = closeMatch.end;
  }
  // Trailing "preparing" placeholder: if there is an unclosed
  // `<DSML:invoke` token after the last fully-scanned position AND no
  // partial invoke was already emitted for it (name still empty), emit a
  // sentinel preparing entry so the UI can show a generic card before
  // the tool name lands.
  if (_firstMatchFrom(_unclosedInvokeOpenerPattern, canonical, cursor) !=
          null &&
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
  for (var index = 0; index < buffer.length; index++) {
    final needles = _markerNeedlesByLeadChar[_asciiLower(
      buffer.codeUnitAt(index),
    )];
    if (needles == null) continue;
    for (final needle in needles) {
      if (_matchesIgnoreCaseAt(buffer, index, needle)) return true;
    }
  }
  return false;
}

/// 所有标记按首字符分桶。热路径逐字符扫描一次，只在首字符命中时才逐个比对
/// 同桶内的候选，全程零分配。
///
/// 此前的实现是 `buffer.toLowerCase()` 后再跑 30 次 contains——每个 text
/// delta 都要把**整个累积缓冲**复制一份，长回复上叠成 O(n²) 的分配与拷贝，
/// 而这个函数正是为了让纯文本 delta「几乎免费」才存在的。
final Map<int, List<String>> _markerNeedlesByLeadChar = _groupNeedlesByLeadChar(
  const <String>[
    // Already-canonical form.
    '<dsml:invoke',
    // Bracket-pipe wrappers (ASCII + fullwidth + doubled).
    '<|dsml', '<｜dsml', '<｜｜dsml', '<||dsml',
    // Bracket-style wrappers used by some weak fine-tunes.
    '<<dsml', '<【dsml', '<《dsml', '<[dsml', '<「dsml', '<『dsml',
    // Raw or namespaced invoke / function_calls openers.
    '<invoke', '<function_calls', '<tool_calls', '.invoke', ':invoke',
    // JSON/YAML envelope variants recognized by the final extractor.
    '##tool_call##', '[tool_call]', '[tool_use]', '[openai_fn]',
    '[function_call]', '<tool_call', '<tool_use', '<function_call',
    '<openai_fn', '<fn_call', '```tool', '```dsml', '```openai',
    'tool_call:', 'tool_use:', 'function_call:', 'openai_fn:',
  ],
);

Map<int, List<String>> _groupNeedlesByLeadChar(List<String> needles) {
  final grouped = <int, List<String>>{};
  for (final needle in needles) {
    grouped
        .putIfAbsent(_asciiLower(needle.codeUnitAt(0)), () => <String>[])
        .add(needle);
  }
  return grouped;
}

/// 只折叠 'A'..'Z'。标记本身全是 ASCII 或按原样比较的全角标点，因此与
/// `toLowerCase()` 的差异仅限于同形异码点（如开尔文符号 U+212A 折叠成 'k'）
/// 这类不可能出现在模型标签里的输入；即便真的出现，流结束后的完整抽取器仍会
/// 识别该工具调用，受影响的只是流式期间的预览卡片。
int _asciiLower(int codeUnit) {
  return (codeUnit >= 0x41 && codeUnit <= 0x5A) ? codeUnit | 0x20 : codeUnit;
}

bool _matchesIgnoreCaseAt(String buffer, int offset, String needle) {
  if (offset + needle.length > buffer.length) return false;
  for (var i = 0; i < needle.length; i++) {
    if (_asciiLower(buffer.codeUnitAt(offset + i)) !=
        _asciiLower(needle.codeUnitAt(i))) {
      return false;
    }
  }
  return true;
}

/// 从 [start] 开始找第一个匹配，避免 `substring` 整尾拷贝。
/// [RegExp.allMatches] 是惰性的，取首个即停止扫描。
RegExpMatch? _firstMatchFrom(RegExp pattern, String input, int start) {
  if (start >= input.length) return null;
  for (final match in pattern.allMatches(input, start)) {
    return match;
  }
  return null;
}

/// Matches an opening `<DSML:invoke` whose `>` has not yet arrived. Used
/// to detect a fresh, name-less invoke at the tail of a streaming buffer.
final RegExp _unclosedInvokeOpenerPattern = RegExp(
  r'<DSML:invoke\b[^>]*$',
  caseSensitive: false,
);
