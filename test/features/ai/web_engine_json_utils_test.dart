import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/index.dart';

void main() {
  group('decodeJsonObjectBytes', () {
    test('decodes object responses with string keyed maps', () {
      final decoded = decodeJsonObjectBytes(
        utf8.encode('{"results":[{"title":"Example"}],"count":1}'),
        source: 'Search response',
      );

      expect(decoded['count'], 1);
      expect(readJsonPath<String>(decoded, ['results', 0, 'title']), 'Example');
    });

    test('rejects empty, malformed, and non-object responses', () {
      expect(
        () => decodeJsonObjectBytes(utf8.encode(''), source: 'Empty response'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeJsonObjectBytes(
          utf8.encode('[{"title":"Example"}]'),
          source: 'Array response',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Array response'),
          ),
        ),
      );
      expect(
        () => decodeJsonObjectBytes(
          utf8.encode('{bad json'),
          source: 'Malformed response',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('jsonObjectOf', () {
    test('normalizes map values and ignores non-map values', () {
      expect(jsonObjectOf({'title': 'Example'}), {'title': 'Example'});
      expect(jsonObjectOf(null), isEmpty);
      expect(jsonObjectOf(['bad']), isEmpty);
    });
  });
}
