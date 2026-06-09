String? nullIfBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

List<String> splitTrimmedNonEmpty(String value, {Pattern separator = ','}) {
  return value
      .split(separator)
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<String> stringListFromValue(Object? value, {Pattern separator = ','}) {
  if (value is List) {
    return value
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (value is String) {
    return splitTrimmedNonEmpty(value, separator: separator);
  }
  return const <String>[];
}

Map<String, String> keyValueMapFromValue(
  Object? value, {
  Pattern lineSeparator = '\n',
  String keyValueSeparator = '=',
}) {
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
    final index = line.indexOf(keyValueSeparator);
    if (index <= 0) continue;
    final key = line.substring(0, index).trim();
    if (key.isEmpty) continue;
    map[key] = line.substring(index + keyValueSeparator.length).trim();
  }
  return map;
}

List<int> invalidKeyValueLineNumbersFromText(
  String value, {
  Pattern lineSeparator = '\n',
  String keyValueSeparator = '=',
}) {
  if (value.trim().isEmpty) return const <int>[];
  final invalidLines = <int>[];
  final lines = value.split(lineSeparator);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final index = line.indexOf(keyValueSeparator);
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
  if (value is num) return value.toInt() == 1;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == '1' || normalized == 'true') return true;
    if (normalized == '0' || normalized == 'false') return false;
  }
  return defaultValue;
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
    return double.tryParse(value.trim()) ?? fallback;
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

int positiveIntFromValue(Object? value, {required int fallback}) {
  final parsed = optionalIntFromValue(value);
  return parsed == null || parsed <= 0 ? fallback : parsed;
}

int clampedIntFromValue(
  Object? value, {
  required int fallback,
  required int min,
  required int max,
}) {
  final parsed = intFromValue(value, fallback: fallback);
  final lower = min <= max ? min : max;
  final upper = min <= max ? max : min;
  return parsed.clamp(lower, upper).toInt();
}

double clampedDoubleFromValue(
  Object? value, {
  required double fallback,
  required double min,
  required double max,
}) {
  final parsed = optionalDoubleFromValue(value);
  final lower = min <= max ? min : max;
  final upper = min <= max ? max : min;
  final safeFallback = fallback.isFinite ? fallback : lower;
  return (parsed ?? safeFallback).clamp(lower, upper).toDouble();
}

int clampedIntFromText(
  String value, {
  required int fallback,
  required int min,
  required int max,
}) {
  final parsed = int.tryParse(value.trim()) ?? fallback;
  final lower = min <= max ? min : max;
  final upper = min <= max ? max : min;
  return parsed.clamp(lower, upper).toInt();
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

double? optionalDoubleFromText(String value) {
  return optionalDoubleFromValue(value);
}

int positiveIntFromText(String value, {required int fallback}) {
  return positiveIntFromValue(value, fallback: fallback);
}
