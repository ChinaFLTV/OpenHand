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
import '../../../shared/ui/openhand_safe_scrollbar.dart';
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
const double _kProxyOpsRecentMaxHeight = 360;
const double _kProxyOpsListMaxHeight = 340;
const double _kProxyOpsSubDialogWidthFraction = 0.94;
const double _kProxyOpsSubDialogHeightFraction = 0.92;
const double _kProxyOpsInsightMaxWidth = 940;
const double _kProxyOpsInsightMaxHeight = 800;
const double _kProxyOpsMetricMinCellWidth = 168;
const double _kProxyOpsPanelPairBreakpoint = 720;
const double _kProxyOpsDonutHeight = 220;
const double _kProxyOpsGaugeSize = 132;
const double _kProxyOpsHeatCellExtent = 72;
const int _kProxyOpsLogMaxEntries = 30;
const int _kProxyOpsTopLogEntries = 12;
const int _kProxyOpsRankMaxRows = 12;
const int _kProxyOpsHourBuckets = 24;
const int _kProxyOpsFastLatencyMs = 1000;
const int _kProxyOpsSlowLatencyMs = 3000;

Widget _proxyOpsBoundedList(
  BuildContext context,
  Widget child, {
  double maxHeight = _kProxyOpsListMaxHeight,
}) {
  return ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: ListView(
      shrinkWrap: true,
      physics: openHandDialogAwareScrollPhysics(context),
      padding: EdgeInsets.zero,
      children: [child],
    ),
  );
}

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
      group.durationMs += record.durationMs;
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
  int durationMs = 0;

  int get avgMs => requests <= 0 ? 0 : (durationMs / requests).round();
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
            if (metric.helper.trim().isNotEmpty) ...[
              kOpenHandGap4,
              _ProxyOpsCopyText(
                metric.helper.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: metric.color.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    final duration = openHandMotionDuration(context, kOpenHandMotion120);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.975 : 1,
          duration: duration,
          curve: kOpenHandSwitchInCurve,
          child: Stack(
            children: [
              widget.child,
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: duration,
                    curve: kOpenHandSwitchInCurve,
                    decoration: BoxDecoration(
                      color: _pressed
                          ? widget.tone.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(widget.radius),
                    ),
                  ),
                ),
              ),
            ],
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

class _ProxyOpsRecentRequests extends StatefulWidget {
  const _ProxyOpsRecentRequests({required this.data});
  final _ProxyOpsSnapshot data;

  @override
  State<_ProxyOpsRecentRequests> createState() =>
      _ProxyOpsRecentRequestsState();
}

class _ProxyOpsRecentRequestsState extends State<_ProxyOpsRecentRequests> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final data = widget.data;
    final recent = data.records.reversed.toList(growable: false);
    return _ProxyOpsPanel(
      title: text(zh: '最近请求', en: 'Recent requests'),
      subtitle: text(
        zh: '保留最近 200 条摘要，帮助快速定位后备模型、客户端与失败原因。',
        en: 'Up to 200 summaries for fast provider, client and failure diagnosis.',
      ),
      icon: Icons.receipt_long_rounded,
      child: recent.isEmpty
          ? Text(
              text(zh: '暂无中转请求记录。', en: 'No proxy requests yet.'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: _kProxyOpsRecentMaxHeight,
              ),
              child: OpenHandSafeScrollbar(
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  primary: false,
                  shrinkWrap: true,
                  itemCount: recent.length,
                  physics: openHandDialogAwareScrollPhysics(context),
                  itemBuilder: (context, index) => _ProxyOpsRequestTile(
                    record: recent[index],
                    providerLabel: data.providerLabelFor(
                      recent[index],
                      unknown: text(zh: '未知', en: 'Unknown'),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ProxyOpsRequestTile extends StatelessWidget {
  const _ProxyOpsRequestTile({
    required this.record,
    required this.providerLabel,
  });
  final AiModelProxyRequestRecord record;
  final String providerLabel;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = [
      providerLabel,
      record.modelId,
    ].where((value) => value.trim().isNotEmpty).join(' / ');
    final details = [
      if (record.apiStyle.trim().isNotEmpty) record.apiStyle,
      '${record.tokens} tokens',
      '${record.durationMs} ms',
      if (record.proxyMode.trim().isNotEmpty) record.proxyMode,
      if (record.clientEndpoint.isNotEmpty) record.clientEndpoint,
      if (record.clientUserAgent.trim().isNotEmpty)
        'UA ${record.clientUserAgent.trim()}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            record.success
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            color: record.success ? OpenHandStatusColors.success : cs.error,
            size: 20,
          ),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? '未知请求' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                kOpenHandGap4,
                Text(
                  record.error == null ? details : '$details · ${record.error}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          kOpenHandHGap10,
          Text(
            formatMonthDayHm(record.startedAt),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
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
    this.trailing,
    this.onTap,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
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
                if (trailing != null) ...[kOpenHandHGap8, trailing!],
                if (trailing == null && onTap != null) ...[
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
    if (onTap == null) return panel;
    return _ProxyOpsTappableCard(
      onTap: onTap,
      radius: _kProxyOpsPanelRadius,
      tone: cs.primary,
      child: panel,
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

class _ProxyOpsStatusChip extends StatelessWidget {
  const _ProxyOpsStatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxLabelWidth = math.min(
      460.0,
      math.max(120.0, MediaQuery.sizeOf(context).width * 0.58),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          kOpenHandHGap6,
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxLabelWidth),
            child: _ProxyOpsCopyText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyOpsMiniTag extends StatelessWidget {
  const _ProxyOpsMiniTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSurfaceVariant),
          kOpenHandHGap4,
          Flexible(
            child: _ProxyOpsCopyText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
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
        final width = maxWidth.isFinite
            ? (maxWidth - _kProxyOpsGap * (columns - 1)) / columns
            : 220.0;
        return Wrap(
          spacing: _kProxyOpsGap,
          runSpacing: _kProxyOpsGap,
          alignment: WrapAlignment.center,
          children: [
            for (final child in children)
              SizedBox(
                width: width < 0 ? 0 : width,
                child: Center(child: child),
              ),
          ],
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
      return Wrap(
        spacing: _kProxyOpsGap,
        runSpacing: _kProxyOpsGap,
        children: [
          for (final child in children)
            SizedBox(width: (maxWidth - _kProxyOpsGap) / 2, child: child),
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

class _ProxyOpsLogListPanel extends StatelessWidget {
  const _ProxyOpsLogListPanel({
    required this.icon,
    required this.title,
    required this.records,
    required this.data,
    required this.emptyLabel,
    this.showReason = false,
    this.maxEntries = _kProxyOpsLogMaxEntries,
  });

  final IconData icon;
  final String title;
  final List<AiModelProxyRequestRecord> records;
  final _ProxyOpsSnapshot data;
  final String emptyLabel;
  final bool showReason;
  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = records.take(maxEntries).toList(growable: false);
    return _ProxyOpsPanel(
      icon: icon,
      title: title,
      trailing: records.isEmpty
          ? null
          : _ProxyOpsStatusChip(
              icon: Icons.list_alt_rounded,
              label: '${records.length}',
              color: cs.primary,
            ),
      child: shown.isEmpty
          ? _ProxyOpsInsightEmpty(label: emptyLabel)
          : _proxyOpsBoundedList(
              context,
              Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i != 0)
                      Divider(
                        height: 16,
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                    _ProxyOpsLogRow(
                      record: shown[i],
                      data: data,
                      showReason: showReason,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ProxyOpsLogRow extends StatelessWidget {
  const _ProxyOpsLogRow({
    required this.record,
    required this.data,
    this.showReason = false,
  });

  final AiModelProxyRequestRecord record;
  final _ProxyOpsSnapshot data;
  final bool showReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = openHandTextResolver(context);
    final unknown = text(zh: '未知', en: 'Unknown');
    final statusColor = record.success
        ? OpenHandStatusColors.success
        : cs.error;
    final client = record.clientUserAgent.trim().isEmpty
        ? (record.apiStyle.trim().isEmpty
              ? text(zh: '未知客户端', en: 'Unknown client')
              : record.apiStyle.trim())
        : _proxyOpsUserAgentFamily(record.clientUserAgent);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 38,
          margin: const EdgeInsets.only(top: 2, right: 10),
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: kOpenHandPillBorderRadius,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ProxyOpsCopyText(
                      _proxyOpsRequestTitle(data, record, unknown),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  kOpenHandHGap8,
                  _ProxyOpsCopyText(
                    formatMonthDayHmsLocal(record.startedAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              kOpenHandGap4,
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (record.clientEndpoint.isNotEmpty)
                    _ProxyOpsMiniTag(
                      icon: Icons.public_rounded,
                      label: record.clientEndpoint,
                    ),
                  _ProxyOpsMiniTag(icon: Icons.devices_rounded, label: client),
                  _ProxyOpsMiniTag(
                    icon: Icons.timer_rounded,
                    label: '${record.durationMs}ms',
                  ),
                  if (record.tokens > 0)
                    _ProxyOpsMiniTag(
                      icon: Icons.token_rounded,
                      label: '${record.tokens} tokens',
                    ),
                ],
              ),
              if (showReason && (record.error?.trim().isNotEmpty ?? false)) ...[
                kOpenHandGap4,
                _ProxyOpsCopyText(
                  record.error!.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
  bool semicircular = true,
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
    onSelectionChanged: null,
  );
}

Widget _proxyOpsEntityRow(
  BuildContext context, {
  required String title,
  required String subtitle,
  required bool enabled,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final text = openHandTextResolver(context);
  final tone = enabled ? OpenHandStatusColors.success : cs.onSurfaceVariant;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 4,
        height: 34,
        margin: const EdgeInsets.only(top: 2, right: 10),
        decoration: BoxDecoration(
          color: tone,
          borderRadius: kOpenHandPillBorderRadius,
        ),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProxyOpsCopyText(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle.trim().isNotEmpty)
              _ProxyOpsCopyText(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      kOpenHandHGap8,
      _ProxyOpsStatusChip(
        icon: enabled ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
        label: enabled
            ? text(zh: '启用', en: 'Enabled')
            : text(zh: '停用', en: 'Disabled'),
        color: tone,
      ),
    ],
  );
}

Widget _proxyOpsEntityListPanel(
  BuildContext context, {
  required IconData icon,
  required String title,
  required List<Widget> rows,
  required String emptyLabel,
}) {
  final cs = Theme.of(context).colorScheme;
  return _ProxyOpsPanel(
    icon: icon,
    title: title,
    child: rows.isEmpty
        ? _ProxyOpsInsightEmpty(label: emptyLabel)
        : _proxyOpsBoundedList(
            context,
            Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i != 0)
                    Divider(
                      height: 16,
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  rows[i],
                ],
              ],
            ),
          ),
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
              icon: Icons.grid_view_rounded,
              title: text(zh: '对端活跃时段', en: 'Peer Hours'),
              empty: data.hourPeerCounts.every((value) => value <= 0),
              emptyLabel: emptyChart,
              chart: OpenHandOperationalHeatmap(
                segments: _proxyOpsHourSegments(
                  data.hourPeerCounts,
                  cs.primary,
                ),
                color: cs.primary,
                maxCrossAxisExtent: _kProxyOpsHeatCellExtent,
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
                      semicircular: false,
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
                      semicircular: false,
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
              icon: Icons.grid_view_rounded,
              title: text(zh: '到达时段热力', en: 'Arrival Heat'),
              empty: data.hourRequestCounts.every((value) => value <= 0),
              emptyLabel: emptyChart,
              chart: OpenHandOperationalHeatmap(
                segments: _proxyOpsHourSegments(
                  data.hourRequestCounts,
                  cs.secondary,
                ),
                color: cs.secondary,
                maxCrossAxisExtent: _kProxyOpsHeatCellExtent,
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
              chart: OpenHandOperationalRankTable(
                headers: [
                  text(zh: '模型', en: 'Model'),
                  text(zh: '次数', en: 'Count'),
                  text(zh: '均耗时', en: 'Avg'),
                  text(zh: 'Token', en: 'Tokens'),
                ],
                rows: [
                  for (final group in models.take(_kProxyOpsRankMaxRows))
                    OpenHandOperationalRankRow(
                      cells: [
                        group.label,
                        '${group.requests}',
                        '${group.avgMs}ms',
                        '${group.tokens}',
                      ],
                      value: group.requests,
                      highlightColor: success,
                    ),
                ],
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
              chart: OpenHandOperationalRankTable(
                headers: [
                  text(zh: '模型', en: 'Model'),
                  text(zh: '失败', en: 'Failed'),
                  text(zh: '均耗时', en: 'Avg'),
                ],
                rows: [
                  for (final group in models.take(_kProxyOpsRankMaxRows))
                    OpenHandOperationalRankRow(
                      cells: [
                        group.label,
                        '${group.requests}',
                        '${group.avgMs}ms',
                      ],
                      value: group.requests,
                      highlightColor: cs.error,
                    ),
                ],
              ),
            ),
            _ProxyOpsLogListPanel(
              icon: Icons.bug_report_rounded,
              title: text(zh: '失败记录', en: 'Failure Log'),
              records: logs,
              data: data,
              showReason: true,
              emptyLabel: text(zh: '暂无失败记录', en: 'No failures'),
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
              icon: Icons.grid_view_rounded,
              title: text(zh: '失败时段热力', en: 'Failure Hours'),
              empty: data.hourFailureCounts.every((value) => value <= 0),
              emptyLabel: emptyChart,
              chart: OpenHandOperationalHeatmap(
                segments: _proxyOpsHourSegments(
                  data.hourFailureCounts,
                  cs.error,
                ),
                color: cs.error,
                maxCrossAxisExtent: _kProxyOpsHeatCellExtent,
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
            _ProxyOpsLogListPanel(
              icon: Icons.trending_down_rounded,
              title: text(zh: '最慢调用', en: 'Slowest Calls'),
              records: slowest
                  .where((record) => record.durationMs > 0)
                  .toList(growable: false),
              data: data,
              maxEntries: _kProxyOpsTopLogEntries,
              emptyLabel: text(zh: '暂无耗时样本', en: 'No latency samples'),
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
                    semicircular: false,
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
              chart: OpenHandOperationalRankTable(
                headers: [
                  text(zh: '提供商', en: 'Provider'),
                  text(zh: 'Token', en: 'Tokens'),
                  text(zh: '请求', en: 'Requests'),
                  text(zh: '单均', en: 'Avg'),
                ],
                rows: [
                  for (final group in providers.take(_kProxyOpsRankMaxRows))
                    OpenHandOperationalRankRow(
                      cells: [
                        group.label,
                        '${group.tokens}',
                        '${group.requests}',
                        '${group.requests <= 0 ? 0 : (group.tokens / group.requests).round()}',
                      ],
                      value: group.tokens,
                      highlightColor: cs.tertiary,
                    ),
                ],
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
              chart: OpenHandOperationalRankTable(
                headers: [
                  text(zh: '上游', en: 'Upstream'),
                  text(zh: '请求', en: 'Requests'),
                  text(zh: '成功', en: 'OK'),
                  text(zh: '总耗时', en: 'Time'),
                ],
                rows: [
                  for (final group in upstream.take(_kProxyOpsRankMaxRows))
                    OpenHandOperationalRankRow(
                      cells: [
                        group.label,
                        '${group.requests}',
                        '${group.successes}',
                        '${group.durationMs}ms',
                      ],
                      value: group.requests,
                      highlightColor: cs.tertiary,
                    ),
                ],
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
                icon: Icons.grid_view_rounded,
                title: text(zh: '后备规模热力', en: 'Backend Footprint'),
                empty: heat.every((segment) => segment.safeValue <= 0),
                emptyLabel: emptyChart,
                chart: OpenHandOperationalHeatmap(
                  segments: heat,
                  color: cs.primary,
                  maxCrossAxisExtent: 160,
                ),
              ),
            ]),
            _proxyOpsEntityListPanel(
              context,
              icon: Icons.list_alt_rounded,
              title: text(zh: '模型列表', en: 'Model List'),
              emptyLabel: text(zh: '暂无注册模型', en: 'No models registered'),
              rows: [
                for (final route in data.settings.routes)
                  _proxyOpsEntityRow(
                    context,
                    title: route.exposedModel,
                    subtitle: text(
                      zh: '${route.backends.where((backend) => backend.enabled).length} 个启用后备',
                      en: '${route.backends.where((backend) => backend.enabled).length} enabled backends',
                    ),
                    enabled: route.enabled,
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
            _proxyOpsEntityListPanel(
              context,
              icon: Icons.list_alt_rounded,
              title: text(zh: '后备列表', en: 'Backend List'),
              emptyLabel: text(zh: '暂无后备模型', en: 'No backends'),
              rows: [
                for (final route in data.settings.routes)
                  for (final backend in route.backends)
                    _proxyOpsEntityRow(
                      context,
                      title:
                          '${data.providerLabelForId(backend.providerId) ?? backend.providerId} / ${backend.modelId}',
                      subtitle: route.exposedModel,
                      enabled: route.enabled && backend.enabled,
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
        subtitle: text(zh: '成功与失败叠加曲线', en: 'Success and failure overlay'),
        sections: (context, data) => [
          _proxyOpsRequestTrendPanel(context, data),
        ],
      );

    case _ProxyOpsInsightKind.latencyTrend:
      return _ProxyOpsInsightSpec(
        icon: Icons.timeline_rounded,
        title: text(zh: '耗时曲线', en: 'Latency Curve'),
        subtitle: text(zh: '平均与 p95 叠加', en: 'Average and p95 overlay'),
        sections: (context, data) => [
          _proxyOpsLatencyOverlayPanel(context, data),
        ],
      );

    case _ProxyOpsInsightKind.statusMix:
      return _ProxyOpsInsightSpec(
        icon: Icons.donut_small_rounded,
        title: text(zh: '状态分布', en: 'Status Mix'),
        sections: (context, data) {
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
          return [
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
                icon: Icons.stacked_bar_chart_rounded,
                title: text(zh: '状态色带', en: 'Status Band'),
                empty: segments.isEmpty,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalStatusBand(segments: segments),
              ),
            ]),
          ];
        },
      );

    case _ProxyOpsInsightKind.providerMix:
      return _ProxyOpsInsightSpec(
        icon: Icons.hub_outlined,
        title: text(zh: '提供商分布', en: 'Provider Mix'),
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
                icon: Icons.leaderboard_rounded,
                title: text(zh: '提供商成功率', en: 'Provider Quality'),
                empty: groups.isEmpty,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalRankTable(
                  headers: [
                    text(zh: '提供商', en: 'Provider'),
                    text(zh: '请求', en: 'Requests'),
                    text(zh: '成功率', en: 'Success'),
                  ],
                  rows: [
                    for (final group in groups.take(_kProxyOpsRankMaxRows))
                      OpenHandOperationalRankRow(
                        cells: [
                          group.label,
                          '${group.requests}',
                          '${(group.successRate * 100).toStringAsFixed(1)}%',
                        ],
                        value: group.successRate,
                        highlightColor: cs.tertiary,
                      ),
                  ],
                ),
              ),
            ]),
          ];
        },
      );

    case _ProxyOpsInsightKind.modelMix:
      return _ProxyOpsInsightSpec(
        icon: Icons.model_training_outlined,
        title: text(zh: '模型分布', en: 'Model Mix'),
        sections: (context, data) {
          final groups = data.groupBy(
            (record) => record.modelId,
            unknown: unknownModel,
          );
          return [
            _proxyOpsPanelRow([
              _proxyOpsChartPanel(
                icon: Icons.grid_view_rounded,
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
                  maxCrossAxisExtent: 160,
                ),
              ),
              _proxyOpsChartPanel(
                icon: Icons.leaderboard_rounded,
                title: text(zh: '模型成功率', en: 'Model Quality'),
                empty: groups.isEmpty,
                emptyLabel: emptyChart,
                chart: OpenHandOperationalRankTable(
                  headers: [
                    text(zh: '模型', en: 'Model'),
                    text(zh: '请求', en: 'Requests'),
                    text(zh: '成功率', en: 'Success'),
                  ],
                  rows: [
                    for (final group in groups.take(_kProxyOpsRankMaxRows))
                      OpenHandOperationalRankRow(
                        cells: [
                          group.label,
                          '${group.requests}',
                          '${(group.successRate * 100).toStringAsFixed(1)}%',
                        ],
                        value: group.successRate,
                      ),
                  ],
                ),
              ),
            ]),
          ];
        },
      );

    case _ProxyOpsInsightKind.clientMix:
      return _ProxyOpsInsightSpec(
        icon: Icons.devices_other_rounded,
        title: text(zh: '协议与客户端', en: 'Protocol and Clients'),
        sections: (context, data) {
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
          ];
        },
      );
  }
}
