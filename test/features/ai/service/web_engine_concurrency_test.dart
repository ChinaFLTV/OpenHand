import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/web_engine_concurrency.dart';
import 'package:openhand/features/ai/service/web_engine_telemetry_store_base.dart';

void main() {
  group('WebEngineSemaphore', () {
    test('grants up to maxCount permits without waiting', () async {
      final sem = WebEngineSemaphore(3);
      // Three immediate acquires must all complete in the same microtask turn.
      final results = await Future.wait([
        sem.acquire(),
        sem.acquire(),
        sem.acquire(),
      ]);
      expect(results, hasLength(3));
    });

    test('queues additional acquires until release', () async {
      final sem = WebEngineSemaphore(1);
      await sem.acquire();

      var secondAcquired = false;
      final pending = sem.acquire().then((_) => secondAcquired = true);

      // Without release, the second acquire stays pending.
      await Future<void>.delayed(Duration.zero);
      expect(secondAcquired, isFalse);

      sem.release();
      await pending;
      expect(secondAcquired, isTrue);
    });

    test(
      'release without waiters refills available count, capped at maxCount',
      () async {
        final sem = WebEngineSemaphore(2);
        // Over-release must not push _available beyond maxCount.
        sem.release();
        sem.release();
        sem.release();
        // After three releases on a fresh semaphore we still only get 2 immediate
        // permits; the 3rd acquire must queue.
        await sem.acquire();
        await sem.acquire();

        var thirdAcquired = false;
        final pending = sem.acquire().then((_) => thirdAcquired = true);
        await Future<void>.delayed(Duration.zero);
        expect(thirdAcquired, isFalse);

        sem.release();
        await pending;
        expect(thirdAcquired, isTrue);
      },
    );

    test('FIFO ordering for queued waiters', () async {
      final sem = WebEngineSemaphore(1);
      await sem.acquire();

      final completedOrder = <int>[];
      final f1 = sem.acquire().then((_) => completedOrder.add(1));
      final f2 = sem.acquire().then((_) => completedOrder.add(2));
      final f3 = sem.acquire().then((_) => completedOrder.add(3));

      sem.release();
      await f1;
      sem.release();
      await f2;
      sem.release();
      await f3;

      expect(completedOrder, [1, 2, 3]);
    });
  });

  group('filterByCooldownThrottleWithFallback', () {
    test('uses primary configs when at least one is usable', () async {
      final outcome =
          await filterByCooldownThrottleWithFallback<
            _TestEngineConfig,
            _TestEngineKind
          >(
            primaryConfigs: const [_TestEngineConfig(_TestEngineKind.primary)],
            fallbackConfigs: const [
              _TestEngineConfig(_TestEngineKind.fallbackA),
            ],
            kindOf: (config) => config.kind,
            telemetry: _FakeTelemetry(),
            throttlePerMinute: 0,
          );

      expect(outcome.usable.map((config) => config.kind), [
        _TestEngineKind.primary,
      ]);
      expect(outcome.skipped, isEmpty);
      expect(outcome.fallbackUsed, isFalse);
    });

    test(
      'tries fallback configs when every primary config is skipped',
      () async {
        final outcome =
            await filterByCooldownThrottleWithFallback<
              _TestEngineConfig,
              _TestEngineKind
            >(
              primaryConfigs: const [
                _TestEngineConfig(_TestEngineKind.primary),
              ],
              fallbackConfigs: const [
                _TestEngineConfig(_TestEngineKind.fallbackA),
              ],
              kindOf: (config) => config.kind,
              telemetry: _FakeTelemetry(
                cooldownMs: const {_TestEngineKind.primary: 1000},
              ),
              throttlePerMinute: 0,
            );

        expect(outcome.usable.map((config) => config.kind), [
          _TestEngineKind.fallbackA,
        ]);
        expect(outcome.skipped.single.config.kind, _TestEngineKind.primary);
        expect(outcome.skipped.single.reason, 'skipped: cooldown active');
        expect(outcome.fallbackUsed, isTrue);
      },
    );

    test('does not retry a fallback kind already skipped as primary', () async {
      final outcome =
          await filterByCooldownThrottleWithFallback<
            _TestEngineConfig,
            _TestEngineKind
          >(
            primaryConfigs: const [
              _TestEngineConfig(_TestEngineKind.fallbackA),
            ],
            fallbackConfigs: const [
              _TestEngineConfig(_TestEngineKind.fallbackA),
              _TestEngineConfig(_TestEngineKind.fallbackB),
            ],
            kindOf: (config) => config.kind,
            telemetry: _FakeTelemetry(
              cooldownMs: const {_TestEngineKind.fallbackA: 1000},
            ),
            throttlePerMinute: 0,
          );

      expect(outcome.usable.map((config) => config.kind), [
        _TestEngineKind.fallbackB,
      ]);
      expect(outcome.skipped.map((item) => item.config.kind), [
        _TestEngineKind.fallbackA,
      ]);
      expect(outcome.fallbackUsed, isTrue);
    });

    test(
      'returns diagnostics instead of rerunning when fallback is also skipped',
      () async {
        final outcome =
            await filterByCooldownThrottleWithFallback<
              _TestEngineConfig,
              _TestEngineKind
            >(
              primaryConfigs: const [
                _TestEngineConfig(_TestEngineKind.primary),
              ],
              fallbackConfigs: const [
                _TestEngineConfig(_TestEngineKind.fallbackA),
              ],
              kindOf: (config) => config.kind,
              telemetry: _FakeTelemetry(
                cooldownMs: const {
                  _TestEngineKind.primary: 1000,
                  _TestEngineKind.fallbackA: 1000,
                },
              ),
              throttlePerMinute: 0,
            );

        expect(outcome.usable, isEmpty);
        expect(outcome.skipped.map((item) => item.config.kind), [
          _TestEngineKind.primary,
          _TestEngineKind.fallbackA,
        ]);
        expect(outcome.fallbackUsed, isTrue);
      },
    );

    test('skips by throttle when recent calls reach the limit', () async {
      final outcome =
          await filterByCooldownThrottleWithFallback<
            _TestEngineConfig,
            _TestEngineKind
          >(
            primaryConfigs: const [_TestEngineConfig(_TestEngineKind.primary)],
            fallbackConfigs: const [],
            kindOf: (config) => config.kind,
            telemetry: _FakeTelemetry(
              callsLastMinute: const {_TestEngineKind.primary: 3},
            ),
            throttlePerMinute: 3,
          );

      expect(outcome.usable, isEmpty);
      expect(outcome.skipped.single.reason, 'skipped: throttle limit reached');
      expect(outcome.fallbackUsed, isFalse);
    });
  });
}

enum _TestEngineKind { primary, fallbackA, fallbackB }

class _TestEngineConfig {
  const _TestEngineConfig(this.kind);

  final _TestEngineKind kind;
}

class _FakeTelemetry extends WebEngineTelemetryStoreBase<_TestEngineKind> {
  _FakeTelemetry({
    this.cooldownMs = const <_TestEngineKind, int>{},
    this.callsLastMinute = const <_TestEngineKind, int>{},
  });

  final Map<_TestEngineKind, int> cooldownMs;
  final Map<_TestEngineKind, int> callsLastMinute;

  @override
  String get subdir => 'test';

  @override
  String get logTag => 'test';

  @override
  List<_TestEngineKind> get kindValues => _TestEngineKind.values;

  @override
  _TestEngineKind? parseKind(String name) {
    return _TestEngineKind.values
        .where((kind) => kind.name == name)
        .firstOrNull;
  }

  @override
  Future<int> cooldownRemaining(_TestEngineKind kind) async {
    return cooldownMs[kind] ?? 0;
  }

  @override
  Future<int> callsInLastMinute(_TestEngineKind kind) async {
    return callsLastMinute[kind] ?? 0;
  }
}
