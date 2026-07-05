import 'package:characters/characters.dart';

import 'input_value_parsing.dart';

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

String clipMiddleText(
  String value, {
  required int maxChars,
  String separator = '…',
  double headFraction = 0.6,
}) {
  if (maxChars <= 0) return '';
  final characters = value.characters;
  final charCount = characters.length;
  if (charCount <= maxChars) return value;

  final separatorChars = separator.characters;
  final separatorLength = separatorChars.length;
  if (separatorLength >= maxChars) {
    return separatorChars.take(maxChars).toString();
  }

  final available = maxChars - separatorLength;
  final safeHeadFraction = finiteUnitInterval(headFraction, fallback: 0.6);
  final headCount = (available * safeHeadFraction)
      .round()
      .clamp(0, available)
      .toInt();
  final tailCount = available - headCount;
  final head = characters.take(headCount);
  if (tailCount <= 0) {
    return '$head$separator';
  }
  final tail = characters.skip(charCount - tailCount);
  return '$head$separator$tail';
}
