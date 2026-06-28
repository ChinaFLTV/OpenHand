import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_stream_throttle_override.dart';

void main() {
  test('fromJson parses JSON text with loose numeric and boolean values', () {
    final override = AiStreamThrottleOverride.fromJson('''
      {
        "chars_per_second": "80",
        "cards_per_second": 2.0,
        "enabled": "off"
      }
    ''');

    expect(override, isNotNull);
    expect(override!.charsPerSecond, 80);
    expect(override.cardsPerSecond, 2);
    expect(override.enabled, isFalse);
  });

  test(
    'fromJson ignores invalid rates while keeping explicit enabled flag',
    () {
      final override = AiStreamThrottleOverride.fromJson(<Object?, Object?>{
        'chars_per_second': 0,
        'cards_per_second': '-1',
        'enabled': 'yes',
      });

      expect(override, isNotNull);
      expect(override!.charsPerSecond, isNull);
      expect(override.cardsPerSecond, isNull);
      expect(override.enabled, isTrue);
    },
  );

  test('fromJson returns null for empty or invalid overrides', () {
    expect(AiStreamThrottleOverride.fromJson(<String, Object?>{}), isNull);
    expect(AiStreamThrottleOverride.fromJson('[]'), isNull);
    expect(
      AiStreamThrottleOverride.fromJson(<String, Object?>{
        'chars_per_second': 'bad',
        'cards_per_second': 0,
        'enabled': 'maybe',
      }),
      isNull,
    );
  });
}
