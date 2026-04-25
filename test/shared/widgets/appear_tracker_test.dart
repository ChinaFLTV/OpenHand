import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/widgets/appear_tracker.dart';

void main() {
  group('AppearTracker', () {
    test('does not animate anything before initial build is marked done', () {
      final tracker = AppearTracker();
      expect(tracker.shouldAnimate('a'), isFalse);
      expect(tracker.shouldAnimate('b'), isFalse);
      tracker.markSeen('a');
      // Even if we ask again, no animation until initial build done.
      expect(tracker.shouldAnimate('a'), isFalse);
    });

    test('animates only ids unseen after initial build is done', () {
      final tracker = AppearTracker();
      // Pre-populate with the existing sidebar contents.
      tracker.markSeen('ai-1');
      tracker.markSeen('ai-2');
      tracker.markSeen('he-h1');
      tracker.markInitialBuildDone();

      expect(tracker.shouldAnimate('ai-1'), isFalse);
      expect(tracker.shouldAnimate('ai-2'), isFalse);
      expect(tracker.shouldAnimate('he-h1'), isFalse);

      // A user creates a new thread.
      expect(tracker.shouldAnimate('ai-3'), isTrue);
      tracker.markSeen('ai-3');
      // Subsequent rebuild: must not re-animate.
      expect(tracker.shouldAnimate('ai-3'), isFalse);
    });

    test(
      'retainOnly forgets ids no longer present so a future re-appearance '
      'animates again',
      () {
        final tracker = AppearTracker();
        tracker.markSeen('ai-1');
        tracker.markSeen('ai-2');
        tracker.markInitialBuildDone();

        // User deletes ai-2.
        tracker.retainOnly(<String>['ai-1']);
        expect(tracker.seenIdsForTest, equals(<String>{'ai-1'}));

        // A snapshot restore brings ai-2 back.
        expect(tracker.shouldAnimate('ai-2'), isTrue);
      },
    );

    test('isInitialBuildDone reflects markInitialBuildDone', () {
      final tracker = AppearTracker();
      expect(tracker.isInitialBuildDone, isFalse);
      tracker.markInitialBuildDone();
      expect(tracker.isInitialBuildDone, isTrue);
    });

    test('seenIdsForTest is unmodifiable', () {
      final tracker = AppearTracker();
      tracker.markSeen('a');
      expect(
        () => tracker.seenIdsForTest.add('b'),
        throwsUnsupportedError,
      );
    });
  });
}
