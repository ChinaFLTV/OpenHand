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

  group('numeric fallback parsing', () {
    test('keeps only positive integers when requested', () {
      expect(positiveIntFromText('12', fallback: 7), 12);
      expect(positiveIntFromText('0', fallback: 7), 7);
      expect(positiveIntFromText('-1', fallback: 7), 7);
      expect(positiveIntFromText('bad', fallback: 7), 7);
    });

    test('keeps zero for non-negative integer fields', () {
      expect(nonNegativeIntFromText('0', fallback: 7), 0);
      expect(nonNegativeIntFromText('9', fallback: 7), 9);
      expect(nonNegativeIntFromText('-1', fallback: 7), 7);
      expect(nonNegativeIntFromText('bad', fallback: 7), 7);
    });
  });
}
