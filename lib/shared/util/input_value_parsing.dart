import 'dart:convert';

String? nullIfBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

final RegExp _looseDelimitedValueSeparator = RegExp(r'[\s,，;；]+');

({bool ok, Object? value}) _tryDecodeJsonText(String value) {
  try {
    return (ok: true, value: jsonDecode(value));
  } on FormatException {
    return (ok: false, value: null);
  }
}

List<String> splitTrimmed(String value, {Pattern separator = ','}) {
  if (separator is String && separator.isEmpty) {
    return <String>[value.trim()];
  }
  return value
      .split(separator)
      .map((item) => item.trim())
      .toList(growable: false);
}

List<String> splitTrimmedNonEmpty(String value, {Pattern separator = ','}) {
  return splitTrimmed(
    value,
    separator: separator,
  ).where((item) => item.isNotEmpty).toList(growable: false);
}

List<String> splitLooseDelimitedValues(String value) {
  return splitTrimmedNonEmpty(value, separator: _looseDelimitedValueSeparator);
}

bool _keepStringListItem(String item, {required bool ignoreLiteralNull}) {
  return item.isNotEmpty && (!ignoreLiteralNull || item != 'null');
}

List<String> trimmedNonEmptyStrings(
  Iterable<Object?> values, {
  bool ignoreLiteralNull = false,
}) {
  return values
      .where((item) => item != null)
      .map((item) => '$item'.trim())
      .where(
        (item) =>
            _keepStringListItem(item, ignoreLiteralNull: ignoreLiteralNull),
      )
      .toList(growable: false);
}

List<String> trimRightNonEmptyLines(Iterable<String> lines, {int? limit}) {
  if (limit != null && limit <= 0) return const <String>[];
  final normalized = lines
      .map((line) => line.trimRight())
      .where((line) => nullIfBlank(line) != null);
  return (limit == null ? normalized : normalized.take(limit)).toList(
    growable: false,
  );
}

List<String> stringListFromListValue(
  Object? value, {
  bool ignoreLiteralNull = false,
}) {
  if (value is! List) return const <String>[];
  return trimmedNonEmptyStrings(value, ignoreLiteralNull: ignoreLiteralNull);
}

List<String> stringListFromValue(
  Object? value, {
  Pattern separator = ',',
  bool ignoreLiteralNull = false,
}) {
  if (value is List) {
    return stringListFromListValue(value, ignoreLiteralNull: ignoreLiteralNull);
  }
  if (value is String) {
    return splitTrimmedNonEmpty(value, separator: separator)
        .where(
          (item) =>
              _keepStringListItem(item, ignoreLiteralNull: ignoreLiteralNull),
        )
        .toList(growable: false);
  }
  return const <String>[];
}

List<String> stringListFromJsonText(
  String value, {
  Pattern separator = ',',
  bool requireList = false,
}) {
  return optionalStringListFromJsonText(
        value,
        separator: separator,
        requireList: requireList,
      ) ??
      const <String>[];
}

List<String>? optionalStringListFromJsonText(
  String value, {
  Pattern separator = ',',
  bool requireList = false,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return const <String>[];
  final decoded = _tryDecodeJsonText(trimmed);
  if (!decoded.ok) return null;
  if (requireList && decoded.value is! List) return null;
  return stringListFromValue(decoded.value, separator: separator);
}

List<String> stringListFromValueOrJsonText(
  Object? value, {
  Pattern separator = ',',
  bool requireList = false,
}) {
  return optionalStringListFromValueOrJsonText(
        value,
        separator: separator,
        requireList: requireList,
      ) ??
      const <String>[];
}

List<String>? optionalStringListFromValueOrJsonText(
  Object? value, {
  Pattern separator = ',',
  bool requireList = false,
}) {
  if (value is List) {
    return stringListFromValue(value, separator: separator);
  }
  if (value is String) {
    return optionalStringListFromJsonText(
          value,
          separator: separator,
          requireList: requireList,
        ) ??
        (requireList ? null : stringListFromValue(value, separator: separator));
  }
  return null;
}

String stringFromValue(Object? value, {String fallback = ''}) {
  return optionalStringFromValue(value) ?? fallback;
}

String? optionalStringFromValue(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

Map<String, Object?> stringKeyedMapFromValue(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is! Map) return const <String, Object?>{};
  return value.map((key, item) => MapEntry('$key', item));
}

List<Map<String, Object?>> stringKeyedMapListFromValue(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  final out = <Map<String, Object?>>[];
  for (final item in value) {
    if (item is Map) {
      out.add(stringKeyedMapFromValue(item));
    }
  }
  return out;
}

List<Map<String, Object?>> stringKeyedMapListFromValueOrJsonText(
  Object? value,
) {
  return optionalStringKeyedMapListFromValueOrJsonText(value) ??
      const <Map<String, Object?>>[];
}

List<Map<String, Object?>>? optionalStringKeyedMapListFromValueOrJsonText(
  Object? value,
) {
  if (value is List) return stringKeyedMapListFromValue(value);
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const <Map<String, Object?>>[];
    final decoded = _tryDecodeJsonText(trimmed);
    if (decoded.value is List) {
      return stringKeyedMapListFromValue(decoded.value);
    }
  }
  return null;
}

Map<String, Object?> stringKeyedMapFromJsonText(String value) {
  return optionalStringKeyedMapFromJsonText(value) ?? const <String, Object?>{};
}

Map<String, Object?> stringKeyedMapFromValueOrJsonText(Object? value) {
  return optionalStringKeyedMapFromValueOrJsonText(value) ??
      const <String, Object?>{};
}

Map<String, Object?>? optionalStringKeyedMapFromValueOrJsonText(Object? value) {
  if (value is Map) return stringKeyedMapFromValue(value);
  if (value is String) return optionalStringKeyedMapFromJsonText(value);
  return null;
}

Map<String, Object?>? optionalStringKeyedMapFromJsonText(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final decoded = _tryDecodeJsonText(trimmed);
  if (decoded.value is Map) return stringKeyedMapFromValue(decoded.value);
  return null;
}

Map<String, String> keyValueMapFromValue(
  Object? value, {
  Pattern lineSeparator = '\n',
  String keyValueSeparator = '=',
}) {
  final separator = _effectiveKeyValueSeparator(keyValueSeparator);
  if (value is Map) {
    final map = <String, String>{};
    for (final entry in value.entries) {
      final key = '${entry.key}'.trim();
      if (key.isEmpty) continue;
      map[key] = '${entry.value}'.trim();
    }
    return map;
  }
  if (value is! String || value.trim().isEmpty) {
    return const <String, String>{};
  }

  final map = <String, String>{};
  for (final line in value.split(lineSeparator)) {
    final index = line.indexOf(separator);
    if (index <= 0) continue;
    final key = line.substring(0, index).trim();
    if (key.isEmpty) continue;
    map[key] = line.substring(index + separator.length).trim();
  }
  return map;
}

List<int> invalidKeyValueLineNumbersFromText(
  String value, {
  Pattern lineSeparator = '\n',
  String keyValueSeparator = '=',
}) {
  if (value.trim().isEmpty) return const <int>[];
  final separator = _effectiveKeyValueSeparator(keyValueSeparator);
  final invalidLines = <int>[];
  final lines = value.split(lineSeparator);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final index = line.indexOf(separator);
    if (index <= 0) {
      invalidLines.add(i + 1);
      continue;
    }
    final key = line.substring(0, index).trim();
    if (key.isEmpty) invalidLines.add(i + 1);
  }
  return invalidLines;
}

enum DateTimeNumericTimestampMode {
  milliseconds,
  seconds,
  secondsOrMilliseconds,
}

DateTime? dateTimeFromValue(
  Object? value, {
  DateTimeNumericTimestampMode numericTimestampMode =
      DateTimeNumericTimestampMode.milliseconds,
  bool requirePositiveTimestamp = false,
}) {
  if (value is DateTime) return value;
  if (value is num) {
    return _dateTimeFromNumericTimestamp(
      value,
      mode: numericTimestampMode,
      requirePositive: requirePositiveTimestamp,
    );
  }
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}

DateTime? utcDateTimeFromValue(
  Object? value, {
  DateTimeNumericTimestampMode numericTimestampMode =
      DateTimeNumericTimestampMode.milliseconds,
  bool requirePositiveTimestamp = false,
}) {
  return dateTimeFromValue(
    value,
    numericTimestampMode: numericTimestampMode,
    requirePositiveTimestamp: requirePositiveTimestamp,
  )?.toUtc();
}

DateTime? _dateTimeFromNumericTimestamp(
  num value, {
  required DateTimeNumericTimestampMode mode,
  required bool requirePositive,
}) {
  if (!value.isFinite) return null;
  final raw = value.toInt();
  if (requirePositive && raw <= 0) return null;
  final milliseconds = switch (mode) {
    DateTimeNumericTimestampMode.milliseconds => raw,
    DateTimeNumericTimestampMode.seconds => raw * 1000,
    DateTimeNumericTimestampMode.secondsOrMilliseconds =>
      raw > 1000000000000 ? raw : raw * 1000,
  };
  try {
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  } on ArgumentError {
    return null;
  }
}

bool boolFromValue(Object? value, {bool defaultValue = false}) {
  return optionalBoolFromValue(value) ?? defaultValue;
}

bool? optionalBoolFromValue(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) {
    if (!value.isFinite) return null;
    if (value == 1) return true;
    if (value == 0) return false;
    return null;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    if (normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'y' ||
        normalized == 'on' ||
        normalized == 'enabled') {
      return true;
    }
    if (normalized == '0' ||
        normalized == 'false' ||
        normalized == 'no' ||
        normalized == 'n' ||
        normalized == 'off' ||
        normalized == 'disabled') {
      return false;
    }
    final integral = optionalIntegralIntFromValue(normalized);
    if (integral == 1) return true;
    if (integral == 0) return false;
  }
  return null;
}

int intFromValue(Object? value, {required int fallback}) {
  return optionalIntFromValue(value) ?? fallback;
}

double doubleFromValue(Object? value, {required double fallback}) {
  return optionalDoubleFromValue(value) ?? fallback;
}

double? optionalDoubleFromValue(Object? value) {
  if (value == null) return null;
  if (value is double && value.isFinite) return value;
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    return parsed != null && parsed.isFinite ? parsed : null;
  }
  return null;
}

double? optionalNonNegativeDoubleFromValue(Object? value) {
  final parsed = optionalDoubleFromValue(value);
  return parsed == null || parsed < 0 ? null : parsed;
}

double? optionalPositiveDoubleFromValue(Object? value) {
  final parsed = optionalDoubleFromValue(value);
  return parsed == null || parsed <= 0 ? null : parsed;
}

int? optionalIntFromText(String? value, {int? radix}) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return int.tryParse(trimmed, radix: radix);
}

int? optionalIntFromValue(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) {
    return optionalIntFromText(value);
  }
  return null;
}

int? optionalRoundedIntFromValue(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.round() : null;
  if (value is String) {
    final parsed = optionalDoubleFromValue(value);
    return parsed?.round();
  }
  return null;
}

int? optionalIntegralIntFromValue(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) {
    if (!value.isFinite) return null;
    final coerced = value.toInt();
    return value == coerced ? coerced : null;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed != null) return parsed;
    final parsedDouble = double.tryParse(trimmed);
    if (parsedDouble == null || !parsedDouble.isFinite) return null;
    final coerced = parsedDouble.toInt();
    return parsedDouble == coerced ? coerced : null;
  }
  return null;
}

int? optionalNonNegativeIntegralIntFromValue(Object? value) {
  final parsed = optionalIntegralIntFromValue(value);
  return parsed == null || parsed < 0 ? null : parsed;
}

int? optionalPositiveIntFromValue(Object? value) {
  final parsed = optionalIntFromValue(value);
  return parsed == null || parsed <= 0 ? null : parsed;
}

int? optionalNonNegativeIntFromValue(Object? value) {
  final parsed = optionalIntFromValue(value);
  return parsed == null || parsed < 0 ? null : parsed;
}

int positiveIntFromValue(Object? value, {required int fallback}) {
  return optionalPositiveIntFromValue(value) ?? fallback;
}

int nonNegativeIntFromValue(Object? value, {required int fallback}) {
  return optionalNonNegativeIntFromValue(value) ?? fallback;
}

int clampedIntFromValue(
  Object? value, {
  required int fallback,
  required int min,
  required int max,
}) {
  final parsed = intFromValue(value, fallback: fallback);
  final (:lower, :upper) = _orderedIntBounds(min, max);
  return parsed.clamp(lower, upper).toInt();
}

double clampedDoubleFromValue(
  Object? value, {
  required double fallback,
  required double min,
  required double max,
}) {
  final parsed = optionalDoubleFromValue(value);
  final (:lower, :upper) = _orderedDoubleBounds(min, max);
  final safeFallback = fallback.isFinite ? fallback : lower;
  return (parsed ?? safeFallback).clamp(lower, upper).toDouble();
}

int clampedIntFromText(
  String value, {
  required int fallback,
  required int min,
  required int max,
}) {
  return clampedIntFromValue(value, fallback: fallback, min: min, max: max);
}

double clampedDoubleFromText(
  String value, {
  required double fallback,
  required double min,
  required double max,
}) {
  return clampedDoubleFromValue(value, fallback: fallback, min: min, max: max);
}

int? optionalPositiveIntFromText(String value) {
  return optionalPositiveIntFromValue(value);
}

double? optionalDoubleFromText(String value) {
  return optionalDoubleFromValue(value);
}

double? optionalNonNegativeDoubleFromText(String value) {
  return optionalNonNegativeDoubleFromValue(value);
}

double? optionalPositiveDoubleFromText(String value) {
  return optionalPositiveDoubleFromValue(value);
}

int positiveIntFromText(String value, {required int fallback}) {
  return positiveIntFromValue(value, fallback: fallback);
}

int nonNegativeIntFromText(String value, {required int fallback}) {
  return nonNegativeIntFromValue(value, fallback: fallback);
}

String _effectiveKeyValueSeparator(String separator) {
  return separator.isEmpty ? '=' : separator;
}

({int lower, int upper}) _orderedIntBounds(int min, int max) {
  return min <= max ? (lower: min, upper: max) : (lower: max, upper: min);
}

({double lower, double upper}) _orderedDoubleBounds(double min, double max) {
  final safeMin = min.isFinite ? min : 0.0;
  final safeMax = max.isFinite ? max : safeMin;
  return safeMin <= safeMax
      ? (lower: safeMin, upper: safeMax)
      : (lower: safeMax, upper: safeMin);
}
