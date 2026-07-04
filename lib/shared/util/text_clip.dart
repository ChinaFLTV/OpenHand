import 'package:characters/characters.dart';

String clipText(String value, int maxChars, {String suffix = '...'}) {
  final safeMaxChars = maxChars < 0 ? 0 : maxChars;
  final characters = value.characters;
  if (characters.length <= safeMaxChars) return value;
  return '${characters.take(safeMaxChars)}$suffix';
}

String clipTextWithEllipsis(String value, int maxChars) {
  return clipText(value, maxChars, suffix: '…');
}

String? clipNullableText(String? value, int maxChars, {String suffix = '...'}) {
  if (value == null) return null;
  return clipText(value, maxChars, suffix: suffix);
}
