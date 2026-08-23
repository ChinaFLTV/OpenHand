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
const int _kProxyOpsTrendBuckets = 12;
const double _kProxyOpsRecentMaxHeight = 360;

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
        expandToMax: true,
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
          Expanded(
            child: SingleChildScrollView(
              physics: openHandDialogAwareScrollPhysics(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
  recentRequest,
}

void _showProxyOpsInsight(BuildContext context, _ProxyOpsInsightKind kind) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => ServiceDialogInteractionTheme(
      child: _ProxyOpsInsightDialog(kind: kind),
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
    final durations = records.map((item) => item.durationMs).toList()..sort();
    final p95Index = durations.isEmpty
        ? -1
        : ((durations.length - 1) * 0.95).round();
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
    for (final record in records) {
      final age = trendEndAt.difference(record.startedAt).inMinutes;
      if (age < 0 || age >= _kProxyOpsTrendBuckets) continue;
      final index = _kProxyOpsTrendBuckets - age - 1;
      (record.success ? success : failure)[index] += 1;
    }
    return _ProxyOpsSnapshot(
      controller: controller,
      settings: settings,
      records: records,
      providerNames: providerNames,
      p95LatencyMs: p95Index < 0 ? 0 : durations[p95Index],
      trendSuccess: success,
      trendFailure: failure,
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
  String get endpoint => '${settings.listenHost}:${settings.listenPort}';

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
          color: cs.surfaceContainerHigh.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(_kProxyOpsPanelRadius),
          border: Border.all(color: metric.color.withValues(alpha: 0.26)),
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
                  ),
                  alignment: Alignment.center,
                  child: Icon(metric.icon, size: 17, color: metric.color),
                ),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
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
            Text(
              metric.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            kOpenHandGap4,
            Text(
              metric.helper,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: metric.color,
                fontWeight: FontWeight.w700,
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
                values: _latencySeries(data),
                color: Theme.of(context).colorScheme.primary,
              ),
              OpenHandChartSeries(
                label: 'P95',
                values: _p95Series(data),
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

  static List<double> _latencySeries(_ProxyOpsSnapshot data) {
    final buckets = List<List<int>>.generate(
      _kProxyOpsTrendBuckets,
      (_) => <int>[],
    );
    for (final record in data.records) {
      final age = data.trendEndAt.difference(record.startedAt).inMinutes;
      if (age >= 0 && age < _kProxyOpsTrendBuckets) {
        buckets[_kProxyOpsTrendBuckets - age - 1].add(record.durationMs);
      }
    }
    return [
      for (final bucket in buckets)
        bucket.isEmpty ? 0 : bucket.reduce((a, b) => a + b) / bucket.length,
    ];
  }

  static List<double> _p95Series(_ProxyOpsSnapshot data) => _latencySeries(data)
      .map(
        (value) =>
            value == 0 ? 0.0 : math.max(value, data.p95LatencyMs).toDouble(),
      )
      .toList(growable: false);
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
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      kOpenHandHGap6,
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
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
        values: _countBy(
          data.records,
          (item) => data.providerLabelFor(
            item,
            unknown: text(zh: '未知', en: 'Unknown'),
          ),
          text(zh: '未知', en: 'Unknown'),
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
        values: _countBy(
          data.records,
          (item) => item.modelId,
          text(zh: '未知', en: 'Unknown'),
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
        values: _countBy(
          data.records,
          (item) => item.apiStyle.isEmpty
              ? text(zh: '未知协议', en: 'Unknown protocol')
              : _clientDistributionLabel(item),
          text(zh: '未知', en: 'Unknown'),
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

  static Map<String, int> _countBy(
    Iterable<AiModelProxyRequestRecord> records,
    String Function(AiModelProxyRequestRecord item) keyOf,
    String unknown,
  ) {
    final counts = <String, int>{};
    for (final record in records) {
      final key = keyOf(record).trim();
      final normalized = key.isEmpty ? unknown : key;
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
    return counts;
  }

  static String _clientDistributionLabel(AiModelProxyRequestRecord record) {
    final protocol = record.apiStyle.trim();
    final userAgent = record.clientUserAgent.trim();
    if (userAgent.isEmpty) return protocol;
    return '$protocol · ${_userAgentFamily(userAgent)}';
  }

  static String _userAgentFamily(String value) {
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
                        colors: colors.take(top.length).toList(growable: false),
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
                          color: colors[index % colors.length],
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
    final cs = Theme.of(context).colorScheme;
    final ratio = total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Text(
                '$value',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
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
                minHeight: 7,
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
          : SizedBox(
              height: _kProxyOpsRecentMaxHeight,
              child: Scrollbar(
                child: ListView.builder(
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
      if (record.clientIp.trim().isNotEmpty) record.clientIp,
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
    return _ProxyOpsTappableCard(
      onTap: onTap,
      radius: _kProxyOpsPanelRadius,
      tone: cs.primary,
      child: AnimatedContainer(
        duration: openHandMotionDuration(context, kOpenHandMotion180),
        curve: kOpenHandSwitchInCurve,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(_kProxyOpsPanelRadius),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 17, color: cs.primary),
                ),
                kOpenHandHGap8,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: cs.primary.withValues(alpha: 0.72),
                  ),
              ],
            ),
            kOpenHandGap14,
            child,
          ],
        ),
      ),
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
      borderRadius: BorderRadius.circular(12),
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
            fontFamily: monospace ? 'monospace' : null,
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

class _ProxyOpsInsightDialog extends StatelessWidget {
  const _ProxyOpsInsightDialog({required this.kind});

  final _ProxyOpsInsightKind kind;

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
    final title = _proxyOpsInsightTitle(context, kind);
    final accent = _proxyOpsInsightTone(context, kind);
    return OpenHandEscapeDismissScope(
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: 940,
        maxHeight: 800,
        maxWidthFraction: 0.94,
        maxHeightFraction: 0.9,
        minAvailableWidth: 320,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.72),
            ),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.18),
                blurRadius: 38,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Icon(_proxyOpsInsightIcon(kind), color: accent),
                    ),
                    kOpenHandHGap10,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          kOpenHandGap3,
                          Text(
                            text(
                              zh: '实时数据明细 · 点击外部区域或关闭按钮返回服务运维',
                              en: 'Live details · close this view to return to service operations',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                kOpenHandGap14,
                Expanded(
                  child: SingleChildScrollView(
                    physics: openHandDialogAwareScrollPhysics(context),
                    child: _buildProxyOpsInsightBody(context, data, kind),
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

Widget _buildProxyOpsInsightBody(
  BuildContext context,
  _ProxyOpsSnapshot data,
  _ProxyOpsInsightKind kind,
) {
  final text = openHandTextResolver(context);
  final cs = Theme.of(context).colorScheme;
  Widget metric(
    IconData icon,
    String label,
    String value, {
    String helper = '',
    Color? color,
  }) => _ProxyOpsMetric(
    metric: _ProxyOpsMetricData(
      icon,
      label,
      value,
      helper,
      color ?? cs.primary,
    ),
  );
  Widget statPanel(String title, IconData icon, List<Widget> tiles) =>
      _ProxyOpsPanel(
        title: title,
        icon: icon,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 650 ? 2 : 1;
            const gap = _kProxyOpsGap;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final tile in tiles) SizedBox(width: width, child: tile),
              ],
            );
          },
        ),
      );
  Widget recentPanel({
    String title = '最近请求',
    Iterable<AiModelProxyRequestRecord>? records,
  }) {
    final selected = (records ?? data.records).toList(growable: false);
    return _ProxyOpsPanel(
      title: text(zh: title, en: title == '最近请求' ? 'Recent requests' : title),
      icon: Icons.receipt_long_rounded,
      child: selected.isEmpty
          ? Text(
              text(zh: '暂无请求样本。', en: 'No request samples yet.'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            )
          : Column(
              children: [
                for (final record in selected.reversed.take(40))
                  _ProxyOpsRequestTile(
                    record: record,
                    providerLabel: data.providerLabelFor(
                      record,
                      unknown: text(zh: '未知', en: 'Unknown'),
                    ),
                  ),
              ],
            ),
    );
  }

  switch (kind) {
    case _ProxyOpsInsightKind.connections:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statPanel(
            text(zh: '连接概览', en: 'Connection overview'),
            Icons.hub_rounded,
            [
              metric(
                Icons.link_rounded,
                text(zh: '当前连接', en: 'Connections'),
                '${data.controller.currentConnections}',
                helper: text(zh: '实时连接', en: 'Live connections'),
              ),
              metric(
                Icons.bolt_rounded,
                text(zh: '活跃请求', en: 'Active'),
                '${data.controller.activeRequests}',
                helper: text(zh: '执行中', en: 'In flight'),
                color: cs.tertiary,
              ),
              metric(
                Icons.schedule_rounded,
                text(zh: '运行时长', en: 'Uptime'),
                formatCompactDuration(data.controller.uptime),
              ),
              metric(
                Icons.network_check_rounded,
                text(zh: '入口地址', en: 'Endpoint'),
                data.endpoint,
              ),
            ],
          ),
          const SizedBox(height: _kProxyOpsGap),
          recentPanel(),
        ],
      );
    case _ProxyOpsInsightKind.activeRequests:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statPanel(
            text(zh: '实时吞吐', en: 'Live throughput'),
            Icons.bolt_rounded,
            [
              metric(
                Icons.bolt_rounded,
                text(zh: '活跃请求', en: 'Active'),
                '${data.controller.activeRequests}',
                color: cs.tertiary,
              ),
              metric(
                Icons.speed_rounded,
                'RPM',
                '${_proxyOpsCurrentRpm(data)}',
                helper: data.settings.limitThreshold > 0
                    ? '/ ${data.settings.limitThreshold}'
                    : text(zh: '不限流', en: 'Unlimited'),
              ),
              metric(
                Icons.call_made_rounded,
                text(zh: '近窗请求', en: 'Recent'),
                '${data.records.length}',
              ),
            ],
          ),
          const SizedBox(height: _kProxyOpsGap),
          recentPanel(),
        ],
      );
    case _ProxyOpsInsightKind.requests:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statPanel(
            text(zh: '请求构成', en: 'Request composition'),
            Icons.analytics_rounded,
            [
              metric(
                Icons.call_made_rounded,
                text(zh: '请求总数', en: 'Requests'),
                '${data.requestTotal}',
              ),
              metric(
                Icons.task_alt_rounded,
                text(zh: '成功', en: 'Succeeded'),
                '${data.successTotal}',
                helper: '${(data.successRate * 100).toStringAsFixed(1)}%',
                color: OpenHandStatusColors.success,
              ),
              metric(
                Icons.error_outline_rounded,
                text(zh: '失败', en: 'Failures'),
                '${data.failureTotal}',
                helper: '${(data.failureRate * 100).toStringAsFixed(1)}%',
                color: cs.error,
              ),
              metric(
                Icons.token_rounded,
                text(zh: 'Token', en: 'Tokens'),
                '${data.settings.totalTokens}',
              ),
            ],
          ),
          const SizedBox(height: _kProxyOpsGap),
          _ProxyOpsTrendPanel(
            title: text(zh: '请求趋势', en: 'Request trend'),
            subtitle: text(zh: '最近 12 个采样桶', en: 'Last 12 samples'),
            series: [
              OpenHandChartSeries(
                label: text(zh: '成功', en: 'Success'),
                values: data.trendSuccess,
                color: OpenHandStatusColors.success,
              ),
              OpenHandChartSeries(
                label: text(zh: '失败', en: 'Failure'),
                values: data.trendFailure,
                color: cs.error,
              ),
            ],
            valueSuffix: '',
          ),
          const SizedBox(height: _kProxyOpsGap),
          recentPanel(),
        ],
      );
    case _ProxyOpsInsightKind.ingress:
    case _ProxyOpsInsightKind.ingressErrors:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statPanel(text(zh: '入口请求', en: 'Ingress'), Icons.input_rounded, [
            metric(
              Icons.input_rounded,
              text(zh: '入口请求', en: 'Ingress'),
              '${data.controller.runtimeRequestCount}',
            ),
            metric(
              Icons.report_problem_outlined,
              text(zh: '入口错误', en: 'Errors'),
              '${data.controller.runtimeErrorCount}',
              helper: 'HTTP 4xx/5xx',
              color: cs.error,
            ),
            metric(
              Icons.swap_vert_rounded,
              text(zh: '入口流量', en: 'Inbound'),
              formatByteSize(data.controller.runtimeInboundBytes),
            ),
          ]),
          const SizedBox(height: _kProxyOpsGap),
          recentPanel(),
        ],
      );
    case _ProxyOpsInsightKind.succeeded:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statPanel(
            text(zh: '成功概览', en: 'Success overview'),
            Icons.verified_rounded,
            [
              metric(
                Icons.task_alt_rounded,
                text(zh: '成功数量', en: 'Succeeded'),
                '${data.successTotal}',
                helper: '${(data.successRate * 100).toStringAsFixed(1)}%',
                color: OpenHandStatusColors.success,
              ),
              metric(
                Icons.call_made_rounded,
                text(zh: '请求总数', en: 'Requests'),
                '${data.requestTotal}',
              ),
              metric(
                Icons.speed_rounded,
                text(zh: '平均耗时', en: 'Average'),
                '${data.settings.averageDurationMs.toStringAsFixed(0)} ms',
              ),
            ],
          ),
          const SizedBox(height: _kProxyOpsGap),
          recentPanel(
            title: '成功请求',
            records: data.records.where((record) => record.success),
          ),
        ],
      );
    case _ProxyOpsInsightKind.failures:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statPanel(
            text(zh: '失败概览', en: 'Failure overview'),
            Icons.report_rounded,
            [
              metric(
                Icons.error_outline_rounded,
                text(zh: '失败数量', en: 'Failures'),
                '${data.failureTotal}',
                helper: '${(data.failureRate * 100).toStringAsFixed(1)}%',
                color: cs.error,
              ),
              metric(
                Icons.call_made_rounded,
                text(zh: '请求总数', en: 'Requests'),
                '${data.requestTotal}',
              ),
              metric(
                Icons.warning_amber_rounded,
                text(zh: '入口错误', en: 'Ingress errors'),
                '${data.controller.runtimeErrorCount}',
                color: cs.error,
              ),
            ],
          ),
          const SizedBox(height: _kProxyOpsGap),
          recentPanel(
            title: '失败请求',
            records: data.records.where((record) => !record.success),
          ),
        ],
      );
    case _ProxyOpsInsightKind.averageLatency:
    case _ProxyOpsInsightKind.p95Latency:
    case _ProxyOpsInsightKind.latencyTrend:
      final slowest = [...data.records]
        ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statPanel(
            text(zh: '耗时概览', en: 'Latency overview'),
            Icons.timer_rounded,
            [
              metric(
                Icons.speed_rounded,
                text(zh: '平均耗时', en: 'Average'),
                '${data.settings.averageDurationMs.toStringAsFixed(0)} ms',
              ),
              metric(
                Icons.timeline_rounded,
                'P95',
                '${data.p95LatencyMs} ms',
                color: cs.tertiary,
              ),
              metric(
                Icons.trending_down_rounded,
                text(zh: '最慢调用', en: 'Slowest'),
                slowest.isEmpty ? '0 ms' : '${slowest.first.durationMs} ms',
                color: cs.error,
              ),
            ],
          ),
          const SizedBox(height: _kProxyOpsGap),
          _ProxyOpsTrendPanel(
            title: text(zh: '耗时曲线', en: 'Latency curve'),
            subtitle: text(
              zh: '平均耗时与 P95 尾延迟',
              en: 'Average and P95 tail latency',
            ),
            series: [
              OpenHandChartSeries(
                label: text(zh: '平均', en: 'Average'),
                values: _ProxyOpsTrendRow._latencySeries(data),
                color: cs.primary,
              ),
              OpenHandChartSeries(
                label: 'P95',
                values: _ProxyOpsTrendRow._p95Series(data),
                color: cs.tertiary,
              ),
            ],
            valueSuffix: ' ms',
          ),
          const SizedBox(height: _kProxyOpsGap),
          recentPanel(title: '最慢调用', records: slowest.take(20)),
        ],
      );
    case _ProxyOpsInsightKind.tokens:
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statPanel(
            text(zh: 'Token 消耗', en: 'Token usage'),
            Icons.token_rounded,
            [
              metric(
                Icons.token_rounded,
                text(zh: 'Token 总量', en: 'Total tokens'),
                '${data.settings.totalTokens}',
              ),
              metric(
                Icons.call_made_rounded,
                text(zh: '请求总数', en: 'Requests'),
                '${data.requestTotal}',
              ),
              metric(
                Icons.analytics_rounded,
                text(zh: '平均每次', en: 'Average/request'),
                data.requestTotal <= 0
                    ? '0'
                    : (data.settings.totalTokens / data.requestTotal)
                          .toStringAsFixed(1),
              ),
            ],
          ),
          const SizedBox(height: _kProxyOpsGap),
          _ProxyOpsDetailDistribution(
            title: text(zh: '模型 Token 请求分布', en: 'Token request model mix'),
            icon: Icons.model_training_rounded,
            values: _countProxyBy(
              data.records,
              (record) => record.modelId,
              text(zh: '未知', en: 'Unknown'),
            ),
          ),
        ],
      );
    case _ProxyOpsInsightKind.inbound:
    case _ProxyOpsInsightKind.outbound:
      final inbound = kind == _ProxyOpsInsightKind.inbound;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          statPanel(
            inbound
                ? text(zh: '入口流量', en: 'Inbound traffic')
                : text(zh: '出口流量', en: 'Outbound traffic'),
            inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
            [
              metric(
                inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
                inbound
                    ? text(zh: '入口流量', en: 'Inbound')
                    : text(zh: '出口流量', en: 'Outbound'),
                formatByteSize(
                  inbound
                      ? data.controller.runtimeInboundBytes
                      : data.controller.runtimeOutboundBytes,
                ),
              ),
              metric(
                Icons.call_made_rounded,
                text(zh: '请求总数', en: 'Requests'),
                '${data.requestTotal}',
              ),
            ],
          ),
          const SizedBox(height: _kProxyOpsGap),
          recentPanel(),
        ],
      );
    case _ProxyOpsInsightKind.exposedModels:
      return _ProxyOpsRoutePanel(data: data, showBackends: false);
    case _ProxyOpsInsightKind.backends:
      return _ProxyOpsRoutePanel(data: data, showBackends: true);
    case _ProxyOpsInsightKind.requestTrend:
      return _ProxyOpsTrendPanel(
        title: text(zh: '请求趋势', en: 'Request trend'),
        subtitle: text(
          zh: '最近 12 个采样桶 · 成功与失败',
          en: 'Last 12 samples · success and failure',
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
            color: cs.error,
          ),
        ],
        valueSuffix: '',
      );
    case _ProxyOpsInsightKind.statusMix:
      return _ProxyOpsDetailDistribution(
        title: text(zh: '状态分布', en: 'Status mix'),
        icon: Icons.donut_small_rounded,
        values: {
          text(zh: '成功', en: 'Success'): data.successTotal,
          text(zh: '失败', en: 'Failure'): data.failureTotal,
        },
      );
    case _ProxyOpsInsightKind.providerMix:
      return _ProxyOpsDetailDistribution(
        title: text(zh: '提供商分布', en: 'Provider mix'),
        icon: Icons.hub_outlined,
        values: _countProxyBy(
          data.records,
          (record) => data.providerLabelFor(
            record,
            unknown: text(zh: '未知', en: 'Unknown'),
          ),
          text(zh: '未知', en: 'Unknown'),
        ),
      );
    case _ProxyOpsInsightKind.modelMix:
      return _ProxyOpsDetailDistribution(
        title: text(zh: '模型分布', en: 'Model mix'),
        icon: Icons.model_training_outlined,
        values: _countProxyBy(
          data.records,
          (record) => record.modelId,
          text(zh: '未知', en: 'Unknown'),
        ),
      );
    case _ProxyOpsInsightKind.clientMix:
      return _ProxyOpsDetailDistribution(
        title: text(zh: '协议与客户端', en: 'Protocol and clients'),
        icon: Icons.devices_other_rounded,
        values: _countProxyBy(
          data.records,
          _ProxyOpsDistributionGrid._clientDistributionLabel,
          text(zh: '未知', en: 'Unknown'),
        ),
      );
    case _ProxyOpsInsightKind.recentRequest:
      return recentPanel();
  }
}

int _proxyOpsCurrentRpm(_ProxyOpsSnapshot data) {
  final now = DateTime.now();
  return data.records.where((record) {
    final age = now.difference(record.startedAt);
    return age >= Duration.zero && age < const Duration(minutes: 1);
  }).length;
}

Map<String, int> _countProxyBy(
  Iterable<AiModelProxyRequestRecord> records,
  String Function(AiModelProxyRequestRecord) keyOf,
  String unknown,
) {
  final result = <String, int>{};
  for (final record in records) {
    final key = keyOf(record).trim();
    final normalized = key.isEmpty ? unknown : key;
    result[normalized] = (result[normalized] ?? 0) + 1;
  }
  return result;
}

class _ProxyOpsDetailDistribution extends StatelessWidget {
  const _ProxyOpsDetailDistribution({
    required this.title,
    required this.icon,
    required this.values,
  });

  final String title;
  final IconData icon;
  final Map<String, int> values;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = values.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<int>(0, (sum, entry) => sum + entry.value);
    final palette = [
      cs.primary,
      cs.tertiary,
      cs.secondary,
      OpenHandStatusColors.success,
      OpenHandStatusColors.warning,
      cs.error,
    ];
    return _ProxyOpsPanel(
      title: title,
      icon: icon,
      child: sorted.isEmpty
          ? Text(
              openHandTextResolver(context)(
                zh: '暂无样本数据。',
                en: 'No samples yet.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            )
          : Column(
              children: [
                for (var index = 0; index < sorted.length; index++)
                  _ProxyOpsDistributionRow(
                    label: sorted[index].key,
                    value: sorted[index].value,
                    total: total,
                    color: palette[index % palette.length],
                  ),
              ],
            ),
    );
  }
}

class _ProxyOpsRoutePanel extends StatelessWidget {
  const _ProxyOpsRoutePanel({required this.data, required this.showBackends});

  final _ProxyOpsSnapshot data;
  final bool showBackends;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final routes = data.settings.routes
        .where((route) => route.enabled)
        .toList(growable: false);
    final rows = <Widget>[];
    for (final route in routes) {
      if (!showBackends) {
        rows.add(
          _ProxyOpsRouteRow(
            title: route.exposedModel,
            subtitle:
                '${route.backends.where((backend) => backend.enabled).length} ${text(zh: '个后备模型', en: 'backends')}',
            icon: Icons.hub_rounded,
          ),
        );
      } else {
        for (final backend in route.backends.where(
          (backend) => backend.enabled,
        )) {
          rows.add(
            _ProxyOpsRouteRow(
              title: backend.modelId,
              subtitle:
                  '${data.providerLabelForId(backend.providerId) ?? backend.providerId} · ${route.exposedModel}',
              icon: Icons.storage_rounded,
            ),
          );
        }
      }
    }
    return _ProxyOpsPanel(
      title: showBackends
          ? text(zh: '后备模型', en: 'Backends')
          : text(zh: '启用模型', en: 'Exposed models'),
      icon: showBackends ? Icons.storage_rounded : Icons.hub_rounded,
      child: rows.isEmpty
          ? Text(
              text(zh: '暂无启用路由。', en: 'No enabled routes.'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 18),
                  rows[i],
                ],
              ],
            ),
    );
  }
}

class _ProxyOpsRouteRow extends StatelessWidget {
  const _ProxyOpsRouteRow({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, color: cs.primary, size: 20),
        kOpenHandHGap10,
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        kOpenHandHGap10,
        Flexible(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

IconData _proxyOpsInsightIcon(_ProxyOpsInsightKind kind) => switch (kind) {
  _ProxyOpsInsightKind.connections => Icons.link_rounded,
  _ProxyOpsInsightKind.activeRequests => Icons.bolt_rounded,
  _ProxyOpsInsightKind.requests => Icons.call_made_rounded,
  _ProxyOpsInsightKind.ingress => Icons.input_rounded,
  _ProxyOpsInsightKind.succeeded => Icons.task_alt_rounded,
  _ProxyOpsInsightKind.failures ||
  _ProxyOpsInsightKind.ingressErrors => Icons.error_outline_rounded,
  _ProxyOpsInsightKind.averageLatency ||
  _ProxyOpsInsightKind.p95Latency ||
  _ProxyOpsInsightKind.latencyTrend => Icons.speed_rounded,
  _ProxyOpsInsightKind.tokens => Icons.token_rounded,
  _ProxyOpsInsightKind.inbound => Icons.south_west_rounded,
  _ProxyOpsInsightKind.outbound => Icons.north_east_rounded,
  _ProxyOpsInsightKind.exposedModels => Icons.hub_rounded,
  _ProxyOpsInsightKind.backends => Icons.storage_rounded,
  _ProxyOpsInsightKind.requestTrend => Icons.show_chart_rounded,
  _ProxyOpsInsightKind.statusMix => Icons.donut_small_rounded,
  _ProxyOpsInsightKind.providerMix => Icons.hub_outlined,
  _ProxyOpsInsightKind.modelMix => Icons.model_training_outlined,
  _ProxyOpsInsightKind.clientMix => Icons.devices_other_rounded,
  _ProxyOpsInsightKind.recentRequest => Icons.receipt_long_rounded,
};

String _proxyOpsInsightTitle(BuildContext context, _ProxyOpsInsightKind kind) {
  final text = openHandTextResolver(context);
  return switch (kind) {
    _ProxyOpsInsightKind.connections => text(zh: '连接明细', en: 'Connections'),
    _ProxyOpsInsightKind.activeRequests => text(
      zh: '活跃请求',
      en: 'Active requests',
    ),
    _ProxyOpsInsightKind.requests => text(zh: '请求总览', en: 'Requests'),
    _ProxyOpsInsightKind.ingress => text(zh: '入口请求', en: 'Ingress requests'),
    _ProxyOpsInsightKind.succeeded => text(
      zh: '成功请求',
      en: 'Succeeded requests',
    ),
    _ProxyOpsInsightKind.failures => text(zh: '失败明细', en: 'Failures'),
    _ProxyOpsInsightKind.ingressErrors => text(
      zh: '入口错误',
      en: 'Ingress errors',
    ),
    _ProxyOpsInsightKind.averageLatency ||
    _ProxyOpsInsightKind.p95Latency ||
    _ProxyOpsInsightKind.latencyTrend => text(zh: '耗时分析', en: 'Latency'),
    _ProxyOpsInsightKind.tokens => text(zh: 'Token 消耗', en: 'Token usage'),
    _ProxyOpsInsightKind.inbound => text(zh: '入口流量', en: 'Inbound traffic'),
    _ProxyOpsInsightKind.outbound => text(zh: '出口流量', en: 'Outbound traffic'),
    _ProxyOpsInsightKind.exposedModels => text(
      zh: '启用模型',
      en: 'Exposed models',
    ),
    _ProxyOpsInsightKind.backends => text(zh: '后备模型', en: 'Backends'),
    _ProxyOpsInsightKind.requestTrend => text(zh: '请求趋势', en: 'Request trend'),
    _ProxyOpsInsightKind.statusMix => text(zh: '状态分布', en: 'Status mix'),
    _ProxyOpsInsightKind.providerMix => text(zh: '提供商分布', en: 'Provider mix'),
    _ProxyOpsInsightKind.modelMix => text(zh: '模型分布', en: 'Model mix'),
    _ProxyOpsInsightKind.clientMix => text(
      zh: '协议与客户端',
      en: 'Protocol and clients',
    ),
    _ProxyOpsInsightKind.recentRequest => text(
      zh: '请求明细',
      en: 'Request details',
    ),
  };
}

Color _proxyOpsInsightTone(BuildContext context, _ProxyOpsInsightKind kind) {
  final cs = Theme.of(context).colorScheme;
  return switch (kind) {
    _ProxyOpsInsightKind.succeeded => OpenHandStatusColors.success,
    _ProxyOpsInsightKind.failures ||
    _ProxyOpsInsightKind.ingressErrors => cs.error,
    _ProxyOpsInsightKind.activeRequests ||
    _ProxyOpsInsightKind.p95Latency => cs.tertiary,
    _ => cs.primary,
  };
}
