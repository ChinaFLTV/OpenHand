import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/services/model/dependency_telemetry.dart';

void main() {
  test('历史记录按时间和数量裁剪并去重', () {
    final history = DependencyTelemetryHistory(
      maxSamples: 2,
      maxAge: const Duration(minutes: 2),
    );
    final base = DateTime(2026, 8, 4, 12);

    history.add(<String, Object?>{'value': 1}, receivedAt: base);
    history.add(<String, Object?>{'value': 2}, receivedAt: base);
    history.add(<String, Object?>{
      'value': 3,
    }, receivedAt: base.add(const Duration(minutes: 1)));
    history.add(<String, Object?>{
      'value': 4,
    }, receivedAt: base.add(const Duration(minutes: 3)));

    expect(history.samples, hasLength(2));
    expect(history.samples.first.overview['value'], 3);
    expect(history.samples.last.overview['value'], 4);
  });

  test('计数器速率忽略重置与无效时间间隔', () {
    final base = DateTime(2026, 8, 4, 12);
    final samples = <DependencyTelemetrySample>[
      DependencyTelemetrySample(
        capturedAt: base,
        overview: const <String, Object?>{'value': 10},
      ),
      DependencyTelemetrySample(
        capturedAt: base.add(const Duration(seconds: 2)),
        overview: const <String, Object?>{'value': 18},
      ),
      DependencyTelemetrySample(
        capturedAt: base.add(const Duration(seconds: 4)),
        overview: const <String, Object?>{'value': 2},
      ),
    ];

    expect(
      dependencyCounterRates(samples, (overview) => overview['value']! as num),
      <double>[0, 4, 0],
    );
  });

  test('安全比例处理除零和无效数值', () {
    expect(dependencySafeRatio(1, 0), 0);
    expect(dependencySafeRatio(double.nan, 2), 0);
    expect(dependencySafeRatio(3, 4), 0.75);
  });
}
