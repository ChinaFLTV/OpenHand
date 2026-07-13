import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/lifecycle_cache.dart';

void main() {
  test('LRU cache enforces entry and aggregate cost limits', () {
    final cache = LifecycleLruCache<List<int>>(
      maxEntries: 3,
      maxCost: 4,
      costOf: (value) => value.length,
    );

    cache.put('one', <int>[1, 2]);
    cache.put('two', <int>[3]);
    expect(cache.get('one'), <int>[1, 2]);
    cache.put('three', <int>[4, 5]);

    expect(cache.get('two'), isNull);
    expect(cache.get('one'), <int>[1, 2]);
    expect(cache.get('three'), <int>[4, 5]);

    cache.put('one', <int>[1, 2, 3, 4, 5]);
    expect(cache.get('one'), isNull);
  });

  test('putIfAbsent and removeWhere preserve cache accounting', () {
    final cache = LifecycleLruCache<String>(maxEntries: 3);
    var creates = 0;

    expect(cache.putIfAbsent('session:a', () => '${++creates}'), '1');
    expect(cache.putIfAbsent('session:a', () => '${++creates}'), '1');
    cache.put('session:b', '2');
    cache.put('other', '3');
    cache.removeWhere((key, _) => key.startsWith('session:'));
    cache.put('new', '4');

    expect(creates, 1);
    expect(cache.get('session:a'), isNull);
    expect(cache.get('session:b'), isNull);
    expect(cache.get('other'), '3');
    expect(cache.get('new'), '4');
  });
}
