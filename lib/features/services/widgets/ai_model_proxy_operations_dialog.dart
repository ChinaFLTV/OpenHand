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
const double _kProxyOpsMetricWideBreakpoint = 860;
const double _kProxyOpsMetricMediumBreakpoint = 560;
const double _kProxyOpsTrendChartHeight = 208;
const int _kProxyOpsLogMaxEntries = 30;
const int _kProxyOpsTopLogEntries = 12;

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
    required this.p95LatencyMs,
    required this.trendSuccess,
    required this.trendFailure,
    required this.averageLatencyBuckets,
    required this.p95LatencyBuckets,
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
    final latencyBuckets = List<List<int>>.generate(
      _kProxyOpsTrendBuckets,
      (_) => <int>[],
    );
    for (final record in records) {
      final age = trendEndAt.difference(record.startedAt).inMinutes;
      if (age < 0 || age >= _kProxyOpsTrendBuckets) continue;
      final index = _kProxyOpsTrendBuckets - age - 1;
      (record.success ? success : failure)[index] += 1;
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
    return _ProxyOpsSnapshot(
      controller: controller,
      settings: settings,
      records: records,
      providerNames: providerNames,
      p95LatencyMs: _proxyOpsPercentile(
        records.map((item) => item.durationMs).toList(growable: false),
        0.95,
      ),
      trendSuccess: success,
      trendFailure: failure,
      averageLatencyBuckets: averageLatency,
      p95LatencyBuckets: p95Latency,
      trendEndAt: trendEndAt,
      usesHistoricalTrendWindow: usesHistoricalTrendWindow,
    );
  }

  final AiModelProxyController controller;
  final AiModelProxySettings settings;
  final List<AiModelProxyRequestRecord> records;
  final Map<String, String> providerNames;
  final int p95LatencyMs;
  final List<double> trendSuccess;
  final List<double> trendFailure;
  final List<double> averageLatencyBuckets;
  final List<double> p95LatencyBuckets;
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
  final index = ((sorted.length - 1) * percentile.clamp(0.0, 1.0)).round();
  return sorted[index.clamp(0, sorted.length - 1)];
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
    this.showPercent = false,
  });
  final String label;
  final int value;
  final int total;
  final Color color;
  final bool showPercent;
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
              if (showPercent) ...[
                _ProxyOpsCopyText(
                  '${(ratio * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                kOpenHandHGap8,
              ],
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = !maxWidth.isFinite
            ? 3
            : maxWidth >= _kProxyOpsMetricWideBreakpoint
            ? 4
            : maxWidth >= _kProxyOpsMetricMediumBreakpoint
            ? 2
            : 1;
        final width = maxWidth.isFinite
            ? (maxWidth - _kProxyOpsGap * (columns - 1)) / columns
            : 220.0;
        return Wrap(
          spacing: _kProxyOpsGap,
          runSpacing: _kProxyOpsGap,
          children: [
            for (final child in children)
              SizedBox(width: width < 0 ? 0 : width, child: child),
          ],
        );
      },
    );
  }
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

class _ProxyOpsBarPanel extends StatelessWidget {
  const _ProxyOpsBarPanel({
    required this.icon,
    required this.title,
    required this.values,
  });

  final IconData icon;
  final String title;
  final Map<String, int> values;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = values.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<int>(0, (sum, entry) => sum + entry.value);
    final palette = _proxyOpsChartPalette(cs);
    return _ProxyOpsPanel(
      icon: icon,
      title: title,
      trailing: sorted.isEmpty
          ? null
          : _ProxyOpsStatusChip(
              icon: Icons.functions_rounded,
              label: '$total',
              color: cs.primary,
            ),
      child: sorted.isEmpty
          ? _ProxyOpsInsightEmpty(
              label: openHandTextResolver(context)(
                zh: '暂无样本数据',
                en: 'No samples yet',
              ),
            )
          : _proxyOpsBoundedList(
              context,
              Column(
                children: [
                  for (var i = 0; i < sorted.length; i++)
                    _ProxyOpsDistributionRow(
                      label: sorted[i].key,
                      value: sorted[i].value,
                      total: total,
                      color: palette[i % palette.length],
                      showPercent: true,
                    ),
                ],
              ),
            ),
    );
  }
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxValue = series
        .expand((item) => item.values)
        .fold<double>(0, (max, value) => math.max(max, value));
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
          SizedBox(
            height: _kProxyOpsTrendChartHeight,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: OpenHandSmoothLineChartPainter(
                  series: series,
                  gridColor: cs.outlineVariant.withValues(alpha: 0.46),
                  labelColor: cs.onSurfaceVariant,
                  emptyLabel: maxValue <= 0 ? emptyLabel : '',
                  valueSuffix: valueSuffix,
                  textDirection: Directionality.of(context),
                ),
              ),
            ),
          ),
          kOpenHandGap12,
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final item in series)
                _ProxyOpsLegend(label: item.label, color: item.color),
            ],
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

List<Widget> _proxyOpsOutcomeTiles(
  BuildContext context,
  _ProxyOpsSnapshot data,
) {
  final cs = Theme.of(context).colorScheme;
  final text = openHandTextResolver(context);
  return [
    _proxyOpsInsightTile(
      context,
      Icons.call_made_rounded,
      text(zh: '请求总数', en: 'Requests'),
      '${data.requestTotal}',
    ),
    _proxyOpsInsightTile(
      context,
      Icons.task_alt_rounded,
      text(zh: '成功', en: 'Succeeded'),
      '${data.successTotal}',
      helper: '${data.successRateLabel}%',
      color: OpenHandStatusColors.success,
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
      Icons.input_rounded,
      text(zh: '入口请求', en: 'Ingress'),
      '${data.controller.runtimeRequestCount}',
    ),
  ];
}

Widget _proxyOpsRequestTrendPanel(
  BuildContext context,
  _ProxyOpsSnapshot data,
) {
  final text = openHandTextResolver(context);
  final cs = Theme.of(context).colorScheme;
  return _ProxyOpsTrendDetailPanel(
    icon: Icons.show_chart_rounded,
    title: text(zh: '请求趋势', en: 'Request Trend'),
    subtitle: data.usesHistoricalTrendWindow
        ? text(zh: '最近 12 个采样桶 · 成功/失败', en: 'Last 12 samples · success/failed')
        : text(zh: '最近 12 分钟 · 成功/失败', en: 'Last 12 minutes · success/failed'),
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

Widget _proxyOpsLatencyTrendPanel(
  BuildContext context,
  _ProxyOpsSnapshot data,
) {
  final text = openHandTextResolver(context);
  final cs = Theme.of(context).colorScheme;
  return _ProxyOpsTrendDetailPanel(
    icon: Icons.timeline_rounded,
    title: text(zh: '耗时曲线', en: 'Latency Curve'),
    subtitle: text(zh: '平均耗时与尾延迟', en: 'Average and tail latency'),
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

Map<String, int> _proxyOpsStatusDistribution(
  BuildContext context,
  _ProxyOpsSnapshot data,
) {
  final text = openHandTextResolver(context);
  return <String, int>{
    text(zh: '成功', en: 'Success'): data.successTotal,
    text(zh: '失败', en: 'Failed'): data.failureTotal,
  }..removeWhere((_, value) => value <= 0);
}

_ProxyOpsInsightSpec _proxyOpsTrafficSpec(
  BuildContext context, {
  required bool inbound,
}) {
  final text = openHandTextResolver(context);
  return _ProxyOpsInsightSpec(
    icon: inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
    title: inbound
        ? text(zh: '入口流量', en: 'Inbound Traffic')
        : text(zh: '出口流量', en: 'Outbound Traffic'),
    sections: (context, data) {
      final bytes = inbound
          ? data.controller.runtimeInboundBytes
          : data.controller.runtimeOutboundBytes;
      final count = data.controller.runtimeRequestCount;
      final avg = count <= 0 ? 0 : bytes ~/ count;
      return [
        _ProxyOpsStatPanel(
          icon: Icons.swap_vert_rounded,
          title: text(zh: '流量概览', en: 'Overview'),
          tiles: [
            _proxyOpsInsightTile(
              context,
              inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
              inbound
                  ? text(zh: '入口总量', en: 'Inbound')
                  : text(zh: '出口总量', en: 'Outbound'),
              formatByteSize(bytes),
            ),
            _proxyOpsInsightTile(
              context,
              Icons.straighten_rounded,
              text(zh: '平均每请求', en: 'Per request'),
              formatByteSize(avg),
            ),
            _proxyOpsInsightTile(
              context,
              Icons.call_made_rounded,
              text(zh: '请求总数', en: 'Requests'),
              '${data.requestTotal}',
              helper: text(zh: '本次入口 $count', en: 'Ingress $count'),
            ),
          ],
        ),
        _ProxyOpsBarPanel(
          icon: Icons.public_rounded,
          title: text(zh: '来源地址分布', en: 'Peer Mix'),
          values: data.countBy(
            (record) => record.clientEndpoint,
            unknown: text(zh: '未知地址', en: 'Unknown address'),
          ),
        ),
        _ProxyOpsLogListPanel(
          icon: Icons.data_usage_rounded,
          title: inbound
              ? text(zh: '最近入口请求', en: 'Recent Inbound')
              : text(zh: '最近出口请求', en: 'Recent Outbound'),
          records: data.recentFirst,
          data: data,
          maxEntries: _kProxyOpsTopLogEntries,
          emptyLabel: text(zh: '暂无流量样本', en: 'No traffic samples'),
        ),
      ];
    },
  );
}

_ProxyOpsInsightSpec _proxyOpsDistributionSpec(
  BuildContext context, {
  required IconData icon,
  required String title,
  required Map<String, int> Function(_ProxyOpsSnapshot data) selector,
}) {
  return _ProxyOpsInsightSpec(
    icon: icon,
    title: title,
    sections: (context, data) => [
      _ProxyOpsBarPanel(icon: icon, title: title, values: selector(data)),
    ],
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

_ProxyOpsInsightSpec _proxyOpsInsightSpec(
  BuildContext context,
  _ProxyOpsInsightKind kind,
) {
  final cs = Theme.of(context).colorScheme;
  final text = openHandTextResolver(context);
  const success = OpenHandStatusColors.success;
  final unknown = text(zh: '未知', en: 'Unknown');
  final unknownProtocol = text(zh: '未知协议', en: 'Unknown protocol');
  final unknownAddress = text(zh: '未知地址', en: 'Unknown address');
  final unknownModel = text(zh: '未知模型', en: 'Unknown model');
  final unknownProvider = text(zh: '未知提供商', en: 'Unknown provider');
  final unknownMode = text(zh: '未知模式', en: 'Unknown mode');

  switch (kind) {
    case _ProxyOpsInsightKind.connections:
      return _ProxyOpsInsightSpec(
        icon: Icons.link_rounded,
        title: text(zh: '连接明细', en: 'Connections'),
        subtitle: text(
          zh: '实时会话 · 活跃与入口连接',
          en: 'Live sessions · active and ingress',
        ),
        sections: (context, data) => [
          _ProxyOpsStatPanel(
            icon: Icons.hub_rounded,
            title: text(zh: '连接概览', en: 'Overview'),
            tiles: [
              _proxyOpsInsightTile(
                context,
                Icons.link_rounded,
                text(zh: '当前连接', en: 'Connections'),
                '${data.controller.currentConnections}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.bolt_rounded,
                text(zh: '活跃请求', en: 'Active'),
                '${data.controller.activeRequests}',
                color: cs.primary,
              ),
              _proxyOpsInsightTile(
                context,
                Icons.input_rounded,
                text(zh: '入口请求', en: 'Ingress'),
                '${data.controller.runtimeRequestCount}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.schedule_rounded,
                text(zh: '运行时长', en: 'Uptime'),
                formatCompactDuration(data.controller.uptime),
              ),
            ],
          ),
          _ProxyOpsDetailSection(
            icon: Icons.tune_rounded,
            title: text(zh: '连接属性', en: 'Properties'),
            rows: {
              text(zh: '服务入口', en: 'Endpoint'): data.endpoint,
              text(
                zh: '访问鉴权',
                en: 'Authentication',
              ): data.settings.requireAuthentication
                  ? text(zh: '已启用', en: 'Enabled')
                  : text(zh: '未启用', en: 'Disabled'),
              text(zh: '调度策略', en: 'Scheduling'):
                  data.settings.scheduling.label,
              text(zh: '接口风格', en: 'API style'): data.settings.apiStyle.label,
            },
          ),
          _ProxyOpsBarPanel(
            icon: Icons.public_rounded,
            title: text(zh: '来源地址分布', en: 'Peer Mix'),
            values: data.countBy(
              (record) => record.clientEndpoint,
              unknown: unknownAddress,
            ),
          ),
          _ProxyOpsBarPanel(
            icon: Icons.devices_other_rounded,
            title: text(zh: '客户端分布', en: 'Client Mix'),
            values: data.countBy(
              (record) => _proxyOpsClientMixLabel(record, unknownProtocol),
              unknown: unknown,
            ),
          ),
          _ProxyOpsLogListPanel(
            icon: Icons.history_rounded,
            title: text(zh: '最近请求', en: 'Recent Requests'),
            records: data.recentFirst,
            data: data,
            emptyLabel: text(zh: '暂无请求记录', en: 'No requests yet'),
          ),
        ],
      );

    case _ProxyOpsInsightKind.activeRequests:
      return _ProxyOpsInsightSpec(
        icon: Icons.bolt_rounded,
        title: text(zh: '活跃请求', en: 'Active Requests'),
        subtitle: text(
          zh: '执行中的请求与近窗吞吐',
          en: 'In-flight requests and throughput',
        ),
        sections: (context, data) => [
          _ProxyOpsStatPanel(
            icon: Icons.speed_rounded,
            title: text(zh: '实时吞吐', en: 'Throughput'),
            tiles: [
              _proxyOpsInsightTile(
                context,
                Icons.bolt_rounded,
                text(zh: '活跃请求', en: 'Active'),
                '${data.controller.activeRequests}',
                color: cs.tertiary,
              ),
              _proxyOpsInsightTile(
                context,
                Icons.link_rounded,
                text(zh: '当前连接', en: 'Connections'),
                '${data.controller.currentConnections}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.speed_rounded,
                data.settings.limitMode.label,
                '${data.currentRpm}',
                helper: '/ ${data.settings.limitThreshold}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.call_made_rounded,
                text(zh: '近窗请求', en: 'Window'),
                '${data.windowRequestCount}',
              ),
            ],
          ),
          _ProxyOpsBarPanel(
            icon: Icons.alt_route_rounded,
            title: text(zh: '执行模式分布', en: 'Mode Mix'),
            values: data.countBy(
              (record) => record.proxyMode,
              unknown: unknownMode,
            ),
          ),
          _ProxyOpsLogListPanel(
            icon: Icons.history_rounded,
            title: text(zh: '最近调用', en: 'Recent Calls'),
            records: data.recentFirst,
            data: data,
            emptyLabel: text(zh: '暂无调用记录', en: 'No calls yet'),
          ),
        ],
      );

    case _ProxyOpsInsightKind.requests:
      return _ProxyOpsInsightSpec(
        icon: Icons.call_made_rounded,
        title: text(zh: '请求总览', en: 'Requests'),
        subtitle: text(zh: '累计请求与成功/失败构成', en: 'Totals and success/failed mix'),
        sections: (context, data) => [
          _ProxyOpsStatPanel(
            icon: Icons.analytics_rounded,
            title: text(zh: '请求构成', en: 'Composition'),
            tiles: _proxyOpsOutcomeTiles(context, data),
          ),
          _proxyOpsRequestTrendPanel(context, data),
          _ProxyOpsBarPanel(
            icon: Icons.api_rounded,
            title: text(zh: '接口协议分布', en: 'Protocol Mix'),
            values: data.countBy(
              (record) => record.apiStyle,
              unknown: unknownProtocol,
            ),
          ),
          _ProxyOpsLogListPanel(
            icon: Icons.history_rounded,
            title: text(zh: '最近请求', en: 'Recent Requests'),
            records: data.recentFirst,
            data: data,
            emptyLabel: text(zh: '暂无请求记录', en: 'No requests yet'),
          ),
        ],
      );

    case _ProxyOpsInsightKind.ingress:
      return _ProxyOpsInsightSpec(
        icon: Icons.input_rounded,
        title: text(zh: '入口请求', en: 'Ingress'),
        subtitle: text(
          zh: '本次运行入口请求与来源构成',
          en: 'This-run ingress and source mix',
        ),
        sections: (context, data) => [
          _ProxyOpsStatPanel(
            icon: Icons.input_rounded,
            title: text(zh: '入口概览', en: 'Overview'),
            tiles: [
              _proxyOpsInsightTile(
                context,
                Icons.input_rounded,
                text(zh: '入口请求', en: 'Ingress'),
                '${data.controller.runtimeRequestCount}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.report_problem_outlined,
                text(zh: '入口错误', en: 'Ingress errors'),
                '${data.controller.runtimeErrorCount}',
                color: cs.error,
              ),
              _proxyOpsInsightTile(
                context,
                Icons.public_rounded,
                text(zh: '来源地址', en: 'Peers'),
                '${data.countBy((record) => record.clientEndpoint, unknown: unknownAddress).length}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.south_west_rounded,
                text(zh: '入口流量', en: 'Inbound'),
                formatByteSize(data.controller.runtimeInboundBytes),
              ),
            ],
          ),
          _ProxyOpsBarPanel(
            icon: Icons.api_rounded,
            title: text(zh: '入口协议', en: 'Ingress Protocols'),
            values: data.countBy(
              (record) => record.apiStyle,
              unknown: unknownProtocol,
            ),
          ),
          _ProxyOpsBarPanel(
            icon: Icons.public_rounded,
            title: text(zh: '来源地址分布', en: 'Peer Mix'),
            values: data.countBy(
              (record) => record.clientEndpoint,
              unknown: unknownAddress,
            ),
          ),
          _ProxyOpsLogListPanel(
            icon: Icons.history_rounded,
            title: text(zh: '最近请求', en: 'Recent Requests'),
            records: data.recentFirst,
            data: data,
            emptyLabel: text(zh: '暂无请求记录', en: 'No requests yet'),
          ),
        ],
      );

    case _ProxyOpsInsightKind.succeeded:
      return _ProxyOpsInsightSpec(
        icon: Icons.task_alt_rounded,
        title: text(zh: '成功请求', en: 'Succeeded'),
        tone: success,
        sections: (context, data) => [
          _ProxyOpsStatPanel(
            icon: Icons.verified_rounded,
            title: text(zh: '成功概览', en: 'Overview'),
            tiles: _proxyOpsOutcomeTiles(context, data),
          ),
          _ProxyOpsBarPanel(
            icon: Icons.donut_small_rounded,
            title: text(zh: '状态分布', en: 'Status Mix'),
            values: _proxyOpsStatusDistribution(context, data),
          ),
          _proxyOpsRequestTrendPanel(context, data),
        ],
      );

    case _ProxyOpsInsightKind.failures:
      return _ProxyOpsInsightSpec(
        icon: Icons.error_outline_rounded,
        title: text(zh: '失败明细', en: 'Failures'),
        tone: cs.error,
        sections: (context, data) {
          final logs = data.recentFirst
              .where((record) => !record.success)
              .toList(growable: false);
          return [
            _ProxyOpsStatPanel(
              icon: Icons.report_rounded,
              title: text(zh: '失败概览', en: 'Overview'),
              tiles: [
                _proxyOpsInsightTile(
                  context,
                  Icons.error_outline_rounded,
                  text(zh: '失败数量', en: 'Failures'),
                  '${data.failureTotal}',
                  helper: '${data.failureRateLabel}%',
                  color: cs.error,
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.task_alt_rounded,
                  text(zh: '成功数量', en: 'Succeeded'),
                  '${data.successTotal}',
                  color: success,
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.call_made_rounded,
                  text(zh: '请求总数', en: 'Requests'),
                  '${data.requestTotal}',
                ),
              ],
            ),
            _ProxyOpsBarPanel(
              icon: Icons.rule_rounded,
              title: text(zh: '失败原因', en: 'Failure Reasons'),
              values: data.countBy(
                (record) =>
                    record.error ?? text(zh: '未提供错误原因', en: 'No error reason'),
                unknown: text(zh: '未提供错误原因', en: 'No error reason'),
                source: logs,
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
        icon: Icons.error_outline_rounded,
        title: text(zh: '入口错误', en: 'Ingress Errors'),
        subtitle: text(zh: 'HTTP 4xx/5xx 入口错误', en: 'HTTP 4xx/5xx ingress'),
        tone: cs.error,
        sections: (context, data) {
          final logs = data.recentFirst
              .where((record) => !record.success)
              .toList(growable: false);
          return [
            _ProxyOpsStatPanel(
              icon: Icons.report_rounded,
              title: text(zh: '错误概览', en: 'Overview'),
              tiles: [
                _proxyOpsInsightTile(
                  context,
                  Icons.report_problem_outlined,
                  text(zh: '入口错误', en: 'Ingress errors'),
                  '${data.controller.runtimeErrorCount}',
                  color: cs.error,
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.error_outline_rounded,
                  text(zh: '失败数量', en: 'Failures'),
                  '${data.failureTotal}',
                  helper: '${data.failureRateLabel}%',
                  color: cs.error,
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.call_made_rounded,
                  text(zh: '请求总数', en: 'Requests'),
                  '${data.requestTotal}',
                ),
              ],
            ),
            _ProxyOpsBarPanel(
              icon: Icons.api_rounded,
              title: text(zh: '错误入口协议', en: 'Error Protocols'),
              values: data.countBy(
                (record) => record.apiStyle,
                unknown: unknownProtocol,
                source: logs,
              ),
            ),
            _ProxyOpsLogListPanel(
              icon: Icons.bug_report_rounded,
              title: text(zh: '错误记录', en: 'Error Log'),
              records: logs,
              data: data,
              showReason: true,
              emptyLabel: text(zh: '暂无入口错误', en: 'No ingress errors'),
            ),
          ];
        },
      );

    case _ProxyOpsInsightKind.averageLatency:
    case _ProxyOpsInsightKind.p95Latency:
    case _ProxyOpsInsightKind.latencyTrend:
      return _ProxyOpsInsightSpec(
        icon: Icons.speed_rounded,
        title: text(zh: '耗时分析', en: 'Latency'),
        subtitle: text(
          zh: '平均耗时、尾延迟与最慢调用',
          en: 'Average, tail latency and slowest calls',
        ),
        sections: (context, data) {
          final slowest = [...data.records]
            ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
          return [
            _ProxyOpsStatPanel(
              icon: Icons.timer_rounded,
              title: text(zh: '耗时概览', en: 'Overview'),
              tiles: [
                _proxyOpsInsightTile(
                  context,
                  Icons.speed_rounded,
                  text(zh: '平均耗时', en: 'Average'),
                  '${data.settings.averageDurationMs.toStringAsFixed(0)}ms',
                ),
                _proxyOpsInsightTile(
                  context,
                  Icons.timeline_rounded,
                  'p95',
                  '${data.p95LatencyMs}ms',
                  color: cs.tertiary,
                ),
              ],
            ),
            _proxyOpsLatencyTrendPanel(context, data),
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
        sections: (context, data) => [
          _ProxyOpsStatPanel(
            icon: Icons.token_rounded,
            title: text(zh: '消耗概览', en: 'Overview'),
            tiles: [
              _proxyOpsInsightTile(
                context,
                Icons.token_rounded,
                text(zh: 'Token 总量', en: 'Tokens'),
                '${data.settings.totalTokens}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.straighten_rounded,
                text(zh: '平均每请求', en: 'Per request'),
                '${data.avgTokensPerRequest}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.call_made_rounded,
                text(zh: '请求总数', en: 'Requests'),
                '${data.requestTotal}',
              ),
            ],
          ),
          _ProxyOpsBarPanel(
            icon: Icons.model_training_outlined,
            title: text(zh: '模型 Token 分布', en: 'Tokens by Model'),
            values: data.sumBy(
              (record) => record.modelId,
              (record) => record.tokens,
              unknown: unknownModel,
            ),
          ),
          _ProxyOpsLogListPanel(
            icon: Icons.history_rounded,
            title: text(zh: '最近请求', en: 'Recent Requests'),
            records: data.recentFirst,
            data: data,
            emptyLabel: text(zh: '暂无请求记录', en: 'No requests yet'),
          ),
        ],
      );

    case _ProxyOpsInsightKind.inbound:
      return _proxyOpsTrafficSpec(context, inbound: true);
    case _ProxyOpsInsightKind.outbound:
      return _proxyOpsTrafficSpec(context, inbound: false);

    case _ProxyOpsInsightKind.exposedModels:
      return _ProxyOpsInsightSpec(
        icon: Icons.hub_rounded,
        title: text(zh: '启用模型', en: 'Exposed Models'),
        sections: (context, data) => [
          _ProxyOpsStatPanel(
            icon: Icons.dns_rounded,
            title: text(zh: '模型概览', en: 'Overview'),
            tiles: [
              _proxyOpsInsightTile(
                context,
                Icons.hub_rounded,
                text(zh: '注册数量', en: 'Registered'),
                '${data.settings.routes.length}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.toggle_on_rounded,
                text(zh: '已启用', en: 'Enabled'),
                '${data.enabledRouteCount}',
                color: success,
              ),
              _proxyOpsInsightTile(
                context,
                Icons.storage_rounded,
                text(zh: '启用后备', en: 'Backends'),
                '${data.enabledBackendCount}',
              ),
            ],
          ),
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
                    zh: '${route.backends.where((backend) => backend.enabled).length} 个后备模型',
                    en: '${route.backends.where((backend) => backend.enabled).length} backends',
                  ),
                  enabled: route.enabled,
                ),
            ],
          ),
        ],
      );

    case _ProxyOpsInsightKind.backends:
      return _ProxyOpsInsightSpec(
        icon: Icons.storage_rounded,
        title: text(zh: '后备模型', en: 'Backends'),
        sections: (context, data) => [
          _ProxyOpsStatPanel(
            icon: Icons.storage_rounded,
            title: text(zh: '后备概览', en: 'Overview'),
            tiles: [
              _proxyOpsInsightTile(
                context,
                Icons.storage_rounded,
                text(zh: '启用后备', en: 'Enabled'),
                '${data.enabledBackendCount}',
                color: success,
              ),
              _proxyOpsInsightTile(
                context,
                Icons.hub_rounded,
                text(zh: '启用模型', en: 'Exposed'),
                '${data.enabledRouteCount}',
              ),
              _proxyOpsInsightTile(
                context,
                Icons.alt_route_rounded,
                text(zh: '调度策略', en: 'Scheduling'),
                data.settings.scheduling.label,
              ),
            ],
          ),
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
        ],
      );

    case _ProxyOpsInsightKind.requestTrend:
      return _ProxyOpsInsightSpec(
        icon: Icons.show_chart_rounded,
        title: text(zh: '请求趋势', en: 'Request Trend'),
        subtitle: text(
          zh: '最近 12 分钟成功/失败',
          en: 'Last 12 minutes success/failed',
        ),
        sections: (context, data) => [
          _proxyOpsRequestTrendPanel(context, data),
          _ProxyOpsBarPanel(
            icon: Icons.donut_small_rounded,
            title: text(zh: '状态分布', en: 'Status Mix'),
            values: _proxyOpsStatusDistribution(context, data),
          ),
          _ProxyOpsBarPanel(
            icon: Icons.api_rounded,
            title: text(zh: '接口协议分布', en: 'Protocol Mix'),
            values: data.countBy(
              (record) => record.apiStyle,
              unknown: unknownProtocol,
            ),
          ),
        ],
      );

    case _ProxyOpsInsightKind.statusMix:
      return _ProxyOpsInsightSpec(
        icon: Icons.donut_small_rounded,
        title: text(zh: '状态分布', en: 'Status Mix'),
        sections: (context, data) => [
          _ProxyOpsStatPanel(
            icon: Icons.pie_chart_rounded,
            title: text(zh: '状态概览', en: 'Overview'),
            tiles: _proxyOpsOutcomeTiles(context, data),
          ),
          _ProxyOpsBarPanel(
            icon: Icons.donut_small_rounded,
            title: text(zh: '状态占比', en: 'Status Share'),
            values: _proxyOpsStatusDistribution(context, data),
          ),
          _proxyOpsRequestTrendPanel(context, data),
        ],
      );

    case _ProxyOpsInsightKind.providerMix:
      return _proxyOpsDistributionSpec(
        context,
        icon: Icons.hub_outlined,
        title: text(zh: '提供商分布', en: 'Provider Mix'),
        selector: (data) => data.countBy(
          (record) => data.providerLabelFor(record, unknown: unknownProvider),
          unknown: unknownProvider,
        ),
      );
    case _ProxyOpsInsightKind.modelMix:
      return _proxyOpsDistributionSpec(
        context,
        icon: Icons.model_training_outlined,
        title: text(zh: '模型分布', en: 'Model Mix'),
        selector: (data) =>
            data.countBy((record) => record.modelId, unknown: unknownModel),
      );
    case _ProxyOpsInsightKind.clientMix:
      return _ProxyOpsInsightSpec(
        icon: Icons.devices_other_rounded,
        title: text(zh: '协议与客户端', en: 'Protocol and Clients'),
        sections: (context, data) => [
          _ProxyOpsBarPanel(
            icon: Icons.api_rounded,
            title: text(zh: '协议分布', en: 'Protocol Mix'),
            values: data.countBy(
              (record) => record.apiStyle,
              unknown: unknownProtocol,
            ),
          ),
          _ProxyOpsBarPanel(
            icon: Icons.devices_other_rounded,
            title: text(zh: '客户端分布', en: 'Client Mix'),
            values: data.countBy(
              (record) => _proxyOpsClientMixLabel(record, unknownProtocol),
              unknown: unknown,
            ),
          ),
        ],
      );
  }
}
