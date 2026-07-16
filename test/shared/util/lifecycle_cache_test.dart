import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/lifecycle_cache.dart';

void main() {
  test('可空缓存命中 null 时不会重复创建且会刷新最近使用顺序', () {
    final cache = LifecycleLruCache<String?>(maxEntries: 2);
    var createCount = 0;
    cache.put('nullable', null);
    cache.put('older', '旧值');

    final value = cache.putIfAbsent('nullable', () {
      createCount++;
      return '错误的新值';
    });
    cache.put('newer', '新值');

    expect(value, isNull);
    expect(createCount, 0);
    expect(cache.containsKey('nullable'), isTrue);
    expect(cache.containsKey('older'), isFalse);
    expect(cache.get('newer'), '新值');
  });
}
