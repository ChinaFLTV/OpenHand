import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  group('弹窗尺寸约束', () {
    test('正常按视口、边距和最大值收敛', () {
      final value = resolveOpenHandResponsiveDialogExtent(
        viewportExtent: 1000,
        maxExtent: 900,
        minAvailableExtent: 320,
        viewportMargin: 80,
        viewportFraction: 0.9,
      );

      expect(value, 900);
    });

    test('非法边距和比例不会产生异常尺寸', () {
      final value = resolveOpenHandResponsiveDialogExtent(
        viewportExtent: 600,
        maxExtent: double.nan,
        minAvailableExtent: 240,
        viewportMargin: double.nan,
        viewportFraction: double.infinity,
      );

      expect(value.isFinite, isTrue);
      expect(value, 600);
    });

    test('负边距按零处理，避免窗口被意外放大', () {
      final value = resolveOpenHandResponsiveDialogExtent(
        viewportExtent: 600,
        maxExtent: 700,
        minAvailableExtent: 240,
        viewportMargin: -120,
      );

      expect(value, 600);
    });
  });
}
