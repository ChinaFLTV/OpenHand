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

  group('stringListFromListValue', () {
    test('trims list entries and drops blank or null values', () {
      expect(
        stringListFromListValue(<Object?>[' alpha ', '', null, ' beta ']),
        <String>['alpha', 'beta'],
      );
    });

    test('does not treat scalar text as a list', () {
      expect(stringListFromListValue('alpha,beta'), isEmpty);
    });

    test('can ignore literal null entries', () {
      expect(
        stringListFromListValue(<Object?>[
          'alpha',
          ' null ',
          'beta',
        ], ignoreLiteralNull: true),
        <String>['alpha', 'beta'],
      );
    });
  });

  group('trimmedNonEmptyStrings', () {
    test('normalizes any iterable values to trimmed non-empty strings', () {
      expect(
        trimmedNonEmptyStrings(<Object?>[' alpha ', 42, '', null, ' beta ']),
        <String>['alpha', '42', 'beta'],
      );
    });

    test('can ignore literal null after trimming', () {
      expect(
        trimmedNonEmptyStrings(<Object?>[
          ' null ',
          'value',
        ], ignoreLiteralNull: true),
        <String>['value'],
      );
    });
  });

  group('trimRightNonEmptyLines', () {
    test('drops blank lines while preserving leading whitespace', () {
      expect(
        trimRightNonEmptyLines(<String>['  alpha  ', '   ', '\tbeta\t']),
        <String>['  alpha', '\tbeta'],
      );
    });

    test('applies non-positive and positive limits safely', () {
      final lines = <String>[' one ', ' two ', ' three '];
      expect(trimRightNonEmptyLines(lines, limit: 0), isEmpty);
      expect(trimRightNonEmptyLines(lines, limit: -1), isEmpty);
      expect(trimRightNonEmptyLines(lines, limit: 2), <String>[' one', ' two']);
    });
  });

  group('splitTrimmedNonEmpty', () {
    test('trims entries and drops empty delimiter gaps', () {
      expect(splitTrimmedNonEmpty(' alpha, , beta ,'), <String>[
        'alpha',
        'beta',
      ]);
    });

    test('treats an empty string separator as one trimmed item', () {
      expect(splitTrimmedNonEmpty('  alpha,beta  ', separator: ''), <String>[
        'alpha,beta',
      ]);
      expect(splitTrimmedNonEmpty('   ', separator: ''), isEmpty);
    });
  });

  group('splitTrimmed', () {
    test('trims entries while preserving empty delimiter gaps', () {
      expect(splitTrimmed(' alpha, , beta ,'), <String>[
        'alpha',
        '',
        'beta',
        '',
      ]);
    });

    test('treats an empty string separator as one trimmed item', () {
      expect(splitTrimmed('  alpha,beta  ', separator: ''), <String>[
        'alpha,beta',
      ]);
      expect(splitTrimmed('   ', separator: ''), <String>['']);
    });
  });

  group('splitLooseDelimitedValues', () {
    test('splits comma, Chinese punctuation, semicolon, and whitespace', () {
      expect(
        splitLooseDelimitedValues(' adb, frida；jadx apktool， mitm;  ida '),
        <String>['adb', 'frida', 'jadx', 'apktool', 'mitm', 'ida'],
      );
    });
  });

  group('stringKeyedMapFromValue', () {
    test('normalizes map keys to strings', () {
      expect(
        stringKeyedMapFromValue(<Object?, Object?>{1: 'one', 'two': 2}),
        <String, Object?>{'1': 'one', 'two': 2},
      );
    });

    test('uses an empty map for unsupported values', () {
      expect(stringKeyedMapFromValue(null), isEmpty);
      expect(stringKeyedMapFromValue('not a map'), isEmpty);
    });
  });

  group('stringKeyedMapListFromValue', () {
    test('keeps only map entries and normalizes keys', () {
      expect(
        stringKeyedMapListFromValue(<Object?>[
          <Object?, Object?>{1: 'one'},
          'ignored',
          <String, Object?>{'two': 2},
        ]),
        <Map<String, Object?>>[
          <String, Object?>{'1': 'one'},
          <String, Object?>{'two': 2},
        ],
      );
    });

    test('uses an empty list for unsupported values', () {
      expect(stringKeyedMapListFromValue(null), isEmpty);
      expect(stringKeyedMapListFromValue('not a list'), isEmpty);
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

  group('optionalNonNegativeIntFromValue', () {
    test('accepts non-negative ints and finite numeric values', () {
      expect(optionalNonNegativeIntFromValue(2), 2);
      expect(optionalNonNegativeIntFromValue(2.9), 2);
      expect(optionalNonNegativeIntFromValue('2'), 2);
      expect(optionalNonNegativeIntFromValue(0), 0);
    });

    test('rejects negative, fractional strings, and non-finite values', () {
      expect(optionalNonNegativeIntFromValue(-1), isNull);
      expect(optionalNonNegativeIntFromValue('-1'), isNull);
      expect(optionalNonNegativeIntFromValue('2.5'), isNull);
      expect(optionalNonNegativeIntFromValue(double.infinity), isNull);
    });
  });

  group('optionalIntFromText', () {
    test('trims text and parses decimal integers', () {
      expect(optionalIntFromText(' 42 '), 42);
      expect(optionalIntFromText(''), isNull);
      expect(optionalIntFromText(null), isNull);
    });

    test('supports radix parsing', () {
      expect(optionalIntFromText(' ff ', radix: 16), 255);
      expect(optionalIntFromText('xyz', radix: 16), isNull);
    });
  });

  group('optionalPositiveIntFromValue', () {
    test('accepts positive ints and finite numeric values', () {
      expect(optionalPositiveIntFromValue(2), 2);
      expect(optionalPositiveIntFromValue(2.9), 2);
      expect(optionalPositiveIntFromValue('2'), 2);
    });

    test('rejects zero, sub-unit numeric values, and invalid strings', () {
      expect(optionalPositiveIntFromValue(0), isNull);
      expect(optionalPositiveIntFromValue(0.5), isNull);
      expect(optionalPositiveIntFromValue('-1'), isNull);
      expect(optionalPositiveIntFromValue('2.5'), isNull);
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

  group('optionalPositiveDoubleFromValue', () {
    test('accepts only finite positive values', () {
      expect(optionalPositiveDoubleFromValue(1), 1.0);
      expect(optionalPositiveDoubleFromValue(' 2.5 '), 2.5);
      expect(optionalPositiveDoubleFromValue(0), isNull);
      expect(optionalPositiveDoubleFromValue('-0.1'), isNull);
      expect(optionalPositiveDoubleFromValue(double.nan), isNull);
      expect(optionalPositiveDoubleFromValue('abc'), isNull);
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
