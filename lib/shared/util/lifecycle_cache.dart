import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

const int _defaultLifecycleCacheEntryCost = 1;
const int _maxLifecycleCacheEntryCost = 1 << 62;

class LifecycleLruCache<V> {
  LifecycleLruCache({
    required this.maxEntries,
    int? maxCost,
    int Function(V value)? costOf,
  }) : maxCost = maxCost == null || maxCost <= 0 ? null : maxCost,
       _costOf = costOf;

  final int maxEntries;
  final int? maxCost;
  final int Function(V value)? _costOf;
  final LinkedHashMap<String, _LifecycleCacheEntry<V>> _entries =
      LinkedHashMap<String, _LifecycleCacheEntry<V>>();
  int _totalCost = 0;

  /// Distinguishes a cached nullable value from an absent entry.
  bool containsKey(String key) => _entries.containsKey(key);

  V? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry.value;
  }

  void put(String key, V value) {
    if (maxEntries <= 0) return;
    final cost = _entryCost(value);
    final costLimit = maxCost;
    final previous = _entries.remove(key);
    if (previous != null) _totalCost -= previous.cost;
    if (costLimit != null && cost > costLimit) return;
    _entries[key] = _LifecycleCacheEntry<V>(value, cost);
    _totalCost += cost;
    _evictOverflow();
  }

  V putIfAbsent(String key, V Function() create) {
    final cached = get(key);
    if (cached != null) return cached;
    final value = create();
    put(key, value);
    return value;
  }

  V? remove(String key) {
    final removed = _entries.remove(key);
    if (removed == null) return null;
    _totalCost -= removed.cost;
    return removed.value;
  }

  void removeWhere(bool Function(String key, V value) test) {
    final keys = <String>[];
    for (final entry in _entries.entries) {
      if (test(entry.key, entry.value.value)) keys.add(entry.key);
    }
    for (final key in keys) {
      remove(key);
    }
  }

  void clear() {
    _entries.clear();
    _totalCost = 0;
  }

  /// Returns an immutable insertion-ordered copy without changing recency.
  Map<String, V> snapshot() => Map<String, V>.unmodifiable(<String, V>{
    for (final entry in _entries.entries) entry.key: entry.value.value,
  });

  int _entryCost(V value) {
    final cost = _costOf?.call(value) ?? _defaultLifecycleCacheEntryCost;
    return cost.clamp(0, _maxLifecycleCacheEntryCost);
  }

  void _evictOverflow() {
    final costLimit = maxCost;
    while (_entries.length > maxEntries ||
        (costLimit != null && _totalCost > costLimit)) {
      if (_entries.isEmpty) {
        _totalCost = 0;
        return;
      }
      final oldestKey = _entries.keys.first;
      final oldest = _entries.remove(oldestKey);
      if (oldest != null) _totalCost -= oldest.cost;
    }
  }
}

class _LifecycleCacheEntry<V> {
  const _LifecycleCacheEntry(this.value, this.cost);

  final V value;
  final int cost;
}

String stableJsonSha256(Object? value) {
  final canonical = jsonEncode(_canonicalJsonValue(value));
  return sha256.convert(utf8.encode(canonical)).toString();
}

Object? _canonicalJsonValue(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (value.isFinite) return value;
    return value.toString();
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
      return _canonicalJsonSortKey(
        a.value,
      ).compareTo(_canonicalJsonSortKey(b.value));
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

String _canonicalJsonSortKey(Object? value) {
  return jsonEncode(value);
}
