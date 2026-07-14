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

/// Emits one alert when an engine enters an unhealthy state, then suppresses
/// repeats until that metric recovers. State is bounded by engine × alert kind.
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
