import 'dart:collection';

import 'argument_guards.dart';
import 'text_clip.dart';

/// 保留最新文本并记录绝对偏移，避免滚动裁剪后丢失增量读取位置。
final class BoundedTextBuffer {
  BoundedTextBuffer({required this.maxCharacters, String initialValue = ''}) {
    requirePositiveInt(maxCharacters, 'maxCharacters');
    replace(initialValue);
  }

  static const int _maxChunks = 256;

  final int maxCharacters;
  final ListQueue<String> _chunks = ListQueue<String>();
  int _retainedCharacters = 0;
  int _totalCharacters = 0;
  String? _cachedText;

  int get length => _retainedCharacters;
  int get startOffset => _totalCharacters - _retainedCharacters;
  int get endOffset => _totalCharacters;
  bool get isEmpty => _retainedCharacters == 0;
  bool get isNotEmpty => _retainedCharacters != 0;

  String get text {
    final cached = _cachedText;
    if (cached != null) return cached;
    final value = _chunks.join();
    _cachedText = value;
    return value;
  }

  void append(String value) {
    if (value.isEmpty) return;
    _chunks.addLast(value);
    _retainedCharacters += value.length;
    _totalCharacters += value.length;
    _cachedText = null;
    _trim();
    if (_chunks.length > _maxChunks) {
      final compacted = text;
      _chunks
        ..clear()
        ..add(compacted);
    }
  }

  void replace(String value) {
    _chunks.clear();
    _retainedCharacters = 0;
    _totalCharacters = 0;
    _cachedText = null;
    append(value);
  }

  void clear() => replace('');

  bool discardedSince(int absoluteOffset) => absoluteOffset < startOffset;

  String textFrom(int absoluteOffset) {
    final value = text;
    final requestedStart = absoluteOffset - startOffset;
    final localStart = safeUtf16SuffixStart(value, requestedStart);
    return value.substring(localStart);
  }

  void _trim() {
    var overflow = _retainedCharacters - maxCharacters;
    while (overflow > 0 && _chunks.isNotEmpty) {
      final first = _chunks.first;
      if (first.length <= overflow) {
        _chunks.removeFirst();
        _retainedCharacters -= first.length;
        overflow -= first.length;
        if (isUtf16HighSurrogateCodeUnit(first.codeUnitAt(first.length - 1))) {
          _removeLeadingLowSurrogate();
          overflow = _retainedCharacters - maxCharacters;
        }
        continue;
      }
      final removeLength = safeUtf16SuffixStart(first, overflow);
      _chunks.removeFirst();
      _retainedCharacters -= removeLength;
      if (removeLength < first.length) {
        _chunks.addFirst(first.substring(removeLength));
      }
      overflow = _retainedCharacters - maxCharacters;
    }
  }

  void _removeLeadingLowSurrogate() {
    if (_chunks.isEmpty) return;
    final first = _chunks.first;
    if (!isUtf16LowSurrogateCodeUnit(first.codeUnitAt(0))) return;
    _chunks.removeFirst();
    _retainedCharacters -= 1;
    if (first.length > 1) {
      _chunks.addFirst(first.substring(1));
    }
  }
}
