import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'bounded_json_conversion.dart';

const int kStableFnv1a32OffsetBasis = 0x811c9dc5;
const int kStableFnv1a32Prime = 0x01000193;
const int kStableFnv1a32Mask = 0xffffffff;
const int kStableSha256HexLength = 64;
const int _stableJsonEqualityMaxDepth = 128;
const int _stableJsonEqualityMaxNodes = 100000;

String stableFnv1a32Hex(String content) {
  var hash = kStableFnv1a32OffsetBasis;
  for (final codeUnit in content.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * kStableFnv1a32Prime) & kStableFnv1a32Mask;
  }
  return hash.toUnsigned(32).toRadixString(16).padLeft(8, '0');
}

String stableSha256Hex(String content, {int length = kStableSha256HexLength}) {
  final full = crypto.sha256.convert(utf8.encode(content)).toString();
  final safeLength = length.clamp(1, full.length);
  return full.substring(0, safeLength);
}

/// 对 JSON 类数据有界规范化后计算稳定指纹，不受 Map 插入顺序影响。
String stableJsonSha256(Object? value) {
  return stableSha256Hex(stableJsonEncode(value));
}

/// 对 JSON 类数据有界规范化后编码，不受 Map 插入顺序影响。
String stableJsonEncode(Object? value) {
  final safeValue = convertToJsonSafeValue(value);
  return jsonEncode(_canonicalJsonValue(safeValue));
}

/// 比较两份 JSON 类数据；对象字段顺序不影响结果，数组顺序保持语义。
bool stableJsonEquals(Object? left, Object? right) {
  return _StableJsonEquality().equals(left, right);
}

final class _StableJsonEquality {
  final Map<Object, Set<Object>> _activePairs =
      HashMap<Object, Set<Object>>.identity();
  int _visitedNodes = 0;

  bool equals(Object? left, Object? right, [int depth = 0]) {
    if (identical(left, right)) {
      if (depth == 0) return true;
      if (_visitedNodes >= _stableJsonEqualityMaxNodes) return false;
      _visitedNodes += 1;
      return true;
    }
    if (depth > _stableJsonEqualityMaxDepth ||
        _visitedNodes >= _stableJsonEqualityMaxNodes) {
      return false;
    }
    _visitedNodes += 1;

    if (left == null || right == null) return false;
    if (left is num && right is num) {
      if (!left.isFinite || !right.isFinite) {
        return left.toString() == right.toString();
      }
      return left == right;
    }
    if (left is String || right is String || left is bool || right is bool) {
      return left == right;
    }
    if (left is DateTime || right is DateTime) {
      return left is DateTime &&
          right is DateTime &&
          left.toUtc() == right.toUtc();
    }
    if (left is Duration || right is Duration) {
      return left is Duration &&
          right is Duration &&
          left.inMilliseconds == right.inMilliseconds;
    }
    if (left is Uri || right is Uri || left is BigInt || right is BigInt) {
      return left.runtimeType == right.runtimeType &&
          left.toString() == right.toString();
    }
    if (left is Enum || right is Enum) {
      return left is Enum && right is Enum && left.name == right.name;
    }
    if (left is Map || right is Map) {
      if (left is! Map || right is! Map) return false;
      if (left.length > _stableJsonEqualityMaxNodes ||
          right.length > _stableJsonEqualityMaxNodes) {
        return false;
      }
      return _compareContainers(left, right, () {
        final leftMap = _stringKeyedMap(left);
        final rightMap = _stringKeyedMap(right);
        if (leftMap.length != rightMap.length) return false;
        for (final entry in leftMap.entries) {
          if (!rightMap.containsKey(entry.key) ||
              !equals(entry.value, rightMap[entry.key], depth + 1)) {
            return false;
          }
        }
        return true;
      });
    }
    if (left is Iterable || right is Iterable) {
      if (left is! Iterable || right is! Iterable) return false;
      return _compareContainers(left, right, () {
        final leftIterator = left.iterator;
        final rightIterator = right.iterator;
        while (true) {
          final hasLeft = leftIterator.moveNext();
          final hasRight = rightIterator.moveNext();
          if (hasLeft != hasRight) return false;
          if (!hasLeft) return true;
          if (!equals(leftIterator.current, rightIterator.current, depth + 1)) {
            return false;
          }
        }
      });
    }
    return left.runtimeType == right.runtimeType &&
        left.toString() == right.toString();
  }

  bool _compareContainers(Object left, Object right, bool Function() compare) {
    final activeRights = _activePairs.putIfAbsent(
      left,
      HashSet<Object>.identity,
    );
    if (!activeRights.add(right)) return true;
    try {
      return compare();
    } finally {
      activeRights.remove(right);
      if (activeRights.isEmpty) _activePairs.remove(left);
    }
  }

  Map<String, Object?> _stringKeyedMap(Map<Object?, Object?> value) {
    return <String, Object?>{
      for (final entry in value.entries) '${entry.key}': entry.value,
    };
  }
}

Object? _canonicalJsonValue(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    return value.isFinite ? value : value.toString();
  }
  if (value is num) return value;
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Enum) return value.name;
  if (value is Map) {
    final entries = <MapEntry<String, Object?>>[];
    value.forEach((key, child) {
      entries.add(
        MapEntry<String, Object?>('$key', _canonicalJsonValue(child)),
      );
    });
    entries.sort((a, b) {
      final keyOrder = a.key.compareTo(b.key);
      if (keyOrder != 0) return keyOrder;
      return jsonEncode(a.value).compareTo(jsonEncode(b.value));
    });
    return <String, Object?>{
      for (final entry in entries) entry.key: entry.value,
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalJsonValue).toList(growable: false);
  }
  return '$value';
}
