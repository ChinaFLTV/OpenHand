import 'dart:convert';

import 'package:characters/characters.dart';

import 'input_value_parsing.dart';

/// 返回不拆分 UTF-16 代理对的安全前缀长度。
int safeUtf16PrefixCodeUnits(String value, int requestedLength) {
  var length = requestedLength.clamp(0, value.length);
  if (length > 0 &&
      length < value.length &&
      isUtf16HighSurrogateCodeUnit(value.codeUnitAt(length - 1)) &&
      isUtf16LowSurrogateCodeUnit(value.codeUnitAt(length))) {
    length -= 1;
  }
  return length;
}

/// 返回不拆分 UTF-16 代理对的安全后缀起点。
int safeUtf16SuffixStart(String value, int requestedStart) {
  var start = requestedStart.clamp(0, value.length);
  if (start > 0 &&
      start < value.length &&
      isUtf16HighSurrogateCodeUnit(value.codeUnitAt(start - 1)) &&
      isUtf16LowSurrogateCodeUnit(value.codeUnitAt(start))) {
    start += 1;
  }
  return start;
}

/// 返回不拆分字符且不超过 UTF-8 字节上限的安全前缀长度。
int safeUtf8PrefixCodeUnits(String value, int maxBytes) {
  if (maxBytes <= 0) return 0;
  var byteLength = 0;
  var codeUnitLength = 0;
  for (final character in value.characters) {
    final characterByteLength = utf8.encode(character).length;
    if (byteLength + characterByteLength > maxBytes) break;
    byteLength += characterByteLength;
    codeUnitLength += character.length;
  }
  return codeUnitLength;
}

/// 计算 UTF-8 字节数，不创建完整编码副本。
int utf8ByteLength(String value) {
  var length = 0;
  for (final rune in value.runes) {
    if (rune <= 0x7F) {
      length += 1;
    } else if (rune <= 0x7FF) {
      length += 2;
    } else if (rune <= 0xFFFF) {
      length += 3;
    } else {
      length += 4;
    }
  }
  return length;
}

const int _highSurrogateMin = 0xD800;
const int _highSurrogateMax = 0xDBFF;
const int _lowSurrogateMin = 0xDC00;
const int _lowSurrogateMax = 0xDFFF;

bool isUtf16HighSurrogateCodeUnit(int codeUnit) =>
    codeUnit >= _highSurrogateMin && codeUnit <= _highSurrogateMax;

bool isUtf16LowSurrogateCodeUnit(int codeUnit) =>
    codeUnit >= _lowSurrogateMin && codeUnit <= _lowSurrogateMax;

/// 按扩展字符裁剪文本，返回值包含 [suffix] 且不超过 [maxChars] 个字符。
String clipText(String value, int maxChars, {String suffix = '...'}) {
  final safeMaxChars = maxChars < 0 ? 0 : maxChars;
  final characters = value.characters;
  if (characters.length <= safeMaxChars) return value;
  if (safeMaxChars == 0) return '';

  final suffixCharacters = suffix.characters;
  final suffixLength = suffixCharacters.length;
  if (suffixLength >= safeMaxChars) {
    return suffixCharacters.take(safeMaxChars).toString();
  }
  return '${characters.take(safeMaxChars - suffixLength)}$suffix';
}

String clipTextWithEllipsis(String value, int maxChars) {
  return clipText(value, maxChars, suffix: '…');
}

/// 按 UTF-16 代码单元裁剪文本，适用于持久化和内存容量预算。
String clipTextByCodeUnits(
  String value,
  int maxCodeUnits, {
  String suffix = '...',
}) {
  final limit = maxCodeUnits < 0 ? 0 : maxCodeUnits;
  if (value.length <= limit) return value;
  if (limit == 0) return '';
  if (suffix.length >= limit) {
    return suffix.substring(0, safeUtf16PrefixCodeUnits(suffix, limit));
  }
  final end = safeUtf16PrefixCodeUnits(value, limit - suffix.length);
  return '${value.substring(0, end)}$suffix';
}

String clipTextByCodeUnitsWithEllipsis(String value, int maxCodeUnits) {
  return clipTextByCodeUnits(value, maxCodeUnits, suffix: '…');
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
  final headCount = (available * safeHeadFraction).round().clamp(0, available);
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
      throw ArgumentError.value(maxCodeUnits, 'maxCodeUnits', '必须能够容纳省略标记。');
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
  throw StateError('文本裁剪未能收敛。');
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
