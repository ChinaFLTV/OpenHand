part of 'settings_view.dart';

const double _kAiUsageMetricThreeColumnMinWidth = 660;
const double _kAiUsageMetricTwoColumnMinWidth = 440;
const double _kAiUsageMetricHeight = 150;
const double _kAiUsageHeatmapMinWidth = 820;
const double _kAiUsageBreakdownTableMinWidth = 860;
const double _kAiUsageBreakdownHeaderHeight = 46;
const double _kAiUsageBreakdownRowHeight = 74;
const double _kAiUsageBreakdownBodyMaxHeight = 444;
const double _kAiUsageToolbarControlHeight = 40;
const double _kAiUsageFilterChipMinWidth = 96;
const double _kAiUsageFilterChipIconSlotWidth = 26;
const double _kAiUsageRequestTimeColumnMinWidth = 220;
const double _kAiUsageHeroInlineMinWidth = 840;
const double _kAiUsageOverviewFourColumnMinWidth = 1040;
const double _kAiUsageOverviewTwoColumnMinWidth = 560;
const double _kAiUsageDistributionTwoColumnMinWidth = 860;
const double _kAiUsageOverviewMetricHeight = 150;
const double _kAiUsageDistributionRowHeight = 52;
const double _kAiUsageDistributionBodyMaxHeight = 312;
const double _kAiUsageDistributionEmptyBodyHeight = 72;
const Duration _kAiUsageRefreshDebounce = Duration(milliseconds: 600);
const OpenHandAnimationTransitionProfile _kAiUsagePanelTransitionProfile =
    OpenHandAnimationTransitionProfile(
      alignment: Alignment.topCenter,
      fadeScaleBegin: 0.985,
      expandScaleBegin: 0.97,
      rotateScaleBegin: 0.985,
      elasticScaleBegin: 0.985,
      springScaleBegin: 0.985,
      slideUpOffset: Offset(0, 0.035),
      slideDownOffset: Offset(0, -0.035),
      slideLeftOffset: Offset(-0.035, 0),
      slideRightOffset: Offset(0.035, 0),
    );

Widget _buildAiUsageAnimatedSwap(BuildContext context, Widget child) {
  final settings = openHandMotionSettingsOf(
    context,
    OpenHandMotionSettingsScope.panel,
  );
  if (settings.disablesAnimation || settings.duration <= Duration.zero) {
    return child;
  }
  return ClipRect(
    child: AnimatedSize(
      duration: settings.entranceDuration,
      reverseDuration: settings.exitDuration,
      curve: kOpenHandEmphasizedCurve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: settings.entranceDuration,
        reverseDuration: settings.exitDuration,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        transitionBuilder: (animatedChild, animation) =>
            buildAnimationStyleTransition(
              animation: animation,
              settings: settings,
              profile: _kAiUsagePanelTransitionProfile,
              child: RepaintBoundary(child: animatedChild),
            ),
        child: child,
      ),
    ),
  );
}

class _AiUsageSettingsSection extends StatefulWidget {
  const _AiUsageSettingsSection({
    this.embedded = false,
    this.initialFilter = const AiUsageFilter(),
  });

  final bool embedded;
  final AiUsageFilter initialFilter;

  @override
  State<_AiUsageSettingsSection> createState() =>
      _AiUsageSettingsSectionState();
}

class _AiUsageSettingsSectionState extends State<_AiUsageSettingsSection> {
  late AiUsageFilter _filter = widget.initialFilter;
  AiUsageSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  int _loadGeneration = 0;
  Timer? _refreshDebounce;

  AiUsageTracker get _tracker => AiUsageTracker.instance;

  @override
  void initState() {
    super.initState();
    _tracker.changes.addListener(_scheduleRefresh);
    unawaited(_load());
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _tracker.changes.removeListener(_scheduleRefresh);
    super.dispose();
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = startSafeTimer(_kAiUsageRefreshDebounce, () async {
      _refreshDebounce = null;
      if (!mounted) return;
      await _load(quiet: true);
    });
  }

  Future<void> _load({bool quiet = false}) async {
    final generation = ++_loadGeneration;
    if (!quiet && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snapshot = await _tracker.loadSnapshot(_filter);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _error = null;
      });
    } catch (error, stack) {
      silentLog('settings_ai_usage', '加载 AI 使用统计', error, stack);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _showFilterDialog() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final next = await showAnimatedDialog<AiUsageFilter>(
      context: context,
      builder: (_) => _AiUsageFilterDialog(
        initial: _filter,
        providerFacets: snapshot.providerFacets,
        modelFacets: snapshot.modelFacets,
        sourceFacets: snapshot.sourceFacets,
      ),
    );
    if (!mounted || next == null) return;
    setState(() => _filter = next);
    await _load();
  }

  Future<void> _clearStatistics() async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '清空 AI 使用统计？',
        en: 'Clear AI usage analytics?',
      ),
      message: openHandLocalizedText(
        context,
        zh: '会永久删除本机保存的 Token、成本与请求统计，不影响会话消息和知识库内容。',
        en: 'This permanently removes local token, cost, and request analytics. Sessions and knowledge content are not affected.',
      ),
      cancelLabel: openHandCancelLabel(context),
      confirmLabel: _settingsClearLabel(context),
      destructive: true,
    );
    if (confirmed != true) return;
    await _tracker.clear();
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    showOpenHandSuccessSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '使用统计已清空',
        en: 'Usage analytics cleared',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildToolbar(context),
        if (_loading && _snapshot == null) ...[
          kOpenHandGap24,
          const LinearProgressIndicator(minHeight: 3),
          kOpenHandGap18,
          _AiUsageLoadingState(),
        ] else if (_error != null && _snapshot == null) ...[
          kOpenHandGap20,
          Column(
            children: [
              _SettingsStateBox(
                icon: Icons.query_stats_rounded,
                title: openHandLocalizedText(
                  context,
                  zh: '使用统计加载失败',
                  en: 'Usage analytics could not be loaded',
                ),
                body: '$_error',
              ),
              kOpenHandGap12,
              FilledButton.tonalIcon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(openHandRetryLabel(context)),
              ),
            ],
          ),
        ] else if (_snapshot case final snapshot?) ...[
          kOpenHandGap20,
          _buildAiUsageAnimatedSwap(
            context,
            KeyedSubtree(
              key: ValueKey<int>(snapshot.generatedAt.microsecondsSinceEpoch),
              child: snapshot.summary.requestCount == 0
                  ? _AiUsageEmptyState(hasFilters: _activeFilterCount > 0)
                  : _buildAnalytics(context, snapshot),
            ),
          ),
        ],
      ],
    );
    if (widget.embedded) return child;
    return _SettingsSubsectionCard(
      title: openHandLocalizedText(context, zh: '使用统计', en: 'Usage Analytics'),
      description: openHandLocalizedText(
        context,
        zh: '查看线程、知识库、子任务与辅助 AI 请求的 Token 消耗、成本、缓存效率和性能追踪。',
        en: 'Inspect token usage, cost, cache efficiency, and performance traces across threads, knowledge, subagents, and supporting AI requests.',
      ),
      child: child,
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final range in AiUsageRange.values)
              ChoiceChip(
                showCheckmark: false,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_filter.range == range) ...[
                      Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(_usageRangeLabel(context, range)),
                  ],
                ),
                selected: _filter.range == range,
                onSelected: (selected) {
                  if (!selected || _filter.range == range) return;
                  setState(() => _filter = _filter.copyWith(range: range));
                  unawaited(_load());
                },
              ),
            OutlinedButton.icon(
              onPressed: _snapshot == null ? null : _showFilterDialog,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, _kAiUsageToolbarControlHeight),
                maximumSize: const Size(
                  double.infinity,
                  _kAiUsageToolbarControlHeight,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Badge(
                isLabelVisible: _activeFilterCount > 0,
                label: Text('$_activeFilterCount'),
                backgroundColor: colorScheme.primary,
                textColor: colorScheme.onPrimary,
                child: const Icon(Icons.tune_rounded, size: 19),
              ),
              label: Text(
                openHandLocalizedText(context, zh: '多维筛选', en: 'Filters'),
              ),
            ),
            IconButton.outlined(
              onPressed: _loading ? null : _load,
              tooltip: openHandLocalizedText(
                context,
                zh: '刷新统计',
                en: 'Refresh analytics',
              ),
              icon: AnimatedRotation(
                turns: _loading ? 1 : 0,
                duration: openHandMotionDuration(context, kOpenHandMotion520),
                curve: kOpenHandSwitchInCurve,
                child: const Icon(Icons.refresh_rounded),
              ),
            ),
            IconButton.outlined(
              onPressed: _snapshot?.summary.requestCount == 0
                  ? null
                  : _clearStatistics,
              tooltip: openHandLocalizedText(
                context,
                zh: '清空统计',
                en: 'Clear analytics',
              ),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }

  int get _activeFilterCount =>
      (_filter.providerConfigId == null ? 0 : 1) +
      (_filter.modelId == null ? 0 : 1) +
      (_filter.source == null ? 0 : 1) +
      (_filter.scope == AiUsageDataScope.all ? 0 : 1);

  Widget _buildAnalytics(BuildContext context, AiUsageSnapshot snapshot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AiUsageHero(summary: snapshot.summary),
        kOpenHandGap14,
        _AiUsageOverviewPanel(snapshot: snapshot),
        kOpenHandGap14,
        _AiUsageMetricGrid(summary: snapshot.summary),
        kOpenHandGap14,
        _AiUsagePanel(
          title: openHandLocalizedText(context, zh: '使用趋势', en: 'Usage Trend'),
          subtitle: openHandLocalizedText(
            context,
            zh: '输入、输出与缓存命中随时间变化，双指缩放调整范围',
            en: 'Input, output and cache hits over time; pinch to zoom the range',
          ),
          trailing: Text(_usageRangeLabel(context, snapshot.filter.range)),
          child: _AiUsageTrendChart(buckets: snapshot.trend),
        ),
        kOpenHandGap14,
        _AiUsagePanel(
          title: openHandLocalizedText(
            context,
            zh: '请求状态趋势',
            en: 'Request Status Trend',
          ),
          subtitle: openHandLocalizedText(
            context,
            zh: '成功、失败、超时与请求总数随时间变化，独立统计请求结果',
            en: 'Success, failures, timeouts and total requests over time',
          ),
          trailing: Text(_usageRangeLabel(context, snapshot.filter.range)),
          child: _AiUsageTrendChart(
            buckets: snapshot.trend,
            mode: _AiUsageTrendMode.status,
          ),
        ),
        kOpenHandGap14,
        _AiUsageHealthPanel(snapshot: snapshot),
        kOpenHandGap14,
        _AiUsagePanel(
          title: openHandLocalizedText(
            context,
            zh: '每日 Token 热力图',
            en: 'Daily Token Heatmap',
          ),
          subtitle: openHandLocalizedText(
            context,
            zh: '最近一年每日消耗，颜色越深表示 Token 越多',
            en: 'Daily consumption over the last year; darker cells mean more tokens',
          ),
          child: _AiUsageHeatmap(buckets: snapshot.heatmap),
        ),
        kOpenHandGap14,
        _AiUsageBreakdownPanel(snapshot: snapshot),
        kOpenHandGap14,
        _AiUsageRecentPanel(filter: _filter, revision: snapshot.generatedAt),
      ],
    );
  }
}

/// 服务弹窗复用全局设置中的完整使用统计与请求追踪结构。
class AiUsageAnalyticsView extends StatelessWidget {
  const AiUsageAnalyticsView({
    super.key,
    this.embedded = false,
    this.initialFilter = const AiUsageFilter(),
  });

  final bool embedded;
  final AiUsageFilter initialFilter;

  @override
  Widget build(BuildContext context) =>
      _AiUsageSettingsSection(embedded: embedded, initialFilter: initialFilter);
}

class _AiUsageHero extends StatelessWidget {
  const _AiUsageHero({required this.summary});

  final AiUsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _kAiUsageHeroInlineMinWidth;
          final primary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(kOpenHandRadius15),
                    ),
                    child: Icon(Icons.bolt_rounded, color: colorScheme.primary),
                  ),
                  kOpenHandHGap12,
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '真实消耗 Tokens',
                      en: 'Consumed Tokens',
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              kOpenHandGap14,
              Text(
                _usageCompactNumber(summary.totalTokens, decimals: 2),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.3,
                  height: 1,
                ),
              ),
              kOpenHandGap8,
              Text(
                openHandLocalizedText(
                  context,
                  zh: '${_usageInteger(summary.totalTokens)} 个 Token',
                  en: '${_usageInteger(summary.totalTokens)} tokens',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          final side = Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              _AiUsageHeroPill(
                label: _settingsAiUsagRequestsLabel(context),
                value: _usageInteger(summary.requestCount),
                icon: Icons.monitor_heart_outlined,
                color: colorScheme.primary,
              ),
              _AiUsageHeroPill(
                label: openHandLocalizedText(
                  context,
                  zh: '总成本',
                  en: 'Total Cost',
                ),
                value: summary.pricedRequestCount == 0
                    ? '—'
                    : summary.hasCompletePricing
                    ? _usageMoney(summary.totalCostUsd)
                    : '≥${_usageMoney(summary.totalCostUsd)}',
                icon: Icons.payments_outlined,
                color: colorScheme.tertiary,
              ),
              _AiUsageHeroPill(
                label: _settingsAiUsagSuccessLabel(context),
                value: _usagePercent(summary.successRate),
                icon: Icons.verified_outlined,
                color: OpenHandStatusColors.success,
              ),
              if (summary.failureCount > 0)
                _AiUsageHeroPill(
                  label: openHandLocalizedText(
                    context,
                    zh: '未成功',
                    en: 'Unsuccessful',
                  ),
                  value: _usageInteger(summary.failureCount),
                  icon: Icons.error_outline_rounded,
                  color: OpenHandStatusColors.error,
                ),
            ],
          );
          final alignedSide = Align(
            alignment: AlignmentDirectional.topEnd,
            child: side,
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [primary, kOpenHandGap20, alignedSide],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: primary),
              kOpenHandHGap24,
              alignedSide,
            ],
          );
        },
      ),
    );
  }
}

class _AiUsageHeroPill extends StatelessWidget {
  const _AiUsageHeroPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          kOpenHandHGap9,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              kOpenHandGap2,
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiUsageMetricGrid extends StatelessWidget {
  const _AiUsageMetricGrid({required this.summary});

  final AiUsageSummary summary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metrics = <_AiUsageMetricData>[
      _AiUsageMetricData(
        label: openHandLocalizedText(context, zh: '输入 Token', en: 'Input'),
        value: _usageCompactNumber(summary.promptTokens),
        detail: openHandLocalizedText(
          context,
          zh: '发送给模型的上下文',
          en: 'Context sent to models',
        ),
        icon: Icons.south_rounded,
        color: colorScheme.primary,
      ),
      _AiUsageMetricData(
        label: openHandLocalizedText(context, zh: '输出 Token', en: 'Output'),
        value: _usageCompactNumber(summary.completionTokens),
        detail: openHandLocalizedText(
          context,
          zh: '模型生成内容',
          en: 'Model-generated content',
        ),
        icon: Icons.north_rounded,
        color: colorScheme.tertiary,
      ),
      _AiUsageMetricData(
        label: openHandLocalizedText(context, zh: '缓存读取', en: 'Cache Read'),
        value: _usageCompactNumber(summary.cacheReadTokens),
        detail: openHandLocalizedText(
          context,
          zh: '命中率 ${_usagePercent(summary.cacheHitRate)}',
          en: '${_usagePercent(summary.cacheHitRate)} hit rate',
        ),
        icon: Icons.bolt_outlined,
        color: OpenHandStatusColors.success,
        progress: summary.cacheHitRate,
      ),
      _AiUsageMetricData(
        label: openHandLocalizedText(context, zh: '缓存创建', en: 'Cache Write'),
        value: _usageCompactNumber(summary.cacheCreationTokens),
        detail: openHandLocalizedText(
          context,
          zh: '可供后续请求复用',
          en: 'Reusable by later requests',
        ),
        icon: Icons.storage_rounded,
        color: colorScheme.secondary,
      ),
      _AiUsageMetricData(
        label: openHandLocalizedText(context, zh: '推理 Token', en: 'Reasoning'),
        value: _usageCompactNumber(summary.reasoningTokens),
        detail: openHandLocalizedText(
          context,
          zh: '包含在模型输出中',
          en: 'Included in model output',
        ),
        icon: Icons.psychology_alt_outlined,
        color: colorScheme.error,
      ),
      _AiUsageMetricData(
        label: openHandLocalizedText(context, zh: '平均响应', en: 'Avg. Response'),
        value: _usageDuration(summary.averageDurationMs),
        detail: summary.firstTokenSampleCount == 0
            ? openHandLocalizedText(
                context,
                zh: '暂无首字延迟样本',
                en: 'No first-token samples',
              )
            : openHandLocalizedText(
                context,
                zh: '首字 ${_usageDuration(summary.averageFirstTokenMs)}',
                en: 'First token ${_usageDuration(summary.averageFirstTokenMs)}',
              ),
        icon: Icons.speed_rounded,
        color: colorScheme.primary,
      ),
    ];
    final multimodalTokens =
        summary.audioInputTokens +
        summary.imageInputTokens +
        summary.videoInputTokens;
    if (multimodalTokens > 0) {
      metrics.add(
        _AiUsageMetricData(
          label: openHandLocalizedText(
            context,
            zh: '多模态输入',
            en: 'Multimodal Input',
          ),
          value: _usageCompactNumber(multimodalTokens),
          detail:
              'Audio ${_usageCompactNumber(summary.audioInputTokens)} · '
              'Image ${_usageCompactNumber(summary.imageInputTokens)} · '
              'Video ${_usageCompactNumber(summary.videoInputTokens)}',
          icon: Icons.perm_media_outlined,
          color: colorScheme.secondary,
        ),
      );
    }
    if (summary.failureCount > 0) {
      metrics.add(
        _AiUsageMetricData(
          label: openHandLocalizedText(
            context,
            zh: '未成功请求',
            en: 'Unsuccessful Requests',
          ),
          value: _usageInteger(summary.failureCount),
          detail: openHandLocalizedText(
            context,
            zh: '失败 ${summary.failedCount} · 超时 ${summary.timeoutCount} · 异常 ${summary.errorCount} · 取消 ${summary.cancelledCount}',
            en: '${summary.failedCount} failed · ${summary.timeoutCount} timed out · ${summary.errorCount} errors · ${summary.cancelledCount} cancelled',
          ),
          icon: Icons.monitor_heart_outlined,
          color: OpenHandStatusColors.error,
        ),
      );
    }
    metrics.add(
      _AiUsageMetricData(
        label: openHandLocalizedText(context, zh: '数据覆盖', en: 'Data Coverage'),
        value:
            '${summary.requestCount - summary.estimatedCount}/${summary.requestCount}',
        detail: openHandLocalizedText(
          context,
          zh: '真实 Token · ${summary.pricedRequestCount} 次具备价格',
          en: 'Exact token records · ${summary.pricedRequestCount} priced',
        ),
        icon: Icons.fact_check_outlined,
        color: OpenHandStatusColors.info,
        progress: summary.requestCount == 0
            ? 0
            : (summary.requestCount - summary.estimatedCount) /
                  summary.requestCount,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= _kAiUsageMetricThreeColumnMinWidth
            ? 3
            : constraints.maxWidth >= _kAiUsageMetricTwoColumnMinWidth
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final metric in metrics)
              SettingsAwareAppearOnce(
                key: ValueKey<String>('usage-metric-${metric.label}'),
                child: SizedBox(
                  width: width,
                  height: _kAiUsageMetricHeight,
                  child: _AiUsageMetricCard(data: metric),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AiUsageMetricData {
  const _AiUsageMetricData({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    this.progress,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  final double? progress;
}

class _AiUsageMetricCard extends StatelessWidget {
  const _AiUsageMetricCard({required this.data});

  final _AiUsageMetricData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: kOpenHandBorderRadius18,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(kOpenHandRadius11),
                ),
                child: Icon(data.icon, size: 19, color: data.color),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Text(
                  data.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          Text(
            data.value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          kOpenHandGap5,
          Text(
            data.detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (data.progress case final progress?) ...[
            kOpenHandGap11,
            ClipRRect(
              borderRadius: kOpenHandPillBorderRadius,
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 5,
                color: data.color,
                backgroundColor: data.color.withValues(alpha: 0.12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AiUsageHealthPanel extends StatelessWidget {
  const _AiUsageHealthPanel({required this.snapshot});

  final AiUsageSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _AiUsagePanel(
      title: openHandLocalizedText(
        context,
        zh: '实时健康概览',
        en: 'Live Health Overview',
      ),
      subtitle: openHandLocalizedText(
        context,
        zh: '供应商与网络代理的请求质量、成功率和异常占比',
        en: 'Request quality, success rate and error mix by provider and route',
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cards = <Widget>[
            _AiUsageHealthCard(
              title: _settingsAiUsagProviderLabel(context),
              icon: Icons.cloud_outlined,
              color: colors.primary,
              items: snapshot.healthProviders.isEmpty
                  ? snapshot.providers
                  : snapshot.healthProviders,
              emptyMessage: openHandLocalizedText(
                context,
                zh: '当前范围暂无供应商记录',
                en: 'No provider records in this range',
              ),
            ),
            _AiUsageHealthCard(
              title: openHandLocalizedText(
                context,
                zh: '网络代理',
                en: 'Network Proxy',
              ),
              icon: Icons.lan_outlined,
              color: colors.tertiary,
              items: snapshot.proxyRoutes,
              emptyMessage: openHandLocalizedText(
                context,
                zh: '当前范围暂无中转站代理记录',
                en: 'No proxy route records in this range',
              ),
              labelBuilder: (item) => aiModelProxyDispatchModeLabel(
                item.key,
                openHandTextResolver(context),
              ),
            ),
          ];
          if (constraints.maxWidth >= _kAiUsageDistributionTwoColumnMinWidth) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cards[0]),
                kOpenHandHGap12,
                Expanded(child: cards[1]),
              ],
            );
          }
          return Column(children: [cards[0], kOpenHandGap12, cards[1]]);
        },
      ),
    );
  }
}

class _AiUsageHealthCard extends StatelessWidget {
  const _AiUsageHealthCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
    required this.emptyMessage,
    this.labelBuilder,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<AiUsageBreakdown> items;
  final String emptyMessage;
  final String Function(AiUsageBreakdown item)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: kOpenHandBorderRadius18,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                kOpenHandHGap8,
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                if (items.isNotEmpty)
                  Text(
                    '${items.fold<int>(0, (sum, item) => sum + item.requestCount)} ${openHandLocalizedText(context, zh: '次', en: 'req')}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            kOpenHandGap12,
            if (items.isEmpty)
              Text(
                emptyMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else
              for (final item in items.take(6)) ...[
                _AiUsageHealthRow(
                  label: labelBuilder?.call(item) ?? item.label,
                  item: item,
                  color: color,
                ),
                if (item != items.take(6).last) kOpenHandGap10,
              ],
          ],
        ),
      ),
    );
  }
}

class _AiUsageHealthRow extends StatelessWidget {
  const _AiUsageHealthRow({
    required this.label,
    required this.item,
    required this.color,
  });

  final String label;
  final AiUsageBreakdown item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final success = item.successRate;
    final timeout = item.requestCount == 0
        ? 0.0
        : item.timeoutCount / item.requestCount;
    final failed = item.requestCount == 0
        ? 0.0
        : math.max(0, item.failureCount - item.timeoutCount) /
              item.requestCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
            Text(
              '${(success * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            kOpenHandHGap8,
            Text(
              '${item.requestCount}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        kOpenHandGap5,
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              Expanded(
                flex: math.max(1, (success * 1000).round()),
                child: ColoredBox(
                  color: color,
                  child: const SizedBox(height: 6),
                ),
              ),
              if (failed > 0)
                Expanded(
                  flex: math.max(1, (failed * 1000).round()),
                  child: ColoredBox(
                    color: colors.error.withValues(alpha: 0.78),
                    child: const SizedBox(height: 6),
                  ),
                ),
              if (timeout > 0)
                Expanded(
                  flex: math.max(1, (timeout * 1000).round()),
                  child: ColoredBox(
                    color: colors.tertiary.withValues(alpha: 0.8),
                    child: const SizedBox(height: 6),
                  ),
                ),
            ],
          ),
        ),
        kOpenHandGap4,
        Text(
          openHandLocalizedText(
            context,
            zh: '成功 ${(success * 100).toStringAsFixed(0)}% · 失败 ${(failed * 100).toStringAsFixed(0)}% · 超时 ${(timeout * 100).toStringAsFixed(0)}%',
            en: 'Success ${(success * 100).toStringAsFixed(0)}% · Failed ${(failed * 100).toStringAsFixed(0)}% · Timeout ${(timeout * 100).toStringAsFixed(0)}%',
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AiUsageOverviewPanel extends StatelessWidget {
  const _AiUsageOverviewPanel({required this.snapshot});

  final AiUsageSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final summary = snapshot.summary;
    final pricingCoverage = summary.requestCount == 0
        ? 0.0
        : summary.pricedRequestCount / summary.requestCount;
    final metrics = <_AiUsageOverviewMetricData>[
      _AiUsageOverviewMetricData(
        label: openHandLocalizedText(context, zh: '请求花费', en: 'Request Cost'),
        value: summary.pricedRequestCount == 0
            ? '—'
            : summary.hasCompletePricing
            ? _usageMoney(summary.totalCostUsd)
            : '≥${_usageMoney(summary.totalCostUsd)}',
        detail: openHandLocalizedText(
          context,
          zh: '${summary.pricedRequestCount}/${summary.requestCount} 次请求具备价格',
          en: '${summary.pricedRequestCount}/${summary.requestCount} requests priced',
        ),
        values: [for (final bucket in snapshot.trend) bucket.totalCostUsd],
        color: OpenHandStatusColors.success,
      ),
      _AiUsageOverviewMetricData(
        label: openHandLocalizedText(
          context,
          zh: '计费覆盖',
          en: 'Pricing Coverage',
        ),
        value: _usagePercent(pricingCoverage),
        detail: openHandLocalizedText(
          context,
          zh: '${summary.requestCount - summary.pricedRequestCount} 次请求暂无价格',
          en: '${summary.requestCount - summary.pricedRequestCount} requests unpriced',
        ),
        values: [
          for (final bucket in snapshot.trend)
            bucket.requestCount == 0
                ? 0
                : bucket.pricedRequestCount / bucket.requestCount,
        ],
        color: colorScheme.secondary,
      ),
      _AiUsageOverviewMetricData(
        label: openHandRequestsLabel(context),
        value: _usageCompactNumber(summary.requestCount),
        detail: openHandLocalizedText(
          context,
          zh: '${summary.successCount} 次成功 · ${summary.failureCount} 次未成功',
          en: '${summary.successCount} succeeded · ${summary.failureCount} unsuccessful',
        ),
        values: [
          for (final bucket in snapshot.trend) bucket.requestCount.toDouble(),
        ],
        color: colorScheme.primary,
      ),
      _AiUsageOverviewMetricData(
        label: 'Tokens',
        value: _usageCompactNumber(summary.totalTokens, decimals: 2),
        detail: openHandLocalizedText(
          context,
          zh: '含推理 ${_usageCompactNumber(summary.reasoningTokens)} Token',
          en: 'Includes ${_usageCompactNumber(summary.reasoningTokens)} reasoning tokens',
        ),
        values: [
          for (final bucket in snapshot.trend) bucket.totalTokens.toDouble(),
        ],
        color: colorScheme.tertiary,
      ),
    ];
    final modelMaxTokens = snapshot.models.fold<int>(
      1,
      (value, item) => math.max(value, item.totalTokens),
    );
    final pricedProviders =
        snapshot.providers.where((item) => item.pricedRequestCount > 0).toList()
          ..sort(
            (left, right) => right.totalCostUsd.compareTo(left.totalCostUsd),
          );
    final providerMaxCost = pricedProviders.fold<double>(
      0,
      (value, item) => math.max(value, item.totalCostUsd),
    );
    final modelDistribution = _AiUsageDistributionCard(
      title: openHandLocalizedText(
        context,
        zh: '模型使用分布',
        en: 'Model Usage Distribution',
      ),
      items: snapshot.models,
      color: colorScheme.primary,
      emptyMessage: openHandLocalizedText(
        context,
        zh: '当前范围暂无模型用量',
        en: 'No model usage in this range',
      ),
      leadingValue: (item) => openHandLocalizedText(
        context,
        zh: '${_usageCompactNumber(item.requestCount)} 次',
        en: '${_usageCompactNumber(item.requestCount)} requests',
      ),
      trailingValue: (item) => '${_usageCompactNumber(item.totalTokens)} Token',
      progressValue: (item) => item.totalTokens / modelMaxTokens,
    );
    final providerDistribution = _AiUsageDistributionCard(
      title: openHandLocalizedText(
        context,
        zh: '供应商计费分布',
        en: 'Provider Cost Distribution',
      ),
      items: pricedProviders,
      color: colorScheme.tertiary,
      emptyMessage: openHandLocalizedText(
        context,
        zh: '当前范围暂无计价数据',
        en: 'No priced usage in this range',
      ),
      leadingValue: (item) => openHandLocalizedText(
        context,
        zh: '${item.pricedRequestCount} 次计费',
        en: '${item.pricedRequestCount} priced',
      ),
      trailingValue: (item) =>
          '${_usageMoney(item.totalCostUsd)} · '
          '${_usagePercent(summary.totalCostUsd <= 0 ? 0 : item.totalCostUsd / summary.totalCostUsd)}',
      progressValue: (item) =>
          providerMaxCost <= 0 ? 0 : item.totalCostUsd / providerMaxCost,
    );
    return _AiUsagePanel(
      title: openHandLocalizedText(
        context,
        zh: '费用与用量概览',
        en: 'Cost & Usage Overview',
      ),
      subtitle: openHandLocalizedText(
        context,
        zh: '请求费用、计费覆盖、请求与 Token 趋势，以及模型和供应商分布',
        en: 'Request cost, pricing coverage, request and token trends, plus model and provider distribution',
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  constraints.maxWidth >= _kAiUsageOverviewFourColumnMinWidth
                  ? 4
                  : constraints.maxWidth >= _kAiUsageOverviewTwoColumnMinWidth
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final metric in metrics)
                    SettingsAwareAppearOnce(
                      key: ValueKey<String>('usage-overview-${metric.label}'),
                      child: SizedBox(
                        width: width,
                        height: _kAiUsageOverviewMetricHeight,
                        child: _AiUsageOverviewMetricCard(data: metric),
                      ),
                    ),
                ],
              );
            },
          ),
          kOpenHandGap12,
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >=
                  _kAiUsageDistributionTwoColumnMinWidth) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: modelDistribution),
                    kOpenHandHGap12,
                    Expanded(child: providerDistribution),
                  ],
                );
              }
              return Column(
                children: [
                  modelDistribution,
                  kOpenHandGap12,
                  providerDistribution,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AiUsageOverviewMetricData {
  const _AiUsageOverviewMetricData({
    required this.label,
    required this.value,
    required this.detail,
    required this.values,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final List<double> values;
  final Color color;
}

class _AiUsageOverviewMetricCard extends StatelessWidget {
  const _AiUsageOverviewMetricCard({required this.data});

  final _AiUsageOverviewMetricData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueColor = Color.alphaBlend(
      data.color.withValues(alpha: 0.34),
      theme.colorScheme.onSurface,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: kOpenHandBorderRadius18,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                kOpenHandHGap10,
                Expanded(
                  flex: 6,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: data.color.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(kOpenHandRadius11),
                        border: Border.all(
                          color: data.color.withValues(alpha: 0.18),
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          data.value,
                          maxLines: 1,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: valueColor,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            letterSpacing: -0.7,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            kOpenHandGap4,
            Text(
              data.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _AiUsageSparklinePainter(
                    values: data.values,
                    color: data.color,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiUsageSparklinePainter extends CustomPainter {
  const _AiUsageSparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.isEmpty) return;
    const inset = 3.0;
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final span = maxValue - minValue;
    final step = values.length <= 1 ? 0.0 : size.width / (values.length - 1);
    final points = <Offset>[
      for (var index = 0; index < values.length; index++)
        Offset(
          values.length == 1 ? size.width / 2 : index * step,
          span == 0
              ? maxValue == 0
                    ? size.height - inset
                    : size.height / 2
              : inset +
                    (size.height - inset * 2) *
                        (1 - (values[index] - minValue) / span),
        ),
    ];
    if (points.length == 1) {
      points
        ..insert(0, Offset(0, points.first.dy))
        ..add(Offset(size.width, points.last.dy));
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < points.length - 1; index++) {
      final before = index == 0 ? points[index] : points[index - 1];
      final current = points[index];
      final next = points[index + 1];
      final after = index + 2 < points.length ? points[index + 2] : next;
      final control1Y = (current.dy + (next.dy - before.dy) / 6).clamp(
        inset,
        size.height - inset,
      );
      final control2Y = (next.dy - (after.dy - current.dy) / 6).clamp(
        inset,
        size.height - inset,
      );
      path.cubicTo(
        current.dx + (next.dx - before.dx) / 6,
        control1Y,
        next.dx - (after.dx - current.dx) / 6,
        control2Y,
        next.dx,
        next.dy,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(points.last, 3.1, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AiUsageSparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

class _AiUsageDistributionCard extends StatefulWidget {
  const _AiUsageDistributionCard({
    required this.title,
    required this.items,
    required this.color,
    required this.emptyMessage,
    required this.leadingValue,
    required this.trailingValue,
    required this.progressValue,
  });

  final String title;
  final List<AiUsageBreakdown> items;
  final Color color;
  final String emptyMessage;
  final String Function(AiUsageBreakdown item) leadingValue;
  final String Function(AiUsageBreakdown item) trailingValue;
  final double Function(AiUsageBreakdown item) progressValue;

  @override
  State<_AiUsageDistributionCard> createState() =>
      _AiUsageDistributionCardState();
}

class _AiUsageDistributionCardState extends State<_AiUsageDistributionCard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSize(
      alignment: Alignment.topCenter,
      duration: openHandMotionDuration(context, kOpenHandMotion280),
      curve: kOpenHandSwitchInCurve,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: kOpenHandBorderRadius18,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (widget.items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.09),
                        borderRadius: kOpenHandPillBorderRadius,
                        border: Border.all(
                          color: widget.color.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        openHandLocalizedText(
                          context,
                          zh: '${widget.items.length} 项',
                          en: '${widget.items.length} ${widget.items.length == 1 ? 'item' : 'items'}',
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Color.alphaBlend(
                            widget.color.withValues(alpha: 0.34),
                            theme.colorScheme.onSurface,
                          ),
                          fontWeight: FontWeight.w700,
                          height: 1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
              kOpenHandGap14,
              if (widget.items.isEmpty)
                SizedBox(
                  height: _kAiUsageDistributionEmptyBodyHeight,
                  child: OpenHandInlineEmptyState(message: widget.emptyMessage),
                )
              else
                OpenHandClientPager<AiUsageBreakdown>(
                  items: widget.items,
                  builder: (context, pageItems) {
                    final bodyHeight = math.min(
                      math.max(pageItems.length, 1) *
                          _kAiUsageDistributionRowHeight,
                      _kAiUsageDistributionBodyMaxHeight,
                    );
                    return SizedBox(
                      height: bodyHeight,
                      child: OpenHandSafeScrollbar(
                        controller: _scrollController,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.zero,
                          itemCount: pageItems.length,
                          itemExtent: _kAiUsageDistributionRowHeight,
                          itemBuilder: (context, index) {
                            final item = pageItems[index];
                            return SettingsAwareAppearOnce(
                              key: ValueKey<String>(
                                'usage-distribution-${item.key}',
                              ),
                              child: _buildItem(context, item),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, AiUsageBreakdown item) {
    final theme = Theme.of(context);
    final secondaryStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        SizedBox(
          width: 126,
          child: Tooltip(
            message: item.label,
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        kOpenHandHGap12,
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.leadingValue(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: secondaryStyle,
                    ),
                  ),
                  kOpenHandHGap8,
                  Flexible(
                    child: Text(
                      widget.trailingValue(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: secondaryStyle,
                    ),
                  ),
                ],
              ),
              kOpenHandGap5,
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: widget.progressValue(item).clamp(0, 1),
                ),
                duration: openHandMotionDuration(context, kOpenHandMotion420),
                curve: kOpenHandSwitchInCurve,
                builder: (context, progress, _) => ClipRRect(
                  borderRadius: kOpenHandPillBorderRadius,
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: widget.color.withValues(alpha: 0.1)),
                        FractionallySizedBox(
                          widthFactor: progress,
                          alignment: Alignment.centerLeft,
                          child: ColoredBox(color: widget.color),
                        ),
                      ],
                    ),
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

class _AiUsagePanel extends StatelessWidget {
  const _AiUsagePanel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    kOpenHandGap4,
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                kOpenHandHGap12,
                DefaultTextStyle(
                  style: theme.textTheme.labelLarge!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  child: trailing!,
                ),
              ],
            ],
          ),
          kOpenHandGap20,
          child,
        ],
      ),
    );
  }
}

enum _AiUsageTrendMode { usage, status }

class _AiUsageTrendChart extends StatefulWidget {
  const _AiUsageTrendChart({
    required this.buckets,
    this.mode = _AiUsageTrendMode.usage,
  });

  final List<AiUsageBucket> buckets;
  final _AiUsageTrendMode mode;

  @override
  State<_AiUsageTrendChart> createState() => _AiUsageTrendChartState();
}

class _AiUsageTrendChartState extends State<_AiUsageTrendChart> {
  int? _selectedIndex;
  int? _tooltipIndex;
  bool _tooltipVisible = false;
  double _visibleFraction = 1;
  double _gestureStartFraction = 1;

  @override
  void didUpdateWidget(covariant _AiUsageTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buckets == widget.buckets && oldWidget.mode == widget.mode) {
      return;
    }
    _selectedIndex = null;
    _tooltipIndex = null;
    _tooltipVisible = false;
    if (oldWidget.buckets != widget.buckets) {
      _visibleFraction = 1;
      _gestureStartFraction = 1;
    }
  }

  List<AiUsageBucket> get _displayBuckets {
    final buckets = widget.buckets;
    if (buckets.length < 3 || _visibleFraction >= 0.999) return buckets;
    final count = math.max(2, (buckets.length * _visibleFraction).round());
    return buckets.sublist(math.max(0, buckets.length - count));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets = _displayBuckets;
    if (buckets.isEmpty) {
      return SizedBox(
        height: 180,
        child: OpenHandInlineEmptyState(
          message: openHandLocalizedText(
            context,
            zh: '当前范围暂无趋势数据',
            en: 'No trend data in this range',
          ),
        ),
      );
    }
    return Column(
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 7,
          children: [
            if (widget.mode == _AiUsageTrendMode.usage) ...[
              _AiUsageLegendDot(
                color: theme.colorScheme.primary,
                label: _settingsAiUsagInputLabel(context),
              ),
              _AiUsageLegendDot(
                color: theme.colorScheme.tertiary,
                label: openHandOutputLabel(context),
              ),
              _AiUsageLegendDot(
                color: OpenHandStatusColors.success,
                label: openHandLocalizedText(
                  context,
                  zh: '缓存命中',
                  en: 'Cache Read',
                ),
              ),
            ] else ...[
              _AiUsageLegendDot(
                color: OpenHandStatusColors.success,
                label: openHandLocalizedText(context, zh: '成功数', en: 'Success'),
              ),
              _AiUsageLegendDot(
                color: theme.colorScheme.error,
                label: openHandLocalizedText(context, zh: '失败数', en: 'Failed'),
              ),
              _AiUsageLegendDot(
                color: theme.colorScheme.tertiary,
                label: openHandLocalizedText(context, zh: '超时数', en: 'Timeout'),
              ),
              _AiUsageLegendDot(
                color: theme.colorScheme.onSurface,
                label: openHandLocalizedText(
                  context,
                  zh: '请求总数',
                  en: 'Requests',
                ),
              ),
            ],
          ],
        ),
        kOpenHandGap14,
        LayoutBuilder(
          builder: (context, constraints) {
            const height = 220.0;
            final width = constraints.maxWidth;
            return MouseRegion(
              onExit: (_) => _hideTooltip(),
              onHover: (event) => _selectBucket(event.localPosition.dx, width),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    _selectBucket(details.localPosition.dx, width),
                onScaleStart: (_) => _gestureStartFraction = _visibleFraction,
                onScaleUpdate: (details) {
                  if (details.scale == 1) return;
                  final next = (_gestureStartFraction / details.scale).clamp(
                    0.2,
                    1.0,
                  );
                  if ((next - _visibleFraction).abs() < 0.01) return;
                  setState(() {
                    _visibleFraction = next;
                    _selectedIndex = null;
                    _tooltipIndex = null;
                    _tooltipVisible = false;
                  });
                },
                child: SizedBox(
                  height: height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _AiUsageTrendPainter(
                              buckets: buckets,
                              colorScheme: theme.colorScheme,
                              selectedIndex: _selectedIndex,
                              mode: widget.mode,
                            ),
                          ),
                        ),
                      ),
                      if (_tooltipIndex case final index?)
                        _buildTooltip(context, index, width),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _selectBucket(double dx, double width) {
    final buckets = _displayBuckets;
    if (buckets.isEmpty || width <= 0) return;
    final index = buckets.length == 1
        ? 0
        : (dx / width * (buckets.length - 1)).round().clamp(
            0,
            buckets.length - 1,
          );
    if (_selectedIndex == index && _tooltipVisible) return;
    setState(() {
      _selectedIndex = index;
      _tooltipIndex = index;
      _tooltipVisible = true;
    });
  }

  void _hideTooltip() {
    if (!_tooltipVisible && _selectedIndex == null) return;
    setState(() {
      _selectedIndex = null;
      _tooltipVisible = false;
    });
  }

  Widget _buildTooltip(BuildContext context, int index, double width) {
    final theme = Theme.of(context);
    final buckets = _displayBuckets;
    final bucket = buckets[index];
    final tooltipWidth = math.min(width, 210.0);
    final center = buckets.length == 1
        ? width / 2
        : index * width / (buckets.length - 1);
    final left = (center - tooltipWidth / 2).clamp(0.0, width - tooltipWidth);
    final duration = openHandMotionDuration(context, kOpenHandMotion220);
    return AnimatedPositioned(
      left: left,
      top: 8,
      width: tooltipWidth,
      duration: openHandMotionDuration(context, kOpenHandMotion170),
      curve: kOpenHandSwitchInCurve,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _tooltipVisible ? 1 : 0,
          duration: duration,
          curve: _tooltipVisible
              ? kOpenHandSwitchInCurve
              : kOpenHandSwitchOutCurve,
          child: AnimatedSlide(
            offset: _tooltipVisible ? Offset.zero : const Offset(0, 0.08),
            duration: duration,
            curve: _tooltipVisible
                ? kOpenHandEntranceCurve
                : kOpenHandSwitchOutCurve,
            child: AnimatedScale(
              scale: _tooltipVisible ? 1 : 0.9,
              duration: duration,
              curve: _tooltipVisible
                  ? kOpenHandEntranceCurve
                  : kOpenHandSwitchOutCurve,
              alignment: Alignment.topCenter,
              child: Material(
                elevation: 8,
                color: theme.colorScheme.inverseSurface,
                borderRadius: kOpenHandBorderRadius14,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DefaultTextStyle(
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: theme.colorScheme.onInverseSurface,
                      height: 1.5,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _usageBucketLabel(bucket.key),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onInverseSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        kOpenHandGap5,
                        if (widget.mode == _AiUsageTrendMode.usage) ...[
                          Text('Token  ${_usageInteger(bucket.totalTokens)}'),
                          Text(
                            '${_settingsAiUsagInputLabel(context)}  ${_usageInteger(bucket.promptTokens)}  ·  '
                            '${openHandOutputLabel(context)}  ${_usageInteger(bucket.completionTokens)}',
                          ),
                          Text(
                            '${_settingsAiUsagCostLabel(context)}  ${bucket.pricedRequestCount == 0
                                ? '—'
                                : bucket.pricedRequestCount < bucket.requestCount
                                ? '≥${_usageMoney(bucket.totalCostUsd)}'
                                : _usageMoney(bucket.totalCostUsd)}',
                          ),
                        ] else ...[
                          Text(
                            '${openHandLocalizedText(context, zh: '成功', en: 'Success')}  ${bucket.successCount}  ·  '
                            '${openHandLocalizedText(context, zh: '失败', en: 'Failed')}  ${bucket.failedCount}  ·  '
                            '${openHandLocalizedText(context, zh: '超时', en: 'Timeout')}  ${bucket.timeoutCount}  ·  '
                            '${openHandLocalizedText(context, zh: '总请求', en: 'Requests')}  ${bucket.requestCount}',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiUsageTrendPainter extends CustomPainter {
  const _AiUsageTrendPainter({
    required this.buckets,
    required this.colorScheme,
    required this.selectedIndex,
    required this.mode,
  });

  final List<AiUsageBucket> buckets;
  final ColorScheme colorScheme;
  final int? selectedIndex;
  final _AiUsageTrendMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 12.0;
    const bottom = 28.0;
    final chartHeight = size.height - top - bottom;
    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = top + chartHeight * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final maxTokens = buckets.fold<int>(
      1,
      (maxValue, bucket) => math.max(
        maxValue,
        math.max(
          bucket.promptTokens,
          math.max(bucket.completionTokens, bucket.cacheReadTokens),
        ),
      ),
    );
    final maxStatus = buckets.fold<int>(
      1,
      (maxValue, bucket) => math.max(
        maxValue,
        math.max(
          bucket.requestCount,
          math.max(
            bucket.successCount,
            math.max(bucket.failedCount, bucket.timeoutCount),
          ),
        ),
      ),
    );
    final step = buckets.length <= 1 ? 0.0 : size.width / (buckets.length - 1);
    List<Offset> pointsFor(int Function(AiUsageBucket) valueOf) {
      if (buckets.length == 1) {
        final value = valueOf(buckets.first);
        final y = top + chartHeight * (1 - value / maxTokens);
        return <Offset>[Offset(0, y), Offset(size.width, y)];
      }
      return <Offset>[
        for (var index = 0; index < buckets.length; index++)
          Offset(
            index * step,
            top + chartHeight * (1 - valueOf(buckets[index]) / maxTokens),
          ),
      ];
    }

    Path smoothPath(List<Offset> points) {
      final path = Path();
      if (points.isEmpty) return path;
      path.moveTo(points.first.dx, points.first.dy);
      for (var index = 0; index < points.length - 1; index++) {
        final before = index == 0 ? points[index] : points[index - 1];
        final current = points[index];
        final next = points[index + 1];
        final after = index + 2 < points.length ? points[index + 2] : next;
        final control1 = Offset(
          current.dx + (next.dx - before.dx) / 6,
          (current.dy + (next.dy - before.dy) / 6).clamp(
            top,
            top + chartHeight,
          ),
        );
        final control2 = Offset(
          next.dx - (after.dx - current.dx) / 6,
          (next.dy - (after.dy - current.dy) / 6).clamp(top, top + chartHeight),
        );
        path.cubicTo(
          control1.dx,
          control1.dy,
          control2.dx,
          control2.dy,
          next.dx,
          next.dy,
        );
      }
      return path;
    }

    final inputPoints = pointsFor((bucket) => bucket.promptTokens);
    final outputPoints = pointsFor((bucket) => bucket.completionTokens);
    final cachePoints = pointsFor((bucket) => bucket.cacheReadTokens);
    List<Offset> statusPoints(int Function(AiUsageBucket) valueOf) {
      if (buckets.length == 1) {
        final value = valueOf(buckets.first);
        final y = top + chartHeight * (1 - value / maxStatus);
        return <Offset>[Offset(0, y), Offset(size.width, y)];
      }
      return <Offset>[
        for (var index = 0; index < buckets.length; index++)
          Offset(
            index * step,
            top + chartHeight * (1 - valueOf(buckets[index]) / maxStatus),
          ),
      ];
    }

    final inputPath = smoothPath(inputPoints);
    final statusSuccessPoints = statusPoints((bucket) => bucket.successCount);
    final statusFailedPoints = statusPoints((bucket) => bucket.failedCount);
    final statusTimeoutPoints = statusPoints((bucket) => bucket.timeoutCount);
    final statusRequestPoints = statusPoints((bucket) => bucket.requestCount);
    final statusRequestPath = smoothPath(statusRequestPoints);
    final areaPath =
        Path.from(
            mode == _AiUsageTrendMode.usage ? inputPath : statusRequestPath,
          )
          ..lineTo(size.width, top + chartHeight)
          ..lineTo(0, top + chartHeight)
          ..close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..color =
            (mode == _AiUsageTrendMode.usage
                    ? colorScheme.primary
                    : colorScheme.onSurface)
                .withValues(alpha: 0.08),
    );
    void drawSeries(Path path, Color color, double width) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = width,
      );
    }

    if (mode == _AiUsageTrendMode.usage) {
      drawSeries(inputPath, colorScheme.primary, 2.6);
      drawSeries(smoothPath(outputPoints), colorScheme.tertiary, 2.2);
      drawSeries(smoothPath(cachePoints), OpenHandStatusColors.success, 2.2);
    } else {
      drawSeries(
        smoothPath(statusSuccessPoints),
        OpenHandStatusColors.success,
        2.4,
      );
      drawSeries(smoothPath(statusFailedPoints), colorScheme.error, 2.2);
      drawSeries(smoothPath(statusTimeoutPoints), colorScheme.tertiary, 2.2);
      drawSeries(smoothPath(statusRequestPoints), colorScheme.onSurface, 2.8);
    }
    final selected = selectedIndex;
    if (selected != null) {
      final x = buckets.length <= 1 ? size.width / 2 : selected * step;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + chartHeight),
        Paint()
          ..color = colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
      void drawPoint(List<Offset> points, Color color) {
        final point = buckets.length == 1
            ? Offset(size.width / 2, points.first.dy)
            : points[selected];
        canvas.drawCircle(
          point,
          5,
          Paint()..color = colorScheme.surfaceContainerLow,
        );
        canvas.drawCircle(point, 3.2, Paint()..color = color);
      }

      if (mode == _AiUsageTrendMode.usage) {
        drawPoint(inputPoints, colorScheme.primary);
        drawPoint(outputPoints, colorScheme.tertiary);
        drawPoint(cachePoints, OpenHandStatusColors.success);
      } else {
        drawPoint(statusSuccessPoints, OpenHandStatusColors.success);
        drawPoint(statusFailedPoints, colorScheme.error);
        drawPoint(statusTimeoutPoints, colorScheme.tertiary);
        drawPoint(statusRequestPoints, colorScheme.onSurface);
      }
    }
    final labelStyle = TextStyle(
      color: colorScheme.onSurfaceVariant,
      fontSize: 11,
    );
    _paintText(
      canvas,
      _usageBucketLabel(buckets.first.key),
      Offset(0, size.height - 17),
      labelStyle,
    );
    final lastLabel = _usageBucketLabel(buckets.last.key);
    final lastPainter = TextPainter(
      text: TextSpan(text: lastLabel, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    lastPainter.paint(
      canvas,
      Offset(size.width - lastPainter.width, size.height - 17),
    );
  }

  void _paintText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _AiUsageTrendPainter oldDelegate) {
    return oldDelegate.buckets != buckets ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.mode != mode;
  }
}

class _AiUsageLegendDot extends StatelessWidget {
  const _AiUsageLegendDot({required this.color, required this.label});

  final Color color;
  final String label;

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
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AiUsageHeatmap extends StatelessWidget {
  const _AiUsageHeatmap({required this.buckets});

  final List<AiUsageBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDate = <String, AiUsageBucket>{
      for (final bucket in buckets) bucket.key: bucket,
    };
    final today = DateTime.now();
    final localToday = DateTime(today.year, today.month, today.day);
    final currentWeekSunday = localToday.subtract(
      Duration(days: localToday.weekday % 7),
    );
    final start = currentWeekSunday.subtract(const Duration(days: 52 * 7));
    final maxTokens = buckets.fold<int>(
      0,
      (value, bucket) => math.max(value, bucket.totalTokens),
    );
    final activeDays = buckets.where((bucket) => bucket.totalTokens > 0).length;
    final annualTokens = buckets.fold<int>(
      0,
      (sum, bucket) => sum + bucket.totalTokens,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            Text(
              openHandLocalizedText(
                context,
                zh: '过去一年 ${_usageCompactNumber(annualTokens)} Token',
                en: '${_usageCompactNumber(annualTokens)} tokens in the last year',
              ),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              openHandLocalizedText(
                context,
                zh: '$activeDays 个活跃日',
                en: '$activeDays active days',
              ),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        kOpenHandGap14,
        LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = math.max(
              constraints.maxWidth,
              _kAiUsageHeatmapMinWidth,
            );
            // 走安全包装：横向滚动视图默认不接管 PrimaryScrollController，
            // 裸 Scrollbar 在拿不到 ScrollPosition 时会直接抛 FlutterError。
            return OpenHandSafeScrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 14),
                child: SizedBox(
                  width: contentWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 21, right: 8),
                        child: Column(
                          children: [
                            for (var day = 0; day < 7; day++)
                              SizedBox(
                                height: 15,
                                child: Text(
                                  switch (day) {
                                    1 => openHandLocalizedText(
                                      context,
                                      zh: '一',
                                      en: 'Mon',
                                    ),
                                    3 => openHandLocalizedText(
                                      context,
                                      zh: '三',
                                      en: 'Wed',
                                    ),
                                    5 => openHandLocalizedText(
                                      context,
                                      zh: '五',
                                      en: 'Fri',
                                    ),
                                    _ => '',
                                  },
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 9,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var week = 0; week < 53; week++)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    height: 20,
                                    width: 12,
                                    child:
                                        week == 0 ||
                                            start
                                                    .add(
                                                      Duration(days: week * 7),
                                                    )
                                                    .month !=
                                                start
                                                    .add(
                                                      Duration(
                                                        days: (week - 1) * 7,
                                                      ),
                                                    )
                                                    .month
                                        ? OverflowBox(
                                            maxWidth: 44,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              _usageMonthLabel(
                                                context,
                                                start.add(
                                                  Duration(days: week * 7),
                                                ),
                                              ),
                                              softWrap: false,
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          )
                                        : null,
                                  ),
                                  for (var day = 0; day < 7; day++)
                                    _AiUsageHeatmapCell(
                                      date: start.add(
                                        Duration(days: week * 7 + day),
                                      ),
                                      today: localToday,
                                      bucket:
                                          byDate[formatYearMonthDay(
                                            start.add(
                                              Duration(days: week * 7 + day),
                                            ),
                                          )],
                                      maxTokens: maxTokens,
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        kOpenHandGap8,
        Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                openHandLocalizedText(context, zh: '少', en: 'Less'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              kOpenHandHGap6,
              for (var level = 0; level < 5; level++) ...[
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: _usageHeatColor(theme.colorScheme, level / 4),
                    borderRadius: BorderRadius.circular(kOpenHandRadius3),
                  ),
                ),
                kOpenHandHGap3,
              ],
              kOpenHandHGap3,
              Text(
                openHandLocalizedText(context, zh: '多', en: 'More'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiUsageHeatmapCell extends StatelessWidget {
  const _AiUsageHeatmapCell({
    required this.date,
    required this.today,
    required this.bucket,
    required this.maxTokens,
  });

  final DateTime date;
  final DateTime today;
  final AiUsageBucket? bucket;
  final int maxTokens;

  @override
  Widget build(BuildContext context) {
    final future = date.isAfter(today);
    final tokens = bucket?.totalTokens ?? 0;
    final intensity = tokens <= 0 || maxTokens <= 0
        ? 0.0
        : math.log(tokens + 1) / math.log(maxTokens + 1);
    final cell = Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: future
            ? Colors.transparent
            : _usageHeatColor(Theme.of(context).colorScheme, intensity),
        borderRadius: BorderRadius.circular(kOpenHandRadius3),
        border: future
            ? null
            : Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.34),
                width: 0.5,
              ),
      ),
    );
    if (future) return cell;
    return Tooltip(
      message:
          '${formatYearMonthDay(date)}\n'
          '${_usageInteger(tokens)} Token · ${bucket?.requestCount ?? 0} '
          '${openHandLocalizedText(context, zh: '次请求', en: 'requests')}\n'
          '${_settingsAiUsagCostLabel(context)} ${bucket == null || bucket!.pricedRequestCount == 0
              ? '—'
              : bucket!.pricedRequestCount < bucket!.requestCount
              ? '≥${_usageMoney(bucket!.totalCostUsd)}'
              : _usageMoney(bucket!.totalCostUsd)}',
      child: cell,
    );
  }
}

class _AiUsageBreakdownPanel extends StatefulWidget {
  const _AiUsageBreakdownPanel({required this.snapshot});

  final AiUsageSnapshot snapshot;

  @override
  State<_AiUsageBreakdownPanel> createState() => _AiUsageBreakdownPanelState();
}

class _AiUsageBreakdownPanelState extends State<_AiUsageBreakdownPanel> {
  String _dimension = 'source';

  @override
  Widget build(BuildContext context) {
    final options = <(String, String)>[
      ('source', openHandSourceLabel(context)),
      ('provider', _settingsAiUsagProviderLabel(context)),
      ('model', openHandModelLabel(context)),
      ('surface', _settingsAiUsagSurfaceLabel(context)),
      ('template', openHandTemplateLabel(context)),
      ('operation', _settingsAiUsagOperationLabel(context)),
    ];
    final items = switch (_dimension) {
      'provider' => widget.snapshot.providers,
      'model' => widget.snapshot.models,
      'surface' => widget.snapshot.surfaces,
      'template' => widget.snapshot.templates,
      'operation' => widget.snapshot.operations,
      _ => widget.snapshot.sources,
    };
    return _AiUsagePanel(
      title: openHandLocalizedText(
        context,
        zh: '多维用量分析',
        en: 'Multidimensional Analysis',
      ),
      subtitle: openHandLocalizedText(
        context,
        zh: '按来源、APP/WEB 端侧、供应商、模型、线程模板与内部操作拆解',
        en: 'Break down usage by source, APP/WEB surface, provider, model, thread template, and operation',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                SizedBox(
                  height: _kAiUsageToolbarControlHeight,
                  child: ChoiceChip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    selected: _dimension == option.$1,
                    label: Text(option.$2),
                    onSelected: (selected) {
                      if (selected) setState(() => _dimension = option.$1);
                    },
                  ),
                ),
            ],
          ),
          kOpenHandGap18,
          _buildAiUsageAnimatedSwap(
            context,
            items.isEmpty
                ? SizedBox(
                    key: ValueKey<String>(
                      '$_dimension-empty-${widget.snapshot.generatedAt.microsecondsSinceEpoch}',
                    ),
                    height: 110,
                    child: OpenHandInlineEmptyState(
                      message: openHandLocalizedText(
                        context,
                        zh: '该维度暂无数据',
                        en: 'No data for this dimension',
                      ),
                    ),
                  )
                : _AiUsageBreakdownTable(
                    key: ValueKey<String>(
                      '$_dimension-${widget.snapshot.generatedAt.microsecondsSinceEpoch}',
                    ),
                    items: items,
                    dimension: _dimension,
                  ),
          ),
        ],
      ),
    );
  }
}

class _AiUsageBreakdownTable extends StatefulWidget {
  const _AiUsageBreakdownTable({
    super.key,
    required this.items,
    required this.dimension,
  });

  final List<AiUsageBreakdown> items;
  final String dimension;

  @override
  State<_AiUsageBreakdownTable> createState() => _AiUsageBreakdownTableState();
}

class _AiUsageBreakdownTableState extends State<_AiUsageBreakdownTable> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  int _page = 1;
  int _pageSize = kOpenHandTableDefaultPageSize;

  OpenHandPageWindow get _window => OpenHandPageWindow.normalize(
    page: _page,
    pageSize: _pageSize,
    total: widget.items.length,
  );

  @override
  void didUpdateWidget(covariant _AiUsageBreakdownTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final window = _window;
    _page = window.page;
    _pageSize = window.pageSize;
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final window = _window;
    final pageItems = window.slice(widget.items);
    final bodyHeight = math.min(
      _kAiUsageBreakdownBodyMaxHeight,
      math.max(pageItems.length, 1) * _kAiUsageBreakdownRowHeight,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(
          constraints.maxWidth,
          _kAiUsageBreakdownTableMinWidth,
        );
        return ClipRRect(
          borderRadius: kOpenHandBorderRadius16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: kOpenHandBorderRadius16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OpenHandSafeScrollbar(
                  controller: _horizontalController,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: SingleChildScrollView(
                    controller: _horizontalController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: _kAiUsageBreakdownHeaderHeight,
                            color: colorScheme.surfaceContainerHighest,
                            child: _buildRow(context, header: true),
                          ),
                          SizedBox(
                            height: bodyHeight,
                            child: OpenHandSafeScrollbar(
                              controller: _verticalController,
                              child: ListView.builder(
                                controller: _verticalController,
                                padding: EdgeInsets.zero,
                                itemCount: pageItems.length,
                                itemExtent: _kAiUsageBreakdownRowHeight,
                                itemBuilder: (context, index) {
                                  final item = pageItems[index];
                                  return SettingsAwareAppearOnce(
                                    key: ValueKey<String>(
                                      '${widget.dimension}-${item.key}',
                                    ),
                                    child: Container(
                                      color: index.isEven
                                          ? colorScheme.surfaceContainerLowest
                                          : colorScheme.surfaceContainerLow,
                                      child: _buildRow(context, item: item),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                OpenHandTablePagination(
                  total: window.total,
                  page: window.page,
                  pageSize: window.pageSize,
                  bar: true,
                  onPageChanged: (page) {
                    setState(() => _page = page);
                    if (_verticalController.hasClients) {
                      _verticalController.jumpTo(0);
                    }
                  },
                  onPageSizeChanged: (size) => setState(() {
                    _pageSize = size;
                    _page = 1;
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context, {
    bool header = false,
    AiUsageBreakdown? item,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final label = item == null
        ? ''
        : switch (widget.dimension) {
            'source' => _usageSourceLabel(context, item.label),
            'operation' => _usageOperationLabel(context, item.label),
            'surface' => item.label.toUpperCase(),
            _ => item.label,
          };
    final successRate = item == null || item.requestCount == 0
        ? 0.0
        : item.successCount / item.requestCount;
    Widget cell({
      required int flex,
      required Widget child,
      Alignment alignment = Alignment.centerRight,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(alignment: alignment, child: child),
        ),
      );
    }

    Text value(String text, {TextAlign align = TextAlign.right}) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: header ? headerStyle : valueStyle,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.7),
        ),
      ),
      child: Row(
        children: [
          cell(
            flex: 28,
            alignment: Alignment.centerLeft,
            child: header
                ? value(
                    _usageBreakdownDimensionLabel(context, widget.dimension),
                    align: TextAlign.left,
                  )
                : Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(kOpenHandRadius9),
                        ),
                        child: Icon(
                          _usageDimensionIcon(widget.dimension),
                          size: 16,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      kOpenHandHGap10,
                      Expanded(
                        child: Tooltip(
                          message: label,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: valueStyle,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          cell(
            flex: 16,
            child: header
                ? value('Token')
                : OpenHandTokenMetricCell(
                    total: item!.totalTokens,
                    showBreakdown: false,
                  ),
          ),
          cell(
            flex: 11,
            child: value(
              header
                  ? _settingsAiUsagRequestsLabel(context)
                  : '${item?.requestCount ?? 0}',
            ),
          ),
          cell(
            flex: 13,
            child: value(
              header
                  ? _settingsAiUsagSuccessLabel(context)
                  : _usagePercent(successRate),
            ),
          ),
          cell(
            flex: 16,
            child: header
                ? value(_settingsAiUsagCostLabel(context))
                : OpenHandCostMetricCell(
                    usd: item!.pricedRequestCount == 0
                        ? null
                        : item.totalCostUsd,
                    uncertain: item.pricedRequestCount < item.requestCount,
                  ),
          ),
          cell(
            flex: 16,
            child: header
                ? value(
                    openHandLocalizedText(
                      context,
                      zh: '平均耗时',
                      en: 'Avg. Latency',
                    ),
                  )
                : OpenHandDurationMetricCell(
                    durationMs: item?.averageDurationMs,
                  ),
          ),
        ],
      ),
    );
  }
}

class _AiUsageRecentPanel extends StatefulWidget {
  const _AiUsageRecentPanel({required this.filter, required this.revision});

  final AiUsageFilter filter;
  final DateTime revision;

  @override
  State<_AiUsageRecentPanel> createState() => _AiUsageRecentPanelState();
}

class _AiUsageRecentPanelState extends State<_AiUsageRecentPanel> {
  int _page = 1;
  int _pageSize = kOpenHandTableDefaultPageSize;
  int _total = 0;
  int _generation = 0;
  List<AiUsageRequestRecord> _records = const <AiUsageRequestRecord>[];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _AiUsageRecentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.filter, widget.filter)) {
      _page = 1;
      unawaited(_load());
      return;
    }
    if (oldWidget.revision != widget.revision) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final page = _page;
    final pageSize = _pageSize;
    if (mounted) setState(() => _loading = true);
    try {
      final fetched = await openHandFetchPage<AiUsageRequestRecord>(
        page: page,
        pageSize: pageSize,
        fetch: ({required offset, required limit}) {
          return AiUsageTracker.instance.loadRequestPage(
            widget.filter,
            offset: offset,
            limit: limit,
          );
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _total = fetched.$2.total;
        _records = fetched.$1;
        _page = fetched.$2.page;
        _pageSize = fetched.$2.pageSize;
        _loading = false;
        _error = null;
      });
    } catch (error, stack) {
      silentLog('settings_ai_usage', '分页加载请求追踪', error, stack);
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = !_loading && _total == 0 && _error == null;
    return _AiUsagePanel(
      title: openHandLocalizedText(context, zh: '请求追踪', en: 'Request Traces'),
      subtitle: openHandLocalizedText(
        context,
        zh: '最近请求的模型、来源、Token、成本、耗时与状态，不保存 Prompt 正文',
        en: 'Recent model, source, token, cost, latency, and status data; prompt bodies are never stored',
      ),
      child: empty
          ? SizedBox(
              height: 110,
              child: OpenHandInlineEmptyState(
                message: openHandLocalizedText(
                  context,
                  zh: '当前范围暂无请求记录',
                  en: 'No request records in this range',
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      openHandLocalizedText(
                        context,
                        zh: '请求记录加载失败，可稍后重试。',
                        en: 'Failed to load request records. Try again later.',
                      ),
                    ),
                  ),
                if (_loading && _records.isEmpty)
                  const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _AiUsageRequestTable(
                    records: _records,
                    scrollResetKey: (_page, _pageSize),
                    footer: OpenHandTablePagination(
                      total: _total,
                      page: _page,
                      pageSize: _pageSize,
                      bar: true,
                      enabled: !_loading,
                      onPageChanged: (page) {
                        setState(() => _page = page);
                        unawaited(_load());
                      },
                      onPageSizeChanged: (size) {
                        setState(() {
                          _pageSize = size;
                          _page = 1;
                        });
                        unawaited(_load());
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

class _AiUsageRequestTable extends StatelessWidget {
  const _AiUsageRequestTable({
    required this.records,
    required this.scrollResetKey,
    this.footer,
  });

  final List<AiUsageRequestRecord> records;
  final Object scrollResetKey;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final traceLabel = openHandLocalizedText(
      context,
      zh: '追踪 ID',
      en: 'Trace ID',
    );
    final unknown = openHandLocalizedText(context, zh: '未知', en: 'Unknown');
    final firstTokenLabel = openHandLocalizedText(
      context,
      zh: '首字',
      en: 'First',
    );

    return OpenHandOperationalRankTable(
      sortByValue: false,
      paginate: false,
      footer: footer,
      scrollResetKey: scrollResetKey,
      animateRows: true,
      semanticsLabel: openHandLocalizedText(
        context,
        zh: '请求追踪表',
        en: 'Request trace table',
      ),
      maxBodyHeight: kOpenHandTableMetricBodyMaxHeight,
      minimumColumnWidths: const <int, double>{
        0: _kAiUsageRequestTimeColumnMinWidth,
      },
      columnAlignments: const <int, Alignment>{
        0: Alignment.centerLeft,
        1: Alignment.centerLeft,
        2: Alignment.centerLeft,
        3: Alignment.centerLeft,
        4: Alignment.centerLeft,
        5: Alignment.centerLeft,
        6: Alignment.centerLeft,
        7: Alignment.centerLeft,
      },
      headers: [
        openHandLocalizedText(context, zh: '请求时间', en: 'Time'),
        openHandModelLabel(context),
        openHandSourceLabel(context),
        openHandProtocolLabel(context),
        openHandLocalizedText(context, zh: '来源地址', en: 'Source'),
        openHandLocalizedText(context, zh: '网络路径', en: 'Network'),
        openHandLocalizedText(context, zh: '进程/服务', en: 'Process'),
        openHandLocalizedText(context, zh: '设备/MAC', en: 'Device/MAC'),
        'Token',
        _settingsAiUsagCostLabel(context),
        openHandLocalizedText(context, zh: '耗时', en: 'Latency'),
        openHandStatusLabel(context),
      ],
      rows: [
        for (final record in records)
          OpenHandOperationalRankRow(
            value: record.startedAt.microsecondsSinceEpoch,
            data: record,
            rowKey: record.id,
            cells: [
              formatYearMonthDayHms(record.startedAt),
              record.modelId,
              _usageSourceLabel(context, record.source),
              record.apiFamily.replaceAll('_', ' '),
              record.sourceEndpoint.isEmpty ? unknown : record.sourceEndpoint,
              record.networkMode.isEmpty
                  ? unknown
                  : _usageNetworkModeLabel(context, record.networkMode),
              record.processServiceName.isEmpty
                  ? unknown
                  : record.processServiceName,
              record.macAddress.isEmpty ? unknown : record.macAddress,
              '${openHandTableMetricInteger(record.usage.totalTokens ?? 0)}${record.usageEstimated ? ' ≈' : ''}',
              record.totalCostUsd == null
                  ? kOpenHandTableMetricEmpty
                  : _usageMoney(record.totalCostUsd!),
              openHandTableMetricDuration(record.durationMs),
              _usageRequestStatusLabel(context, record.status),
            ],
            cellSubtitles: [
              '',
              record.providerName,
              '${_usageOperationLabel(context, record.operation)} · ${record.surface.toUpperCase()}',
              '',
              record.userAgent.isEmpty ? unknown : record.userAgent,
              [
                if (record.targetHost.isNotEmpty) record.targetHost,
                if (record.targetPort.isNotEmpty) ':${record.targetPort}',
                if (record.networkEndpoint.isNotEmpty)
                  ' · ${record.networkEndpoint}',
              ].join(),
              record.processId.isEmpty ? unknown : 'PID ${record.processId}',
              [
                record.metadataText('host_os'),
                record.metadataText('host_hostname'),
              ].where((value) => value.isNotEmpty).join(' · '),
              [
                '$kOpenHandTableMetricTokenInputMarker ${openHandTableMetricCompactNumber(record.usage.promptTokens ?? 0)}',
                '$kOpenHandTableMetricTokenOutputMarker ${openHandTableMetricCompactNumber(record.usage.completionTokens ?? 0)}',
                if ((record.usage.cacheReadTokens ?? 0) > 0)
                  '$kOpenHandTableMetricTokenCacheMarker ${openHandTableMetricCompactNumber(record.usage.cacheReadTokens!)}',
              ].join('  '),
              '',
              record.firstTokenMs == null
                  ? ''
                  : '$firstTokenLabel ${openHandTableMetricDuration(record.firstTokenMs!)}',
              '',
            ],
            cellWidgets: [
              null,
              null,
              null,
              null,
              null,
              null,
              null,
              null,
              OpenHandTokenMetricCell(
                total: record.usage.totalTokens ?? 0,
                promptTokens: record.usage.promptTokens ?? 0,
                completionTokens: record.usage.completionTokens ?? 0,
                cacheReadTokens: record.usage.cacheReadTokens ?? 0,
                estimated: record.usageEstimated,
              ),
              OpenHandCostMetricCell(usd: record.totalCostUsd),
              OpenHandDurationMetricCell(
                durationMs: record.durationMs,
                firstTokenMs: record.firstTokenMs,
                firstTokenLabel: firstTokenLabel,
              ),
              OpenHandTableStatusBadge(
                label: _usageRequestStatusLabel(context, record.status),
                color: _usageRequestStatusColor(colorScheme, record.status),
                tooltip:
                    '${openHandStatusLabel(context)}: ${_usageRequestStatusLabel(context, record.status)}'
                    '${record.errorType == null ? '' : '\n${openHandErrorLabel(context)}: ${record.errorType}'}'
                    '\n$traceLabel: ${record.traceId}',
              ),
            ],
          ),
      ],
      onRowTap: (row) {
        final record = row.data;
        if (record is AiUsageRequestRecord) {
          unawaited(_showDetails(context, record));
        }
      },
    );
  }

  Future<void> _showDetails(BuildContext context, AiUsageRequestRecord record) {
    return showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => _AiUsageRequestDetailsDialog(record: record),
    );
  }
}

class _AiUsageRequestDetailsDialog extends StatelessWidget {
  const _AiUsageRequestDetailsDialog({required this.record});

  final AiUsageRequestRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final statusColor = _usageRequestStatusColor(colorScheme, record.status);
    final unsuccessful = record.status != AiUsageRequestStatus.success;
    final endedAt = record.startedAt.add(
      Duration(milliseconds: record.durationMs),
    );
    final requestRows = <({String label, String value})>[
      (label: openHandModelLabel(context), value: record.modelId),
      (
        label: _settingsAiUsagProviderLabel(context),
        value: record.providerName,
      ),
      (
        label: openHandSourceLabel(context),
        value:
            '${_usageSourceLabel(context, record.source)} · ${_usageOperationLabel(context, record.operation)} · ${record.surface.toUpperCase()}',
      ),
      (
        label: openHandProtocolLabel(context),
        value: record.apiFamily.replaceAll('_', ' '),
      ),
      (
        label: openHandLocalizedText(context, zh: '来源地址', en: 'Source'),
        value: record.sourceEndpoint.isEmpty ? '—' : record.sourceEndpoint,
      ),
      (
        label: openHandLocalizedText(context, zh: '客户端 UA', en: 'User-Agent'),
        value: record.userAgent.isEmpty ? '—' : record.userAgent,
      ),
      (
        label: openHandLocalizedText(context, zh: '网络路径', en: 'Network'),
        value:
            [
              if (record.networkMode.isNotEmpty)
                _usageNetworkModeLabel(context, record.networkMode),
              if (record.targetHost.isNotEmpty) record.targetHost,
              if (record.targetPort.isNotEmpty) ':${record.targetPort}',
            ].join(' · ').trim().isEmpty
            ? '—'
            : [
                if (record.networkMode.isNotEmpty)
                  _usageNetworkModeLabel(context, record.networkMode),
                if (record.targetHost.isNotEmpty) record.targetHost,
                if (record.targetPort.isNotEmpty) ':${record.targetPort}',
              ].join(' · '),
      ),
      (
        label: openHandLocalizedText(context, zh: '进程/服务', en: 'Process'),
        value:
            [
              if (record.processServiceName.isNotEmpty)
                record.processServiceName,
              if (record.processId.isNotEmpty) 'PID ${record.processId}',
            ].join(' · ').trim().isEmpty
            ? '—'
            : [
                if (record.serviceName.isNotEmpty) record.serviceName,
                if (record.processId.isNotEmpty) 'PID ${record.processId}',
              ].join(' · '),
      ),
      (
        label: openHandLocalizedText(context, zh: '设备/MAC', en: 'Device/MAC'),
        value: record.macAddress.isEmpty ? '—' : record.macAddress,
      ),
      if (record.clientMetadataSource.isNotEmpty)
        (
          label: openHandLocalizedText(
            context,
            zh: '客户端元数据来源',
            en: 'Client metadata source',
          ),
          value: record.clientMetadataSource == 'client_declared'
              ? openHandLocalizedText(
                  context,
                  zh: '客户端声明',
                  en: 'Client declared',
                )
              : record.clientMetadataSource,
        ),
    ];
    final diagnosticRows = <({String label, String value})>[
      if (record.errorType case final value?)
        (
          label: openHandLocalizedText(
            context,
            zh: '异常类型',
            en: 'Exception Type',
          ),
          value: value,
        ),
      if (record.httpStatusCode case final value?)
        (label: 'HTTP', value: '$value'),
      if (record.timeoutMs case final value?)
        (
          label: openHandLocalizedText(
            context,
            zh: '超时阈值',
            en: 'Timeout Limit',
          ),
          value: _usageDuration(value.toDouble()),
        ),
      if (record.timeoutPhase case final value?)
        (
          label: openHandLocalizedText(
            context,
            zh: '超时阶段',
            en: 'Timeout Phase',
          ),
          value: _usageTimeoutPhaseLabel(context, value),
        ),
    ];
    return buildOpenHandDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius20),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: math.min(780, size.height * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 10, 15),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: kOpenHandBorderRadius12,
                  ),
                  child: Icon(
                    _usageRequestStatusIcon(record.status),
                    color: statusColor,
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '请求诊断',
                          en: 'Request Diagnostics',
                        ),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      kOpenHandGap2,
                      Text(
                        '${formatYearMonthDayHms(record.startedAt)} · ${_usageRequestStatusLabel(context, record.status)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => unawaited(
                    copyOpenHandTextToClipboard(
                      logTag: 'settings',
                      context: context,
                      text: _diagnosticJson(),
                      successMessage: openHandLocalizedText(
                        context,
                        zh: '请求诊断已复制',
                        en: 'Request diagnostics copied',
                      ),
                      logAction: '复制 AI 请求诊断',
                    ),
                  ),
                  tooltip: openHandLocalizedText(
                    context,
                    zh: '复制诊断',
                    en: 'Copy diagnostics',
                  ),
                  icon: const Icon(Icons.copy_all_outlined),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: openHandCloseLabel(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 540 ? 2 : 1;
                      final width =
                          (constraints.maxWidth - (columns - 1) * 10) / columns;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _AiUsageDetailMetric(
                            width: width,
                            icon: Icons.timer_outlined,
                            label: openHandLocalizedText(
                              context,
                              zh: '请求耗时',
                              en: 'Duration',
                            ),
                            value: _usageDuration(record.durationMs.toDouble()),
                          ),
                          _AiUsageDetailMetric(
                            width: width,
                            icon: Icons.data_usage_rounded,
                            label: 'Token',
                            value: _usageInteger(record.usage.totalTokens ?? 0),
                          ),
                        ],
                      );
                    },
                  ),
                  if (unsuccessful) ...[
                    kOpenHandGap12,
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: kOpenHandBorderRadius12,
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            openHandLocalizedText(
                              context,
                              zh: '错误摘要',
                              en: 'Error Summary',
                            ),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          kOpenHandGap8,
                          SelectableText(
                            record.errorMessage ??
                                record.errorType ??
                                openHandLocalizedText(
                                  context,
                                  zh: '底层请求未提供错误正文。',
                                  en: 'The underlying request did not provide an error message.',
                                ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (diagnosticRows.isNotEmpty) ...[
                    kOpenHandGap12,
                    _AiUsageDetailSection(
                      title: openHandLocalizedText(
                        context,
                        zh: '诊断信息',
                        en: 'Diagnostics',
                      ),
                      rows: diagnosticRows,
                    ),
                  ],
                  kOpenHandGap12,
                  _AiUsageDetailSection(
                    title: openHandLocalizedText(
                      context,
                      zh: '请求上下文',
                      en: 'Request Context',
                    ),
                    rows: requestRows,
                  ),
                  kOpenHandGap12,
                  _AiUsageDetailSection(
                    title: openHandLocalizedText(
                      context,
                      zh: '追踪标识',
                      en: 'Trace Identity',
                    ),
                    rows: <({String label, String value})>[
                      (
                        label: openHandLocalizedText(
                          context,
                          zh: '开始时间',
                          en: 'Started',
                        ),
                        value: formatYearMonthDayHms(record.startedAt),
                      ),
                      (
                        label: openHandLocalizedText(
                          context,
                          zh: '结束时间',
                          en: 'Ended',
                        ),
                        value: formatYearMonthDayHms(endedAt),
                      ),
                      (label: 'Trace ID', value: record.traceId),
                      if (record.sessionId case final value?)
                        (label: 'Session ID', value: value),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _diagnosticJson() {
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'trace_id': record.traceId,
      'started_at': record.startedAt.toIso8601String(),
      'duration_ms': record.durationMs,
      'status': record.status,
      'error_type': record.errorType,
      'error_message': record.errorMessage,
      'http_status_code': record.httpStatusCode,
      'timeout_ms': record.timeoutMs,
      'timeout_phase': record.timeoutPhase,
      'source': record.source,
      'operation': record.operation,
      'surface': record.surface,
      'provider': record.providerName,
      'model': record.modelId,
      'api_family': record.apiFamily,
      'session_id': record.sessionId,
      'metadata': record.metadata,
    });
  }
}

class _AiUsageDetailMetric extends StatelessWidget {
  const _AiUsageDetailMetric({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: kOpenHandBorderRadius10,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                kOpenHandGap2,
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _AiUsageDetailSection extends StatelessWidget {
  const _AiUsageDetailSection({required this.title, required this.rows});

  final String title;
  final List<({String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          kOpenHandGap6,
          for (var index = 0; index < rows.length; index++) ...[
            _AiUsageDetailRow(
              label: rows[index].label,
              value: rows[index].value,
            ),
            if (index < rows.length - 1)
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _AiUsageDetailRow extends StatelessWidget {
  const _AiUsageDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 480;
          final label = Text(
            this.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          );
          final value = SelectableText(
            this.value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, kOpenHandGap4, value],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 138, child: label),
              kOpenHandHGap12,
              Expanded(child: value),
            ],
          );
        },
      ),
    );
  }
}

class _AiUsageFilterDialog extends StatefulWidget {
  const _AiUsageFilterDialog({
    required this.initial,
    required this.providerFacets,
    required this.modelFacets,
    required this.sourceFacets,
  });

  final AiUsageFilter initial;
  final List<AiUsageFacet> providerFacets;
  final List<AiUsageFacet> modelFacets;
  final List<AiUsageFacet> sourceFacets;

  @override
  State<_AiUsageFilterDialog> createState() => _AiUsageFilterDialogState();
}

class _AiUsageFilterDialogState extends State<_AiUsageFilterDialog> {
  late AiUsageFilter _filter = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    return buildOpenHandDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandDialogDefaultRadius),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      maxWidth: kOpenHandDialogWidthWide,
      maxHeight: math.min(760, size.height * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 14, 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(kOpenHandRadius15),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                kOpenHandWidth13,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '多维筛选',
                          en: 'Usage Filters',
                        ),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        openHandLocalizedText(
                          context,
                          zh: '按供应商、模型和来源组合过滤',
                          en: 'Combine provider, model, and source filters',
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildScopeFacet(context),
                  kOpenHandGap22,
                  _buildFacet(
                    context,
                    title: _settingsAiUsagProviderLabel(context),
                    facets: widget.providerFacets,
                    selected: _filter.providerConfigId,
                    onSelected: (value) => setState(
                      () => _filter = value == null
                          ? _filter.copyWith(clearProvider: true)
                          : _filter.copyWith(providerConfigId: value),
                    ),
                  ),
                  kOpenHandGap22,
                  _buildFacet(
                    context,
                    title: openHandModelLabel(context),
                    facets: widget.modelFacets,
                    selected: _filter.modelId,
                    onSelected: (value) => setState(
                      () => _filter = value == null
                          ? _filter.copyWith(clearModel: true)
                          : _filter.copyWith(modelId: value),
                    ),
                  ),
                  kOpenHandGap22,
                  _buildFacet(
                    context,
                    title: openHandSourceLabel(context),
                    facets: widget.sourceFacets,
                    selected: _filter.source,
                    sourceLabels: true,
                    onSelected: (value) => setState(
                      () => _filter = value == null
                          ? _filter.copyWith(clearSource: true)
                          : _filter.copyWith(source: value),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                OpenHandDialogActionButton.secondary(
                  onPressed: () => setState(
                    () => _filter = AiUsageFilter(range: _filter.range),
                  ),
                  icon: Icons.restart_alt_rounded,
                  label: openHandResetLabel(context),
                ),
                OpenHandDialogActionButton.primary(
                  onPressed: () => Navigator.of(context).pop(_filter),
                  icon: Icons.check_rounded,
                  label: openHandLocalizedText(
                    context,
                    zh: '应用筛选',
                    en: 'Apply',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeFacet(BuildContext context) {
    final theme = Theme.of(context);
    final options = <(AiUsageDataScope, String, String)>[
      (AiUsageDataScope.proxyOnly, '中转站统计', 'Proxy only'),
      (AiUsageDataScope.nonProxy, '非中转站统计', 'Non-proxy only'),
      (AiUsageDataScope.all, '全部统计数据', 'All statistics'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          openHandLocalizedText(context, zh: '数据统计范围', en: 'Data scope'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        kOpenHandGap6,
        Text(
          openHandLocalizedText(
            context,
            zh: '先选择统计来源，再叠加供应商、模型和来源条件',
            en: 'Choose the data scope before adding provider, model or source filters',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        kOpenHandGap10,
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                showCheckmark: false,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_filter.scope == option.$1) ...[
                      Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      openHandLocalizedText(
                        context,
                        zh: option.$2,
                        en: option.$3,
                      ),
                    ),
                  ],
                ),
                selected: _filter.scope == option.$1,
                onSelected: (_) => setState(
                  () => _filter = _filter.copyWith(scope: option.$1),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFacet(
    BuildContext context, {
    required String title,
    required List<AiUsageFacet> facets,
    required String? selected,
    required ValueChanged<String?> onSelected,
    bool sourceLabels = false,
  }) {
    final theme = Theme.of(context);
    final selectionDuration = openHandMotionDuration(
      context,
      kOpenHandMotion180,
    );
    final options = <({String label, String? value})>[
      (label: openHandAllLabel(context), value: null),
      for (final facet in facets)
        (
          label: sourceLabels
              ? _usageSourceLabel(context, facet.label)
              : facet.label,
          value: facet.value,
        ),
    ];
    final baseLabelStyle = theme.textTheme.labelLarge ?? const TextStyle();
    final labelStyles = <TextStyle>[
      baseLabelStyle.merge(theme.chipTheme.labelStyle),
      baseLabelStyle.merge(theme.chipTheme.secondaryLabelStyle),
    ];
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    double measureLabel(String label) {
      var labelWidth = 0.0;
      for (final style in labelStyles) {
        labelWidth = math.max(
          labelWidth,
          TextPainter.computeWidth(
            text: TextSpan(text: label, style: style),
            textDirection: textDirection,
            textScaler: textScaler,
            maxLines: 1,
          ),
        );
      }
      return labelWidth;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        kOpenHandGap10,
        LayoutBuilder(
          builder: (context, constraints) {
            Widget chip(({String label, String? value}) option) {
              final isSelected = selected == option.value;
              final chipWidth = math.min(
                math.max(
                  _kAiUsageFilterChipMinWidth,
                  measureLabel(option.label) +
                      _kAiUsageFilterChipIconSlotWidth * 2,
                ),
                constraints.maxWidth,
              );
              return FilterChip(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                labelPadding: EdgeInsets.zero,
                showCheckmark: false,
                selected: isSelected,
                label: SizedBox(
                  width: chipWidth,
                  height: _kAiUsageToolbarControlHeight,
                  child: Row(
                    children: [
                      SizedBox(
                        width: _kAiUsageFilterChipIconSlotWidth,
                        child: AnimatedScale(
                          scale: isSelected ? 1 : 0.72,
                          duration: selectionDuration,
                          curve: isSelected
                              ? kOpenHandEntranceCurve
                              : kOpenHandSwitchOutCurve,
                          child: AnimatedOpacity(
                            opacity: isSelected ? 1 : 0,
                            duration: selectionDuration,
                            child: Icon(
                              Icons.check_rounded,
                              size: 18,
                              color:
                                  theme.chipTheme.checkmarkColor ??
                                  theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: _kAiUsageFilterChipIconSlotWidth),
                    ],
                  ),
                ),
                onSelected: (_) => onSelected(option.value),
              );
            }

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final option in options) chip(option)],
            );
          },
        ),
      ],
    );
  }
}

class _AiUsageEmptyState extends StatelessWidget {
  const _AiUsageEmptyState({required this.hasFilters});

  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius22),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(kOpenHandRadius22),
            ),
            child: Icon(
              hasFilters
                  ? Icons.filter_alt_off_rounded
                  : Icons.insights_rounded,
              size: 32,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          kOpenHandGap16,
          Text(
            hasFilters
                ? openHandLocalizedText(
                    context,
                    zh: '当前筛选范围暂无数据',
                    en: 'No data matches the current filters',
                  )
                : openHandLocalizedText(
                    context,
                    zh: '等待首条 AI 使用记录',
                    en: 'Waiting for the first AI usage record',
                  ),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          kOpenHandGap6,
          Text(
            openHandLocalizedText(
              context,
              zh: '发起线程对话、知识库索引、翻译或子任务后，这里会自动更新。',
              en: 'Start a thread, knowledge indexing, translation, or subagent task and analytics will update automatically.',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiUsageLoadingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Column(
      children: [
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(kOpenHandRadius24),
          ),
        ),
        kOpenHandGap12,
        Row(
          children: [
            for (var index = 0; index < 3; index++) ...[
              Expanded(
                child: Container(
                  height: 112,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: kOpenHandBorderRadius18,
                  ),
                ),
              ),
              if (index < 2) kOpenHandHGap10,
            ],
          ],
        ),
      ],
    );
  }
}

String _usageRangeLabel(BuildContext context, AiUsageRange range) {
  return switch (range) {
    AiUsageRange.today => openHandRecentUsageWindowLabel(
      context,
      OpenHandRecentUsageWindow.day,
    ),
    AiUsageRange.sevenDays => openHandRecentUsageWindowLabel(
      context,
      OpenHandRecentUsageWindow.week,
    ),
    AiUsageRange.thirtyDays => openHandRecentUsageWindowLabel(
      context,
      OpenHandRecentUsageWindow.month,
    ),
    AiUsageRange.year => openHandRecentUsageWindowLabel(
      context,
      OpenHandRecentUsageWindow.year,
    ),
    AiUsageRange.all => openHandAllLabel(context),
  };
}

String _usageSourceLabel(BuildContext context, String source) {
  return switch (source) {
    AiUsageSource.thread => openHandLocalizedText(
      context,
      zh: '线程会话',
      en: 'Thread',
    ),
    AiUsageSource.knowledgeBase => openHandKnowledgeBaseLabel(context),
    AiUsageSource.harness => 'Harness Engineering',
    AiUsageSource.translation => openHandLocalizedText(
      context,
      zh: '翻译',
      en: 'Translation',
    ),
    AiUsageSource.textToSpeech => openHandLocalizedText(
      context,
      zh: '文本转语音',
      en: 'Text to Speech',
    ),
    AiUsageSource.speechCommunication => openHandLocalizedText(
      context,
      zh: '语音沟通',
      en: 'Voice Conversation',
    ),
    AiUsageSource.selfLearning => openHandLocalizedText(
      context,
      zh: '自学习',
      en: 'Self Learning',
    ),
    AiUsageSource.subagent => openHandLocalizedText(
      context,
      zh: '子任务',
      en: 'Subagent',
    ),
    AiUsageSource.webSearch => 'WebSearch',
    AiUsageSource.webFetch => 'WebFetch',
    AiUsageSource.modelTest => openHandLocalizedText(
      context,
      zh: '模型测试',
      en: 'Model Test',
    ),
    AiUsageSource.modelProxy => openHandLocalizedText(
      context,
      zh: 'AI模型服务中转站',
      en: 'AI Model Service Proxy',
    ),
    _ => openHandOtherLabel(context),
  };
}

String _usageOperationLabel(BuildContext context, String operation) {
  return switch (operation) {
    'conversation_round' => openHandLocalizedText(
      context,
      zh: '会话回复',
      en: 'Conversation',
    ),
    'speech_text_polishing' => openHandLocalizedText(
      context,
      zh: '语音文本润色',
      en: 'Speech Text Polishing',
    ),
    'goal_turn' => openHandLocalizedText(context, zh: '目标执行', en: 'Goal Turn'),
    'goal_evaluation' => openHandLocalizedText(
      context,
      zh: '目标评估',
      en: 'Goal Evaluation',
    ),
    'auto_title' => openHandLocalizedText(
      context,
      zh: '自动标题',
      en: 'Auto Title',
    ),
    'manual_title' => openHandLocalizedText(
      context,
      zh: '手动标题',
      en: 'Manual Title',
    ),
    'context_compression' => openHandLocalizedText(
      context,
      zh: '上下文压缩',
      en: 'Context Compression',
    ),
    'document_embedding' => openHandLocalizedText(
      context,
      zh: '文档向量化',
      en: 'Document Embedding',
    ),
    'query_embedding' => openHandLocalizedText(
      context,
      zh: '查询向量化',
      en: 'Query Embedding',
    ),
    'retrieval_rerank' => openHandLocalizedText(
      context,
      zh: '检索重排',
      en: 'Retrieval Rerank',
    ),
    'reader_conversion' => openHandLocalizedText(
      context,
      zh: '文档读取转换',
      en: 'Reader Conversion',
    ),
    'text_translation' => openHandLocalizedText(
      context,
      zh: '文本翻译',
      en: 'Text Translation',
    ),
    'speech_synthesis' => openHandLocalizedText(
      context,
      zh: '语音合成',
      en: 'Speech Synthesis',
    ),
    'proxy_request' => openHandLocalizedText(
      context,
      zh: '中转站请求',
      en: 'Proxy Request',
    ),
    'self_learning_round' => openHandLocalizedText(
      context,
      zh: '自学习轮次',
      en: 'Self-learning Round',
    ),
    'phase_execution' => openHandLocalizedText(
      context,
      zh: '阶段执行',
      en: 'Phase Execution',
    ),
    'context_handoff' => openHandLocalizedText(
      context,
      zh: '上下文交接',
      en: 'Context Handoff',
    ),
    'result_summary' || 'content_summary' => openHandLocalizedText(
      context,
      zh: '结果总结',
      en: 'Result Summary',
    ),
    'subagent_round' => openHandLocalizedText(
      context,
      zh: '子任务轮次',
      en: 'Subagent Round',
    ),
    'availability_probe' => openHandLocalizedText(
      context,
      zh: '可用性测试',
      en: 'Availability Probe',
    ),
    'media_generation' => openHandLocalizedText(
      context,
      zh: '媒体生成',
      en: 'Media Generation',
    ),
    _ => operation.replaceAll('_', ' '),
  };
}

IconData _usageDimensionIcon(String dimension) {
  return switch (dimension) {
    'provider' => Icons.hub_outlined,
    'model' => Icons.smart_toy_outlined,
    'template' => Icons.dashboard_customize_outlined,
    'surface' => Icons.devices_rounded,
    'operation' => Icons.account_tree_outlined,
    _ => Icons.layers_outlined,
  };
}

String _usageBreakdownDimensionLabel(BuildContext context, String dimension) {
  return switch (dimension) {
    'provider' => _settingsAiUsagProviderLabel(context),
    'model' => openHandModelLabel(context),
    'template' => openHandTemplateLabel(context),
    'surface' => _settingsAiUsagSurfaceLabel(context),
    'operation' => _settingsAiUsagOperationLabel(context),
    _ => openHandSourceLabel(context),
  };
}

String _usageRequestStatusLabel(BuildContext context, String status) {
  return switch (status) {
    AiUsageRequestStatus.success => openHandSuccessLabel(context),
    AiUsageRequestStatus.failed => openHandFailedLabel(context),
    AiUsageRequestStatus.timeout => openHandLocalizedText(
      context,
      zh: '超时',
      en: 'Timed Out',
    ),
    AiUsageRequestStatus.error => openHandLocalizedText(
      context,
      zh: '异常',
      zhHant: '異常',
      en: 'Error',
      fr: 'Erreur',
      de: 'Fehler',
      ja: 'エラー',
    ),
    AiUsageRequestStatus.cancelled => openHandCancelledLabel(context),
    _ => status.isEmpty ? openHandUnknownLabel(context) : status,
  };
}

Color _usageRequestStatusColor(ColorScheme colors, String status) =>
    openHandTableMetricRequestStatusColor(colors, status);

IconData _usageRequestStatusIcon(String status) {
  return switch (status) {
    AiUsageRequestStatus.success => Icons.check_circle_outline_rounded,
    AiUsageRequestStatus.timeout => Icons.timer_off_outlined,
    AiUsageRequestStatus.cancelled => Icons.block_rounded,
    AiUsageRequestStatus.failed => Icons.cancel_outlined,
    AiUsageRequestStatus.error => Icons.report_problem_outlined,
    _ => Icons.help_outline_rounded,
  };
}

String _usageTimeoutPhaseLabel(BuildContext context, String phase) {
  return switch (phase) {
    'connection' => openHandLocalizedText(
      context,
      zh: '连接建立',
      en: 'Connection',
    ),
    'response_headers' => openHandLocalizedText(
      context,
      zh: '等待响应头',
      en: 'Response Headers',
    ),
    'response_body' => openHandLocalizedText(
      context,
      zh: '读取响应体',
      en: 'Response Body',
    ),
    'stream_idle' => openHandLocalizedText(
      context,
      zh: '流式响应空闲',
      en: 'Stream Idle',
    ),
    _ => openHandLocalizedText(context, zh: '完整请求', en: 'Request'),
  };
}

Color _usageHeatColor(ColorScheme colors, double intensity) {
  final safe = intensity.clamp(0.0, 1.0);
  if (safe <= 0) return colors.surfaceContainerHighest;
  return Color.lerp(colors.primaryContainer, colors.primary, 0.2 + safe * 0.8)!;
}

String _usageCompactNumber(int value, {int decimals = 1}) =>
    openHandTableMetricCompactNumber(value, decimals: decimals);

String _usageInteger(int value) => openHandTableMetricInteger(value);

String _usageMoney(double value) => openHandTableMetricMoney(value);

String _usagePercent(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _usageDuration(double milliseconds) =>
    openHandTableMetricDuration(milliseconds);

String _usageBucketLabel(String key) {
  if (key.length >= 13 && key[10] == 'T') {
    return '${key.substring(5, 10)} ${key.substring(11, 13)}:00';
  }
  if (key.length >= 10) return key.substring(5, 10);
  return key;
}

String _usageMonthLabel(BuildContext context, DateTime date) {
  final english = Localizations.localeOf(context).languageCode != 'zh';
  if (!english) return '${date.month}月';
  return const <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][date.month - 1];
}

String _settingsAiUsagCostLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '成本', en: 'Cost');
}

String _settingsAiUsagInputLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '输入', en: 'Input');
}

String _settingsAiUsagOperationLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '操作', en: 'Operation');
}

String _settingsAiUsagProviderLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '供应商', en: 'Provider');
}

String _settingsAiUsagRequestsLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '请求', en: 'Requests');
}

String _settingsAiUsagSuccessLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '成功率', en: 'Success');
}

String _settingsAiUsagSurfaceLabel(BuildContext context) {
  return openHandLocalizedText(context, zh: '端侧', en: 'Surface');
}

String _usageNetworkModeLabel(BuildContext context, String mode) {
  return switch (mode.trim().toLowerCase()) {
    'direct' => openHandLocalizedText(context, zh: '直连', en: 'Direct'),
    'system_proxy' ||
    'system' => openHandLocalizedText(context, zh: '系统代理', en: 'System proxy'),
    'pool' ||
    'proxy_pool' => openHandLocalizedText(context, zh: '代理池', en: 'Proxy pool'),
    _ => mode,
  };
}
