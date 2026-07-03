List<String> extractSseDataLines(String block) {
  final trimmedBlock = block.trim();
  if (trimmedBlock.isEmpty) return const <String>[];
  return trimmedBlock
      .split('\n')
      .where((line) => line.startsWith('data:'))
      .map((line) => line.substring(5).trim())
      .toList(growable: false);
}
