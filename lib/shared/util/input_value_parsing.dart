import 'dart:convert';

String? nullIfBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

final RegExp _looseDelimitedValueSeparator = RegExp(r'[\s,，;；]+');

List<String> splitTrimmedNonEmpty(String value, {Pattern separator = ','}) {
  if (separator is String && separator.isEmpty) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? const <String>[] : <String>[trimmed];
  }
  return value
      .split(separator)
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<String> splitLooseDelimitedValues(String value) {
  return splitTrimmedNonEmpty(value, separator: _looseDelimitedValueSeparator);
}

List<String> stringListFromValue(Object? value, {Pattern separator = ','}) {
  if (value is List) {
    return value
        .where((item) => item != null)
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (value is String) {
    return splitTrimmedNonEmpty(value, separator: separator);
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
  try {
    final decoded = jsonDecode(trimmed);
    if (requireList && decoded is! List) return null;
    return stringListFromValue(decoded, separator: separator);
  } catch (_) {}
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
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) return stringKeyedMapFromValue(decoded);
  } catch (_) {}
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

DateTime? dateTimeFromValue(Object? value) {
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}

bool boolFromValue(Object? value, {bool defaultValue = false}) {
  if (value is bool) return value;
  if (value is num) return value.isFinite ? value.toInt() == 1 : defaultValue;
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
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

double doubleFromValue(Object? value, {required double fallback}) {
  if (value is double && value.isFinite) return value;
  if (value is num && value.isFinite) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    return parsed != null && parsed.isFinite ? parsed : fallback;
  }
  return fallback;
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

int? optionalIntFromValue(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : int.tryParse(trimmed);
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

int? optionalIntFromText(String value) {
  return optionalIntFromValue(value);
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
