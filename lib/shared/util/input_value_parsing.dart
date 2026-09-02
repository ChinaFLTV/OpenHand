import 'dart:convert';

String? nullIfBlank(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String nonBlankStringOr(String? value, String fallback) {
  return nullIfBlank(value) ?? fallback;
}

/// 依次尝试 [keys]，返回 [map] 中第一个非空白字符串值（已 trim）；
/// 全部缺失或空白时返回 null。
String? firstNonBlankStringForKeys(
  Map<String, Object?> map,
  List<String> keys,
) {
  for (final key in keys) {
    final value = map[key];
    if (value is String) {
      final normalized = nullIfBlank(value);
      if (normalized != null) return normalized;
    }
  }
  return null;
}

/// 依次尝试 [keys]，返回首个可展示的非空文本；非字符串标量会安全转为文本。
String? firstNonBlankTextForKeys(
  Map<String, Object?> map,
  List<String> keys, {
  bool ignoreLiteralNull = true,
}) {
  for (final key in keys) {
    final value = optionalStringFromValue(
      map[key],
      ignoreLiteralNull: ignoreLiteralNull,
    );
    if (value != null) return value;
  }
  return null;
}

void putIfNotBlank(Map<String, Object?> target, String key, String? value) {
  final normalized = nullIfBlank(value);
  if (normalized != null) target[key] = normalized;
}

T? enumByStorageValue<T extends Enum>(
  Iterable<T> values,
  Object? value,
  String Function(T value) storageValue, {
  String Function(String value)? normalize,
}) {
  return _enumByValue(values, value, storageValue, normalize: normalize);
}

T enumByStorageValueOr<T extends Enum>(
  Iterable<T> values,
  Object? value,
  String Function(T value) storageValue, {
  required T fallback,
  String Function(String value)? normalize,
}) {
  return enumByStorageValue(
        values,
        value,
        storageValue,
        normalize: normalize,
      ) ??
      fallback;
}

T? enumByName<T extends Enum>(
  Iterable<T> values,
  Object? value, {
  String Function(String value)? normalize,
}) {
  return _enumByValue(values, value, (item) => item.name, normalize: normalize);
}

T? _enumByValue<T extends Enum>(
  Iterable<T> values,
  Object? value,
  String Function(T value) valueOf, {
  String Function(String value)? normalize,
}) {
  final normalizedValue = optionalStringFromValue(value);
  if (normalizedValue == null) return null;
  final target = normalize?.call(normalizedValue) ?? normalizedValue;
  for (final item in values) {
    if (valueOf(item) == target) return item;
  }
  return null;
}

T enumByNameOr<T extends Enum>(
  Iterable<T> values,
  Object? value, {
  required T fallback,
  String Function(String value)? normalize,
}) {
  return enumByName(values, value, normalize: normalize) ?? fallback;
}

final RegExp _looseDelimitedValueSeparator = RegExp(r'[\s,，;；]+');
const int _autoMillisecondsTimestampThreshold = 1000000000000;
const double kUnitIntervalMinimum = 0;
const double kUnitIntervalMaximum = 1;
const Set<String> _truthyBoolTexts = <String>{
  '1',
  'true',
  'yes',
  'y',
  'on',
  'enabled',
};
const Set<String> _falsyBoolTexts = <String>{
  '0',
  'false',
  'no',
  'n',
  'off',
  'disabled',
};

({bool ok, Object? value}) _tryDecodeJsonText(String value) {
  try {
    return (ok: true, value: jsonDecode(value));
  } on FormatException {
    return (ok: false, value: null);
  }
}

/// 尝试解析 JSON；空输入或解析失败时返回 `null`。
Object? tryDecodeJson(String value) {
  if (value.isEmpty) return null;
  final decoded = _tryDecodeJsonText(value);
  return decoded.ok ? decoded.value : null;
}

/// 全局复用的双空格缩进 JSON 编码器。
const JsonEncoder kPrettyJsonEncoder = JsonEncoder.withIndent('  ');

/// 输出缩进 JSON；[emptyMapAsBlank] 为真时将空映射输出为空串。
String prettyPrintJson(Object? value, {bool emptyMapAsBlank = false}) {
  if (emptyMapAsBlank && value is Map && value.isEmpty) return '';
  return kPrettyJsonEncoder.convert(value);
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
  int? limit,
}) {
  if (value is! List) return const <String>[];
  if (limit != null && limit <= 0) return const <String>[];
  return trimmedNonEmptyStrings(
    limit == null ? value : value.take(limit),
    ignoreLiteralNull: ignoreLiteralNull,
  );
}

List<String> stringListFromValue(
  Object? value, {
  Pattern separator = ',',
  bool ignoreLiteralNull = false,
  int? limit,
}) {
  if (limit != null && limit <= 0) return const <String>[];
  if (value is List) {
    return stringListFromListValue(
      value,
      ignoreLiteralNull: ignoreLiteralNull,
      limit: limit,
    );
  }
  if (value is String) {
    final items = splitTrimmedNonEmpty(value, separator: separator);
    return (limit == null ? items : items.take(limit))
        .where(
          (item) =>
              _keepStringListItem(item, ignoreLiteralNull: ignoreLiteralNull),
        )
        .toList(growable: false);
  }
  return const <String>[];
}

List<String>? optionalStringListFromJsonText(
  String value, {
  Pattern separator = ',',
  bool requireList = false,
  int? limit,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return const <String>[];
  final decoded = _tryDecodeJsonText(trimmed);
  if (!decoded.ok) return null;
  if (requireList && decoded.value is! List) return null;
  return stringListFromValue(decoded.value, separator: separator, limit: limit);
}

List<String> stringListFromValueOrJsonText(
  Object? value, {
  Pattern separator = ',',
  bool requireList = false,
  int? limit,
}) {
  return optionalStringListFromValueOrJsonText(
        value,
        separator: separator,
        requireList: requireList,
        limit: limit,
      ) ??
      const <String>[];
}

List<String>? optionalStringListFromValueOrJsonText(
  Object? value, {
  Pattern separator = ',',
  bool requireList = false,
  int? limit,
}) {
  if (value is List) {
    return stringListFromValue(value, separator: separator, limit: limit);
  }
  if (value is String) {
    return optionalStringListFromJsonText(
          value,
          separator: separator,
          requireList: requireList,
          limit: limit,
        ) ??
        (requireList
            ? null
            : stringListFromValue(value, separator: separator, limit: limit));
  }
  return null;
}

String stringFromValue(
  Object? value, {
  String fallback = '',
  bool ignoreLiteralNull = false,
}) {
  return optionalStringFromValue(value, ignoreLiteralNull: ignoreLiteralNull) ??
      fallback;
}

String lowercaseStringFromValue(Object? value, {String fallback = ''}) {
  return optionalLowercaseStringFromValue(value) ?? fallback.toLowerCase();
}

String? optionalStringFromValue(
  Object? value, {
  bool ignoreLiteralNull = false,
}) {
  if (value == null) return null;
  final text = '$value'.trim();
  if (text.isEmpty || (ignoreLiteralNull && text == 'null')) return null;
  return text;
}

String? optionalLowercaseStringFromValue(Object? value) {
  return optionalStringFromValue(value)?.toLowerCase();
}

String _decodeUriOrOriginal(String value, String Function(String) decode) {
  try {
    return decode(value);
  } on ArgumentError {
    return value;
  } on FormatException {
    return value;
  }
}

/// 解码 URI 组件；百分号编码截断或 UTF-8 无效时保留原值。
String decodeUriComponentOrOriginal(String value) {
  return _decodeUriOrOriginal(value, Uri.decodeComponent);
}

/// 解码查询参数；百分号编码截断或 UTF-8 无效时保留原值。
String decodeQueryComponentOrOriginal(String value) {
  return _decodeUriOrOriginal(value, Uri.decodeQueryComponent);
}

/// 解析查询串；损坏的百分号编码按原值保留。
Map<String, List<String>> decodeQueryParametersAll(
  String query, {
  bool requireValueSeparator = false,
}) {
  final parameters = <String, List<String>>{};
  for (final pair in query.split('&')) {
    if (pair.isEmpty) continue;
    final separator = pair.indexOf('=');
    if (requireValueSeparator && separator < 0) continue;
    final rawKey = separator < 0 ? pair : pair.substring(0, separator);
    if (rawKey.isEmpty) continue;
    final rawValue = separator < 0 ? '' : pair.substring(separator + 1);
    final key = decodeQueryComponentOrOriginal(rawKey);
    final value = decodeQueryComponentOrOriginal(rawValue);
    parameters.putIfAbsent(key, () => <String>[]).add(value);
  }
  return parameters;
}

/// 解码完整 URI 文本；百分号编码截断或 UTF-8 无效时保留原值。
String decodeUriFullOrOriginal(String value) {
  return _decodeUriOrOriginal(value, Uri.decodeFull);
}

Map<String, Object?> stringKeyedMapFromValue(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is! Map) return const <String, Object?>{};
  return value.map((key, item) => MapEntry('$key', item));
}

Map<String, Object?>? optionalStringKeyedMapFromValue(Object? value) {
  return value is Map ? stringKeyedMapFromValue(value) : null;
}

void validateCanonicalJsonSubset(
  Object? source,
  Object? canonical, {
  String path = 'value',
  int maxDepth = 128,
  int maxContainerItems = 100000,
  int maxTotalNodes = 1000000,
  bool requireMatchingScalarTypes = true,
}) {
  if (maxDepth < 0 || maxContainerItems <= 0 || maxTotalNodes <= 0) {
    throw ArgumentError('JSON 校验边界无效。');
  }
  final pending =
      <({Object? source, Object? canonical, String path, int depth})>[
        (source: source, canonical: canonical, path: path, depth: 0),
      ];
  var visitedNodes = 0;

  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    visitedNodes += 1;
    if (visitedNodes > maxTotalNodes) {
      throw FormatException('${current.path} 的节点数量超过限制。');
    }
    if (current.depth > maxDepth) {
      throw FormatException('${current.path} 的嵌套层级超过限制。');
    }

    final currentSource = current.source;
    final currentCanonical = current.canonical;
    if (currentSource is Map) {
      if (currentCanonical is! Map) {
        throw FormatException('${current.path} 必须是对象。');
      }
      if (currentSource.length > maxContainerItems) {
        throw FormatException('${current.path} 的字段数量超过限制。');
      }
      final entries = currentSource.entries.toList(growable: false);
      for (final entry in entries) {
        final key = '${entry.key}';
        if (!currentCanonical.containsKey(key)) {
          throw FormatException('${current.path} 包含不支持的字段：$key。');
        }
      }
      for (var index = entries.length - 1; index >= 0; index -= 1) {
        final entry = entries[index];
        final key = '${entry.key}';
        pending.add((
          source: entry.value,
          canonical: currentCanonical[key],
          path: '${current.path}.$key',
          depth: current.depth + 1,
        ));
      }
      continue;
    }
    if (currentSource is List) {
      if (currentCanonical is! List ||
          currentSource.length != currentCanonical.length) {
        throw FormatException('${current.path} 包含无效集合项。');
      }
      if (currentSource.length > maxContainerItems) {
        throw FormatException('${current.path} 的集合项数超过限制。');
      }
      for (var index = currentSource.length - 1; index >= 0; index -= 1) {
        pending.add((
          source: currentSource[index],
          canonical: currentCanonical[index],
          path: '${current.path}[$index]',
          depth: current.depth + 1,
        ));
      }
      continue;
    }
    if ((requireMatchingScalarTypes &&
            currentSource.runtimeType != currentCanonical.runtimeType) ||
        currentSource != currentCanonical) {
      throw FormatException('${current.path} 包含无效值。');
    }
  }
}

List<Map<String, Object?>> stringKeyedMapListFromValue(
  Object? value, {
  int? limit,
  bool fromEnd = false,
}) {
  if (value is! List) return const <Map<String, Object?>>[];
  if (limit != null && limit <= 0) return const <Map<String, Object?>>[];
  final out = <Map<String, Object?>>[];
  final items = limit == null
      ? value
      : fromEnd && value.length > limit
      ? value.skip(value.length - limit)
      : value.take(limit);
  for (final item in items) {
    if (item is Map) {
      out.add(stringKeyedMapFromValue(item));
    }
  }
  return out;
}

List<Map<String, Object?>> stringKeyedMapListFromValueOrJsonText(
  Object? value, {
  int? limit,
  bool fromEnd = false,
}) {
  return optionalStringKeyedMapListFromValueOrJsonText(
        value,
        limit: limit,
        fromEnd: fromEnd,
      ) ??
      const <Map<String, Object?>>[];
}

List<Map<String, Object?>>? optionalStringKeyedMapListFromValueOrJsonText(
  Object? value, {
  int? limit,
  bool fromEnd = false,
}) {
  if (value is List) {
    return stringKeyedMapListFromValue(value, limit: limit, fromEnd: fromEnd);
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const <Map<String, Object?>>[];
    final decoded = _tryDecodeJsonText(trimmed);
    if (decoded.value is List) {
      return stringKeyedMapListFromValue(
        decoded.value,
        limit: limit,
        fromEnd: fromEnd,
      );
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
  final map = optionalStringKeyedMapFromValue(value);
  if (map != null) return map;
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
  if (value is! String || nullIfBlank(value) == null) {
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
  if (nullIfBlank(value) == null) return const <int>[];
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
  bool parseNumericText = false,
}) {
  if (value is DateTime) return value;
  if (value is num) {
    return _dateTimeFromNumericTimestamp(
      value,
      mode: numericTimestampMode,
      requirePositive: requirePositiveTimestamp,
    );
  }
  if (value is String) {
    final trimmed = nullIfBlank(value);
    if (trimmed == null) return null;
    if (parseNumericText) {
      final numeric = num.tryParse(trimmed);
      if (numeric != null) {
        return _dateTimeFromNumericTimestamp(
          numeric,
          mode: numericTimestampMode,
          requirePositive: requirePositiveTimestamp,
        );
      }
    }
    return DateTime.tryParse(trimmed);
  }
  return null;
}

DateTime? utcDateTimeFromValue(
  Object? value, {
  DateTimeNumericTimestampMode numericTimestampMode =
      DateTimeNumericTimestampMode.milliseconds,
  bool requirePositiveTimestamp = false,
  bool parseNumericText = false,
}) {
  return dateTimeFromValue(
    value,
    numericTimestampMode: numericTimestampMode,
    requirePositiveTimestamp: requirePositiveTimestamp,
    parseNumericText: parseNumericText,
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
      raw >= _autoMillisecondsTimestampThreshold ? raw : raw * 1000,
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
    if (_truthyBoolTexts.contains(normalized)) return true;
    if (_falsyBoolTexts.contains(normalized)) return false;
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

double? optionalUnitIntervalFromValue(Object? value) {
  final parsed = optionalDoubleFromValue(value);
  return parsed == null ? null : clampUnitInterval(parsed);
}

List<double>? optionalUnitIntervalListFromValue(
  Object? value, {
  bool sorted = false,
}) {
  if (value is! Iterable) return null;
  final parsed = <double>[];
  for (final item in value) {
    final number = optionalDoubleFromValue(item);
    if (number == null) continue;
    parsed.add(clampUnitInterval(number));
  }
  if (sorted) parsed.sort();
  return List<double>.unmodifiable(parsed);
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

int? optionalNonNegativeRoundedIntFromValue(Object? value) {
  final parsed = optionalRoundedIntFromValue(value);
  return parsed == null || parsed < 0 ? null : parsed;
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

int nonNegativeRoundedIntFromValue(Object? value, {required int fallback}) {
  return optionalNonNegativeRoundedIntFromValue(value) ?? fallback;
}

int clampedIntFromValue(
  Object? value, {
  required int fallback,
  required int min,
  required int max,
}) {
  final parsed = intFromValue(value, fallback: fallback);
  return clampIntToRange(parsed, min: min, max: max);
}

int clampedIntegralIntFromValue(
  Object? value, {
  required int fallback,
  required int min,
  required int max,
}) {
  final parsed = optionalIntegralIntFromValue(value);
  final (:lower, :upper) = _orderedIntBounds(min, max);
  final safeFallback = fallback.clamp(lower, upper).toInt();
  return clampIntToRange(parsed ?? safeFallback, min: lower, max: upper);
}

int clampIntToRange(int value, {required int min, required int max}) {
  final (:lower, :upper) = _orderedIntBounds(min, max);
  return value.clamp(lower, upper).toInt();
}

class IntValueRange {
  const IntValueRange({
    required this.fallback,
    required this.min,
    required this.max,
  });

  final int fallback;
  final int min;
  final int max;

  int fromValue(Object? value) {
    return clampedIntFromValue(value, fallback: fallback, min: min, max: max);
  }

  int fromValueOr(Object? value, {required int fallback}) {
    return clampedIntFromValue(value, fallback: fallback, min: min, max: max);
  }

  int normalize(int value) {
    return clampIntToRange(value, min: min, max: max);
  }
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
  return clampDoubleToRange(
    parsed ?? safeFallback,
    min: lower,
    max: upper,
    fallback: safeFallback,
  );
}

double clampDoubleToRange(
  num value, {
  required double min,
  required double max,
  double? fallback,
}) {
  final (:lower, :upper) = _orderedDoubleBounds(min, max);
  final safeFallback = fallback != null && fallback.isFinite
      ? fallback.clamp(lower, upper).toDouble()
      : lower;
  if (!value.isFinite) {
    if (value.isInfinite) return value.isNegative ? lower : upper;
    return safeFallback;
  }
  return value.clamp(lower, upper).toDouble();
}

class DoubleValueRange {
  const DoubleValueRange({
    required this.fallback,
    required this.min,
    required this.max,
  });

  final double fallback;
  final double min;
  final double max;

  double fromValue(Object? value) {
    return clampedDoubleFromValue(
      value,
      fallback: fallback,
      min: min,
      max: max,
    );
  }

  double fromValueOr(Object? value, {required double fallback}) {
    return clampedDoubleFromValue(
      value,
      fallback: fallback,
      min: min,
      max: max,
    );
  }

  double normalize(num value) {
    return clampDoubleToRange(value, min: min, max: max, fallback: fallback);
  }
}

double clampUnitInterval(num value, {double fallback = kUnitIntervalMinimum}) {
  final safeFallback = fallback.isFinite
      ? fallback.clamp(kUnitIntervalMinimum, kUnitIntervalMaximum).toDouble()
      : kUnitIntervalMinimum;
  if (!value.isFinite) {
    if (value.isInfinite) {
      return value.isNegative ? kUnitIntervalMinimum : kUnitIntervalMaximum;
    }
    return safeFallback;
  }
  return value.clamp(kUnitIntervalMinimum, kUnitIntervalMaximum).toDouble();
}

double finiteUnitInterval(num value, {double fallback = kUnitIntervalMinimum}) {
  final safeFallback = clampUnitInterval(fallback);
  if (!value.isFinite) return safeFallback;
  return clampUnitInterval(value);
}

double unitRatio(num numerator, num denominator) {
  if (!denominator.isFinite || denominator <= 0) return kUnitIntervalMinimum;
  return clampUnitInterval(numerator / denominator);
}

int nonNegativeRemaining(int capacity, int used) {
  if (capacity <= 0) return 0;
  final remaining = capacity - used;
  return remaining < 0 ? 0 : remaining;
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

/// 紧凑计数格式化：1000→1.0K, 1000000→1.0M, 1000000000→1.0B。
String formatCompactCount(num value, {int fractionDigits = 1}) {
  if (!value.isFinite) return '--';
  final abs = value.abs();
  if (abs >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(fractionDigits)}B';
  }
  if (abs >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(fractionDigits)}M';
  }
  if (abs >= 1000) {
    return '${(value / 1000).toStringAsFixed(fractionDigits)}K';
  }
  if (value is int) return '$value';
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(fractionDigits);
}
