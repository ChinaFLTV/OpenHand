import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/bounded_animation.dart';

void main() {
  group('openHandBoundedProgress', () {
    test('clamps values into the default animation range', () {
      expect(openHandBoundedProgress(-0.25), 0.0);
      expect(openHandBoundedProgress(0.5), 0.5);
      expect(openHandBoundedProgress(1.25), 1.0);
    });

    test('orders reversed custom bounds before clamping', () {
      expect(openHandBoundedProgress(0.75, min: 1.0, max: 0.25), 0.75);
      expect(openHandBoundedProgress(2.0, min: 1.0, max: 0.25), 1.0);
    });

    test('falls back to finite bounds for non-finite inputs', () {
      expect(openHandBoundedProgress(double.nan), 0.0);
      expect(openHandBoundedProgress(double.infinity), 1.0);
      expect(openHandBoundedProgress(0.5, min: double.nan), 0.5);
      expect(openHandBoundedProgress(2.0, max: double.nan), 1.0);
    });
  });
}
