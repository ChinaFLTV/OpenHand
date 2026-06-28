import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';

void main() {
  group('splitLooseDelimitedValues', () {
    test('splits whitespace and common Chinese or English separators', () {
      expect(
        splitLooseDelimitedValues(' alpha, beta，gamma; delta；epsilon\nzeta '),
        <String>['alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta'],
      );
    });

    test('drops empty segments', () {
      expect(splitLooseDelimitedValues(' ,， ;； \n\t '), isEmpty);
    });
  });

  group('string list parsing', () {
    test('drops null and blank list entries while keeping scalar values', () {
      expect(
        stringListFromValue(<Object?>[' alpha ', null, 42, '', ' beta ']),
        <String>['alpha', '42', 'beta'],
      );
    });

    test('parses JSON text lists with malformed input fallback', () {
      expect(
        optionalStringListFromJsonText('[" alpha ", null, 42, "", "beta"]'),
        <String>['alpha', '42', 'beta'],
      );
      expect(optionalStringListFromJsonText(''), isEmpty);
      expect(optionalStringListFromJsonText('not-json'), isNull);
      expect(
        optionalStringListFromJsonText('"alpha,beta"', requireList: true),
        isNull,
      );
      expect(stringListFromJsonText('not-json'), isEmpty);
    });

    test('parses list values or JSON text through one entrypoint', () {
      expect(
        stringListFromValueOrJsonText(<Object?>[' alpha ', null, 42, 'beta']),
        <String>['alpha', '42', 'beta'],
      );
      expect(
        stringListFromValueOrJsonText('[" alpha ", 42, "", "beta"]'),
        <String>['alpha', '42', 'beta'],
      );
      expect(stringListFromValueOrJsonText('alpha,beta'), <String>[
        'alpha',
        'beta',
      ]);
      expect(
        optionalStringListFromValueOrJsonText('alpha,beta', requireList: true),
        isNull,
      );
      expect(optionalStringListFromValueOrJsonText(42), isNull);
    });
  });

  group('string scalar parsing', () {
    test('trims scalar values and falls back for blank input', () {
      expect(stringFromValue(' alpha '), 'alpha');
      expect(stringFromValue(42), '42');
      expect(stringFromValue(null, fallback: 'fallback'), 'fallback');
      expect(stringFromValue('   ', fallback: 'fallback'), 'fallback');
      expect(optionalStringFromValue(false), 'false');
      expect(optionalStringFromValue(''), isNull);
    });
  });

  group('string keyed map parsing', () {
    test('normalizes loose map keys without dropping values', () {
      expect(
        stringKeyedMapFromValue(<Object?, Object?>{1: 'one', 'two': 2}),
        <String, Object?>{'1': 'one', 'two': 2},
      );
    });

    test('parses JSON object text into a normalized map', () {
      expect(
        stringKeyedMapFromJsonText('{"answer": 42, "enabled": true}'),
        <String, Object?>{'answer': 42, 'enabled': true},
      );
      expect(stringKeyedMapFromJsonText('[1, 2]'), isEmpty);
      expect(optionalStringKeyedMapFromJsonText('not-json'), isNull);
    });

    test('parses map values or JSON object text through one entrypoint', () {
      expect(
        optionalStringKeyedMapFromValueOrJsonText(<Object?, Object?>{
          1: 'one',
          'two': 2,
        }),
        <String, Object?>{'1': 'one', 'two': 2},
      );
      expect(
        stringKeyedMapFromValueOrJsonText('{"answer": 42}'),
        <String, Object?>{'answer': 42},
      );
      expect(optionalStringKeyedMapFromValueOrJsonText('[1, 2]'), isNull);
      expect(optionalStringKeyedMapFromValueOrJsonText(42), isNull);
    });
  });

  group('numeric fallback parsing', () {
    test('keeps only positive integers when requested', () {
      expect(optionalPositiveIntFromText('12'), 12);
      expect(optionalPositiveIntFromText('0'), isNull);
      expect(optionalPositiveIntFromText('-1'), isNull);
      expect(optionalPositiveIntFromText('bad'), isNull);
      expect(positiveIntFromText('12', fallback: 7), 12);
      expect(positiveIntFromText('0', fallback: 7), 7);
      expect(positiveIntFromText('-1', fallback: 7), 7);
      expect(positiveIntFromText('bad', fallback: 7), 7);
    });

    test('keeps zero for non-negative integer fields', () {
      expect(optionalNonNegativeIntFromValue('0'), 0);
      expect(optionalNonNegativeIntFromValue(9), 9);
      expect(optionalNonNegativeIntFromValue(double.infinity), isNull);
      expect(optionalNonNegativeIntFromValue(-1), isNull);
      expect(nonNegativeIntFromText('0', fallback: 7), 0);
      expect(nonNegativeIntFromText('9', fallback: 7), 9);
      expect(nonNegativeIntFromText('-1', fallback: 7), 7);
      expect(nonNegativeIntFromText('bad', fallback: 7), 7);
    });

    test('keeps only integral numeric values when requested', () {
      expect(optionalIntegralIntFromValue(3), 3);
      expect(optionalIntegralIntFromValue(3.0), 3);
      expect(optionalIntegralIntFromValue('3'), 3);
      expect(optionalIntegralIntFromValue('3.0'), 3);
      expect(optionalIntegralIntFromValue(3.25), isNull);
      expect(optionalIntegralIntFromValue('3.25'), isNull);
      expect(optionalIntegralIntFromValue(double.nan), isNull);
      expect(optionalIntegralIntFromValue('Infinity'), isNull);
    });

    test('keeps finite non-negative doubles when requested', () {
      expect(optionalNonNegativeDoubleFromText('0'), 0);
      expect(optionalNonNegativeDoubleFromText('1.25'), 1.25);
      expect(optionalNonNegativeDoubleFromText(''), isNull);
      expect(optionalNonNegativeDoubleFromText('-0.1'), isNull);
      expect(optionalNonNegativeDoubleFromText('NaN'), isNull);
      expect(optionalNonNegativeDoubleFromText('Infinity'), isNull);
      expect(optionalNonNegativeDoubleFromText('bad'), isNull);
    });
  });

  group('boolean parsing', () {
    test('parses optional booleans from explicit flag values only', () {
      expect(optionalBoolFromValue(true), isTrue);
      expect(optionalBoolFromValue(false), isFalse);
      expect(optionalBoolFromValue(1), isTrue);
      expect(optionalBoolFromValue(0), isFalse);
      expect(optionalBoolFromValue('1.0'), isTrue);
      expect(optionalBoolFromValue('yes'), isTrue);
      expect(optionalBoolFromValue('on'), isTrue);
      expect(optionalBoolFromValue('enabled'), isTrue);
      expect(optionalBoolFromValue('0.0'), isFalse);
      expect(optionalBoolFromValue('no'), isFalse);
      expect(optionalBoolFromValue('off'), isFalse);
      expect(optionalBoolFromValue('disabled'), isFalse);
      expect(optionalBoolFromValue(2), isNull);
      expect(optionalBoolFromValue(0.5), isNull);
      expect(optionalBoolFromValue(double.nan), isNull);
      expect(optionalBoolFromValue('bad'), isNull);
    });

    test('falls back for non-finite numeric values', () {
      expect(boolFromValue(double.nan), isFalse);
      expect(boolFromValue(double.infinity, defaultValue: true), isTrue);
      expect(boolFromValue(double.negativeInfinity), isFalse);
    });
  });
}
