import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/ui/native_audio_preview.dart';

void main() {
  group('native audio seek guards', () {
    test(
      'keeps optimistic seek position when platform echoes the beginning',
      () {
        final requestedAt = DateTime(2026, 6, 24, 12);
        final ignore = shouldIgnoreNativeAudioSeekEcho(
          candidate: Duration.zero,
          target: const Duration(seconds: 40),
          hasActiveSeekEchoGuard: true,
          requestedAt: requestedAt,
          isPlaying: true,
          now: requestedAt.add(const Duration(milliseconds: 600)),
        );

        expect(ignore, isTrue);
      },
    );

    test(
      'accepts reported progress once playback advances near the seek target',
      () {
        final requestedAt = DateTime(2026, 6, 24, 12);
        final close = isNativeAudioSeekCandidateCloseToTarget(
          candidate: const Duration(seconds: 42),
          target: const Duration(seconds: 40),
          requestedAt: requestedAt,
          isPlaying: true,
          now: requestedAt.add(const Duration(seconds: 1)),
        );

        expect(close, isTrue);
      },
    );

    test('ignores non-user large rewinds after seek repair guard expires', () {
      final ignore = shouldIgnoreNativeAudioUnexpectedRewind(
        candidate: const Duration(seconds: 12),
        displayedPosition: const Duration(seconds: 45),
        sourceReady: true,
        playerCompleted: false,
      );

      expect(ignore, isTrue);
    });

    test('allows legitimate early progress and completed reset states', () {
      expect(
        shouldIgnoreNativeAudioUnexpectedRewind(
          candidate: const Duration(seconds: 1),
          displayedPosition: const Duration(seconds: 3),
          sourceReady: true,
          playerCompleted: false,
        ),
        isFalse,
      );
      expect(
        shouldIgnoreNativeAudioUnexpectedRewind(
          candidate: Duration.zero,
          displayedPosition: const Duration(minutes: 2),
          sourceReady: true,
          playerCompleted: true,
        ),
        isFalse,
      );
    });
  });
}
