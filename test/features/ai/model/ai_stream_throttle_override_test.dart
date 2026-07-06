import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/model/ai_stream_throttle_override.dart';

void main() {
  group('AiStreamThrottleOverride', () {
    test('fromJson keeps zero as an explicit disabled rate', () {
      final override = AiStreamThrottleOverride.fromJson(
        const <String, Object?>{
          'chars_per_second': 0,
          'cards_per_second': 0,
          'enabled': true,
        },
      );

      expect(override, isNotNull);
      expect(override!.charsPerSecond, 0);
      expect(override.cardsPerSecond, 0);
      expect(override.enabled, isTrue);
      expect(override.isEmpty, isFalse);
    });

    test('fromJson clamps excessive rates and drops invalid values', () {
      final clamped = AiStreamThrottleOverride.fromJson(const <String, Object?>{
        'chars_per_second': 999999999,
        'cards_per_second': 999,
      });
      final invalid = AiStreamThrottleOverride.fromJson(const <String, Object?>{
        'chars_per_second': -1,
        'cards_per_second': 0.5,
      });

      expect(clamped, isNotNull);
      expect(
        clamped!.charsPerSecond,
        AiStreamThrottleOverride.maxCharsPerSecond,
      );
      expect(
        clamped.cardsPerSecond,
        AiStreamThrottleOverride.maxCardsPerSecond,
      );
      expect(invalid, isNull);
    });

    test('copyWith and toJson normalize unsafe current values', () {
      const override = AiStreamThrottleOverride(
        charsPerSecond: -1,
        cardsPerSecond: 999,
      );

      final normalized = override.copyWith();

      expect(normalized.charsPerSecond, isNull);
      expect(
        normalized.cardsPerSecond,
        AiStreamThrottleOverride.maxCardsPerSecond,
      );
      expect(override.toJson(), <String, Object?>{
        'cards_per_second': AiStreamThrottleOverride.maxCardsPerSecond,
      });
    });

    test('copyWith normalizes replacements and supports explicit clearing', () {
      const override = AiStreamThrottleOverride(
        charsPerSecond: 10,
        cardsPerSecond: 1,
        enabled: true,
      );

      final replaced = override.copyWith(
        charsPerSecond: 999999999,
        cardsPerSecond: 0,
      );
      final cleared = override.copyWith(charsPerSecond: null, enabled: null);

      expect(
        replaced.charsPerSecond,
        AiStreamThrottleOverride.maxCharsPerSecond,
      );
      expect(replaced.cardsPerSecond, 0);
      expect(cleared.charsPerSecond, isNull);
      expect(cleared.cardsPerSecond, 1);
      expect(cleared.enabled, isNull);
    });
  });
}
