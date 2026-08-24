part of 'ai_exposure_monitoring_dialogs.dart';

void _showMetricInsight(
  BuildContext context, {
  required String title,
  required _Metric selected,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: selected.icon,
      title: selected.label,
      subtitle: '$title · 指标详情',
      color: selected.color,
      showDataScope: selected.id == _MetricInsightId.overviewTaskTotal,
      adaptiveHeight: selected.id == _MetricInsightId.overviewEnabledRules,
      child: _MetricInsightBody(selected: selected),
    ),
  );
}

void _showTrendInsight(
  BuildContext context, {
  required _TrendInsightId id,
  required IconData icon,
  required String title,
  required String subtitle,
  required ValueListenable<List<OpenHandChartSeries>> series,
  required ValueListenable<List<String>> sampleLabels,
  required String suffix,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: icon,
      title: title,
      subtitle: subtitle,
      child: AnimatedBuilder(
        animation: Listenable.merge([series, sampleLabels]),
        builder: (context, _) => _TrendInsightBody(
          id: id,
          title: title,
          series: series.value,
          sampleLabels: sampleLabels.value,
          suffix: suffix,
        ),
      ),
    ),
  );
}

void _showDistributionInsight(
  BuildContext context, {
  required _DistributionInsightId id,
  required IconData icon,
  required String title,
  required ValueListenable<List<_DistributionItem>> items,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: icon,
      title: title,
      subtitle: '实时业务分布与诊断',
      child: ValueListenableBuilder<List<_DistributionItem>>(
        valueListenable: items,
        builder: (context, values, _) =>
            _DistributionInsightBody(id: id, title: title, items: values),
      ),
    ),
  );
}

class _OperationsInsightDialog extends StatelessWidget {
  const _OperationsInsightDialog({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.color,
    this.entity = false,
    this.showDataScope = false,
    this.adaptiveHeight = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Color? color;
  final bool entity;
  final bool showDataScope;
  final bool adaptiveHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tone = color ?? colors.primary;
    return OpenHandEscapeDismissScope(
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: entity
            ? kOpenHandDialogWidthStandard
            : kOpenHandDialogWidthExtraWide,
        maxHeight: kOpenHandDialogHeightTall,
        maxWidthFraction: 0.92,
        maxHeightFraction: 0.9,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandRadius16)),
        expandToMax: !adaptiveHeight,
        child: ServiceDialogInteractionTheme(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: adaptiveHeight
                  ? MainAxisSize.min
                  : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(kOpenHandRadius8),
                        border: Border.all(color: tone.withValues(alpha: 0.28)),
                      ),
                      child: Icon(icon, color: tone),
                    ),
                    kOpenHandHGap12,
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
                          kOpenHandGap2,
                          OpenHandLiveValue(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ServiceDialogHeaderIconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                kOpenHandGap14,
                Divider(height: 1, color: colors.outlineVariant),
                kOpenHandGap14,
                if (showDataScope) ...[
                  const _OperationsDataScopeBar(),
                  kOpenHandGap12,
                ],
                Flexible(
                  fit: adaptiveHeight ? FlexFit.loose : FlexFit.tight,
                  child: SingleChildScrollView(
                    physics: openHandDialogAwareScrollPhysics(context),
                    child: child,
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

class _MetricInsightBody extends StatelessWidget {
  const _MetricInsightBody({required this.selected});

  final _Metric selected;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    return _buildDistinctMetricInsight(
      context,
      id: selected.id!,
      controller: controller,
    );
  }
}

class _TrendInsightBody extends StatelessWidget {
  const _TrendInsightBody({
    required this.id,
    required this.title,
    required this.series,
    required this.sampleLabels,
    required this.suffix,
  });
  final _TrendInsightId id;
  final String title;
  final List<OpenHandChartSeries> series;
  final List<String> sampleLabels;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    return _buildTrendInsight(
      context,
      id: id,
      title: title,
      controller: controller,
      series: series,
      sampleLabels: sampleLabels,
      suffix: suffix,
    );
  }
}

class _DistributionInsightBody extends StatelessWidget {
  const _DistributionInsightBody({
    required this.id,
    required this.title,
    required this.items,
  });
  final _DistributionInsightId id;
  final String title;
  final List<_DistributionItem> items;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    return _buildDistributionInsight(
      context,
      id: id,
      title: title,
      controller: controller,
      items: items,
    );
  }
}

class _DistributionDetailRow extends StatelessWidget {
  const _DistributionDetailRow({
    required this.item,
    required this.total,
    required this.selected,
    this.onTap,
  });
  final _DistributionItem item;
  final int total;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final share = total <= 0 ? 0.0 : item.value / total;
    final bar = ClipRRect(
      borderRadius: kOpenHandPillBorderRadius,
      child: ServiceAnimatedProgressBar(
        value: share,
        minHeight: 9,
        color: item.color,
        backgroundColor: item.color.withValues(alpha: 0.1),
      ),
    );
    final label = Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
        ),
        kOpenHandHGap9,
        Expanded(
          child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        kOpenHandHGap10,
        Text(
          '${item.value} · ${(share * 100).toStringAsFixed(1)}%',
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    );
    return ServiceInteractiveSurface(
      padding: const EdgeInsets.symmetric(vertical: 7),
      tooltip: onTap == null ? null : '筛选${item.label}记录',
      onTap: onTap,
      color: selected ? item.color.withValues(alpha: 0.08) : null,
      borderColor: selected ? item.color.withValues(alpha: 0.35) : null,
      reserveDetailsIconSpace: true,
      detailsIconColor: item.color,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 440) {
            return Column(children: [label, kOpenHandGap8, bar]);
          }
          return Row(
            children: [
              SizedBox(width: 238, child: label),
              kOpenHandHGap12,
              Expanded(child: bar),
            ],
          );
        },
      ),
    );
  }
}

String _formatChartValue(double value) => value == value.roundToDouble()
    ? '${value.round()}'
    : value.toStringAsFixed(1);

sealed class _InsightTarget {
  const _InsightTarget();
}

class _TaskInsightTarget extends _InsightTarget {
  _TaskInsightTarget(AiExposureHistoryEntry task)
    : taskId = task.id,
      legacySnapshot = task.id.isEmpty ? task : null;

  final String taskId;
  final AiExposureHistoryEntry? legacySnapshot;
}

class _TaskCollectionInsightTarget extends _InsightTarget {
  const _TaskCollectionInsightTarget({
    required this.status,
    required this.title,
  });

  final String status;
  final String title;
}

class _SourceInsightTarget extends _InsightTarget {
  const _SourceInsightTarget(this.source);

  final AiExposureSource source;
}

class _ProxyEndpointInsightTarget extends _InsightTarget {
  _ProxyEndpointInsightTarget(AiExposureProxyEndpoint endpoint)
    : endpointId = endpoint.runtimeId;

  final String endpointId;
}

class _ResultInsightTarget extends _InsightTarget {
  _ResultInsightTarget(AiExposureResult result)
    : resultId = result.id,
      legacySnapshot = result.id.isEmpty ? result : null;

  final String resultId;
  final AiExposureResult? legacySnapshot;
}

class _LogInsightTarget extends _InsightTarget {
  const _LogInsightTarget(this.entry);

  final AiExposureLogEntry entry;
}

class _RuleInsightTarget extends _InsightTarget {
  _RuleInsightTarget(AiExposureScanRule rule)
    : ruleId = rule.id,
      legacySnapshot = rule.id.isEmpty ? rule : null;

  final String ruleId;
  final AiExposureScanRule? legacySnapshot;
}

class _ProxyRequestInsightTarget extends _InsightTarget {
  const _ProxyRequestInsightTarget({
    required this.address,
    required this.sample,
    this.endpoint,
  });

  final AiExposureProxyEndpoint? endpoint;
  final String address;
  final AiExposureProxyRequestSample sample;
}

class _ProxyProbeInsightTarget extends _InsightTarget {
  const _ProxyProbeInsightTarget({
    required this.endpoint,
    required this.sample,
  });

  final AiExposureProxyEndpoint endpoint;
  final AiExposureProxyProbeSample sample;
}

class _StageInsightTarget extends _InsightTarget {
  const _StageInsightTarget(this.stage, {this.taskId});

  final String stage;
  final String? taskId;
}

class _DependencyInsightTarget extends _InsightTarget {
  const _DependencyInsightTarget({
    required this.id,
    required this.name,
    required this.configured,
    required this.connected,
    required this.message,
  });

  final _DependencyInsightId id;
  final String name;
  final bool? configured;
  final bool? connected;
  final String message;
}

void _openInsightTarget(BuildContext context, _InsightTarget target) {
  switch (target) {
    case _TaskInsightTarget(:final taskId, :final legacySnapshot):
      _showTaskEntityInsightById(
        context,
        taskId: taskId,
        legacySnapshot: legacySnapshot,
      );
    case _TaskCollectionInsightTarget(:final status, :final title):
      _showTaskCollectionInsight(context, status: status, title: title);
    case _SourceInsightTarget(:final source):
      _showSourceEntityInsight(context, source);
    case _ProxyEndpointInsightTarget(:final endpointId):
      _showProxyEndpointEntityInsightById(context, endpointId);
    case _ResultInsightTarget(:final resultId, :final legacySnapshot):
      _showResultEntityInsightById(
        context,
        resultId: resultId,
        legacySnapshot: legacySnapshot,
      );
    case _LogInsightTarget(:final entry):
      _showLogEntityInsight(context, entry);
    case _RuleInsightTarget(:final ruleId, :final legacySnapshot):
      _showRuleEntityInsightById(
        context,
        ruleId: ruleId,
        legacySnapshot: legacySnapshot,
      );
    case _ProxyRequestInsightTarget(
      :final endpoint,
      :final address,
      :final sample,
    ):
      _showProxyRequestEntityInsight(
        context,
        endpoint: endpoint,
        address: address,
        sample: sample,
      );
    case _ProxyProbeInsightTarget(:final endpoint, :final sample):
      _showProxyProbeEntityInsight(context, endpoint: endpoint, sample: sample);
    case _StageInsightTarget(:final stage, :final taskId):
      _showStageEntityInsight(context, stage: stage, taskId: taskId);
    case _DependencyInsightTarget(
      :final id,
      :final name,
      :final configured,
      :final connected,
      :final message,
    ):
      _showDependencyEntityInsight(
        context,
        id: id,
        name: name,
        configured: configured,
        connected: connected,
        message: message,
      );
  }
}

class _InsightRecord {
  const _InsightRecord({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tags,
    required this.color,
    this.target,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> tags;
  final Color color;
  final _InsightTarget? target;
}

const double _kInsightListMaxHeight = 420;
const double _kInsightListScrollbarGutter = 10;

class _InsightListViewport extends StatefulWidget {
  const _InsightListViewport({required this.child});

  final Widget child;

  @override
  State<_InsightListViewport> createState() => _InsightListViewportState();
}

class _InsightListViewportState extends State<_InsightListViewport> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: _kInsightListMaxHeight),
    child: Padding(
      padding: const EdgeInsets.only(right: _kInsightListScrollbarGutter),
      child: OpenHandSafeScrollbar(
        controller: _controller,
        thumbVisibility: true,
        interactive: true,
        thickness: 5,
        radius: kOpenHandPillRadius,
        scrollbarOrientation: ScrollbarOrientation.right,
        child: SingleChildScrollView(
          controller: _controller,
          primary: false,
          physics: openHandDialogAwareScrollPhysics(context),
          child: widget.child,
        ),
      ),
    ),
  );
}

class _InsightRecordPanel extends StatelessWidget {
  const _InsightRecordPanel({
    required this.icon,
    required this.title,
    required this.records,
    required this.emptyLabel,
    this.maxEntries = 30,
  });

  final IconData icon;
  final String title;
  final List<_InsightRecord> records;
  final String emptyLabel;
  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Section(
      title: records.isEmpty ? title : '$title · ${records.length}',
      icon: icon,
      child: records.isEmpty
          ? _InsightEmpty(label: emptyLabel)
          : OpenHandClientPager<_InsightRecord>(
              items: records,
              initialPageSize: maxEntries.clamp(
                kOpenHandTableMinPageSize,
                kOpenHandTableMaxPageSize,
              ),
              builder: (context, shown) => _InsightListViewport(
                child: Column(
                  children: [
                    ...shown.indexed.map(
                      (entry) => Column(
                        children: [
                          if (entry.$1 > 0)
                            Divider(
                              height: 18,
                              color: colors.outlineVariant.withValues(alpha: 0.5),
                            ),
                          _InsightRecordRow(record: entry.$2),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _InsightRecordRow extends StatelessWidget {
  const _InsightRecordRow({required this.record});
  final _InsightRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ServiceInteractiveSurface(
      padding: const EdgeInsets.all(4),
      tooltip: record.target == null ? null : '查看记录详情',
      onTap: record.target == null
          ? null
          : () => _openInsightTarget(context, record.target!),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 48,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: record.color,
              borderRadius: kOpenHandPillBorderRadius,
            ),
          ),
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: record.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(kOpenHandRadius8),
            ),
            child: Icon(record.icon, size: 18, color: record.color),
          ),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (record.tags.isNotEmpty) ...[
                  kOpenHandGap5,
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: record.tags
                        .where((tag) => tag.trim().isNotEmpty)
                        .map((tag) => _InsightMiniTag(label: tag))
                        .toList(growable: false),
                  ),
                ],
                if (record.subtitle.trim().isNotEmpty) ...[
                  kOpenHandGap5,
                  Text(
                    record.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightMiniTag extends StatelessWidget {
  const _InsightMiniTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InsightEmpty extends StatelessWidget {
  const _InsightEmpty({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            color: colors.onSurfaceVariant.withValues(alpha: 0.65),
          ),
          kOpenHandGap8,
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _TrendSampleTable extends StatelessWidget {
  const _TrendSampleTable({
    required this.series,
    required this.sampleLabels,
    required this.suffix,
    this.targets = const <_InsightTarget?>[],
  });
  final List<OpenHandChartSeries> series;
  final List<String> sampleLabels;
  final String suffix;
  final List<_InsightTarget?> targets;

  @override
  Widget build(BuildContext context) {
    final maxSamples = series.fold<int>(
      0,
      (count, item) => item.values.length > count ? item.values.length : count,
    );
    if (maxSamples == 0) return const _InsightEmpty(label: '暂无趋势样本。');
    final newestFirst = <int>[
      for (var i = maxSamples - 1; i >= 0; i--) i,
    ];
    return OpenHandClientPager<int>(
      items: newestFirst,
      builder: (context, indexes) => Column(
      children: [
        ...indexes.map((index) {
          final target = index < targets.length ? targets[index] : null;
          return ServiceInteractiveSurface(
            padding: const EdgeInsets.symmetric(vertical: 6),
            tooltip: target == null ? null : '查看样本详情',
            onTap: target == null
                ? null
                : () => _openInsightTarget(context, target),
            child: Row(
              children: [
                SizedBox(
                  width: 116,
                  child: Text(
                    index < sampleLabels.length
                        ? sampleLabels[index]
                        : '样本 ${index + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                kOpenHandHGap8,
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.end,
                    children: series
                        .map(
                          (item) => _StatusPill(
                            icon: Icons.circle,
                            label:
                                '${item.label} ${index < item.values.length ? _formatChartValue(item.values[index]) : '--'}$suffix',
                            color: item.color,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
      ),
    );
  }
}

class _InsightTrendSection extends StatelessWidget {
  const _InsightTrendSection({
    required this.title,
    required this.icon,
    required this.series,
    required this.sampleLabels,
    this.sampleTimes = const <DateTime>[],
    required this.suffix,
    required this.emptyLabel,
    this.interpolation = OpenHandChartInterpolation.linear,
    this.targets = const <_InsightTarget?>[],
  });

  final String title;
  final IconData icon;
  final List<OpenHandChartSeries> series;
  final List<String> sampleLabels;
  final List<DateTime> sampleTimes;
  final String suffix;
  final String emptyLabel;
  final OpenHandChartInterpolation interpolation;
  final List<_InsightTarget?> targets;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildChart(context),
          kOpenHandGap10,
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: series
                .map((item) => _OpsLegend(label: item.label, color: item.color))
                .toList(growable: false),
          ),
          kOpenHandGap10,
          _TrendSampleTable(
            series: series,
            sampleLabels: sampleLabels,
            suffix: suffix,
            targets: targets,
          ),
        ],
      ),
    );
  }

  Widget _buildChart(BuildContext context) =>
      OpenHandZoomableOperationalTrendChart(
        series: series,
        xLabels: sampleLabels,
        sampleTimes: sampleTimes,
        valueSuffix: suffix,
        emptyLabel: emptyLabel,
        interpolation: interpolation,
        showLegend: false,
        externalLegendProvided: true,
        semanticLabel:
            '$title，${series.length} 个序列，${sampleLabels.length} 个样本，支持双指缩放',
        onSelectionChanged: (_) {},
        onSelectionActivated: (selection) {
          if (selection.pointIndex < 0 ||
              selection.pointIndex >= targets.length) {
            return;
          }
          final target = targets[selection.pointIndex];
          if (target != null) _openInsightTarget(context, target);
        },
      );
}

class _InsightDonutSection extends StatefulWidget {
  const _InsightDonutSection({
    required this.title,
    required this.icon,
    required this.items,
    this.detailBuilder,
  });

  final String title;
  final IconData icon;
  final List<_DistributionItem> items;
  final Widget Function(BuildContext context, _DistributionItem item)?
  detailBuilder;

  @override
  State<_InsightDonutSection> createState() => _InsightDonutSectionState();
}

class _InsightDonutSectionState extends State<_InsightDonutSection> {
  Object? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final items = widget.items;
    final total = items.fold<int>(0, (sum, item) => sum + item.value);
    final selected = _selectedKey == null
        ? null
        : items
              .where((item) => (item.key ?? item.label) == _selectedKey)
              .firstOrNull;
    final distribution = _Section(
      title: widget.title,
      icon: widget.icon,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final donut = SizedBox.square(
            dimension: 138,
            child: OpenHandOperationalDonutChart(
              segments: items
                  .map(
                    (item) => OpenHandChartSegment(
                      label: item.label,
                      value: item.value,
                      color: item.color,
                      valueLabel: '${item.value}',
                    ),
                  )
                  .toList(growable: false),
              trackColor: colors.surfaceContainerHighest,
              height: 138,
              showLegend: false,
              externalLegendProvided: true,
              centerLabel: selected == null ? '$total' : '${selected.value}',
              semanticLabel: '${widget.title}，共 $total 条',
              onSelectionChanged: (_) {},
              onSegmentTap: widget.detailBuilder == null
                  ? null
                  : (selection) => setState(
                      () => _selectedKey =
                          items[selection.index].key ??
                          items[selection.index].label,
                    ),
            ),
          );
          final rows = Column(
            children: items.indexed
                .map(
                  (entry) => _DistributionDetailRow(
                    item: entry.$2,
                    total: total,
                    selected: (entry.$2.key ?? entry.$2.label) == _selectedKey,
                    onTap: widget.detailBuilder == null || entry.$2.value <= 0
                        ? null
                        : () => setState(
                            () => _selectedKey = entry.$2.key ?? entry.$2.label,
                          ),
                  ),
                )
                .toList(growable: false),
          );
          if (constraints.maxWidth < 560) {
            return Column(children: [donut, kOpenHandGap12, rows]);
          }
          return Row(
            children: [
              donut,
               kOpenHandWidth22,
              Expanded(child: rows),
            ],
          );
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        distribution,
        if (selected != null && widget.detailBuilder != null) ...[
          kOpenHandGap12,
          widget.detailBuilder!(context, selected),
        ],
      ],
    );
  }
}

class _InsightKpi {
  const _InsightKpi({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
    required this.color,
    this.target,
  });

  final IconData icon;
  final String label;
  final String value;
  final String helper;
  final Color color;
  final _InsightTarget? target;
}

class _InsightKpiBand extends StatelessWidget {
  const _InsightKpiBand({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<_InsightKpi> items;

  @override
  Widget build(BuildContext context) => _Section(
    title: title,
    icon: icon,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final maxColumns = constraints.maxWidth >= 760
            ? 4
            : constraints.maxWidth >= 500
            ? 2
            : 1;
        if (items.isEmpty) return const SizedBox.shrink();
        const gap = 10.0;
        final rows = <Widget>[];
        final rowCount = (items.length / maxColumns).ceil();
        var start = 0;
        for (var row = 0; row < rowCount; row++) {
          final remainingRows = rowCount - row;
          final rowLength =
              (items.length - start + remainingRows - 1) ~/ remainingRows;
          final end = start + rowLength;
          if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = start; index < end; index++) ...[
                  if (index > start) const SizedBox(width: gap),
                  Expanded(
                    child: ServiceInteractiveSurface(
                      onTap: items[index].target == null
                          ? null
                          : () => _openInsightTarget(
                              context,
                              items[index].target!,
                            ),
                      tooltip: items[index].target == null
                          ? null
                          : '查看${items[index].label}详情',
                      padding: EdgeInsets.zero,
                      showDetailsIcon: items[index].target != null,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 108),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: items[index].color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(kOpenHandRadius8),
                          border: Border.all(
                            color: items[index].color.withValues(alpha: 0.26),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  items[index].icon,
                                  size: 18,
                                  color: items[index].color,
                                ),
                                kOpenHandHGap7,
                                Expanded(
                                  child: Text(
                                    items[index].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium,
                                  ),
                                ),
                              ],
                            ),
                            kOpenHandGap10,
                            Text(
                              items[index].value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            kOpenHandGap3,
                            Text(
                              items[index].helper,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
          start = end;
        }
        return Column(children: rows);
      },
    ),
  );
}

class _InsightRankItem {
  const _InsightRankItem({
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.color,
    this.helper = '',
    this.key,
    this.target,
  });

  final String label;
  final double value;
  final String valueLabel;
  final Color color;
  final String helper;
  final Object? key;
  final _InsightTarget? target;
}

class _InsightRankingSection extends StatefulWidget {
  const _InsightRankingSection({
    required this.title,
    required this.icon,
    required this.items,
    required this.emptyLabel,
    this.detailBuilder,
  });

  final String title;
  final IconData icon;
  final List<_InsightRankItem> items;
  final String emptyLabel;
  final Widget Function(BuildContext context, _InsightRankItem item)?
  detailBuilder;

  @override
  State<_InsightRankingSection> createState() => _InsightRankingSectionState();
}

class _InsightRankingSectionState extends State<_InsightRankingSection> {
  Object? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.items]
      ..sort((left, right) => right.value.compareTo(left.value));
    final selected = _selectedKey == null
        ? null
        : sorted
              .where((item) => (item.key ?? item.label) == _selectedKey)
              .firstOrNull;
    final maxValue = sorted.fold<double>(
      0,
      (current, item) => item.value > current ? item.value : current,
    );
    final ranking = _Section(
      title: widget.title,
      icon: widget.icon,
      child: sorted.isEmpty
          ? _InsightEmpty(label: widget.emptyLabel)
          : OpenHandClientPager<_InsightRankItem>(
              items: sorted,
              builder: (context, shown) => _InsightListViewport(
                child: Column(
                  children: shown.indexed
                      .map((entry) {
                      final item = entry.$2;
                      final actionable =
                          item.value > 0 &&
                          (item.target != null || widget.detailBuilder != null);
                      return Opacity(
                        opacity: item.value > 0 ? 1 : 0.52,
                        child: ServiceInteractiveSurface(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 7,
                          ),
                          reserveDetailsIconSpace: actionable,
                          detailsIconColor: item.color,
                          tooltip: !actionable
                              ? null
                              : item.target != null
                              ? '查看排行详情'
                              : widget.detailBuilder != null && item.value > 0
                              ? '筛选${item.label}记录'
                              : null,
                          onTap: !actionable
                              ? null
                              : item.target != null
                              ? () => _openInsightTarget(context, item.target!)
                              : () => setState(
                                  () => _selectedKey = item.key ?? item.label,
                                ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      '${entry.$1 + 1}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: item.color,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  kOpenHandHGap12,
                                  Text(
                                    item.value <= 0 ? '无记录' : item.valueLabel,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ],
                              ),
                              kOpenHandGap7,
                              ClipRRect(
                                borderRadius: kOpenHandPillBorderRadius,
                                child: ServiceAnimatedProgressBar(
                                  value: maxValue <= 0
                                      ? 0
                                      : item.value / maxValue,
                                  minHeight: 9,
                                  color: item.color,
                                  backgroundColor: item.color.withValues(
                                    alpha: 0.1,
                                  ),
                                ),
                              ),
                              if (item.helper.isNotEmpty) ...[
                                kOpenHandGap5,
                                Text(
                                  item.helper,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ranking,
        if (selected != null && widget.detailBuilder != null) ...[
          kOpenHandGap12,
          widget.detailBuilder!(context, selected),
        ],
      ],
    );
  }
}

class _InsightMatrixCell {
  const _InsightMatrixCell({required this.label, required this.color});

  final String label;
  final Color color;
}

class _InsightMatrixRow {
  const _InsightMatrixRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.cells,
    this.target,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final List<_InsightMatrixCell> cells;
  final _InsightTarget? target;
}

class _InsightMatrixSection extends StatelessWidget {
  const _InsightMatrixSection({
    required this.title,
    required this.icon,
    required this.rows,
    required this.emptyLabel,
  });

  final String title;
  final IconData icon;
  final List<_InsightMatrixRow> rows;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Section(
      title: rows.isEmpty ? title : '$title · ${rows.length}',
      icon: icon,
      child: rows.isEmpty
          ? _InsightEmpty(label: emptyLabel)
          : OpenHandClientPager<_InsightMatrixRow>(
              items: rows,
              builder: (context, shown) => _InsightListViewport(
              child: Column(
                children: [
                  ...shown.indexed.map(
                    (entry) => Column(
                      children: [
                        if (entry.$1 > 0)
                          Divider(
                            height: 18,
                            color: colors.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ServiceInteractiveSurface(
                          padding: const EdgeInsets.all(4),
                          tooltip: entry.$2.target == null ? null : '查看矩阵记录详情',
                          onTap: entry.$2.target == null
                              ? null
                              : () => _openInsightTarget(
                                  context,
                                  entry.$2.target!,
                                ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: entry.$2.color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(kOpenHandRadius8),
                                ),
                                child: Icon(
                                  entry.$2.icon,
                                  size: 19,
                                  color: entry.$2.color,
                                ),
                              ),
                              kOpenHandHGap11,
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.$2.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    if (entry.$2.subtitle.isNotEmpty) ...[
                                      kOpenHandGap3,
                                      Text(
                                        entry.$2.subtitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                    kOpenHandGap7,
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: entry.$2.cells
                                          .map(
                                            (cell) => _StatusPill(
                                              icon: Icons.circle,
                                              label: cell.label,
                                              color: cell.color,
                                            ),
                                          )
                                          .toList(growable: false),
                                    ),
                                  ],
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
            ),
            ),
    );
  }
}

class _InsightTimelineEntry {
  const _InsightTimelineEntry({
    required this.at,
    required this.title,
    required this.detail,
    required this.color,
    this.tag = '',
    this.target,
  });

  final DateTime at;
  final String title;
  final String detail;
  final Color color;
  final String tag;
  final _InsightTarget? target;
}

class _InsightTimelineSection extends StatelessWidget {
  const _InsightTimelineSection({
    required this.title,
    required this.icon,
    required this.entries,
    required this.emptyLabel,
  });

  final String title;
  final IconData icon;
  final List<_InsightTimelineEntry> entries;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Section(
      title: entries.isEmpty ? title : '$title · ${entries.length}',
      icon: icon,
      child: entries.isEmpty
          ? _InsightEmpty(label: emptyLabel)
          : OpenHandClientPager<_InsightTimelineEntry>(
              items: entries,
              builder: (context, shown) => _InsightListViewport(
              child: Column(
                children: [
                  ...shown.indexed.map((entry) {
                    final item = entry.$2;
                    return ServiceInteractiveSurface(
                      padding: const EdgeInsets.all(4),
                      margin: const EdgeInsets.only(bottom: 4),
                      tooltip: item.target == null ? null : '查看时间线详情',
                      onTap: item.target == null
                          ? null
                          : () => _openInsightTarget(context, item.target!),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 76,
                              child: Text(
                                _shortDateTime(item.at),
                                maxLines: 2,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ),
                            SizedBox(
                              width: 18,
                              child: Column(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: item.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  if (entry.$1 < shown.length - 1)
                                    Expanded(
                                      child: Container(
                                        width: 2,
                                        color: colors.outlineVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            kOpenHandHGap8,
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                        if (item.tag.isNotEmpty) ...[
                                          kOpenHandHGap8,
                                          _InsightMiniTag(label: item.tag),
                                        ],
                                      ],
                                    ),
                                    if (item.detail.isNotEmpty) ...[
                                      kOpenHandGap4,
                                      Text(
                                        item.detail,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            ),
    );
  }
}

class _InsightFunnelItem {
  const _InsightFunnelItem({
    required this.label,
    required this.value,
    required this.color,
    this.target,
  });

  final String label;
  final int value;
  final Color color;
  final _InsightTarget? target;
}

class _InsightFunnelSection extends StatelessWidget {
  const _InsightFunnelSection({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<_InsightFunnelItem> items;

  @override
  Widget build(BuildContext context) {
    final maxValue = items.fold<int>(
      0,
      (current, item) => item.value > current ? item.value : current,
    );
    return _Section(
      title: title,
      icon: icon,
      child: items.isEmpty
          ? const _InsightEmpty(label: '暂无漏斗样本。')
          : _InsightListViewport(
              child: Column(
                children: items.indexed
                    .map((entry) {
                      final item = entry.$2;
                      final width = serviceProgressRatio(
                        value: item.value,
                        maximum: maxValue,
                        minimumVisible: 0.04,
                      );
                      final previous = entry.$1 == 0
                          ? null
                          : items[entry.$1 - 1];
                      final conversion = previous == null || previous.value <= 0
                          ? null
                          : item.value * 100 / previous.value;
                      final content = Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelLarge,
                                  ),
                                ),
                                Text(
                                  conversion == null
                                      ? '${item.value}'
                                      : '${item.value} · ${conversion.toStringAsFixed(1)}%',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            kOpenHandGap7,
                            _AnimatedFunnelBar(
                              widthFactor: width,
                              color: item.color,
                            ),
                          ],
                        ),
                      );
                      if (item.target == null || item.value <= 0) {
                        return content;
                      }
                      return ServiceInteractiveSurface(
                        onTap: () => _openInsightTarget(context, item.target!),
                        tooltip: '查看${item.label}详情',
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        detailsIconColor: item.color,
                        child: content,
                      );
                    })
                    .toList(growable: false),
              ),
            ),
    );
  }
}

class _AnimatedFunnelBar extends StatelessWidget {
  const _AnimatedFunnelBar({required this.widthFactor, required this.color});

  final double widthFactor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: ServiceAnimatedValue(
        value: widthFactor.clamp(0.0, 1.0),
        builder: (context, animatedWidth) => Align(
          child: FractionallySizedBox(
            widthFactor: animatedWidth.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(kOpenHandRadius4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InsightCapacitySection extends StatelessWidget {
  const _InsightCapacitySection({
    required this.title,
    required this.icon,
    required this.configured,
    required this.maximum,
    required this.color,
  });

  final String title;
  final IconData icon;
  final int configured;
  final int maximum;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final safeMaximum = maximum.clamp(1, 256);
    final safeConfigured = configured.clamp(0, safeMaximum);
    return _Section(
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '$safeConfigured',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                ' / $safeMaximum 个可配置工作槽',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 4.0;
              final columns = constraints.maxWidth >= 720 ? 32 : 16;
              final size =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return ServiceAnimatedValue(
                value: safeConfigured.toDouble(),
                builder: (context, animatedConfigured) => Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: List<Widget>.generate(safeMaximum, (index) {
                    final activity = (animatedConfigured - index).clamp(
                      0.0,
                      1.0,
                    );
                    return Container(
                      width: size,
                      height: size.clamp(7, 16),
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          colors.surfaceContainerHighest,
                          color,
                          activity,
                        ),
                        borderRadius: BorderRadius.circular(kOpenHandRadius2),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
          kOpenHandGap10,
          Text(
            '该图展示任务内部工作并发配置，不推断服务未上报的实时槽位占用。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
