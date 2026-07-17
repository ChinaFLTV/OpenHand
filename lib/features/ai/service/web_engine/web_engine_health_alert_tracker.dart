import '../../../../app/support/openhand_notification_service.dart';
import '../../../../app/support/silent_log.dart';
import 'web_engine_telemetry_store_base.dart';

enum WebEngineHealthAlertKind { lowSuccessRate, slowAverageDuration }

class WebEngineHealthAlert {
  const WebEngineHealthAlert({
    required this.kind,
    required this.engineName,
    required this.actualValue,
    required this.threshold,
  });

  final WebEngineHealthAlertKind kind;
  final String engineName;
  final int actualValue;
  final int threshold;
}

/// 引擎进入异常状态时仅提醒一次，指标恢复后才允许再次提醒。
class WebEngineHealthAlertTracker {
  static const int minimumSampleCount = 5;

  final Set<(String, WebEngineHealthAlertKind)> _activeAlerts =
      <(String, WebEngineHealthAlertKind)>{};

  List<WebEngineHealthAlert> update({
    required String engineName,
    required int totalCalls,
    required double successRate,
    required double averageDurationMs,
    required int successRateThresholdPct,
    required int averageDurationThresholdMs,
  }) {
    final normalizedEngineName = engineName.trim();
    if (normalizedEngineName.isEmpty) return const <WebEngineHealthAlert>[];
    if (totalCalls < minimumSampleCount) {
      _removeEngine(normalizedEngineName);
      return const <WebEngineHealthAlert>[];
    }

    final successRatePct = (successRate * 100).round();
    final averageDuration = averageDurationMs.round();
    final alerts = <WebEngineHealthAlert>[];
    _updateMetric(
      alerts,
      kind: WebEngineHealthAlertKind.lowSuccessRate,
      engineName: normalizedEngineName,
      unhealthy:
          successRateThresholdPct > 0 &&
          successRatePct < successRateThresholdPct,
      actualValue: successRatePct,
      threshold: successRateThresholdPct,
    );
    _updateMetric(
      alerts,
      kind: WebEngineHealthAlertKind.slowAverageDuration,
      engineName: normalizedEngineName,
      unhealthy:
          averageDurationThresholdMs > 0 &&
          averageDuration > averageDurationThresholdMs,
      actualValue: averageDuration,
      threshold: averageDurationThresholdMs,
    );
    return alerts;
  }

  void retainEngines(Iterable<String> engineNames) {
    final retained = engineNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    _activeAlerts.removeWhere((entry) => !retained.contains(entry.$1));
  }

  void reset() => _activeAlerts.clear();

  Future<void> notifyFromStats<E, S extends WebEngineStatBase>({
    required Future<Map<E, S>> Function() loadStats,
    required String Function(E engine) engineName,
    required int successRateThresholdPct,
    required int averageDurationThresholdMs,
    required String titlePrefix,
    required String logTag,
  }) async {
    if (successRateThresholdPct <= 0 && averageDurationThresholdMs <= 0) {
      reset();
      return;
    }
    try {
      final stats = await loadStats();
      retainEngines(stats.keys.map(engineName));
      for (final entry in stats.entries) {
        final stat = entry.value;
        final alerts = update(
          engineName: engineName(entry.key),
          totalCalls: stat.totalCalls,
          successRate: stat.successRate,
          averageDurationMs: stat.avgDurationMs,
          successRateThresholdPct: successRateThresholdPct,
          averageDurationThresholdMs: averageDurationThresholdMs,
        );
        for (final alert in alerts) {
          final body = switch (alert.kind) {
            WebEngineHealthAlertKind.lowSuccessRate =>
              '成功率 ${alert.actualValue}% < 阈值 ${alert.threshold}%'
                  '（共 ${stat.totalCalls} 次调用）',
            WebEngineHealthAlertKind.slowAverageDuration =>
              '平均耗时 ${alert.actualValue}ms > 阈值 ${alert.threshold}ms',
          };
          await OpenHandNotificationService.showInApp(
            title: '$titlePrefix · ${alert.engineName}',
            body: body,
            level: OpenHandNotificationLevel.warning,
          );
        }
      }
    } catch (error, stack) {
      silentLog(logTag, '检查 Web 引擎健康状态', error, stack);
    }
  }

  void _updateMetric(
    List<WebEngineHealthAlert> alerts, {
    required WebEngineHealthAlertKind kind,
    required String engineName,
    required bool unhealthy,
    required int actualValue,
    required int threshold,
  }) {
    final key = (engineName, kind);
    if (!unhealthy) {
      _activeAlerts.remove(key);
      return;
    }
    if (!_activeAlerts.add(key)) return;
    alerts.add(
      WebEngineHealthAlert(
        kind: kind,
        engineName: engineName,
        actualValue: actualValue,
        threshold: threshold,
      ),
    );
  }

  void _removeEngine(String engineName) {
    _activeAlerts.removeWhere((entry) => entry.$1 == engineName);
  }
}
