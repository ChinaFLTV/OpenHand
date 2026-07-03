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
}
