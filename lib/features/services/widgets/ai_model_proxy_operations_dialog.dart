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
          : SizedBox(
              height: _kProxyOpsRecentMaxHeight,
              child: OpenHandSafeScrollbar(
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  primary: false,
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
                            _proxyOpsInsightSubtitle(context, kind),
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
) => _ProxyOpsUniqueDetail(data: data, kind: kind);

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

/// 每个运维卡片的专属详情内容。外层弹窗保持统一动画与安全边界，内部按
/// 遥测语义选择不同的信息形态，避免同一项数据在多个详情中重复出现。
class _ProxyOpsUniqueDetail extends StatelessWidget {
  const _ProxyOpsUniqueDetail({required this.data, required this.kind});

  final _ProxyOpsSnapshot data;
  final _ProxyOpsInsightKind kind;

  @override
  Widget build(BuildContext context) {
    return switch (kind) {
      _ProxyOpsInsightKind.connections => _connections(context),
      _ProxyOpsInsightKind.activeRequests => _activeRequests(context),
      _ProxyOpsInsightKind.requests => _requests(context),
      _ProxyOpsInsightKind.ingress => _ingress(context),
      _ProxyOpsInsightKind.ingressErrors => _ingressErrors(context),
      _ProxyOpsInsightKind.succeeded => _succeeded(context),
      _ProxyOpsInsightKind.failures => _failures(context),
      _ProxyOpsInsightKind.averageLatency => _averageLatency(context),
      _ProxyOpsInsightKind.p95Latency => _p95Latency(context),
      _ProxyOpsInsightKind.latencyTrend => _latencyTrend(context),
      _ProxyOpsInsightKind.tokens => _tokens(context),
      _ProxyOpsInsightKind.inbound => _traffic(context, inbound: true),
      _ProxyOpsInsightKind.outbound => _traffic(context, inbound: false),
      _ProxyOpsInsightKind.exposedModels => _routes(
        context,
        showBackends: false,
      ),
      _ProxyOpsInsightKind.backends => _routes(context, showBackends: true),
      _ProxyOpsInsightKind.requestTrend => _requestTrend(context),
      _ProxyOpsInsightKind.statusMix => _statusMix(context),
      _ProxyOpsInsightKind.providerMix => _providerMix(context),
      _ProxyOpsInsightKind.modelMix => _modelMix(context),
      _ProxyOpsInsightKind.clientMix => _clientMix(context),
      _ProxyOpsInsightKind.recentRequest => _requests(context),
    };
  }

  Widget _metric(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    String helper = '',
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return _ProxyOpsMetric(
      metric: _ProxyOpsMetricData(
        icon,
        label,
        value,
        helper,
        color ?? cs.primary,
      ),
    );
  }

  Widget _metricGrid(BuildContext context, List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 2 : 1;
        const gap = _kProxyOpsGap;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }

  Widget _connections(BuildContext context) {
    final text = openHandTextResolver(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProxyOpsPanel(
          title: text(zh: '连接拓扑', en: 'Connection topology'),
          icon: Icons.hub_rounded,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: 0.14),
                  cs.tertiary.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                _ProxyOpsNodeBadge(
                  icon: Icons.devices_rounded,
                  label: text(zh: '客户端', en: 'Clients'),
                  value: '${data.controller.currentConnections}',
                  color: cs.primary,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        Icon(Icons.arrow_forward_rounded, color: cs.primary),
                        const SizedBox(height: 6),
                        Text(
                          data.endpoint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                _ProxyOpsNodeBadge(
                  icon: Icons.cloud_done_rounded,
                  label: text(zh: '服务状态', en: 'Service state'),
                  value: _lifecycleLabel(context, data.controller.lifecycle),
                  color: cs.tertiary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: _kProxyOpsGap),
        _ProxyOpsPanel(
          title: text(zh: '连接属性', en: 'Connection properties'),
          icon: Icons.tune_rounded,
          child: _metricGrid(context, [
            _metric(
              context,
              Icons.schedule_rounded,
              text(zh: '运行时长', en: 'Uptime'),
              formatCompactDuration(data.controller.uptime),
            ),
            _metric(
              context,
              Icons.alt_route_rounded,
              text(zh: '调度策略', en: 'Scheduling'),
              data.settings.scheduling.label,
              color: cs.tertiary,
            ),
            _metric(
              context,
              Icons.lock_rounded,
              text(zh: '访问鉴权', en: 'Authentication'),
              data.settings.requireAuthentication
                  ? text(zh: '已启用', en: 'Enabled')
                  : text(zh: '未启用', en: 'Disabled'),
            ),
            _metric(
              context,
              Icons.api_rounded,
              text(zh: '接口风格', en: 'API style'),
              data.settings.apiStyle.label,
            ),
          ]),
        ),
      ],
    );
  }

  Widget _activeRequests(BuildContext context) {
    final text = openHandTextResolver(context);
    final cs = Theme.of(context).colorScheme;
    final modes = _countProxyBy(
      data.records,
      (record) => record.proxyMode,
      text(zh: '未知模式', en: 'Unknown mode'),
    );
    final active = data.controller.activeRequests;
    final capacity = data.settings.limitThreshold.clamp(1, 1000000);
    final ratio = (active / capacity).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProxyOpsPanel(
          title: text(zh: '实时执行队列', en: 'Live execution queue'),
          icon: Icons.bolt_rounded,
          child: Row(
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: ratio),
                      duration: openHandMotionDuration(
                        context,
                        kOpenHandMotion420,
                      ),
                      curve: kOpenHandSwitchInCurve,
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value,
                        strokeWidth: 12,
                        backgroundColor: cs.surfaceContainerHighest,
                        color: cs.tertiary,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$active',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          text(zh: '执行中', en: 'in flight'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              kOpenHandHGap18,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text(
                        zh: data.settings.limitThreshold > 0
                            ? '当前执行量 / 配置阈值'
                            : '当前执行量 / 无限制',
                        en: data.settings.limitThreshold > 0
                            ? 'In flight / configured threshold'
                            : 'In flight / unlimited',
                      ),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    kOpenHandGap8,
                    Text(
                      data.settings.limitThreshold > 0
                          ? '$active / ${data.settings.limitThreshold}'
                          : '$active / ∞',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: cs.tertiary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    kOpenHandGap8,
                    Text(
                      text(
                        zh: active == 0 ? '当前没有等待中的请求' : '请求正在占用执行槽位',
                        en: active == 0
                            ? 'No request is waiting right now'
                            : 'Requests are occupying execution slots',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: _kProxyOpsGap),
        _ProxyOpsDetailDistribution(
          title: text(zh: '执行模式', en: 'Execution modes'),
          icon: Icons.alt_route_rounded,
          values: modes,
        ),
      ],
    );
  }

  Widget _requests(BuildContext context) {
    final text = openHandTextResolver(context);
    final cs = Theme.of(context).colorScheme;
    final apiStyles = _countProxyBy(
      data.records,
      (record) => record.apiStyle,
      text(zh: '未知协议', en: 'Unknown protocol'),
    );
    final recent = data.records.reversed.take(12).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProxyOpsPanel(
          title: text(zh: '请求脉络', en: 'Request pulse'),
          icon: Icons.insights_rounded,
          subtitle: text(
            zh: '只展示请求量与接口协议构成',
            en: 'Request volume and API protocol composition',
          ),
          child: _metricGrid(context, [
            _metric(
              context,
              Icons.call_made_rounded,
              text(zh: '累计请求', en: 'Total requests'),
              '${data.requestTotal}',
            ),
            _metric(
              context,
              Icons.history_toggle_off_rounded,
              text(zh: '最近样本', en: 'Recent samples'),
              '${recent.length}',
              helper: text(zh: '最多展示 12 条', en: 'Up to 12 samples'),
              color: cs.tertiary,
            ),
          ]),
        ),
        const SizedBox(height: _kProxyOpsGap),
        _ProxyOpsDetailDistribution(
          title: text(zh: '接口协议构成', en: 'API protocol mix'),
          icon: Icons.api_rounded,
          values: apiStyles,
        ),
        const SizedBox(height: _kProxyOpsGap),
        _ProxyOpsRequestLedger(
          title: text(zh: '请求时间线', en: 'Request timeline'),
          icon: Icons.view_list_rounded,
          records: recent,
          data: data,
          accent: cs.primary,
        ),
      ],
    );
  }

  Widget _ingress(BuildContext context) {
    final text = openHandTextResolver(context);
    final protocols = _countProxyBy(
      data.records,
      (record) => record.apiStyle,
      text(zh: '未知协议', en: 'Unknown protocol'),
    );
    final clients = _countProxyBy(
      data.records,
      (record) => record.clientIp,
      text(zh: '未知地址', en: 'Unknown address'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProxyOpsPanel(
          title: text(zh: '入口画像', en: 'Ingress profile'),
          icon: Icons.input_rounded,
          child: _metricGrid(context, [
            _metric(
              context,
              Icons.input_rounded,
              text(zh: '入口请求', en: 'Ingress requests'),
              '${data.controller.runtimeRequestCount}',
            ),
            _metric(
              context,
              Icons.public_rounded,
              text(zh: '来源地址', en: 'Source addresses'),
              '${clients.length}',
            ),
          ]),
        ),
        const SizedBox(height: _kProxyOpsGap),
        _ProxyOpsDetailDistribution(
          title: text(zh: '入口协议', en: 'Ingress protocols'),
          icon: Icons.api_rounded,
          values: protocols,
        ),
        const SizedBox(height: _kProxyOpsGap),
        _ProxyOpsAddressLedger(
          title: text(zh: '来源地址排行', en: 'Source address ranking'),
          values: clients,
        ),
      ],
    );
  }

  Widget _ingressErrors(BuildContext context) {
    final text = openHandTextResolver(context);
    final failures = data.records
        .where((record) => !record.success)
        .toList(growable: false);
    final protocols = _countProxyBy(
      failures,
      (record) => record.apiStyle,
      text(zh: '未知协议', en: 'Unknown protocol'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProxyOpsErrorBanner(
          count: data.controller.runtimeErrorCount,
          title: text(zh: '入口错误账本', en: 'Ingress error ledger'),
          subtitle: text(
            zh: '仅记录 HTTP 4xx/5xx 入口错误与失败原因',
            en: 'HTTP 4xx/5xx ingress errors and failure reasons only',
          ),
        ),
        const SizedBox(height: _kProxyOpsGap),
        _ProxyOpsDetailDistribution(
          title: text(zh: '错误入口协议', en: 'Error ingress protocols'),
          icon: Icons.api_rounded,
          values: protocols,
        ),
      ],
    );
  }

  Widget _succeeded(BuildContext context) {
    final text = openHandTextResolver(context);
    final success = data.records
        .where((record) => record.success)
        .toList(growable: false);
    final latencyBands = _countProxyBy(
      success,
      (record) => record.durationMs < 1000
          ? text(zh: '快速 < 1s', en: 'Fast < 1s')
          : record.durationMs < 3000
          ? text(zh: '正常 1-3s', en: 'Normal 1-3s')
          : text(zh: '慢速 >= 3s', en: 'Slow >= 3s'),
      text(zh: '未知耗时', en: 'Unknown latency'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProxyOpsSuccessBanner(
          successCount: data.successTotal,
          successRate: data.successRate,
        ),
        const SizedBox(height: _kProxyOpsGap),
        _ProxyOpsDetailDistribution(
          title: text(zh: '成功耗时带', en: 'Successful latency bands'),
          icon: Icons.speed_rounded,
          values: latencyBands,
        ),
        const SizedBox(height: _kProxyOpsGap),
        _ProxyOpsSuccessTimeline(
          title: text(zh: '成功样本', en: 'Successful samples'),
          records: success.reversed.take(20),
          data: data,
        ),
      ],
    );
  }

  Widget _failures(BuildContext context) {
    final text = openHandTextResolver(context);
    final failures = data.records
        .where((record) => !record.success)
        .toList(growable: false);
    final reasons = _countProxyBy(
      failures,
      (record) => record.error ?? text(zh: '未提供错误原因', en: 'No error reason'),
      text(zh: '未提供错误原因', en: 'No error reason'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProxyOpsErrorBanner(
          count: data.failureTotal,
          title: text(zh: '失败诊断', en: 'Failure diagnosis'),
          subtitle: text(
            zh: '按失败模型聚合，帮助快速定位路由问题',
            en: 'Grouped by failed model for route diagnosis',
          ),
        ),
        const SizedBox(height: _kProxyOpsGap),
        _ProxyOpsDetailDistribution(
          title: text(zh: '失败原因排行', en: 'Failure reason ranking'),
          icon: Icons.rule_rounded,
          values: reasons,
        ),
        const SizedBox(height: _kProxyOpsGap),
        _ProxyOpsFailureLedger(
          title: text(zh: '失败样本与原因', en: 'Failure samples and reasons'),
          records: failures.reversed.take(30),
          data: data,
        ),
      ],
    );
  }

  Widget _averageLatency(BuildContext context) {
    final text = openHandTextResolver(context);
    final aggregates = _aggregateProxyBy(
      data.records,
      (record) => record.modelId.isEmpty
          ? text(zh: '未知模型', en: 'Unknown model')
          : record.modelId,
    );
    return _ProxyOpsAggregateTable(
      title: text(zh: '模型平均耗时', en: 'Average latency by model'),
      icon: Icons.speed_rounded,
      aggregates: aggregates,
      accent: Theme.of(context).colorScheme.primary,
      showLatency: true,
    );
  }

  Widget _p95Latency(BuildContext context) {
    final text = openHandTextResolver(context);
    final sorted = [...data.records]
      ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
    return _ProxyOpsTailLatencyPanel(
      title: text(zh: 'P95 尾延迟样本', en: 'P95 tail samples'),
      subtitle: text(
        zh: '按耗时从高到低展示最近尾部请求',
        en: 'Recent tail requests ranked by duration',
      ),
      p95Ms: data.p95LatencyMs,
      records: sorted.take(24).toList(growable: false),
      data: data,
    );
  }

  Widget _latencyTrend(BuildContext context) {
    final text = openHandTextResolver(context);
    return _ProxyOpsTrendDetail(
      title: text(zh: '耗时趋势时间桶', en: 'Latency trend buckets'),
      subtitle: text(
        zh: '平均耗时与 P95 的逐桶明细',
        en: 'Per-bucket average and P95 detail',
      ),
      series: [
        OpenHandChartSeries(
          label: text(zh: '平均', en: 'Average'),
          values: _ProxyOpsTrendRow._latencySeries(data),
          color: Theme.of(context).colorScheme.primary,
        ),
        OpenHandChartSeries(
          label: 'P95',
          values: _ProxyOpsTrendRow._p95Series(data),
          color: Theme.of(context).colorScheme.tertiary,
        ),
      ],
      valueSuffix: ' ms',
    );
  }

  Widget _tokens(BuildContext context) {
    final text = openHandTextResolver(context);
    final aggregates = _aggregateProxyBy(
      data.records,
      (record) => record.modelId.isEmpty
          ? text(zh: '未知模型', en: 'Unknown model')
          : record.modelId,
    );
    return _ProxyOpsAggregateTable(
      title: text(zh: '模型 Token 消耗', en: 'Token usage by model'),
      icon: Icons.token_rounded,
      aggregates: aggregates,
      accent: Theme.of(context).colorScheme.primary,
      showTokens: true,
    );
  }

  Widget _traffic(BuildContext context, {required bool inbound}) {
    final text = openHandTextResolver(context);
    final bytes = inbound
        ? data.controller.runtimeInboundBytes
        : data.controller.runtimeOutboundBytes;
    final count = data.controller.runtimeRequestCount;
    return _ProxyOpsTrafficFlow(
      inbound: inbound,
      title: inbound
          ? text(zh: '入口流量流向', en: 'Inbound flow')
          : text(zh: '出口流量流向', en: 'Outbound flow'),
      bytes: bytes,
      requestCount: count,
      endpoint: data.endpoint,
    );
  }

  Widget _routes(BuildContext context, {required bool showBackends}) {
    final text = openHandTextResolver(context);
    final routes = data.settings.routes
        .where((route) => route.enabled)
        .toList(growable: false);
    return _ProxyOpsRouteTopology(
      title: showBackends
          ? text(zh: '后备模型拓扑', en: 'Backend topology')
          : text(zh: '对外模型拓扑', en: 'Exposed model topology'),
      routes: routes,
      data: data,
      showBackends: showBackends,
    );
  }

  Widget _requestTrend(BuildContext context) {
    final text = openHandTextResolver(context);
    return _ProxyOpsTrendDetail(
      title: text(zh: '请求趋势时间桶', en: 'Request trend buckets'),
      subtitle: text(
        zh: '成功与失败按采样桶展开',
        en: 'Success and failure per sample bucket',
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
    );
  }

  Widget _statusMix(BuildContext context) {
    final text = openHandTextResolver(context);
    return _ProxyOpsStatusDonut(
      title: text(zh: '状态占比', en: 'Status share'),
      values: {
        text(zh: '成功', en: 'Success'): data.successTotal,
        text(zh: '失败', en: 'Failure'): data.failureTotal,
      },
      colors: [
        OpenHandStatusColors.success,
        Theme.of(context).colorScheme.error,
      ],
    );
  }

  Widget _providerMix(BuildContext context) {
    final text = openHandTextResolver(context);
    final aggregates = _aggregateProxyBy(
      data.records,
      (record) => data.providerLabelFor(
        record,
        unknown: text(zh: '未知提供商', en: 'Unknown provider'),
      ),
    );
    return _ProxyOpsAggregateTable(
      title: text(zh: '提供商服务排行', en: 'Provider leaderboard'),
      icon: Icons.hub_outlined,
      aggregates: aggregates,
      accent: Theme.of(context).colorScheme.tertiary,
      showSuccessRate: true,
    );
  }

  Widget _modelMix(BuildContext context) {
    final text = openHandTextResolver(context);
    final aggregates = _aggregateProxyBy(
      data.records,
      (record) => record.modelId.isEmpty
          ? text(zh: '未知模型', en: 'Unknown model')
          : record.modelId,
    );
    return _ProxyOpsAggregateTable(
      title: text(zh: '模型调用排行', en: 'Model leaderboard'),
      icon: Icons.model_training_outlined,
      aggregates: aggregates,
      accent: Theme.of(context).colorScheme.primary,
      showSuccessRate: true,
    );
  }

  Widget _clientMix(BuildContext context) {
    final text = openHandTextResolver(context);
    final records = data.records.toList(growable: false);
    return _ProxyOpsClientLedger(
      title: text(zh: '客户端 UA 明细', en: 'Client UA details'),
      records: records,
    );
  }
}

class _ProxyOpsNodeBadge extends StatelessWidget {
  const _ProxyOpsNodeBadge({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Icon(icon, color: color),
        ),
        kOpenHandGap6,
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ProxyOpsAggregate {
  int requests = 0;
  int successes = 0;
  int tokens = 0;
  int durationMs = 0;
}

Map<String, _ProxyOpsAggregate> _aggregateProxyBy(
  Iterable<AiModelProxyRequestRecord> records,
  String Function(AiModelProxyRequestRecord record) keyOf,
) {
  final result = <String, _ProxyOpsAggregate>{};
  for (final record in records) {
    final key = keyOf(record).trim();
    if (key.isEmpty) continue;
    final aggregate = result.putIfAbsent(key, _ProxyOpsAggregate.new);
    aggregate.requests += 1;
    aggregate.successes += record.success ? 1 : 0;
    aggregate.tokens += record.tokens;
    aggregate.durationMs += record.durationMs;
  }
  return result;
}

class _ProxyOpsAggregateTable extends StatelessWidget {
  const _ProxyOpsAggregateTable({
    required this.title,
    required this.icon,
    required this.aggregates,
    required this.accent,
    this.showLatency = false,
    this.showTokens = false,
    this.showSuccessRate = false,
  });

  final String title;
  final IconData icon;
  final Map<String, _ProxyOpsAggregate> aggregates;
  final Color accent;
  final bool showLatency;
  final bool showTokens;
  final bool showSuccessRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sorted = aggregates.entries.toList()
      ..sort((a, b) => b.value.requests.compareTo(a.value.requests));
    final total = sorted.fold<int>(0, (sum, item) => sum + item.value.requests);
    return _ProxyOpsPanel(
      title: title,
      icon: icon,
      child: sorted.isEmpty
          ? Text(
              openHandTextResolver(context)(
                zh: '暂无可聚合样本。',
                en: 'No aggregate samples yet.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < sorted.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 18,
                      color: cs.outlineVariant.withValues(alpha: 0.48),
                    ),
                  _ProxyOpsAggregateRow(
                    rank: index + 1,
                    label: sorted[index].key,
                    aggregate: sorted[index].value,
                    total: total,
                    accent: accent,
                    showLatency: showLatency,
                    showTokens: showTokens,
                    showSuccessRate: showSuccessRate,
                  ),
                ],
              ],
            ),
    );
  }
}

class _ProxyOpsAggregateRow extends StatelessWidget {
  const _ProxyOpsAggregateRow({
    required this.rank,
    required this.label,
    required this.aggregate,
    required this.total,
    required this.accent,
    required this.showLatency,
    required this.showTokens,
    required this.showSuccessRate,
  });

  final int rank;
  final String label;
  final _ProxyOpsAggregate aggregate;
  final int total;
  final Color accent;
  final bool showLatency;
  final bool showTokens;
  final bool showSuccessRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = total <= 0
        ? 0.0
        : (aggregate.requests / total).clamp(0.0, 1.0).toDouble();
    final detail = showLatency
        ? '${aggregate.requests} · ${(aggregate.durationMs / aggregate.requests).toStringAsFixed(0)} ms'
        : showTokens
        ? '${aggregate.requests} · ${aggregate.tokens} tokens'
        : showSuccessRate
        ? '${aggregate.requests} · ${(aggregate.successes / aggregate.requests * 100).toStringAsFixed(1)}%'
        : '${aggregate.requests}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: rank <= 3 ? 0.16 : 0.08),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            kOpenHandHGap8,
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            kOpenHandHGap8,
            Text(
              detail,
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        kOpenHandGap6,
        ClipRRect(
          borderRadius: kOpenHandPillBorderRadius,
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            color: accent,
            backgroundColor: cs.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _ProxyOpsRequestLedger extends StatelessWidget {
  const _ProxyOpsRequestLedger({
    required this.title,
    required this.icon,
    required this.records,
    required this.data,
    required this.accent,
  });

  final String title;
  final IconData icon;
  final Iterable<AiModelProxyRequestRecord> records;
  final _ProxyOpsSnapshot data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final items = records.toList(growable: false);
    return _ProxyOpsPanel(
      title: title,
      icon: icon,
      child: items.isEmpty
          ? Text(
              text(zh: '暂无匹配记录。', en: 'No matching records.'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  _ProxyOpsLedgerRow(
                    record: items[index],
                    providerLabel: data.providerLabelFor(
                      items[index],
                      unknown: text(zh: '未知', en: 'Unknown'),
                    ),
                    accent: accent,
                  ),
                ],
              ],
            ),
    );
  }
}

class _ProxyOpsSuccessTimeline extends StatelessWidget {
  const _ProxyOpsSuccessTimeline({
    required this.title,
    required this.records,
    required this.data,
  });

  final String title;
  final Iterable<AiModelProxyRequestRecord> records;
  final _ProxyOpsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final items = records.toList(growable: false);
    final cs = Theme.of(context).colorScheme;
    return _ProxyOpsPanel(
      title: title,
      icon: Icons.timeline_rounded,
      child: items.isEmpty
          ? Text(
              openHandTextResolver(context)(
                zh: '暂无成功样本。',
                en: 'No successful samples.',
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < items.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: OpenHandStatusColors.success.withValues(
                              alpha: 0.14,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: OpenHandStatusColors.success,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        kOpenHandHGap9,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                items[index].modelId.isEmpty
                                    ? '未知模型'
                                    : items[index].modelId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              kOpenHandGap3,
                              Text(
                                '${data.providerLabelFor(items[index])} · ${items[index].tokens} tokens',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        kOpenHandHGap8,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${items[index].durationMs} ms',
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: OpenHandStatusColors.success,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            Text(
                              formatMonthDayHm(items[index].startedAt),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ProxyOpsFailureLedger extends StatelessWidget {
  const _ProxyOpsFailureLedger({
    required this.title,
    required this.records,
    required this.data,
  });

  final String title;
  final Iterable<AiModelProxyRequestRecord> records;
  final _ProxyOpsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final items = records.toList(growable: false);
    final cs = Theme.of(context).colorScheme;
    return _ProxyOpsPanel(
      title: title,
      icon: Icons.bug_report_rounded,
      child: items.isEmpty
          ? Text(
              openHandTextResolver(context)(
                zh: '暂无失败样本。',
                en: 'No failure samples.',
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < items.length; index++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.error.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: cs.error,
                              size: 18,
                            ),
                            kOpenHandHGap7,
                            Expanded(
                              child: Text(
                                items[index].modelId.isEmpty
                                    ? '未知模型'
                                    : items[index].modelId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            Text(
                              '${items[index].durationMs} ms',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cs.error,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ],
                        ),
                        kOpenHandGap5,
                        Text(
                          items[index].error?.trim().isNotEmpty == true
                              ? items[index].error!.trim()
                              : openHandTextResolver(context)(
                                  zh: '未提供错误原因',
                                  en: 'No error reason',
                                ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.error,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        kOpenHandGap5,
                        Text(
                          '${data.providerLabelFor(items[index])} · ${formatMonthDayHm(items[index].startedAt)}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ProxyOpsLedgerRow extends StatelessWidget {
  const _ProxyOpsLedgerRow({
    required this.record,
    required this.providerLabel,
    required this.accent,
  });

  final AiModelProxyRequestRecord record;
  final String providerLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = [
      providerLabel,
      record.modelId,
    ].where((value) => value.trim().isNotEmpty).join(' / ');
    final metadata = [
      if (record.apiStyle.trim().isNotEmpty) record.apiStyle,
      '${record.tokens} tokens',
      '${record.durationMs} ms',
      if (record.clientIp.trim().isNotEmpty) record.clientIp,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              record.success
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              color: record.success ? OpenHandStatusColors.success : cs.error,
              size: 19,
            ),
          ),
          kOpenHandHGap9,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? '未知请求' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                kOpenHandGap4,
                Text(
                  metadata,
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
          Text(
            formatMonthDayHm(record.startedAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyOpsAddressLedger extends StatelessWidget {
  const _ProxyOpsAddressLedger({required this.title, required this.values});

  final String title;
  final Map<String, int> values;

  @override
  Widget build(BuildContext context) {
    final sorted = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<int>(0, (sum, item) => sum + item.value);
    final cs = Theme.of(context).colorScheme;
    return _ProxyOpsPanel(
      title: title,
      icon: Icons.public_rounded,
      child: sorted.isEmpty
          ? Text(
              openHandTextResolver(context)(
                zh: '暂无来源地址。',
                en: 'No source addresses.',
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < sorted.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ProxyOpsDistributionRow(
                      label: sorted[index].key,
                      value: sorted[index].value,
                      total: total,
                      color: [cs.primary, cs.tertiary, cs.secondary][index % 3],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ProxyOpsErrorBanner extends StatelessWidget {
  const _ProxyOpsErrorBanner({
    required this.count,
    required this.title,
    required this.subtitle,
  });

  final int count;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.error.withValues(alpha: 0.16),
            cs.error.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.error.withValues(alpha: 0.34)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_rounded, color: cs.error, size: 28),
          ),
          kOpenHandHGap12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                kOpenHandGap4,
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            '$count',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: cs.error,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyOpsSuccessBanner extends StatelessWidget {
  const _ProxyOpsSuccessBanner({
    required this.successCount,
    required this.successRate,
  });

  final int successCount;
  final double successRate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const success = OpenHandStatusColors.success;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: success.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: success.withValues(alpha: 0.36)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: success, size: 42),
          kOpenHandHGap12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  openHandTextResolver(context)(
                    zh: '成功质量',
                    en: 'Success quality',
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                kOpenHandGap4,
                Text(
                  '${(successRate * 100).toStringAsFixed(1)}%',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            '$successCount',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: success,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProxyOpsTailLatencyPanel extends StatelessWidget {
  const _ProxyOpsTailLatencyPanel({
    required this.title,
    required this.subtitle,
    required this.p95Ms,
    required this.records,
    required this.data,
  });

  final String title;
  final String subtitle;
  final int p95Ms;
  final List<AiModelProxyRequestRecord> records;
  final _ProxyOpsSnapshot data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return _ProxyOpsPanel(
      title: title,
      subtitle: subtitle,
      icon: Icons.timelapse_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'p95',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '$p95Ms ms',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.tertiary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          kOpenHandGap10,
          ClipRRect(
            borderRadius: kOpenHandPillBorderRadius,
            child: LinearProgressIndicator(
              value: p95Ms <= 0
                  ? 0
                  : (records.isEmpty
                        ? 0
                        : (p95Ms / records.first.durationMs).clamp(0.0, 1.0)),
              minHeight: 9,
              color: cs.tertiary,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          kOpenHandGap14,
          for (var index = 0; index < records.length; index++) ...[
            if (index > 0)
              Divider(
                height: 16,
                color: cs.outlineVariant.withValues(alpha: 0.42),
              ),
            _ProxyOpsLedgerRow(
              record: records[index],
              providerLabel: data.providerLabelFor(records[index]),
              accent: cs.tertiary,
            ),
          ],
          if (records.isEmpty)
            Text(
              openHandTextResolver(context)(
                zh: '暂无耗时样本。',
                en: 'No latency samples.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProxyOpsTrendDetail extends StatelessWidget {
  const _ProxyOpsTrendDetail({
    required this.title,
    required this.subtitle,
    required this.series,
    required this.valueSuffix,
  });

  final String title;
  final String subtitle;
  final List<OpenHandChartSeries> series;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxValue = series
        .expand((item) => item.values)
        .fold<double>(0, (max, value) => math.max(max, value));
    return _ProxyOpsPanel(
      title: title,
      subtitle: subtitle,
      icon: Icons.timeline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: OpenHandSmoothLineChartPainter(
                  series: series,
                  gridColor: cs.outlineVariant.withValues(alpha: 0.46),
                  labelColor: cs.onSurfaceVariant,
                  emptyLabel: maxValue <= 0
                      ? openHandTextResolver(context)(
                          zh: '暂无趋势样本',
                          en: 'No trend samples',
                        )
                      : '',
                  valueSuffix: valueSuffix,
                  textDirection: Directionality.of(context),
                ),
              ),
            ),
          ),
          kOpenHandGap12,
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final item in series)
                _ProxyOpsLegend(label: item.label, color: item.color),
            ],
          ),
          kOpenHandGap12,
          for (var index = series.first.values.length - 1; index >= 0; index--)
            if (series.any(
              (item) => index < item.values.length && item.values[index] > 0,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Text(
                      '${index + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    for (final item in series) ...[
                      Text(
                        index < item.values.length
                            ? '${item.values[index].round()}$valueSuffix'
                            : '-',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: item.color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (item != series.last) const SizedBox(width: 18),
                    ],
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ProxyOpsTrafficFlow extends StatelessWidget {
  const _ProxyOpsTrafficFlow({
    required this.inbound,
    required this.title,
    required this.bytes,
    required this.requestCount,
    required this.endpoint,
  });

  final bool inbound;
  final String title;
  final int bytes;
  final int requestCount;
  final String endpoint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tone = inbound ? cs.secondary : cs.tertiary;
    final perRequest = requestCount <= 0 ? 0 : bytes / requestCount;
    final text = openHandTextResolver(context);
    return _ProxyOpsPanel(
      title: title,
      icon: inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tone.withValues(alpha: 0.26)),
            ),
            child: Row(
              children: [
                _ProxyOpsFlowNode(
                  label: inbound
                      ? text(zh: '客户端', en: 'Client')
                      : text(zh: '中转服务', en: 'Proxy'),
                  icon: inbound ? Icons.devices_rounded : Icons.cloud_rounded,
                  color: tone,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        inbound
                            ? Icons.arrow_forward_rounded
                            : Icons.arrow_back_rounded,
                        color: tone,
                        size: 30,
                      ),
                      kOpenHandGap4,
                      Text(
                        endpoint,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                _ProxyOpsFlowNode(
                  label: inbound
                      ? text(zh: '中转服务', en: 'Proxy')
                      : text(zh: '上游模型', en: 'Upstream'),
                  icon: inbound ? Icons.cloud_rounded : Icons.hub_rounded,
                  color: tone,
                ),
              ],
            ),
          ),
          kOpenHandGap14,
          Row(
            children: [
              Expanded(
                child: _ProxyOpsFlowStat(
                  label: text(zh: '累计字节', en: 'Total bytes'),
                  value: formatByteSize(bytes),
                  color: tone,
                ),
              ),
              kOpenHandHGap10,
              Expanded(
                child: _ProxyOpsFlowStat(
                  label: text(zh: '平均每请求', en: 'Average/request'),
                  value: formatByteSize(perRequest.round()),
                  color: tone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProxyOpsFlowNode extends StatelessWidget {
  const _ProxyOpsFlowNode({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.26)),
        ),
        child: Icon(icon, color: color),
      ),
      kOpenHandGap5,
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _ProxyOpsFlowStat extends StatelessWidget {
  const _ProxyOpsFlowStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
        kOpenHandGap4,
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _ProxyOpsRouteTopology extends StatelessWidget {
  const _ProxyOpsRouteTopology({
    required this.title,
    required this.routes,
    required this.data,
    required this.showBackends,
  });

  final String title;
  final List<AiModelProxyRoute> routes;
  final _ProxyOpsSnapshot data;
  final bool showBackends;

  @override
  Widget build(BuildContext context) {
    final text = openHandTextResolver(context);
    final cs = Theme.of(context).colorScheme;
    return _ProxyOpsPanel(
      title: title,
      icon: showBackends ? Icons.storage_rounded : Icons.hub_rounded,
      child: routes.isEmpty
          ? Text(
              text(zh: '暂无启用路由。', en: 'No enabled routes.'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            )
          : Column(
              children: [
                for (var index = 0; index < routes.length; index++) ...[
                  if (index > 0) const SizedBox(height: 10),
                  _ProxyOpsRouteTopologyRow(
                    route: routes[index],
                    data: data,
                    showBackends: showBackends,
                    accent: [cs.primary, cs.tertiary, cs.secondary][index % 3],
                  ),
                ],
              ],
            ),
    );
  }
}

class _ProxyOpsRouteTopologyRow extends StatelessWidget {
  const _ProxyOpsRouteTopologyRow({
    required this.route,
    required this.data,
    required this.showBackends,
    required this.accent,
  });

  final AiModelProxyRoute route;
  final _ProxyOpsSnapshot data;
  final bool showBackends;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final backends = route.backends
        .where((backend) => backend.enabled)
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(
            showBackends ? Icons.storage_rounded : Icons.hub_rounded,
            color: accent,
          ),
          kOpenHandHGap9,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.exposedModel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                kOpenHandGap4,
                if (showBackends)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final backend in backends)
                        Chip(
                          avatar: Icon(
                            Icons.cloud_rounded,
                            size: 14,
                            color: accent,
                          ),
                          label: Text(
                            '${data.providerLabelForId(backend.providerId) ?? backend.providerId} / ${backend.modelId}',
                          ),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                            color: accent.withValues(alpha: 0.24),
                          ),
                          backgroundColor: cs.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                        ),
                    ],
                  )
                else
                  Text(
                    '${backends.length} 个后备模型',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (!showBackends)
            Icon(
              Icons.arrow_forward_rounded,
              color: accent.withValues(alpha: 0.72),
            ),
        ],
      ),
    );
  }
}

class _ProxyOpsStatusDonut extends StatelessWidget {
  const _ProxyOpsStatusDonut({
    required this.title,
    required this.values,
    required this.colors,
  });

  final String title;
  final Map<String, int> values;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = values.entries
        .where((entry) => entry.value > 0)
        .toList(growable: false);
    final total = entries.fold<int>(0, (sum, item) => sum + item.value);
    return _ProxyOpsPanel(
      title: title,
      icon: Icons.donut_small_rounded,
      child: entries.isEmpty
          ? Text(
              openHandTextResolver(context)(
                zh: '暂无状态样本。',
                en: 'No status samples.',
              ),
            )
          : Row(
              children: [
                SizedBox(
                  width: 166,
                  height: 166,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: OpenHandDonutChartPainter(
                        values: entries
                            .map((entry) => entry.value)
                            .toList(growable: false),
                        colors: colors
                            .take(entries.length)
                            .toList(growable: false),
                        trackColor: cs.surfaceContainerHighest,
                      ),
                      child: Center(
                        child: Text(
                          '$total',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                ),
                kOpenHandHGap18,
                Expanded(
                  child: Column(
                    children: [
                      for (var index = 0; index < entries.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: colors[index % colors.length],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              kOpenHandHGap7,
                              Expanded(
                                child: Text(
                                  entries[index].key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              Text(
                                '${(entries[index].value / total * 100).toStringAsFixed(1)}%',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: colors[index % colors.length],
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ],
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

class _ProxyOpsClientLedger extends StatelessWidget {
  const _ProxyOpsClientLedger({required this.title, required this.records});

  final String title;
  final List<AiModelProxyRequestRecord> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = openHandTextResolver(context);
    final shown = records.reversed.take(40).toList(growable: false);
    return _ProxyOpsPanel(
      title: title,
      icon: Icons.devices_other_rounded,
      subtitle: text(
        zh: '完整客户端标识、协议与来源地址',
        en: 'Full client identity, protocol and source address',
      ),
      child: shown.isEmpty
          ? Text(text(zh: '暂无客户端样本。', en: 'No client samples.'))
          : Column(
              children: [
                for (var index = 0; index < shown.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 18,
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: cs.secondary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.devices_rounded,
                          size: 18,
                          color: cs.secondary,
                        ),
                      ),
                      kOpenHandHGap9,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shown[index].clientUserAgent.trim().isEmpty
                                  ? text(
                                      zh: '未提供 User-Agent',
                                      en: 'User-Agent unavailable',
                                    )
                                  : shown[index].clientUserAgent.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontFamily: 'monospace',
                              ),
                            ),
                            kOpenHandGap4,
                            Text(
                              [shown[index].apiStyle, shown[index].clientIp]
                                  .where((item) => item.trim().isNotEmpty)
                                  .join(' · '),
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
                      Text(
                        formatMonthDayHm(shown[index].startedAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
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

String _proxyOpsInsightSubtitle(
  BuildContext context,
  _ProxyOpsInsightKind kind,
) {
  final text = openHandTextResolver(context);
  return switch (kind) {
    _ProxyOpsInsightKind.connections => text(
      zh: '客户端、服务入口与实时连接拓扑',
      en: 'Client, endpoint and live connection topology',
    ),
    _ProxyOpsInsightKind.activeRequests => text(
      zh: '执行槽位、限流阈值与调度模式',
      en: 'Execution slots, limits and scheduling modes',
    ),
    _ProxyOpsInsightKind.requests => text(
      zh: '请求量、接口协议与时间线样本',
      en: 'Request volume, API protocols and timeline samples',
    ),
    _ProxyOpsInsightKind.ingress => text(
      zh: '入口来源、协议与地址画像',
      en: 'Ingress sources, protocols and address profile',
    ),
    _ProxyOpsInsightKind.ingressErrors => text(
      zh: '只查看入口错误，不混入模型失败明细',
      en: 'Ingress errors only, without model failure details',
    ),
    _ProxyOpsInsightKind.succeeded => text(
      zh: '成功质量与成功提供商样本',
      en: 'Success quality and successful provider samples',
    ),
    _ProxyOpsInsightKind.failures => text(
      zh: '失败模型、错误原因与失败样本',
      en: 'Failed models, reasons and failure samples',
    ),
    _ProxyOpsInsightKind.averageLatency => text(
      zh: '按模型查看平均耗时贡献',
      en: 'Average latency contribution by model',
    ),
    _ProxyOpsInsightKind.p95Latency => text(
      zh: '尾部请求与 P95 阈值对照',
      en: 'Tail requests compared with the P95 threshold',
    ),
    _ProxyOpsInsightKind.latencyTrend => text(
      zh: '逐采样桶查看平均与尾延迟变化',
      en: 'Average and tail latency by sample bucket',
    ),
    _ProxyOpsInsightKind.tokens => text(
      zh: '模型级 Token 消耗排行',
      en: 'Model-level token usage ranking',
    ),
    _ProxyOpsInsightKind.inbound => text(
      zh: '客户端到中转服务的请求体流向',
      en: 'Request-body flow from clients to the proxy',
    ),
    _ProxyOpsInsightKind.outbound => text(
      zh: '中转服务到上游模型的响应体流向',
      en: 'Response-body flow from the proxy to upstream models',
    ),
    _ProxyOpsInsightKind.exposedModels => text(
      zh: '对外模型与后备链路拓扑',
      en: 'Exposed models and fallback topology',
    ),
    _ProxyOpsInsightKind.backends => text(
      zh: '后备模型对应的提供商与路由关系',
      en: 'Backend providers and route relationships',
    ),
    _ProxyOpsInsightKind.requestTrend => text(
      zh: '成功与失败的逐桶请求变化',
      en: 'Bucketed request changes for success and failure',
    ),
    _ProxyOpsInsightKind.statusMix => text(
      zh: '成功与失败的整体占比',
      en: 'Overall share of success and failure',
    ),
    _ProxyOpsInsightKind.providerMix => text(
      zh: '提供商请求量与成功率排行',
      en: 'Provider request volume and success ranking',
    ),
    _ProxyOpsInsightKind.modelMix => text(
      zh: '模型请求量与成功率排行',
      en: 'Model request volume and success ranking',
    ),
    _ProxyOpsInsightKind.clientMix => text(
      zh: '客户端完整 User-Agent 与来源地址',
      en: 'Full client User-Agent and source address',
    ),
    _ProxyOpsInsightKind.recentRequest => text(
      zh: '请求样本时间线',
      en: 'Request sample timeline',
    ),
  };
}
