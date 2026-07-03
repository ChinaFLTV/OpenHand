import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/native_audio_preview.dart';

void main() {
  test(
    'normalizeNativeAudioText collapses whitespace and removes audio suffix',
    () {
      expect(
        normalizeNativeAudioText('  demo   track.mp3  ', fallback: 'fallback'),
        'demo track',
      );
      expect(normalizeNativeAudioText('   ', fallback: 'fallback'), 'fallback');
    },
  );

  test('deriveNativeAudioArtist uses the first cleaned filename segment', () {
    expect(deriveNativeAudioArtist('/tmp/Alice - Morning.wav'), 'Alice');
    expect(deriveNativeAudioArtist('/tmp/audio_123.mp3'), 'OpenHand 音频');
  });
}
