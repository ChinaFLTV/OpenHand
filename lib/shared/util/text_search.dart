const _highSurrogateMin = 0xD800;
const _highSurrogateMax = 0xDBFF;
const _lowSurrogateMin = 0xDC00;
const _lowSurrogateMax = 0xDFFF;

List<int> findTextMatchOffsets({
  required String text,
  required String query,
  bool caseSensitive = false,
  int maxMatches = 10000,
  bool allowOverlapping = true,
}) {
  if (text.isEmpty || query.isEmpty || maxMatches <= 0) {
    return const <int>[];
  }

  final pattern = caseSensitive ? query : query.toLowerCase();
  if (pattern.isEmpty) return const <int>[];

  final searchText = caseSensitive ? text : text.toLowerCase();
  if (!caseSensitive &&
      (searchText.length != text.length || pattern.length != query.length)) {
    return _findCaseInsensitiveOffsetsByFoldedIndex(
      text: text,
      pattern: pattern,
      maxMatches: maxMatches,
      allowOverlapping: allowOverlapping,
    );
  }
  final offsets = <int>[];
  final step = allowOverlapping ? 1 : pattern.length;
  var startIndex = 0;
  while (startIndex <= searchText.length) {
    final index = searchText.indexOf(pattern, startIndex);
    if (index < 0) break;
    offsets.add(index);
    if (offsets.length >= maxMatches) break;
    startIndex = index + step;
  }
  return offsets;
}

List<int> _findCaseInsensitiveOffsetsByFoldedIndex({
  required String text,
  required String pattern,
  required int maxMatches,
  required bool allowOverlapping,
}) {
  final foldedText = _foldTextWithOffsets(text);
  final searchText = foldedText.text;
  final offsetMap = foldedText.offsets;
  if (pattern.length > searchText.length) return const <int>[];

  final offsets = <int>[];
  final step = allowOverlapping ? 1 : pattern.length;
  var startIndex = 0;
  while (startIndex <= searchText.length) {
    final index = searchText.indexOf(pattern, startIndex);
    if (index < 0) break;
    offsets.add(offsetMap[index]);
    if (offsets.length >= maxMatches) break;
    startIndex = index + step;
  }
  return offsets;
}

_FoldedText _foldTextWithOffsets(String text) {
  final buffer = StringBuffer();
  final offsets = <int>[];
  for (var index = 0; index < text.length;) {
    final nextIndex = _nextRuneIndex(text, index);
    final char = text.substring(index, nextIndex);
    final folded = char.toLowerCase();
    buffer.write(folded);
    offsets.addAll(List<int>.filled(folded.length, index));
    index = nextIndex;
  }
  return _FoldedText(buffer.toString(), offsets);
}

int _nextRuneIndex(String text, int index) {
  final unit = text.codeUnitAt(index);
  if (unit >= _highSurrogateMin &&
      unit <= _highSurrogateMax &&
      index + 1 < text.length) {
    final next = text.codeUnitAt(index + 1);
    if (next >= _lowSurrogateMin && next <= _lowSurrogateMax) {
      return index + 2;
    }
  }
  return index + 1;
}

class _FoldedText {
  const _FoldedText(this.text, this.offsets);

  final String text;
  final List<int> offsets;
}
