import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/lifecycle_cache.dart';

void main() {
  group('LifecycleLruCache', () {
    test(
      'evicts the least recently used entry when max entries is exceeded',
      () {
        final cache = LifecycleLruCache<String>(maxEntries: 2);
        cache.put('a', 'alpha');
        cache.put('b', 'beta');

        expect(cache.get('a'), 'alpha');
        cache.put('c', 'gamma');

        expect(cache.get('b'), isNull);
        expect(cache.get('a'), 'alpha');
        expect(cache.get('c'), 'gamma');
      },
    );

    test('evicts by total cost and rejects entries above max cost', () {
      final cache = LifecycleLruCache<String>(
        maxEntries: 10,
        maxCost: 5,
        costOf: (value) => value.length,
      );

      cache.put('a', 'aa');
      cache.put('b', 'bbb');
      cache.put('c', 'cc');

      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 'bbb');
      expect(cache.get('c'), 'cc');

      cache.put('too-large', 'toolarge');
      expect(cache.get('too-large'), isNull);
    });

    test('clamps negative entry costs to zero', () {
      final cache = LifecycleLruCache<String>(
        maxEntries: 2,
        maxCost: 1,
        costOf: (_) => -10,
      );

      cache.put('a', 'alpha');
      cache.put('b', 'beta');

      expect(cache.get('a'), 'alpha');
      expect(cache.get('b'), 'beta');
    });
  });

  group('stableJsonSha256', () {
    test('is stable across map insertion order', () {
      final first = stableJsonSha256(<String, Object?>{
        'b': 2,
        'a': <String, Object?>{'y': true, 'x': 1},
      });
      final second = stableJsonSha256(<String, Object?>{
        'a': <String, Object?>{'x': 1, 'y': true},
        'b': 2,
      });

      expect(first, second);
    });

    test('normalizes non-finite doubles without throwing', () {
      expect(stableJsonSha256(double.nan), stableJsonSha256('NaN'));
      expect(
        stableJsonSha256(<String, Object?>{'value': double.infinity}),
        stableJsonSha256(<String, Object?>{'value': 'Infinity'}),
      );
    });
  });
}
