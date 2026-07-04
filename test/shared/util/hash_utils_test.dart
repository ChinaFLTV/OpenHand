import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/rolling_hash.dart';
import 'package:openhand/shared/util/stable_hash.dart';

void main() {
  group('rollingHashWithMask', () {
    test('applies the rolling multiplier with a mask', () {
      expect(
        rollingHashWithMask<int>(
          <int>[1, 2, 3],
          (value) => value,
          seed: 7,
          mask: 0xff,
        ),
        (((7 * kRollingHash31Multiplier + 1) * kRollingHash31Multiplier + 2) *
                    kRollingHash31Multiplier +
                3) &
            0xff,
      );
    });

    test('keeps empty inputs bounded by the mask', () {
      expect(
        rollingHashWithMask<int>(const <int>[], (value) => value, seed: -1),
        kRollingHash30Mask,
      );
      expect(
        rollingHashWithMask<int>(
          const <int>[],
          (value) => value,
          seed: 123,
          mask: 0,
        ),
        0,
      );
    });

    test('falls back to the default mask for invalid negative masks', () {
      final withDefaultMask = rollingHashWithMask<int>(<int>[
        1,
        2,
        3,
      ], (value) => value);
      final withNegativeMask = rollingHashWithMask<int>(
        <int>[1, 2, 3],
        (value) => value,
        mask: -1,
      );

      expect(withNegativeMask, withDefaultMask);
    });
  });

  group('rollingHash helpers', () {
    test('use their documented masks', () {
      expect(
        rollingHash30<int>(<int>[1, 2, 3], (value) => value),
        rollingHashWithMask<int>(<int>[1, 2, 3], (value) => value),
      );
      expect(
        rollingHashPositive31Bit<int>(<int>[1, 2, 3], (value) => value),
        rollingHashWithMask<int>(
          <int>[1, 2, 3],
          (value) => value,
          mask: kRollingHashPositive31BitMask,
        ),
      );
    });
  });

  group('stableFnv1a32Hex', () {
    test('returns stable eight-character hex strings', () {
      expect(stableFnv1a32Hex(''), '811c9dc5');
      expect(stableFnv1a32Hex('OpenHand'), stableFnv1a32Hex('OpenHand'));
      expect(stableFnv1a32Hex('OpenHand'), hasLength(8));
    });
  });

  group('stableSha256Hex', () {
    test('returns full SHA-256 by default', () {
      expect(
        stableSha256Hex(''),
        'e3b0c44298fc1c149afbf4c8996fb924'
        '27ae41e4649b934ca495991b7852b855',
      );
    });

    test('clamps requested hash length into the valid range', () {
      final full = stableSha256Hex('OpenHand');

      expect(stableSha256Hex('OpenHand', length: 12), full.substring(0, 12));
      expect(stableSha256Hex('OpenHand', length: 0), full.substring(0, 1));
      expect(stableSha256Hex('OpenHand', length: 999), full);
    });
  });
}
