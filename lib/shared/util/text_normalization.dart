final RegExp _inlineWhitespacePattern = RegExp(r'\s+');

String collapseInlineWhitespace(String value) {
  return value.replaceAll(_inlineWhitespacePattern, ' ').trim();
}

String removeInlineWhitespace(String value) {
  return value.replaceAll(_inlineWhitespacePattern, '');
}
