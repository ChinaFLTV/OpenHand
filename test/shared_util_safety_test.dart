import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/dialog_animation_settings.dart';
import 'package:openhand/shared/util/async_concurrency.dart';
import 'package:openhand/shared/util/timer_safety.dart';

void main() {
  group('runOrderedWithConcurrencyLimit', () {
    test('preserves result order while bounding worker count', () async {
      var active = 0;
      var maxActive = 0;

      final results = await runOrderedWithConcurrencyLimit<int>(
        itemCount: kOpenHandMaxAsyncConcurrency + 8,
        maxConcurrency: 999,
        task: (index) async {
          active += 1;
          maxActive = active > maxActive ? active : maxActive;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active -= 1;
          return index * 2;
        },
      );

      expect(
        results,
        List<int>.generate(kOpenHandMaxAsyncConcurrency + 8, (index) {
          return index * 2;
        }),
      );
      expect(maxActive, lessThanOrEqualTo(kOpenHandMaxAsyncConcurrency));
    });

    test('normalizes empty and invalid concurrency inputs', () async {
      final empty = await runOrderedWithConcurrencyLimit<int>(
        itemCount: 0,
        maxConcurrency: 4,
        task: (index) async => index,
      );
      final singleWorker = await runOrderedWithConcurrencyLimit<int>(
        itemCount: 3,
        maxConcurrency: 0,
        task: (index) async => index,
      );

      expect(empty, isEmpty);
      expect(singleWorker, <int>[0, 1, 2]);
    });
  });

  group('forEachIndexWithConcurrencyLimit', () {
    test('stops scheduling new work when shouldContinue turns false', () async {
      var keepGoing = true;
      final visited = <int>[];

      await forEachIndexWithConcurrencyLimit(
        itemCount: 8,
        maxConcurrency: 1,
        shouldContinue: () => keepGoing,
        task: (index) async {
          visited.add(index);
          if (index == 1) {
            keepGoing = false;
          }
        },
      );

      expect(visited, <int>[0, 1]);
    });
  });

  group('timer safety normalization', () {
    test('clamps one-shot and periodic timer durations', () {
      expect(safeTimerDelay(const Duration(days: -1)), Duration.zero);
      expect(
        safeTimerDelay(
          const Duration(days: 30),
          max: const Duration(seconds: 5),
        ),
        const Duration(seconds: 5),
      );
      expect(
        safePeriodicTimerInterval(const Duration(milliseconds: 1)),
        kOpenHandMinPeriodicTimerInterval,
      );
      expect(
        safePeriodicTimerInterval(
          const Duration(days: 30),
          max: const Duration(seconds: 10),
        ),
        const Duration(seconds: 10),
      );
    });
  });

  group('DialogAnimationSettings', () {
    test('normalizes unknown styles and clamps animated duration', () {
      final settings = DialogAnimationSettings.fromJson(<String, Object?>{
        'entrance_style': 'unknown',
        'exit_style': 'also_unknown',
        'duration_ms': 999999,
        'curve': 'missing',
      });

      expect(settings.entranceStyle, DialogAnimationStyle.fadeScale);
      expect(settings.exitStyle, DialogAnimationStyle.fadeScale);
      expect(settings.durationMs, DialogAnimationSettings.maxDurationMs);
      expect(settings.curve, DialogAnimationCurve.easeOutCubic);
    });

    test('keeps fully disabled motion at zero duration', () {
      final settings = DialogAnimationSettings.fromJson(<String, Object?>{
        'entrance_style': 'none',
        'exit_style': 'none',
        'duration_ms': 480,
      });

      expect(settings.disablesAnimation, isTrue);
      expect(settings.duration, Duration.zero);
      expect(settings.toJson()['duration_ms'], 0);
    });
  });
}
