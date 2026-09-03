import 'dart:collection';

import 'argument_guards.dart';
import 'text_clip.dart';

enum JsonNonFiniteNumberBehavior { stringify, zero }

typedef JsonMapValueTransformer = Object? Function(String key, Object? value);

typedef JsonValueMetrics = ({int nodeCount, int stringCodeUnits});

/// 非递归校验 JSON 值的结构预算；超限、循环引用或非 JSON 类型返回 null。
JsonValueMetrics? measureJsonValueWithinBounds(
  Object? value, {
  required int maxDepth,
  required int maxContainerItems,
  required int maxTotalNodes,
  required int maxStringCodeUnits,
  required int maxTotalStringCodeUnits,
}) {
  requireNonNegativeInt(maxDepth, 'maxDepth');
  requirePositiveInt(maxContainerItems, 'maxContainerItems');
  requirePositiveInt(maxTotalNodes, 'maxTotalNodes');
  requirePositiveInt(maxStringCodeUnits, 'maxStringCodeUnits');
  requirePositiveInt(maxTotalStringCodeUnits, 'maxTotalStringCodeUnits');

  final pending = <({Object? value, int depth, bool exiting})>[
    (value: value, depth: 0, exiting: false),
  ];
  final activeContainers = HashSet<Object>.identity();
  var nodeCount = 0;
  var stringCodeUnits = 0;

  bool addString(String text) {
    if (text.length > maxStringCodeUnits ||
        text.length > maxTotalStringCodeUnits - stringCodeUnits) {
      return false;
    }
    stringCodeUnits += text.length;
    return true;
  }

  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (current.exiting) {
      activeContainers.remove(current.value);
      continue;
    }
    nodeCount += 1;
    if (nodeCount > maxTotalNodes || current.depth > maxDepth) return null;

    final currentValue = current.value;
    if (currentValue == null || currentValue is bool) continue;
    if (currentValue is num) {
      if (!currentValue.isFinite) return null;
      continue;
    }
    if (currentValue is String) {
      if (!addString(currentValue)) return null;
      continue;
    }
    if (currentValue is Map) {
      if (currentValue.length > maxContainerItems ||
          !activeContainers.add(currentValue)) {
        return null;
      }
      pending.add((value: currentValue, depth: current.depth, exiting: true));
      for (final entry in currentValue.entries) {
        final key = entry.key;
        if (key is! String || !addString(key)) return null;
        pending.add((
          value: entry.value,
          depth: current.depth + 1,
          exiting: false,
        ));
      }
      continue;
    }
    if (currentValue is List) {
      if (currentValue.length > maxContainerItems ||
          !activeContainers.add(currentValue)) {
        return null;
      }
      pending.add((value: currentValue, depth: current.depth, exiting: true));
      for (final item in currentValue) {
        pending.add((value: item, depth: current.depth + 1, exiting: false));
      }
      continue;
    }
    return null;
  }

  return (nodeCount: nodeCount, stringCodeUnits: stringCodeUnits);
}

/// JSON 安全转换的资源与兼容策略。
final class BoundedJsonConversionConfig {
  const BoundedJsonConversionConfig({
    this.maxDepth = 64,
    this.maxContainerItems = 10000,
    this.maxTotalNodes = 100000,
    this.maxStringCodeUnits,
    this.maxTotalStringCodeUnits,
    this.truncatedStringSuffix = '...',
    this.mapValueTransformer,
    this.nonFiniteNumberBehavior = JsonNonFiniteNumberBehavior.stringify,
    this.maxDepthPlaceholder = '<max-depth>',
    this.cyclicMapPlaceholder = '<cyclic-map>',
    this.cyclicIterablePlaceholder = '<cyclic-iterable>',
    this.truncatedPlaceholder = '<truncated>',
  });

  final int maxDepth;
  final int maxContainerItems;
  final int maxTotalNodes;
  final int? maxStringCodeUnits;
  final int? maxTotalStringCodeUnits;
  final String truncatedStringSuffix;
  final JsonMapValueTransformer? mapValueTransformer;
  final JsonNonFiniteNumberBehavior nonFiniteNumberBehavior;
  final String maxDepthPlaceholder;
  final String cyclicMapPlaceholder;
  final String cyclicIterablePlaceholder;
  final String truncatedPlaceholder;

  void validate() {
    requireNonNegativeInt(maxDepth, 'maxDepth');
    requirePositiveInt(maxContainerItems, 'maxContainerItems');
    requirePositiveInt(maxTotalNodes, 'maxTotalNodes');
    final perStringLimit = maxStringCodeUnits;
    if (perStringLimit != null) {
      requireNonNegativeInt(perStringLimit, 'maxStringCodeUnits');
    }
    final totalStringLimit = maxTotalStringCodeUnits;
    if (totalStringLimit != null) {
      requireNonNegativeInt(totalStringLimit, 'maxTotalStringCodeUnits');
    }
  }
}

Object? convertToJsonSafeValue(
  Object? value, {
  BoundedJsonConversionConfig config = const BoundedJsonConversionConfig(),
}) {
  config.validate();
  return _BoundedJsonConverter(config).convert(value);
}

Map<String, Object?> convertToJsonSafeMap(
  Map<Object?, Object?> value, {
  BoundedJsonConversionConfig config = const BoundedJsonConversionConfig(),
}) {
  config.validate();
  return Map<String, Object?>.from(
    _BoundedJsonConverter(config).convert(value) as Map<String, Object?>,
  );
}

final class _BoundedJsonConverter {
  _BoundedJsonConverter(this.config);

  final BoundedJsonConversionConfig config;
  final Set<Object> _activeContainers = HashSet<Object>.identity();
  int _visitedNodes = 0;
  int _convertedStringCodeUnits = 0;

  Object? convert(Object? value, [int depth = 0]) {
    if (_visitedNodes >= config.maxTotalNodes) {
      return config.truncatedPlaceholder;
    }
    _visitedNodes += 1;

    if (value == null || value is bool) return value;
    if (value is String) return _convertString(value);
    if (value is num) {
      if (value.isFinite) return value;
      return switch (config.nonFiniteNumberBehavior) {
        JsonNonFiniteNumberBehavior.stringify => _convertString(
          value.toString(),
        ),
        JsonNonFiniteNumberBehavior.zero => 0,
      };
    }
    if (value is DateTime) {
      return _convertString(value.toUtc().toIso8601String());
    }
    if (value is Duration) return value.inMilliseconds;
    if (value is Uri || value is BigInt) {
      return _convertString(value.toString());
    }
    if (value is Enum) return _convertString(value.name);
    if (depth >= config.maxDepth) return config.maxDepthPlaceholder;
    if (value is Map) return _convertMap(value, depth);
    if (value is Iterable) return _convertIterable(value, depth);
    return _convertString(value.toString());
  }

  Object _convertMap(Map<Object?, Object?> value, int depth) {
    if (!_activeContainers.add(value)) return config.cyclicMapPlaceholder;
    try {
      final result = <String, Object?>{};
      final iterator = value.entries.iterator;
      var itemCount = 0;
      while (itemCount < config.maxContainerItems &&
          _visitedNodes < config.maxTotalNodes &&
          _hasStringBudget &&
          iterator.moveNext()) {
        final entry = iterator.current;
        final key = '${entry.key}';
        final transformer = config.mapValueTransformer;
        final entryValue = transformer == null
            ? entry.value
            : transformer(key, entry.value);
        result[_convertString(key)] = convert(entryValue, depth + 1);
        itemCount += 1;
      }
      if ((itemCount >= config.maxContainerItems ||
              _visitedNodes >= config.maxTotalNodes ||
              !_hasStringBudget) &&
          iterator.moveNext()) {
        result[_availableTruncationKey(result)] = config.truncatedPlaceholder;
      }
      return result;
    } finally {
      _activeContainers.remove(value);
    }
  }

  Object _convertIterable(Iterable<Object?> value, int depth) {
    if (!_activeContainers.add(value)) {
      return config.cyclicIterablePlaceholder;
    }
    try {
      final result = <Object?>[];
      final iterator = value.iterator;
      var itemCount = 0;
      while (itemCount < config.maxContainerItems &&
          _visitedNodes < config.maxTotalNodes &&
          _hasStringBudget &&
          iterator.moveNext()) {
        result.add(convert(iterator.current, depth + 1));
        itemCount += 1;
      }
      if ((itemCount >= config.maxContainerItems ||
              _visitedNodes >= config.maxTotalNodes ||
              !_hasStringBudget) &&
          iterator.moveNext()) {
        result.add(config.truncatedPlaceholder);
      }
      return result;
    } finally {
      _activeContainers.remove(value);
    }
  }

  String _availableTruncationKey(Map<String, Object?> result) {
    var key = config.truncatedPlaceholder;
    while (result.containsKey(key)) {
      key = '_$key';
    }
    return key;
  }

  String _convertString(String value) {
    final perStringLimit = config.maxStringCodeUnits;
    final totalLimit = config.maxTotalStringCodeUnits;
    if (perStringLimit == null && totalLimit == null) return value;

    var maxCodeUnits = perStringLimit ?? value.length;
    if (totalLimit != null) {
      final remaining = totalLimit - _convertedStringCodeUnits;
      if (maxCodeUnits > remaining) maxCodeUnits = remaining;
    }
    final converted = value.length <= maxCodeUnits
        ? value
        : clipTextByCodeUnits(
            value,
            maxCodeUnits,
            suffix: config.truncatedStringSuffix,
          );
    _convertedStringCodeUnits += converted.length;
    return converted;
  }

  bool get _hasStringBudget {
    final limit = config.maxTotalStringCodeUnits;
    return limit == null || _convertedStringCodeUnits < limit;
  }
}
