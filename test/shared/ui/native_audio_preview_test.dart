import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/native_audio_preview.dart';

void main() {
  group('native audio playback backend selection', () {
    test('uses just_audio on Apple app targets', () {
      expect(
        selectNativeAudioPlaybackBackend(
          isWeb: false,
          targetPlatform: TargetPlatform.macOS,
        ),
        NativeAudioPlaybackBackendKind.justAudio,
      );
      expect(
        selectNativeAudioPlaybackBackend(
          isWeb: false,
          targetPlatform: TargetPlatform.iOS,
        ),
        NativeAudioPlaybackBackendKind.justAudio,
      );
    });

    test('keeps audioplayers for web and non-Apple desktop targets', () {
      expect(
        selectNativeAudioPlaybackBackend(
          isWeb: true,
          targetPlatform: TargetPlatform.macOS,
        ),
        NativeAudioPlaybackBackendKind.audioplayers,
      );
      expect(
        selectNativeAudioPlaybackBackend(
          isWeb: false,
          targetPlatform: TargetPlatform.windows,
        ),
        NativeAudioPlaybackBackendKind.audioplayers,
      );
    });
  });
}
