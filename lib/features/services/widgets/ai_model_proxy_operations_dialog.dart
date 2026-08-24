import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_live_value.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_ops_press_scale.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_metric_cells.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../ai_model_proxy_controller.dart';
import '../model/ai_model_proxy_models.dart';
import '../service/ai_model_proxy_network.dart';
import 'service_dialog_controls.dart';

const double _kProxyOpsGap = 16;
const double _kProxyOpsPanelRadius = 16;
const double _kProxyOpsMaxWidth = 1180;
const double _kProxyOpsMaxHeight = 860;
const double _kProxyOpsOuterRadius = 28;
const double _kProxyOpsShellRadius = 20;
const int _kProxyOpsTrendBuckets = 12;
const Duration _kProxyOpsTrendWindow = Duration(
  minutes: _kProxyOpsTrendBuckets,
);
const double _kProxyOpsTrendChartHeight = 204;
const double _kProxyOpsSubDialogWidthFraction = 0.94;
const double _kProxyOpsSubDialogHeightFraction = 0.92;
const double _kProxyOpsInsightMaxWidth = 940;
const double _kProxyOpsInsightMaxHeight = 800;
const double _kProxyOpsMetricMinCellWidth = 120;
const double _kProxyOpsPanelPairBreakpoint = 480;
const double _kProxyOpsDonutHeight = 220;
const double _kProxyOpsGaugeSize = 108;
const double _kProxyOpsMetricHelperHeight = 16;
const double _kProxyOpsRankBodyMaxHeight = 444;
const double _kProxyOpsConnectionListMaxHeight = 290;
const int _kProxyOpsHourBuckets = 24;
const int _kProxyOpsFastLatencyMs = 1000;
const int _kProxyOpsSlowLatencyMs = 3000;

Future<void> showAiModelProxyOperationsDialog(BuildContext context) =>
    showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => buildOpenHandResponsiveDialogShell(
        context: dialogContext,
        maxWidth: _kProxyOpsMaxWidth,
        maxHeight: _kProxyOpsMaxHeight,
        maxWidthFraction: 0.95,
        maxHeightFraction: 0.92,
        minAvailableWidth: 320,
        horizontalMargin: 24,
        verticalMargin: 42,
        child: const ServiceDialogInteractionTheme(
          child: _AiModelProxyOperationsDialog(),
        ),
      ),
    );

class _AiModelProxyOperationsDialog extends StatefulWidget {
  const _AiModelProxyOperationsDialog();

  @override
  State<_AiModelProxyOperationsDialog> createState() =>
      _AiModelProxyOperationsDialogState();
}

class _AiModelProxyOperationsDialogState
    extends State<_AiModelProxyOperationsDialog> {
  final _ProxyOpsSnapshotHold _hold = _ProxyOpsSnapshotHold();
  String? _lanHostKey;
  Future<List<String>>? _lanHostsFuture;

  Future<List<String>> _resolveLanHostsFuture(String listenHost) {
    final key = listenHost.trim().toLowerCase();
    if (_lanHostKey == key && _lanHostsFuture != null) {
      return _lanHostsFuture!;
    }
    _lanHostKey = key;
    _lanHostsFuture = discoverAiModelProxyLanHosts(listenHost);
    return _lanHostsFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AiModelProxyController>();
    final providers = context.select<SettingsController, List<AiModelConfig>>(
      (settings) => settings.aiModels,
    );
    final data = _hold.resolve(controller, providers);
    final lanHostsFuture = _resolveLanHostsFuture(data.settings.listenHost);
    final text = openHandTextResolver(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(15),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.monitor_heart_rounded,
                  color: cs.onPrimaryContainer,
                ),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text(zh: '服务运维', en: 'Service operations'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    kOpenHandGap4,
                    Text(
                      text(
                        zh: '实时观察入口健康、调度质量、请求流量与后备模型表现。',
                        en: 'Observe endpoint health, routing quality, traffic and backend performance.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          kOpenHandGap16,
          Flexible(
            child: ListView(
              shrinkWrap: true,
              physics: openHandDialogAwareScrollPhysics(context),
              padding: EdgeInsets.zero,
              children: [
                FutureBuilder<List<String>>(
                  future: lanHostsFuture,
                  builder: (context, snapshot) => _ProxyOpsHero(
                    data: data,
                    lanHosts: snapshot.data ?? const <String>[],
                    lanHostsReady:
                        snapshot.connectionState == ConnectionState.done,
                  ),
                ),
                const SizedBox(height: _kProxyOpsGap),
                _ProxyOpsMetricGrid(data: data),
                const SizedBox(height: _kProxyOpsGap),
                _ProxyOpsTrendRow(data: data),
                const SizedBox(height: _kProxyOpsGap),
                _ProxyOpsDistributionGrid(data: data),
                const SizedBox(height: _kProxyOpsGap),
                _ProxyOpsRecentRequests(data: data),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ProxyOpsInsightKind {
  connections,
  activeRequests,
  requests,
  ingress,
  succeeded,
  failures,
  ingressErrors,
  averageLatency,
  p95Latency,
  tokens,
  inbound,
  outbound,
  exposedModels,
  backends,
  requestTrend,
  latencyTrend,
  statusMix,
  providerMix,
  modelMix,
  clientMix,
}

void _showProxyOpsInsight(BuildContext context, _ProxyOpsInsightKind kind) {
  final spec = _proxyOpsInsightSpec(context, kind);
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => ServiceDialogInteractionTheme(
      child: _ProxyOpsInsightDialog(
        icon: spec.icon,
        title: spec.title,
        subtitle: spec.subtitle,
        tone: spec.tone,
        sections: spec.sections,
      ),
    ),
  );
}

class _ProxyOpsSnapshotHold {
  List<AiModelProxyRequestRecord>? _records;
  List<AiModelProxyTelemetryBucket>? _telemetry;
  List<AiModelConfig>? _providers;
  _ProxyOpsSnapshot? _cache;

  _ProxyOpsSnapshot resolve(
    AiModelProxyController controller,
    List<AiModelConfig> providers,
  ) {
    final records = controller.settings.recentRequests;
    final telemetry = controller.telemetryBuckets;
    if (_cache != null &&
        identical(records, _records) &&
        identical(telemetry, _telemetry) &&
        identical(providers, _providers)) {
      return _cache!;
    }
    _records = records;
    _telemetry = telemetry;
    _providers = providers;
    _cache = _ProxyOpsSnapshot.from(controller, providers: providers);
    return _cache!;
  }
}

class _ProxyOpsSnapshot {
  const _ProxyOpsSnapshot({
    required this.controller,
    required this.settings,
    required this.records,
    required this.providerNames,
    required this.p50LatencyMs,
    required this.p95LatencyMs,
    required this.p99LatencyMs,
    required this.maxLatencyMs,
    required this.maxTokens,
    required this.uniquePeerCount,
    required this.uniquePortCount,
    required this.trendSuccess,
    required this.trendFailure,
    required this.averageLatencyBuckets,
    required this.p95LatencyBuckets,
    required this.tokenBuckets,
    required this.connectionBuckets,
    required this.ingressErrorBuckets,
    required this.inboundByteBuckets,
    required this.outboundByteBuckets,
    required this.hourRequestCounts,
    required this.hourPeerCounts,
    required this.hourFailureCounts,
    required this.hourStats,
    required this.trendEndAt,
    required this.usesHistoricalTrendWindow,
  });

  factory _ProxyOpsSnapshot.from(
    AiModelProxyController controller, {
    required List<AiModelConfig> providers,
  }) {
    final settings = controller.settings;
    final records = settings.recentRequests;
    final telemetry = controller.telemetryBuckets;
    final providerNames = <String, String>{
      for (final provider in providers)
        if (provider.id.trim().isNotEmpty)
          provider.id.trim().toLowerCase(): _providerDisplayName(provider),
    };
    final now = DateTime.now();
    final activity = _proxyOpsRequestActivitySpan(
      records: records,
      telemetry: telemetry,
      lastRequestAt: settings.lastRequestAt,
    );
    var latestRequestAt = activity.latest;
    if (latestRequestAt != null && latestRequestAt.isAfter(now)) {
      latestRequestAt = now;
    }
    var usesHistoricalTrendWindow = false;
    var trendEndAt = now;
    if (latestRequestAt != null &&
        now.difference(latestRequestAt) >= _kProxyOpsTrendWindow) {
      usesHistoricalTrendWindow = true;
      trendEndAt = latestRequestAt;
    }
    final trendEndKey = aiModelProxyTelemetryBucketKey(trendEndAt);
    var earliestSignal = trendEndAt;
    final earliestRequestAt = activity.earliest;
    if (earliestRequestAt != null &&
        earliestRequestAt.isBefore(earliestSignal)) {
      earliestSignal = earliestRequestAt;
    }
    if (telemetry.isNotEmpty &&
        telemetry.first.bucketAt.isBefore(earliestSignal)) {
      earliestSignal = telemetry.first.bucketAt;
    }
    final earliestKey = aiModelProxyTelemetryBucketKey(earliestSignal);
    final trendBucketCount = math
        .max(
          _kProxyOpsTrendBuckets,
          ((trendEndKey - earliestKey) ~/ aiModelProxyTelemetryBucketMs + 1)
              .clamp(1, aiModelProxyTelemetryLoadLimit),
        )
        .toInt();
    final success = List<double>.filled(trendBucketCount, 0);
    final failure = List<double>.filled(trendBucketCount, 0);
    final tokens = List<double>.filled(trendBucketCount, 0);
    final connections = List<double>.filled(trendBucketCount, 0);
    final ingressErrors = List<double>.filled(trendBucketCount, 0);
    final inboundBytes = List<double>.filled(trendBucketCount, 0);
    final outboundBytes = List<double>.filled(trendBucketCount, 0);
    final latencyBuckets = List<List<int>>.generate(
      trendBucketCount,
      (_) => <int>[],
    );
    final hourStats = List<_ProxyOpsGroupStat>.generate(
      _kProxyOpsHourBuckets,
      (hour) => _ProxyOpsGroupStat(twoDigit(hour)),
    );
    final peers = <String>{};
    final ports = <String>{};
    final durations = <int>[];
    var maxTokens = 0;
    for (final record in records) {
      durations.add(record.durationMs);
      if (record.tokens > maxTokens) maxTokens = record.tokens;
      final hour = record.startedAt.hour.clamp(0, _kProxyOpsHourBuckets - 1);
      _proxyOpsAccumulateRecord(hourStats[hour], record);
      final peer = _proxyOpsRecordPeer(record);
      if (peer.isNotEmpty) peers.add(peer);
      final port = record.clientPort.trim();
      if (port.isNotEmpty) ports.add(port);
      final recordKey = aiModelProxyTelemetryBucketKey(record.startedAt);
      final age = (trendEndKey - recordKey) ~/ aiModelProxyTelemetryBucketMs;
      if (age < 0 || age >= trendBucketCount) continue;
      final index = trendBucketCount - age - 1;
      (record.success ? success : failure)[index] += 1;
      tokens[index] += record.tokens;
      latencyBuckets[index].add(record.durationMs);
    }
    final averageLatency = List<double>.filled(trendBucketCount, 0);
    final p95Latency = List<double>.filled(trendBucketCount, 0);
    for (var i = 0; i < trendBucketCount; i++) {
      final bucket = latencyBuckets[i];
      if (bucket.isEmpty) continue;
      averageLatency[i] = bucket.reduce((a, b) => a + b) / bucket.length;
      p95Latency[i] = _proxyOpsPercentile(bucket, 0.95).toDouble();
    }
    for (final bucket in telemetry) {
      final age =
          (trendEndKey - bucket.bucketAtMs) ~/ aiModelProxyTelemetryBucketMs;
      if (age < 0 || age >= trendBucketCount) continue;
      final index = trendBucketCount - age - 1;
      connections[index] = bucket.peakConnections.toDouble();
      ingressErrors[index] = bucket.ingressErrorCount.toDouble();
      inboundBytes[index] = bucket.inboundBytes.toDouble();
      outboundBytes[index] = bucket.outboundBytes.toDouble();
      if (bucket.recordedRequestCount <= 0) continue;
      final existingRequests = (success[index] + failure[index]).round();
      if (bucket.recordedRequestCount >= existingRequests) {
        success[index] = bucket.successCount.toDouble();
        failure[index] = bucket.failureCount.toDouble();
        tokens[index] = bucket.tokenCount.toDouble();
      }
      averageLatency[index] = bucket.averageDurationMs;
    }
    if (!usesHistoricalTrendWindow && connections.isNotEmpty) {
      connections.last = math.max(
        connections.last,
        controller.currentConnections.toDouble(),
      );
    }
    final sortedDurations = [...durations]..sort();
    return _ProxyOpsSnapshot(
      controller: controller,
      settings: settings,
      records: records,
      providerNames: providerNames,
      p50LatencyMs: _proxyOpsPercentileSorted(sortedDurations, 0.50),
      p95LatencyMs: _proxyOpsPercentileSorted(sortedDurations, 0.95),
      p99LatencyMs: _proxyOpsPercentileSorted(sortedDurations, 0.99),
      maxLatencyMs: sortedDurations.isEmpty ? 0 : sortedDurations.last,
      maxTokens: maxTokens,
      uniquePeerCount: peers.length,
      uniquePortCount: ports.length,
      trendSuccess: success,
      trendFailure: failure,
      averageLatencyBuckets: averageLatency,
      p95LatencyBuckets: p95Latency,
      tokenBuckets: tokens,
      connectionBuckets: connections,
      ingressErrorBuckets: ingressErrors,
      inboundByteBuckets: inboundBytes,
      outboundByteBuckets: outboundBytes,
      hourRequestCounts: [for (final hour in hourStats) hour.requests],
      hourPeerCounts: [for (final hour in hourStats) hour.peers.length],
      hourFailureCounts: [for (final hour in hourStats) hour.failures],
      hourStats: hourStats,
      trendEndAt: trendEndAt,
      usesHistoricalTrendWindow: usesHistoricalTrendWindow,
    );
  }

  final AiModelProxyController controller;
  final AiModelProxySettings settings;
  final List<AiModelProxyRequestRecord> records;
  final Map<String, String> providerNames;
  final int p50LatencyMs;
  final int p95LatencyMs;
  final int p99LatencyMs;
  final int maxLatencyMs;
  final int maxTokens;
  final int uniquePeerCount;
  final int uniquePortCount;
  final List<double> trendSuccess;
  final List<double> trendFailure;
  final List<double> averageLatencyBuckets;
  final List<double> p95LatencyBuckets;
  final List<double> tokenBuckets;
  final List<double> connectionBuckets;
  final List<double> ingressErrorBuckets;
  final List<double> inboundByteBuckets;
  final List<double> outboundByteBuckets;
  final List<int> hourRequestCounts;
  final List<int> hourPeerCounts;
  final List<int> hourFailureCounts;
  final List<_ProxyOpsGroupStat> hourStats;
  final DateTime trendEndAt;
  final bool usesHistoricalTrendWindow;

  int get requestTotal => settings.requestCount;
  int get successTotal => settings.successCount;
  int get failureTotal => settings.failureCount;
  double get successRate => requestTotal <= 0
      ? 0
      : (successTotal / requestTotal).clamp(0.0, 1.0).toDouble();
  double get failureRate => requestTotal <= 0
      ? 0
      : (failureTotal / requestTotal).clamp(0.0, 1.0).toDouble();
  String get successRateLabel => (successRate * 100).toStringAsFixed(1);
  String get failureRateLabel => (failureRate * 100).toStringAsFixed(1);
  String get endpoint => '${settings.listenHost}:${settings.listenPort}';
  int get currentRpm => trendSuccess.isEmpty
      ? 0
      : (trendSuccess.last + trendFailure.last).round();
  int get windowRequestCount {
    var total = 0;
    for (var i = _recentTrendStart; i < trendSuccess.length; i++) {
      total += trendSuccess[i].round();
      if (i < trendFailure.length) total += trendFailure[i].round();
    }
    return total;
  }

  int get enabledRouteCount =>
      settings.routes.where((route) => route.enabled).length;
  int get enabledBackendCount => settings.routes
      .expand((route) => route.backends)
      .where((backend) => backend.enabled)
      .length;
  int get avgTokensPerRequest => requestTotal <= 0
      ? 0
      : (settings.totalTokens / requestTotal).round().clamp(0, 1 << 31);

  List<double> get throughputBuckets => [
    for (var i = 0; i < trendSuccess.length; i++)
      trendSuccess[i] + (i < trendFailure.length ? trendFailure[i] : 0),
  ];

  int get _recentTrendStart =>
      math.max(0, trendSuccess.length - _kProxyOpsTrendBuckets);

  List<double> get recentThroughputBuckets =>
      throughputBuckets.skip(_recentTrendStart).toList(growable: false);

  List<double> get recentTrendSuccess =>
      trendSuccess.skip(_recentTrendStart).toList(growable: false);

  List<double> get recentTrendFailure =>
      trendFailure.skip(_recentTrendStart).toList(growable: false);

  List<double> get recentAverageLatencyBuckets =>
      averageLatencyBuckets.skip(_recentTrendStart).toList(growable: false);

  List<double> get recentP95LatencyBuckets =>
      p95LatencyBuckets.skip(_recentTrendStart).toList(growable: false);

  List<DateTime> get bucketMinutes {
    final endKey = aiModelProxyTelemetryBucketKey(trendEndAt);
    return [
      for (var i = 0; i < trendSuccess.length; i++)
        DateTime.fromMillisecondsSinceEpoch(
          endKey -
              (trendSuccess.length - i - 1) * aiModelProxyTelemetryBucketMs,
          isUtc: true,
        ).toLocal(),
    ];
  }

  List<DateTime> get recentBucketMinutes =>
      bucketMinutes.skip(_recentTrendStart).toList(growable: false);

  List<AiModelProxyRequestRecord> get recentFirst =>
      records.reversed.toList(growable: false);

  List<AiModelProxyRequestRecord> get windowRecords {
    final endKey = aiModelProxyTelemetryBucketKey(trendEndAt);
    final startKey =
        endKey - (_kProxyOpsTrendBuckets - 1) * aiModelProxyTelemetryBucketMs;
    final matches = <AiModelProxyRequestRecord>[];
    for (final record in records) {
      final key = aiModelProxyTelemetryBucketKey(record.startedAt);
      if (key >= startKey && key <= endKey) matches.add(record);
    }
    return matches;
  }

  Map<String, int> countBy(
    String Function(AiModelProxyRequestRecord record) keyOf, {
    required String unknown,
    Iterable<AiModelProxyRequestRecord>? source,
  }) {
    final counts = <String, int>{};
    for (final record in source ?? records) {
      final key = keyOf(record).trim();
      final normalized = key.isEmpty ? unknown : key;
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> sumBy(
    String Function(AiModelProxyRequestRecord record) keyOf,
    int Function(AiModelProxyRequestRecord record) amountOf, {
    required String unknown,
    Iterable<AiModelProxyRequestRecord>? source,
  }) {
    final totals = <String, int>{};
    for (final record in source ?? records) {
      final key = keyOf(record).trim();
      final normalized = key.isEmpty ? unknown : key;
      final amount = amountOf(record);
      if (amount <= 0) continue;
      totals[normalized] = (totals[normalized] ?? 0) + amount;
    }
    return totals;
  }

  List<_ProxyOpsGroupStat> groupBy(
    String Function(AiModelProxyRequestRecord record) keyOf, {
    required String unknown,
    Iterable<AiModelProxyRequestRecord>? source,
    bool Function(AiModelProxyRequestRecord record)? where,
  }) {
    final groups = <String, _ProxyOpsGroupStat>{};
    for (final record in source ?? records) {
      if (where != null && !where(record)) continue;
      final key = keyOf(record).trim();
      final normalized = key.isEmpty ? unknown : key;
      final group = groups.putIfAbsent(
        normalized,
        () => _ProxyOpsGroupStat(normalized),
      );
      _proxyOpsAccumulateRecord(group, record);
    }
    return groups.values.toList()
      ..sort((a, b) => b.requests.compareTo(a.requests));
  }

  String providerLabelFor(
    AiModelProxyRequestRecord record, {
    String unknown = '未知',
  }) {
    final providerId = record.providerId.trim();
    final configured = providerLabelForId(providerId);
    if (configured != null) return configured;
    final remoteHost = record.remoteHost.trim();
    if (remoteHost.isNotEmpty &&
        (providerId.isEmpty || RegExp(r'^\d+$').hasMatch(providerId))) {
      return remoteHost;
    }
    return providerId.isEmpty || RegExp(r'^\d+$').hasMatch(providerId)
        ? unknown
        : providerId;
  }

  String? providerLabelForId(String providerId) {
    final normalized = providerId.trim().toLowerCase();
    final configured = providerNames[normalized]?.trim();
    return configured?.isNotEmpty == true ? configured : null;
  }
}

String _providerDisplayName(AiModelConfig provider) {
  final name = provider.name.trim();
  if (name.isNotEmpty) return name;
  final modelName = provider.modelId.trim();
  if (modelName.isNotEmpty) return modelName;
  final host = Uri.tryParse(provider.baseUrl)?.host.trim();
  return host?.isNotEmpty == true ? host! : provider.id.trim();
}

({DateTime? earliest, DateTime? latest}) _proxyOpsRequestActivitySpan({
  required List<AiModelProxyRequestRecord> records,
  required List<AiModelProxyTelemetryBucket> telemetry,
  DateTime? lastRequestAt,
}) {
  DateTime? earliest;
  DateTime? latest;
  void consider(DateTime? value) {
    if (value == null) return;
    if (earliest == null || value.isBefore(earliest!)) earliest = value;
    if (latest == null || value.isAfter(latest!)) latest = value;
  }

  consider(lastRequestAt);
  for (final record in records) {
    consider(record.startedAt);
  }
  for (final bucket in telemetry) {
    if (bucket.recordedRequestCount <= 0) continue;
    consider(bucket.bucketAt);
  }
  return (earliest: earliest, latest: latest);
}

int _proxyOpsPercentile(List<int> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return _proxyOpsPercentileSorted(sorted, percentile);
}

int _proxyOpsPercentileSorted(List<int> sorted, double percentile) {
  if (sorted.isEmpty) return 0;
  final index = ((sorted.length - 1) * percentile.clamp(0.0, 1.0)).round();
  return sorted[index.clamp(0, sorted.length - 1)];
}

void _proxyOpsAccumulateRecord(
  _ProxyOpsGroupStat group,
  AiModelProxyRequestRecord record,
) {
  final statusRecord = isAiModelProxyStatusRecord(record);
  group.requests += 1;
  if (record.success) group.successes += 1;
  group.tokens += record.tokens;
  group.promptTokens += record.promptTokens;
  group.completionTokens += record.completionTokens;
  group.durationMs += record.durationMs;
  group.inboundBytes += record.inboundBytes;
  group.outboundBytes += record.outboundBytes;
  if (record.stream) group.streams += 1;
  if (record.attempt > 1) group.retries += 1;
  if (record.durationMs >= aiModelProxySlowLatencyMs) group.slowCount += 1;
  if (!statusRecord) {
    group.inferenceDurationMs += record.durationMs;
    group.inferenceDurations.add(record.durationMs);
    if (record.durationMs >= aiModelProxySlowLatencyMs) {
      group.inferenceSlowCount += 1;
    }
  }
  if (record.durationMs > group.maxMs) group.maxMs = record.durationMs;
  group.durations.add(record.durationMs);
  final peer = _proxyOpsRecordPeer(record);
  if (peer.isNotEmpty) group.peers.add(peer);
  if (group.lastAt == null || record.startedAt.isAfter(group.lastAt!)) {
    group.lastAt = record.startedAt;
  }
  final error = record.error?.trim() ?? '';
  if (error.isNotEmpty) {
    group.errors[error] = (group.errors[error] ?? 0) + 1;
  }
  final model = record.modelId.trim();
  if (model.isNotEmpty) {
    group.modelCounts[model] = (group.modelCounts[model] ?? 0) + 1;
  }
  if (statusRecord) {
    group.statusRequests += 1;
    if (record.success) group.statusSuccesses += 1;
  }
}

class _ProxyOpsGroupStat {
  _ProxyOpsGroupStat(this.label);

  final String label;
  int requests = 0;
  int successes = 0;
  int tokens = 0;
  int promptTokens = 0;
  int completionTokens = 0;
  int durationMs = 0;
  int maxMs = 0;
  int inboundBytes = 0;
  int outboundBytes = 0;
  int streams = 0;
  int slowCount = 0;
  int inferenceDurationMs = 0;
  int inferenceSlowCount = 0;
  int retries = 0;
  int statusRequests = 0;
  int statusSuccesses = 0;
  DateTime? lastAt;
  int inflight = 0;
  String userAgentFamily = '';
  final Set<String> peers = <String>{};
  final List<int> durations = <int>[];
  final List<int> inferenceDurations = <int>[];
  final Map<String, int> errors = <String, int>{};
  final Map<String, int> modelCounts = <String, int>{};

  int get failures => math.max(0, requests - successes);
  int get inferenceRequests => math.max(0, requests - statusRequests);
  int get inferenceSuccesses => math.max(0, successes - statusSuccesses);
  int get inferenceFailures =>
      math.max(0, inferenceRequests - inferenceSuccesses);
  int get avgMs => requests <= 0 ? 0 : (durationMs / requests).round();
  int get inferenceAvgMs => inferenceRequests <= 0
      ? 0
      : (inferenceDurationMs / inferenceRequests).round();
  int get avgTokens => requests <= 0 ? 0 : (tokens / requests).round();
  int get p95Ms => _proxyOpsPercentile(durations, 0.95);
  int get inferenceP95Ms => _proxyOpsPercentile(inferenceDurations, 0.95);
  double get successRate =>
      requests <= 0 ? 0 : (successes / requests).clamp(0.0, 1.0).toDouble();
  double get inferenceSuccessRate => inferenceRequests <= 0
      ? 0
      : (inferenceSuccesses / inferenceRequests).clamp(0.0, 1.0).toDouble();
}

String _proxyOpsRecordPeer(AiModelProxyRequestRecord record) {
  if (record.clientEndpoint.isNotEmpty) return record.clientEndpoint;
  return record.clientIp.trim();
}

String _proxyOpsPeerLabel(AiModelProxyRequestRecord record, String unknown) {
  final peer = _proxyOpsRecordPeer(record);
  return peer.isEmpty ? unknown : peer;
}

String _proxyOpsClientFamilyLabel(String userAgent, String unknown) {
  final ua = userAgent.trim();
  if (ua.isEmpty) return unknown;
  final family = _proxyOpsUserAgentFamily(ua);
  return family.isEmpty ? unknown : family;
}

List<_ProxyOpsGroupStat> _proxyOpsLiveAwareGroups({
  required List<_ProxyOpsGroupStat> groups,
  required Iterable<AiModelProxyLiveConnection> live,
  required String Function(AiModelProxyLiveConnection connection) keyOf,
  required String unknown,
  int unknownInflight = 0,
}) {
  final history = <String, _ProxyOpsGroupStat>{
    for (final group in groups) group.label: group,
  };
  final merged = <String, _ProxyOpsGroupStat>{};
  void absorb({
    required String label,
    required int inflight,
    String peer = '',
    String userAgent = '',
    DateTime? lastAt,
  }) {
    if (inflight <= 0) return;
    final key = label.trim().isEmpty ? unknown : label.trim();
    final group = merged.putIfAbsent(
      key,
      () => history[key] ?? _ProxyOpsGroupStat(key),
    );
    group.inflight = (group.inflight + inflight).clamp(0, 1 << 30).toInt();
    final endpoint = peer.trim();
    if (endpoint.isNotEmpty) group.peers.add(endpoint);
    if (userAgent.trim().isNotEmpty) {
      group.userAgentFamily = _proxyOpsUserAgentFamily(userAgent);
    }
    if (lastAt != null &&
        (group.lastAt == null || lastAt.isAfter(group.lastAt!))) {
      group.lastAt = lastAt;
    }
  }

  for (final connection in live) {
    absorb(
      label: keyOf(connection),
      inflight: connection.inflight,
      peer: connection.endpoint,
      userAgent: connection.userAgent,
      lastAt: connection.lastSeenAt,
    );
  }
  if (unknownInflight > 0) {
    absorb(label: unknown, inflight: unknownInflight);
  }
  return merged.values.toList()..sort((left, right) {
    final liveCmp = right.inflight.compareTo(left.inflight);
    if (liveCmp != 0) return liveCmp;
    final requestCmp = right.requests.compareTo(left.requests);
    if (requestCmp != 0) return requestCmp;
    final leftAt = left.lastAt;
    final rightAt = right.lastAt;
    if (leftAt == null && rightAt == null) {
      return left.label.compareTo(right.label);
    }
    if (leftAt == null) return 1;
    if (rightAt == null) return -1;
    return rightAt.compareTo(leftAt);
  });
}

String _proxyOpsUserAgentFamily(String value) {
  final normalized = value.toLowerCase();
  if (normalized.contains('claude')) return 'Claude Code';
  if (normalized.contains('chrome')) return 'Chrome';
  if (normalized.contains('firefox')) return 'Firefox';
  if (normalized.contains('safari')) return 'Safari';
  if (normalized.contains('curl')) return 'curl';
  if (normalized.contains('python')) return 'Python';
  if (normalized.contains('dart')) return 'Dart';
  return value.length > 36 ? '${value.substring(0, 36)}…' : value;
}

String _proxyOpsClientMixLabel(
  AiModelProxyRequestRecord record,
  String unknownProtocol,
) {
  final protocol = isAiModelProxyStatusRecord(record)
      ? openHandAmbientText(zh: '状态页', en: 'Status page')
      : aiModelProxyApiStyleLabel(record.apiStyle, openHandAmbientText);
  final userAgent = record.clientUserAgent.trim();
  if (protocol.isEmpty && userAgent.isEmpty) return unknownProtocol;
  if (userAgent.isEmpty) return protocol;
  if (protocol.isEmpty) return _proxyOpsUserAgentFamily(userAgent);
  return '$protocol · ${_proxyOpsUserAgentFamily(userAgent)}';
}

class _ProxyOpsHero extends StatelessWidget {
  const _ProxyOpsHero({
    required this.data,
    required this.lanHosts,
    required this.lanHostsReady,
  });

  final _ProxyOpsSnapshot data;
  final List<String> lanHosts;
  final bool lanHostsReady;

  Future<void> _openStatusPage(BuildContext context, String url) async {
    try {
      final opened = await openHttpUrlWithSystemBrowser(
        url,
        tag: 'ai_model_proxy_operations.open_status',
      );
      if (!context.mounted) return;
      final text = openHandTextResolver(context);
      if (opened) {
        showOpenHandInfoSnack(
          context,
          text(zh: '正在打开状态页：$url', en: 'Opening status page: $url'),
        );
      } else {
        showOpenHandErrorSnack(
          context,
          text(
            zh: '无法打开状态页，请检查系统默认浏览器设置。',
            en: 'Could not open the status page. Check the system default browser.',
          ),
        );
      }
    } catch (error, stack) {
      silentLog('ai_model_proxy_operations', '打开状态页', error, stack);
      if (!context.mounted) return;
      showOpenHandErrorSnack(
        context,
        openHandTextResolver(context)(
          zh: '打开状态页失败，请稍后重试。',
          en: 'Failed to open the status page. Try again later.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = openHandTextResolver(context);
    final running = data.controller.lifecycle == AiModelProxyLifecycle.running;
    final tone = running ? OpenHandStatusColors.success : cs.outline;
    final wildcardListen = isAiModelProxyWildcardListenHost(
      data.settings.listenHost,
    );
    final statusUrl = data.controller.publicStatusUrl;
    final boundPort = data.controller.boundPort ?? data.settings.listenPort;
    final lanStatusUrl = lanHosts.isEmpty
        ? ''
        : aiModelProxyStatusUrl(
            listenHost: lanHosts.first,
            listenPort: boundPort,
          );
    return _ProxyOpsPanel(
      title: text(zh: '服务控制台', en: 'Service console'),
      icon: running ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ProxyOpsChip(
                icon: running
                    ? Icons.check_circle_rounded
                    : Icons.pause_circle_outline_rounded,
                label: _lifecycleLabel(context, data.controller.lifecycle),
                color: tone,
                pulse: running,
              ),
              _ProxyOpsChip(
                icon: Icons.link_rounded,
                label: data.endpoint,
                color: cs.primary,
                monospace: true,
              ),
              _ProxyOpsChip(
                icon: Icons.schedule_rounded,
                color: cs.tertiary,
                labelChild: OpenHandLiveDuration(
                  startedAt: data.controller.startedAt,
                  running: running,
                  prefix: text(zh: '运行', en: 'Uptime'),
                ),
              ),
              _ProxyOpsChip(
                icon: data.settings.requireAuthentication
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
                label: data.settings.requireAuthentication
                    ? text(zh: 'API 鉴权已启用', en: 'API auth enabled')
                    : text(zh: '未启用鉴权', en: 'API auth disabled'),
                color: data.settings.requireAuthentication
                    ? cs.secondary
                    : cs.onSurfaceVariant,
              ),
              _ProxyOpsChip(
                icon: Icons.alt_route_rounded,
                label: aiModelProxySchedulingLabel(
                  data.settings.scheduling,
                  text,
                ),
                color: cs.primary,
              ),
              if (running)
                _ProxyOpsChip(
                  icon: Icons.public_rounded,
                  label: statusUrl,
                  color: cs.secondary,
                  monospace: true,
                  onTap: () => _openStatusPage(context, statusUrl),
                ),
              if (running && wildcardListen && lanHosts.isNotEmpty)
                _ProxyOpsChip(
                  icon: Icons.wifi_rounded,
                  label: text(zh: '局域网 $lanStatusUrl', en: 'LAN $lanStatusUrl'),
                  color: cs.tertiary,
                  monospace: true,
                  onTap: () => _openStatusPage(context, lanStatusUrl),
                ),
              if (running &&
                  wildcardListen &&
                  lanHostsReady &&
                  lanHosts.isEmpty)
                _ProxyOpsChip(
                  icon: Icons.warning_amber_rounded,
                  label: text(zh: '未发现局域网地址', en: 'No LAN address detected'),
                  color: Colors.amber.shade700,
                ),
            ],
          ),
          kOpenHandGap12,
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: const Color(0xff0b0d10),
              borderRadius: BorderRadius.circular(kOpenHandRadius12),
              border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OpenHandLiveConsoleLine(
                    prompt: 'OpenHand',
                    command: 'ai-model-proxy',
                    detail: 'endpoint=${data.endpoint}',
                    promptColor: OpenHandStatusColors.success,
                    commandColor: cs.tertiary,
                  ),
                  kOpenHandGap4,
                  OpenHandLiveConsoleLine(
                    prompt: 'state',
                    command: _lifecycleLabel(
                      context,
                      data.controller.lifecycle,
                    ),
                    detail:
                        'active=${data.controller.activeRequests} connections=${data.controller.currentConnections}',
                    promptColor: OpenHandStatusColors.success,
                    commandColor: cs.tertiary,
                  ),
                  kOpenHandGap4,
                  OpenHandLiveConsoleLine(
                    prompt: 'traffic',
                    command:
                        'in=${formatByteSize(data.controller.runtimeInboundBytes)}',
                    detail:
                        'out=${formatByteSize(data.controller.runtimeOutboundBytes)} avg=${data.settings.averageDurationMs.toStringAsFixed(0)}ms p95=${data.p95LatencyMs}ms',
                    promptColor: OpenHandStatusColors.success,
                    commandColor: cs.tertiary,
                  ),
                ],
              ),
            ),
          ),
          if (data.controller.errorMessage?.trim().isNotEmpty ?? false) ...[
            kOpenHandGap10,
            OpenHandLiveValue(
              data.controller.errorMessage!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProxyOpsMetricGrid extends StatelessWidget {
  const _ProxyOpsMetricGrid({required this.data});

  final _ProxyOpsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final cs = Theme.of(context).colorScheme;
    final metrics = <_ProxyOpsMetricData>[
      _ProxyOpsMetricData(
        Icons.link_rounded,
        text(zh: '活跃连接', en: 'Active connections'),
        '${data.controller.currentConnections}',
        text(zh: '当前占用入口', en: 'Occupying ingress'),
        cs.primary,
        insight: _ProxyOpsInsightKind.connections,
      ),
      _ProxyOpsMetricData(
        Icons.bolt_rounded,
        text(zh: '活跃请求', en: 'Active requests'),
        '${data.controller.activeRequests}',
        text(zh: '执行中', en: 'In flight'),
        cs.tertiary,
        insight: _ProxyOpsInsightKind.activeRequests,
      ),
      _ProxyOpsMetricData(
        Icons.call_made_rounded,
        text(zh: '请求总数', en: 'Requests'),
        '${data.requestTotal}',
        text(zh: '累计请求', en: 'Total'),
        cs.primary,
        insight: _ProxyOpsInsightKind.requests,
      ),
      _ProxyOpsMetricData(
        Icons.input_rounded,
        text(zh: '入口请求', en: 'Ingress requests'),
        '${data.controller.runtimeRequestCount}',
        text(zh: '本次运行', en: 'This run'),
        cs.secondary,
        insight: _ProxyOpsInsightKind.ingress,
      ),
      _ProxyOpsMetricData(
        Icons.task_alt_rounded,
        text(zh: '成功数量', en: 'Succeeded'),
        '${data.successTotal}',
        '${(data.successRate * 100).toStringAsFixed(1)}%',
        OpenHandStatusColors.success,
        insight: _ProxyOpsInsightKind.succeeded,
      ),
      _ProxyOpsMetricData(
        Icons.error_outline_rounded,
        text(zh: '失败数量', en: 'Failures'),
        '${data.failureTotal}',
        '${(data.failureRate * 100).toStringAsFixed(1)}%',
        cs.error,
        insight: _ProxyOpsInsightKind.failures,
      ),
      _ProxyOpsMetricData(
        Icons.report_problem_outlined,
        text(zh: '入口错误', en: 'Ingress errors'),
        '${data.controller.runtimeErrorCount}',
        text(zh: 'HTTP 4xx/5xx', en: 'HTTP 4xx/5xx'),
        cs.error,
        insight: _ProxyOpsInsightKind.ingressErrors,
      ),
      _ProxyOpsMetricData(
        Icons.speed_rounded,
        text(zh: '平均耗时', en: 'Avg latency'),
        '${data.settings.averageDurationMs.toStringAsFixed(0)} ms',
        text(zh: '已完成请求', en: 'Completed'),
        cs.secondary,
        insight: _ProxyOpsInsightKind.averageLatency,
      ),
      _ProxyOpsMetricData(
        Icons.timelapse_rounded,
        'P95',
        '${data.p95LatencyMs} ms',
        text(zh: '尾延迟', en: 'Tail latency'),
        cs.tertiary,
        insight: _ProxyOpsInsightKind.p95Latency,
      ),
      _ProxyOpsMetricData(
        Icons.token_rounded,
        text(zh: 'Token 总量', en: 'Tokens'),
        '${data.settings.totalTokens}',
        text(zh: '累计消耗', en: 'Consumed'),
        cs.primary,
        insight: _ProxyOpsInsightKind.tokens,
      ),
      _ProxyOpsMetricData(
        Icons.south_west_rounded,
        text(zh: '入口流量', en: 'Inbound'),
        formatByteSize(data.controller.runtimeInboundBytes),
        text(zh: '请求体', en: 'Request body'),
        cs.secondary,
        insight: _ProxyOpsInsightKind.inbound,
      ),
      _ProxyOpsMetricData(
        Icons.north_east_rounded,
        text(zh: '出口流量', en: 'Outbound'),
        formatByteSize(data.controller.runtimeOutboundBytes),
        text(zh: '响应体', en: 'Response body'),
        cs.tertiary,
        insight: _ProxyOpsInsightKind.outbound,
      ),
      _ProxyOpsMetricData(
        Icons.hub_rounded,
        text(zh: '启用模型', en: 'Exposed models'),
        '${data.settings.routes.where((route) => route.enabled).length}',
        text(zh: '对外暴露', en: 'Published'),
        cs.primary,
        insight: _ProxyOpsInsightKind.exposedModels,
      ),
      _ProxyOpsMetricData(
        Icons.storage_rounded,
        text(zh: '后备模型', en: 'Backends'),
        '${data.settings.routes.expand((route) => route.backends).where((backend) => backend.enabled).length}',
        text(zh: '启用后备', en: 'Enabled'),
        cs.secondary,
        insight: _ProxyOpsInsightKind.backends,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - _kProxyOpsGap * (columns - 1)) / columns;
        return Wrap(
          spacing: _kProxyOpsGap,
          runSpacing: _kProxyOpsGap,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: _ProxyOpsMetric(metric: metric),
              ),
          ],
        );
      },
    );
  }
}

class _ProxyOpsMetricData {
  const _ProxyOpsMetricData(
    this.icon,
    this.label,
    this.value,
    this.helper,
    this.color, {
    this.insight,
  });
  final IconData icon;
  final String label;
  final String value;
  final String helper;
  final Color color;
  final _ProxyOpsInsightKind? insight;
}

class _ProxyOpsMetric extends StatelessWidget {
  const _ProxyOpsMetric({required this.metric});
  final _ProxyOpsMetricData metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return OpenHandOpsPressScale(
      onTap: metric.insight == null
          ? null
          : () => _showProxyOpsInsight(context, metric.insight!),
      tone: metric.color,
      motionClearance: const EdgeInsets.all(kOpenHandOpsMotionClearance),
      child: AnimatedContainer(
        duration: openHandMotionDuration(context, kOpenHandMotion180),
        curve: kOpenHandSwitchInCurve,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.66),
          borderRadius: BorderRadius.circular(_kProxyOpsPanelRadius),
          border: Border.all(color: metric.color.withValues(alpha: 0.26)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: metric.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: metric.color.withValues(alpha: 0.22),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(metric.icon, size: 17, color: metric.color),
                ),
                kOpenHandHGap8,
                Expanded(
                  child: _ProxyOpsCopyText(
                    metric.label,
                    selectable: false,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (metric.insight != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: metric.color.withValues(alpha: 0.72),
                  ),
              ],
            ),
            kOpenHandGap8,
            OpenHandLiveValue(
              metric.value.trim().isEmpty ? '-' : metric.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            kOpenHandGap4,
            SizedBox(
              height: _kProxyOpsMetricHelperHeight,
              child: metric.helper.trim().isEmpty
                  ? null
                  : OpenHandLiveValue(
                      metric.helper.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: metric.color.withValues(alpha: 0.86),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProxyOpsTrendRow extends StatelessWidget {
  const _ProxyOpsTrendRow({required this.data});
  final _ProxyOpsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final panels = [
          _ProxyOpsTrendPanel(
            title: text(zh: '请求趋势', en: 'Request trend'),
            subtitle: text(
              zh: data.usesHistoricalTrendWindow
                  ? '默认最近 12 个采样桶 · 双指缩放回看'
                  : '默认最近 12 分钟 · 双指缩放回看',
              en: data.usesHistoricalTrendWindow
                  ? 'Latest 12 samples by default · pinch to review'
                  : 'Latest 12 minutes by default · pinch to review',
            ),
            series: [
              OpenHandChartSeries(
                label: text(zh: '成功', en: 'Success'),
                values: data.trendSuccess,
                aggregation: OpenHandTrendAggregation.sum,
                color: OpenHandStatusColors.success,
              ),
              OpenHandChartSeries(
                label: text(zh: '失败', en: 'Failure'),
                values: data.trendFailure,
                aggregation: OpenHandTrendAggregation.sum,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
            minutes: data.bucketMinutes,
            valueSuffix: '',
            insight: _ProxyOpsInsightKind.requestTrend,
          ),
          _ProxyOpsTrendPanel(
            title: text(zh: '耗时曲线', en: 'Latency curve'),
            subtitle: text(
              zh: data.usesHistoricalTrendWindow
                  ? '默认最近 12 个采样桶 · 双指缩放回看'
                  : '平均耗时与 P95 尾延迟 · 双指缩放回看',
              en: data.usesHistoricalTrendWindow
                  ? 'Latest 12 samples by default · pinch to review'
                  : 'Average and P95 tail latency · pinch to review',
            ),
            series: [
              OpenHandChartSeries(
                label: text(zh: '平均', en: 'Average'),
                values: data.averageLatencyBuckets,
                color: Theme.of(context).colorScheme.primary,
              ),
              OpenHandChartSeries(
                label: 'P95',
                values: data.p95LatencyBuckets,
                aggregation: OpenHandTrendAggregation.maximum,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ],
            minutes: data.bucketMinutes,
            valueSuffix: ' ms',
            insight: _ProxyOpsInsightKind.latencyTrend,
          ),
        ];
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              for (final panel in panels) ...[
                panel,
                const SizedBox(height: _kProxyOpsGap),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < panels.length; i++) ...[
              Expanded(child: panels[i]),
              if (i == 0) const SizedBox(width: _kProxyOpsGap),
            ],
          ],
        );
      },
    );
  }
}

class _ProxyOpsTrendPanel extends StatelessWidget {
  const _ProxyOpsTrendPanel({
    required this.title,
    required this.subtitle,
    required this.series,
    required this.minutes,
    required this.valueSuffix,
    this.insight,
  });
  final String title;
  final String subtitle;
  final List<OpenHandChartSeries> series;
  final List<DateTime> minutes;
  final String valueSuffix;
  final _ProxyOpsInsightKind? insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _ProxyOpsPanel(
      title: title,
      subtitle: subtitle,
      icon: Icons.show_chart_rounded,
      onTap: insight == null
          ? null
          : () => _showProxyOpsInsight(context, insight!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _kProxyOpsTrendChartHeight,
            child: OpenHandTrendZoomRegion(
              itemCount: series.fold<int>(
                minutes.length,
                (count, item) => math.max(count, item.values.length),
              ),
              sampleTimes: minutes,
              initialVisibleItemCount: _kProxyOpsTrendBuckets,
              semanticLabel: '$title，支持双指缩放',
              builder: (context, viewport) => RepaintBoundary(
                child: CustomPaint(
                  painter: OpenHandSmoothLineChartPainter(
                    series: viewport.sliceSeries(series),
                    gridColor: cs.outlineVariant.withValues(alpha: 0.5),
                    labelColor: cs.onSurfaceVariant,
                    emptyLabel: openHandTextResolver(context)(
                      zh: '等待请求样本',
                      en: 'Waiting for traffic',
                    ),
                    valueSuffix: valueSuffix,
                    textDirection: Directionality.of(context),
                    xLabels: [
                      for (final minute in viewport.slice(minutes))
                        formatHourMinuteLocal(minute),
                    ],
                  ),
                  size: Size.infinite,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          kOpenHandGap10,
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final item in series)
                _ProxyOpsLegend(label: item.label, color: item.color),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProxyOpsLegend extends StatelessWidget {
  const _ProxyOpsLegend({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        kOpenHandHGap6,
        _ProxyOpsCopyText(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ProxyOpsDistributionGrid extends StatelessWidget {
  const _ProxyOpsDistributionGrid({required this.data});
  final _ProxyOpsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final cs = Theme.of(context).colorScheme;
    final panels = [
      _ProxyOpsDistribution(
        title: text(zh: '状态分布', en: 'Status mix'),
        icon: Icons.donut_small_rounded,
        values: {
          text(zh: '成功', en: 'Success'): data.successTotal,
          text(zh: '失败', en: 'Failure'): data.failureTotal,
        },
        colors: [OpenHandStatusColors.success, cs.error],
        insight: _ProxyOpsInsightKind.statusMix,
      ),
      _ProxyOpsDistribution(
        title: text(zh: '提供商分布', en: 'Provider mix'),
        icon: Icons.hub_outlined,
        values: data.countBy(
          (item) => data.providerLabelFor(
            item,
            unknown: text(zh: '未知', en: 'Unknown'),
          ),
          unknown: text(zh: '未知', en: 'Unknown'),
        ),
        colors: [
          cs.primary,
          cs.tertiary,
          cs.secondary,
          OpenHandStatusColors.warning,
          cs.error,
        ],
        insight: _ProxyOpsInsightKind.providerMix,
      ),
      _ProxyOpsDistribution(
        title: text(zh: '模型分布', en: 'Model mix'),
        icon: Icons.model_training_outlined,
        values: data.countBy(
          (item) => item.modelId,
          unknown: text(zh: '未知', en: 'Unknown'),
        ),
        colors: [
          cs.tertiary,
          cs.primary,
          OpenHandStatusColors.success,
          cs.secondary,
          cs.error,
        ],
        insight: _ProxyOpsInsightKind.modelMix,
      ),
      _ProxyOpsDistribution(
        title: text(zh: '协议与客户端', en: 'Protocol and clients'),
        icon: Icons.devices_other_rounded,
        values: data.countBy(
          (item) => _proxyOpsClientMixLabel(
            item,
            text(zh: '未知协议', en: 'Unknown protocol'),
          ),
          unknown: text(zh: '未知', en: 'Unknown'),
        ),
        colors: [
          cs.secondary,
          cs.primary,
          cs.tertiary,
          OpenHandStatusColors.warning,
          cs.error,
        ],
        insight: _ProxyOpsInsightKind.clientMix,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        final width =
            (constraints.maxWidth - _kProxyOpsGap * (columns - 1)) / columns;
        return Wrap(
          spacing: _kProxyOpsGap,
          runSpacing: _kProxyOpsGap,
          children: [
            for (final panel in panels) SizedBox(width: width, child: panel),
          ],
        );
      },
    );
  }
}

class _ProxyOpsDistribution extends StatelessWidget {
  const _ProxyOpsDistribution({
    required this.title,
    required this.icon,
    required this.values,
    required this.colors,
    this.insight,
  });
  final String title;
  final IconData icon;
  final Map<String, int> values;
  final List<Color> colors;
  final _ProxyOpsInsightKind? insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sorted = values.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList(growable: false);
    final total = values.values.fold<int>(0, (sum, value) => sum + value);
    final palette = colors.isEmpty ? <Color>[cs.primary] : colors;
    return _ProxyOpsPanel(
      title: title,
      icon: icon,
      onTap: insight == null
          ? null
          : () => _showProxyOpsInsight(context, insight!),
      child: top.isEmpty
          ? Text(
              openHandTextResolver(context)(
                zh: '等待请求样本',
                en: 'Waiting for traffic',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          : Row(
              children: [
                SizedBox(
                  width: 112,
                  height: 112,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: OpenHandDonutChartPainter(
                        values: top
                            .map((entry) => entry.value)
                            .toList(growable: false),
                        colors: [
                          for (var index = 0; index < top.length; index++)
                            palette[index % palette.length],
                        ],
                        trackColor: cs.surfaceContainerHighest,
                      ),
                      child: Center(
                        child: OpenHandLiveValue(
                          '$total',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                kOpenHandHGap14,
                Expanded(
                  child: Column(
                    children: [
                      for (var index = 0; index < top.length; index++)
                        _ProxyOpsDistributionRow(
                          label: top[index].key,
                          value: top[index].value,
                          total: total,
                          color: palette[index % palette.length],
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ProxyOpsDistributionRow extends StatelessWidget {
  const _ProxyOpsDistributionRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });
  final String label;
  final int value;
  final int total;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ProxyOpsCopyText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
              OpenHandLiveValue(
                '$value',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          kOpenHandGap5,
          ClipRRect(
            borderRadius: kOpenHandPillBorderRadius,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio),
              duration: openHandMotionDuration(context, kOpenHandMotion420),
              curve: kOpenHandSwitchInCurve,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                color: color,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyOpsRecentRequests extends StatelessWidget {
  const _ProxyOpsRecentRequests({required this.data});
  final _ProxyOpsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final recent = data.records.reversed.toList(growable: false);
    return _ProxyOpsPanel(
      title: text(zh: '最近请求', en: 'Recent requests'),
      subtitle: text(
        zh: '时间、模型、协议、Token、客户端与调度路径，保留最近 200 条。',
        en: 'Time, model, protocol, tokens, client and routing for the last 200 calls.',
      ),
      icon: Icons.receipt_long_rounded,
      child: recent.isEmpty
          ? Text(
              text(zh: '暂无中转请求记录。', en: 'No proxy requests yet.'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : _proxyOpsTraceTable(
              context: context,
              data: data,
              records: recent,
              emptyLabel: text(zh: '暂无中转请求记录。', en: 'No proxy requests yet.'),
              showError: true,
            ),
    );
  }
}

BoxDecoration _proxyOpsCardDecoration(ColorScheme cs) => BoxDecoration(
  color: cs.surfaceContainerLow.withValues(alpha: 0.84),
  borderRadius: BorderRadius.circular(_kProxyOpsPanelRadius),
  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.62)),
  boxShadow: <BoxShadow>[
    BoxShadow(
      color: cs.shadow.withValues(alpha: 0.05),
      blurRadius: 18,
      offset: const Offset(0, 10),
    ),
  ],
);

class _ProxyOpsPanel extends StatelessWidget {
  const _ProxyOpsPanel({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.onTap,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final subtitleText = subtitle?.trim();
    final panel = AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion180),
      curve: kOpenHandSwitchInCurve,
      decoration: _proxyOpsCardDecoration(cs),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(kOpenHandRadius11),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Icon(icon, size: 19, color: cs.primary),
                ),
                kOpenHandHGap11,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProxyOpsCopyText(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitleText != null && subtitleText.isNotEmpty) ...[
                        kOpenHandGap3,
                        OpenHandLiveValue(
                          subtitleText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  kOpenHandHGap8,
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
            kOpenHandGap14,
            child,
          ],
        ),
      ),
    );
    final sized = SizedBox(width: double.infinity, child: panel);
    if (onTap == null) return sized;
    return OpenHandOpsPressScale(onTap: onTap, tone: cs.primary, child: sized);
  }
}

class _ProxyOpsChip extends StatelessWidget {
  const _ProxyOpsChip({
    required this.icon,
    required this.color,
    this.label = '',
    this.labelChild,
    this.monospace = false,
    this.pulse = false,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final Widget? labelChild;
  final Color color;
  final bool monospace;
  final bool pulse;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final duration = openHandMotionDuration(context, kOpenHandMotion180);
    final labelStyle = openHandOpsChipLabelStyle(
      context,
      color: color,
      monospace: monospace,
    );
    final chip = AnimatedContainer(
      duration: duration,
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.07),
          ],
        ),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pulse
              ? OpenHandLiveStatusDot(color: color, pulse: true, size: 10)
              : Icon(icon, size: 16, color: color),
          kOpenHandHGap6,
          DefaultTextStyle(
            style: labelStyle,
            child:
                labelChild ??
                OpenHandLiveValue(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return OpenHandOpsPressScale(
      onTap: onTap,
      tone: color,
      radius: 999,
      child: chip,
    );
  }
}

String _lifecycleLabel(BuildContext context, AiModelProxyLifecycle lifecycle) {
  final text = openHandTextResolver(context);
  return switch (lifecycle) {
    AiModelProxyLifecycle.running => text(zh: '运行中', en: 'Running'),
    AiModelProxyLifecycle.starting => text(zh: '启动中', en: 'Starting'),
    AiModelProxyLifecycle.stopping => text(zh: '停止中', en: 'Stopping'),
    AiModelProxyLifecycle.error => text(zh: '异常', en: 'Error'),
    AiModelProxyLifecycle.stopped => text(zh: '已停止', en: 'Stopped'),
  };
}

class _ProxyOpsInsightSpec {
  const _ProxyOpsInsightSpec({
    required this.icon,
    required this.title,
    required this.sections,
    this.subtitle = '',
    this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? tone;
  final _ProxyOpsInsightSections sections;
}

typedef _ProxyOpsInsightSections =
    List<Widget> Function(BuildContext context, _ProxyOpsSnapshot data);

class _ProxyOpsCopyText extends StatelessWidget {
  const _ProxyOpsCopyText(
    this.text, {
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.selectable = true,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: style,
    );
    return selectable ? SelectionArea(child: child) : child;
  }
}

class _ProxyOpsInsightDialog extends StatefulWidget {
  const _ProxyOpsInsightDialog({
    required this.icon,
    required this.title,
    required this.sections,
    this.subtitle = '',
    this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? tone;
  final _ProxyOpsInsightSections sections;

  @override
  State<_ProxyOpsInsightDialog> createState() => _ProxyOpsInsightDialogState();
}

class _ProxyOpsInsightDialogState extends State<_ProxyOpsInsightDialog> {
  final _ProxyOpsSnapshotHold _hold = _ProxyOpsSnapshotHold();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AiModelProxyController>();
    final providers = context.select<SettingsController, List<AiModelConfig>>(
      (settings) => settings.aiModels,
    );
    final data = _hold.resolve(controller, providers);
    final cs = Theme.of(context).colorScheme;
    final accent = widget.tone ?? cs.primary;
    final children = widget.sections(context, data);
    return OpenHandEscapeDismissScope(
      child: _buildProxyOpsSubDialog(
        context: context,
        maxWidth: _kProxyOpsInsightMaxWidth,
        maxHeight: _kProxyOpsInsightMaxHeight,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(kOpenHandRadius13),
                  border: Border.all(color: accent.withValues(alpha: 0.26)),
                ),
                child: Icon(widget.icon, color: accent),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProxyOpsCopyText(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (widget.subtitle.trim().isNotEmpty) ...[
                      kOpenHandGap3,
                      OpenHandLiveValue(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          kOpenHandGap14,
          Flexible(
            child: ListView(
              shrinkWrap: true,
              physics: openHandDialogAwareScrollPhysics(context),
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i != 0) const SizedBox(height: _kProxyOpsGap),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildProxyOpsSubDialog({
  required BuildContext context,
  required double maxWidth,
  double maxHeight = kOpenHandToolDialogDefaultMaxHeight,
  required List<Widget> children,
}) {
  return buildOpenHandResponsiveDialogShell(
    context: context,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    maxWidthFraction: _kProxyOpsSubDialogWidthFraction,
    maxHeightFraction: _kProxyOpsSubDialogHeightFraction,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_kProxyOpsOuterRadius),
    ),
    child: _ProxyOpsDialogSurface(
      child: _ProxyOpsConsoleShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

class _ProxyOpsDialogSurface extends StatelessWidget {
  const _ProxyOpsDialogSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(_kProxyOpsOuterRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.72)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.18),
            blurRadius: 38,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _ProxyOpsConsoleShell extends StatelessWidget {
  const _ProxyOpsConsoleShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion180),
      curve: kOpenHandSwitchInCurve,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(_kProxyOpsShellRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.74)),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _ProxyOpsInsightEmpty extends StatelessWidget {
  const _ProxyOpsInsightEmpty({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_rounded,
            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          kOpenHandGap8,
          _ProxyOpsCopyText(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyOpsStatPanel extends StatelessWidget {
  const _ProxyOpsStatPanel({
    required this.icon,
    required this.title,
    required this.tiles,
  });

  final IconData icon;
  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return _ProxyOpsPanel(
      icon: icon,
      title: title,
      child: _ProxyOpsInsightMetricGrid(children: tiles),
    );
  }
}

class _ProxyOpsInsightMetricGrid extends StatelessWidget {
  const _ProxyOpsInsightMetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final fit = !maxWidth.isFinite
            ? children.length
            : math.max(1, (maxWidth / _kProxyOpsMetricMinCellWidth).floor());
        final columns = math.max(1, math.min(fit, children.length));
        final rows = <Widget>[];
        for (var start = 0; start < children.length; start += columns) {
          final slice = children.sublist(
            start,
            math.min(start + columns, children.length),
          );
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: start == 0 ? 0 : _kProxyOpsGap),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < slice.length; i++) ...[
                      if (i != 0) const SizedBox(width: _kProxyOpsGap),
                      Expanded(child: slice[i]),
                    ],
                    for (var i = slice.length; i < columns; i++) ...[
                      const SizedBox(width: _kProxyOpsGap),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

/// 仅并排仪表、环图、柱图、热力等同级图卡。列表面板必须作为独立 section 独占一行。
Widget _proxyOpsPanelRow(List<Widget> children) {
  if (children.isEmpty) return const SizedBox.shrink();
  if (children.length == 1) return children.first;
  return LayoutBuilder(
    builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final pair =
          maxWidth.isFinite && maxWidth >= _kProxyOpsPanelPairBreakpoint;
      if (!pair) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i != 0) const SizedBox(height: _kProxyOpsGap),
              children[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i != 0) const SizedBox(width: _kProxyOpsGap),
            Expanded(child: children[i]),
          ],
        ],
      );
    },
  );
}

_ProxyOpsMetric _proxyOpsInsightTile(
  BuildContext context,
  IconData icon,
  String label,
  String value, {
  String helper = '',
  Color? color,
}) {
  return _ProxyOpsMetric(
    metric: _ProxyOpsMetricData(
      icon,
      label,
      value,
      helper,
      color ?? Theme.of(context).colorScheme.primary,
    ),
  );
}

List<Color> _proxyOpsChartPalette(ColorScheme cs) {
  return <Color>[
    cs.primary,
    cs.tertiary,
    OpenHandStatusColors.success,
    OpenHandStatusColors.warning,
    cs.error,
    cs.secondary,
  ];
}

class _ProxyOpsTrendDetailPanel extends StatelessWidget {
  const _ProxyOpsTrendDetailPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.series,
    required this.minutes,
    required this.emptyLabel,
    this.valueSuffix = '',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<OpenHandChartSeries> series;
  final List<DateTime> minutes;
  final String emptyLabel;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    return _ProxyOpsPanel(
      icon: icon,
      title: title,
      subtitle: subtitle,
      child: OpenHandTrendZoomRegion(
        itemCount: series.fold<int>(
          minutes.length,
          (count, item) => math.max(count, item.values.length),
        ),
        sampleTimes: minutes,
        initialVisibleItemCount: _kProxyOpsTrendBuckets,
        semanticLabel: '$title，支持双指缩放',
        builder: (context, viewport) {
          final visibleSeries = viewport.sliceSeries(series);
          final labels = [
            for (final minute in viewport.slice(minutes))
              formatHourMinuteLocal(minute),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OpenHandOperationalTrendChart(
                series: visibleSeries,
                valueSuffix: valueSuffix,
                xLabels: labels,
                emptyLabel: emptyLabel,
                area: true,
                showLegend: false,
                externalLegendProvided: true,
                onSelectionChanged: null,
              ),
              OpenHandOperationalTrendLanes(
                series: visibleSeries,
                xLabels: labels,
                valueSuffix: valueSuffix,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProxyOpsDetailSection extends StatelessWidget {
  const _ProxyOpsDetailSection({
    required this.title,
    required this.rows,
    this.icon = Icons.info_outline_rounded,
  });

  final String title;
  final Map<String, String> rows;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final visibleRows = rows.entries
        .where((row) => row.value.trim().isNotEmpty)
        .toList(growable: false);
    return _ProxyOpsPanel(
      icon: icon,
      title: title,
      child: visibleRows.isEmpty
          ? _ProxyOpsInsightEmpty(
              label: openHandTextResolver(context)(
                zh: '暂无明细',
                en: 'No details',
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in visibleRows.indexed)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: row.$1 == visibleRows.length - 1 ? 0 : 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 180,
                          child: _ProxyOpsCopyText(
                            row.$2.key,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        kOpenHandHGap12,
                        Expanded(
                          child: OpenHandLiveValue(
                            row.$2.value,
                            selectable: true,
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

String _proxyOpsRequestTitle(
  _ProxyOpsSnapshot data,
  AiModelProxyRequestRecord record,
  String unknown,
) {
  if (isAiModelProxyStatusRecord(record)) {
    return openHandAmbientText(zh: '状态页', en: 'Status page');
  }
  final title = [
    data.providerLabelFor(record, unknown: unknown),
    record.modelId,
  ].where((value) => value.trim().isNotEmpty).join(' / ');
  return title.isEmpty ? unknown : title;
}

String _proxyOpsModelGroupLabel(
  AiModelProxyRequestRecord record,
  String unknown,
) {
  if (isAiModelProxyStatusRecord(record)) {
    return openHandAmbientText(zh: '状态页', en: 'Status page');
  }
  final id = record.modelId.trim();
  return id.isEmpty ? unknown : id;
}

Widget _proxyOpsChartPanel({
  required IconData icon,
  required String title,
  required bool empty,
  required String emptyLabel,
  required Widget chart,
  String? subtitle,
}) {
  return _ProxyOpsPanel(
    icon: icon,
    title: title,
    subtitle: subtitle,
    child: empty ? _ProxyOpsInsightEmpty(label: emptyLabel) : chart,
  );
}

Widget _proxyOpsRankTablePanel({
  required IconData icon,
  required String title,
  required bool empty,
  required String emptyLabel,
  required List<String> headers,
  required List<OpenHandOperationalRankRow> rows,
  bool sortByValue = true,
}) {
  return _proxyOpsChartPanel(
    icon: icon,
    title: title,
    empty: empty,
    emptyLabel: emptyLabel,
    chart: OpenHandOperationalRankTable(
      sortByValue: sortByValue,
      emptyLabel: emptyLabel,
      headers: headers,
      rows: rows,
    ),
  );
}

OpenHandOperationalMeter _proxyOpsCountMeter({
  required String label,
  required num value,
  required num maximum,
  required Color color,
  String? helper,
  bool semicircular = false,
}) {
  final cap = math.max(maximum.toDouble(), math.max(value.toDouble(), 1));
  return OpenHandOperationalMeter(
    label: label,
    value: value,
    maximum: cap,
    color: color,
    valueLabel: '${value.round()}',
    helper: helper,
    semicircular: semicircular,
    gaugeSize: _kProxyOpsGaugeSize,
  );
}

OpenHandOperationalMeter _proxyOpsRateMeter({
  required String label,
  required double rate,
  required Color color,
  String? helper,
  bool unavailable = false,
}) {
  final safe = rate.isFinite ? rate.clamp(0.0, 1.0).toDouble() : 0.0;
  return OpenHandOperationalMeter(
    label: label,
    value: safe,
    color: color,
    valueLabel: unavailable ? '--' : '${(safe * 100).toStringAsFixed(1)}%',
    helper: helper,
    unavailable: unavailable,
    semicircular: false,
    gaugeSize: _kProxyOpsGaugeSize,
  );
}

Color _proxyOpsHealthColor(ColorScheme cs, double rate) {
  if (rate >= 0.9) return OpenHandStatusColors.success;
  if (rate >= 0.7) return OpenHandStatusColors.warning;
  return cs.error;
}

List<OpenHandChartSegment> _proxyOpsSegments(
  Map<String, int> values,
  List<Color> palette,
) {
  final sorted = values.entries.where((entry) => entry.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (var i = 0; i < sorted.length; i++)
      OpenHandChartSegment(
        label: sorted[i].key,
        value: sorted[i].value,
        color: palette[i % palette.length],
        valueLabel: '${sorted[i].value}',
      ),
  ];
}

String _proxyOpsPercentLabel(double rate) =>
    '${(rate * 100).toStringAsFixed(1)}%';

String _proxyOpsDurationLabel(int ms) {
  if (ms <= 0) return kOpenHandTableMetricEmpty;
  return openHandTableMetricDuration(ms);
}

OpenHandTokenMetricCell _proxyOpsTokenMetric({
  required int total,
  int promptTokens = 0,
  int completionTokens = 0,
}) {
  return OpenHandTokenMetricCell(
    total: total,
    promptTokens: promptTokens,
    completionTokens: completionTokens,
  );
}

OpenHandDurationMetricCell _proxyOpsDurationMetric(int ms) {
  return OpenHandDurationMetricCell(durationMs: ms <= 0 ? null : ms);
}

OpenHandTableStatusBadge _proxyOpsRequestStatusBadge(
  BuildContext context,
  AiModelProxyRequestRecord record,
) {
  final text = openHandTextResolver(context);
  final label = record.success
      ? text(zh: '成功', en: 'OK')
      : text(zh: '失败', en: 'Fail');
  return OpenHandTableStatusBadge(
    label: label,
    color: record.success
        ? OpenHandStatusColors.success
        : OpenHandStatusColors.error,
    tooltip: [
      label,
      if (record.statusCode > 0) '${record.statusCode}',
      if (record.error != null && record.error!.trim().isNotEmpty)
        record.error!.trim(),
    ].join(' · '),
  );
}

OpenHandTableStatusBadge _proxyOpsEnablementBadge(
  BuildContext context, {
  required bool enabled,
}) {
  final colors = Theme.of(context).colorScheme;
  final text = openHandTextResolver(context);
  return OpenHandTableStatusBadge(
    label: enabled ? text(zh: '启用', en: 'On') : text(zh: '停用', en: 'Off'),
    color: enabled ? OpenHandStatusColors.success : colors.onSurfaceVariant,
  );
}

OpenHandOperationalRankRow _proxyOpsExposedModelRankRow({
  required BuildContext context,
  required AiModelProxyRoute route,
  required Map<String, _ProxyOpsGroupStat> usageByExposed,
}) {
  final text = openHandTextResolver(context);
  final usage = usageByExposed[route.exposedModel];
  final lastAt = usage?.lastAt;
  return OpenHandOperationalRankRow(
    subtitle: text(
      zh: '${route.backends.where((backend) => backend.enabled).length} 个启用后备',
      en: '${route.backends.where((backend) => backend.enabled).length} enabled backends',
    ),
    cells: [
      route.exposedModel,
      route.enabled ? text(zh: '启用', en: 'On') : text(zh: '停用', en: 'Off'),
      '${route.backends.length}',
      '${usage?.requests ?? 0}',
      usage == null
          ? kOpenHandTableMetricEmpty
          : _proxyOpsPercentLabel(usage.successRate),
      openHandTableMetricInteger(usage?.tokens ?? 0),
      usage == null
          ? kOpenHandTableMetricEmpty
          : _proxyOpsDurationLabel(usage.avgMs),
      lastAt == null ? kOpenHandTableMetricEmpty : formatListDateTime(lastAt),
    ],
    cellWidgets: [
      null,
      _proxyOpsEnablementBadge(context, enabled: route.enabled),
      null,
      null,
      null,
      _proxyOpsTokenMetric(
        total: usage?.tokens ?? 0,
        promptTokens: usage?.promptTokens ?? 0,
        completionTokens: usage?.completionTokens ?? 0,
      ),
      _proxyOpsDurationMetric(usage?.avgMs ?? 0),
      null,
    ],
    value: usage?.requests ?? 0,
  );
}

OpenHandOperationalRankRow _proxyOpsBackendRankRow({
  required BuildContext context,
  required _ProxyOpsSnapshot data,
  required AiModelProxyRoute route,
  required AiModelProxyBackend backend,
  required Map<String, _ProxyOpsGroupStat> usageByBackend,
}) {
  final text = openHandTextResolver(context);
  final usage =
      usageByBackend['${backend.providerId.trim()}\u0000${backend.modelId.trim()}'];
  final lastAt = usage?.lastAt;
  return OpenHandOperationalRankRow(
    subtitle: data.providerLabelForId(backend.providerId) ?? backend.providerId,
    cells: [
      backend.modelId,
      route.exposedModel,
      route.enabled && backend.enabled
          ? text(zh: '启用', en: 'On')
          : text(zh: '停用', en: 'Off'),
      '${usage?.requests ?? 0}',
      usage == null
          ? kOpenHandTableMetricEmpty
          : _proxyOpsPercentLabel(usage.successRate),
      openHandTableMetricInteger(usage?.tokens ?? 0),
      usage == null
          ? kOpenHandTableMetricEmpty
          : _proxyOpsDurationLabel(usage.avgMs),
      lastAt == null ? kOpenHandTableMetricEmpty : formatListDateTime(lastAt),
    ],
    cellWidgets: [
      null,
      null,
      _proxyOpsEnablementBadge(
        context,
        enabled: route.enabled && backend.enabled,
      ),
      null,
      null,
      _proxyOpsTokenMetric(
        total: usage?.tokens ?? 0,
        promptTokens: usage?.promptTokens ?? 0,
        completionTokens: usage?.completionTokens ?? 0,
      ),
      _proxyOpsDurationMetric(usage?.avgMs ?? 0),
      null,
    ],
    value: usage?.requests ?? 0,
  );
}

OpenHandOperationalRankTable _proxyOpsGroupTable({
  required BuildContext context,
  required List<_ProxyOpsGroupStat> groups,
  required String leadingHeader,
  required String emptyLabel,
  num Function(_ProxyOpsGroupStat group)? valueOf,
  double? maxBodyHeight,
  bool sortByValue = true,
}) {
  final text = openHandTextResolver(context);
  return OpenHandOperationalRankTable(
    sortByValue: sortByValue,
    emptyLabel: emptyLabel,
    maxBodyHeight: maxBodyHeight ?? _kProxyOpsRankBodyMaxHeight,
    headers: [
      leadingHeader,
      text(zh: '请求', en: 'Requests'),
      text(zh: '成功', en: 'OK'),
      text(zh: '失败', en: 'Fail'),
      text(zh: '成功率', en: 'Success'),
      'Token',
      text(zh: '均耗时', en: 'Avg'),
      'P95',
      text(zh: '对端', en: 'Peers'),
      text(zh: '最近', en: 'Latest'),
    ],
    rows: [
      for (final group in groups)
        OpenHandOperationalRankRow(
          subtitle: [
            if (group.inflight > 0)
              text(zh: '在线 ${group.inflight}', en: 'Live ${group.inflight}'),
            if (group.userAgentFamily.isNotEmpty &&
                group.userAgentFamily != group.label)
              group.userAgentFamily,
            if (group.avgTokens > 0) '单均 ${group.avgTokens}',
            if (group.streams > 0) '流式 ${group.streams}',
            if (group.inboundBytes + group.outboundBytes > 0)
              '${formatByteSize(group.inboundBytes)} → ${formatByteSize(group.outboundBytes)}',
          ].join(' · '),
          cells: [
            group.label,
            '${group.requests}',
            '${group.successes}',
            '${group.failures}',
            _proxyOpsPercentLabel(group.successRate),
            openHandTableMetricInteger(group.tokens),
            _proxyOpsDurationLabel(group.avgMs),
            _proxyOpsDurationLabel(group.p95Ms),
            '${group.peers.length}',
            group.lastAt == null
                ? kOpenHandTableMetricEmpty
                : formatListDateTime(group.lastAt!),
          ],
          cellWidgets: [
            null,
            null,
            null,
            null,
            null,
            _proxyOpsTokenMetric(
              total: group.tokens,
              promptTokens: group.promptTokens,
              completionTokens: group.completionTokens,
            ),
            _proxyOpsDurationMetric(group.avgMs),
            _proxyOpsDurationMetric(group.p95Ms),
            null,
            null,
          ],
          value: valueOf?.call(group) ?? group.requests,
        ),
    ],
  );
}

Widget _proxyOpsGroupTablePanel({
  required BuildContext context,
  required IconData icon,
  required String title,
  required List<_ProxyOpsGroupStat> groups,
  required String leadingHeader,
  required String emptyLabel,
  String? subtitle,
  num Function(_ProxyOpsGroupStat group)? valueOf,
  double? maxBodyHeight,
  bool sortByValue = true,
}) {
  return _proxyOpsChartPanel(
    icon: icon,
    title: title,
    subtitle: subtitle,
    empty: groups.isEmpty,
    emptyLabel: emptyLabel,
    chart: _proxyOpsGroupTable(
      context: context,
      groups: groups,
      leadingHeader: leadingHeader,
      emptyLabel: emptyLabel,
      valueOf: valueOf,
      maxBodyHeight: maxBodyHeight,
      sortByValue: sortByValue,
    ),
  );
}

OpenHandOperationalRankTable _proxyOpsTraceTable({
  required BuildContext context,
  required _ProxyOpsSnapshot data,
  required List<AiModelProxyRequestRecord> records,
  required String emptyLabel,
  bool showError = false,
}) {
  final text = openHandTextResolver(context);
  final unknown = text(zh: '未知', en: 'Unknown');
  return OpenHandOperationalRankTable(
    sortByValue: false,
    emptyLabel: emptyLabel,
    headers: [
      text(zh: '时间', en: 'Time'),
      text(zh: '模型', en: 'Model'),
      text(zh: '源地址', en: 'Source'),
      text(zh: '协议', en: 'Protocol'),
      'Token',
      text(zh: '耗时', en: 'Latency'),
      text(zh: '客户端 UA', en: 'Client UA'),
      text(zh: '客户端环境', en: 'Client env'),
      text(zh: '调度', en: 'Route'),
      text(zh: '状态', en: 'Status'),
      if (showError) text(zh: '原因', en: 'Reason'),
    ],
    rows: [
      for (final record in records)
        OpenHandOperationalRankRow(
          subtitle: [
            if (record.requestPath.trim().isNotEmpty) record.requestPath.trim(),
            if (record.stream) text(zh: '流式', en: 'Stream'),
            if (record.attempt > 1) '#${record.attempt}',
          ].join(' · '),
          cells: [
            formatListDateTime(record.startedAt),
            _proxyOpsRequestTitle(data, record, unknown),
            record.clientEndpoint.isEmpty ? unknown : record.clientEndpoint,
            [
              if (record.apiStyle.trim().isNotEmpty)
                aiModelProxyApiStyleLabel(record.apiStyle, text),
              if (record.exposedModel.trim().isNotEmpty)
                record.exposedModel.trim(),
            ].join(' · '),
            openHandTableMetricInteger(record.tokens),
            _proxyOpsDurationLabel(record.durationMs),
            _proxyOpsUserAgentFamily(
              record.clientUserAgent.trim().isEmpty
                  ? unknown
                  : record.clientUserAgent,
            ),
            [
              if (record.clientProcessName.trim().isNotEmpty)
                record.clientProcessName.trim(),
              if (record.clientProcessId.trim().isNotEmpty)
                'PID ${record.clientProcessId.trim()}',
              if (record.clientServiceName.trim().isNotEmpty)
                record.clientServiceName.trim(),
              if (record.clientMacAddress.trim().isNotEmpty)
                record.clientMacAddress.trim(),
            ].join(' · '),
            [
              if (record.proxyMode.trim().isNotEmpty)
                aiModelProxyDispatchModeLabel(record.proxyMode, text),
              if (record.remoteHost.trim().isNotEmpty)
                _proxyOpsUpstreamEndpoint(record, unknown),
            ].join(' · '),
            [
              record.success
                  ? text(zh: '成功', en: 'OK')
                  : text(zh: '失败', en: 'Fail'),
              if (record.statusCode > 0) '${record.statusCode}',
            ].join(' '),
            if (showError)
              (record.error?.trim().isEmpty ?? true)
                  ? kOpenHandTableMetricEmpty
                  : record.error!.trim(),
          ],
          cellWidgets: [
            null,
            OpenHandTableStackedCell(
              primary: isAiModelProxyStatusRecord(record)
                  ? openHandAmbientText(zh: '状态页', en: 'Status page')
                  : (record.modelId.trim().isEmpty
                        ? unknown
                        : record.modelId.trim()),
              secondary: isAiModelProxyStatusRecord(record)
                  ? ''
                  : data.providerLabelFor(record, unknown: unknown),
            ),
            OpenHandTableStackedCell(
              primary: record.clientEndpoint.isEmpty
                  ? unknown
                  : record.clientEndpoint,
              secondary: _proxyOpsUserAgentFamily(
                record.clientUserAgent.trim().isEmpty
                    ? unknown
                    : record.clientUserAgent,
              ),
              alignEnd: true,
            ),
            OpenHandTableStackedCell(
              primary: record.apiStyle.trim().isEmpty
                  ? kOpenHandTableMetricEmpty
                  : aiModelProxyApiStyleLabel(record.apiStyle, text),
              secondary: record.exposedModel.trim(),
            ),
            _proxyOpsTokenMetric(
              total: record.tokens,
              promptTokens: record.promptTokens,
              completionTokens: record.completionTokens,
            ),
            _proxyOpsDurationMetric(record.durationMs),
            OpenHandTableStackedCell(
              primary: _proxyOpsUserAgentFamily(
                record.clientUserAgent.trim().isEmpty
                    ? unknown
                    : record.clientUserAgent,
              ),
              secondary: record.clientUserAgent.trim(),
              alignEnd: true,
            ),
            OpenHandTableStackedCell(
              primary: record.clientProcessName.trim().isEmpty
                  ? unknown
                  : record.clientProcessName.trim(),
              secondary: [
                if (record.clientProcessId.trim().isNotEmpty)
                  'PID ${record.clientProcessId.trim()}',
                if (record.clientServiceName.trim().isNotEmpty)
                  record.clientServiceName.trim(),
                if (record.clientMacAddress.trim().isNotEmpty)
                  record.clientMacAddress.trim(),
              ].join(' · '),
              alignEnd: true,
            ),
            OpenHandTableStackedCell(
              primary: record.proxyMode.trim().isEmpty
                  ? kOpenHandTableMetricEmpty
                  : aiModelProxyDispatchModeLabel(record.proxyMode, text),
              secondary: record.remoteHost.trim().isEmpty
                  ? ''
                  : _proxyOpsUpstreamEndpoint(record, unknown),
              alignEnd: true,
            ),
            _proxyOpsRequestStatusBadge(context, record),
            if (showError) null,
          ],
          value: record.durationMs,
        ),
    ],
  );
}

enum _ProxyOpsServiceHealth { idle, healthy, warning, degraded, outage }

String _proxyOpsHourRangeLabel(int hour) {
  final safe = hour.clamp(0, _kProxyOpsHourBuckets - 1);
  final next = (safe + 1) % _kProxyOpsHourBuckets;
  return '${twoDigit(safe)}:00 – ${twoDigit(next)}:00';
}

String? _proxyOpsTopCountLabel(Map<String, int> counts) {
  MapEntry<String, int>? top;
  for (final entry in counts.entries) {
    if (top == null || entry.value > top.value) top = entry;
  }
  return top?.key;
}

_ProxyOpsServiceHealth _proxyOpsHourHealth(_ProxyOpsGroupStat hour) {
  if (hour.inferenceRequests <= 0) {
    return _ProxyOpsServiceHealth.idle;
  }
  return switch (classifyAiModelProxyHealth(
    requests: hour.inferenceRequests,
    successes: hour.inferenceSuccesses,
    slowCount: hour.inferenceSlowCount,
    p95Ms: hour.inferenceP95Ms,
  )) {
    AiModelProxyHealth.idle => _ProxyOpsServiceHealth.idle,
    AiModelProxyHealth.healthy => _ProxyOpsServiceHealth.healthy,
    AiModelProxyHealth.warning => _ProxyOpsServiceHealth.warning,
    AiModelProxyHealth.degraded => _ProxyOpsServiceHealth.degraded,
    AiModelProxyHealth.outage => _ProxyOpsServiceHealth.outage,
  };
}

_ProxyOpsServiceHealth _proxyOpsOverallHealth(List<_ProxyOpsGroupStat> hours) {
  var seenTraffic = false;
  var seenWarning = false;
  var seenDegraded = false;
  for (final hour in hours) {
    switch (_proxyOpsHourHealth(hour)) {
      case _ProxyOpsServiceHealth.outage:
        return _ProxyOpsServiceHealth.outage;
      case _ProxyOpsServiceHealth.degraded:
        seenDegraded = true;
        seenTraffic = true;
      case _ProxyOpsServiceHealth.warning:
        seenWarning = true;
        seenTraffic = true;
      case _ProxyOpsServiceHealth.healthy:
        seenTraffic = true;
      case _ProxyOpsServiceHealth.idle:
        break;
    }
  }
  if (seenDegraded) return _ProxyOpsServiceHealth.degraded;
  if (seenWarning) return _ProxyOpsServiceHealth.warning;
  if (seenTraffic) return _ProxyOpsServiceHealth.healthy;
  return _ProxyOpsServiceHealth.idle;
}

Color _proxyOpsServiceHealthColor(
  ColorScheme cs,
  _ProxyOpsServiceHealth health,
) {
  return switch (health) {
    _ProxyOpsServiceHealth.idle => cs.onSurfaceVariant,
    _ProxyOpsServiceHealth.healthy => OpenHandStatusColors.success,
    _ProxyOpsServiceHealth.warning => OpenHandStatusColors.caution,
    _ProxyOpsServiceHealth.degraded => OpenHandStatusColors.warning,
    _ProxyOpsServiceHealth.outage => OpenHandStatusColors.error,
  };
}

String _proxyOpsServiceHealthLabel(
  OpenHandLocalizedTextResolver text,
  _ProxyOpsServiceHealth health,
) {
  return switch (health) {
    _ProxyOpsServiceHealth.idle => text(zh: '空闲待命', en: 'Idle'),
    _ProxyOpsServiceHealth.healthy => text(zh: '正常运行', en: 'Operational'),
    _ProxyOpsServiceHealth.warning => text(zh: '轻微波动', en: 'Minor disruption'),
    _ProxyOpsServiceHealth.degraded => text(zh: '服务降级', en: 'Degraded'),
    _ProxyOpsServiceHealth.outage => text(zh: '服务中断', en: 'Outage'),
  };
}

List<OpenHandChartTooltipMetric> _proxyOpsHourTooltipMetrics({
  required OpenHandLocalizedTextResolver text,
  required _ProxyOpsGroupStat hour,
  required Color tone,
  int dayRequests = 0,
  bool inferenceOnly = false,
}) {
  final requests = inferenceOnly ? hour.inferenceRequests : hour.requests;
  final successes = inferenceOnly ? hour.inferenceSuccesses : hour.successes;
  final failures = inferenceOnly ? hour.inferenceFailures : hour.failures;
  final successRate = inferenceOnly
      ? hour.inferenceSuccessRate
      : hour.successRate;
  final averageMs = inferenceOnly ? hour.inferenceAvgMs : hour.avgMs;
  final p95Ms = inferenceOnly ? hour.inferenceP95Ms : hour.p95Ms;
  final slowCount = inferenceOnly ? hour.inferenceSlowCount : hour.slowCount;
  final share = dayRequests <= 0 || requests <= 0
      ? null
      : text(
          zh: '占近窗样本 ${_proxyOpsPercentLabel(requests / dayRequests)}',
          en: '${_proxyOpsPercentLabel(requests / dayRequests)} of samples',
        );
  final topModel = _proxyOpsTopCountLabel(hour.modelCounts);
  return [
    OpenHandChartTooltipMetric(
      label: text(zh: '请求次数', en: 'Requests'),
      value: '$requests',
      hint: share,
      icon: Icons.call_made_rounded,
      color: tone,
    ),
    OpenHandChartTooltipMetric(
      label: text(zh: '成功率', en: 'Success'),
      value: requests <= 0 ? '—' : _proxyOpsPercentLabel(successRate),
      hint: '$successes / $requests',
      icon: Icons.verified_rounded,
      color: OpenHandStatusColors.success,
    ),
    OpenHandChartTooltipMetric(
      label: text(zh: '失败次数', en: 'Failures'),
      value: '$failures',
      hint: failures <= 0
          ? text(zh: '该时段无失败', en: 'No failures')
          : _proxyOpsTopCountLabel(hour.errors),
      icon: Icons.error_outline_rounded,
      color: failures > 0
          ? OpenHandStatusColors.error
          : OpenHandStatusColors.success,
    ),
    OpenHandChartTooltipMetric(
      label: text(zh: '平均耗时', en: 'Avg latency'),
      value: _proxyOpsDurationLabel(averageMs),
      icon: Icons.timer_outlined,
      color: tone,
    ),
    OpenHandChartTooltipMetric(
      label: 'P95',
      value: _proxyOpsDurationLabel(p95Ms),
      hint: text(zh: '尾延迟', en: 'Tail latency'),
      icon: Icons.speed_rounded,
      color: p95Ms >= _kProxyOpsSlowLatencyMs
          ? OpenHandStatusColors.warning
          : tone,
    ),
    OpenHandChartTooltipMetric(
      label: text(zh: '慢请求', en: 'Slow calls'),
      value: '$slowCount',
      hint: text(zh: '耗时 ≥ 3s', en: 'Latency ≥ 3s'),
      icon: Icons.hourglass_bottom_rounded,
      color: slowCount > 0 ? OpenHandStatusColors.warning : tone,
    ),
    OpenHandChartTooltipMetric(
      label: 'Token',
      value: '${hour.tokens}',
      hint: hour.avgTokens <= 0
          ? null
          : text(zh: '单均 ${hour.avgTokens}', en: 'Avg ${hour.avgTokens}'),
      icon: Icons.token_rounded,
      color: tone,
    ),
    OpenHandChartTooltipMetric(
      label: text(zh: '独立对端', en: 'Peers'),
      value: '${hour.peers.length}',
      hint: topModel == null
          ? null
          : text(zh: '主模型 $topModel', en: 'Top model $topModel'),
      icon: Icons.devices_rounded,
      color: tone,
    ),
  ];
}

OpenHandChartTooltip _proxyOpsHourVolumeTooltip({
  required OpenHandLocalizedTextResolver text,
  required _ProxyOpsGroupStat hour,
  required Color tone,
  required String subtitle,
  required String summary,
  required List<String> notes,
  String? badge,
  int dayRequests = 0,
}) {
  final hourIndex = int.tryParse(hour.label) ?? 0;
  return OpenHandChartTooltip(
    title: _proxyOpsHourRangeLabel(hourIndex),
    subtitle: subtitle,
    badge: badge ?? '${hour.requests}',
    badgeColor: tone,
    summary: summary,
    metrics: [
      ..._proxyOpsHourTooltipMetrics(
        text: text,
        hour: hour,
        tone: tone,
        dayRequests: dayRequests,
      ),
      if (hour.lastAt != null)
        OpenHandChartTooltipMetric(
          label: text(zh: '最近请求', en: 'Latest'),
          value: formatListDateTime(hour.lastAt!),
          icon: Icons.schedule_rounded,
          color: tone,
        ),
    ],
    notes: notes,
  );
}

List<OpenHandChartSegment> _proxyOpsHourSegments(
  List<_ProxyOpsGroupStat> hours,
  Color color, {
  required num Function(_ProxyOpsGroupStat hour) valueOf,
  required String Function(_ProxyOpsGroupStat hour) valueLabelOf,
  required OpenHandChartTooltip Function(_ProxyOpsGroupStat hour) tooltipOf,
}) {
  return [
    for (final hour in hours)
      OpenHandChartSegment(
        label: hour.label,
        value: valueOf(hour),
        color: color,
        valueLabel: valueLabelOf(hour),
        tooltip: tooltipOf(hour),
      ),
  ];
}

Widget _proxyOpsServiceHealthPanel(
  BuildContext context,
  _ProxyOpsSnapshot data,
) {
  final text = openHandTextResolver(context);
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final overall = _proxyOpsOverallHealth(data.hourStats);
  final tone = _proxyOpsServiceHealthColor(cs, overall);
  final toneForeground = overall == _ProxyOpsServiceHealth.warning
      ? (Color.lerp(tone, cs.onSurface, 0.36) ?? tone)
      : tone;
  final inferenceRequests = data.records
      .where((record) => !isAiModelProxyStatusRecord(record))
      .length;
  final healthyPct = aiModelProxyHealthPercentLabel(
    aiModelProxyHealthHealthyRate,
  );
  final warningPct = aiModelProxyHealthPercentLabel(
    aiModelProxyHealthWarningRate,
  );
  final degradedPct = aiModelProxyHealthPercentLabel(
    aiModelProxyHealthDegradedRate,
  );
  final outageFailPct = aiModelProxyHealthPercentLabel(
    1 - aiModelProxyHealthDegradedRate,
  );
  final slowPct = aiModelProxyHealthPercentLabel(aiModelProxyHealthSlowRate);
  final severeSlowPct = aiModelProxyHealthPercentLabel(
    aiModelProxyHealthSevereSlowRate,
  );
  final slowSec = aiModelProxyLatencySeconds(aiModelProxySlowLatencyMs);
  final severeSec = aiModelProxyLatencySeconds(aiModelProxySevereLatencyMs);
  var warningHours = 0;
  var degradedHours = 0;
  var outageHours = 0;
  var activeHours = 0;
  for (final hour in data.hourStats) {
    switch (_proxyOpsHourHealth(hour)) {
      case _ProxyOpsServiceHealth.outage:
        outageHours += 1;
        activeHours += 1;
      case _ProxyOpsServiceHealth.degraded:
        degradedHours += 1;
        activeHours += 1;
      case _ProxyOpsServiceHealth.warning:
        warningHours += 1;
        activeHours += 1;
      case _ProxyOpsServiceHealth.healthy:
        activeHours += 1;
      case _ProxyOpsServiceHealth.idle:
        break;
    }
  }
  final title = switch (overall) {
    _ProxyOpsServiceHealth.idle => text(
      zh: '当前暂无对外流量',
      en: 'No public traffic yet',
    ),
    _ProxyOpsServiceHealth.healthy => text(
      zh: '对外中转服务整体运行正常',
      en: 'Public proxy is fully operational',
    ),
    _ProxyOpsServiceHealth.warning => text(
      zh: '部分时段出现轻微波动',
      en: 'Some hours had minor disruption',
    ),
    _ProxyOpsServiceHealth.degraded => text(
      zh: '部分时段出现服务降级',
      en: 'Some hours are degraded',
    ),
    _ProxyOpsServiceHealth.outage => text(
      zh: '存在不可用时段',
      en: 'Some hours had an outage',
    ),
  };
  final body = switch (overall) {
    _ProxyOpsServiceHealth.idle => text(
      zh: '近窗还没有请求样本。下方 24 格保持待命灰，一旦有流量就会按成功率与尾延迟上色。',
      en: 'No samples in the recent window. The 24 cells stay idle-gray until traffic arrives.',
    ),
    _ProxyOpsServiceHealth.healthy => text(
      zh: '有流量的 $activeHours 个整点均未跌破健康阈值：成功率 ≥ $healthyPct，且 P95 < ${slowSec}s。',
      en: 'All $activeHours hours with traffic stayed healthy: success ≥ $healthyPct and P95 < ${slowSec}s.',
    ),
    _ProxyOpsServiceHealth.warning => text(
      zh: '有 $warningHours 个整点进入黄色波动区：成功率 ≥ $warningPct 且 < $healthyPct，或 P95 / 慢请求刚越过健康线，服务仍稳定可用。',
      en: '$warningHours hours entered the yellow band: success was ≥ $warningPct and < $healthyPct, or P95 / slow calls just crossed the healthy line.',
    ),
    _ProxyOpsServiceHealth.degraded => text(
      zh: '有 $degradedHours 个整点进入橙色降级区，另有 $warningHours 个黄色波动时段。部分请求可能失败或明显变慢。',
      en: '$degradedHours hours entered the orange degraded band, with $warningHours more in yellow. Some calls may fail or slow noticeably.',
    ),
    _ProxyOpsServiceHealth.outage => text(
      zh: '近窗包含 $outageHours 个红色中断时段、$degradedHours 个橙色降级时段和 $warningHours 个黄色波动时段。中断时段的失败率已达到 $outageFailPct 以上。',
      en: 'The window contains $outageHours red outage, $degradedHours orange degraded, and $warningHours yellow disruption hours. Outage hours reached at least $outageFailPct failures.',
    ),
  };
  Widget legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(kOpenHandRadius3),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 6),
            ],
          ),
        ),
        kOpenHandHGap6,
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  return _ProxyOpsPanel(
    icon: Icons.monitor_heart_rounded,
    title: text(zh: '对外服务时段健康', en: 'Service health by hour'),
    subtitle: text(
      zh: '按自然小时汇总近窗请求的可用性，颜色表示健康状态而不是流量大小',
      en: 'Clock-hour availability of the public proxy. Color is health, not volume.',
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kOpenHandRadius14),
            color: tone.withValues(alpha: 0.14),
            border: Border.all(color: tone.withValues(alpha: 0.38)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(kOpenHandRadius12),
                  border: Border.all(color: tone.withValues(alpha: 0.4)),
                ),
                child: Icon(switch (overall) {
                  _ProxyOpsServiceHealth.idle => Icons.hourglass_empty_rounded,
                  _ProxyOpsServiceHealth.healthy => Icons.verified_rounded,
                  _ProxyOpsServiceHealth.warning => Icons.info_outline_rounded,
                  _ProxyOpsServiceHealth.degraded =>
                    Icons.warning_amber_rounded,
                  _ProxyOpsServiceHealth.outage => Icons.report_rounded,
                }, color: tone),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: toneForeground,
                      ),
                    ),
                    kOpenHandGap4,
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              kOpenHandHGap8,
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(kOpenHandRadius20),
                  border: Border.all(color: tone.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _proxyOpsServiceHealthLabel(text, overall),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: toneForeground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        kOpenHandGap12,
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            legendDot(
              OpenHandStatusColors.success,
              text(zh: '正常', en: 'Operational'),
            ),
            legendDot(
              OpenHandStatusColors.caution,
              text(zh: '波动', en: 'Minor disruption'),
            ),
            legendDot(
              OpenHandStatusColors.warning,
              text(zh: '降级', en: 'Degraded'),
            ),
            legendDot(OpenHandStatusColors.error, text(zh: '中断', en: 'Outage')),
            legendDot(
              cs.onSurfaceVariant.withValues(alpha: 0.45),
              text(zh: '空闲', en: 'Idle'),
            ),
          ],
        ),
        kOpenHandGap14,
        OpenHandOperationalHeatmap(
          keepIdleCells: true,
          tone: OpenHandHeatmapTone.categorical,
          color: tone,
          emptyLabel: text(zh: '等待请求样本', en: 'Waiting for traffic'),
          segments: [
            for (final hour in data.hourStats)
              () {
                final health = _proxyOpsHourHealth(hour);
                final color = _proxyOpsServiceHealthColor(cs, health);
                final hourIndex = int.tryParse(hour.label) ?? 0;
                final rule = switch (health) {
                  _ProxyOpsServiceHealth.idle => text(
                    zh: '该小时没有请求样本，因此标为空闲待命，而不是事故。',
                    en: 'No samples this hour, so it is idle rather than an incident.',
                  ),
                  _ProxyOpsServiceHealth.healthy => text(
                    zh: '成功率 ≥ $healthyPct 且 P95 < ${slowSec}s，判定为正常运行。',
                    en: 'Success ≥ $healthyPct and P95 < ${slowSec}s, so this hour is operational.',
                  ),
                  _ProxyOpsServiceHealth.warning => text(
                    zh: '成功率 ≥ $warningPct 且 < $healthyPct，或 P95 ≥ ${slowSec}s、慢请求占比 ≥ $slowPct，判定为轻微波动。',
                    en: 'Success is ≥ $warningPct and < $healthyPct, or P95 ≥ ${slowSec}s / slow calls ≥ $slowPct, so this hour has minor disruption.',
                  ),
                  _ProxyOpsServiceHealth.degraded => text(
                    zh: '成功率 ≥ $degradedPct 且 < $warningPct，或 P95 ≥ ${severeSec}s、慢请求占比 ≥ $severeSlowPct，判定为服务降级。',
                    en: 'Success is ≥ $degradedPct and < $warningPct, or P95 ≥ ${severeSec}s / slow calls ≥ $severeSlowPct, so this hour is degraded.',
                  ),
                  _ProxyOpsServiceHealth.outage => text(
                    zh: '成功率低于 $degradedPct，判定为中断：该小时失败过于集中。',
                    en: 'Success below $degradedPct, so this hour is treated as an outage.',
                  ),
                };
                final topError = _proxyOpsTopCountLabel(hour.errors);
                return OpenHandChartSegment(
                  label: hour.label,
                  value: health == _ProxyOpsServiceHealth.idle ? 0 : 1,
                  color: color,
                  valueLabel: _proxyOpsServiceHealthLabel(text, health),
                  tooltip: OpenHandChartTooltip(
                    title: _proxyOpsHourRangeLabel(hourIndex),
                    subtitle: text(
                      zh: '该整点对外中转健康',
                      en: 'Public proxy health this hour',
                    ),
                    badge: _proxyOpsServiceHealthLabel(text, health),
                    badgeColor: color,
                    summary: switch (health) {
                      _ProxyOpsServiceHealth.idle => text(
                        zh: '这一小时没有对外请求。灰格只表示空闲，客户端并没有撞上故障。',
                        en: 'No public requests this hour. Gray only means idle, not a client-facing fault.',
                      ),
                      _ProxyOpsServiceHealth.healthy => text(
                        zh: '这一小时中转请求 ${hour.inferenceRequests} 次，成功 ${_proxyOpsPercentLabel(hour.inferenceSuccessRate)}，P95 ${_proxyOpsDurationLabel(hour.inferenceP95Ms)}，处于健康阈值内。',
                        en: '${hour.inferenceRequests} proxy requests this hour, ${_proxyOpsPercentLabel(hour.inferenceSuccessRate)} succeeded, P95 ${_proxyOpsDurationLabel(hour.inferenceP95Ms)} — within the healthy band.',
                      ),
                      _ProxyOpsServiceHealth.warning => text(
                        zh: '这一小时服务仍稳定可用，但成功率 ${_proxyOpsPercentLabel(hour.inferenceSuccessRate)} 或尾延迟 ${_proxyOpsDurationLabel(hour.inferenceP95Ms)} 已进入黄色波动区。',
                        en: 'Service remained available, but success ${_proxyOpsPercentLabel(hour.inferenceSuccessRate)} or P95 ${_proxyOpsDurationLabel(hour.inferenceP95Ms)} entered the yellow band.',
                      ),
                      _ProxyOpsServiceHealth.degraded => text(
                        zh: '这一小时成功率 ${_proxyOpsPercentLabel(hour.inferenceSuccessRate)} 或尾延迟 ${_proxyOpsDurationLabel(hour.inferenceP95Ms)} 已进入橙色降级区，用户体验可能明显受损。',
                        en: 'Success ${_proxyOpsPercentLabel(hour.inferenceSuccessRate)} or P95 ${_proxyOpsDurationLabel(hour.inferenceP95Ms)} entered the orange degraded band and may noticeably affect callers.',
                      ),
                      _ProxyOpsServiceHealth.outage => text(
                        zh: '这一小时失败 ${hour.inferenceFailures} / ${hour.inferenceRequests}，失败率偏高，对外中转在该时段很可能已经中断。',
                        en: '${hour.inferenceFailures} / ${hour.inferenceRequests} proxy requests failed this hour. The public proxy likely interrupted callers.',
                      ),
                    },
                    metrics: [
                      OpenHandChartTooltipMetric(
                        label: text(zh: '健康判定', en: 'Verdict'),
                        value: _proxyOpsServiceHealthLabel(text, health),
                        hint: rule,
                        icon: Icons.monitor_heart_rounded,
                        color: color,
                      ),
                      ..._proxyOpsHourTooltipMetrics(
                        text: text,
                        hour: hour,
                        tone: color,
                        dayRequests: inferenceRequests,
                        inferenceOnly: true,
                      ),
                      OpenHandChartTooltipMetric(
                        label: text(zh: '流式请求', en: 'Streams'),
                        value: '${hour.streams}',
                        icon: Icons.stream_rounded,
                        color: color,
                      ),
                      OpenHandChartTooltipMetric(
                        label: text(zh: '重试请求', en: 'Retries'),
                        value: '${hour.retries}',
                        icon: Icons.replay_rounded,
                        color: hour.retries > 0
                            ? OpenHandStatusColors.warning
                            : color,
                      ),
                      if (hour.lastAt != null)
                        OpenHandChartTooltipMetric(
                          label: text(zh: '最近请求', en: 'Latest'),
                          value: formatListDateTime(hour.lastAt!),
                          icon: Icons.schedule_rounded,
                          color: color,
                        ),
                    ],
                    notes: [
                      rule,
                      text(
                        zh: '绿 / 黄 / 橙 / 红依次表示正常、波动、降级、中断，灰表示空闲。请求量深浅请看「入口请求」里的到达热力。',
                        en: 'Green / yellow / orange / red means operational, minor disruption, degraded, and outage; gray is idle. Volume depth lives on the Ingress arrival heat.',
                      ),
                      if (topError != null)
                        text(
                          zh: '主要失败原因：$topError',
                          en: 'Top error: $topError',
                        ),
                    ],
                  ),
                );
              }(),
          ],
        ),
        kOpenHandGap10,
        Text(
          text(
            zh: '健康判定：绿色 ≥ $healthyPct；黄色 ≥ $warningPct 且 < $healthyPct；橙色 ≥ $degradedPct 且 < $warningPct；红色 < $degradedPct。P95 达到 $slowSec / $severeSec 秒或慢请求占比达到 $slowPct / $severeSlowPct 时，也会分别下调至黄色 / 橙色。灰格表示空闲。',
            en: 'Health bands: green ≥ $healthyPct, yellow ≥ $warningPct and < $healthyPct, orange ≥ $degradedPct and < $warningPct, red < $degradedPct. P95 at ${slowSec}s / ${severeSec}s or slow calls at $slowPct / $severeSlowPct also lowers the grade to yellow / orange. Gray means idle.',
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

String _proxyOpsUpstreamEndpoint(
  AiModelProxyRequestRecord record,
  String unknown,
) {
  final host = record.remoteHost.trim();
  final port = record.remotePort.trim();
  if (host.isEmpty) return unknown;
  if (port.isEmpty) return host;
  final display = host.contains(':') && !host.startsWith('[')
      ? '[$host]'
      : host;
  return '$display:$port';
}

Widget _proxyOpsDonut({
  required ColorScheme cs,
  required List<OpenHandChartSegment> segments,
  String? centerLabel,
}) {
  return OpenHandOperationalDonutChart(
    segments: segments,
    trackColor: cs.surfaceContainerHighest,
    centerLabel: centerLabel,
    height: _kProxyOpsDonutHeight,
    showSelectionHighlight: false,
    onSelectionChanged: null,
  );
}

Widget _proxyOpsRequestTrendPanel(
  BuildContext context,
  _ProxyOpsSnapshot data,
) {
  final text = openHandTextResolver(context);
  final cs = Theme.of(context).colorScheme;
  return _ProxyOpsTrendDetailPanel(
    icon: Icons.show_chart_rounded,
    title: text(zh: '成功 / 失败曲线', en: 'Success / Failure Curve'),
    subtitle: data.usesHistoricalTrendWindow
        ? text(zh: '默认最近 12 个采样桶', en: 'Latest 12 samples by default')
        : text(zh: '默认最近 12 分钟', en: 'Latest 12 minutes by default'),
    series: [
      OpenHandChartSeries(
        label: text(zh: '成功', en: 'Success'),
        values: data.trendSuccess,
        aggregation: OpenHandTrendAggregation.sum,
        color: OpenHandStatusColors.success,
      ),
      OpenHandChartSeries(
        label: text(zh: '失败', en: 'Failed'),
        values: data.trendFailure,
        aggregation: OpenHandTrendAggregation.sum,
        color: cs.error,
      ),
    ],
    minutes: data.bucketMinutes,
    emptyLabel: text(zh: '等待请求样本', en: 'Waiting for traffic'),
  );
}

Widget _proxyOpsLatencyOverlayPanel(
  BuildContext context,
  _ProxyOpsSnapshot data,
) {
  final text = openHandTextResolver(context);
  final cs = Theme.of(context).colorScheme;
  return _ProxyOpsTrendDetailPanel(
    icon: Icons.timeline_rounded,
    title: text(zh: '平均 / p95 叠加', en: 'Average / p95 Overlay'),
    subtitle: text(zh: '同一时间轴对比均值与尾延迟', en: 'Mean versus tail on one axis'),
    series: [
      OpenHandChartSeries(
        label: text(zh: '平均', en: 'Average'),
        values: data.averageLatencyBuckets,
        color: cs.primary,
      ),
      OpenHandChartSeries(
        label: 'p95',
        values: data.p95LatencyBuckets,
        aggregation: OpenHandTrendAggregation.maximum,
        color: cs.tertiary,
      ),
    ],
    minutes: data.bucketMinutes,
    valueSuffix: 'ms',
    emptyLabel: text(zh: '暂无耗时样本', en: 'No latency samples'),
  );
}

({List<double> values, String suffix}) _proxyOpsScaledByteTrend(
  List<double> bytes,
) {
  final maximum = bytes.fold<double>(0, math.max);
  final divisor = maximum >= 1024 * 1024 * 1024
      ? 1024 * 1024
      : maximum >= 1024
      ? 1024
      : 1;
  final suffix = divisor == 1024 * 1024
      ? ' MB'
      : divisor == 1024
      ? ' KB'
      : ' B';
  return (values: [for (final value in bytes) value / divisor], suffix: suffix);
}

_ProxyOpsInsightSpec _proxyOpsInsightSpec(
  BuildContext context,
  _ProxyOpsInsightKind kind,
) {
  final cs = Theme.of(context).colorScheme;
  final text = openHandTextResolver(context);
  const success = OpenHandStatusColors.success;
  final palette = _proxyOpsChartPalette(cs);
  final unknown = text(zh: '未知', en: 'Unknown');
  final unknownProtocol = text(zh: '未知协议', en: 'Unknown protocol');
  final unknownModel = text(zh: '未知模型', en: 'Unknown model');
  final unknownProvider = text(zh: '未知提供商', en: 'Unknown provider');
  final unknownMode = text(zh: '未知模式', en: 'Unknown mode');
  final unknownUpstream = text(zh: '未知上游', en: 'Unknown upstream');
  final unknownClient = text(zh: '未知客户端', en: 'Unknown client');
  final emptyChart = text(zh: '暂无样本数据', en: 'No samples yet');

  switch (kind) {
    case _ProxyOpsInsightKind.connections:
      return _ProxyOpsInsightSpec(
        icon: Icons.link_rounded,
        title: text(zh: '连接明细', en: 'Connections'),
        subtitle: text(
          zh: '连接趋势、实时占用、对端与时段热力',
          en: 'Connection trend, occupancy, peers and hourly heat',
        ),
        sections: (context, data) {
          final current = data.controller.currentConnections;
          final peerCap = math.max(data.uniquePeerCount, math.max(current, 1));
          final live = data.controller.liveConnections;
          final unknownInflight = data.controller.unknownLiveConnections;
          final clients = _proxyOpsLiveAwareGroups(
            groups: data.groupBy(
              (record) => _proxyOpsClientFamilyLabel(
                record.clientUserAgent,
                unknownClient,
              ),
              unknown: unknownClient,
            ),
            live: live,
            keyOf: (connection) =>
                _proxyOpsClientFamilyLabel(connection.userAgent, unknownClient),
            unknown: unknownClient,
            unknownInflight: unknownInflight,
          );
          final peers = _proxyOpsLiveAwareGroups(
            groups: data.groupBy(
              (record) => _proxyOpsPeerLabel(record, unknown),
              unknown: unknown,
            ),
            live: live,
            keyOf: (connection) {
              final endpoint = connection.endpoint.trim();
              return endpoint.isEmpty ? unknown : endpoint;
            },
            unknown: unknown,
            unknownInflight: unknownInflight,
          );
          return [
            _ProxyOpsPanel(
              icon: Icons.speed_rounded,
              title: text(zh: '连接仪表', en: 'Connection Gauges'),
              child: _ProxyOpsInsightMetricGrid(
                children: [
                  _proxyOpsCountMeter(
                    label: text(zh: '当前连接', en: 'Live'),
                    value: current,
                    maximum: peerCap,
                    color: cs.primary,
                    helper: text(
                      zh: '对端 ${data.uniquePeerCount}',
                      en: 'Peers ${data.uniquePeerCount}',
                    ),
                  ),
                  _proxyOpsCountMeter(
                    label: text(zh: '独立对端', en: 'Unique peers'),
                    value: data.uniquePeerCount,
                    maximum: math.max(data.uniquePeerCount, 1),
                    color: cs.tertiary,
                  ),
                  _proxyOpsCountMeter(
                    label: text(zh: '独立端口', en: 'Unique ports'),
                    value: data.uniquePortCount,
                    maximum: math.max(data.uniquePortCount, 1),
                    color: cs.secondary,
                  ),
                ],
              ),
            ),
            _ProxyOpsTrendDetailPanel(
              icon: Icons.show_chart_rounded,
              title: text(zh: '连接趋势', en: 'Connection Trend'),
              subtitle: text(
                zh: '每分钟连接峰值 · 遥测持久化留存',
                en: 'Peak connections per minute · persisted telemetry',
              ),
              series: [
                OpenHandChartSeries(
                  label: text(zh: '连接峰值', en: 'Peak connections'),
                  values: data.connectionBuckets,
                  aggregation: OpenHandTrendAggregation.maximum,
                  color: cs.primary,
                ),
              ],
              minutes: data.bucketMinutes,
              emptyLabel: text(zh: '等待连接样本', en: 'Waiting for connections'),
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.devices_rounded,
              title: text(zh: '客户端列表', en: 'Client List'),
              subtitle: text(
                zh: clients.isEmpty
                    ? '正在占用入口的客户端家族'
                    : '当前在线 ${clients.length} 个客户端家族',
                en: clients.isEmpty
                    ? 'Client families occupying the gateway'
                    : '${clients.length} live client families',
              ),
              groups: clients,
              leadingHeader: text(zh: '客户端', en: 'Client'),
              emptyLabel: text(zh: '等待客户端连入', en: 'Waiting for clients'),
              maxBodyHeight: _kProxyOpsConnectionListMaxHeight,
              sortByValue: false,
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.public_rounded,
              title: text(zh: '对端列表', en: 'Peer List'),
              subtitle: text(
                zh: peers.isEmpty ? '正在占用入口的对端地址' : '当前在线 ${peers.length} 个对端',
                en: peers.isEmpty
                    ? 'Peers occupying the gateway'
                    : '${peers.length} live peers',
              ),
              groups: peers,
              leadingHeader: text(zh: '对端', en: 'Peer'),
              emptyLabel: text(zh: '等待对端连入', en: 'Waiting for peers'),
              maxBodyHeight: _kProxyOpsConnectionListMaxHeight,
              sortByValue: false,
            ),
            _proxyOpsChartPanel(
              icon: Icons.view_week_rounded,
              title: text(zh: '对端活跃时段', en: 'Peer Hours'),
              empty: false,
              emptyLabel: emptyChart,
              subtitle: text(
                zh: '颜色深度表示该整点连入的独立客户端数',
                en: 'Color depth is unique clients in that clock hour',
              ),
              chart: OpenHandOperationalHeatmap(
                keepIdleCells: true,
                segments: _proxyOpsHourSegments(
                  data.hourStats,
                  cs.primary,
                  valueOf: (hour) => hour.peers.length,
                  valueLabelOf: (hour) => '${hour.peers.length}',
                  tooltipOf: (hour) => _proxyOpsHourVolumeTooltip(
                    text: text,
                    hour: hour,
                    tone: cs.primary,
                    badge: text(
                      zh: '${hour.peers.length} 个对端',
                      en: '${hour.peers.length} peers',
                    ),
                    subtitle: text(
                      zh: '该整点独立客户端活跃度',
                      en: 'Unique clients this clock hour',
                    ),
                    summary: hour.peers.isEmpty
                        ? text(
                            zh: '这一小时没有记录到客户端对端。灰格表示空闲，不代表服务中断。',
                            en: 'No client peers in this hour. Gray means idle, not an outage.',
                          )
                        : text(
                            zh: '这一小时有 ${hour.peers.length} 个独立对端连入，共 ${hour.requests} 次请求。颜色越深表示对端越密集，与底部健康条的绿黄红含义不同。',
                            en: '${hour.peers.length} unique peers sent ${hour.requests} requests. Darker color means denser clients, not health.',
                          ),
                    notes: [
                      text(
                        zh: '此图统计的是客户端多样性，不是成功率。整体对外健康请看「请求总览」底部的时段健康条。',
                        en: 'This strip measures client diversity, not success rate. Overall health is on the Requests dialog.',
                      ),
                    ],
                    dayRequests: data.records.length,
                  ),
                ),
                color: cs.primary,
              ),
            ),
            _ProxyOpsDetailSection(
              icon: Icons.tune_rounded,
              title: text(zh: '监听属性', en: 'Listen Properties'),
              rows: {
                text(zh: '服务入口', en: 'Endpoint'): data.endpoint,
                text(
                  zh: '访问鉴权',
                  en: 'Authentication',
                ): data.settings.requireAuthentication
                    ? text(zh: '已启用', en: 'Enabled')
                    : text(zh: '未启用', en: 'Disabled'),
                text(zh: '接口风格', en: 'API style'): data.settings.apiStyle.label,
                text(zh: '状态页', en: 'Status page'):
                    data.controller.publicStatusUrl,
                text(zh: '运行时长', en: 'Uptime'): formatCompactDuration(
                  data.controller.uptime,
                ),
              },
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.activeRequests:
      return _ProxyOpsInsightSpec(
        icon: Icons.bolt_rounded,
        title: text(zh: '活跃请求', en: 'Active Requests'),
        subtitle: text(
          zh: '执行槽位、限流与调度模式',
          en: 'Slots, limits and dispatch mode',
        ),
        sections: (context, data) {
          final active = data.controller.activeRequests;
          final limit = data.settings.limitThreshold;
          final requestCapacity = data.controller.concurrentRequestLimit;
          final available = math.max(0, requestCapacity - active);
          final modeSegments = _proxyOpsSegments(
            data.countBy(
              (record) => aiModelProxyDispatchModeLabel(record.proxyMode, text),
              unknown: unknownMode,
            ),
            palette,
          );
          return [
            _proxyOpsPanelRow([
              _ProxyOpsPanel(
                icon: Icons.speed_rounded,
                title: text(zh: '执行仪表', en: 'Execution Gauges'),
                child: _ProxyOpsInsightMetricGrid(
                  children: [
                    _proxyOpsCountMeter(
                      label: text(zh: '执行中', en: 'In flight'),
                      value: active,
                      maximum: requestCapacity,
                      color: cs.tertiary,
                      helper: text(
                        zh: '并发上限 $requestCapacity',
                        en: 'Concurrency cap $requestCapacity',
                      ),
                    ),
                    _proxyOpsCountMeter(
                      label: data.settings.limitMode.label,
                      value: data.currentRpm,
                      maximum: limit,
                      color: cs.primary,
                      helper: text(
                        zh: '近窗 ${data.windowRequestCount}',
                        en: 'Window ${data.windowRequestCount}',
                      ),
                    ),
                  ],
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.stacked_bar_chart_rounded,
                title: text(zh: '并发槽位', en: 'Concurrency Slots'),
                empty: requestCapacity <= 0,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalStatusBand(
                  segments: [
                    OpenHandChartSegment(
                      label: text(zh: '占用', en: 'Used'),
                      value: active,
                      color: cs.tertiary,
                      icon: Icons.bolt_rounded,
                      valueLabel: '$active',
                    ),
                    OpenHandChartSegment(
                      label: text(zh: '可用', en: 'Available'),
                      value: available,
                      color: cs.primary,
                      icon: Icons.check_circle_outline_rounded,
                      valueLabel: '$available',
                    ),
                  ],
                ),
              ),
            ]),
            _proxyOpsChartPanel(
              icon: Icons.alt_route_rounded,
              title: text(zh: '调度模式柱状图', en: 'Dispatch Mode Bars'),
              empty: modeSegments.isEmpty,
              emptyLabel: emptyChart,
              chart: OpenHandOperationalComparisonBars(
                segments: modeSegments,
                orientation: OpenHandComparisonBarOrientation.vertical,
                valueLabel: (segment) => '${segment.value.round()}',
              ),
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.requests:
      return _ProxyOpsInsightSpec(
        icon: Icons.call_made_rounded,
        title: text(zh: '请求总览', en: 'Requests'),
        subtitle: text(
          zh: '累计体量、吞吐曲线与对外时段健康',
          en: 'Volume, throughput and hourly service health',
        ),
        sections: (context, data) => [
          _ProxyOpsStatPanel(
            icon: Icons.analytics_rounded,
            title: text(zh: '体量概览', en: 'Volume'),
            tiles: [
              _proxyOpsInsightTile(
                context,
                Icons.call_made_rounded,
                text(zh: '累计请求', en: 'Lifetime'),
                '${data.requestTotal}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.history_toggle_off_rounded,
                text(zh: '近窗请求', en: 'Window'),
                '${data.windowRequestCount}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.av_timer_rounded,
                text(zh: '窗内均值', en: 'Window avg'),
                (data.windowRequestCount / _kProxyOpsTrendBuckets)
                    .toStringAsFixed(1),
                helper: text(zh: '每分钟', en: 'per minute'),
                color: cs.tertiary,
              ),
              _proxyOpsInsightTile(
                context,
                Icons.public_rounded,
                text(zh: '状态页访问', en: 'Status hits'),
                '${data.records.where(isAiModelProxyStatusRecord).length}',
                helper: text(zh: '近窗样本', en: 'in window'),
                color: cs.secondary,
              ),
            ],
          ),
          _ProxyOpsTrendDetailPanel(
            icon: Icons.show_chart_rounded,
            title: text(zh: '吞吐曲线', en: 'Throughput Curve'),
            subtitle: text(zh: '每分钟请求总量', en: 'Requests per minute'),
            series: [
              OpenHandChartSeries(
                label: text(zh: '吞吐', en: 'Throughput'),
                values: data.throughputBuckets,
                aggregation: OpenHandTrendAggregation.sum,
                color: cs.primary,
              ),
            ],
            minutes: data.bucketMinutes,
            emptyLabel: text(zh: '等待请求样本', en: 'Waiting for traffic'),
          ),
          _proxyOpsServiceHealthPanel(context, data),
        ],
      );

    case _ProxyOpsInsightKind.ingress:
      return _ProxyOpsInsightSpec(
        icon: Icons.input_rounded,
        title: text(zh: '入口请求', en: 'Ingress'),
        subtitle: text(
          zh: '本次运行摄入与全天到达热力',
          en: 'This-run intake and daily arrival heat',
        ),
        sections: (context, data) {
          final runtime = data.controller.runtimeRequestCount;
          final runtimeErrors = data.controller.runtimeErrorCount;
          final lifetime = math.max(data.requestTotal, runtime);
          final errorRate = runtime <= 0 ? 0.0 : runtimeErrors / runtime;
          return [
            _proxyOpsPanelRow([
              _ProxyOpsPanel(
                icon: Icons.speed_rounded,
                title: text(zh: '入口仪表', en: 'Ingress Gauges'),
                child: _ProxyOpsInsightMetricGrid(
                  children: [
                    _proxyOpsRateMeter(
                      label: text(zh: '本轮错误率', en: 'Run error rate'),
                      rate: errorRate,
                      color: _proxyOpsHealthColor(cs, 1 - errorRate),
                      helper: '$runtimeErrors / $runtime',
                    ),
                    _proxyOpsRateMeter(
                      label: text(zh: '本轮 / 累计', en: 'Run / lifetime'),
                      rate: lifetime <= 0 ? 0 : runtime / lifetime,
                      color: cs.secondary,
                      helper: '$runtime / $lifetime',
                      unavailable: lifetime <= 0,
                    ),
                  ],
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.bar_chart_rounded,
                title: text(zh: '本轮对照', en: 'This-run Contrast'),
                empty: runtime <= 0 && data.requestTotal <= 0,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalComparisonBars(
                  orientation: OpenHandComparisonBarOrientation.vertical,
                  valueLabel: (segment) => '${segment.value.round()}',
                  segments: [
                    OpenHandChartSegment(
                      label: text(zh: '本轮入口', en: 'This run'),
                      value: runtime,
                      color: cs.secondary,
                      valueLabel: '$runtime',
                    ),
                    OpenHandChartSegment(
                      label: text(zh: '累计请求', en: 'Lifetime'),
                      value: data.requestTotal,
                      color: cs.primary,
                      valueLabel: '${data.requestTotal}',
                    ),
                    OpenHandChartSegment(
                      label: text(zh: '本轮错误', en: 'Run errors'),
                      value: runtimeErrors,
                      color: cs.error,
                      valueLabel: '$runtimeErrors',
                    ),
                  ],
                ),
              ),
            ]),
            _proxyOpsChartPanel(
              icon: Icons.view_week_rounded,
              title: text(zh: '到达时段热力', en: 'Arrival Heat'),
              empty: false,
              emptyLabel: emptyChart,
              subtitle: text(
                zh: '颜色深度表示该整点到达的请求量',
                en: 'Color depth is arrival volume in that clock hour',
              ),
              chart: OpenHandOperationalHeatmap(
                keepIdleCells: true,
                segments: _proxyOpsHourSegments(
                  data.hourStats,
                  cs.secondary,
                  valueOf: (hour) => hour.requests,
                  valueLabelOf: (hour) => '${hour.requests}',
                  tooltipOf: (hour) => _proxyOpsHourVolumeTooltip(
                    text: text,
                    hour: hour,
                    tone: cs.secondary,
                    badge: text(
                      zh: '${hour.requests} 次到达',
                      en: '${hour.requests} arrivals',
                    ),
                    subtitle: text(
                      zh: '该整点入口到达量',
                      en: 'Ingress arrivals this clock hour',
                    ),
                    summary: hour.requests <= 0
                        ? text(
                            zh: '这一小时没有入口请求到达。灰格表示空闲，不代表事故。',
                            en: 'No ingress arrived this hour. Gray means idle, not an incident.',
                          )
                        : text(
                            zh: '这一小时到达 ${hour.requests} 次请求，成功 ${hour.successes} 次、失败 ${hour.failures} 次。颜色越深只说明更忙，不表示更健康。',
                            en: '${hour.requests} arrivals, ${hour.successes} succeeded and ${hour.failures} failed. Darker only means busier, not healthier.',
                          ),
                    notes: [
                      text(
                        zh: '到达热力只描述流量何时进来。对外服务是否正常，请看「请求总览」底部的绿/黄/红健康条。',
                        en: 'Arrival heat only shows when traffic came in. Service health is the green/yellow/red strip on Requests.',
                      ),
                    ],
                    dayRequests: data.records.length,
                  ),
                ),
                color: cs.secondary,
              ),
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.succeeded:
      return _ProxyOpsInsightSpec(
        icon: Icons.task_alt_rounded,
        title: text(zh: '成功请求', en: 'Succeeded'),
        tone: success,
        subtitle: text(
          zh: '成功趋势、成功率、耗时带与模型质量',
          en: 'Success trend, rate, latency bands and model quality',
        ),
        sections: (context, data) {
          final fast = text(zh: '快速 < 1s', en: 'Fast < 1s');
          final normal = text(zh: '正常 1-3s', en: 'Normal 1-3s');
          final slow = text(zh: '慢速 ≥ 3s', en: 'Slow ≥ 3s');
          final bands = _proxyOpsSegments(
            data.countBy(
              (record) => record.durationMs < _kProxyOpsFastLatencyMs
                  ? fast
                  : record.durationMs < _kProxyOpsSlowLatencyMs
                  ? normal
                  : slow,
              unknown: unknown,
              source: data.records.where((record) => record.success),
            ),
            [success, cs.primary, OpenHandStatusColors.warning],
          );
          final models = data.groupBy(
            (record) => _proxyOpsModelGroupLabel(record, unknownModel),
            unknown: unknownModel,
            where: (record) => record.success,
          );
          return [
            _proxyOpsPanelRow([
              _ProxyOpsPanel(
                icon: Icons.verified_rounded,
                title: text(zh: '成功仪表', en: 'Success Gauge'),
                child: _ProxyOpsInsightMetricGrid(
                  children: [
                    _proxyOpsRateMeter(
                      label: text(zh: '成功率', en: 'Success rate'),
                      rate: data.successRate,
                      color: _proxyOpsHealthColor(cs, data.successRate),
                      helper: '${data.successTotal} / ${data.requestTotal}',
                    ),
                  ],
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.donut_small_rounded,
                title: text(zh: '成功耗时带', en: 'Success Latency Bands'),
                empty: bands.isEmpty,
                emptyLabel: emptyChart,
                chart: _proxyOpsDonut(
                  cs: cs,
                  segments: bands,
                  centerLabel: '${data.successTotal}',
                ),
              ),
            ]),
            _ProxyOpsTrendDetailPanel(
              icon: Icons.trending_up_rounded,
              title: text(zh: '成功趋势', en: 'Success Trend'),
              subtitle: text(
                zh: '每分钟成功请求 · 遥测持久化留存',
                en: 'Successful requests per minute · persisted telemetry',
              ),
              series: [
                OpenHandChartSeries(
                  label: text(zh: '成功', en: 'Succeeded'),
                  values: data.trendSuccess,
                  aggregation: OpenHandTrendAggregation.sum,
                  color: success,
                ),
              ],
              minutes: data.bucketMinutes,
              emptyLabel: text(zh: '暂无成功样本', en: 'No successful samples'),
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.leaderboard_rounded,
              title: text(zh: '成功模型排行', en: 'Successful Models'),
              groups: models,
              leadingHeader: text(zh: '模型', en: 'Model'),
              emptyLabel: emptyChart,
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.failures:
      return _ProxyOpsInsightSpec(
        icon: Icons.error_outline_rounded,
        title: text(zh: '失败明细', en: 'Failures'),
        tone: cs.error,
        subtitle: text(
          zh: '失败趋势、失败率、原因条与失败模型',
          en: 'Failure trend, rate, reasons and failed models',
        ),
        sections: (context, data) {
          final logs = data.recentFirst
              .where((record) => !record.success)
              .toList(growable: false);
          final reasons = _proxyOpsSegments(
            data.countBy(
              (record) =>
                  record.error ?? text(zh: '未提供错误原因', en: 'No error reason'),
              unknown: text(zh: '未提供错误原因', en: 'No error reason'),
              source: logs,
            ),
            palette,
          );
          final models = data.groupBy(
            (record) => _proxyOpsModelGroupLabel(record, unknownModel),
            unknown: unknownModel,
            where: (record) => !record.success,
          );
          return [
            _proxyOpsPanelRow([
              _ProxyOpsPanel(
                icon: Icons.report_rounded,
                title: text(zh: '失败仪表', en: 'Failure Gauge'),
                child: _ProxyOpsInsightMetricGrid(
                  children: [
                    _proxyOpsRateMeter(
                      label: text(zh: '失败率', en: 'Failure rate'),
                      rate: data.failureRate,
                      color: _proxyOpsHealthColor(cs, 1 - data.failureRate),
                      helper: '${data.failureTotal} / ${data.requestTotal}',
                    ),
                  ],
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.stacked_bar_chart_rounded,
                title: text(zh: '失败原因', en: 'Failure Reasons'),
                empty: reasons.isEmpty,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalComparisonBars(
                  segments: reasons,
                  orientation: OpenHandComparisonBarOrientation.horizontal,
                  valueLabel: (segment) => '${segment.value.round()}',
                ),
              ),
            ]),
            _ProxyOpsTrendDetailPanel(
              icon: Icons.trending_down_rounded,
              title: text(zh: '失败趋势', en: 'Failure Trend'),
              subtitle: text(
                zh: '每分钟失败请求 · 遥测持久化留存',
                en: 'Failed requests per minute · persisted telemetry',
              ),
              series: [
                OpenHandChartSeries(
                  label: text(zh: '失败', en: 'Failed'),
                  values: data.trendFailure,
                  aggregation: OpenHandTrendAggregation.sum,
                  color: cs.error,
                ),
              ],
              minutes: data.bucketMinutes,
              emptyLabel: text(zh: '暂无失败样本', en: 'No failure samples'),
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.leaderboard_rounded,
              title: text(zh: '失败模型排行', en: 'Failed Models'),
              groups: models,
              leadingHeader: text(zh: '模型', en: 'Model'),
              emptyLabel: emptyChart,
            ),
            _proxyOpsChartPanel(
              icon: Icons.bug_report_rounded,
              title: text(zh: '失败记录', en: 'Failure Log'),
              empty: logs.isEmpty,
              emptyLabel: text(zh: '暂无失败记录', en: 'No failures'),
              chart: _proxyOpsTraceTable(
                context: context,
                data: data,
                records: logs,
                emptyLabel: text(zh: '暂无失败记录', en: 'No failures'),
                showError: true,
              ),
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.ingressErrors:
      return _ProxyOpsInsightSpec(
        icon: Icons.report_problem_outlined,
        title: text(zh: '入口错误', en: 'Ingress Errors'),
        subtitle: text(
          zh: '网关错误趋势、模型失败对照与时段热力',
          en: 'Gateway error trend, upstream contrast and hourly heat',
        ),
        tone: cs.error,
        sections: (context, data) {
          final runtime = data.controller.runtimeRequestCount;
          final runtimeErrors = data.controller.runtimeErrorCount;
          final errorRate = runtime <= 0 ? 0.0 : runtimeErrors / runtime;
          return [
            _proxyOpsPanelRow([
              _ProxyOpsPanel(
                icon: Icons.speed_rounded,
                title: text(zh: '网关错误仪表', en: 'Gateway Error Gauge'),
                child: _ProxyOpsInsightMetricGrid(
                  children: [
                    _proxyOpsRateMeter(
                      label: text(zh: '本轮入口错误率', en: 'Run ingress error'),
                      rate: errorRate,
                      color: _proxyOpsHealthColor(cs, 1 - errorRate),
                      helper: '$runtimeErrors / $runtime',
                    ),
                  ],
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.bar_chart_rounded,
                title: text(zh: '网关 vs 上游', en: 'Gateway vs Upstream'),
                empty: runtimeErrors <= 0 && data.failureTotal <= 0,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalComparisonBars(
                  orientation: OpenHandComparisonBarOrientation.vertical,
                  valueLabel: (segment) => '${segment.value.round()}',
                  segments: [
                    OpenHandChartSegment(
                      label: text(zh: '入口错误', en: 'Ingress'),
                      value: runtimeErrors,
                      color: OpenHandStatusColors.warning,
                      valueLabel: '$runtimeErrors',
                    ),
                    OpenHandChartSegment(
                      label: text(zh: '模型失败', en: 'Upstream'),
                      value: data.failureTotal,
                      color: cs.error,
                      valueLabel: '${data.failureTotal}',
                    ),
                  ],
                ),
              ),
            ]),
            _ProxyOpsTrendDetailPanel(
              icon: Icons.monitor_heart_outlined,
              title: text(zh: '入口错误趋势', en: 'Ingress Error Trend'),
              subtitle: text(
                zh: '每分钟网关错误 · 遥测持久化留存',
                en: 'Gateway errors per minute · persisted telemetry',
              ),
              series: [
                OpenHandChartSeries(
                  label: text(zh: '入口错误', en: 'Ingress errors'),
                  values: data.ingressErrorBuckets,
                  aggregation: OpenHandTrendAggregation.sum,
                  color: OpenHandStatusColors.warning,
                ),
              ],
              minutes: data.bucketMinutes,
              emptyLabel: text(zh: '暂无入口错误', en: 'No ingress errors'),
            ),
            _proxyOpsChartPanel(
              icon: Icons.view_week_rounded,
              title: text(zh: '失败时段热力', en: 'Failure Hours'),
              empty: false,
              emptyLabel: emptyChart,
              subtitle: text(
                zh: '颜色深度表示该整点失败次数',
                en: 'Color depth is failure count in that clock hour',
              ),
              chart: OpenHandOperationalHeatmap(
                keepIdleCells: true,
                segments: _proxyOpsHourSegments(
                  data.hourStats,
                  cs.error,
                  valueOf: (hour) => hour.failures,
                  valueLabelOf: (hour) => '${hour.failures}',
                  tooltipOf: (hour) {
                    final topError = _proxyOpsTopCountLabel(hour.errors);
                    return _proxyOpsHourVolumeTooltip(
                      text: text,
                      hour: hour,
                      tone: cs.error,
                      badge: hour.failures <= 0
                          ? text(zh: '无失败', en: 'No failures')
                          : text(
                              zh: '${hour.failures} 次失败',
                              en: '${hour.failures} failures',
                            ),
                      subtitle: text(
                        zh: '该整点上游/网关失败集中度',
                        en: 'Failure concentration this clock hour',
                      ),
                      summary: hour.failures <= 0
                          ? text(
                              zh: '这一小时没有失败样本。浅色格表示没有失败，不代表完全没有流量。',
                              en: 'No failures in this hour. A pale cell means no failures, not necessarily no traffic.',
                            )
                          : text(
                              zh: '这一小时失败 ${hour.failures} 次，占该时段 ${_proxyOpsPercentLabel(hour.requests <= 0 ? 0 : hour.failures / hour.requests)}。颜色越深表示失败越集中。',
                              en: '${hour.failures} failures (${_proxyOpsPercentLabel(hour.requests <= 0 ? 0 : hour.failures / hour.requests)} of the hour). Darker means more concentrated failures.',
                            ),
                      notes: [
                        if (topError != null)
                          text(
                            zh: '主要失败原因：$topError',
                            en: 'Top error: $topError',
                          ),
                        text(
                          zh: '此图只看失败次数。若要看该小时是否中断，请到「请求总览」底部的阶段健康热力。',
                          en: 'This strip counts failures only. Hourly outage vs idle is on the Requests health strip.',
                        ),
                      ],
                      dayRequests: data.records.length,
                    );
                  },
                ),
                color: cs.error,
              ),
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.averageLatency:
      return _ProxyOpsInsightSpec(
        icon: Icons.speed_rounded,
        title: text(zh: '平均耗时', en: 'Average Latency'),
        subtitle: text(
          zh: '均值仪表、分位对照与模型均耗时',
          en: 'Mean gauge, percentiles and per-model avg',
        ),
        sections: (context, data) {
          final avg = data.settings.averageDurationMs;
          final models = data.groupBy(
            (record) => _proxyOpsModelGroupLabel(record, unknownModel),
            unknown: unknownModel,
          );
          return [
            _proxyOpsPanelRow([
              _ProxyOpsPanel(
                icon: Icons.timer_rounded,
                title: text(zh: '均值仪表', en: 'Mean Gauge'),
                child: _ProxyOpsInsightMetricGrid(
                  children: [
                    _proxyOpsRateMeter(
                      label: text(zh: '相对 3s SLA', en: 'vs 3s SLA'),
                      rate: avg / _kProxyOpsSlowLatencyMs,
                      color: _proxyOpsHealthColor(
                        cs,
                        1 - (avg / _kProxyOpsSlowLatencyMs).clamp(0.0, 1.0),
                      ),
                      helper: '${avg.toStringAsFixed(0)}ms',
                    ),
                  ],
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.straighten_rounded,
                title: text(zh: 'p50 / 均值', en: 'p50 / Mean'),
                empty: data.p50LatencyMs <= 0 && avg <= 0,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalLatencyRange(
                  segments: [
                    OpenHandChartSegment(
                      label: 'p50',
                      value: data.p50LatencyMs,
                      color: cs.secondary,
                      valueLabel: '${data.p50LatencyMs}ms',
                    ),
                    OpenHandChartSegment(
                      label: text(zh: '均值', en: 'Avg'),
                      value: avg,
                      color: cs.primary,
                      valueLabel: '${avg.toStringAsFixed(0)}ms',
                    ),
                  ],
                ),
              ),
            ]),
            _proxyOpsChartPanel(
              icon: Icons.bar_chart_rounded,
              title: text(zh: '模型平均耗时', en: 'Avg by Model'),
              empty: models.isEmpty,
              emptyLabel: emptyChart,
              chart: OpenHandOperationalComparisonBars(
                orientation: OpenHandComparisonBarOrientation.vertical,
                valueLabel: (segment) => '${segment.value.round()}ms',
                segments: [
                  for (var i = 0; i < models.length && i < 8; i++)
                    OpenHandChartSegment(
                      label: models[i].label,
                      value: models[i].avgMs,
                      color: palette[i % palette.length],
                      valueLabel: '${models[i].avgMs}ms',
                    ),
                ],
              ),
            ),
            _ProxyOpsTrendDetailPanel(
              icon: Icons.show_chart_rounded,
              title: text(zh: '均值曲线', en: 'Mean Curve'),
              subtitle: text(zh: '每分钟平均耗时', en: 'Average latency per minute'),
              series: [
                OpenHandChartSeries(
                  label: text(zh: '平均', en: 'Average'),
                  values: data.averageLatencyBuckets,
                  color: cs.primary,
                ),
              ],
              minutes: data.bucketMinutes,
              valueSuffix: 'ms',
              emptyLabel: text(zh: '暂无耗时样本', en: 'No latency samples'),
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.p95Latency:
      return _ProxyOpsInsightSpec(
        icon: Icons.timelapse_rounded,
        title: text(zh: 'P95 尾延迟', en: 'P95 Latency'),
        subtitle: text(
          zh: '尾部分位、p95 曲线与最慢调用',
          en: 'Tail percentiles, p95 curve and slowest calls',
        ),
        sections: (context, data) {
          final slowest = [...data.records]
            ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
          final cap = math.max(
            data.maxLatencyMs,
            math.max(data.p95LatencyMs, 1),
          );
          return [
            _proxyOpsPanelRow([
              _ProxyOpsPanel(
                icon: Icons.timelapse_rounded,
                title: text(zh: 'p95 仪表', en: 'p95 Gauge'),
                child: _ProxyOpsInsightMetricGrid(
                  children: [
                    _proxyOpsRateMeter(
                      label: 'p95 / max',
                      rate: data.p95LatencyMs / cap,
                      color: cs.tertiary,
                      helper: '${data.p95LatencyMs}ms / ${data.maxLatencyMs}ms',
                    ),
                  ],
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.straighten_rounded,
                title: text(zh: '尾部分位', en: 'Tail Percentiles'),
                empty: data.maxLatencyMs <= 0,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalLatencyRange(
                  segments: [
                    OpenHandChartSegment(
                      label: 'p50',
                      value: data.p50LatencyMs,
                      color: cs.secondary,
                      valueLabel: '${data.p50LatencyMs}ms',
                    ),
                    OpenHandChartSegment(
                      label: 'p95',
                      value: data.p95LatencyMs,
                      color: cs.tertiary,
                      valueLabel: '${data.p95LatencyMs}ms',
                    ),
                    OpenHandChartSegment(
                      label: 'p99',
                      value: data.p99LatencyMs,
                      color: OpenHandStatusColors.warning,
                      valueLabel: '${data.p99LatencyMs}ms',
                    ),
                    OpenHandChartSegment(
                      label: 'max',
                      value: data.maxLatencyMs,
                      color: cs.error,
                      valueLabel: '${data.maxLatencyMs}ms',
                    ),
                  ],
                ),
              ),
            ]),
            _ProxyOpsTrendDetailPanel(
              icon: Icons.show_chart_rounded,
              title: text(zh: 'p95 曲线', en: 'p95 Curve'),
              subtitle: text(zh: '每分钟尾延迟', en: 'Tail latency per minute'),
              series: [
                OpenHandChartSeries(
                  label: 'p95',
                  values: data.p95LatencyBuckets,
                  aggregation: OpenHandTrendAggregation.maximum,
                  color: cs.tertiary,
                ),
              ],
              minutes: data.bucketMinutes,
              valueSuffix: 'ms',
              emptyLabel: text(zh: '暂无耗时样本', en: 'No latency samples'),
            ),
            _proxyOpsChartPanel(
              icon: Icons.trending_down_rounded,
              title: text(zh: '最慢调用', en: 'Slowest Calls'),
              empty: slowest.every((record) => record.durationMs <= 0),
              emptyLabel: text(zh: '暂无耗时样本', en: 'No latency samples'),
              chart: _proxyOpsTraceTable(
                context: context,
                data: data,
                records: slowest
                    .where((record) => record.durationMs > 0)
                    .toList(growable: false),
                emptyLabel: text(zh: '暂无耗时样本', en: 'No latency samples'),
                showError: true,
              ),
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.tokens:
      return _ProxyOpsInsightSpec(
        icon: Icons.token_rounded,
        title: text(zh: 'Token 消耗', en: 'Token Usage'),
        sections: (context, data) {
          final avg = data.avgTokensPerRequest;
          final scale = math.max(avg * 2, math.max(data.maxTokens, 1));
          final providers = data.groupBy(
            (record) => data.providerLabelFor(record, unknown: unknownProvider),
            unknown: unknownProvider,
          );
          return [
            _ProxyOpsPanel(
              icon: Icons.token_rounded,
              title: text(zh: '消耗仪表', en: 'Usage Gauge'),
              child: _ProxyOpsInsightMetricGrid(
                children: [
                  _proxyOpsCountMeter(
                    label: text(zh: '单请求均值', en: 'Avg / request'),
                    value: avg,
                    maximum: scale,
                    color: cs.primary,
                    helper: text(
                      zh: '累计 ${data.settings.totalTokens}',
                      en: 'Total ${data.settings.totalTokens}',
                    ),
                  ),
                ],
              ),
            ),
            _ProxyOpsTrendDetailPanel(
              icon: Icons.show_chart_rounded,
              title: text(zh: 'Token 曲线', en: 'Token Curve'),
              subtitle: text(zh: '每分钟 Token 合计', en: 'Tokens per minute'),
              series: [
                OpenHandChartSeries(
                  label: 'Token',
                  values: data.tokenBuckets,
                  aggregation: OpenHandTrendAggregation.sum,
                  color: cs.tertiary,
                ),
              ],
              minutes: data.bucketMinutes,
              emptyLabel: text(zh: '暂无 Token 样本', en: 'No token samples'),
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.leaderboard_rounded,
              title: text(zh: '提供商 Token 排行', en: 'Tokens by Provider'),
              groups: providers,
              leadingHeader: text(zh: '提供商', en: 'Provider'),
              emptyLabel: emptyChart,
              valueOf: (group) => group.tokens,
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.inbound:
      return _ProxyOpsInsightSpec(
        icon: Icons.south_west_rounded,
        title: text(zh: '入口流量', en: 'Inbound Traffic'),
        subtitle: text(
          zh: '请求体趋势、占比与进出口对照',
          en: 'Request-body trend, share and in/out contrast',
        ),
        sections: (context, data) {
          final inbound = data.controller.runtimeInboundBytes;
          final outbound = data.controller.runtimeOutboundBytes;
          final total = inbound + outbound;
          final count = data.controller.runtimeRequestCount;
          final avg = count <= 0 ? 0 : inbound ~/ count;
          final inboundTrend = _proxyOpsScaledByteTrend(
            data.inboundByteBuckets,
          );
          return [
            _ProxyOpsStatPanel(
              icon: Icons.swap_vert_rounded,
              title: text(zh: '入口字节', en: 'Inbound Bytes'),
              tiles: [
                _proxyOpsInsightTile(
                  context,
                  Icons.south_west_rounded,
                  text(zh: '入口总量', en: 'Inbound'),
                  formatByteSize(inbound),
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.straighten_rounded,
                  text(zh: '平均每请求', en: 'Per request'),
                  formatByteSize(avg),
                ),
              ],
            ),
            _ProxyOpsTrendDetailPanel(
              icon: Icons.show_chart_rounded,
              title: text(zh: '入口流量趋势', en: 'Inbound Traffic Trend'),
              subtitle: text(
                zh: '每分钟请求字节 · 遥测持久化留存',
                en: 'Request bytes per minute · persisted telemetry',
              ),
              series: [
                OpenHandChartSeries(
                  label: text(zh: '入口', en: 'Inbound'),
                  values: inboundTrend.values,
                  aggregation: OpenHandTrendAggregation.sum,
                  color: cs.secondary,
                ),
              ],
              minutes: data.bucketMinutes,
              valueSuffix: inboundTrend.suffix,
              emptyLabel: text(zh: '暂无入口流量', en: 'No inbound traffic'),
            ),
            _proxyOpsPanelRow([
              _ProxyOpsPanel(
                icon: Icons.pie_chart_rounded,
                title: text(zh: '入口占比仪表', en: 'Inbound Share'),
                child: _ProxyOpsInsightMetricGrid(
                  children: [
                    _proxyOpsRateMeter(
                      label: text(zh: '入口 / 总流量', en: 'Inbound / total'),
                      rate: total <= 0 ? 0 : inbound / total,
                      color: cs.secondary,
                      helper: formatByteSize(inbound),
                      unavailable: total <= 0,
                    ),
                  ],
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.stacked_bar_chart_rounded,
                title: text(zh: '进出口对照', en: 'In / Out Contrast'),
                empty: total <= 0,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalStatusBand(
                  segments: [
                    OpenHandChartSegment(
                      label: text(zh: '入口', en: 'In'),
                      value: inbound,
                      color: cs.secondary,
                      icon: Icons.south_west_rounded,
                      valueLabel: formatByteSize(inbound),
                    ),
                    OpenHandChartSegment(
                      label: text(zh: '出口', en: 'Out'),
                      value: outbound,
                      color: cs.tertiary,
                      icon: Icons.north_east_rounded,
                      valueLabel: formatByteSize(outbound),
                    ),
                  ],
                ),
              ),
            ]),
          ];
        },
      );

    case _ProxyOpsInsightKind.outbound:
      return _ProxyOpsInsightSpec(
        icon: Icons.north_east_rounded,
        title: text(zh: '出口流量', en: 'Outbound Traffic'),
        subtitle: text(
          zh: '响应体趋势与上游端点排行',
          en: 'Response-body trend and upstream endpoints',
        ),
        sections: (context, data) {
          final outbound = data.controller.runtimeOutboundBytes;
          final count = data.controller.runtimeRequestCount;
          final avg = count <= 0 ? 0 : outbound ~/ count;
          final outboundTrend = _proxyOpsScaledByteTrend(
            data.outboundByteBuckets,
          );
          final upstream = data.groupBy(
            (record) => _proxyOpsUpstreamEndpoint(record, unknownUpstream),
            unknown: unknownUpstream,
          );
          return [
            _ProxyOpsStatPanel(
              icon: Icons.swap_vert_rounded,
              title: text(zh: '出口字节', en: 'Outbound Bytes'),
              tiles: [
                _proxyOpsInsightTile(
                  context,
                  Icons.north_east_rounded,
                  text(zh: '出口总量', en: 'Outbound'),
                  formatByteSize(outbound),
                  color: cs.tertiary,
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.straighten_rounded,
                  text(zh: '平均每请求', en: 'Per request'),
                  formatByteSize(avg),
                  color: cs.tertiary,
                ),
              ],
            ),
            _ProxyOpsTrendDetailPanel(
              icon: Icons.show_chart_rounded,
              title: text(zh: '出口流量趋势', en: 'Outbound Traffic Trend'),
              subtitle: text(
                zh: '每分钟响应字节 · 遥测持久化留存',
                en: 'Response bytes per minute · persisted telemetry',
              ),
              series: [
                OpenHandChartSeries(
                  label: text(zh: '出口', en: 'Outbound'),
                  values: outboundTrend.values,
                  aggregation: OpenHandTrendAggregation.sum,
                  color: cs.tertiary,
                ),
              ],
              minutes: data.bucketMinutes,
              valueSuffix: outboundTrend.suffix,
              emptyLabel: text(zh: '暂无出口流量', en: 'No outbound traffic'),
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.leaderboard_rounded,
              title: text(zh: '上游端点排行', en: 'Upstream Endpoints'),
              groups: upstream,
              leadingHeader: text(zh: '上游', en: 'Upstream'),
              emptyLabel: emptyChart,
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.exposedModels:
      return _ProxyOpsInsightSpec(
        icon: Icons.hub_rounded,
        title: text(zh: '启用模型', en: 'Exposed Models'),
        sections: (context, data) {
          final enabled = data.enabledRouteCount;
          final disabled = math.max(0, data.settings.routes.length - enabled);
          final usageByExposed = <String, _ProxyOpsGroupStat>{
            for (final group in data.groupBy((record) {
              if (isAiModelProxyStatusRecord(record)) {
                return openHandAmbientText(zh: '状态页', en: 'Status page');
              }
              final exposed = record.exposedModel.trim();
              return exposed.isEmpty ? record.modelId : exposed;
            }, unknown: unknownModel))
              group.label: group,
          };
          final heat = [
            for (final route in data.settings.routes)
              () {
                final usage = usageByExposed[route.exposedModel];
                final enabledBackends = route.backends
                    .where((backend) => backend.enabled)
                    .length;
                return OpenHandChartSegment(
                  label: route.exposedModel,
                  value: route.backends.length,
                  color: route.enabled ? success : cs.onSurfaceVariant,
                  valueLabel: '${route.backends.length}',
                  tooltip: OpenHandChartTooltip(
                    title: route.exposedModel,
                    subtitle: text(
                      zh: '对外暴露模型的后备规模',
                      en: 'Backend footprint of this exposed model',
                    ),
                    badge: route.enabled
                        ? text(zh: '已启用', en: 'Enabled')
                        : text(zh: '已停用', en: 'Disabled'),
                    badgeColor: route.enabled ? success : cs.onSurfaceVariant,
                    summary: route.enabled
                        ? text(
                            zh: '该对外模型当前启用，挂了 ${route.backends.length} 个后备（其中 $enabledBackends 个启用）。颜色来自启用状态，深浅来自后备数量。',
                            en: 'This exposed model is enabled with ${route.backends.length} backends ($enabledBackends on). Color is enablement; depth is footprint.',
                          )
                        : text(
                            zh: '该对外模型当前停用，仍保留 ${route.backends.length} 个后备配置，不会承接新流量。',
                            en: 'This exposed model is disabled. It still has ${route.backends.length} backends configured but will not take new traffic.',
                          ),
                    metrics: [
                      OpenHandChartTooltipMetric(
                        label: text(zh: '后备总数', en: 'Backends'),
                        value: '${route.backends.length}',
                        icon: Icons.storage_rounded,
                        color: route.enabled ? success : cs.onSurfaceVariant,
                      ),
                      OpenHandChartTooltipMetric(
                        label: text(zh: '启用后备', en: 'Enabled backends'),
                        value: '$enabledBackends',
                        icon: Icons.check_circle_outline_rounded,
                        color: success,
                      ),
                      OpenHandChartTooltipMetric(
                        label: text(zh: '近窗请求', en: 'Window requests'),
                        value: '${usage?.requests ?? 0}',
                        icon: Icons.call_made_rounded,
                        color: cs.primary,
                      ),
                      OpenHandChartTooltipMetric(
                        label: text(zh: '成功率', en: 'Success'),
                        value: usage == null
                            ? '—'
                            : _proxyOpsPercentLabel(usage.successRate),
                        icon: Icons.verified_rounded,
                        color: success,
                      ),
                      OpenHandChartTooltipMetric(
                        label: 'Token',
                        value: '${usage?.tokens ?? 0}',
                        icon: Icons.token_rounded,
                        color: cs.tertiary,
                      ),
                      OpenHandChartTooltipMetric(
                        label: text(zh: '均耗时', en: 'Avg'),
                        value: usage == null
                            ? '—'
                            : _proxyOpsDurationLabel(usage.avgMs),
                        icon: Icons.timer_outlined,
                        color: cs.primary,
                      ),
                    ],
                    notes: [
                      text(
                        zh: '此图描述路由配置规模，不是调用热度。调用次数请看「模型分布」。',
                        en: 'This strip is routing footprint, not call heat. Call volume is on Model Mix.',
                      ),
                      if (usage?.lastAt case final latest?)
                        text(
                          zh: '最近一次调用 ${formatListDateTime(latest)}',
                          en: 'Last call ${formatListDateTime(latest)}',
                        ),
                    ],
                  ),
                );
              }(),
          ];
          return [
            _proxyOpsPanelRow([
              _proxyOpsChartPanel(
                icon: Icons.donut_small_rounded,
                title: text(zh: '启用构成', en: 'Enablement Mix'),
                empty: data.settings.routes.isEmpty,
                emptyLabel: text(zh: '暂无注册模型', en: 'No models registered'),
                chart: _proxyOpsDonut(
                  cs: cs,
                  segments: [
                    if (enabled > 0)
                      OpenHandChartSegment(
                        label: text(zh: '启用', en: 'Enabled'),
                        value: enabled,
                        color: success,
                        valueLabel: '$enabled',
                      ),
                    if (disabled > 0)
                      OpenHandChartSegment(
                        label: text(zh: '停用', en: 'Disabled'),
                        value: disabled,
                        color: cs.onSurfaceVariant,
                        valueLabel: '$disabled',
                      ),
                  ],
                  centerLabel: '${data.settings.routes.length}',
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.view_week_rounded,
                title: text(zh: '后备规模热力', en: 'Backend Footprint'),
                empty: heat.isEmpty,
                emptyLabel: emptyChart,
                subtitle: text(
                  zh: '色块表示启用状态，深度表示后备数量',
                  en: 'Hue is enablement; depth is backend count',
                ),
                chart: OpenHandOperationalHeatmap(
                  segments: heat,
                  color: cs.primary,
                ),
              ),
            ]),
            _proxyOpsRankTablePanel(
              icon: Icons.list_alt_rounded,
              title: text(zh: '模型列表', en: 'Model List'),
              empty: data.settings.routes.isEmpty,
              emptyLabel: text(zh: '暂无注册模型', en: 'No models registered'),
              sortByValue: false,
              headers: [
                text(zh: '模型', en: 'Model'),
                text(zh: '状态', en: 'Status'),
                text(zh: '后备', en: 'Backends'),
                text(zh: '请求', en: 'Requests'),
                text(zh: '成功率', en: 'Success'),
                'Token',
                text(zh: '均耗时', en: 'Avg'),
                text(zh: '最近', en: 'Latest'),
              ],
              rows: [
                for (final route in data.settings.routes)
                  _proxyOpsExposedModelRankRow(
                    context: context,
                    route: route,
                    usageByExposed: usageByExposed,
                  ),
              ],
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.backends:
      return _ProxyOpsInsightSpec(
        icon: Icons.storage_rounded,
        title: text(zh: '后备模型', en: 'Backends'),
        sections: (context, data) {
          final perRoute = [
            for (var i = 0; i < data.settings.routes.length; i++)
              OpenHandChartSegment(
                label: data.settings.routes[i].exposedModel,
                value: data.settings.routes[i].backends
                    .where((backend) => backend.enabled)
                    .length,
                color: palette[i % palette.length],
              ),
          ].where((segment) => segment.safeValue > 0).toList(growable: false);
          final usageByBackend = <String, _ProxyOpsGroupStat>{
            for (final group in data.groupBy(
              (record) =>
                  '${record.providerId.trim()}\u0000${record.modelId.trim()}',
              unknown: unknownModel,
            ))
              group.label: group,
          };
          return [
            _proxyOpsPanelRow([
              _ProxyOpsDetailSection(
                icon: Icons.tune_rounded,
                title: text(zh: '调度与重试', en: 'Routing Policy'),
                rows: {
                  text(
                    zh: '调度策略',
                    en: 'Scheduling',
                  ): aiModelProxySchedulingLabel(
                    data.settings.scheduling,
                    text,
                  ),
                  text(zh: '重试策略', en: 'Retry'): aiModelProxyRetryPolicyLabel(
                    data.settings.retryPolicy,
                    text,
                  ),
                  text(zh: '重试次数', en: 'Retries'):
                      '${data.settings.retryCount}',
                  data.settings.limitMode.label:
                      '${data.settings.limitThreshold}',
                },
              ),
              _proxyOpsChartPanel(
                icon: Icons.bar_chart_rounded,
                title: text(zh: '各模型启用后备', en: 'Enabled Backends / Route'),
                empty: perRoute.isEmpty,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalComparisonBars(
                  segments: perRoute,
                  orientation: OpenHandComparisonBarOrientation.vertical,
                  valueLabel: (segment) => '${segment.value.round()}',
                ),
              ),
            ]),
            _proxyOpsRankTablePanel(
              icon: Icons.list_alt_rounded,
              title: text(zh: '后备列表', en: 'Backend List'),
              empty: data.settings.routes.every(
                (route) => route.backends.isEmpty,
              ),
              emptyLabel: text(zh: '暂无后备模型', en: 'No backends'),
              sortByValue: false,
              headers: [
                text(zh: '后备', en: 'Backend'),
                text(zh: '暴露模型', en: 'Exposed'),
                text(zh: '状态', en: 'Status'),
                text(zh: '请求', en: 'Requests'),
                text(zh: '成功率', en: 'Success'),
                'Token',
                text(zh: '均耗时', en: 'Avg'),
                text(zh: '最近', en: 'Latest'),
              ],
              rows: [
                for (final route in data.settings.routes)
                  for (final backend in route.backends)
                    _proxyOpsBackendRankRow(
                      context: context,
                      data: data,
                      route: route,
                      backend: backend,
                      usageByBackend: usageByBackend,
                    ),
              ],
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.requestTrend:
      return _ProxyOpsInsightSpec(
        icon: Icons.show_chart_rounded,
        title: text(zh: '请求趋势', en: 'Request Trend'),
        subtitle: text(
          zh: '窗口脉搏、突发分钟与流式占比',
          en: 'Window pulse, burst minutes and stream share',
        ),
        sections: (context, data) {
          final window = data.windowRecords;
          final windowOk = window.where((record) => record.success).length;
          final throughput = data.recentThroughputBuckets;
          final peak = throughput.fold<double>(
            0,
            (max, value) => math.max(max, value),
          );
          var quiet = 0;
          var peakIndex = 0;
          for (var i = 0; i < throughput.length; i++) {
            if (throughput[i] <= 0) quiet += 1;
            if (throughput[i] >= throughput[peakIndex]) {
              peakIndex = i;
            }
          }
          final minutes = data.recentBucketMinutes;
          final successBuckets = data.recentTrendSuccess;
          final failureBuckets = data.recentTrendFailure;
          final burstSegments = <OpenHandChartSegment>[];
          for (var i = 0; i < minutes.length; i++) {
            final ok = i < successBuckets.length ? successBuckets[i] : 0.0;
            final fail = i < failureBuckets.length ? failureBuckets[i] : 0.0;
            final total = ok + fail;
            if (total <= 0) continue;
            burstSegments.add(
              OpenHandChartSegment(
                label: formatHourMinuteLocal(minutes[i]),
                value: total,
                color: fail > 0 ? cs.error : success,
                valueLabel: '${total.round()}',
              ),
            );
          }
          burstSegments.sort((a, b) => b.safeValue.compareTo(a.safeValue));
          final streamGroups = data.groupBy(
            (record) => record.stream
                ? text(zh: '流式', en: 'Stream')
                : text(zh: '一次性', en: 'Unary'),
            unknown: unknown,
            source: window,
          );
          return [
            _ProxyOpsStatPanel(
              icon: Icons.monitor_heart_rounded,
              title: text(zh: '窗口脉搏', en: 'Window Pulse'),
              tiles: [
                _proxyOpsInsightTile(
                  context,
                  Icons.call_made_rounded,
                  text(zh: '窗口请求', en: 'Window'),
                  '${data.windowRequestCount}',
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.speed_rounded,
                  text(zh: '峰值分钟', en: 'Peak minute'),
                  '${peak.round()}',
                  helper: minutes.isEmpty
                      ? ''
                      : formatHourMinuteLocal(minutes[peakIndex]),
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.hourglass_empty_rounded,
                  text(zh: '静默分钟', en: 'Quiet minutes'),
                  '$quiet',
                  helper: text(
                    zh: '/ $_kProxyOpsTrendBuckets',
                    en: '/ $_kProxyOpsTrendBuckets',
                  ),
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.verified_rounded,
                  text(zh: '窗口成功率', en: 'Window success'),
                  window.isEmpty
                      ? '—'
                      : _proxyOpsPercentLabel(windowOk / window.length),
                  color: _proxyOpsHealthColor(
                    cs,
                    window.isEmpty ? 0 : windowOk / window.length,
                  ),
                ),
              ],
            ),
            _proxyOpsRequestTrendPanel(context, data),
            _proxyOpsChartPanel(
              icon: Icons.stream_rounded,
              title: text(zh: '窗口投递形态', en: 'Delivery Shape'),
              empty: streamGroups.isEmpty,
              emptyLabel: emptyChart,
              chart: OpenHandOperationalComparisonBars(
                orientation: OpenHandComparisonBarOrientation.vertical,
                valueLabel: (segment) => '${segment.value.round()}',
                segments: [
                  for (var i = 0; i < streamGroups.length; i++)
                    OpenHandChartSegment(
                      label: streamGroups[i].label,
                      value: streamGroups[i].requests,
                      color: palette[i % palette.length],
                      valueLabel: '${streamGroups[i].requests}',
                    ),
                ],
              ),
            ),
            _proxyOpsChartPanel(
              icon: Icons.bolt_rounded,
              title: text(zh: '突发分钟', en: 'Burst Minutes'),
              empty: burstSegments.isEmpty,
              emptyLabel: emptyChart,
              subtitle: text(zh: '按请求量从高到低', en: 'Ranked by request volume'),
              chart: OpenHandOperationalComparisonBars(
                orientation: OpenHandComparisonBarOrientation.horizontal,
                emptyLabel: emptyChart,
                segments: burstSegments,
              ),
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.latencyTrend:
      return _ProxyOpsInsightSpec(
        icon: Icons.timeline_rounded,
        title: text(zh: '耗时曲线', en: 'Latency Curve'),
        subtitle: text(
          zh: '窗口抖动、降级分钟与小时尾延迟',
          en: 'Jitter, degraded minutes and hourly tail',
        ),
        sections: (context, data) {
          final window = data.windowRecords;
          final windowDurations = [
            for (final record in window)
              if (record.durationMs > 0) record.durationMs,
          ];
          final windowAvg = windowDurations.isEmpty
              ? 0
              : (windowDurations.reduce((a, b) => a + b) /
                        windowDurations.length)
                    .round();
          final windowP95 = _proxyOpsPercentile(windowDurations, 0.95);
          final activeAvg = [
            for (final value in data.recentAverageLatencyBuckets)
              if (value > 0) value,
          ];
          final jitter = activeAvg.length < 2
              ? 0
              : (activeAvg.reduce(math.max) - activeAvg.reduce(math.min))
                    .round();
          final slow = window
              .where((record) => record.durationMs >= _kProxyOpsSlowLatencyMs)
              .length;
          final fast = text(zh: '快速 < 1s', en: 'Fast < 1s');
          final normal = text(zh: '正常 1-3s', en: 'Normal 1-3s');
          final slowLabel = text(zh: '慢速 ≥ 3s', en: 'Slow ≥ 3s');
          final bands = _proxyOpsSegments(
            data.countBy(
              (record) {
                if (record.durationMs < _kProxyOpsFastLatencyMs) return fast;
                if (record.durationMs < _kProxyOpsSlowLatencyMs) return normal;
                return slowLabel;
              },
              unknown: unknown,
              source: window,
            ),
            [success, cs.primary, OpenHandStatusColors.warning],
          );
          final minutes = data.recentBucketMinutes;
          final recentAverage = data.recentAverageLatencyBuckets;
          final recentP95 = data.recentP95LatencyBuckets;
          final degradedLabels = <String>[];
          final degradedAvg = <double>[];
          final degradedP95 = <double>[];
          for (var i = 0; i < minutes.length; i++) {
            if (i >= recentP95.length ||
                recentP95[i] < _kProxyOpsSlowLatencyMs) {
              continue;
            }
            degradedLabels.add(formatHourMinuteLocal(minutes[i]));
            degradedAvg.add(i < recentAverage.length ? recentAverage[i] : 0);
            degradedP95.add(recentP95[i]);
          }
          final hourP95 = _proxyOpsHourSegments(
            data.hourStats,
            cs.tertiary,
            valueOf: (hour) => hour.p95Ms,
            valueLabelOf: (hour) => _proxyOpsDurationLabel(hour.p95Ms),
            tooltipOf: (hour) => _proxyOpsHourVolumeTooltip(
              text: text,
              hour: hour,
              tone: cs.tertiary,
              badge: hour.requests <= 0
                  ? text(zh: '无样本', en: 'No samples')
                  : 'P95 ${_proxyOpsDurationLabel(hour.p95Ms)}',
              subtitle: text(zh: '该整点尾延迟', en: 'Tail latency this clock hour'),
              summary: hour.requests <= 0
                  ? text(
                      zh: '这一小时没有耗时样本，P95 无法计算。浅色格表示空闲，不是延迟为 0。',
                      en: 'No latency samples this hour, so P95 is undefined. A pale cell is idle, not 0 ms.',
                    )
                  : text(
                      zh: '这一小时 ${hour.requests} 次请求，平均 ${_proxyOpsDurationLabel(hour.avgMs)}，P95 ${_proxyOpsDurationLabel(hour.p95Ms)}，最慢 ${_proxyOpsDurationLabel(hour.maxMs)}。颜色越深表示尾延迟越高。',
                      en: '${hour.requests} requests this hour, avg ${_proxyOpsDurationLabel(hour.avgMs)}, P95 ${_proxyOpsDurationLabel(hour.p95Ms)}, max ${_proxyOpsDurationLabel(hour.maxMs)}. Darker means a slower tail.',
                    ),
              notes: [
                text(
                  zh: '此图看的是延迟高低，不是成功率。绿黄红健康请看「请求总览」底部的时段健康条。',
                  en: 'This strip is latency, not success. Green/yellow/red health is on the Requests dialog.',
                ),
                if (hour.slowCount > 0)
                  text(
                    zh: '其中 ${hour.slowCount} 次耗时 ≥ 3s。',
                    en: '${hour.slowCount} calls took 3s or more.',
                  ),
              ],
              dayRequests: data.records.length,
            ),
          );
          return [
            _ProxyOpsStatPanel(
              icon: Icons.speed_rounded,
              title: text(zh: '窗口时延', en: 'Window Latency'),
              tiles: [
                _proxyOpsInsightTile(
                  context,
                  Icons.timer_rounded,
                  text(zh: '窗口均耗时', en: 'Window avg'),
                  _proxyOpsDurationLabel(windowAvg),
                  color: cs.primary,
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.timelapse_rounded,
                  'P95',
                  _proxyOpsDurationLabel(windowP95),
                  color: cs.tertiary,
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.graphic_eq_rounded,
                  text(zh: '抖动', en: 'Jitter'),
                  _proxyOpsDurationLabel(jitter),
                  helper: text(zh: '均线峰谷差', en: 'Peak-trough of mean'),
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.warning_amber_rounded,
                  text(zh: '慢请求', en: 'Slow calls'),
                  window.isEmpty
                      ? '—'
                      : _proxyOpsPercentLabel(slow / window.length),
                  helper: '$slow / ${window.length}',
                  color: OpenHandStatusColors.warning,
                ),
              ],
            ),
            _proxyOpsLatencyOverlayPanel(context, data),
            _proxyOpsChartPanel(
              icon: Icons.stacked_bar_chart_rounded,
              title: text(zh: '窗口耗时带', en: 'Window Latency Bands'),
              empty: bands.isEmpty,
              emptyLabel: emptyChart,
              chart: OpenHandOperationalComparisonBars(
                orientation: OpenHandComparisonBarOrientation.vertical,
                valueLabel: (segment) => '${segment.value.round()}',
                segments: bands,
              ),
            ),
            _proxyOpsChartPanel(
              icon: Icons.report_rounded,
              title: text(zh: '降级分钟', en: 'Degraded Minutes'),
              empty: degradedLabels.isEmpty,
              emptyLabel: text(
                zh: '窗口内无 P95 ≥ 3s',
                en: 'No P95 ≥ 3s in window',
              ),
              subtitle: text(
                zh: '仅列出 P95 ≥ 3s 的分钟',
                en: 'Minutes whose P95 is at least 3s',
              ),
              chart: OpenHandOperationalTrendLanes(
                series: [
                  OpenHandChartSeries(
                    label: text(zh: '平均', en: 'Average'),
                    values: degradedAvg,
                    color: cs.primary,
                  ),
                  OpenHandChartSeries(
                    label: 'P95',
                    values: degradedP95,
                    color: cs.tertiary,
                  ),
                ],
                xLabels: degradedLabels,
                formatValue: (value) => _proxyOpsDurationLabel(value.round()),
              ),
            ),
            _proxyOpsChartPanel(
              icon: Icons.view_week_rounded,
              title: text(zh: '小时 P95 热力', en: 'Hourly P95 Heat'),
              empty: false,
              emptyLabel: emptyChart,
              subtitle: text(
                zh: '颜色深度表示该整点 P95 尾延迟',
                en: 'Color depth is P95 tail latency that clock hour',
              ),
              chart: OpenHandOperationalHeatmap(
                keepIdleCells: true,
                segments: hourP95,
                color: cs.tertiary,
              ),
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.statusMix:
      return _ProxyOpsInsightSpec(
        icon: Icons.donut_small_rounded,
        title: text(zh: '状态分布', en: 'Status Mix'),
        subtitle: text(
          zh: 'HTTP 族、重试结果与状态码排行',
          en: 'HTTP class, retries and status ranks',
        ),
        sections: (context, data) {
          final unknownStatus = text(zh: '无状态码', en: 'No status');
          final segments = <OpenHandChartSegment>[
            if (data.successTotal > 0)
              OpenHandChartSegment(
                label: text(zh: '成功', en: 'Success'),
                value: data.successTotal,
                color: success,
                icon: Icons.task_alt_rounded,
                valueLabel: '${data.successRateLabel}%',
              ),
            if (data.failureTotal > 0)
              OpenHandChartSegment(
                label: text(zh: '失败', en: 'Failed'),
                value: data.failureTotal,
                color: cs.error,
                icon: Icons.error_outline_rounded,
                valueLabel: '${data.failureRateLabel}%',
              ),
          ];
          String familyOf(int code) {
            if (code <= 0) return unknownStatus;
            if (code < 300) return '2xx';
            if (code < 400) return '3xx';
            if (code < 500) return '4xx';
            return '5xx';
          }

          final families = _proxyOpsSegments(
            data.countBy(
              (record) => familyOf(record.statusCode),
              unknown: unknownStatus,
            ),
            [success, cs.tertiary, OpenHandStatusColors.warning, cs.error],
          );
          final once = text(zh: '一次成功', en: 'First-try OK');
          final retried = text(zh: '重试成功', en: 'Retry OK');
          final failed = text(zh: '最终失败', en: 'Failed');
          final attempts = _proxyOpsSegments(
            data.countBy((record) {
              if (!record.success) return failed;
              return record.attempt > 1 ? retried : once;
            }, unknown: unknown),
            [success, cs.tertiary, cs.error],
          );
          final codes = data.groupBy(
            (record) =>
                record.statusCode <= 0 ? unknownStatus : '${record.statusCode}',
            unknown: unknownStatus,
          );
          final streamed = data.records.where((record) => record.stream).length;
          final retriedCount = data.records
              .where((record) => record.attempt > 1)
              .length;
          return [
            _ProxyOpsStatPanel(
              icon: Icons.flag_rounded,
              title: text(zh: '结果构成', en: 'Outcome Mix'),
              tiles: [
                _proxyOpsInsightTile(
                  context,
                  Icons.task_alt_rounded,
                  text(zh: '成功', en: 'Succeeded'),
                  '${data.successTotal}',
                  helper: '${data.successRateLabel}%',
                  color: success,
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.error_outline_rounded,
                  text(zh: '失败', en: 'Failed'),
                  '${data.failureTotal}',
                  helper: '${data.failureRateLabel}%',
                  color: cs.error,
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.stream_rounded,
                  text(zh: '流式请求', en: 'Streaming'),
                  '$streamed',
                  helper: data.records.isEmpty
                      ? ''
                      : _proxyOpsPercentLabel(streamed / data.records.length),
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.replay_rounded,
                  text(zh: '发生重试', en: 'Retried'),
                  '$retriedCount',
                  helper: data.records.isEmpty
                      ? ''
                      : _proxyOpsPercentLabel(
                          retriedCount / data.records.length,
                        ),
                  color: cs.tertiary,
                ),
              ],
            ),
            _proxyOpsPanelRow([
              _proxyOpsChartPanel(
                icon: Icons.donut_small_rounded,
                title: text(zh: '状态环图', en: 'Status Donut'),
                empty: segments.isEmpty,
                emptyLabel: emptyChart,
                chart: _proxyOpsDonut(
                  cs: cs,
                  segments: segments,
                  centerLabel: '${data.requestTotal}',
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.http_rounded,
                title: text(zh: 'HTTP 族', en: 'HTTP Class'),
                empty: families.isEmpty,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalComparisonBars(
                  orientation: OpenHandComparisonBarOrientation.vertical,
                  valueLabel: (segment) => '${segment.value.round()}',
                  segments: families,
                ),
              ),
            ]),
            _proxyOpsChartPanel(
              icon: Icons.stacked_bar_chart_rounded,
              title: text(zh: '重试结果', en: 'Retry Outcome'),
              empty: attempts.isEmpty,
              emptyLabel: emptyChart,
              chart: OpenHandOperationalStatusBand(segments: attempts),
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.tag_rounded,
              title: text(zh: '状态码排行', en: 'Status Codes'),
              groups: codes,
              leadingHeader: text(zh: '状态码', en: 'Status'),
              emptyLabel: emptyChart,
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.providerMix:
      return _ProxyOpsInsightSpec(
        icon: Icons.hub_outlined,
        title: text(zh: '提供商分布', en: 'Provider Mix'),
        subtitle: text(
          zh: '份额、上游时延与出口字节',
          en: 'Share, upstream latency and outbound bytes',
        ),
        sections: (context, data) {
          final groups = data.groupBy(
            (record) => data.providerLabelFor(record, unknown: unknownProvider),
            unknown: unknownProvider,
          );
          final segments = [
            for (var i = 0; i < groups.length; i++)
              OpenHandChartSegment(
                label: groups[i].label,
                value: groups[i].requests,
                color: palette[i % palette.length],
                valueLabel: '${groups[i].requests}',
              ),
          ];
          final latencyBars = [
            for (var i = 0; i < groups.length && i < 8; i++)
              OpenHandChartSegment(
                label: groups[i].label,
                value: groups[i].avgMs,
                color: palette[i % palette.length],
                valueLabel: _proxyOpsDurationLabel(groups[i].avgMs),
              ),
          ];
          final byteBars = [
            for (var i = 0; i < groups.length && i < 8; i++)
              OpenHandChartSegment(
                label: groups[i].label,
                value: groups[i].outboundBytes,
                color: palette[i % palette.length],
                valueLabel: formatByteSize(groups[i].outboundBytes),
              ),
          ];
          return [
            _proxyOpsPanelRow([
              _proxyOpsChartPanel(
                icon: Icons.donut_small_rounded,
                title: text(zh: '提供商环图', en: 'Provider Donut'),
                empty: segments.isEmpty,
                emptyLabel: emptyChart,
                chart: _proxyOpsDonut(
                  cs: cs,
                  segments: segments,
                  centerLabel:
                      '${groups.fold<int>(0, (sum, item) => sum + item.requests)}',
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.timer_rounded,
                title: text(zh: '提供商均耗时', en: 'Avg by Provider'),
                empty: latencyBars.every((segment) => segment.safeValue <= 0),
                emptyLabel: emptyChart,
                chart: OpenHandOperationalComparisonBars(
                  orientation: OpenHandComparisonBarOrientation.vertical,
                  valueLabel: (segment) =>
                      _proxyOpsDurationLabel(segment.value.round()),
                  segments: latencyBars,
                ),
              ),
            ]),
            _proxyOpsChartPanel(
              icon: Icons.north_east_rounded,
              title: text(zh: '提供商出口字节', en: 'Outbound by Provider'),
              empty: byteBars.every((segment) => segment.safeValue <= 0),
              emptyLabel: emptyChart,
              chart: OpenHandOperationalComparisonBars(
                orientation: OpenHandComparisonBarOrientation.horizontal,
                valueLabel: (segment) => formatByteSize(segment.value.round()),
                segments: byteBars,
              ),
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.leaderboard_rounded,
              title: text(zh: '提供商质量表', en: 'Provider Quality'),
              groups: groups,
              leadingHeader: text(zh: '提供商', en: 'Provider'),
              emptyLabel: emptyChart,
              valueOf: (group) => group.successRate,
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.modelMix:
      return _ProxyOpsInsightSpec(
        icon: Icons.model_training_outlined,
        title: text(zh: '模型分布', en: 'Model Mix'),
        subtitle: text(
          zh: '调用热力、调度映射与单均 Token',
          en: 'Call heat, routing map and tokens per call',
        ),
        sections: (context, data) {
          final groups = data.groupBy(
            (record) => _proxyOpsModelGroupLabel(record, unknownModel),
            unknown: unknownModel,
          );
          final routed = data.groupBy((record) {
            if (isAiModelProxyStatusRecord(record)) {
              return openHandAmbientText(zh: '状态页', en: 'Status page');
            }
            final exposed = record.exposedModel.trim();
            final model = record.modelId.trim().isEmpty
                ? unknownModel
                : record.modelId.trim();
            if (exposed.isEmpty || exposed == model) return model;
            return '$exposed → $model';
          }, unknown: unknownModel);
          final tokenBars = [
            for (var i = 0; i < groups.length && i < 8; i++)
              OpenHandChartSegment(
                label: groups[i].label,
                value: groups[i].avgTokens,
                color: palette[i % palette.length],
                valueLabel: '${groups[i].avgTokens}',
              ),
          ];
          return [
            _proxyOpsPanelRow([
              _proxyOpsChartPanel(
                icon: Icons.view_week_rounded,
                title: text(zh: '模型调用热力', en: 'Model Heat'),
                empty: groups.isEmpty,
                emptyLabel: emptyChart,
                subtitle: text(
                  zh: '颜色深度表示该模型近窗被调度次数',
                  en: 'Color depth is how often this model was dispatched',
                ),
                chart: OpenHandOperationalHeatmap(
                  segments: [
                    for (var i = 0; i < groups.length; i++)
                      OpenHandChartSegment(
                        label: groups[i].label,
                        value: groups[i].requests,
                        color: palette[i % palette.length],
                        valueLabel: '${groups[i].requests}',
                        tooltip: OpenHandChartTooltip(
                          title: groups[i].label,
                          subtitle: text(
                            zh: '近窗上游模型调用热度',
                            en: 'Upstream model heat in the recent window',
                          ),
                          badge: text(
                            zh: '${groups[i].requests} 次调用',
                            en: '${groups[i].requests} calls',
                          ),
                          badgeColor: palette[i % palette.length],
                          summary: text(
                            zh: '${groups[i].label} 近窗被调度 ${groups[i].requests} 次，成功 ${_proxyOpsPercentLabel(groups[i].successRate)}，单均 Token ${groups[i].avgTokens}，平均 ${_proxyOpsDurationLabel(groups[i].avgMs)}。',
                            en: '${groups[i].label} was dispatched ${groups[i].requests} times, ${_proxyOpsPercentLabel(groups[i].successRate)} succeeded, ${groups[i].avgTokens} tokens/call, avg ${_proxyOpsDurationLabel(groups[i].avgMs)}.',
                          ),
                          metrics: [
                            OpenHandChartTooltipMetric(
                              label: text(zh: '调用次数', en: 'Calls'),
                              value: '${groups[i].requests}',
                              hint: text(
                                zh: '占近窗 ${_proxyOpsPercentLabel(data.records.isEmpty ? 0 : groups[i].requests / data.records.length)}',
                                en: '${_proxyOpsPercentLabel(data.records.isEmpty ? 0 : groups[i].requests / data.records.length)} of window',
                              ),
                              icon: Icons.model_training_outlined,
                              color: palette[i % palette.length],
                            ),
                            OpenHandChartTooltipMetric(
                              label: text(zh: '成功率', en: 'Success'),
                              value: _proxyOpsPercentLabel(
                                groups[i].successRate,
                              ),
                              hint:
                                  '${groups[i].successes} / ${groups[i].requests}',
                              icon: Icons.verified_rounded,
                              color: OpenHandStatusColors.success,
                            ),
                            OpenHandChartTooltipMetric(
                              label: text(zh: '失败', en: 'Fail'),
                              value: '${groups[i].failures}',
                              icon: Icons.error_outline_rounded,
                              color: groups[i].failures > 0
                                  ? OpenHandStatusColors.error
                                  : OpenHandStatusColors.success,
                            ),
                            OpenHandChartTooltipMetric(
                              label: 'Token',
                              value: '${groups[i].tokens}',
                              hint: text(
                                zh: '单均 ${groups[i].avgTokens}',
                                en: 'Avg ${groups[i].avgTokens}',
                              ),
                              icon: Icons.token_rounded,
                              color: cs.tertiary,
                            ),
                            OpenHandChartTooltipMetric(
                              label: text(zh: '均耗时', en: 'Avg'),
                              value: _proxyOpsDurationLabel(groups[i].avgMs),
                              icon: Icons.timer_outlined,
                              color: cs.primary,
                            ),
                            OpenHandChartTooltipMetric(
                              label: 'P95',
                              value: _proxyOpsDurationLabel(groups[i].p95Ms),
                              icon: Icons.speed_rounded,
                              color: groups[i].p95Ms >= _kProxyOpsSlowLatencyMs
                                  ? OpenHandStatusColors.warning
                                  : cs.primary,
                            ),
                            OpenHandChartTooltipMetric(
                              label: text(zh: '对端', en: 'Peers'),
                              value: '${groups[i].peers.length}',
                              icon: Icons.devices_rounded,
                              color: cs.secondary,
                            ),
                            if (groups[i].lastAt != null)
                              OpenHandChartTooltipMetric(
                                label: text(zh: '最近', en: 'Latest'),
                                value: formatListDateTime(groups[i].lastAt!),
                                icon: Icons.schedule_rounded,
                                color: palette[i % palette.length],
                              ),
                          ],
                          notes: [
                            text(
                              zh: '此图按实际上游模型汇总调用次数。对外暴露名与后备映射请看「启用模型」。',
                              en: 'This strip groups actual upstream models. Exposed names and backends are on Exposed Models.',
                            ),
                          ],
                        ),
                      ),
                  ],
                  color: cs.primary,
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.token_rounded,
                title: text(zh: '单均 Token', en: 'Tokens / Call'),
                empty: tokenBars.every((segment) => segment.safeValue <= 0),
                emptyLabel: emptyChart,
                chart: OpenHandOperationalComparisonBars(
                  orientation: OpenHandComparisonBarOrientation.vertical,
                  valueLabel: (segment) => '${segment.value.round()}',
                  segments: tokenBars,
                ),
              ),
            ]),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.alt_route_rounded,
              title: text(zh: '暴露 → 后备映射', en: 'Exposed → Backend'),
              groups: routed,
              leadingHeader: text(zh: '映射', en: 'Route'),
              emptyLabel: emptyChart,
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.leaderboard_rounded,
              title: text(zh: '模型质量表', en: 'Model Quality'),
              groups: groups,
              leadingHeader: text(zh: '模型', en: 'Model'),
              emptyLabel: emptyChart,
              valueOf: (group) => group.successRate,
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.clientMix:
      return _ProxyOpsInsightSpec(
        icon: Icons.devices_other_rounded,
        title: text(zh: '协议与客户端', en: 'Protocol and Clients'),
        subtitle: text(
          zh: '客户端家族、对端与入口路径',
          en: 'Client family, peers and ingress paths',
        ),
        sections: (context, data) {
          final unknownPath = text(zh: '未知路径', en: 'Unknown path');
          final agents = _proxyOpsSegments(
            data.countBy(
              (record) => _proxyOpsClientFamilyLabel(
                record.clientUserAgent,
                unknownClient,
              ),
              unknown: unknownClient,
            ),
            palette,
          );
          final protocols = _proxyOpsSegments(
            data.countBy(
              (record) => isAiModelProxyStatusRecord(record)
                  ? text(zh: '状态页', en: 'Status page')
                  : aiModelProxyApiStyleLabel(record.apiStyle, text),
              unknown: unknownProtocol,
            ),
            palette,
          );
          final families = data.groupBy(
            (record) => _proxyOpsClientFamilyLabel(
              record.clientUserAgent,
              unknownClient,
            ),
            unknown: unknownClient,
          );
          final peers = data.groupBy(
            (record) => _proxyOpsPeerLabel(record, unknown),
            unknown: unknown,
          );
          final paths = _proxyOpsSegments(
            data.countBy((record) => record.requestPath, unknown: unknownPath),
            palette,
          );
          final protocolQuality = data.groupBy(
            (record) => isAiModelProxyStatusRecord(record)
                ? text(zh: '状态页', en: 'Status page')
                : aiModelProxyApiStyleLabel(record.apiStyle, text),
            unknown: unknownProtocol,
          );
          return [
            _proxyOpsPanelRow([
              _proxyOpsChartPanel(
                icon: Icons.donut_small_rounded,
                title: text(zh: '客户端环图', en: 'Client Donut'),
                empty: agents.isEmpty,
                emptyLabel: emptyChart,
                chart: _proxyOpsDonut(
                  cs: cs,
                  segments: agents,
                  centerLabel: '${data.records.length}',
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.bar_chart_rounded,
                title: text(zh: '协议柱状图', en: 'Protocol Bars'),
                empty: protocols.isEmpty,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalComparisonBars(
                  segments: protocols,
                  orientation: OpenHandComparisonBarOrientation.vertical,
                  valueLabel: (segment) => '${segment.value.round()}',
                ),
              ),
            ]),
            _proxyOpsChartPanel(
              icon: Icons.account_tree_rounded,
              title: text(zh: '入口路径', en: 'Ingress Paths'),
              empty: paths.isEmpty,
              emptyLabel: emptyChart,
              chart: OpenHandOperationalComparisonBars(
                orientation: OpenHandComparisonBarOrientation.horizontal,
                valueLabel: (segment) => '${segment.value.round()}',
                segments: paths,
              ),
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.devices_rounded,
              title: text(zh: '客户端家族', en: 'Client Families'),
              groups: families,
              leadingHeader: text(zh: '客户端', en: 'Client'),
              emptyLabel: emptyChart,
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.public_rounded,
              title: text(zh: '对端排行', en: 'Peer Rank'),
              groups: peers,
              leadingHeader: text(zh: '对端', en: 'Peer'),
              emptyLabel: emptyChart,
            ),
            _proxyOpsGroupTablePanel(
              context: context,
              icon: Icons.api_rounded,
              title: text(zh: '协议质量', en: 'Protocol Quality'),
              groups: protocolQuality,
              leadingHeader: text(zh: '协议', en: 'Protocol'),
              emptyLabel: emptyChart,
              valueOf: (group) => group.successRate,
            ),
          ];
        },
      );
  }
}
