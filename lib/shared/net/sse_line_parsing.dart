/// SSE (Server-Sent Events) 行级字段解析。
///
/// AI 流式对话、MCP Streamable HTTP、扫描引擎实时事件等多处均消费 SSE，
/// 统一处理 SSE 的 `data:` 前缀和行结束符。
library;

import 'dart:convert';

import '../util/argument_guards.dart';

final _sseLineBreak = RegExp(r'\r\n|\r|\n');
const _sseSpace = 0x20;
const _sseLineFeed = 0x0A;
const _sseByteOrderMark = 0xFEFF;

/// 按 SSE 规范只移除冒号后的一个空格，保留载荷自身的空白。
String? sseDataPayload(String line) => _sseFieldValue(line, 'data');

String? sseEventName(String line) => _sseFieldValue(line, 'event');

String? _sseFieldValue(String line, String field) {
  if (line == field) return '';
  if (!line.startsWith('$field:')) return null;
  var start = field.length + 1;
  if (start < line.length && line.codeUnitAt(start) == _sseSpace) start++;
  return line.substring(start);
}

/// 从完整 SSE 事件块文本中提取全部 `data:` 载荷行。
List<String> extractSseDataLines(String block) {
  return const LineSplitter()
      .convert(block)
      .map(sseDataPayload)
      .whereType<String>()
      .toList(growable: false);
}

/// 增量组装 SSE 事件；跨分片的 CRLF 只算一次换行，缓冲受单事件字符上限约束。
/// 只在事件完成时拼接片段，避免小分片反复复制整个未完成事件。
final class BoundedSseEventBuffer {
  BoundedSseEventBuffer({required this.maxEventCharacters}) {
    requirePositiveInt(maxEventCharacters, 'maxEventCharacters');
  }

  final int maxEventCharacters;
  final StringBuffer _buffer = StringBuffer();
  bool _atStart = true;
  bool _skipLeadingLf = false;
  bool _lineHasContent = false;
  bool _pendingLineBreak = false;
  bool _overflowed = false;

  /// 超限时清空缓冲并返回 false；消费者结束后立即丢弃当前分片的剩余数据。
  bool add(
    String chunk, {
    required void Function(String block) onEvent,
    required bool Function() isComplete,
  }) {
    if (_overflowed) return false;
    if (isComplete()) {
      _clear();
      return true;
    }
    if (chunk.isEmpty) return true;
    var start = 0;
    if (_atStart) {
      _atStart = false;
      if (chunk.codeUnitAt(0) == _sseByteOrderMark) start++;
    }
    if (_skipLeadingLf &&
        start < chunk.length &&
        chunk.codeUnitAt(start) == _sseLineFeed) {
      start++;
    }
    _skipLeadingLf = chunk.endsWith('\r');
    for (final match in _sseLineBreak.allMatches(chunk, start)) {
      if (!_append(chunk, start, match.start)) return false;
      start = match.end;
      if (_lineHasContent) {
        _lineHasContent = false;
        _pendingLineBreak = true;
      } else {
        finish(onEvent);
        if (isComplete()) return true;
      }
    }
    return _append(chunk, start, chunk.length);
  }

  /// 兼容未发送末尾空行就关闭连接的供应商。
  void finish(void Function(String block) onEvent) {
    if (_buffer.isEmpty) {
      _clear();
      return;
    }
    final block = _buffer.toString();
    _clear();
    onEvent(block);
  }

  bool _append(String chunk, int start, int end) {
    if (start == end) return true;
    final addedLength = end - start + (_pendingLineBreak ? 1 : 0);
    if (addedLength > maxEventCharacters - _buffer.length) {
      _clear();
      _overflowed = true;
      return false;
    }
    if (_pendingLineBreak) _buffer.write('\n');
    _buffer.write(chunk.substring(start, end));
    _pendingLineBreak = false;
    _lineHasContent = true;
    return true;
  }

  void _clear() {
    _buffer.clear();
    _lineHasContent = false;
    _pendingLineBreak = false;
  }
}
