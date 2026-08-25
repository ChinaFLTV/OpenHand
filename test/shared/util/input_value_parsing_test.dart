import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/input_value_parsing.dart';

void main() {
  group('URI 安全解码', () {
    test('正常解码组件和完整 URI', () {
      expect(decodeUriComponentOrOriginal('a%20b%2Fc'), 'a b/c');
      expect(
        decodeUriFullOrOriginal('https://example.com/a%20b?q=x%2Fy'),
        'https://example.com/a b?q=x/y',
      );
    });

    test('畸形百分号和无效 UTF-8 保留原值', () {
      for (final value in const <String>['%', '%GG', '%FF']) {
        expect(decodeUriComponentOrOriginal(value), value);
        expect(decodeUriFullOrOriginal(value), value);
      }
    });
  });

  group('有界整数解析', () {
    test('拒绝非有限数值并采用安全回退', () {
      expect(clampedIntFromValue(double.nan, fallback: 7, min: 1, max: 10), 7);
      expect(
        clampedIntFromValue(double.infinity, fallback: 7, min: 1, max: 10),
        7,
      );
    });

    test('截断有限小数并限制到合法范围', () {
      expect(clampedIntFromValue(3.9, fallback: 1, min: 1, max: 10), 3);
      expect(clampedIntFromValue('99', fallback: 1, min: 1, max: 10), 10);
    });
  });

  group('时间戳解析', () {
    test('按需解析秒和毫秒数字字符串', () {
      final seconds = dateTimeFromValue(
        '1700000000',
        numericTimestampMode:
            DateTimeNumericTimestampMode.secondsOrMilliseconds,
        parseNumericText: true,
      );
      final milliseconds = dateTimeFromValue(
        '1700000000000',
        numericTimestampMode:
            DateTimeNumericTimestampMode.secondsOrMilliseconds,
        parseNumericText: true,
      );

      expect(seconds?.millisecondsSinceEpoch, 1700000000000);
      expect(milliseconds?.millisecondsSinceEpoch, 1700000000000);
    });

    test('非有限或越界时间戳返回空值', () {
      expect(
        dateTimeFromValue(
          double.infinity,
          numericTimestampMode: DateTimeNumericTimestampMode.seconds,
        ),
        isNull,
      );
      expect(dateTimeFromValue('1e100', parseNumericText: true), isNull);
    });
  });
}
