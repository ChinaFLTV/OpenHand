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
    return _findCaseInsensitiveOffsetsByOriginalIndex(
      text: text,
      query: query,
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

List<int> _findCaseInsensitiveOffsetsByOriginalIndex({
  required String text,
  required String query,
  required String pattern,
  required int maxMatches,
  required bool allowOverlapping,
}) {
  if (query.length > text.length) return const <int>[];
  final offsets = <int>[];
  final step = allowOverlapping ? 1 : query.length;
  var startIndex = 0;
  while (startIndex <= text.length - query.length) {
    final candidate = text.substring(startIndex, startIndex + query.length);
    if (candidate.toLowerCase() == pattern) {
      offsets.add(startIndex);
      if (offsets.length >= maxMatches) break;
      startIndex += step;
    } else {
      startIndex += 1;
    }
  }
  return offsets;
}
