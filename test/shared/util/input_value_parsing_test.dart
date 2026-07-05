import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';

void main() {
  group('optionalBoolFromValue', () {
    test('parses common truthy and falsy values', () {
      expect(optionalBoolFromValue(true), isTrue);
      expect(optionalBoolFromValue(' yes '), isTrue);
      expect(optionalBoolFromValue('enabled'), isTrue);
      expect(optionalBoolFromValue(1.0), isTrue);

      expect(optionalBoolFromValue(false), isFalse);
      expect(optionalBoolFromValue(' off '), isFalse);
      expect(optionalBoolFromValue('disabled'), isFalse);
      expect(optionalBoolFromValue(0.0), isFalse);
    });

    test('rejects ambiguous values', () {
      expect(optionalBoolFromValue(null), isNull);
      expect(optionalBoolFromValue('maybe'), isNull);
      expect(optionalBoolFromValue(2), isNull);
      expect(optionalBoolFromValue(0.5), isNull);
    });
  });

  group('clampUnitInterval', () {
    test('clamps finite values into the unit interval', () {
      expect(clampUnitInterval(-0.25), 0);
      expect(clampUnitInterval(0.42), 0.42);
      expect(clampUnitInterval(1.25), 1);
    });

    test('handles non-finite values gracefully', () {
      expect(clampUnitInterval(double.infinity), 1);
      expect(clampUnitInterval(double.negativeInfinity), 0);
      expect(clampUnitInterval(double.nan, fallback: 0.5), 0.5);
      expect(clampUnitInterval(double.nan, fallback: double.nan), 0);
    });
  });

  group('finiteUnitInterval', () {
    test('clamps finite values into the unit interval', () {
      expect(finiteUnitInterval(-0.25, fallback: 0.6), 0);
      expect(finiteUnitInterval(0.42, fallback: 0.6), 0.42);
      expect(finiteUnitInterval(1.25, fallback: 0.6), 1);
    });

    test('uses fallback for all non-finite values', () {
      expect(finiteUnitInterval(double.infinity, fallback: 0.6), 0.6);
      expect(finiteUnitInterval(double.negativeInfinity, fallback: 0.6), 0.6);
      expect(finiteUnitInterval(double.nan, fallback: 0.6), 0.6);
      expect(finiteUnitInterval(double.nan, fallback: 2), 1);
      expect(finiteUnitInterval(double.nan, fallback: double.nan), 0);
    });
  });

  group('unitRatio', () {
    test('returns a safe unit interval ratio', () {
      expect(unitRatio(3, 4), 0.75);
      expect(unitRatio(5, 4), 1);
      expect(unitRatio(-1, 4), 0);
    });

    test('returns zero for invalid denominators', () {
      expect(unitRatio(1, 0), 0);
      expect(unitRatio(1, -2), 0);
      expect(unitRatio(1, double.nan), 0);
    });
  });

  group('optionalUnitIntervalListFromValue', () {
    test('clamps finite values and ignores invalid entries', () {
      expect(
        optionalUnitIntervalListFromValue(<Object?>[
          -0.25,
          0.42,
          2,
          double.nan,
          double.infinity,
          'bad',
          '0.8',
        ]),
        <double>[0, 0.42, 1, 0.8],
      );
    });

    test('sorts and freezes parsed values on request', () {
      final values = optionalUnitIntervalListFromValue(<Object?>[
        0.75,
        0.25,
      ], sorted: true);
      expect(values, <double>[0.25, 0.75]);
      expect(() => values!.add(1), throwsUnsupportedError);
    });

    test('returns null for non-list values', () {
      expect(optionalUnitIntervalListFromValue('0.5'), isNull);
    });
  });

  group('clampedIntegralIntFromValue', () {
    test('parses integral values and clamps them within ordered bounds', () {
      expect(
        clampedIntegralIntFromValue('7.0', fallback: 3, min: 0, max: 10),
        7,
      );
      expect(clampedIntegralIntFromValue(12, fallback: 3, min: 0, max: 10), 10);
      expect(clampedIntegralIntFromValue(-2, fallback: 3, min: 10, max: 0), 0);
    });

    test('uses a clamped fallback for non-integral values', () {
      expect(
        clampedIntegralIntFromValue('7.5', fallback: 12, min: 0, max: 10),
        10,
      );
      expect(
        clampedIntegralIntFromValue(7.5, fallback: -2, min: 0, max: 10),
        0,
      );
    });
  });

  group('nonNegativeRemaining', () {
    test('returns remaining capacity without going below zero', () {
      expect(nonNegativeRemaining(10, 3), 7);
      expect(nonNegativeRemaining(10, 13), 0);
      expect(nonNegativeRemaining(10, -2), 12);
    });

    test('returns zero when capacity is unavailable', () {
      expect(nonNegativeRemaining(0, 3), 0);
      expect(nonNegativeRemaining(-5, 3), 0);
    });
  });
}
