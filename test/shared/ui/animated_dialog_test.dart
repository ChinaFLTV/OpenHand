import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/animated_dialog.dart';

void main() {
  group('resolveOpenHandResponsiveDialogExtent', () {
    test('caps large viewports at the configured maximum', () {
      expect(
        resolveOpenHandResponsiveDialogExtent(
          viewportExtent: 1440,
          maxExtent: 900,
          viewportMargin: 36,
        ),
        900,
      );
    });

    test('subtracts viewport margin on smaller viewports', () {
      expect(
        resolveOpenHandResponsiveDialogExtent(
          viewportExtent: 800,
          maxExtent: 900,
          viewportMargin: 36,
        ),
        764,
      );
    });

    test('keeps a usable minimum when the viewport is tiny', () {
      expect(
        resolveOpenHandResponsiveDialogExtent(
          viewportExtent: 320,
          maxExtent: 900,
          minAvailableExtent: 360,
          viewportMargin: 120,
        ),
        360,
      );
    });

    test('falls back to the minimum for invalid unbounded input', () {
      expect(
        resolveOpenHandResponsiveDialogExtent(
          viewportExtent: double.infinity,
          maxExtent: double.nan,
          minAvailableExtent: 280,
          viewportMargin: 120,
        ),
        280,
      );
    });
  });
}
