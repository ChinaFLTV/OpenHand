part of 'ai_exposure_monitoring_dialogs.dart';

const double _kTaskLedgerFilterHeight = 56;
const double _kTaskLedgerToolbarGap = 8;
const InputDecoration _kTaskLedgerFilterDecoration = InputDecoration(
  isDense: true,
  border: OutlineInputBorder(),
  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  constraints: BoxConstraints.tightFor(height: _kTaskLedgerFilterHeight),
);
const double _kTaskLedgerDesktopRowHorizontalPadding = 6;
const double _kTaskLedgerPipelineMinHeight = 520;
const double _kTaskLedgerStatusWidth = 84;
const double _kTaskLedgerCreatedWidth = 150;
const double _kTaskLedgerStartedWidth = 150;
const double _kTaskLedgerFinishedWidth = 150;
const double _kTaskLedgerDurationWidth = 84;
const double _kTaskLedgerNameWidth = 210;
const double _kTaskLedgerIdWidth = 190;
const double _kTaskLedgerModeWidth = 68;
const double _kTaskLedgerSourceWidth = 130;
const double _kTaskLedgerProgressWidth = 148;
const double _kTaskLedgerCandidatesWidth = 72;
const double _kTaskLedgerValidWidth = 64;
const double _kTaskLedgerHighValueWidth = 72;
const double _kTaskLedgerUpdatedWidth = 150;
const double _kTaskLedgerFailureStageWidth = 130;
const double _kTaskLedgerRetryWidth = 64;
const double _kTaskLedgerConcurrencyWidth = 68;
const double _kTaskLedgerScopeWidth = 170;
const double _kTaskLedgerErrorWidth = 230;
const double _kTaskLedgerDetailsWidth = 56;
// 列宽合计为内容宽度，表头和数据行各保留左右 6px 内边距。
const double _kTaskLedgerDesktopTableContentWidth =
    _kTaskLedgerStatusWidth +
    _kTaskLedgerCreatedWidth +
    _kTaskLedgerStartedWidth +
    _kTaskLedgerFinishedWidth +
    _kTaskLedgerDurationWidth +
    _kTaskLedgerNameWidth +
    _kTaskLedgerIdWidth +
    _kTaskLedgerModeWidth +
    _kTaskLedgerSourceWidth +
    _kTaskLedgerProgressWidth +
    _kTaskLedgerCandidatesWidth +
    _kTaskLedgerValidWidth +
    _kTaskLedgerHighValueWidth +
    _kTaskLedgerUpdatedWidth +
    _kTaskLedgerFailureStageWidth +
    _kTaskLedgerRetryWidth +
    _kTaskLedgerConcurrencyWidth +
    _kTaskLedgerScopeWidth +
    _kTaskLedgerErrorWidth +
    _kTaskLedgerDetailsWidth;
const double _kTaskLedgerDesktopTableWidth =
    _kTaskLedgerDesktopTableContentWidth +
    _kTaskLedgerDesktopRowHorizontalPadding * 2;
const Duration _kTaskTrendDefaultRange = Duration(hours: 6);
const Duration _kTaskTrendDefaultInterval = Duration(minutes: 5);
const int _kTaskTrendMinRangeMs = 30 * 60 * 1000;
const int _kTaskTrendMaxRangeMs = 30 * 24 * 60 * 60 * 1000;

enum AiExposureTaskLedgerSort {
  createdAt,
  finishedAt,
  duration,
  processed,
  valid,
  highValue,
}

enum _TaskLedgerTimeRange { all, last24Hours, last7Days, last30Days, custom }

bool _isTimeoutTask(AiExposureHistoryEntry task) {
  final stage = task.stage.toLowerCase();
  if (stage == 'timeout' || stage == 'timed_out') return true;
  if (stage != 'failed') return false;
  final detail = [
    task.errorMessage,
    task.failureStage,
    task.progress.failureStage,
    task.progress.message,
  ].whereType<String>().join(' ').toLowerCase();
  return detail.contains('timeout') ||
      detail.contains('timed out') ||
      detail.contains('deadline exceeded') ||
      detail.contains('超时');
}

String _taskStatusId(AiExposureHistoryEntry task) {
  if (_isTimeoutTask(task)) return 'timeout';
  return switch (task.stage) {
    'completed' => 'completed',
    'failed' => 'failed',
    'cancelled' => 'cancelled',
    _ => 'running',
  };
}

List<AiExposureHistoryEntry> filterAndSortAiExposureTasks({
  required List<AiExposureHistoryEntry> source,
  String query = '',
  String status = 'all',
  String mode = 'all',
  Set<AiExposureSource> sources = const <AiExposureSource>{},
  DateTime? createdFrom,
  DateTime? createdUntil,
  AiExposureTaskLedgerSort sort = AiExposureTaskLedgerSort.createdAt,
  bool descending = true,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final now = DateTime.now();
  final tasks = source
      .where((task) {
        final matchesQuery =
            normalizedQuery.isEmpty ||
            task.name.toLowerCase().contains(normalizedQuery) ||
            task.id.toLowerCase().contains(normalizedQuery) ||
            (task.errorMessage ?? '').toLowerCase().contains(normalizedQuery);
        if (!matchesQuery) return false;
        final matchesStatus = switch (status) {
          'running' => _taskStatusId(task) == 'running',
          'completed' => _taskStatusId(task) == 'completed',
          'failed' => _taskStatusId(task) == 'failed',
          'timeout' => _taskStatusId(task) == 'timeout',
          'cancelled' => _taskStatusId(task) == 'cancelled',
          'resumable' => task.isResumable,
          _ => true,
        };
        if (!matchesStatus) return false;
        final matchesMode = switch (mode) {
          'full' => task.mode == AiExposureScanMode.full,
          'incremental' => task.mode == AiExposureScanMode.incremental,
          _ => true,
        };
        if (!matchesMode) return false;
        if (sources.isNotEmpty &&
            !task.sources.any((source) => sources.contains(source))) {
          return false;
        }
        final createdAt = task.reportedCreatedAt;
        if (createdFrom != null &&
            (createdAt == null || createdAt.isBefore(createdFrom))) {
          return false;
        }
        return createdUntil == null ||
            (createdAt != null && !createdAt.isAfter(createdUntil));
      })
      .toList(growable: false);
  tasks.sort((left, right) {
    final compared = switch (sort) {
      AiExposureTaskLedgerSort.createdAt => _taskLedgerTimeValue(
        left.reportedCreatedAt,
      ).compareTo(_taskLedgerTimeValue(right.reportedCreatedAt)),
      AiExposureTaskLedgerSort.finishedAt => _taskLedgerTimeValue(
        left.effectiveFinishedAt,
      ).compareTo(_taskLedgerTimeValue(right.effectiveFinishedAt)),
      AiExposureTaskLedgerSort.duration => _taskLedgerDuration(
        left,
        now,
      ).compareTo(_taskLedgerDuration(right, now)),
      AiExposureTaskLedgerSort.processed => left.progress.processed.compareTo(
        right.progress.processed,
      ),
      AiExposureTaskLedgerSort.valid => left.progress.valid.compareTo(
        right.progress.valid,
      ),
      AiExposureTaskLedgerSort.highValue => left.progress.highValue.compareTo(
        right.progress.highValue,
      ),
    };
    return descending ? -compared : compared;
  });
  return tasks;
}

class _OperationsDataScopeBar extends StatelessWidget {
  const _OperationsDataScopeBar();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final candidates = <DateTime>[
      if (controller.progress?.reportedUpdatedAt case final updatedAt?)
        updatedAt,
      ...controller.history
          .map((entry) => entry.progress.reportedUpdatedAt)
          .whereType<DateTime>(),
      ...controller.results
          .where((entry) => entry.createdAtReported)
          .map((entry) => entry.createdAt),
      ...controller.logs
          .where((entry) => entry.atReported)
          .map((entry) => entry.at),
    ]..sort();
    final updatedAt = candidates.lastOrNull;
    final colors = Theme.of(context).colorScheme;
    final running = controller.isRunning;
    final statusColor = running
        ? OpenHandStatusColors.success
        : colors.onSurfaceVariant;
    return _InsightContextBar(
      icon: running ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
      label: '数据口径',
      value: running ? '当前服务快照' : '最近离线快照',
      helper: running ? '运行中 · 实时同步' : '服务离线 · 保留最近状态',
      color: statusColor,
      items: [
        _InsightContextDatum(
          icon: Icons.task_alt_rounded,
          label: '任务',
          value: '${controller.history.length}',
        ),
        _InsightContextDatum(
          icon: Icons.inventory_2_outlined,
          label: '结果',
          value: '${controller.results.length}',
        ),
        _InsightContextDatum(
          icon: Icons.receipt_long_outlined,
          label: '日志',
          value: '${controller.logs.length}',
        ),
        _InsightContextDatum(
          icon: Icons.schedule_rounded,
          label: '最近更新',
          value: updatedAt == null ? '暂无运行数据' : _taskLedgerDateTime(updatedAt),
          flex: 2,
        ),
      ],
    );
  }
}

class _InsightContextDatum {
  const _InsightContextDatum({
    required this.icon,
    required this.label,
    required this.value,
    this.flex = 1,
  });

  final IconData icon;
  final String label;
  final String value;
  final int flex;
}

class _InsightContextBar extends StatelessWidget {
  const _InsightContextBar({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
    required this.color,
    required this.items,
  });

  final IconData icon;
  final String label;
  final String value;
  final String helper;
  final Color color;
  final List<_InsightContextDatum> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final identity = Row(
      children: [
        AnimatedContainer(
          duration: motion.entranceDuration,
          curve: motion.curve.curve,
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(kOpenHandRadius8),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        kOpenHandHGap10,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
               kOpenHandGap1,
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
               kOpenHandGap1,
              Text(
                helper,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return AnimatedContainer(
      duration: motion.entranceDuration,
      curve: motion.curve.curve,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 860) {
            final columns = constraints.maxWidth < 460 ? 1 : 2;
            const spacing = 12.0;
            final itemWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                kOpenHandGap12,
                Divider(height: 1, color: colors.outlineVariant),
                kOpenHandGap12,
                Wrap(
                  spacing: spacing,
                  runSpacing: 12,
                  children: items
                      .map(
                        (item) => SizedBox(
                          width: itemWidth,
                          child: _InsightContextMetric(item: item),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 226, child: identity),
              kOpenHandHGap16,
              SizedBox(
                height: 48,
                child: VerticalDivider(color: colors.outlineVariant),
              ),
              kOpenHandHGap16,
              for (final entry in items.indexed) ...[
                if (entry.$1 > 0) kOpenHandHGap14,
                Expanded(
                  flex: entry.$2.flex,
                  child: _InsightContextMetric(item: entry.$2),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InsightContextMetric extends StatelessWidget {
  const _InsightContextMetric({required this.item});

  final _InsightContextDatum item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(item.icon, size: 17, color: colors.onSurfaceVariant),
        ),
        kOpenHandHGap7,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              kOpenHandGap2,
              AnimatedSwitcher(
                duration: motion.entranceDuration,
                switchInCurve: motion.curve.curve,
                switchOutCurve: motion.curve.curve,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  item.value,
                  key: ValueKey<(String, String)>((item.label, item.value)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void _showTaskCollectionInsight(
  BuildContext context, {
  required String status,
  required String title,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (_) => _OperationsInsightDialog(
      icon: Icons.table_rows_outlined,
      title: title,
      subtitle: '按状态过滤的真实任务集合',
      child: AiExposureTaskLedger(initialStatus: status),
    ),
  );
}

class _TaskTelemetryInsight extends StatefulWidget {
  const _TaskTelemetryInsight();

  @override
  State<_TaskTelemetryInsight> createState() => _TaskTelemetryInsightState();
}

class _TaskTelemetryInsightState extends State<_TaskTelemetryInsight> {
  Duration _range = _kTaskTrendDefaultRange;
  Duration _interval = _kTaskTrendDefaultInterval;
  Duration _scaleStartRange = _kTaskTrendDefaultRange;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServicesController>();
    final history = controller.history;
    final colors = Theme.of(context).colorScheme;
    final counts = <String, int>{
      'completed': 0,
      'running': 0,
      'failed': 0,
      'timeout': 0,
      'cancelled': 0,
    };
    for (final task in history) {
      counts.update(_taskStatusId(task), (value) => value + 1, ifAbsent: () => 1);
    }
    final trend = _taskTrendBuckets(history);
    final labels = trend
        .map((bucket) => _taskTrendLabel(bucket.at))
        .toList(growable: false);
    return _metricInsightPage([
      _InsightDonutSection(
        title: '任务状态分布',
        icon: Icons.donut_large_rounded,
        items: [
          _DistributionItem(
            '完成',
            counts['completed']!,
            OpenHandStatusColors.success,
          ),
          _DistributionItem(
            '运行中',
            counts['running']!,
            OpenHandStatusColors.info,
          ),
          _DistributionItem(
            '失败',
            counts['failed']!,
            OpenHandStatusColors.error,
          ),
          _DistributionItem(
            '超时',
            counts['timeout']!,
            OpenHandStatusColors.warning,
          ),
          _DistributionItem('取消', counts['cancelled']!, colors.outline),
        ],
      ),
      _TaskStatusTrendSection(
        range: _range,
        interval: _interval,
        series: _taskTrendSeries(trend, colors.outline),
        labels: labels,
        onScaleStart: (_) => _scaleStartRange = _range,
        onScaleUpdate: _handleScaleUpdate,
        onReset: _resetTrend,
      ),
      const AiExposureTaskLedger(),
    ]);
  }

  List<_TaskTrendBucket> _taskTrendBuckets(
    List<AiExposureHistoryEntry> history,
  ) {
    final end = DateTime.now();
    final start = end.subtract(_range);
    final count = (_range.inMilliseconds / _interval.inMilliseconds)
        .ceil()
        .clamp(1, 240);
    final buckets = List<_TaskTrendBucket>.generate(
      count,
      (index) => _TaskTrendBucket(
        at: start.add(_interval * index),
        counts: <String, int>{
          'completed': 0,
          'running': 0,
          'failed': 0,
          'timeout': 0,
          'cancelled': 0,
        },
      ),
      growable: false,
    );
    for (final task in history) {
      final createdAt = task.reportedCreatedAt;
      if (createdAt == null ||
          createdAt.isBefore(start) ||
          createdAt.isAfter(end)) {
        continue;
      }
      final index =
          (createdAt.difference(start).inMilliseconds /
                  _interval.inMilliseconds)
              .floor()
              .clamp(0, buckets.length - 1);
      buckets[index].counts.update(_taskStatusId(task), (value) => value + 1);
    }
    return buckets;
  }

  List<OpenHandChartSeries> _taskTrendSeries(
    List<_TaskTrendBucket> trend,
    Color cancelledColor,
  ) => [
    OpenHandChartSeries(
      label: '完成',
      values: trend
          .map((item) => item.counts['completed']!.toDouble())
          .toList(),
      color: OpenHandStatusColors.success,
    ),
    OpenHandChartSeries(
      label: '运行中',
      values: trend.map((item) => item.counts['running']!.toDouble()).toList(),
      color: OpenHandStatusColors.info,
    ),
    OpenHandChartSeries(
      label: '失败',
      values: trend.map((item) => item.counts['failed']!.toDouble()).toList(),
      color: OpenHandStatusColors.error,
    ),
    OpenHandChartSeries(
      label: '超时',
      values: trend.map((item) => item.counts['timeout']!.toDouble()).toList(),
      color: OpenHandStatusColors.warning,
    ),
    OpenHandChartSeries(
      label: '取消',
      values: trend
          .map((item) => item.counts['cancelled']!.toDouble())
          .toList(),
      color: cancelledColor,
    ),
  ];

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.scale <= 0 || (details.scale - 1).abs() < 0.015) return;
    final range = Duration(
      milliseconds: (_scaleStartRange.inMilliseconds / details.scale)
          .round()
          .clamp(_kTaskTrendMinRangeMs, _kTaskTrendMaxRangeMs),
    );
    final interval = _taskTrendIntervalFor(range);
    if (range == _range && interval == _interval) return;
    setState(() {
      _range = range;
      _interval = interval;
    });
  }

  void _resetTrend() {
    if (_range == _kTaskTrendDefaultRange &&
        _interval == _kTaskTrendDefaultInterval) {
      return;
    }
    setState(() {
      _range = _kTaskTrendDefaultRange;
      _interval = _kTaskTrendDefaultInterval;
    });
  }
}

class _TaskTrendBucket {
  _TaskTrendBucket({required this.at, required this.counts});

  final DateTime at;
  final Map<String, int> counts;
}

class _TaskStatusTrendSection extends StatelessWidget {
  const _TaskStatusTrendSection({
    required this.range,
    required this.interval,
    required this.series,
    required this.labels,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onReset,
  });

  final Duration range;
  final Duration interval;
  final List<OpenHandChartSeries> series;
  final List<String> labels;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Section(
      title: '任务状态数量趋势',
      icon: Icons.stacked_line_chart_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${_taskTrendDurationLabel(range)} · ${_taskTrendDurationLabel(interval)}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              Text(
                '双指缩放时间范围与粒度',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.center_focus_strong_rounded, size: 16),
                label: const Text('恢复默认'),
              ),
            ],
          ),
          kOpenHandGap8,
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: series
                .map((item) => _OpsLegend(label: item.label, color: item.color))
                .toList(growable: false),
          ),
          kOpenHandGap8,
          SizedBox(
            height: 250,
            child: OpenHandTwoFingerScaleGestureDetector(
              onScaleStart: onScaleStart,
              onScaleUpdate: onScaleUpdate,
              child: OpenHandOperationalTrendChart(
                series: series,
                xLabels: labels,
                valueSuffix: ' 个',
                emptyLabel: '暂无任务状态趋势数据',
                height: 250,
                showLegend: false,
                externalLegendProvided: true,
                semanticLabel: '任务状态数量趋势，支持双指缩放',
                onSelectionChanged: (_) {},
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Duration _taskTrendIntervalFor(Duration range) {
  if (range <= const Duration(hours: 2)) return const Duration(minutes: 1);
  if (range <= const Duration(hours: 12)) return const Duration(minutes: 5);
  if (range <= const Duration(days: 2)) return const Duration(minutes: 15);
  if (range <= const Duration(days: 7)) return const Duration(hours: 1);
  return const Duration(hours: 6);
}

String _taskTrendDurationLabel(Duration value) {
  if (value.inDays > 0 && value.inDays * 24 == value.inHours) {
    return '${value.inDays} 天';
  }
  if (value.inHours > 0 && value.inHours * 60 == value.inMinutes) {
    return '${value.inHours} 小时';
  }
  return '${value.inMinutes} 分钟';
}

String _taskTrendLabel(DateTime value) =>
    '${value.month}/${value.day} ${twoDigit(value.hour)}:${twoDigit(value.minute)}';

class AiExposureTaskLedger extends StatefulWidget {
  const AiExposureTaskLedger({
    super.key,
    this.initialStatus = 'all',
    this.tasks,
    this.onOpenTask,
    this.minHeight,
  });

  final String initialStatus;
  final List<AiExposureHistoryEntry>? tasks;
  final ValueChanged<AiExposureHistoryEntry>? onOpenTask;
  final double? minHeight;

  @override
  State<AiExposureTaskLedger> createState() => _TaskLedgerState();
}

class _TaskLedgerState extends State<AiExposureTaskLedger> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _horizontalScroll = ScrollController();
  late String _status;
  String _mode = 'all';
  final Set<AiExposureSource> _sources = <AiExposureSource>{};
  _TaskLedgerTimeRange _timeRange = _TaskLedgerTimeRange.all;
  DateTimeRange? _customTimeRange;
  AiExposureTaskLedgerSort _sort = AiExposureTaskLedgerSort.createdAt;
  bool _descending = true;
  int _page = 1;
  int _pageSize = kOpenHandTableDefaultPageSize;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
  }

  @override
  void dispose() {
    _search.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.tasks == null
        ? context.watch<ServicesController>()
        : null;
    final source = widget.tasks ?? controller!.history;
    final tasks = _filteredTasks(source);
    final refreshedAt = source
        .map((entry) => entry.progress.updatedAt)
        .fold<DateTime?>(
          null,
          (latest, value) =>
              latest == null || value.isAfter(latest) ? value : latest,
        );
    return _Section(
      title: '任务运行账本',
      icon: Icons.table_rows_outlined,
      minHeight: widget.minHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final window = OpenHandPageWindow.normalize(
            page: _page,
            pageSize: _pageSize,
            total: tasks.length,
          );
          final shown = window.slice(tasks);
          final start = tasks.isEmpty ? 0 : window.offset;
          final end = start + shown.length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TaskLedgerScopeBar(
                total: source.length,
                filtered: tasks.length,
                start: tasks.isEmpty ? 0 : start + 1,
                end: end,
                refreshedAt: refreshedAt,
              ),
              kOpenHandGap10,
              _buildToolbar(context, compact),
              kOpenHandGap12,
              if (shown.isEmpty)
                const _InsightEmpty(label: '当前筛选范围内没有任务。')
              else if (compact)
                ...shown.map(
                  (task) => _TaskLedgerCompactRow(
                    task: task,
                    onOpenTask: widget.onOpenTask,
                  ),
                )
              else
                OpenHandSafeScrollbar(
                  controller: _horizontalScroll,
                  thumbVisibility: true,
                  interactive: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    controller: _horizontalScroll,
                    scrollDirection: Axis.horizontal,
                    physics: openHandDialogAwareScrollPhysics(context),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: _kTaskLedgerDesktopTableWidth,
                        child: Column(
                          children: [
                            const _TaskLedgerHeader(),
                            const Divider(height: 1),
                            ...shown.map(
                              (task) => _TaskLedgerDesktopRow(
                                task: task,
                                onOpenTask: widget.onOpenTask,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              kOpenHandGap10,
              _TaskLedgerFooter(
                descending: _descending,
                onToggleDirection: () => setState(() {
                  _descending = !_descending;
                  _page = 1;
                }),
                onReset: _reset,
                pagination: OpenHandTablePagination(
                  total: window.total,
                  page: window.page,
                  pageSize: window.pageSize,
                  onPageChanged: (page) => setState(() => _page = page),
                  onPageSizeChanged: (size) => setState(() {
                    _pageSize = size;
                    _page = 1;
                  }),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, bool compact) {
    final search = SizedBox(
      width: double.infinity,
      height: _kTaskLedgerFilterHeight,
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() => _page = 1),
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search_rounded),
          labelText: '搜索任务名称、ID、错误摘要',
          border: OutlineInputBorder(),
        ),
      ),
    );
    final controls = <Widget>[
      _TaskLedgerDropdown<String>(
        label: '状态',
        width: double.infinity,
        value: _status,
        items: const [
          ('all', '全部'),
          ('running', '运行中'),
          ('completed', '完成'),
          ('failed', '失败'),
          ('timeout', '超时'),
          ('cancelled', '取消'),
          ('resumable', '可恢复'),
        ],
        onChanged: (value) => setState(() {
          _status = value;
          _page = 1;
        }),
      ),
      _TaskLedgerSourceFilter(
        width: double.infinity,
        selected: _sources,
        onToggle: (source) => setState(() {
          _sources.contains(source)
              ? _sources.remove(source)
              : _sources.add(source);
          _page = 1;
        }),
      ),
      _TaskLedgerDropdown<_TaskLedgerTimeRange>(
        label: '时间',
        width: double.infinity,
        value: _timeRange,
        items: const [
          (_TaskLedgerTimeRange.all, '全部'),
          (_TaskLedgerTimeRange.last24Hours, '24 小时'),
          (_TaskLedgerTimeRange.last7Days, '7 天'),
          (_TaskLedgerTimeRange.last30Days, '30 天'),
          (_TaskLedgerTimeRange.custom, '自定义'),
        ],
        onChanged: (value) => _setTimeRange(context, value),
      ),
      _TaskLedgerDropdown<String>(
        label: '模式',
        width: double.infinity,
        value: _mode,
        items: const [('all', '全部'), ('full', '全量'), ('incremental', '增量')],
        onChanged: (value) => setState(() {
          _mode = value;
          _page = 1;
        }),
      ),
      _TaskLedgerDropdown<AiExposureTaskLedgerSort>(
        label: '排序',
        width: double.infinity,
        value: _sort,
        items: const [
          (AiExposureTaskLedgerSort.createdAt, '创建时间'),
          (AiExposureTaskLedgerSort.finishedAt, '结束时间'),
          (AiExposureTaskLedgerSort.duration, '耗时'),
          (AiExposureTaskLedgerSort.processed, '处理量'),
          (AiExposureTaskLedgerSort.valid, '有效结果'),
          (AiExposureTaskLedgerSort.highValue, '高价值'),
        ],
        onChanged: (value) => setState(() {
          _sort = value;
          _page = 1;
        }),
      ),
    ];
    const controlWeights = [108, 124, 112, 100, 124];
    if (compact) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final filterWidth =
              (constraints.maxWidth - _kTaskLedgerToolbarGap) / 2;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: _kTaskLedgerToolbarGap),
              Wrap(
                spacing: _kTaskLedgerToolbarGap,
                runSpacing: _kTaskLedgerToolbarGap,
                children: controls
                    .map(
                      (control) => SizedBox(width: filterWidth, child: control),
                    )
                    .toList(growable: false),
              ),
            ],
          );
        },
      );
    }
    return Row(
      children: [
        Expanded(flex: 260, child: search),
        for (var index = 0; index < controls.length; index++) ...[
          const SizedBox(width: _kTaskLedgerToolbarGap),
          Expanded(flex: controlWeights[index], child: controls[index]),
        ],
      ],
    );
  }

  List<AiExposureHistoryEntry> _filteredTasks(
    List<AiExposureHistoryEntry> source,
  ) {
    final range = _resolvedTimeRange(DateTime.now());
    return filterAndSortAiExposureTasks(
      source: source,
      query: _search.text,
      status: _status,
      mode: _mode,
      sources: _sources,
      createdFrom: range?.start,
      createdUntil: range?.end,
      sort: _sort,
      descending: _descending,
    );
  }

  DateTimeRange? _resolvedTimeRange(DateTime now) => switch (_timeRange) {
    _TaskLedgerTimeRange.all => null,
    _TaskLedgerTimeRange.last24Hours => DateTimeRange(
      start: now.subtract(const Duration(hours: 24)),
      end: now,
    ),
    _TaskLedgerTimeRange.last7Days => DateTimeRange(
      start: now.subtract(const Duration(days: 7)),
      end: now,
    ),
    _TaskLedgerTimeRange.last30Days => DateTimeRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
    ),
    _TaskLedgerTimeRange.custom => _customTimeRange,
  };

  Future<void> _setTimeRange(
    BuildContext context,
    _TaskLedgerTimeRange value,
  ) async {
    if (value != _TaskLedgerTimeRange.custom) {
      setState(() {
        _timeRange = value;
        _page = 1;
      });
      return;
    }
    final now = DateTime.now();
    final selected = await showAnimatedDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day + 1),
      initialDateRange: _customTimeRange,
      helpText: '选择任务创建日期范围',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
    );
    if (!mounted || selected == null) return;
    setState(() {
      _timeRange = value;
      _customTimeRange = DateTimeRange(
        start: DateTime(
          selected.start.year,
          selected.start.month,
          selected.start.day,
        ),
        end: DateTime(
          selected.end.year,
          selected.end.month,
          selected.end.day + 1,
        ).subtract(const Duration(microseconds: 1)),
      );
      _page = 1;
    });
  }

  void _reset() {
    _search.clear();
    setState(() {
      _status = 'all';
      _mode = 'all';
      _sources.clear();
      _timeRange = _TaskLedgerTimeRange.all;
      _customTimeRange = null;
      _sort = AiExposureTaskLedgerSort.createdAt;
      _descending = true;
      _page = 1;
    });
  }
}

class _TaskLedgerSourceFilter extends StatelessWidget {
  const _TaskLedgerSourceFilter({
    required this.width,
    required this.selected,
    required this.onToggle,
  });

  final double width;
  final Set<AiExposureSource> selected;
  final ValueChanged<AiExposureSource> onToggle;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: _kTaskLedgerFilterHeight,
    child: AnimatedPopupMenuButton<AiExposureSource>(
      tooltip: '按来源筛选',
      onSelected: onToggle,
      itemBuilder: (context) => AiExposureSource.values
          .map(
            (source) => CheckedPopupMenuItem<AiExposureSource>(
              value: source,
              checked: selected.contains(source),
              child: Text(aiExposureSourceDisplayName(source)),
            ),
          )
          .toList(growable: false),
      child: InputDecorator(
        decoration: _kTaskLedgerFilterDecoration.copyWith(
          labelText: '来源',
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 18,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(
                selected.isEmpty ? '全部' : '已选 ${selected.length} 项',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            kOpenHandHGap4,
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 24,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    ),
  );
}

class _TaskLedgerScopeBar extends StatelessWidget {
  const _TaskLedgerScopeBar({
    required this.total,
    required this.filtered,
    required this.start,
    required this.end,
    required this.refreshedAt,
  });

  final int total;
  final int filtered;
  final int start;
  final int end;
  final DateTime? refreshedAt;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _InsightContextBar(
      icon: Icons.history_rounded,
      label: '数据范围',
      value: '任务历史记录',
      helper: '当前服务返回',
      color: colors.primary,
      items: [
        _InsightContextDatum(
          icon: Icons.data_usage_rounded,
          label: '任务总量',
          value: '$total',
        ),
        _InsightContextDatum(
          icon: Icons.filter_alt_outlined,
          label: '匹配筛选',
          value: '$filtered',
        ),
        _InsightContextDatum(
          icon: Icons.view_list_outlined,
          label: '当前页',
          value: filtered == 0 ? '0 条' : '$start-$end',
        ),
        _InsightContextDatum(
          icon: Icons.update_rounded,
          label: '最近更新',
          value: refreshedAt == null
              ? '暂无任务数据'
              : _taskLedgerDateTime(refreshedAt!),
          flex: 2,
        ),
      ],
    );
  }
}

class _TaskLedgerDropdown<T> extends StatelessWidget {
  const _TaskLedgerDropdown({
    required this.label,
    required this.width,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final double width;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: _kTaskLedgerFilterHeight,
    child: AnimatedDropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: _kTaskLedgerFilterDecoration.copyWith(labelText: label),
      items: items
          .map(
            (item) => DropdownMenuItem<T>(
              value: item.$1,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
      selectedItemBuilder: (context) => items
          .map(
            (item) =>
                Text(item.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
          )
          .toList(growable: false),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    ),
  );
}

class _TaskLedgerFooter extends StatelessWidget {
  const _TaskLedgerFooter({
    required this.descending,
    required this.onToggleDirection,
    required this.onReset,
    required this.pagination,
  });

  final bool descending;
  final VoidCallback onToggleDirection;
  final VoidCallback onReset;
  final Widget pagination;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final buttonStyle = IconButton.styleFrom(
      fixedSize: const Size.square(40),
      padding: EdgeInsets.zero,
      backgroundColor: colors.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: descending ? '当前降序，点击切换升序' : '当前升序，点击切换降序',
                onPressed: onToggleDirection,
                style: buttonStyle,
                icon: Icon(
                  descending ? Icons.south_rounded : Icons.north_rounded,
                ),
              ),
              kOpenHandHGap8,
              IconButton(
                tooltip: '重置筛选',
                onPressed: onReset,
                style: buttonStyle,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ),
        ),
        kOpenHandGap10,
        pagination,
      ],
    );
  }
}

class _TaskLedgerHeader extends StatelessWidget {
  const _TaskLedgerHeader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(
      horizontal: _kTaskLedgerDesktopRowHorizontalPadding,
    ),
    child: SizedBox(
      height: 40,
      child: Row(
        children: [
          _TaskLedgerCell(width: _kTaskLedgerStatusWidth, child: Text('状态')),
          _TaskLedgerCell(width: _kTaskLedgerCreatedWidth, child: Text('创建时间')),
          _TaskLedgerCell(width: _kTaskLedgerStartedWidth, child: Text('开始时间')),
          _TaskLedgerCell(
            width: _kTaskLedgerFinishedWidth,
            child: Text('结束时间'),
          ),
          _TaskLedgerCell(width: _kTaskLedgerDurationWidth, child: Text('耗时')),
          _TaskLedgerCell(width: _kTaskLedgerNameWidth, child: Text('任务名称')),
          _TaskLedgerCell(width: _kTaskLedgerIdWidth, child: Text('任务 ID')),
          _TaskLedgerCell(width: _kTaskLedgerModeWidth, child: Text('模式')),
          _TaskLedgerCell(width: _kTaskLedgerSourceWidth, child: Text('来源')),
          _TaskLedgerCell(
            width: _kTaskLedgerProgressWidth,
            child: Text('处理进度'),
          ),
          _TaskLedgerCell(
            width: _kTaskLedgerCandidatesWidth,
            child: Text('候选'),
          ),
          _TaskLedgerCell(width: _kTaskLedgerValidWidth, child: Text('有效')),
          _TaskLedgerCell(
            width: _kTaskLedgerHighValueWidth,
            child: Text('高价值'),
          ),
          _TaskLedgerCell(width: _kTaskLedgerUpdatedWidth, child: Text('最近更新')),
          _TaskLedgerCell(
            width: _kTaskLedgerFailureStageWidth,
            child: Text('失败阶段'),
          ),
          _TaskLedgerCell(width: _kTaskLedgerRetryWidth, child: Text('重试')),
          _TaskLedgerCell(
            width: _kTaskLedgerConcurrencyWidth,
            child: Text('并发'),
          ),
          _TaskLedgerCell(width: _kTaskLedgerScopeWidth, child: Text('授权范围')),
          _TaskLedgerCell(width: _kTaskLedgerErrorWidth, child: Text('错误摘要')),
          _TaskLedgerCell(width: _kTaskLedgerDetailsWidth, child: Text('详情')),
        ],
      ),
    ),
  );
}

class _TaskLedgerDesktopRow extends StatelessWidget {
  const _TaskLedgerDesktopRow({required this.task, this.onOpenTask});

  final AiExposureHistoryEntry task;
  final ValueChanged<AiExposureHistoryEntry>? onOpenTask;

  @override
  Widget build(BuildContext context) {
    final status = _taskLedgerStatus(task);
    final startedAt = task.startedAt ?? task.reportedCreatedAt;
    final finishedAt = task.effectiveFinishedAt;
    final fraction = task.progress.total <= 0
        ? 0.0
        : (task.progress.processed / task.progress.total).clamp(0.0, 1.0);
    return ServiceInteractiveSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: _kTaskLedgerDesktopRowHorizontalPadding,
        vertical: 4,
      ),
      tooltip: '查看任务详情',
      showDetailsIcon: false,
      onTap: () {
        final callback = onOpenTask;
        if (callback != null) {
          callback(task);
          return;
        }
        _openInsightTarget(context, _TaskInsightTarget(task));
      },
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            _TaskLedgerCell(
              width: _kTaskLedgerStatusWidth,
              child: Row(
                children: [
                  Icon(status.$1, size: 15, color: status.$3),
                  kOpenHandHGap4,
                  Flexible(
                    child: Text(status.$2, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerCreatedWidth,
              child: Text(
                task.createdAtReported
                    ? _taskLedgerDateTime(task.createdAt)
                    : '未上报',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerStartedWidth,
              child: Text(
                startedAt == null ? '未上报' : _taskLedgerDateTime(startedAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerFinishedWidth,
              child: Text(
                finishedAt == null ? '运行中' : _taskLedgerDateTime(finishedAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerDurationWidth,
              child: Text(_taskLedgerDurationText(task)),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerNameWidth,
              child: Text(
                task.name.trim().isEmpty ? task.id : task.name.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerIdWidth,
              child: Text(
                task.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerModeWidth,
              child: Text(task.mode == AiExposureScanMode.full ? '全量' : '增量'),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerSourceWidth,
              child: Text(
                _taskLedgerSources(task.sources),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerProgressWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${task.progress.processed}/${task.progress.total}'),
                  kOpenHandGap4,
                  ServiceAnimatedProgressBar(value: fraction),
                ],
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerCandidatesWidth,
              child: Text('${task.progress.candidates}'),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerValidWidth,
              child: Text('${task.progress.valid}'),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerHighValueWidth,
              child: Text('${task.progress.highValue}'),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerUpdatedWidth,
              child: Text(
                task.progress.updatedAtReported
                    ? _taskLedgerDateTime(task.progress.updatedAt)
                    : '未上报',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerFailureStageWidth,
              child: Text(
                task.failureStage?.trim().isNotEmpty == true
                    ? _stageName(task.failureStage!)
                    : '--',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerRetryWidth,
              child: Text('${task.retryCount ?? 0}'),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerConcurrencyWidth,
              child: Text('${task.concurrency ?? '--'}'),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerScopeWidth,
              child: Text(
                task.authorizedScope.isEmpty
                    ? '未记录'
                    : task.authorizedScope.take(2).join(' / '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerErrorWidth,
              child: Text(
                task.errorMessage?.trim().isNotEmpty == true
                    ? task.errorMessage!.trim()
                    : task.progress.message.trim().isEmpty
                    ? '--'
                    : task.progress.message.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerDetailsWidth,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskLedgerCompactRow extends StatelessWidget {
  const _TaskLedgerCompactRow({required this.task, this.onOpenTask});

  final AiExposureHistoryEntry task;
  final ValueChanged<AiExposureHistoryEntry>? onOpenTask;

  @override
  Widget build(BuildContext context) {
    final status = _taskLedgerStatus(task);
    final finishedAt = task.effectiveFinishedAt;
    return ServiceInteractiveSurface(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
      tooltip: '查看任务详情',
      onTap: () {
        final callback = onOpenTask;
        if (callback != null) {
          callback(task);
          return;
        }
        _openInsightTarget(context, _TaskInsightTarget(task));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(status.$1, size: 17, color: status.$3),
              kOpenHandHGap6,
              Expanded(
                child: Text(
                  task.name.trim().isEmpty ? task.id : task.name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          kOpenHandGap4,
          Text(
            task.createdAtReported
                ? '创建时间：${_taskLedgerDateTime(task.createdAt)}'
                : '创建时间：未上报',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          kOpenHandGap6,
          Text(
            '${status.$2} · ${task.mode == AiExposureScanMode.full ? '全量' : '增量'} · ${_taskLedgerSources(task.sources)} · 处理 ${task.progress.processed}/${task.progress.total} · 候选 ${task.progress.candidates} · 有效 ${task.progress.valid} · 高价值 ${task.progress.highValue}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          kOpenHandGap4,
          Text(
            finishedAt == null
                ? '结束时间：运行中 · 已运行 ${_taskLedgerDurationText(task)}'
                : '结束时间：${_taskLedgerDateTime(finishedAt)} · 耗时 ${_taskLedgerDurationText(task)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (task.errorMessage?.trim().isNotEmpty == true) ...[
            kOpenHandGap4,
            Text(
              task.errorMessage!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: OpenHandStatusColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskLedgerCell extends StatelessWidget {
  const _TaskLedgerCell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodySmall,
        child: child,
      ),
    );
    return SizedBox(width: width, child: content);
  }
}

(IconData, String, Color) _taskLedgerStatus(
  AiExposureHistoryEntry task,
) => switch (_taskStatusId(task)) {
  'completed' => (
    Icons.check_circle_outline_rounded,
    '完成',
    OpenHandStatusColors.success,
  ),
  'failed' => (Icons.error_outline_rounded, '失败', OpenHandStatusColors.error),
  'timeout' => (Icons.timer_off_outlined, '超时', OpenHandStatusColors.warning),
  'cancelled' => (Icons.cancel_outlined, '取消', OpenHandStatusColors.warning),
  _ => (Icons.pending_actions_rounded, '运行中', OpenHandStatusColors.info),
};

int _taskLedgerTimeValue(DateTime? value) => value?.millisecondsSinceEpoch ?? 0;

int _taskLedgerDuration(AiExposureHistoryEntry task, DateTime now) =>
    task.durationUntil(now)?.inMilliseconds ?? 0;

String _taskLedgerDurationText(AiExposureHistoryEntry task) {
  final duration = task.durationUntil(DateTime.now());
  if (duration == null) return '--';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

String _taskLedgerSources(List<AiExposureSource> sources) {
  if (sources.isEmpty) return '历史记录缺少来源';
  final visible = sources.take(2).map(aiExposureSourceDisplayName).join(' / ');
  return sources.length <= 2 ? visible : '$visible +${sources.length - 2}';
}

String _taskLedgerDateTime(DateTime value) {
  return formatYearMonthDayHmsLocal(value);
}
