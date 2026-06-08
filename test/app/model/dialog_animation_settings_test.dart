import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';

void main() {
  group('DialogAnimationSettings', () {
    test('normalizes invalid persisted animated durations', () {
      final settings = DialogAnimationSettings.fromJson(const <String, dynamic>{
        'entrance_style': 'spring_scale',
        'exit_style': 'fade_scale',
        'duration_ms': -40,
        'curve': 'ease_out_cubic',
      });

      expect(
        settings.durationMs,
        DialogAnimationSettings.minAnimatedDurationMs,
      );
      expect(
        settings.duration.inMilliseconds,
        DialogAnimationSettings.minAnimatedDurationMs,
      );
    });

    test('preserves intentional no-animation settings as zero duration', () {
      final settings = const DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.none,
        exitStyle: DialogAnimationStyle.none,
        durationMs: 360,
      ).normalized();

      expect(settings.disablesAnimation, isTrue);
      expect(settings.durationMs, 0);
      expect(settings.toJson()['duration_ms'], 0);
    });

    test('caps overly long durations before persistence', () {
      const settings = DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.fade,
        exitStyle: DialogAnimationStyle.fade,
        durationMs: 60000,
      );

      expect(
        settings.toJson()['duration_ms'],
        DialogAnimationSettings.maxDurationMs,
      );
    });
  });
}
