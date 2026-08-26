import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/stable_hash.dart';

void main() {
  group('稳定 JSON', () {
    test('对象字段顺序不影响编码和等价判断', () {
      final left = <String, Object?>{
        'name': 'OpenHand',
        'settings': <String, Object?>{'enabled': true, 'count': 2},
      };
      final right = <String, Object?>{
        'settings': <String, Object?>{'count': 2, 'enabled': true},
        'name': 'OpenHand',
      };

      expect(stableJsonEncode(left), stableJsonEncode(right));
      expect(stableJsonEquals(left, right), isTrue);
      expect(stableJsonSha256(left), stableJsonSha256(right));
    });

    test('数组顺序仍参与等价判断', () {
      expect(stableJsonEquals([1, 2, 3], [3, 2, 1]), isFalse);
    });

    test('循环对象能够终止并保持结构语义', () {
      final left = <String, Object?>{};
      final right = <String, Object?>{};
      left['self'] = left;
      right['self'] = right;

      expect(stableJsonEquals(left, right), isTrue);
      right['extra'] = true;
      expect(stableJsonEquals(left, right), isFalse);
    });
  });
}
