import 'dart:collection';

const int _defaultLifecycleCacheEntryCost = 1;
const int _maxLifecycleCacheEntryCost = 1 << 62;

class LifecycleLruCache<V> {
  LifecycleLruCache({required this.maxEntries, int? maxCost, this._costOf})
    : maxCost = maxCost == null || maxCost <= 0 ? null : maxCost;

  final int maxEntries;
  final int? maxCost;
  final int Function(V value)? _costOf;
  final LinkedHashMap<String, _LifecycleCacheEntry<V>> _entries =
      LinkedHashMap<String, _LifecycleCacheEntry<V>>();
  int _totalCost = 0;

  /// 区分已缓存的空值与不存在的条目。
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
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached.value;
    }
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

  bool removeIfIdentical(String key, V expectedValue) {
    final entry = _entries[key];
    if (entry == null || !identical(entry.value, expectedValue)) return false;
    _entries.remove(key);
    _totalCost -= entry.cost;
    return true;
  }

  /// 异步值完成后回填真实成本；条目已被替换时不影响新值。
  bool updateCostIfIdentical(String key, V expectedValue, int cost) {
    final entry = _entries[key];
    if (entry == null || !identical(entry.value, expectedValue)) return false;
    final normalizedCost = cost.clamp(0, _maxLifecycleCacheEntryCost);
    final costLimit = maxCost;
    if (costLimit != null && normalizedCost > costLimit) {
      remove(key);
      return false;
    }
    _totalCost += normalizedCost - entry.cost;
    entry.cost = normalizedCost;
    _evictOverflow();
    return identical(_entries[key]?.value, expectedValue);
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

  /// 返回保持插入顺序的不可变副本，不改变条目新旧顺序。
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
  _LifecycleCacheEntry(this.value, this.cost);

  final V value;
  int cost;
}
