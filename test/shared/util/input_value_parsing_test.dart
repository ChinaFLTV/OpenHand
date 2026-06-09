import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/byte_size_format.dart';
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
      expect(doubleFromValue(' 1.25 ', fallback: 0), 1.25);
      expect(doubleFromValue(double.nan, fallback: 2.5), 2.5);
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

    test('formats and parses byte size inputs consistently', () {
      expect(formatByteSize(0), '0 B');
      expect(formatByteSize(1536), '1.50 KB');
      expect(formatMegabytesInput(50 * kBytesPerMiB), '50.0');
      expect(formatNullableByteSize(null), '...');
      expect(
        megabytesTextToBytes(
          '1.5',
          fallbackBytes: 10 * kBytesPerMiB,
          minBytes: 0,
          maxBytes: 10 * kBytesPerMiB,
        ),
        1536 * kBytesPerKiB,
      );
      expect(
        megabytesTextToBytes(
          '',
          fallbackBytes: 2 * kBytesPerMiB,
          minBytes: 0,
          maxBytes: 10 * kBytesPerMiB,
        ),
        2 * kBytesPerMiB,
      );
      expect(
        megabytesTextToBytes(
          '99',
          fallbackBytes: 0,
          minBytes: 10 * kBytesPerMiB,
          maxBytes: kBytesPerMiB,
        ),
        10 * kBytesPerMiB,
      );
    });
  });
}
