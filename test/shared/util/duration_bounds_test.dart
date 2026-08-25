import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/duration_bounds.dart';

void main() {
  group('有界缩放时长', () {
    test('按比例缩放并限制到上下界', () {
      expect(
        scaledDurationWithinRange(
          const Duration(hours: 6),
          2,
          min: const Duration(minutes: 30),
          max: const Duration(days: 30),
        ),
        const Duration(hours: 3),
      );
      expect(
        scaledDurationWithinRange(
          const Duration(hours: 6),
          0.001,
          min: const Duration(minutes: 30),
          max: const Duration(days: 30),
        ),
        const Duration(days: 30),
      );
    });

    test('拒绝无效比例并兼容倒置边界', () {
      for (final scale in <double>[0, -1, double.nan, double.infinity]) {
        expect(
          scaledDurationWithinRange(
            const Duration(hours: 6),
            scale,
            min: const Duration(minutes: 30),
            max: const Duration(days: 30),
          ),
          isNull,
        );
      }
      expect(
        scaledDurationWithinRange(
          const Duration(hours: 1),
          1,
          min: const Duration(days: 1),
          max: const Duration(minutes: 30),
        ),
        const Duration(hours: 1),
      );
    });
  });
}
