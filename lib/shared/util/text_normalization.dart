final RegExp _inlineWhitespacePattern = RegExp(r'\s+');
final RegExp _asciiLookupTokenSeparatorPattern = RegExp(r'[^a-z0-9]+');
final RegExp _snakeStorageKeySeparatorPattern = RegExp(r'[\s-]+');

String collapseInlineWhitespace(String value) {
  return value.replaceAll(_inlineWhitespacePattern, ' ').trim();
}

String removeInlineWhitespace(String value) {
  return value.replaceAll(_inlineWhitespacePattern, '');
}

/// Normalizes names used for tolerant lookups by keeping only ASCII
/// alphanumeric characters and lower-casing them.
String normalizeAsciiLookupKey(String value) {
  final buffer = StringBuffer();
  for (final code in value.trim().codeUnits) {
    if (code >= 0x30 && code <= 0x39) {
      buffer.writeCharCode(code);
    } else if (code >= 0x41 && code <= 0x5A) {
      buffer.writeCharCode(code | 0x20);
    } else if (code >= 0x61 && code <= 0x7A) {
      buffer.writeCharCode(code);
    }
  }
  return buffer.toString();
}

String normalizeAsciiSlugKey(String value) {
  return value.trim().toLowerCase().replaceAll(
    _asciiLookupTokenSeparatorPattern,
    '-',
  );
}

String normalizeSnakeStorageKey(String value) {
  return value.trim().toLowerCase().replaceAll(
    _snakeStorageKeySeparatorPattern,
    '_',
  );
}
