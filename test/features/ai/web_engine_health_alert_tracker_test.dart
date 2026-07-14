import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/ai/service/web_engine/web_engine_health_alert_tracker.dart';

void main() {
  test('alerts only on unhealthy transitions and resets after recovery', () {
    final tracker = WebEngineHealthAlertTracker();

    expect(
      tracker.update(
        engineName: 'bing',
        totalCalls: 4,
        successRate: 0,
        averageDurationMs: 5000,
        successRateThresholdPct: 80,
        averageDurationThresholdMs: 1000,
      ),
      isEmpty,
    );

    final firstAlerts = tracker.update(
      engineName: 'bing',
      totalCalls: 5,
      successRate: 0.4,
      averageDurationMs: 1500,
      successRateThresholdPct: 80,
      averageDurationThresholdMs: 1000,
    );
    expect(firstAlerts.map((alert) => alert.kind), <WebEngineHealthAlertKind>[
      WebEngineHealthAlertKind.lowSuccessRate,
      WebEngineHealthAlertKind.slowAverageDuration,
    ]);

    expect(
      tracker.update(
        engineName: 'bing',
        totalCalls: 6,
        successRate: 0.5,
        averageDurationMs: 1600,
        successRateThresholdPct: 80,
        averageDurationThresholdMs: 1000,
      ),
      isEmpty,
    );

    expect(
      tracker.update(
        engineName: 'bing',
        totalCalls: 7,
        successRate: 0.9,
        averageDurationMs: 900,
        successRateThresholdPct: 80,
        averageDurationThresholdMs: 1000,
      ),
      isEmpty,
    );

    final regressed = tracker.update(
      engineName: 'bing',
      totalCalls: 8,
      successRate: 0.7,
      averageDurationMs: 800,
      successRateThresholdPct: 80,
      averageDurationThresholdMs: 1000,
    );
    expect(regressed, hasLength(1));
    expect(regressed.single.kind, WebEngineHealthAlertKind.lowSuccessRate);

    tracker.retainEngines(const <String>[]);
    expect(
      tracker.update(
        engineName: 'bing',
        totalCalls: 9,
        successRate: 0.6,
        averageDurationMs: 700,
        successRateThresholdPct: 80,
        averageDurationThresholdMs: 1000,
      ),
      hasLength(1),
    );
  });
}
