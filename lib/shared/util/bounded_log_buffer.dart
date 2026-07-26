import 'dart:collection';

import 'text_clip.dart';

/// 保留最新日志，同时限制行数和字符数，避免单个超长日志撑爆内存。
class BoundedLogBuffer {
  BoundedLogBuffer({
    this.maxLines = defaultMaxLines,
    this.maxCharacters = defaultMaxCharacters,
  }) {
    if (maxLines < 1) {
      throw ArgumentError.value(maxLines, 'maxLines', '必须大于零。');
    }
    if (maxCharacters < 1) {
      throw ArgumentError.value(maxCharacters, 'maxCharacters', '必须大于零。');
    }
  }

  static const int defaultMaxLines = 2000;
  static const int defaultMaxCharacters = 200000;

  final int maxLines;
  final int maxCharacters;
  final ListQueue<String> _lines = ListQueue<String>();
  int _characterCount = 0;
  int _revision = 0;

  int get length => _lines.length;
  int get characterCount => _characterCount;
  int get revision => _revision;
  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;

  String operator [](int index) => _lines.elementAt(index);

  void add(String line) {
    final retained = _retainLatestCharacters(line);
    while (_lines.isNotEmpty &&
        (_lines.length >= maxLines ||
            _characterCount + retained.length > maxCharacters)) {
      _characterCount -= _lines.removeFirst().length;
    }
    _lines.addLast(retained);
    _characterCount += retained.length;
    _revision += 1;
  }

  void addAll(Iterable<String> lines) {
    for (final line in lines) {
      add(line);
    }
  }

  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    _characterCount = 0;
    _revision += 1;
  }

  List<String> snapshot() => List<String>.unmodifiable(_lines);

  String _retainLatestCharacters(String value) {
    if (value.length <= maxCharacters) return value;
    final start = safeUtf16SuffixStart(value, value.length - maxCharacters);
    return value.substring(start);
  }
}
