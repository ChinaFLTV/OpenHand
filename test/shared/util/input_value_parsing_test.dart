import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';

void main() {
  group('optionalStringListFromJsonText', () {
    test('parses JSON arrays while trimming blank values', () {
      expect(
        optionalStringListFromJsonText('[" alpha ", "", 7, null]'),
        <String>['alpha', '7'],
      );
    });

    test('distinguishes invalid JSON from JSON null fallback semantics', () {
      expect(optionalStringListFromJsonText('not-json'), isNull);
      expect(optionalStringListFromJsonText('null'), isEmpty);
      expect(
        optionalStringListFromJsonText('{"a":1}', requireList: true),
        isNull,
      );
    });
  });

  group('string-keyed JSON maps', () {
    test('parses maps and map lists without throwing on malformed input', () {
      expect(optionalStringKeyedMapFromJsonText('{"answer": 42}'), {
        'answer': 42,
      });
      expect(optionalStringKeyedMapFromJsonText('{bad'), isNull);

      expect(
        optionalStringKeyedMapListFromValueOrJsonText('[{"a":1},{"b":2}]'),
        <Map<String, Object?>>[
          {'a': 1},
          {'b': 2},
        ],
      );
      expect(optionalStringKeyedMapListFromValueOrJsonText('{bad'), isNull);
    });
  });
}
