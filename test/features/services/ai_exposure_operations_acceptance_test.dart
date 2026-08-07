import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/model/ai_exposure_models.dart';
import 'package:openhand/features/services/model/dependency_telemetry.dart';
import 'package:openhand/features/services/service/ai_jungler_runtime.dart';
import 'package:openhand/features/services/services_controller.dart';
import 'package:openhand/features/services/widgets/ai_exposure_monitoring_dialogs.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('operations surface switches all six tabs without backend data', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ServicesController(
      runtime: AiJunglerRuntime(),
      initialPreferences: AiExposurePreferences.defaults(),
      proxyInspectionFirstRunDelay: const Duration(days: 1),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ServicesController>.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(body: buildAiExposureOperationsTestSurface()),
        ),
      ),
    );
    await tester.pump();

    const tabs = <String>[
      'Status overview',
      'Pipeline',
      'Sources',
      'Network',
      'Storage',
      'Security',
    ];
    for (final tab in tabs) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(find.text(tab), findsWidgets);
      expect(tester.takeException(), isNull, reason: '切换 $tab 时抛出异常');
    }
  });

  testWidgets('all ten entity surfaces expose honest empty states', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ServicesController(
      runtime: AiJunglerRuntime(),
      initialPreferences: AiExposurePreferences.defaults(),
      proxyInspectionFirstRunDelay: const Duration(days: 1),
    );
    addTearDown(controller.dispose);

    const entities = <String>[
      'task',
      'source',
      'proxyEndpoint',
      'result',
      'log',
      'rule',
      'proxyRequest',
      'proxyProbe',
      'stage',
      'dependency',
    ];
    for (final entity in entities) {
      await tester.pumpWidget(
        ChangeNotifierProvider<ServicesController>.value(
          value: controller,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: buildAiExposureEntityTestSurface(entity),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$entity 空态渲染异常');
      expect(find.byType(Scaffold), findsOneWidget);
    }
  });

  test(
    'task effective boundary handles cancelled and unreported timestamps',
    () {
      final startedAt = DateTime.utc(2026, 8, 7, 1);
      final cancelledAt = startedAt.add(const Duration(seconds: 9));
      final progress = AiExposureProgress(
        jobId: 'job',
        stage: 'cancelled',
        discovered: 0,
        candidates: 0,
        valid: 0,
        highValue: 0,
        processed: 0,
        total: 0,
        message: '',
        updatedAt: DateTime.utc(2026, 8, 7, 2),
        updatedAtReported: false,
      );
      final task = AiExposureHistoryEntry(
        id: 'job',
        name: ' job ',
        stage: 'cancelled',
        sources: const <AiExposureSource>[],
        mode: AiExposureScanMode.incremental,
        authorizedScope: const <String>[],
        progress: progress,
        createdAt: startedAt,
        startedAt: startedAt,
        cancelledAt: cancelledAt,
      );

      expect(task.effectiveFinishedAt, cancelledAt);
      expect(task.durationUntil(cancelledAt)?.inSeconds, 9);
    },
  );

  test('dependency telemetry is bounded and counter rates reject resets', () {
    final history = DependencyTelemetryHistory(
      maxSamples: 2,
      maxAge: const Duration(hours: 1),
    );
    final base = DateTime.utc(2026, 8, 7);
    history.add({'capturedAt': base.toIso8601String(), 'value': 10});
    history.add({
      'capturedAt': base.add(const Duration(seconds: 2)).toIso8601String(),
      'value': 14,
    });
    history.add({
      'capturedAt': base.add(const Duration(seconds: 4)).toIso8601String(),
      'value': 3,
    });

    expect(history.samples, hasLength(2));
    expect(
      dependencyCounterRates(
        history.samples,
        (overview) => overview['value']! as num,
      ),
      [0, 0],
    );
    expect(dependencySafeRatio(1, 0), 0);
    expect(dependencySafeRatio(double.nan, 2), 0);
  });

  test('truncation notice is explicit only when records are hidden', () {
    expect(
      aiExposureListTruncationNotice(total: 40, visible: 30),
      '共 40 条，当前显示前 30 条（已截断）',
    );
    expect(aiExposureListTruncationNotice(total: 30, visible: 30), isNull);
  });

  test(
    'task duration requires a reported start and rejects negative spans',
    () {
      final start = DateTime.utc(2026, 8, 8, 1);
      final progress = AiExposureProgress(
        jobId: 'job',
        stage: 'completed',
        discovered: 0,
        candidates: 0,
        valid: 0,
        highValue: 0,
        processed: 0,
        total: 0,
        message: '',
        updatedAt: start.add(const Duration(minutes: 3)),
      );

      AiExposureHistoryEntry task({
        DateTime? startedAt,
        DateTime? finishedAt,
        DateTime? cancelledAt,
        DateTime? checkpointAt,
        bool createdAtReported = true,
      }) => AiExposureHistoryEntry(
        id: 'job',
        name: 'job',
        stage: 'completed',
        sources: const <AiExposureSource>[],
        mode: AiExposureScanMode.incremental,
        authorizedScope: const <String>[],
        progress: progress,
        createdAt: start,
        createdAtReported: createdAtReported,
        startedAt: startedAt,
        finishedAt: finishedAt,
        cancelledAt: cancelledAt,
        lastCheckpointAt: checkpointAt,
      );

      final finished = start.add(const Duration(minutes: 4));
      final cancelled = start.add(const Duration(minutes: 5));
      final checkpoint = start.add(const Duration(minutes: 6));
      final withAllBoundaries = task(
        startedAt: start,
        finishedAt: finished,
        cancelledAt: cancelled,
        checkpointAt: checkpoint,
      );
      expect(withAllBoundaries.effectiveFinishedAt, finished);
      expect(
        withAllBoundaries.durationUntil(checkpoint),
        const Duration(minutes: 4),
      );

      expect(
        task(
          createdAtReported: false,
          finishedAt: finished,
        ).durationUntil(finished),
        isNull,
      );
      expect(
        task(startedAt: finished, finishedAt: start).durationUntil(finished),
        isNull,
      );
    },
  );

  test(
    'telemetry history replaces duplicate times and rejects older samples',
    () {
      final history = DependencyTelemetryHistory(maxSamples: 4);
      final base = DateTime.utc(2026, 8, 8);
      history.add({'capturedAt': base.toIso8601String(), 'value': 1});
      history.add({'capturedAt': base.toIso8601String(), 'value': 2});
      history.add({
        'capturedAt': base
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
        'value': 3,
      });
      history.add({
        'capturedAt': base.add(const Duration(seconds: 2)).toIso8601String(),
        'value': double.infinity,
      });

      expect(history.samples, hasLength(2));
      expect(history.samples.first.overview['value'], 2);
      expect(
        dependencyCounterRates(
          history.samples,
          (overview) => overview['value']! as num,
        ),
        [0, 0],
      );
      expect(dependencySafeRatio(-1, 2), -0.5);
      expect(dependencySafeRatio(1, double.infinity), 0);
    },
  );
}
