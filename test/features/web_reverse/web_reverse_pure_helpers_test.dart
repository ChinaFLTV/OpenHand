import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_pure_helpers.dart';

void main() {
  group('CDP JSON result parsing', () {
    test('decodes string result objects as string-keyed maps', () {
      final parsed = cdpJsonMapStringResultValue(<String, Object?>{
        'result': <String, Object?>{
          'value': '{"ok":true,"sent":"2","received":["a",3]}',
        },
      });

      expect(parsed, isNotNull);
      expect(parsed!['ok'], isTrue);
      expect(parsed['sent'], '2');
      expect(parsed['received'], <Object?>['a', 3]);
    });

    test('decodes string result arrays without accepting objects', () {
      final parsed = cdpJsonListStringResultValue(<String, Object?>{
        'result': <String, Object?>{'value': '[{"id":1},null,"tail"]'},
      });

      expect(parsed, <Object?>[
        <String, Object?>{'id': 1},
        null,
        'tail',
      ]);
      expect(
        cdpJsonListStringResultValue(<String, Object?>{
          'result': <String, Object?>{'value': '{"id":1}'},
        }),
        isNull,
      );
    });

    test('decodes JSON arrays as normalized string-keyed map lists', () {
      final parsed = decodeStringKeyedJsonMapList(
        '[{"id":1},{"2":"two"},null,"tail"]',
      );

      expect(parsed, <Map<String, Object?>>[
        <String, Object?>{'id': 1},
        <String, Object?>{'2': 'two'},
      ]);
      expect(decodeStringKeyedJsonMapList('{"id":1}'), isNull);
      expect(decodeStringKeyedJsonMapList('[bad'), isNull);
    });

    test(
      'returns null for CDP errors, malformed JSON, and non-object maps',
      () {
        expect(
          cdpJsonMapStringResultValue(<String, Object?>{
            'error': <String, Object?>{'message': 'failed'},
          }),
          isNull,
        );
        expect(decodeStringKeyedJsonMap('[1,2,3]'), isNull);
        expect(decodeStringKeyedJsonMap('{bad'), isNull);
        expect(decodeJsonList('{"ok":true}'), isNull);
        expect(decodeJsonList('[bad'), isNull);
      },
    );
  });

  group('vlqDecode', () {
    test('ignores invalid characters without throwing', () {
      expect(vlqDecode('!@#'), isEmpty);
    });
  });
}
