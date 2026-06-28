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
