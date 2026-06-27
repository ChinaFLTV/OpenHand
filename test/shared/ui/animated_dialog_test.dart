import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  group('resolveOpenHandResponsiveDialogExtent', () {
    test('caps extent by viewport fraction before max extent', () {
      final extent = resolveOpenHandResponsiveDialogExtent(
        viewportExtent: 1000,
        maxExtent: 900,
        viewportFraction: 0.8,
      );

      expect(extent, 800);
    });

    test('keeps minimum available extent when fraction would be too small', () {
      final extent = resolveOpenHandResponsiveDialogExtent(
        viewportExtent: 600,
        maxExtent: double.infinity,
        minAvailableExtent: 400,
        viewportFraction: 0.5,
      );

      expect(extent, 400);
    });

    test('ignores invalid fractions and still applies margin bound', () {
      final extent = resolveOpenHandResponsiveDialogExtent(
        viewportExtent: 720,
        maxExtent: 700,
        viewportMargin: 160,
        viewportFraction: -1,
      );

      expect(extent, 560);
    });
  });
}
