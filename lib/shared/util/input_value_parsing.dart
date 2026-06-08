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

int? optionalIntFromText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : int.tryParse(trimmed);
}
