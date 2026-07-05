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
}
