import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/model/native_audio_playback_settings.dart';

void main() {
  group('原生音频播放设置', () {
    test('默认值保持当前播放体验', () {
      final settings = NativeAudioPlaybackSettings.defaults();

      expect(settings.volume, NativeAudioPlaybackSettings.defaultVolume);
      expect(settings.effect, NativeAudioEffect.standard);
    });

    test('支持 JSON 往返', () {
      final settings = NativeAudioPlaybackSettings(
        volume: 0.42,
        effect: NativeAudioEffect.spatial,
      );

      expect(NativeAudioPlaybackSettings.fromJson(settings.toJson()), settings);
    });

    test('音量越界时钳制且无效数值回退默认值', () {
      expect(NativeAudioPlaybackSettings(volume: -1).volume, 0);
      expect(NativeAudioPlaybackSettings(volume: 2).volume, 1);
      expect(
        NativeAudioPlaybackSettings(volume: double.nan).volume,
        NativeAudioPlaybackSettings.defaultVolume,
      );
      expect(
        NativeAudioPlaybackSettings.fromJson(<String, Object?>{
          'volume': 'invalid',
        }).volume,
        NativeAudioPlaybackSettings.defaultVolume,
      );
    });

    test('未知音效回退标准模式', () {
      final settings = NativeAudioPlaybackSettings.fromJson(<String, Object?>{
        'effect': 'unknown',
      });

      expect(settings.effect, NativeAudioEffect.standard);
    });
  });
}
