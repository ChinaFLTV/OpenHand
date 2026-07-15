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

({String text, bool truncated}) clipTextWithOmissionMarker(
  String value, {
  required int maxCodeUnits,
  required String marker,
}) {
  final normalized = value.trim();
  if (normalized.length <= maxCodeUnits) {
    return (text: normalized, truncated: false);
  }
  if (maxCodeUnits <= 0) return (text: '', truncated: true);

  var omitted = normalized.length - maxCodeUnits;
  final maxAttempts = normalized.length.toString().length + 2;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final suffix = '\n[$marker: omitted $omitted chars]';
    if (suffix.length >= maxCodeUnits) {
      final compactMarker = '[$marker: omitted ${normalized.length} chars]';
      if (compactMarker.length <= maxCodeUnits) {
        return (text: compactMarker, truncated: true);
      }
      throw ArgumentError.value(
        maxCodeUnits,
        'maxCodeUnits',
        'must fit the omission marker',
      );
    }
    final headLength = _safePrefixLength(
      normalized,
      maxCodeUnits - suffix.length,
    );
    final head = normalized.substring(0, headLength).trimRight();
    final actualOmitted = normalized.length - head.length;
    if (actualOmitted == omitted) {
      return (text: '$head$suffix', truncated: true);
    }
    omitted = actualOmitted;
  }
  throw StateError('Text clipping did not converge.');
}

int _safePrefixLength(String value, int requestedLength) {
  final limit = requestedLength.clamp(0, value.length);
  if (limit == value.length) return limit;
  var length = 0;
  for (final character in value.characters) {
    final nextLength = length + character.length;
    if (nextLength > limit) break;
    length = nextLength;
  }
  return length;
}
