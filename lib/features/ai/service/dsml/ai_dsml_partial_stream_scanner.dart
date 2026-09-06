import 'dart:convert';

import 'ai_dsml_tool_call_parser.dart'
    show
        canonicalizeDsmlMarkup,
        decodeDsmlParameterValue,
        dsmlParameterTreatsValueAsString;

/// 从流式文本缓冲中解析出的未完成 DSML 调用。
class PartialDsmlInvoke {
  const PartialDsmlInvoke({
    required this.index,
    required this.id,
    required this.name,
    required this.argumentsJson,
    required this.isComplete,
    this.isPreparing = false,
  });

  /// 缓冲内从零开始的顺序，与流结束后的提取顺序保持一致。
  final int index;

  /// 与流结束后提取结果一致的稳定标识。
  final String id;

  final String name;

  /// JSON 参数；调用未完成时仅包含当前已解析部分。
  final String argumentsJson;

  /// 是否已收到调用闭合标签。
  final bool isComplete;

  /// 是否仅收到未闭合的调用起始标签，此时工具名称仍未知。
  final bool isPreparing;
}

final RegExp _invokeOpenPattern = RegExp(
  r'<DSML:invoke\b([^>]*)>',
  caseSensitive: false,
);
final RegExp _invokeClosePattern = RegExp(
  '</DSML:invoke>',
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

/// 扫描完整及尾部未完成的 DSML 调用；使用与流结束后相同的规范化规则。
List<PartialDsmlInvoke> scanPartialDsmlInvokes(String buffer) {
  // 纯文本直接跳过规范化。
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
      break;
    }
    cursor = closeMatch.end;
  }
  // 未收到工具名称时生成准备中占位项。
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

/// 跨 delta 的增量工具调用标记探测器。
///
/// 纯文本流式路径此前每个 delta 都要对**累积缓冲**做一次 `toString()`
/// 拷贝再全量扫描标记，长回复上叠成 O(N²) 的拷贝与扫描。本探测器只检查
/// 「上次尾部重叠窗口 + 新 delta」，把纯文本 delta 的探测成本降为
/// O(delta)；一旦发现候选标记即永久置位，此后交给完整扫描器处理。
class DsmlStreamMarkerProbe {
  /// 重叠窗口取最长标记长度减一，保证跨 delta 拆开的标记不会漏检。
  static final int _overlapLength = _longestMarkerNeedleLength - 1;

  bool _markerSeen = false;
  String _tail = '';

  /// 吞入写进累积缓冲的新 [delta]，返回缓冲当前是否可能包含工具调用标记。
  bool ingest(String delta) {
    if (_markerSeen) return true;
    if (delta.isEmpty) return false;
    final probe = _tail.isEmpty ? delta : '$_tail$delta';
    if (_mayContainToolCallMarker(probe)) {
      _markerSeen = true;
      _tail = '';
      return true;
    }
    _tail = probe.length <= _overlapLength
        ? probe
        : probe.substring(probe.length - _overlapLength);
    return false;
  }
}

final int _longestMarkerNeedleLength = _markerNeedlesByLeadChar.values.fold(
  1,
  (longest, needles) => needles.fold(
    longest,
    (current, needle) => needle.length > current ? needle.length : current,
  ),
);

/// 保守判断缓冲是否可能包含工具调用标记，纯文本可跳过规范化。
bool _mayContainToolCallMarker(String buffer) {
  for (var index = 0; index < buffer.length; index++) {
    final needles =
        _markerNeedlesByLeadChar[_asciiLower(buffer.codeUnitAt(index))];
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
    // 标准形式。
    '<dsml:invoke',
    // 半角、全角及双竖线外壳。
    '<|dsml', '<｜dsml', '<｜｜dsml', '<||dsml',
    // 弱模型常见括号外壳。
    '<<dsml', '<【dsml', '<《dsml', '<[dsml', '<「dsml', '<『dsml',
    // 原始或带命名空间的调用标记。
    '<invoke', '<function_calls', '<tool_calls', '.invoke', ':invoke',
    // JSON/YAML 信封变体。
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

/// 匹配流式缓冲末尾尚未闭合且工具名称未知的调用起始标签。
final RegExp _unclosedInvokeOpenerPattern = RegExp(
  r'<DSML:invoke\b[^>]*$',
  caseSensitive: false,
);
