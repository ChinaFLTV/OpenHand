import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/native_audio_preview.dart';

void main() {
  group('native audio playback backend selection', () {
    test('uses media_kit on Apple app targets', () {
      expect(
        selectNativeAudioPlaybackBackend(
          isWeb: false,
          targetPlatform: TargetPlatform.macOS,
        ),
        NativeAudioPlaybackBackendKind.mediaKit,
      );
      expect(
        selectNativeAudioPlaybackBackend(
          isWeb: false,
          targetPlatform: TargetPlatform.iOS,
        ),
        NativeAudioPlaybackBackendKind.mediaKit,
      );
    });

    test('keeps media_kit for web and non-Apple desktop targets', () {
      expect(
        selectNativeAudioPlaybackBackend(
          isWeb: true,
          targetPlatform: TargetPlatform.macOS,
        ),
        NativeAudioPlaybackBackendKind.mediaKit,
      );
      expect(
        selectNativeAudioPlaybackBackend(
          isWeb: false,
          targetPlatform: TargetPlatform.windows,
        ),
        NativeAudioPlaybackBackendKind.mediaKit,
      );
    });
  });

  group('native audio source identity', () {
    test('treats equal byte content as the same media source', () {
      final first = NativeAudioPreviewSource.bytes(
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        mimeType: 'audio/mpeg',
      );
      final second = NativeAudioPreviewSource.bytes(
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        mimeType: 'audio/mpeg',
      );

      expect(nativeAudioPreviewSourcesReferToSameMedia(first, second), isTrue);
    });

    test('keeps different media sources distinct', () {
      final first = NativeAudioPreviewSource.bytes(
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        mimeType: 'audio/mpeg',
      );
      final second = NativeAudioPreviewSource.bytes(
        bytes: Uint8List.fromList(<int>[1, 2, 3, 5]),
        mimeType: 'audio/mpeg',
      );

      expect(nativeAudioPreviewSourcesReferToSameMedia(first, second), isFalse);
    });
  });
}
