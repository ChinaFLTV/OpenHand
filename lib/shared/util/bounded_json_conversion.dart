import 'dart:collection';

enum JsonNonFiniteNumberBehavior { stringify, zero }

/// JSON 安全转换的资源与兼容策略。
final class BoundedJsonConversionConfig {
  const BoundedJsonConversionConfig({
    this.maxDepth = 64,
    this.maxContainerItems = 10000,
    this.maxTotalNodes = 100000,
    this.nonFiniteNumberBehavior = JsonNonFiniteNumberBehavior.stringify,
    this.maxDepthPlaceholder = '<max-depth>',
    this.cyclicMapPlaceholder = '<cyclic-map>',
    this.cyclicIterablePlaceholder = '<cyclic-iterable>',
    this.truncatedPlaceholder = '<truncated>',
  }) : assert(maxDepth >= 0),
       assert(maxContainerItems > 0),
       assert(maxTotalNodes > 0);

  final int maxDepth;
  final int maxContainerItems;
  final int maxTotalNodes;
  final JsonNonFiniteNumberBehavior nonFiniteNumberBehavior;
  final String maxDepthPlaceholder;
  final String cyclicMapPlaceholder;
  final String cyclicIterablePlaceholder;
  final String truncatedPlaceholder;
}

Object? convertToJsonSafeValue(
  Object? value, {
  BoundedJsonConversionConfig config = const BoundedJsonConversionConfig(),
}) {
  return _BoundedJsonConverter(config).convert(value);
}

Map<String, Object?> convertToJsonSafeMap(
  Map<Object?, Object?> value, {
  BoundedJsonConversionConfig config = const BoundedJsonConversionConfig(),
}) {
  return Map<String, Object?>.from(
    _BoundedJsonConverter(config).convert(value) as Map<String, Object?>,
  );
}

final class _BoundedJsonConverter {
  _BoundedJsonConverter(this.config);

  final BoundedJsonConversionConfig config;
  final Set<Object> _activeContainers = HashSet<Object>.identity();
  int _visitedNodes = 0;

  Object? convert(Object? value, [int depth = 0]) {
    if (_visitedNodes >= config.maxTotalNodes) {
      return config.truncatedPlaceholder;
    }
    _visitedNodes += 1;

    if (value == null || value is String || value is bool) return value;
    if (value is num) {
      if (value.isFinite) return value;
      return switch (config.nonFiniteNumberBehavior) {
        JsonNonFiniteNumberBehavior.stringify => value.toString(),
        JsonNonFiniteNumberBehavior.zero => 0,
      };
    }
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Duration) return value.inMilliseconds;
    if (value is Uri || value is BigInt) return value.toString();
    if (value is Enum) return value.name;
    if (depth >= config.maxDepth) return config.maxDepthPlaceholder;
    if (value is Map) return _convertMap(value, depth);
    if (value is Iterable) return _convertIterable(value, depth);
    return value.toString();
  }

  Object _convertMap(Map<Object?, Object?> value, int depth) {
    if (!_activeContainers.add(value)) return config.cyclicMapPlaceholder;
    try {
      final result = <String, Object?>{};
      final iterator = value.entries.iterator;
      var itemCount = 0;
      while (itemCount < config.maxContainerItems &&
          _visitedNodes < config.maxTotalNodes &&
          iterator.moveNext()) {
        final entry = iterator.current;
        result['${entry.key}'] = convert(entry.value, depth + 1);
        itemCount += 1;
      }
      if ((itemCount >= config.maxContainerItems ||
              _visitedNodes >= config.maxTotalNodes) &&
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
          iterator.moveNext()) {
        result.add(convert(iterator.current, depth + 1));
        itemCount += 1;
      }
      if ((itemCount >= config.maxContainerItems ||
              _visitedNodes >= config.maxTotalNodes) &&
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
}
