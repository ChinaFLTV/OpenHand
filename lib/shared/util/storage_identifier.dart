final RegExp _unsafeStorageIdentifierPattern = RegExp(
  r'[\u0000-\u001F\u007F/\\]',
);

bool isSafeStorageIdentifier(String value) {
  final normalizedValue = value.trim();
  return normalizedValue.isNotEmpty &&
      normalizedValue != '.' &&
      normalizedValue != '..' &&
      !_unsafeStorageIdentifierPattern.hasMatch(normalizedValue);
}
