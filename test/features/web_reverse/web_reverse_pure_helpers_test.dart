import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/web_reverse/web_reverse_pure_helpers.dart';

void main() {
  group('cdpResultValue', () {
    test('returns Runtime.evaluate result.value', () {
      final response = {
        'result': {'type': 'string', 'value': 'ok'},
      };

      expect(cdpResultValue(response), 'ok');
      expect(cdpStringResultValue(response), 'ok');
    });

    test('returns null for protocol errors and malformed responses', () {
      expect(cdpResultValue({'error': 'boom'}), isNull);
      expect(cdpResultValue({'result': 'not-a-map'}), isNull);
      expect(
        cdpStringResultValue({
          'result': {'value': 42},
        }),
        isNull,
      );
    });
  });
}
