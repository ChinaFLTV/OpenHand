import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';

void main() {
  group('input value parsing', () {
    test('normalizes blank strings to null', () {
      expect(nullIfBlank(null), isNull);
      expect(nullIfBlank('   '), isNull);
      expect(nullIfBlank(' value '), 'value');
    });

    test('splits and trims non-empty list values', () {
      expect(splitTrimmedNonEmpty('alpha, beta,, gamma '), [
        'alpha',
        'beta',
        'gamma',
      ]);
      expect(stringListFromValue([' a ', '', 'b']), ['a', 'b']);
      expect(stringListFromValue(null), isEmpty);
    });

    test('parses key-value lines with trimmed keys and values', () {
      expect(keyValueMapFromValue('A=1\n B = two \ninvalid\n=skip'), {
        'A': '1',
        'B': 'two',
      });
      expect(keyValueMapFromValue({' A ': ' one ', '': 'skip'}), {'A': 'one'});
    });

    test('parses scalar values with safe fallbacks', () {
      expect(boolFromValue('true'), isTrue);
      expect(boolFromValue(0, defaultValue: true), isFalse);
      expect(dateTimeFromValue('2026-06-09T00:00:00Z')?.isUtc, isTrue);
      expect(intFromValue(' 42 ', fallback: 0), 42);
      expect(intFromValue(double.nan, fallback: 7), 7);
      expect(optionalIntFromValue(''), isNull);
      expect(optionalIntFromValue(12.8), 12);
      expect(optionalIntFromText(''), isNull);
      expect(optionalIntFromText('42'), 42);
    });

    test('clamps int text and tolerates reversed ranges', () {
      expect(clampedIntFromText('99', fallback: 5, min: 1, max: 10), 10);
      expect(clampedIntFromText('oops', fallback: 5, min: 1, max: 10), 5);
      expect(clampedIntFromText('-1', fallback: 5, min: 10, max: 1), 1);
      expect(clampedIntFromValue('99', fallback: 5, min: 1, max: 10), 10);
    });
  });
}
