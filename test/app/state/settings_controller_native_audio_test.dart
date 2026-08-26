import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';
import 'package:openhand/shared/model/native_audio_playback_settings.dart';

void main() {
  test('音频播放设置通过全局控制器持久化', () async {
    final store = _MemorySettingsStore();
    final controller = await SettingsController.create(store: store);
    final expected = NativeAudioPlaybackSettings(
      volume: 0.38,
      effect: NativeAudioEffect.warm,
    );

    expect(
      await controller.updateNativeAudioPlaybackSettings(expected),
      isTrue,
    );
    controller.dispose();

    final restored = await SettingsController.create(store: store);
    addTearDown(restored.dispose);
    expect(restored.nativeAudioPlaybackSettings, expected);
  });
}

class _MemorySettingsStore extends SettingsStore {
  AppSettingsSnapshot snapshot = AppSettingsSnapshot.defaults();

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: snapshot, canPersist: true);
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}
