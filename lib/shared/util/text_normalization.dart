final RegExp _inlineWhitespacePattern = RegExp(r'\s+');
final RegExp _asciiLookupTokenSeparatorPattern = RegExp(r'[^a-z0-9]+');

String collapseInlineWhitespace(String value) {
  return value.replaceAll(_inlineWhitespacePattern, ' ').trim();
}

String removeInlineWhitespace(String value) {
  return value.replaceAll(_inlineWhitespacePattern, '');
}

String normalizeAsciiLookupKey(String value) {
  return value.trim().toLowerCase().replaceAll(
    _asciiLookupTokenSeparatorPattern,
    '',
  );
}

String normalizeAsciiSlugKey(String value) {
  return value.trim().toLowerCase().replaceAll(
    _asciiLookupTokenSeparatorPattern,
    '-',
  );
}
