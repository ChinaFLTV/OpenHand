String clipText(String value, int maxChars, {String suffix = '...'}) {
  final safeMaxChars = maxChars < 0 ? 0 : maxChars;
  if (value.length <= safeMaxChars) return value;
  return '${value.substring(0, safeMaxChars)}$suffix';
}

String? clipNullableText(String? value, int maxChars, {String suffix = '...'}) {
  if (value == null) return null;
  return clipText(value, maxChars, suffix: suffix);
}
