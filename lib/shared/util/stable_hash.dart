String stableFnv1a32Hex(String content) {
  var hash = 0x811c9dc5;
  for (final codeUnit in content.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toUnsigned(32).toRadixString(16).padLeft(8, '0');
}
