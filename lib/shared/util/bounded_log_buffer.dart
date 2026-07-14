import 'dart:collection';

/// Keeps the newest interactive log lines without allowing long-running
/// subprocess output to grow UI state indefinitely.
class BoundedLogBuffer {
  BoundedLogBuffer({this.maxLines = defaultMaxLines}) {
    if (maxLines < 1) {
      throw ArgumentError.value(maxLines, 'maxLines', 'Must be positive.');
    }
  }

  static const int defaultMaxLines = 2000;

  final int maxLines;
  final ListQueue<String> _lines = ListQueue<String>();
  int _revision = 0;

  int get length => _lines.length;
  int get revision => _revision;
  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;

  String operator [](int index) => _lines.elementAt(index);

  void add(String line) {
    if (_lines.length >= maxLines) {
      _lines.removeFirst();
    }
    _lines.addLast(line);
    _revision += 1;
  }

  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    _revision += 1;
  }

  List<String> snapshot() => List<String>.unmodifiable(_lines);
}
