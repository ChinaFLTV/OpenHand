part of 'ai_exposure_monitoring_dialogs.dart';

const double _kTaskLedgerFilterHeight = 56;
const InputDecoration _kTaskLedgerFilterDecoration = InputDecoration(
  isDense: true,
  border: OutlineInputBorder(),
  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  constraints: BoxConstraints.tightFor(height: _kTaskLedgerFilterHeight),
);
const double _kTaskLedgerDesktopTableWidth = 1640;
const Duration _kTaskLedgerPageMotionDuration = Duration(milliseconds: 180);
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
const double _kTaskLedgerDetailsWidth = 56;

enum AiExposureTaskLedgerSort {
  createdAt,
  finishedAt,
  duration,
  processed,
  valid,
  highValue,
}

enum _TaskLedgerTimeRange { all, last24Hours, last7Days, last30Days, custom }

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
          'running' => !task.isTerminal,
          'completed' => task.stage == 'completed',
          'failed' => task.stage == 'failed',
          'cancelled' => task.stage == 'cancelled',
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
        if (createdFrom != null && task.createdAt.isBefore(createdFrom)) {
          return false;
        }
        return createdUntil == null || !task.createdAt.isAfter(createdUntil);
      })
      .toList(growable: false);
  tasks.sort((left, right) {
    final compared = switch (sort) {
      AiExposureTaskLedgerSort.createdAt => left.createdAt.compareTo(
        right.createdAt,
      ),
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
      if (controller.progress != null) controller.progress!.updatedAt,
      ...controller.history.map((entry) => entry.progress.updatedAt),
      ...controller.results.map((entry) => entry.createdAt),
      ...controller.logs.map((entry) => entry.at),
    ]..sort();
    final updatedAt = candidates.lastOrNull;
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(controller.isRunning ? '数据口径：当前服务快照' : '数据口径：离线快照'),
          Text('任务 ${controller.history.length}'),
          Text('结果 ${controller.results.length}'),
          Text('日志 ${controller.logs.length}'),
          Text(
            updatedAt == null
                ? '更新时间：暂无运行数据'
                : '更新时间：${_taskLedgerDateTime(updatedAt)}',
          ),
          Text(controller.isRunning ? '新鲜度：实时' : '新鲜度：服务离线'),
        ],
      ),
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

class AiExposureTaskLedger extends StatefulWidget {
  const AiExposureTaskLedger({
    super.key,
    this.initialStatus = 'all',
    this.tasks,
    this.onOpenTask,
  });

  final String initialStatus;
  final List<AiExposureHistoryEntry>? tasks;
  final ValueChanged<AiExposureHistoryEntry>? onOpenTask;

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
  int _page = 0;

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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final pageSize = compact ? 20 : 50;
          final pageCount = tasks.isEmpty
              ? 1
              : (tasks.length / pageSize).ceil();
          final page = _page.clamp(0, pageCount - 1);
          final start = tasks.isEmpty ? 0 : page * pageSize;
          final end = (start + pageSize).clamp(0, tasks.length);
          final shown = tasks.sublist(start, end);
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
              const SizedBox(height: 10),
              _buildToolbar(context, compact, source),
              const SizedBox(height: 12),
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
              const SizedBox(height: 10),
              _TaskLedgerFooter(
                compact: compact,
                countLabel: tasks.isEmpty
                    ? '共 0 条'
                    : '共 ${tasks.length} 条，当前显示 ${start + 1}-$end',
                page: page,
                pageCount: pageCount,
                descending: _descending,
                onToggleDirection: () => setState(() {
                  _descending = !_descending;
                  _page = 0;
                }),
                onReset: _reset,
                onPrevious: page <= 0
                    ? null
                    : () => setState(() => _page = page - 1),
                onNext: page >= pageCount - 1
                    ? null
                    : () => setState(() => _page = page + 1),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    bool compact,
    List<AiExposureHistoryEntry> source,
  ) {
    final search = SizedBox(
      width: compact ? double.infinity : 260,
      height: _kTaskLedgerFilterHeight,
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() => _page = 0),
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
        width: compact ? double.infinity : 108,
        value: _status,
        items: const [
          ('all', '全部'),
          ('running', '运行中'),
          ('completed', '完成'),
          ('failed', '失败'),
          ('cancelled', '取消'),
          ('resumable', '可恢复'),
        ],
        onChanged: (value) => setState(() {
          _status = value;
          _page = 0;
        }),
      ),
      _TaskLedgerSourceFilter(
        width: compact ? double.infinity : 124,
        available: source.expand((task) => task.sources).toSet().toList()
          ..sort((left, right) => left.index.compareTo(right.index)),
        selected: _sources,
        onToggle: (source) => setState(() {
          _sources.contains(source)
              ? _sources.remove(source)
              : _sources.add(source);
          _page = 0;
        }),
      ),
      _TaskLedgerDropdown<_TaskLedgerTimeRange>(
        label: '时间',
        width: compact ? double.infinity : 112,
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
        width: compact ? double.infinity : 100,
        value: _mode,
        items: const [('all', '全部'), ('full', '全量'), ('incremental', '增量')],
        onChanged: (value) => setState(() {
          _mode = value;
          _page = 0;
        }),
      ),
      _TaskLedgerDropdown<AiExposureTaskLedgerSort>(
        label: '排序',
        width: compact ? double.infinity : 124,
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
          _page = 0;
        }),
      ),
    ];
    if (compact) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final filterWidth = (constraints.maxWidth - 8) / 2;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [search, ...controls],
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
        _page = 0;
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
      _page = 0;
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
      _page = 0;
    });
  }
}

class _TaskLedgerSourceFilter extends StatelessWidget {
  const _TaskLedgerSourceFilter({
    required this.width,
    required this.available,
    required this.selected,
    required this.onToggle,
  });

  final double width;
  final List<AiExposureSource> available;
  final Set<AiExposureSource> selected;
  final ValueChanged<AiExposureSource> onToggle;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: _kTaskLedgerFilterHeight,
    child: AnimatedPopupMenuButton<AiExposureSource>(
      tooltip: '按来源筛选',
      enabled: available.isNotEmpty,
      onSelected: onToggle,
      itemBuilder: (context) => available
          .map(
            (source) => CheckedPopupMenuItem<AiExposureSource>(
              value: source,
              checked: selected.contains(source),
              child: Text(_sourceName(source)),
            ),
          )
          .toList(growable: false),
      child: InputDecorator(
        decoration: _kTaskLedgerFilterDecoration.copyWith(labelText: '来源'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Text(selected.isEmpty ? '全部' : '已选 ${selected.length} 项'),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down_rounded, size: 20),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          const Text('数据范围：当前服务返回的任务历史记录'),
          Text('总量 $total'),
          Text(filtered == 0 ? '当前显示 0 条' : '当前显示 $start-$end'),
          Text(
            refreshedAt == null
                ? '更新时间：暂无任务数据'
                : '更新时间：${_taskLedgerDateTime(refreshedAt!)}',
          ),
        ],
      ),
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
            (item) => DropdownMenuItem<T>(value: item.$1, child: Text(item.$2)),
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
    required this.compact,
    required this.countLabel,
    required this.page,
    required this.pageCount,
    required this.descending,
    required this.onToggleDirection,
    required this.onReset,
    required this.onPrevious,
    required this.onNext,
  });

  final bool compact;
  final String countLabel;
  final int page;
  final int pageCount;
  final bool descending;
  final VoidCallback onToggleDirection;
  final VoidCallback onReset;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final buttonStyle = IconButton.styleFrom(
      fixedSize: const Size.square(40),
      padding: EdgeInsets.zero,
      backgroundColor: colors.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    final count = Text(
      countLabel,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: descending ? '当前降序，点击切换升序' : '当前升序，点击切换降序',
          onPressed: onToggleDirection,
          style: buttonStyle,
          icon: Icon(descending ? Icons.south_rounded : Icons.north_rounded),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '重置筛选',
          onPressed: onReset,
          style: buttonStyle,
          icon: const Icon(Icons.restart_alt_rounded),
        ),
        const SizedBox(width: 16),
        SizedBox(
          height: 24,
          child: VerticalDivider(color: colors.outlineVariant),
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: '上一页',
          onPressed: onPrevious,
          style: buttonStyle,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 52,
          child: AnimatedSwitcher(
            duration: openHandMotionDuration(
              context,
              _kTaskLedgerPageMotionDuration,
            ),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              '${page + 1}/$pageCount',
              key: ValueKey<(int, int)>((page, pageCount)),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: '下一页',
          onPressed: onNext,
          style: buttonStyle,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          count,
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight, child: controls),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: count),
        controls,
      ],
    );
  }
}

class _TaskLedgerHeader extends StatelessWidget {
  const _TaskLedgerHeader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 6),
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
    final startedAt = task.startedAt ?? task.createdAt;
    final finishedAt = task.effectiveFinishedAt;
    final fraction = task.progress.total <= 0
        ? 0.0
        : (task.progress.processed / task.progress.total).clamp(0.0, 1.0);
    return ServiceInteractiveSurface(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(status.$2, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerCreatedWidth,
              child: Text(
                _taskLedgerDateTime(task.createdAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TaskLedgerCell(
              width: _kTaskLedgerStartedWidth,
              child: Text(
                _taskLedgerDateTime(startedAt),
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
                task.name.trim().isEmpty ? task.id : task.name,
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
                  const SizedBox(height: 4),
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
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task.name.trim().isEmpty ? task.id : task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '创建时间：${_taskLedgerDateTime(task.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${status.$2} · ${task.mode == AiExposureScanMode.full ? '全量' : '增量'} · ${_taskLedgerSources(task.sources)} · 处理 ${task.progress.processed}/${task.progress.total} · 候选 ${task.progress.candidates} · 有效 ${task.progress.valid} · 高价值 ${task.progress.highValue}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            finishedAt == null
                ? '结束时间：运行中 · 已运行 ${_taskLedgerDurationText(task)}'
                : '结束时间：${_taskLedgerDateTime(finishedAt)} · 耗时 ${_taskLedgerDurationText(task)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (task.errorMessage?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
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
) => switch (task.stage) {
  'completed' => (
    Icons.check_circle_outline_rounded,
    '完成',
    OpenHandStatusColors.success,
  ),
  'failed' => (Icons.error_outline_rounded, '失败', OpenHandStatusColors.error),
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
  final visible = sources.take(2).map(_sourceName).join(' / ');
  return sources.length <= 2 ? visible : '$visible +${sources.length - 2}';
}

String _taskLedgerDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
