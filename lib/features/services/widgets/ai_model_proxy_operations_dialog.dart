import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';
import '../../ai/index.dart';
import '../ai_model_proxy_controller.dart';
import '../model/ai_model_proxy_models.dart';
import 'service_dialog_controls.dart';

const double _kProxyOpsGap = 16;
const double _kProxyOpsPanelRadius = 16;
const double _kProxyOpsMaxWidth = 1180;
const double _kProxyOpsMaxHeight = 860;
const double _kProxyOpsOuterRadius = 28;
const double _kProxyOpsShellRadius = 20;
const double _kProxyOpsControlRadius = 12;
const int _kProxyOpsTrendBuckets = 12;
const double _kProxyOpsSubDialogWidthFraction = 0.94;
const double _kProxyOpsSubDialogHeightFraction = 0.92;
const double _kProxyOpsInsightMaxWidth = 940;
const double _kProxyOpsInsightMaxHeight = 800;
const double _kProxyOpsMetricMinCellWidth = 120;
const double _kProxyOpsPanelPairBreakpoint = 480;
const double _kProxyOpsDonutHeight = 220;
const double _kProxyOpsGaugeSize = 108;
const double _kProxyOpsMetricHelperHeight = 16;
const int _kProxyOpsLogMaxEntries = 30;
const int _kProxyOpsTopLogEntries = 12;
const int _kProxyOpsRankMaxRows = 12;
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
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = startNonOverlappingPeriodicTimer(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AiModelProxyController>();
    final providers = context.select<SettingsController, List<AiModelConfig>>(
      (settings) => settings.aiModels,
    );
    final data = _ProxyOpsSnapshot.from(controller, providers: providers);
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
                _ProxyOpsHero(data: data),
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
    required this.hourRequestCounts,
    required this.hourPeerCounts,
    required this.hourFailureCounts,
    required this.trendEndAt,
    required this.usesHistoricalTrendWindow,
  });

  factory _ProxyOpsSnapshot.from(
    AiModelProxyController controller, {
    required List<AiModelConfig> providers,
  }) {
    final settings = controller.settings;
    final records = settings.recentRequests;
    final providerNames = <String, String>{
      for (final provider in providers)
        if (provider.id.trim().isNotEmpty)
          provider.id.trim().toLowerCase(): _providerDisplayName(provider),
    };
    final now = DateTime.now();
    final latestRecord = records.isEmpty
        ? null
        : records.reduce(
            (latest, item) =>
                item.startedAt.isAfter(latest.startedAt) ? item : latest,
          );
    final usesHistoricalTrendWindow =
        latestRecord != null &&
        (now.difference(latestRecord.startedAt) >=
                const Duration(minutes: _kProxyOpsTrendBuckets) ||
            latestRecord.startedAt.isAfter(now));
    final trendEndAt = usesHistoricalTrendWindow ? latestRecord.startedAt : now;
    final success = List<double>.filled(_kProxyOpsTrendBuckets, 0);
    final failure = List<double>.filled(_kProxyOpsTrendBuckets, 0);
    final tokens = List<double>.filled(_kProxyOpsTrendBuckets, 0);
    final latencyBuckets = List<List<int>>.generate(
      _kProxyOpsTrendBuckets,
      (_) => <int>[],
    );
    final hourRequests = List<int>.filled(_kProxyOpsHourBuckets, 0);
    final hourFailures = List<int>.filled(_kProxyOpsHourBuckets, 0);
    final hourPeerSets = List<Set<String>>.generate(
      _kProxyOpsHourBuckets,
      (_) => <String>{},
    );
    final peers = <String>{};
    final ports = <String>{};
    final durations = <int>[];
    var maxTokens = 0;
    for (final record in records) {
      durations.add(record.durationMs);
      if (record.tokens > maxTokens) maxTokens = record.tokens;
      final hour = record.startedAt.hour.clamp(0, _kProxyOpsHourBuckets - 1);
      hourRequests[hour] += 1;
      if (!record.success) hourFailures[hour] += 1;
      final peer = record.clientEndpoint.isNotEmpty
          ? record.clientEndpoint
          : record.clientIp.trim();
      if (peer.isNotEmpty) {
        peers.add(peer);
        hourPeerSets[hour].add(peer);
      }
      final port = record.clientPort.trim();
      if (port.isNotEmpty) ports.add(port);
      final age = trendEndAt.difference(record.startedAt).inMinutes;
      if (age < 0 || age >= _kProxyOpsTrendBuckets) continue;
      final index = _kProxyOpsTrendBuckets - age - 1;
      (record.success ? success : failure)[index] += 1;
      tokens[index] += record.tokens;
      latencyBuckets[index].add(record.durationMs);
    }
    final averageLatency = List<double>.filled(_kProxyOpsTrendBuckets, 0);
    final p95Latency = List<double>.filled(_kProxyOpsTrendBuckets, 0);
    for (var i = 0; i < _kProxyOpsTrendBuckets; i++) {
      final bucket = latencyBuckets[i];
      if (bucket.isEmpty) continue;
      averageLatency[i] = bucket.reduce((a, b) => a + b) / bucket.length;
      p95Latency[i] = _proxyOpsPercentile(bucket, 0.95).toDouble();
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
      hourRequestCounts: hourRequests,
      hourPeerCounts: [for (final set in hourPeerSets) set.length],
      hourFailureCounts: hourFailures,
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
  final List<int> hourRequestCounts;
  final List<int> hourPeerCounts;
  final List<int> hourFailureCounts;
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
    for (var i = 0; i < trendSuccess.length; i++) {
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

  List<DateTime> get bucketMinutes => [
    for (var i = 0; i < _kProxyOpsTrendBuckets; i++)
      trendEndAt.subtract(Duration(minutes: _kProxyOpsTrendBuckets - i - 1)),
  ];

  List<AiModelProxyRequestRecord> get recentFirst =>
      records.reversed.toList(growable: false);

  List<AiModelProxyRequestRecord> get windowRecords {
    final start = trendEndAt.subtract(
      const Duration(minutes: _kProxyOpsTrendBuckets),
    );
    final end = trendEndAt.add(const Duration(seconds: 59));
    return [
      for (final record in records)
        if (!record.startedAt.isBefore(start) && !record.startedAt.isAfter(end))
          record,
    ];
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
      group.requests += 1;
      if (record.success) group.successes += 1;
      group.tokens += record.tokens;
      group.promptTokens += record.promptTokens;
      group.completionTokens += record.completionTokens;
      group.durationMs += record.durationMs;
      group.inboundBytes += record.inboundBytes;
      group.outboundBytes += record.outboundBytes;
      if (record.stream) group.streams += 1;
      if (record.durationMs > group.maxMs) group.maxMs = record.durationMs;
      group.durations.add(record.durationMs);
      final peer = record.clientEndpoint.isNotEmpty
          ? record.clientEndpoint
          : record.clientIp.trim();
      if (peer.isNotEmpty) group.peers.add(peer);
      if (group.lastAt == null || record.startedAt.isAfter(group.lastAt!)) {
        group.lastAt = record.startedAt;
      }
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
  DateTime? lastAt;
  final Set<String> peers = <String>{};
  final List<int> durations = <int>[];

  int get failures => math.max(0, requests - successes);
  int get avgMs => requests <= 0 ? 0 : (durationMs / requests).round();
  int get avgTokens => requests <= 0 ? 0 : (tokens / requests).round();
  int get p95Ms => _proxyOpsPercentile(durations, 0.95);
  double get successRate =>
      requests <= 0 ? 0 : (successes / requests).clamp(0.0, 1.0).toDouble();
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
  final protocol = record.apiStyle.trim();
  final userAgent = record.clientUserAgent.trim();
  if (protocol.isEmpty && userAgent.isEmpty) return unknownProtocol;
  if (userAgent.isEmpty) return protocol;
  if (protocol.isEmpty) return _proxyOpsUserAgentFamily(userAgent);
  return '$protocol · ${_proxyOpsUserAgentFamily(userAgent)}';
}

class _ProxyOpsHero extends StatelessWidget {
  const _ProxyOpsHero({required this.data});

  final _ProxyOpsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = openHandTextResolver(context);
    final running = data.controller.lifecycle == AiModelProxyLifecycle.running;
    final tone = running ? OpenHandStatusColors.success : cs.outline;
    return _ProxyOpsPanel(
      title: text(zh: '服务控制台', en: 'Service console'),
      icon: running ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ProxyOpsChip(
                icon: running
                    ? Icons.check_circle_rounded
                    : Icons.pause_circle_outline_rounded,
                label: _lifecycleLabel(context, data.controller.lifecycle),
                color: tone,
              ),
              _ProxyOpsChip(
                icon: Icons.link_rounded,
                label: data.endpoint,
                color: cs.primary,
                monospace: true,
              ),
              _ProxyOpsChip(
                icon: Icons.schedule_rounded,
                label: text(
                  zh: '运行 ${formatCompactDuration(data.controller.uptime)}',
                  en: 'Uptime ${formatCompactDuration(data.controller.uptime)}',
                ),
                color: cs.tertiary,
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
                label: data.settings.scheduling.label,
                color: cs.primary,
              ),
            ],
          ),
          kOpenHandGap12,
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: const Color(0xff0b0d10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
            ),
            child: SelectableText.rich(
              TextSpan(
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                children: [
                  const TextSpan(
                    text: '➜ OpenHand ',
                    style: TextStyle(color: OpenHandStatusColors.success),
                  ),
                  TextSpan(
                    text: 'ai-model-proxy ',
                    style: TextStyle(
                      color: cs.tertiary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: 'endpoint=${data.endpoint}\n',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  const TextSpan(
                    text: '  state ',
                    style: TextStyle(color: OpenHandStatusColors.success),
                  ),
                  TextSpan(
                    text:
                        '${_lifecycleLabel(context, data.controller.lifecycle)}  active=${data.controller.activeRequests}  connections=${data.controller.currentConnections}\n',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  const TextSpan(
                    text: '  traffic ',
                    style: TextStyle(color: OpenHandStatusColors.success),
                  ),
                  TextSpan(
                    text:
                        'in=${formatByteSize(data.controller.runtimeInboundBytes)}  out=${formatByteSize(data.controller.runtimeOutboundBytes)}  avg=${data.settings.averageDurationMs.toStringAsFixed(0)}ms  p95=${data.p95LatencyMs}ms',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
              maxLines: 4,
            ),
          ),
          if (data.controller.errorMessage?.trim().isNotEmpty ?? false) ...[
            kOpenHandGap10,
            Text(
              data.controller.errorMessage!,
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
        text(zh: '当前连接数', en: 'Connections'),
        '${data.controller.currentConnections}',
        text(zh: '实时连接', en: 'Live connections'),
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
    return _ProxyOpsTappableCard(
      onTap: metric.insight == null
          ? null
          : () => _showProxyOpsInsight(context, metric.insight!),
      radius: _kProxyOpsPanelRadius,
      tone: metric.color,
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
            _ProxyOpsCopyText(
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
                  : _ProxyOpsCopyText(
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

class _ProxyOpsTappableCard extends StatefulWidget {
  const _ProxyOpsTappableCard({
    required this.child,
    required this.radius,
    required this.tone,
    this.onTap,
  });

  final Widget child;
  final double radius;
  final Color tone;
  final VoidCallback? onTap;

  @override
  State<_ProxyOpsTappableCard> createState() => _ProxyOpsTappableCardState();
}

class _ProxyOpsTappableCardState extends State<_ProxyOpsTappableCard> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    final duration = openHandMotionDuration(context, kOpenHandMotion120);
    final overlayColor = _pressed
        ? widget.tone.withValues(alpha: 0.10)
        : _hovered
        ? widget.tone.withValues(alpha: 0.05)
        : Colors.transparent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered || _pressed) {
          setState(() {
            _hovered = false;
            _pressed = false;
          });
        }
      },
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            if (!_pressed) setState(() => _pressed = true);
          },
          onTapCancel: () {
            if (_pressed) setState(() => _pressed = false);
          },
          onTapUp: (_) {
            if (_pressed) setState(() => _pressed = false);
          },
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.97 : 1,
            duration: duration,
            curve: kOpenHandSwitchInCurve,
            child: Stack(
              children: [
                IgnorePointer(child: widget.child),
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: duration,
                    curve: kOpenHandSwitchInCurve,
                    decoration: BoxDecoration(
                      color: overlayColor,
                      borderRadius: BorderRadius.circular(widget.radius),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                  ? '最近 12 个采样桶 · 模型调用成功与失败'
                  : '最近 12 分钟 · 模型调用成功与失败',
              en: data.usesHistoricalTrendWindow
                  ? 'Last 12 samples · model-call success and failure'
                  : 'Last 12 minutes · model-call success and failure',
            ),
            series: [
              OpenHandChartSeries(
                label: text(zh: '成功', en: 'Success'),
                values: data.trendSuccess,
                color: OpenHandStatusColors.success,
              ),
              OpenHandChartSeries(
                label: text(zh: '失败', en: 'Failure'),
                values: data.trendFailure,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
            valueSuffix: '',
            insight: _ProxyOpsInsightKind.requestTrend,
          ),
          _ProxyOpsTrendPanel(
            title: text(zh: '耗时曲线', en: 'Latency curve'),
            subtitle: text(
              zh: data.usesHistoricalTrendWindow
                  ? '最近 12 个采样桶 · 平均耗时与 P95 尾延迟'
                  : '平均耗时与 P95 尾延迟',
              en: data.usesHistoricalTrendWindow
                  ? 'Last 12 samples · average and P95 latency'
                  : 'Average and P95 tail latency',
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
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ],
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
    required this.valueSuffix,
    this.insight,
  });
  final String title;
  final String subtitle;
  final List<OpenHandChartSeries> series;
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
            height: 204,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: OpenHandSmoothLineChartPainter(
                  series: series,
                  gridColor: cs.outlineVariant.withValues(alpha: 0.5),
                  labelColor: cs.onSurfaceVariant,
                  emptyLabel: openHandTextResolver(context)(
                    zh: '等待请求样本',
                    en: 'Waiting for traffic',
                  ),
                  valueSuffix: valueSuffix,
                  textDirection: Directionality.of(context),
                ),
              ),
            ),
          ),
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
                        child: Text(
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
              _ProxyOpsCopyText(
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
              maxEntries: 200,
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
                        _ProxyOpsCopyText(
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
    return _ProxyOpsTappableCard(
      onTap: onTap,
      radius: _kProxyOpsPanelRadius,
      tone: cs.primary,
      child: sized,
    );
  }
}

class _ProxyOpsChip extends StatelessWidget {
  const _ProxyOpsChip({
    required this.icon,
    required this.label,
    required this.color,
    this.monospace = false,
  });
  final IconData icon;
  final String label;
  final Color color;
  final bool monospace;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(_kProxyOpsControlRadius),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        kOpenHandHGap6,
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontFamily: monospace ? kOpenHandMonospaceFontFamily : null,
          ),
        ),
      ],
    ),
  );
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
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}

class _ProxyOpsInsightDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final controller = context.watch<AiModelProxyController>();
    final providers = context.select<SettingsController, List<AiModelConfig>>(
      (settings) => settings.aiModels,
    );
    final data = _ProxyOpsSnapshot.from(controller, providers: providers);
    final cs = Theme.of(context).colorScheme;
    final accent = tone ?? cs.primary;
    final children = sections(context, data);
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
                child: Icon(icon, color: accent),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProxyOpsCopyText(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      kOpenHandGap3,
                      _ProxyOpsCopyText(
                        subtitle,
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

class _ProxyOpsTableCell extends StatelessWidget {
  const _ProxyOpsTableCell({
    required this.text,
    this.header = false,
    this.alignEnd = false,
    this.color,
  });

  final String text;
  final bool header;
  final bool alignEnd;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: _ProxyOpsCopyText(
        text,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style:
            (header ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
                ?.copyWith(
                  color: color ?? (header ? cs.onSurfaceVariant : null),
                  fontWeight: header ? FontWeight.w800 : FontWeight.w600,
                ),
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
    required this.columns,
    required this.emptyLabel,
    this.valueSuffix = '',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<OpenHandChartSeries> series;
  final List<DateTime> minutes;
  final List<String> columns;
  final String emptyLabel;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    final rows = <TableRow>[];
    for (var i = minutes.length - 1; i >= 0; i--) {
      final hasData = series.any((s) => i < s.values.length && s.values[i] > 0);
      if (!hasData) continue;
      rows.add(
        TableRow(
          children: [
            _ProxyOpsTableCell(text: formatHourMinuteLocal(minutes[i])),
            for (final s in series)
              _ProxyOpsTableCell(
                text: i < s.values.length
                    ? '${s.values[i].round()}$valueSuffix'
                    : '-',
                color: s.color,
                alignEnd: true,
              ),
          ],
        ),
      );
    }
    return _ProxyOpsPanel(
      icon: icon,
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenHandOperationalTrendChart(
            series: series,
            valueSuffix: valueSuffix,
            xLabels: [
              for (final minute in minutes) formatHourMinuteLocal(minute),
            ],
            emptyLabel: emptyLabel,
            area: true,
            externalLegendProvided: rows.isNotEmpty,
            onSelectionChanged: null,
          ),
          if (rows.isNotEmpty) ...[
            kOpenHandGap14,
            Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(1.2),
              },
              children: [
                TableRow(
                  children: [
                    _ProxyOpsTableCell(
                      text: openHandTextResolver(context)(zh: '时间', en: 'Time'),
                      header: true,
                    ),
                    for (final column in columns)
                      _ProxyOpsTableCell(
                        text: column,
                        header: true,
                        alignEnd: true,
                      ),
                  ],
                ),
                ...rows,
              ],
            ),
          ],
        ],
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
                          child: SelectableText(
                            row.$2.value,
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
  final title = [
    data.providerLabelFor(record, unknown: unknown),
    record.modelId,
  ].where((value) => value.trim().isNotEmpty).join(' / ');
  return title.isEmpty ? unknown : title;
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
  if (ms <= 0) return '—';
  if (ms >= 10000) return '${(ms / 1000).toStringAsFixed(1)}s';
  return '${ms}ms';
}

OpenHandOperationalRankTable _proxyOpsGroupTable({
  required BuildContext context,
  required List<_ProxyOpsGroupStat> groups,
  required String leadingHeader,
  required IconData icon,
  required Color tone,
  required String emptyLabel,
  num Function(_ProxyOpsGroupStat group)? valueOf,
}) {
  final text = openHandTextResolver(context);
  return OpenHandOperationalRankTable(
    leadingIcon: icon,
    emptyLabel: emptyLabel,
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
      for (final group in groups.take(_kProxyOpsRankMaxRows))
        OpenHandOperationalRankRow(
          icon: icon,
          highlightColor: tone,
          subtitle: [
            if (group.promptTokens > 0 || group.completionTokens > 0)
              '↑${group.promptTokens}  ↓${group.completionTokens}',
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
            '${group.tokens}',
            _proxyOpsDurationLabel(group.avgMs),
            _proxyOpsDurationLabel(group.p95Ms),
            '${group.peers.length}',
            group.lastAt == null ? '—' : formatMonthDayHmsLocal(group.lastAt!),
          ],
          value: valueOf?.call(group) ?? group.requests,
        ),
    ],
  );
}

OpenHandOperationalRankTable _proxyOpsTraceTable({
  required BuildContext context,
  required _ProxyOpsSnapshot data,
  required List<AiModelProxyRequestRecord> records,
  required String emptyLabel,
  bool showError = false,
  int maxEntries = _kProxyOpsLogMaxEntries,
}) {
  final text = openHandTextResolver(context);
  final cs = Theme.of(context).colorScheme;
  final unknown = text(zh: '未知', en: 'Unknown');
  final shown = records.take(maxEntries).toList(growable: false);
  return OpenHandOperationalRankTable(
    sortByValue: false,
    emptyLabel: emptyLabel,
    leadingIcon: Icons.receipt_long_rounded,
    headers: [
      text(zh: '时间', en: 'Time'),
      text(zh: '模型', en: 'Model'),
      text(zh: '协议', en: 'Protocol'),
      'Token',
      text(zh: '耗时', en: 'Latency'),
      text(zh: '客户端', en: 'Client'),
      text(zh: '调度', en: 'Route'),
      text(zh: '状态', en: 'Status'),
      if (showError) text(zh: '原因', en: 'Reason'),
    ],
    rows: [
      for (final record in shown)
        OpenHandOperationalRankRow(
          icon: record.success
              ? Icons.check_rounded
              : Icons.error_outline_rounded,
          highlightColor: record.success
              ? OpenHandStatusColors.success
              : cs.error,
          subtitle: [
            if (record.requestPath.trim().isNotEmpty) record.requestPath.trim(),
            if (record.stream) text(zh: '流式', en: 'Stream'),
            if (record.attempt > 1) '#${record.attempt}',
          ].join(' · '),
          cells: [
            formatMonthDayHmsLocal(record.startedAt),
            _proxyOpsRequestTitle(data, record, unknown),
            [
              if (record.apiStyle.trim().isNotEmpty) record.apiStyle.trim(),
              if (record.exposedModel.trim().isNotEmpty)
                record.exposedModel.trim(),
            ].join(' · '),
            record.tokens <= 0
                ? '—'
                : record.promptTokens + record.completionTokens > 0
                ? '${record.tokens}  ↑${record.promptTokens} ↓${record.completionTokens}'
                : '${record.tokens}',
            _proxyOpsDurationLabel(record.durationMs),
            [
              _proxyOpsUserAgentFamily(
                record.clientUserAgent.trim().isEmpty
                    ? unknown
                    : record.clientUserAgent,
              ),
              if (record.clientEndpoint.isNotEmpty) record.clientEndpoint,
            ].join(' · '),
            [
              if (record.proxyMode.trim().isNotEmpty) record.proxyMode.trim(),
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
                  ? '—'
                  : record.error!.trim(),
          ],
          value: record.durationMs,
        ),
    ],
  );
}

List<OpenHandChartSegment> _proxyOpsHourSegments(List<int> hours, Color color) {
  return [
    for (
      var hour = 0;
      hour < hours.length && hour < _kProxyOpsHourBuckets;
      hour++
    )
      OpenHandChartSegment(
        label: twoDigit(hour),
        value: hours[hour],
        color: color,
        valueLabel: '${hours[hour]}',
      ),
  ];
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
        ? text(zh: '最近 12 个采样桶', en: 'Last 12 samples')
        : text(zh: '最近 12 分钟', en: 'Last 12 minutes'),
    series: [
      OpenHandChartSeries(
        label: text(zh: '成功', en: 'Success'),
        values: data.trendSuccess,
        color: OpenHandStatusColors.success,
      ),
      OpenHandChartSeries(
        label: text(zh: '失败', en: 'Failed'),
        values: data.trendFailure,
        color: cs.error,
      ),
    ],
    minutes: data.bucketMinutes,
    columns: [
      text(zh: '成功', en: 'Success'),
      text(zh: '失败', en: 'Failed'),
    ],
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
        color: cs.tertiary,
      ),
    ],
    minutes: data.bucketMinutes,
    valueSuffix: 'ms',
    columns: [
      text(zh: '平均', en: 'Average'),
      'p95',
    ],
    emptyLabel: text(zh: '暂无耗时样本', en: 'No latency samples'),
  );
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
          zh: '实时占用、对端与时段热力',
          en: 'Occupancy, peers and hourly heat',
        ),
        sections: (context, data) {
          final current = data.controller.currentConnections;
          final peerCap = math.max(data.uniquePeerCount, math.max(current, 1));
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
            _proxyOpsChartPanel(
              icon: Icons.view_week_rounded,
              title: text(zh: '对端活跃时段', en: 'Peer Hours'),
              empty: data.hourPeerCounts.every((value) => value <= 0),
              emptyLabel: emptyChart,
              chart: OpenHandOperationalHeatmap(
                segments: _proxyOpsHourSegments(
                  data.hourPeerCounts,
                  cs.primary,
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
          final idle = math.max(0, data.controller.currentConnections - active);
          final modeSegments = _proxyOpsSegments(
            data.countBy((record) => record.proxyMode, unknown: unknownMode),
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
                      maximum: limit,
                      color: cs.tertiary,
                      helper: '${data.settings.limitMode.label} / $limit',
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
                title: text(zh: '忙闲套接字', en: 'Busy / Idle Sockets'),
                empty: active <= 0 && idle <= 0,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalStatusBand(
                  segments: [
                    OpenHandChartSegment(
                      label: text(zh: '忙碌', en: 'Busy'),
                      value: active,
                      color: cs.tertiary,
                      icon: Icons.bolt_rounded,
                      valueLabel: '$active',
                    ),
                    OpenHandChartSegment(
                      label: text(zh: '空闲', en: 'Idle'),
                      value: idle,
                      color: cs.primary,
                      icon: Icons.link_rounded,
                      valueLabel: '$idle',
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
        subtitle: text(zh: '累计体量与吞吐曲线', en: 'Lifetime volume and throughput'),
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
                color: cs.primary,
              ),
            ],
            minutes: data.bucketMinutes,
            columns: [text(zh: '吞吐', en: 'Throughput')],
            emptyLabel: text(zh: '等待请求样本', en: 'Waiting for traffic'),
          ),
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
              empty: data.hourRequestCounts.every((value) => value <= 0),
              emptyLabel: emptyChart,
              chart: OpenHandOperationalHeatmap(
                segments: _proxyOpsHourSegments(
                  data.hourRequestCounts,
                  cs.secondary,
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
          zh: '成功率、成功耗时带与模型质量',
          en: 'Rate, latency bands and model quality',
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
            (record) => record.modelId,
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
            _proxyOpsChartPanel(
              icon: Icons.leaderboard_rounded,
              title: text(zh: '成功模型排行', en: 'Successful Models'),
              empty: models.isEmpty,
              emptyLabel: emptyChart,
              chart: _proxyOpsGroupTable(
                context: context,
                groups: models,
                leadingHeader: text(zh: '模型', en: 'Model'),
                icon: Icons.model_training_outlined,
                tone: success,
                emptyLabel: emptyChart,
              ),
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
          zh: '失败率、原因条与失败模型',
          en: 'Rate, reasons and failed models',
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
            (record) => record.modelId,
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
            _proxyOpsChartPanel(
              icon: Icons.leaderboard_rounded,
              title: text(zh: '失败模型排行', en: 'Failed Models'),
              empty: models.isEmpty,
              emptyLabel: emptyChart,
              chart: _proxyOpsGroupTable(
                context: context,
                groups: models,
                leadingHeader: text(zh: '模型', en: 'Model'),
                icon: Icons.model_training_outlined,
                tone: cs.error,
                emptyLabel: emptyChart,
              ),
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
          zh: '网关错误对照模型失败与时段热力',
          en: 'Gateway vs upstream and hourly heat',
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
            _proxyOpsChartPanel(
              icon: Icons.view_week_rounded,
              title: text(zh: '失败时段热力', en: 'Failure Hours'),
              empty: data.hourFailureCounts.every((value) => value <= 0),
              emptyLabel: emptyChart,
              chart: OpenHandOperationalHeatmap(
                segments: _proxyOpsHourSegments(
                  data.hourFailureCounts,
                  cs.error,
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
            (record) => record.modelId,
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
              columns: [text(zh: '平均', en: 'Average')],
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
                  color: cs.tertiary,
                ),
              ],
              minutes: data.bucketMinutes,
              valueSuffix: 'ms',
              columns: ['p95'],
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
                maxEntries: _kProxyOpsTopLogEntries,
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
                  color: cs.tertiary,
                ),
              ],
              minutes: data.bucketMinutes,
              columns: ['Token'],
              emptyLabel: text(zh: '暂无 Token 样本', en: 'No token samples'),
            ),
            _proxyOpsChartPanel(
              icon: Icons.leaderboard_rounded,
              title: text(zh: '提供商 Token 排行', en: 'Tokens by Provider'),
              empty: providers.isEmpty,
              emptyLabel: emptyChart,
              chart: _proxyOpsGroupTable(
                context: context,
                groups: providers,
                leadingHeader: text(zh: '提供商', en: 'Provider'),
                icon: Icons.hub_outlined,
                tone: cs.tertiary,
                emptyLabel: emptyChart,
                valueOf: (group) => group.tokens,
              ),
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.inbound:
      return _ProxyOpsInsightSpec(
        icon: Icons.south_west_rounded,
        title: text(zh: '入口流量', en: 'Inbound Traffic'),
        subtitle: text(
          zh: '请求体占比与进出口对照',
          en: 'Request-body share and in/out contrast',
        ),
        sections: (context, data) {
          final inbound = data.controller.runtimeInboundBytes;
          final outbound = data.controller.runtimeOutboundBytes;
          final total = inbound + outbound;
          final count = data.controller.runtimeRequestCount;
          final avg = count <= 0 ? 0 : inbound ~/ count;
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
          zh: '响应体与上游端点排行',
          en: 'Response body and upstream endpoints',
        ),
        sections: (context, data) {
          final outbound = data.controller.runtimeOutboundBytes;
          final count = data.controller.runtimeRequestCount;
          final avg = count <= 0 ? 0 : outbound ~/ count;
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
            _proxyOpsChartPanel(
              icon: Icons.leaderboard_rounded,
              title: text(zh: '上游端点排行', en: 'Upstream Endpoints'),
              empty: upstream.isEmpty,
              emptyLabel: emptyChart,
              chart: _proxyOpsGroupTable(
                context: context,
                groups: upstream,
                leadingHeader: text(zh: '上游', en: 'Upstream'),
                icon: Icons.cloud_outlined,
                tone: cs.tertiary,
                emptyLabel: emptyChart,
              ),
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
          final heat = [
            for (final route in data.settings.routes)
              OpenHandChartSegment(
                label: route.exposedModel,
                value: route.backends.length,
                color: route.enabled ? success : cs.onSurfaceVariant,
                valueLabel: '${route.backends.length}',
              ),
          ];
          final usageByExposed = <String, _ProxyOpsGroupStat>{
            for (final group in data.groupBy((record) {
              final exposed = record.exposedModel.trim();
              return exposed.isEmpty ? record.modelId : exposed;
            }, unknown: unknownModel))
              group.label: group,
          };
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
                empty: heat.every((segment) => segment.safeValue <= 0),
                emptyLabel: emptyChart,
                chart: OpenHandOperationalHeatmap(
                  segments: heat,
                  color: cs.primary,
                ),
              ),
            ]),
            _proxyOpsChartPanel(
              icon: Icons.list_alt_rounded,
              title: text(zh: '模型列表', en: 'Model List'),
              empty: data.settings.routes.isEmpty,
              emptyLabel: text(zh: '暂无注册模型', en: 'No models registered'),
              chart: OpenHandOperationalRankTable(
                sortByValue: false,
                leadingIcon: Icons.hub_rounded,
                emptyLabel: text(zh: '暂无注册模型', en: 'No models registered'),
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
                    OpenHandOperationalRankRow(
                      icon: Icons.hub_rounded,
                      highlightColor: route.enabled
                          ? success
                          : cs.onSurfaceVariant,
                      subtitle: text(
                        zh: '${route.backends.where((backend) => backend.enabled).length} 个启用后备',
                        en: '${route.backends.where((backend) => backend.enabled).length} enabled backends',
                      ),
                      cells: [
                        route.exposedModel,
                        route.enabled
                            ? text(zh: '启用', en: 'On')
                            : text(zh: '停用', en: 'Off'),
                        '${route.backends.length}',
                        '${usageByExposed[route.exposedModel]?.requests ?? 0}',
                        usageByExposed[route.exposedModel] == null
                            ? '—'
                            : _proxyOpsPercentLabel(
                                usageByExposed[route.exposedModel]!.successRate,
                              ),
                        '${usageByExposed[route.exposedModel]?.tokens ?? 0}',
                        usageByExposed[route.exposedModel] == null
                            ? '—'
                            : _proxyOpsDurationLabel(
                                usageByExposed[route.exposedModel]!.avgMs,
                              ),
                        usageByExposed[route.exposedModel]?.lastAt == null
                            ? '—'
                            : formatMonthDayHmsLocal(
                                usageByExposed[route.exposedModel]!.lastAt!,
                              ),
                      ],
                      value: usageByExposed[route.exposedModel]?.requests ?? 0,
                    ),
                ],
              ),
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
                  text(zh: '调度策略', en: 'Scheduling'):
                      data.settings.scheduling.label,
                  text(zh: '重试策略', en: 'Retry'):
                      data.settings.retryPolicy.label,
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
            _proxyOpsChartPanel(
              icon: Icons.list_alt_rounded,
              title: text(zh: '后备列表', en: 'Backend List'),
              empty: data.settings.routes.every(
                (route) => route.backends.isEmpty,
              ),
              emptyLabel: text(zh: '暂无后备模型', en: 'No backends'),
              chart: OpenHandOperationalRankTable(
                sortByValue: false,
                leadingIcon: Icons.storage_rounded,
                emptyLabel: text(zh: '暂无后备模型', en: 'No backends'),
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
                      OpenHandOperationalRankRow(
                        icon: Icons.storage_rounded,
                        highlightColor: route.enabled && backend.enabled
                            ? success
                            : cs.onSurfaceVariant,
                        subtitle:
                            data.providerLabelForId(backend.providerId) ??
                            backend.providerId,
                        cells: [
                          backend.modelId,
                          route.exposedModel,
                          route.enabled && backend.enabled
                              ? text(zh: '启用', en: 'On')
                              : text(zh: '停用', en: 'Off'),
                          '${usageByBackend['${backend.providerId.trim()}\u0000${backend.modelId.trim()}']?.requests ?? 0}',
                          usageByBackend['${backend.providerId.trim()}\u0000${backend.modelId.trim()}'] ==
                                  null
                              ? '—'
                              : _proxyOpsPercentLabel(
                                  usageByBackend['${backend.providerId.trim()}\u0000${backend.modelId.trim()}']!
                                      .successRate,
                                ),
                          '${usageByBackend['${backend.providerId.trim()}\u0000${backend.modelId.trim()}']?.tokens ?? 0}',
                          usageByBackend['${backend.providerId.trim()}\u0000${backend.modelId.trim()}'] ==
                                  null
                              ? '—'
                              : _proxyOpsDurationLabel(
                                  usageByBackend['${backend.providerId.trim()}\u0000${backend.modelId.trim()}']!
                                      .avgMs,
                                ),
                          usageByBackend['${backend.providerId.trim()}\u0000${backend.modelId.trim()}']
                                      ?.lastAt ==
                                  null
                              ? '—'
                              : formatMonthDayHmsLocal(
                                  usageByBackend['${backend.providerId.trim()}\u0000${backend.modelId.trim()}']!
                                      .lastAt!,
                                ),
                        ],
                        value:
                            usageByBackend['${backend.providerId.trim()}\u0000${backend.modelId.trim()}']
                                ?.requests ??
                            0,
                      ),
                ],
              ),
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
          final peak = data.throughputBuckets.fold<double>(
            0,
            (max, value) => math.max(max, value),
          );
          var quiet = 0;
          var peakIndex = 0;
          for (var i = 0; i < data.throughputBuckets.length; i++) {
            if (data.throughputBuckets[i] <= 0) quiet += 1;
            if (data.throughputBuckets[i] >=
                data.throughputBuckets[peakIndex]) {
              peakIndex = i;
            }
          }
          final minutes = data.bucketMinutes;
          final burstRows = <OpenHandOperationalRankRow>[];
          for (var i = 0; i < minutes.length; i++) {
            final ok = i < data.trendSuccess.length
                ? data.trendSuccess[i]
                : 0.0;
            final fail = i < data.trendFailure.length
                ? data.trendFailure[i]
                : 0.0;
            final total = ok + fail;
            if (total <= 0) continue;
            burstRows.add(
              OpenHandOperationalRankRow(
                icon: Icons.schedule_rounded,
                highlightColor: cs.primary,
                cells: [
                  formatHourMinuteLocal(minutes[i]),
                  '${total.round()}',
                  '${ok.round()}',
                  '${fail.round()}',
                  _proxyOpsPercentLabel(fail / total),
                ],
                value: total,
              ),
            );
          }
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
            _proxyOpsPanelRow([
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
                empty: burstRows.isEmpty,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalRankTable(
                  leadingIcon: Icons.schedule_rounded,
                  emptyLabel: emptyChart,
                  headers: [
                    text(zh: '分钟', en: 'Minute'),
                    text(zh: '总量', en: 'Total'),
                    text(zh: '成功', en: 'OK'),
                    text(zh: '失败', en: 'Fail'),
                    text(zh: '失败率', en: 'Fail rate'),
                  ],
                  rows: burstRows,
                ),
              ),
            ]),
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
            for (final value in data.averageLatencyBuckets)
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
          final minutes = data.bucketMinutes;
          final degraded = <OpenHandOperationalRankRow>[
            for (var i = 0; i < minutes.length; i++)
              if (i < data.p95LatencyBuckets.length &&
                  data.p95LatencyBuckets[i] >= _kProxyOpsSlowLatencyMs)
                OpenHandOperationalRankRow(
                  icon: Icons.warning_amber_rounded,
                  highlightColor: OpenHandStatusColors.warning,
                  cells: [
                    formatHourMinuteLocal(minutes[i]),
                    _proxyOpsDurationLabel(
                      data.averageLatencyBuckets[i].round(),
                    ),
                    _proxyOpsDurationLabel(data.p95LatencyBuckets[i].round()),
                    '${(i < data.throughputBuckets.length ? data.throughputBuckets[i] : 0).round()}',
                  ],
                  value: data.p95LatencyBuckets[i],
                ),
          ];
          final hourDurations = List<List<int>>.generate(
            _kProxyOpsHourBuckets,
            (_) => <int>[],
          );
          for (final record in data.records) {
            if (record.durationMs <= 0) continue;
            hourDurations[record.startedAt.hour.clamp(
                  0,
                  _kProxyOpsHourBuckets - 1,
                )]
                .add(record.durationMs);
          }
          final hourP95 = [
            for (var hour = 0; hour < hourDurations.length; hour++)
              OpenHandChartSegment(
                label: twoDigit(hour),
                value: _proxyOpsPercentile(hourDurations[hour], 0.95),
                color: cs.tertiary,
                valueLabel: _proxyOpsDurationLabel(
                  _proxyOpsPercentile(hourDurations[hour], 0.95),
                ),
              ),
          ];
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
            _proxyOpsPanelRow([
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
                empty: degraded.isEmpty,
                emptyLabel: text(
                  zh: '窗口内无 P95 ≥ 3s',
                  en: 'No P95 ≥ 3s in window',
                ),
                chart: OpenHandOperationalRankTable(
                  leadingIcon: Icons.warning_amber_rounded,
                  emptyLabel: emptyChart,
                  headers: [
                    text(zh: '分钟', en: 'Minute'),
                    text(zh: '均耗时', en: 'Avg'),
                    'P95',
                    text(zh: '请求', en: 'Requests'),
                  ],
                  rows: degraded,
                ),
              ),
            ]),
            _proxyOpsChartPanel(
              icon: Icons.view_week_rounded,
              title: text(zh: '小时 P95 热力', en: 'Hourly P95 Heat'),
              empty: hourP95.every((segment) => segment.safeValue <= 0),
              emptyLabel: emptyChart,
              chart: OpenHandOperationalHeatmap(
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
            _proxyOpsPanelRow([
              _proxyOpsChartPanel(
                icon: Icons.stacked_bar_chart_rounded,
                title: text(zh: '重试结果', en: 'Retry Outcome'),
                empty: attempts.isEmpty,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalStatusBand(segments: attempts),
              ),
              _proxyOpsChartPanel(
                icon: Icons.tag_rounded,
                title: text(zh: '状态码排行', en: 'Status Codes'),
                empty: codes.isEmpty,
                emptyLabel: emptyChart,
                chart: _proxyOpsGroupTable(
                  context: context,
                  groups: codes,
                  leadingHeader: text(zh: '状态码', en: 'Status'),
                  icon: Icons.tag_rounded,
                  tone: cs.secondary,
                  emptyLabel: emptyChart,
                ),
              ),
            ]),
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
            _proxyOpsChartPanel(
              icon: Icons.leaderboard_rounded,
              title: text(zh: '提供商质量表', en: 'Provider Quality'),
              empty: groups.isEmpty,
              emptyLabel: emptyChart,
              chart: _proxyOpsGroupTable(
                context: context,
                groups: groups,
                leadingHeader: text(zh: '提供商', en: 'Provider'),
                icon: Icons.hub_outlined,
                tone: cs.tertiary,
                emptyLabel: emptyChart,
                valueOf: (group) => group.successRate,
              ),
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
            (record) => record.modelId,
            unknown: unknownModel,
          );
          final routed = data.groupBy((record) {
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
                chart: OpenHandOperationalHeatmap(
                  segments: [
                    for (var i = 0; i < groups.length; i++)
                      OpenHandChartSegment(
                        label: groups[i].label,
                        value: groups[i].requests,
                        color: palette[i % palette.length],
                        valueLabel: '${groups[i].requests}',
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
            _proxyOpsChartPanel(
              icon: Icons.alt_route_rounded,
              title: text(zh: '暴露 → 后备映射', en: 'Exposed → Backend'),
              empty: routed.isEmpty,
              emptyLabel: emptyChart,
              chart: _proxyOpsGroupTable(
                context: context,
                groups: routed,
                leadingHeader: text(zh: '映射', en: 'Route'),
                icon: Icons.alt_route_rounded,
                tone: cs.secondary,
                emptyLabel: emptyChart,
              ),
            ),
            _proxyOpsChartPanel(
              icon: Icons.leaderboard_rounded,
              title: text(zh: '模型质量表', en: 'Model Quality'),
              empty: groups.isEmpty,
              emptyLabel: emptyChart,
              chart: _proxyOpsGroupTable(
                context: context,
                groups: groups,
                leadingHeader: text(zh: '模型', en: 'Model'),
                icon: Icons.model_training_outlined,
                tone: cs.primary,
                emptyLabel: emptyChart,
                valueOf: (group) => group.successRate,
              ),
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
            data.countBy((record) {
              final ua = record.clientUserAgent.trim();
              return ua.isEmpty ? unknownClient : _proxyOpsUserAgentFamily(ua);
            }, unknown: unknownClient),
            palette,
          );
          final protocols = _proxyOpsSegments(
            data.countBy((record) => record.apiStyle, unknown: unknownProtocol),
            palette,
          );
          final families = data.groupBy((record) {
            final ua = record.clientUserAgent.trim();
            return ua.isEmpty ? unknownClient : _proxyOpsUserAgentFamily(ua);
          }, unknown: unknownClient);
          final peers = data.groupBy((record) {
            final peer = record.clientEndpoint.isNotEmpty
                ? record.clientEndpoint
                : record.clientIp.trim();
            return peer.isEmpty ? unknown : peer;
          }, unknown: unknown);
          final paths = _proxyOpsSegments(
            data.countBy((record) => record.requestPath, unknown: unknownPath),
            palette,
          );
          final protocolQuality = data.groupBy(
            (record) => record.apiStyle,
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
            _proxyOpsChartPanel(
              icon: Icons.devices_rounded,
              title: text(zh: '客户端家族', en: 'Client Families'),
              empty: families.isEmpty,
              emptyLabel: emptyChart,
              chart: _proxyOpsGroupTable(
                context: context,
                groups: families,
                leadingHeader: text(zh: '客户端', en: 'Client'),
                icon: Icons.devices_rounded,
                tone: cs.secondary,
                emptyLabel: emptyChart,
              ),
            ),
            _proxyOpsPanelRow([
              _proxyOpsChartPanel(
                icon: Icons.public_rounded,
                title: text(zh: '对端排行', en: 'Peer Rank'),
                empty: peers.isEmpty,
                emptyLabel: emptyChart,
                chart: _proxyOpsGroupTable(
                  context: context,
                  groups: peers,
                  leadingHeader: text(zh: '对端', en: 'Peer'),
                  icon: Icons.public_rounded,
                  tone: cs.primary,
                  emptyLabel: emptyChart,
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.api_rounded,
                title: text(zh: '协议质量', en: 'Protocol Quality'),
                empty: protocolQuality.isEmpty,
                emptyLabel: emptyChart,
                chart: _proxyOpsGroupTable(
                  context: context,
                  groups: protocolQuality,
                  leadingHeader: text(zh: '协议', en: 'Protocol'),
                  icon: Icons.api_rounded,
                  tone: cs.tertiary,
                  emptyLabel: emptyChart,
                  valueOf: (group) => group.successRate,
                ),
              ),
            ]),
          ];
        },
      );
  }
}
