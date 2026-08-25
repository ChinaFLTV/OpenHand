import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/shared/util/timer_safety.dart';

void main() {
  group('非重入周期定时器', () {
    test('回调完成后不应触发超时', () async {
      final errors = <Object>[];
      final timer = startNonOverlappingPeriodicTimer(
        const Duration(milliseconds: 20),
        (_) {},
        min: const Duration(milliseconds: 1),
        callbackTimeout: const Duration(milliseconds: 100),
        onError: (error, _) => errors.add(error),
      );

      await Future<void>.delayed(const Duration(milliseconds: 45));
      timer.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(errors, isEmpty);
    });

    test('回调超时后默认取消定时器并上报异常', () async {
      final errors = <Object>[];
      final gate = Completer<void>();
      var ticks = 0;
      final timer = startNonOverlappingPeriodicTimer(
        const Duration(milliseconds: 10),
        (_) async {
          ticks += 1;
          await gate.future;
        },
        min: const Duration(milliseconds: 1),
        callbackTimeout: const Duration(milliseconds: 25),
        onError: (error, _) => errors.add(error),
      );

      await Future<void>.delayed(const Duration(milliseconds: 70));
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(ticks, 1);
      expect(errors, hasLength(1));
      expect(errors.single, isA<TimeoutException>());
      expect(timer.isActive, isFalse);
    });

    test('回调异常后立即释放超时计时器并继续工作', () async {
      final errors = <Object>[];
      var ticks = 0;
      final timer = startNonOverlappingPeriodicTimer(
        const Duration(milliseconds: 10),
        (_) {
          ticks += 1;
          throw StateError('模拟回调异常');
        },
        min: const Duration(milliseconds: 1),
        callbackTimeout: const Duration(milliseconds: 100),
        onError: (error, _) => errors.add(error),
      );

      await Future<void>.delayed(const Duration(milliseconds: 35));
      timer.cancel();

      expect(ticks, greaterThanOrEqualTo(2));
      expect(errors, everyElement(isA<StateError>()));
    });

    test('关闭超时取消后不会重入仍在执行的回调', () async {
      final gate = Completer<void>();
      var active = 0;
      var maxActive = 0;
      final errors = <Object>[];
      final timer = startNonOverlappingPeriodicTimer(
        const Duration(milliseconds: 5),
        (_) async {
          active += 1;
          maxActive = active > maxActive ? active : maxActive;
          await gate.future;
          active -= 1;
        },
        min: const Duration(milliseconds: 1),
        callbackTimeout: const Duration(milliseconds: 15),
        cancelOnCallbackTimeout: false,
        onError: (error, _) => errors.add(error),
      );

      await Future<void>.delayed(const Duration(milliseconds: 25));
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      timer.cancel();

      expect(maxActive, 1);
      expect(errors, hasLength(1));
      expect(errors.single, isA<TimeoutException>());
    });
  });
}
