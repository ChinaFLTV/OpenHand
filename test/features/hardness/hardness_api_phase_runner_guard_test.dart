// 2026-05-04 — Pure unit test for HardnessApiPhaseRunner.guardedRunPhase.
// 锁定 try/finally 包装的契约：无论 run 正常返回 / 抛异常 / 被取消式
// 抛错，onPhaseEnded 都恰好被以正确的 phaseSessionId 调用一次；为
// `null` 时不抛 NPE。
//
// 不构造完整 runner 依赖图；只覆盖 finally 路径本身，等价于在
// 实际 runPhase 全 5 个 return 站点 + 任意 throw 的兜底验证。

import 'package:flutter_test/flutter_test.dart';

import 'package:openhand/features/hardness/hardness_api_phase_runner.dart';

void main() {
  group('HardnessApiPhaseRunner.guardedRunPhase', () {
    test('invokes onPhaseEnded once on normal return', () async {
      final calls = <String>[];
      final result = await HardnessApiPhaseRunner.guardedRunPhase<int>(
        phaseSessionId: 'phase-A',
        onPhaseEnded: ({required phaseSessionId}) =>
            calls.add(phaseSessionId),
        run: () async => 42,
      );
      expect(result, 42);
      expect(calls, ['phase-A']);
    });

    test('invokes onPhaseEnded once when run throws synchronously', () async {
      final calls = <String>[];
      await expectLater(
        HardnessApiPhaseRunner.guardedRunPhase<int>(
          phaseSessionId: 'phase-B',
          onPhaseEnded: ({required phaseSessionId}) =>
              calls.add(phaseSessionId),
          run: () => throw StateError('boom-sync'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(calls, ['phase-B']);
    });

    test('invokes onPhaseEnded once when run rejects asynchronously',
        () async {
      final calls = <String>[];
      await expectLater(
        HardnessApiPhaseRunner.guardedRunPhase<int>(
          phaseSessionId: 'phase-C',
          onPhaseEnded: ({required phaseSessionId}) =>
              calls.add(phaseSessionId),
          run: () async {
            await Future<void>.delayed(const Duration(milliseconds: 1));
            throw const FormatException('boom-async');
          },
        ),
        throwsA(isA<FormatException>()),
      );
      expect(calls, ['phase-C']);
    });

    test('does not throw when onPhaseEnded is null (success path)',
        () async {
      final result = await HardnessApiPhaseRunner.guardedRunPhase<String>(
        phaseSessionId: 'phase-D',
        onPhaseEnded: null,
        run: () async => 'ok',
      );
      expect(result, 'ok');
    });

    test('does not throw when onPhaseEnded is null (throw path)', () async {
      await expectLater(
        HardnessApiPhaseRunner.guardedRunPhase<String>(
          phaseSessionId: 'phase-E',
          onPhaseEnded: null,
          run: () async => throw Exception('x'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('serial calls fire onPhaseEnded once each', () async {
      final calls = <String>[];
      void cb({required String phaseSessionId}) => calls.add(phaseSessionId);
      await HardnessApiPhaseRunner.guardedRunPhase<int>(
        phaseSessionId: 'phase-F',
        onPhaseEnded: cb,
        run: () async => 1,
      );
      await HardnessApiPhaseRunner.guardedRunPhase<int>(
        phaseSessionId: 'phase-G',
        onPhaseEnded: cb,
        run: () async => 2,
      );
      expect(calls, ['phase-F', 'phase-G']);
    });
  });
}
