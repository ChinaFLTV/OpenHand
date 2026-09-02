import 'dart:collection';

const int kDependencyTelemetryMaxSamples = 10800;
const Duration kDependencyTelemetryMaxAge = Duration(hours: 24);

class DependencyTelemetrySample {
  DependencyTelemetrySample({
    required this.capturedAt,
    required Map<String, Object?> overview,
  }) : overview = Map<String, Object?>.unmodifiable(overview);

  factory DependencyTelemetrySample.fromOverview(
    Map<String, Object?> overview, {
    DateTime? receivedAt,
  }) {
    final parsed = DateTime.tryParse('${overview['capturedAt'] ?? ''}');
    return DependencyTelemetrySample(
      capturedAt: (parsed ?? receivedAt ?? DateTime.now()).toLocal(),
      overview: overview,
    );
  }

  final DateTime capturedAt;
  final Map<String, Object?> overview;
}

class DependencyTelemetryHistory {
  DependencyTelemetryHistory({
    this.maxSamples = kDependencyTelemetryMaxSamples,
    this.maxAge = kDependencyTelemetryMaxAge,
  }) : assert(maxSamples > 0);

  final int maxSamples;
  final Duration maxAge;
  final List<DependencyTelemetrySample> _samples =
      <DependencyTelemetrySample>[];

  UnmodifiableListView<DependencyTelemetrySample> get samples =>
      UnmodifiableListView<DependencyTelemetrySample>(_samples);

  void add(Map<String, Object?> overview, {DateTime? receivedAt}) {
    if (overview.isEmpty) return;
    final sample = DependencyTelemetrySample.fromOverview(
      overview,
      receivedAt: receivedAt,
    );
    if (_samples.isNotEmpty &&
        !_samples.last.capturedAt.isBefore(sample.capturedAt)) {
      if (_samples.last.capturedAt == sample.capturedAt) {
        _samples[_samples.length - 1] = sample;
      }
      return;
    }
    _samples.add(sample);
    final cutoff = sample.capturedAt.subtract(maxAge);
    var expired = 0;
    while (expired < _samples.length &&
        _samples[expired].capturedAt.isBefore(cutoff)) {
      expired++;
    }
    if (expired > 0) _samples.removeRange(0, expired);
    if (_samples.length > maxSamples) {
      _samples.removeRange(0, _samples.length - maxSamples);
    }
  }

  List<DependencyTelemetrySample> within(Duration range, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(range);
    return List<DependencyTelemetrySample>.unmodifiable(
      _samples.where((sample) => !sample.capturedAt.isBefore(cutoff)),
    );
  }

  void clear() => _samples.clear();
}

double dependencySafeRatio(num numerator, num denominator) {
  final top = numerator.toDouble();
  final bottom = denominator.toDouble();
  if (!top.isFinite || !bottom.isFinite || bottom <= 0) return 0;
  return top / bottom;
}

List<double> dependencyCounterRates(
  List<DependencyTelemetrySample> samples,
  num Function(DependencyTelemetrySample sample) valueOf,
) {
  if (samples.isEmpty) return const <double>[];
  final rates = <double>[0];
  for (var index = 1; index < samples.length; index++) {
    final previous = valueOf(samples[index - 1]).toDouble();
    final current = valueOf(samples[index]).toDouble();
    final seconds =
        samples[index].capturedAt
            .difference(samples[index - 1].capturedAt)
            .inMilliseconds /
        Duration.millisecondsPerSecond;
    rates.add(
      previous.isFinite &&
              current.isFinite &&
              seconds > 0 &&
              current >= previous
          ? (current - previous) / seconds
          : 0,
    );
  }
  return rates;
}
