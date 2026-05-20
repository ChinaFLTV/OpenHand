import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';

void main() {
  test('default dialog and menu animation settings are spring based', () {
    final snapshot = AppSettingsSnapshot.defaults();

    expect(
      snapshot.dialogAnimationSettings.entranceStyle,
      DialogAnimationStyle.springScale,
    );
    expect(
      snapshot.dialogAnimationSettings.exitStyle,
      DialogAnimationStyle.springScale,
    );
    expect(snapshot.dialogAnimationSettings.durationMs, 360);

    expect(
      snapshot.menuAnimationSettings.entranceStyle,
      DialogAnimationStyle.springScale,
    );
    expect(
      snapshot.menuAnimationSettings.exitStyle,
      DialogAnimationStyle.springScale,
    );
    expect(snapshot.menuAnimationSettings.durationMs, 260);
  });
}
