import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';

void main() {
  test('disabling both directions preserves the configured duration', () {
    const original = DialogAnimationSettings(durationMs: 640);

    final disabled = original.copyWith(
      entranceStyle: DialogAnimationStyle.none,
      exitStyle: DialogAnimationStyle.none,
    );
    final restored = disabled.copyWith(
      entranceStyle: DialogAnimationStyle.fade,
    );

    expect(disabled.durationMs, 640);
    expect(disabled.duration, Duration.zero);
    expect(restored.durationMs, 640);
    expect(restored.entranceDuration, const Duration(milliseconds: 640));
  });

  test('effective durations are independently disabled by direction', () {
    const entranceDisabled = DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.none,
      exitStyle: DialogAnimationStyle.fade,
      durationMs: 520,
    );
    const exitDisabled = DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.fade,
      exitStyle: DialogAnimationStyle.none,
      durationMs: 520,
    );

    expect(entranceDisabled.entranceDuration, Duration.zero);
    expect(entranceDisabled.exitDuration, const Duration(milliseconds: 520));
    expect(exitDisabled.entranceDuration, const Duration(milliseconds: 520));
    expect(exitDisabled.exitDuration, Duration.zero);
  });

  test('JSON round trip retains duration while both directions are none', () {
    const settings = DialogAnimationSettings(
      entranceStyle: DialogAnimationStyle.none,
      exitStyle: DialogAnimationStyle.none,
      durationMs: 700,
    );

    final json = settings.toJson();
    final restored = DialogAnimationSettings.fromJson(json);

    expect(json['duration_ms'], 700);
    expect(restored, settings);
    expect(restored.duration, Duration.zero);
  });

  test('legacy zero duration recovers the channel fallback', () {
    final settings = DialogAnimationSettings.fromJson(<String, Object?>{
      'entrance_style': 'none',
      'exit_style': 'none',
      'duration_ms': 0,
    }, fallbackDurationMs: 800);

    expect(settings.durationMs, 800);
    expect(settings.duration, Duration.zero);
  });
}
