import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';

void main() {
  group('DialogAnimationSettings', () {
    test('fromJson clamps animated durations', () {
      final tooShort = DialogAnimationSettings.fromJson(<String, dynamic>{
        'entrance_style': 'spring_scale',
        'exit_style': 'fade_scale',
        'duration_ms': 1,
      });
      final tooLong = DialogAnimationSettings.fromJson(<String, dynamic>{
        'entrance_style': 'spring_scale',
        'exit_style': 'fade_scale',
        'duration_ms': 5000,
      });
      final malformed = DialogAnimationSettings.fromJson(<String, dynamic>{
        'duration_ms': 'bad',
      });

      expect(
        tooShort.durationMs,
        DialogAnimationSettings.minAnimatedDurationMs,
      );
      expect(tooLong.durationMs, DialogAnimationSettings.maxDurationMs);
      expect(malformed.durationMs, DialogAnimationSettings.defaultDurationMs);
    });

    test('fromJson disables duration when both styles are none', () {
      final settings = DialogAnimationSettings.fromJson(<String, dynamic>{
        'entrance_style': 'none',
        'exit_style': 'none',
        'duration_ms': 500,
      });

      expect(settings.disablesAnimation, isTrue);
      expect(settings.durationMs, 0);
      expect(settings.effectiveDurationMs, 0);
      expect(settings.duration, Duration.zero);
    });

    test('fromJson falls back unknown style and curve values', () {
      final settings = DialogAnimationSettings.fromJson(<String, dynamic>{
        'entrance_style': 'unknown',
        'exit_style': 'unknown',
        'curve': 'unknown',
      });

      expect(settings.entranceStyle, DialogAnimationStyle.fadeScale);
      expect(settings.exitStyle, DialogAnimationStyle.fadeScale);
      expect(settings.curve, DialogAnimationCurve.easeOutCubic);
    });

    test('copyWith and toJson normalize duration consistently', () {
      final settings = const DialogAnimationSettings(durationMs: -1).copyWith();

      expect(
        settings.durationMs,
        DialogAnimationSettings.minAnimatedDurationMs,
      );
      expect(
        settings.copyWith(durationMs: 5000).durationMs,
        DialogAnimationSettings.maxDurationMs,
      );
      expect(settings.toJson()['duration_ms'], settings.durationMs);
    });
  });
}
