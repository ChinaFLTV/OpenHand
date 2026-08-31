import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/lifecycle_cache.dart';

void main() {
  test('LRU 缓存读取后更新淘汰顺序', () {
    final cache = LifecycleLruCache<int>(maxEntries: 2);
    cache.put('a', 1);
    cache.put('b', 2);

    expect(cache.get('a'), 1);
    cache.put('c', 3);

    expect(cache.containsKey('a'), isTrue);
    expect(cache.containsKey('b'), isFalse);
    expect(cache.containsKey('c'), isTrue);
  });

  test('成本上限会拒绝超大条目并淘汰最旧条目', () {
    final cache = LifecycleLruCache<String>(
      maxEntries: 4,
      maxCost: 7,
      costOf: (value) => value.length,
    );
    cache.put('a', '12');
    cache.put('b', '345');
    cache.put('c', '6789');

    expect(cache.containsKey('a'), isFalse);
    expect(cache.snapshot(), <String, String>{'b': '345', 'c': '6789'});

    cache.put('oversize', '12345678');
    expect(cache.containsKey('oversize'), isFalse);
  });

  test('异步成本回填不会误改已替换条目', () {
    final first = Object();
    final second = Object();
    final cache = LifecycleLruCache<Object>(maxEntries: 2, maxCost: 4);
    cache.put('item', first);
    cache.put('item', second);

    expect(cache.updateCostIfIdentical('item', first, 4), isFalse);
    expect(cache.updateCostIfIdentical('item', second, 4), isTrue);
    expect(cache.get('item'), same(second));
  });

  test('缓存禁用时仍返回创建结果但不保留条目', () {
    final cache = LifecycleLruCache<int>(maxEntries: 0);
    var calls = 0;

    expect(cache.putIfAbsent('key', () => ++calls), 1);
    expect(cache.putIfAbsent('key', () => ++calls), 2);
    expect(cache.snapshot(), isEmpty);
  });
}
