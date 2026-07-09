import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/openhand_clipboard.dart';

void main() {
  group('clampOpenHandClipboardTimeout', () {
    test('uses default for non-positive timeouts', () {
      expect(
        clampOpenHandClipboardTimeout(Duration.zero),
        kOpenHandClipboardCopyTimeout,
      );
      expect(
        clampOpenHandClipboardTimeout(const Duration(seconds: -1)),
        kOpenHandClipboardCopyTimeout,
      );
    });

    test('keeps valid timeouts unchanged', () {
      const value = Duration(seconds: 3);
      expect(clampOpenHandClipboardTimeout(value), value);
    });

    test('caps oversized timeouts', () {
      final clamped = clampOpenHandClipboardTimeout(const Duration(hours: 2));
      expect(clamped, lessThanOrEqualTo(const Duration(seconds: 60)));
      expect(clamped.inMilliseconds, greaterThan(0));
    });
  });
}
