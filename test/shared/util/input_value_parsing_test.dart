import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';

void main() {
  group('boolFromValue', () {
    test('parses canonical boolean values', () {
      expect(boolFromValue(true), isTrue);
      expect(boolFromValue(false), isFalse);
      expect(boolFromValue(1), isTrue);
      expect(boolFromValue(0), isFalse);
      expect(boolFromValue('enabled'), isTrue);
      expect(boolFromValue('off'), isFalse);
    });

    test('uses default for non-boolean numeric values', () {
      expect(boolFromValue(2), isFalse);
      expect(boolFromValue(2, defaultValue: true), isTrue);
      expect(boolFromValue(-1, defaultValue: true), isTrue);
      expect(boolFromValue(double.nan, defaultValue: true), isTrue);
    });

    test('uses default for empty or unsupported values', () {
      expect(boolFromValue(null), isFalse);
      expect(boolFromValue('', defaultValue: true), isTrue);
      expect(boolFromValue(<String>[], defaultValue: true), isTrue);
    });
  });

  group('stringListFromValue', () {
    test('can preserve a string as one list item', () {
      expect(stringListFromValue('a,b'), <String>['a', 'b']);
      expect(stringListFromValue('a,b', separator: ''), <String>['a,b']);
    });

    test('can ignore literal null entries', () {
      expect(
        stringListFromValue(<Object?>[
          'alpha',
          ' null ',
          null,
          'beta',
        ], ignoreLiteralNull: true),
        <String>['alpha', 'beta'],
      );
      expect(
        stringListFromValue('null', separator: '', ignoreLiteralNull: true),
        isEmpty,
      );
    });
  });

  group('optionalRoundedIntFromValue', () {
    test('rounds numeric values and numeric strings', () {
      expect(optionalRoundedIntFromValue(2), 2);
      expect(optionalRoundedIntFromValue(2.6), 3);
      expect(optionalRoundedIntFromValue('2.4'), 2);
      expect(optionalRoundedIntFromValue('-1.6'), -2);
    });

    test('rejects blank, unsupported, and non-finite values', () {
      expect(optionalRoundedIntFromValue(''), isNull);
      expect(optionalRoundedIntFromValue('NaN'), isNull);
      expect(optionalRoundedIntFromValue(double.infinity), isNull);
      expect(optionalRoundedIntFromValue(<String>[]), isNull);
    });
  });

  group('optionalNonNegativeIntegralIntFromValue', () {
    test('accepts only non-negative integral values', () {
      expect(optionalNonNegativeIntegralIntFromValue(2), 2);
      expect(optionalNonNegativeIntegralIntFromValue(2.0), 2);
      expect(optionalNonNegativeIntegralIntFromValue('2'), 2);
      expect(optionalNonNegativeIntegralIntFromValue(0), 0);
    });

    test('rejects fractional, negative, and non-finite values', () {
      expect(optionalNonNegativeIntegralIntFromValue(2.5), isNull);
      expect(optionalNonNegativeIntegralIntFromValue('2.5'), isNull);
      expect(optionalNonNegativeIntegralIntFromValue(-1), isNull);
      expect(optionalNonNegativeIntegralIntFromValue(double.nan), isNull);
    });
  });

  group('dateTimeFromValue', () {
    test('parses DateTime and ISO strings', () {
      final value = DateTime.utc(2026, 7, 3, 9, 30);
      expect(dateTimeFromValue(value), same(value));
      expect(dateTimeFromValue('2026-07-03T09:30:00Z')?.toUtc(), value);
    });

    test('parses numeric timestamps with explicit modes', () {
      expect(
        dateTimeFromValue(1710000000000)?.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1710000000000, isUtc: true),
      );
      expect(
        dateTimeFromValue(
          1710000000,
          numericTimestampMode: DateTimeNumericTimestampMode.seconds,
        )?.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1710000000000, isUtc: true),
      );
      expect(
        dateTimeFromValue(
          1710000000,
          numericTimestampMode:
              DateTimeNumericTimestampMode.secondsOrMilliseconds,
        )?.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1710000000000, isUtc: true),
      );
    });

    test('can reject non-positive numeric timestamps', () {
      expect(dateTimeFromValue(0), isNotNull);
      expect(dateTimeFromValue(0, requirePositiveTimestamp: true), isNull);
      expect(dateTimeFromValue(double.nan), isNull);
    });

    test('normalizes parsed values to UTC', () {
      expect(
        utcDateTimeFromValue('2026-07-03T17:30:00+08:00'),
        DateTime.utc(2026, 7, 3, 9, 30),
      );
      expect(utcDateTimeFromValue(DateTime.utc(2026))?.isUtc, isTrue);
    });
  });
}
