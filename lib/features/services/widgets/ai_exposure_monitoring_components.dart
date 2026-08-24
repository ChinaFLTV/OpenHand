part of 'ai_exposure_monitoring_dialogs.dart';

class _DependencyDataAccessPanel extends StatelessWidget {
  const _DependencyDataAccessPanel({required this.controller});

  final ServicesController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dependencies = controller.dependencyStatus;
    final postgresqlReady = dependencies?.postgresql.connected == true;
    final redisReady = dependencies?.redis.connected == true;
    final overview = controller.dependencyDataOverview;
    final postgresql = aiExposureJsonMap(overview['postgresql']);
    final postgresqlTelemetry = aiExposureJsonMap(postgresql['telemetry']);
    final redis = aiExposureJsonMap(overview['redis']);
    return _Section(
      title: '依赖数据服务',
      icon: Icons.dns_rounded,
      child: _OpsPanelGrid(
        children: [
          _DependencyServiceCard(
            title: 'PostgreSQL 数据与遥测',
            detail: postgresqlReady
                ? '${formatByteSize(_metricInt(postgresqlTelemetry['databaseSizeBytes']))} · ${_metricInt(postgresqlTelemetry['activeConnections'])} 个活跃连接'
                : _dependencyUnavailableMessage(
                    dependencies?.postgresql.message,
                  ),
            icon: Icons.storage_rounded,
            color: colors.primary,
            connected: postgresqlReady,
            onTap: postgresqlReady
                ? () => showAiExposureDependencyDataDialog(context)
                : null,
          ),
          _DependencyServiceCard(
            title: 'Redis 键值与遥测',
            detail: redisReady
                ? '${formatByteSize(_metricInt(redis['usedMemoryBytes']))} · ${_metricInt(redis['operationsPerSecond'])} ops/s · ${_metricInt(redis['keyCount'])} 个键'
                : _dependencyUnavailableMessage(dependencies?.redis.message),
            icon: Icons.hub_rounded,
            color: colors.tertiary,
            connected: redisReady,
            onTap: redisReady
                ? () => showAiExposureDependencyDataDialog(
                    context,
                    initialView: DependencyDataView.redis,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _DependencyServiceCard extends StatelessWidget {
  const _DependencyServiceCard({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.connected,
    this.onTap,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final bool connected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final statusColor = connected
          ? OpenHandStatusColors.success
          : colors.outline;
      final identity = Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: connected ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(kOpenHandRadius14),
              border: Border.all(color: color.withValues(alpha: 0.24)),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          kOpenHandHGap14,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                kOpenHandGap6,
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    kOpenHandHGap7,
                    Expanded(
                      child: Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
      final action = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusPill(
            icon: connected
                ? Icons.check_circle_outline_rounded
                : Icons.link_off_rounded,
            label: connected ? '已连接' : '未连接',
            color: statusColor,
          ),
          if (onTap != null) ...[
            kOpenHandHGap10,
            Icon(
              Icons.arrow_forward_rounded,
              size: 20,
              color: color.withValues(alpha: 0.82),
            ),
          ],
        ],
      );
      final compact = constraints.maxWidth < 560;
      return _TappableOpsCard(
        onTap: onTap,
        color: color,
        borderRadius: kOpenHandBorderRadius12,
        child: Container(
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(alpha: connected ? 0.1 : 0.045),
              colors.surfaceContainerHighest.withValues(alpha: 0.28),
            ),
            borderRadius: kOpenHandBorderRadius12,
            border: Border.all(color: color.withValues(alpha: 0.26)),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    kOpenHandGap12,
                    Align(alignment: Alignment.centerRight, child: action),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    kOpenHandHGap16,
                    action,
                  ],
                ),
        ),
      );
    },
  );
}

String _dependencyUnavailableMessage(String? message) {
  final normalized = message?.trim();
  return normalized == null || normalized.isEmpty ? '未启用' : normalized;
}

int _metricInt(Object? value) => optionalIntFromValue(value) ?? 0;

class _Metric {
  const _Metric(
    this.id,
    this.icon,
    this.label,
    this.value,
    this.detail, {
    this.color,
    this.onTap,
  });
  final _MetricInsightId? id;
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color? color;
  final VoidCallback? onTap;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.title,
    required this.metrics,
    this.desktopColumns = 4,
  });
  final String title;
  final List<_Metric> metrics;
  final int desktopColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1000
          ? desktopColumns.clamp(1, 6)
          : constraints.maxWidth >= 620
          ? 2
          : 1;
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: metrics
            .map(
              (metric) => SizedBox(
                width: width,
                child: _MetricTile(
                  metric: metric,
                  onTap:
                      metric.onTap ??
                      (metric.id == null
                          ? null
                          : () => _showMetricInsight(
                              context,
                              title: title,
                              selected: metric,
                            )),
                ),
              ),
            )
            .toList(growable: false),
      );
    },
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric, this.onTap});
  final _Metric metric;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = metric.color ?? cs.primary;
    return _TappableOpsCard(
      onTap: onTap,
      color: color,
      child: Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: kOpenHandBorderRadius8,
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: kOpenHandBorderRadius8,
              ),
              child: Icon(metric.icon, size: 20, color: color),
            ),
            kOpenHandHGap12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    metric.label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    metric.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    metric.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              kOpenHandHGap6,
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: color.withValues(alpha: 0.72),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.minHeight,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      constraints: minHeight == null
          ? null
          : BoxConstraints(minHeight: minHeight!),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          child,
        ],
      ),
    );
  }
}

class _OpsKeyValue extends StatelessWidget {
  const _OpsKeyValue({
    required this.label,
    required this.value,
    this.color,
    this.maxLines = 2,
    this.selectable = false,
    this.copyable = false,
  });

  final String label;
  final String value;
  final Color? color;
  final int maxLines;
  final bool selectable;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        kOpenHandHGap12,
        Expanded(
          flex: 6,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: selectable
                    ? SelectableText(
                        value,
                        maxLines: maxLines,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Text(
                        value,
                        maxLines: maxLines,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              if (copyable) ...[
                kOpenHandHGap4,
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '复制$label',
                  onPressed: () => copyOpenHandTextToClipboard(
                    context: context,
                    text: value,
                    logTag: 'service_operations',
                    logAction: '复制$label',
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 15),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: content,
    );
  }
}

class _OpsKeyValueGrid extends StatelessWidget {
  const _OpsKeyValueGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 560 ? 2 : 1;
      const gap = 18.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(growable: false),
      );
    },
  );
}

class _InsightFlowLane extends StatelessWidget {
  const _InsightFlowLane({required this.nodes});

  final List<({IconData icon, String label, String value, Color color})> nodes;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final horizontal = constraints.maxWidth >= 540;
      final parts = nodes.indexed
          .expand<Widget>((entry) {
            final node = entry.$2;
            return [
              if (entry.$1 > 0)
                Icon(
                  horizontal
                      ? Icons.arrow_forward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              if (horizontal)
                Expanded(child: _InsightFlowNode(node: node))
              else
                _InsightFlowNode(node: node),
            ];
          })
          .toList(growable: false);
      return horizontal
          ? Row(children: parts)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: parts,
            );
    },
  );
}

class _InsightFlowNode extends StatelessWidget {
  const _InsightFlowNode({required this.node});

  final ({IconData icon, String label, String value, Color color}) node;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(node.icon, size: 21, color: node.color),
        kOpenHandHGap8,
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node.value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text(
                node.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _OpsPanelGrid extends StatelessWidget {
  const _OpsPanelGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 820 ? 2 : 1;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(growable: false),
      );
    },
  );
}

class _TrendPanel extends StatefulWidget {
  const _TrendPanel({
    required this.id,
    required this.interpolation,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.sampleTimes,
    required this.sampleLabels,
    required this.series,
    required this.suffix,
  });

  final _TrendInsightId id;
  final OpenHandChartInterpolation interpolation;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<DateTime> sampleTimes;
  final List<String> sampleLabels;
  final List<OpenHandChartSeries> series;
  final String suffix;

  @override
  State<_TrendPanel> createState() => _TrendPanelState();
}

class _TrendPanelState extends State<_TrendPanel> {
  late final ValueNotifier<List<OpenHandChartSeries>> _liveSeries =
      ValueNotifier(widget.series);
  late final ValueNotifier<List<String>> _liveSampleLabels = ValueNotifier(
    widget.sampleLabels,
  );

  @override
  void didUpdateWidget(_TrendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ValueNotifiers are only consumed by the insight dialog callback, not by
    // build, so syncing immediately avoids a one-frame stale-data window without
    // any rebuild-loop risk.
    _liveSeries.value = widget.series;
    _liveSampleLabels.value = widget.sampleLabels;
  }

  @override
  void dispose() {
    _liveSeries.dispose();
    _liveSampleLabels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _TappableOpsCard(
      color: colors.primary,
      onTap: () => _showTrendInsight(
        context,
        id: widget.id,
        icon: widget.icon,
        title: widget.title,
        subtitle: widget.subtitle,
        series: _liveSeries,
        sampleLabels: _liveSampleLabels,
        suffix: widget.suffix,
      ),
      child: Container(
        height: 260,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.24),
          borderRadius: kOpenHandBorderRadius8,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _OpsSectionIcon(icon: widget.icon),
                kOpenHandHGap9,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 17,
                  color: colors.primary.withValues(alpha: 0.72),
                ),
              ],
            ),
            kOpenHandGap12,
            Expanded(
              child: OpenHandTrendZoomRegion(
                itemCount: widget.series.fold<int>(
                  widget.sampleLabels.length,
                  (count, item) => math.max(count, item.values.length),
                ),
                sampleTimes: widget.sampleTimes,
                sampleLabels: widget.sampleLabels,
                semanticLabel: '${widget.title}，支持双指缩放',
                builder: (context, viewport) {
                  final visibleSeries = viewport.sliceSeries(widget.series);
                  return RepaintBoundary(
                    child: ServiceAnimatedChart(
                      series: visibleSeries,
                      builder: (context, series) => CustomPaint(
                        painter: OpenHandSmoothLineChartPainter(
                          series: series,
                          gridColor: colors.outlineVariant.withValues(
                            alpha: 0.58,
                          ),
                          labelColor: colors.onSurfaceVariant,
                          emptyLabel: '暂无趋势数据',
                          valueSuffix: widget.suffix,
                          textDirection: Directionality.of(context),
                          interpolation: widget.interpolation,
                          xLabels: viewport.slice(widget.sampleLabels),
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  );
                },
              ),
            ),
            kOpenHandGap6,
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: widget.series
                  .map(
                    (item) => _OpsLegend(label: item.label, color: item.color),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _DistributionItem {
  const _DistributionItem(this.label, this.value, this.color, {this.key});
  final String label;
  final int value;
  final Color color;
  final Object? key;
}

enum _DistributionRecordType { task, result, rule, log }

class _DistributionPanel extends StatefulWidget {
  const _DistributionPanel({
    required this.id,
    required this.icon,
    required this.title,
    required this.centerValue,
    required this.items,
  });

  final _DistributionInsightId id;
  final IconData icon;
  final String title;
  final String centerValue;
  final List<_DistributionItem> items;

  @override
  State<_DistributionPanel> createState() => _DistributionPanelState();
}

class _DistributionPanelState extends State<_DistributionPanel> {
  late final ValueNotifier<List<_DistributionItem>> _liveItems = ValueNotifier(
    widget.items,
  );
  bool _syncScheduled = false;

  @override
  void didUpdateWidget(_DistributionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncScheduled = false;
      _liveItems.value = widget.items;
    });
  }

  @override
  void dispose() {
    _liveItems.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final visible = widget.items
        .where((item) => item.value > 0)
        .take(8)
        .toList(growable: false);
    final maxValue = visible.fold<int>(
      1,
      (max, item) => item.value > max ? item.value : max,
    );
    return _TappableOpsCard(
      color: colors.primary,
      onTap: () => _showDistributionInsight(
        context,
        id: widget.id,
        icon: widget.icon,
        title: widget.title,
        items: _liveItems,
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 260),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.24),
          borderRadius: kOpenHandBorderRadius8,
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _OpsSectionIcon(icon: widget.icon),
                kOpenHandHGap9,
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 17,
                  color: colors.primary.withValues(alpha: 0.72),
                ),
              ],
            ),
            kOpenHandGap16,
            if (visible.isEmpty)
              SizedBox(
                height: 174,
                child: Center(
                  child: Text(
                    '暂无分布数据',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final donut = SizedBox.square(
                    dimension: 112,
                    child: ServiceAnimatedDonutChart(
                      values: visible.map((item) => item.value).toList(),
                      colors: visible.map((item) => item.color).toList(),
                      trackColor: colors.surfaceContainerHighest,
                      child: Center(
                        child: Text(
                          widget.centerValue,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  );
                  final rows = Column(
                    children: visible
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: item.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                kOpenHandHGap7,
                                SizedBox(
                                  width: 74,
                                  child: Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium,
                                  ),
                                ),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: kOpenHandPillBorderRadius,
                                    child: ServiceAnimatedProgressBar(
                                      value: item.value / maxValue,
                                      minHeight: 7,
                                      color: item.color,
                                      backgroundColor: item.color.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                  ),
                                ),
                                kOpenHandHGap8,
                                SizedBox(
                                  width: 42,
                                  child: Text(
                                    '${item.value}',
                                    textAlign: TextAlign.end,
                                    style: theme.textTheme.labelLarge,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(growable: false),
                  );
                  if (constraints.maxWidth < 430) {
                    return Column(
                      children: [donut, kOpenHandGap12, rows],
                    );
                  }
                  return Row(
                    children: [
                      donut,
                      kOpenHandHGap18,
                      Expanded(child: rows),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _TappableOpsCard extends StatefulWidget {
  const _TappableOpsCard({
    required this.child,
    required this.color,
    this.onTap,
    this.borderRadius = kOpenHandBorderRadius8,
  });

  final Widget child;
  final Color color;
  final VoidCallback? onTap;
  final BorderRadiusGeometry borderRadius;

  @override
  State<_TappableOpsCard> createState() => _TappableOpsCardState();
}

class _TappableOpsCardState extends State<_TappableOpsCard> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    final duration = openHandMotionDuration(
      context,
      _kOperationsCardMotionDuration,
    );
    return Semantics(
      button: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
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
                          color: widget.color.withValues(
                            alpha: _pressed
                                ? 0.09
                                : _hovered
                                ? 0.045
                                : 0,
                          ),
                          borderRadius: widget.borderRadius,
                          border: Border.all(
                            color: _hovered || _pressed || _focused
                                ? widget.color.withValues(
                                    alpha: _focused ? 0.68 : 0.38,
                                  )
                                : Colors.transparent,
                            width: _focused ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentActivityPanel extends StatelessWidget {
  const _RecentActivityPanel({required this.entries});
  final List<AiExposureLogEntry> entries;

  @override
  Widget build(BuildContext context) => _Section(
    title: '最近运行事件',
    icon: Icons.receipt_long_outlined,
    child: entries.isEmpty
        ? const Text('暂无运行事件。')
        : Column(
            children: entries
                .map((entry) {
                  final color = switch (entry.level) {
                    'error' => OpenHandStatusColors.error,
                    'warning' => OpenHandStatusColors.warning,
                    _ => OpenHandStatusColors.info,
                  };
                  return ServiceInteractiveSurface(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    tooltip: '查看运行事件详情',
                    onTap: () => _showLogEntityInsight(context, entry),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 34,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: kOpenHandPillBorderRadius,
                          ),
                        ),
                        kOpenHandHGap10,
                        Expanded(
                          child: Text(
                            entry.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        kOpenHandHGap12,
                        Text(
                          _reportedShortDateTime(entry.at, entry.atReported),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  );
                })
                .toList(growable: false),
          ),
  );
}

class _OpsSectionIcon extends StatelessWidget {
  const _OpsSectionIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.11),
        borderRadius: kOpenHandBorderRadius8,
        border: Border.all(color: colors.primary.withValues(alpha: 0.24)),
      ),
      child: Icon(icon, size: 19, color: colors.primary),
    );
  }
}

class _OpsLegend extends StatelessWidget {
  const _OpsLegend({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      kOpenHandHGap5,
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

Color _sourceColor(AiExposureSource source, ColorScheme colors) =>
    switch (source) {
      AiExposureSource.manual => colors.primary,
      AiExposureSource.github => _kAiExposureSourceGithub,
      AiExposureSource.githubArtifact => _kAiExposureColorSlate500,
      AiExposureSource.gitee => OpenHandStatusColors.error,
      AiExposureSource.gitcode => _kAiExposureSourceGitcode,
      AiExposureSource.fofa => _kAiExposureColorCyan,
      AiExposureSource.shodan => OpenHandStatusColors.warning,
      AiExposureSource.nodeseek => _kAiExposureSourceNodeseek,
      AiExposureSource.linuxDo => _kAiExposureSourceLinuxDo,
      AiExposureSource.v2ex => _kAiExposureColorSlate500,
    };

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.11),
      borderRadius: kOpenHandPillBorderRadius,
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        kOpenHandHGap6,
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.completed,
    required this.active,
    this.taskId,
    this.timing,
  });
  final String stage;
  final bool completed;
  final bool active;
  final String? taskId;
  final AiExposureStageTiming? timing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = completed || active ? cs.primary : cs.outline;
    final t = timing;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _openInsightTarget(
        context,
        _StageInsightTarget(stage, taskId: taskId),
      ),
      leading: Icon(
        completed
            ? Icons.check_circle_rounded
            : active
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: color,
      ),
      title: Text(_stageName(stage)),
      subtitle: t == null
          ? null
          : Text(
              [
                if (t.startedAt != null)
                  '开始 ${_shortDateTime(t.startedAt!)}',
                if (t.finishedAt != null)
                  '结束 ${_shortDateTime(t.finishedAt!)}',
                if (t.durationMs != null) '${t.durationMs} ms',
                if (t.inputCount != null) '输入 ${t.inputCount}',
                if (t.outputCount != null) '输出 ${t.outputCount}',
                if (t.message?.trim().isNotEmpty == true)
                  t.message!.trim(),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: active
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
    );
  }
}

class _DependencyLine extends StatelessWidget {
  const _DependencyLine({
    required this.id,
    required this.name,
    required this.ready,
    required this.detail,
    this.configured,
  });
  final _DependencyInsightId id;
  final String name;
  final bool ready;
  final String detail;
  final bool? configured;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    onTap: () => _showDependencyEntityInsight(
      context,
      id: id,
      name: name,
      configured: configured,
      connected: ready,
      message: detail,
    ),
    leading: Icon(
      ready ? Icons.check_circle_outline_rounded : Icons.circle_outlined,
      color: ready ? OpenHandStatusColors.success : Theme.of(context).colorScheme.outline,
    ),
    title: Text(name),
    subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(ready ? '正常' : '未启用'),
        kOpenHandHGap4,
        const Icon(Icons.chevron_right_rounded, size: 19),
      ],
    ),
  );
}

int _latencyPercentile(List<int> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * percentile.clamp(0, 1)).round();
  return sorted[index];
}

String _proxyStrategyName(AiExposureProxyStrategy strategy) =>
    switch (strategy) {
      AiExposureProxyStrategy.fixed => '固定节点',
      AiExposureProxyStrategy.roundRobin => '轮询调度',
      AiExposureProxyStrategy.random => '随机调度',
      AiExposureProxyStrategy.stickyHost => '目标粘滞',
    };

Color _credentialStateColor(String state, ColorScheme colors) =>
    switch (state) {
      'valid' => OpenHandStatusColors.success,
      'candidate' => OpenHandStatusColors.info,
      'rate_limited' => OpenHandStatusColors.warning,
      'invalid' || 'unauthorized' => OpenHandStatusColors.error,
      'unreachable' => colors.tertiary,
      'duplicate' => colors.secondary,
      _ => colors.outline,
    };

String _duration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final hours = seconds ~/ 3600;
  final minutes = seconds % 3600 ~/ 60;
  return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
}

String _shortDateTime(DateTime value) => formatMonthDayHm(value);

String _reportedShortDateTime(
  DateTime value,
  bool reported, {
  String unavailable = '时间未上报',
}) => reported ? _shortDateTime(value) : unavailable;

String _reportedIsoDateTime(
  DateTime value,
  bool reported, {
  String unavailable = '时间未上报',
}) => reported ? value.toLocal().toIso8601String() : unavailable;

String _stageName(String stage) => switch (stage) {
  'queued' => '排队',
  'discovering' => '资产发现',
  'normalizing' => '目标规范化',
  'fingerprinting' => '产品指纹',
  'extracting' => '凭证提取',
  'validating' => '授权验证',
  'persisting' => '关联归档',
  'completed' => '已完成',
  'cancelled' => '已取消',
  'failed' => '失败',
  _ => stage,
};

IconData _stageIcon(String stage) => switch (stage) {
  'completed' => Icons.check_circle_outline_rounded,
  'failed' => Icons.error_outline_rounded,
  'cancelled' => Icons.cancel_outlined,
  _ => Icons.pending_outlined,
};
