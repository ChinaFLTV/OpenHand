part of 'settings_view.dart';

const double _kAiUsageMetricThreeColumnMinWidth = 660;
const double _kAiUsageMetricTwoColumnMinWidth = 440;
const double _kAiUsageMetricHeight = 150;
const double _kAiUsageHeatmapMinWidth = 820;
const double _kAiUsageBreakdownTableMinWidth = 860;
const double _kAiUsageBreakdownHeaderHeight = 46;
const double _kAiUsageBreakdownRowHeight = 58;
const double _kAiUsageBreakdownBodyMaxHeight = 348;
const double _kAiUsageToolbarControlHeight = 40;
const double _kAiUsageFilterChipMinWidth = 96;
const double _kAiUsageFilterChipIconSlotWidth = 26;
const double _kAiUsageRequestTableMinWidth = 1360;
const double _kAiUsageRequestHeaderHeight = 48;
const double _kAiUsageRequestRowHeight = 74;
const double _kAiUsageRequestBodyMaxHeight = 444;
const double _kAiUsageHeroInlineMinWidth = 840;
const double _kAiUsageOverviewFourColumnMinWidth = 1040;
const double _kAiUsageOverviewTwoColumnMinWidth = 560;
const double _kAiUsageDistributionTwoColumnMinWidth = 860;
const double _kAiUsageOverviewMetricHeight = 150;
const double _kAiUsageDistributionRowHeight = 52;
const double _kAiUsageDistributionBodyMaxHeight = 312;
const double _kAiUsageDistributionEmptyBodyHeight = 72;
const double _kAiUsageDistributionChromeHeight = 74;
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
  const _AiUsageSettingsSection({this.embedded = false});

  final bool embedded;

  @override
  State<_AiUsageSettingsSection> createState() =>
      _AiUsageSettingsSectionState();
}

class _AiUsageSettingsSectionState extends State<_AiUsageSettingsSection> {
  AiUsageFilter _filter = const AiUsageFilter();
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
      dismissOnEscape: false,
      builder: (dialogContext) => Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent ||
              event.logicalKey != LogicalKeyboardKey.escape) {
            return KeyEventResult.ignored;
          }
          unawaited(Navigator.of(dialogContext).maybePop());
          return KeyEventResult.handled;
        },
        child: _AiUsageFilterDialog(
          initial: _filter,
          providerFacets: snapshot.providerFacets,
          modelFacets: snapshot.modelFacets,
          sourceFacets: snapshot.sourceFacets,
        ),
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
        zh: '查看线程、知识库、智能体与辅助 AI 请求的 Token 消耗、成本、缓存效率和性能追踪。',
        en: 'Inspect token usage, cost, cache efficiency, and performance traces across threads, knowledge, agents, and supporting AI requests.',
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
                label: Text(_usageRangeLabel(context, range)),
                selected: _filter.range == range,
                avatar: _filter.range == range
                    ? const Icon(Icons.check_rounded, size: 16)
                    : null,
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
      (_filter.source == null ? 0 : 1);

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
            zh: '输入、输出、缓存与成本随时间的变化',
            en: 'Input, output, cache, and cost over time',
          ),
          trailing: Text(_usageRangeLabel(context, snapshot.filter.range)),
          child: _AiUsageTrendChart(buckets: snapshot.trend),
        ),
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
        _AiUsageRecentPanel(records: snapshot.recentRequests),
      ],
    );
  }
}

/// 服务弹窗复用全局设置中的完整使用统计与请求追踪结构。
class AiUsageAnalyticsView extends StatelessWidget {
  const AiUsageAnalyticsView({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) =>
      _AiUsageSettingsSection(embedded: embedded);
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
    final contentHeight = widget.items.isEmpty
        ? _kAiUsageDistributionEmptyBodyHeight
        : widget.items.length * _kAiUsageDistributionRowHeight;
    final bodyHeight = math.min(
      contentHeight,
      _kAiUsageDistributionBodyMaxHeight,
    );
    final scrollable = contentHeight > _kAiUsageDistributionBodyMaxHeight;
    return AnimatedSize(
      alignment: Alignment.topCenter,
      duration: openHandMotionDuration(context, kOpenHandMotion280),
      curve: kOpenHandSwitchInCurve,
      child: SizedBox(
        height: _kAiUsageDistributionChromeHeight + bodyHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: kOpenHandBorderRadius18,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
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
                SizedBox(
                  height: bodyHeight,
                  child: widget.items.isEmpty
                      ? OpenHandInlineEmptyState(message: widget.emptyMessage)
                      : OpenHandSafeScrollbar(
                          controller: _scrollController,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.only(
                              right: scrollable ? 10 : 0,
                            ),
                            itemCount: widget.items.length,
                            itemExtent: _kAiUsageDistributionRowHeight,
                            itemBuilder: (context, index) {
                              final item = widget.items[index];
                              return SettingsAwareAppearOnce(
                                key: ValueKey<String>(
                                  'usage-distribution-${item.key}',
                                ),
                                child: _buildItem(context, item),
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

class _AiUsageTrendChart extends StatefulWidget {
  const _AiUsageTrendChart({required this.buckets});

  final List<AiUsageBucket> buckets;

  @override
  State<_AiUsageTrendChart> createState() => _AiUsageTrendChartState();
}

class _AiUsageTrendChartState extends State<_AiUsageTrendChart> {
  int? _selectedIndex;
  int? _tooltipIndex;
  bool _tooltipVisible = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buckets = widget.buckets;
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
    if (widget.buckets.isEmpty || width <= 0) return;
    final index = widget.buckets.length == 1
        ? 0
        : (dx / width * (widget.buckets.length - 1)).round().clamp(
            0,
            widget.buckets.length - 1,
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
    final bucket = widget.buckets[index];
    final tooltipWidth = math.min(width, 210.0);
    final center = widget.buckets.length == 1
        ? width / 2
        : index * width / (widget.buckets.length - 1);
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
  });

  final List<AiUsageBucket> buckets;
  final ColorScheme colorScheme;
  final int? selectedIndex;

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
    final inputPath = smoothPath(inputPoints);
    final areaPath = Path.from(inputPath)
      ..lineTo(size.width, top + chartHeight)
      ..lineTo(0, top + chartHeight)
      ..close();
    canvas.drawPath(
      areaPath,
      Paint()..color = colorScheme.primary.withValues(alpha: 0.08),
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

    drawSeries(inputPath, colorScheme.primary, 2.6);
    drawSeries(smoothPath(outputPoints), colorScheme.tertiary, 2.2);
    drawSeries(smoothPath(cachePoints), OpenHandStatusColors.success, 2.2);
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

      drawPoint(inputPoints, colorScheme.primary);
      drawPoint(outputPoints, colorScheme.tertiary);
      drawPoint(cachePoints, OpenHandStatusColors.success);
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
        oldDelegate.selectedIndex != selectedIndex;
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
    final bodyHeight = math.min(
      _kAiUsageBreakdownBodyMaxHeight,
      widget.items.length * _kAiUsageBreakdownRowHeight,
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
            child: OpenHandSafeScrollbar(
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
                            itemCount: widget.items.length,
                            itemExtent: _kAiUsageBreakdownRowHeight,
                            itemBuilder: (context, index) {
                              final item = widget.items[index];
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
            child: value(
              header ? 'Token' : _usageInteger(item?.totalTokens ?? 0),
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
            child: value(
              header
                  ? _settingsAiUsagCostLabel(context)
                  : item!.pricedRequestCount == 0
                  ? '—'
                  : item.pricedRequestCount < item.requestCount
                  ? '≥${_usageMoney(item.totalCostUsd)}'
                  : _usageMoney(item.totalCostUsd),
            ),
          ),
          cell(
            flex: 16,
            child: value(
              header
                  ? openHandLocalizedText(
                      context,
                      zh: '平均耗时',
                      en: 'Avg. Latency',
                    )
                  : _usageDuration(item?.averageDurationMs ?? 0),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiUsageRecentPanel extends StatelessWidget {
  const _AiUsageRecentPanel({required this.records});

  final List<AiUsageRequestRecord> records;

  @override
  Widget build(BuildContext context) {
    return _AiUsagePanel(
      title: openHandLocalizedText(context, zh: '请求追踪', en: 'Request Traces'),
      subtitle: openHandLocalizedText(
        context,
        zh: '最近请求的模型、来源、Token、成本、耗时与状态，不保存 Prompt 正文',
        en: 'Recent model, source, token, cost, latency, and status data; prompt bodies are never stored',
      ),
      child: records.isEmpty
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
          : _AiUsageRequestTable(records: records),
    );
  }
}

class _AiUsageRequestTable extends StatefulWidget {
  const _AiUsageRequestTable({required this.records});

  final List<AiUsageRequestRecord> records;

  @override
  State<_AiUsageRequestTable> createState() => _AiUsageRequestTableState();
}

class _AiUsageRequestTableState extends State<_AiUsageRequestTable> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

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
    final bodyHeight = math.min(
      _kAiUsageRequestBodyMaxHeight,
      widget.records.length * _kAiUsageRequestRowHeight,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(
          constraints.maxWidth,
          _kAiUsageRequestTableMinWidth,
        );
        return ClipRRect(
          borderRadius: kOpenHandBorderRadius16,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: kOpenHandBorderRadius16,
            ),
            child: OpenHandSafeScrollbar(
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
                        height: _kAiUsageRequestHeaderHeight,
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
                            itemCount: widget.records.length,
                            itemExtent: _kAiUsageRequestRowHeight,
                            itemBuilder: (context, index) {
                              final record = widget.records[index];
                              return SettingsAwareAppearOnce(
                                key: ValueKey<String>(record.id),
                                child: ColoredBox(
                                  color: index.isEven
                                      ? colorScheme.surfaceContainerLowest
                                      : colorScheme.surfaceContainerLow,
                                  child: _buildRow(context, record: record),
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
          ),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context, {
    bool header = false,
    AiUsageRequestRecord? record,
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
    final secondaryStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final traceLabel = openHandLocalizedText(
      context,
      zh: '追踪 ID',
      en: 'Trace ID',
    );
    final protocolLabel = record?.apiFamily.replaceAll('_', ' ') ?? '';

    Widget cell({
      required int flex,
      required Widget child,
      Alignment alignment = Alignment.centerLeft,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(alignment: alignment, child: child),
        ),
      );
    }

    Text value(String text, {TextAlign align = TextAlign.left}) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: header ? headerStyle : valueStyle,
      );
    }

    Widget details(String primary, String secondary, {bool alignEnd = false}) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          value(primary, align: alignEnd ? TextAlign.right : TextAlign.left),
          kOpenHandGap3,
          Text(
            secondary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: secondaryStyle,
          ),
        ],
      );
    }

    Widget tokenPart(String marker, int amount, Color color) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$marker ',
              style: secondaryStyle?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: _usageCompactNumber(amount), style: secondaryStyle),
          ],
        ),
        maxLines: 1,
      );
    }

    final promptTokens = record?.usage.promptTokens ?? 0;
    final completionTokens = record?.usage.completionTokens ?? 0;
    final cacheReadTokens = record?.usage.cacheReadTokens ?? 0;
    final statusColor = _usageRequestStatusColor(
      colorScheme,
      record?.status ?? '',
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: header || record == null ? null : () => _showDetails(record),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.7),
            ),
          ),
          child: Row(
            children: [
              cell(
                flex: 20,
                child: header
                    ? value(
                        openHandLocalizedText(context, zh: '请求时间', en: 'Time'),
                      )
                    : Tooltip(
                        message: '$traceLabel: ${record!.traceId}',
                        child: value(formatYearMonthDayHms(record.startedAt)),
                      ),
              ),
              cell(
                flex: 20,
                child: header
                    ? value(openHandModelLabel(context))
                    : details(record!.modelId, record.providerName),
              ),
              cell(
                flex: 20,
                child: header
                    ? value(openHandSourceLabel(context))
                    : details(
                        _usageSourceLabel(context, record!.source),
                        '${_usageOperationLabel(context, record.operation)} · ${record.surface.toUpperCase()}',
                      ),
              ),
              cell(
                flex: 18,
                child: header
                    ? value(openHandProtocolLabel(context))
                    : Tooltip(
                        message: protocolLabel,
                        child: value(protocolLabel),
                      ),
              ),
              cell(
                flex: 23,
                alignment: Alignment.centerRight,
                child: header
                    ? value('Token', align: TextAlign.right)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          value(
                            '${_usageInteger(record!.usage.totalTokens ?? 0)}${record.usageEstimated ? ' ≈' : ''}',
                            align: TextAlign.right,
                          ),
                          kOpenHandGap3,
                          Wrap(
                            spacing: 8,
                            runSpacing: 2,
                            alignment: WrapAlignment.end,
                            children: [
                              tokenPart('↑', promptTokens, colorScheme.primary),
                              tokenPart(
                                '↓',
                                completionTokens,
                                colorScheme.tertiary,
                              ),
                              if (cacheReadTokens > 0)
                                tokenPart(
                                  '↻',
                                  cacheReadTokens,
                                  OpenHandStatusColors.success,
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
              cell(
                flex: 12,
                alignment: Alignment.centerRight,
                child: value(
                  header
                      ? _settingsAiUsagCostLabel(context)
                      : record!.totalCostUsd == null
                      ? '—'
                      : _usageMoney(record.totalCostUsd!),
                  align: TextAlign.right,
                ),
              ),
              cell(
                flex: 12,
                alignment: Alignment.centerRight,
                child: header
                    ? value(
                        openHandLocalizedText(context, zh: '耗时', en: 'Latency'),
                        align: TextAlign.right,
                      )
                    : details(
                        _usageDuration(record!.durationMs.toDouble()),
                        '${openHandLocalizedText(context, zh: '首字', en: 'First')} '
                        '${record.firstTokenMs == null ? '—' : _usageDuration(record.firstTokenMs!.toDouble())}',
                        alignEnd: true,
                      ),
              ),
              cell(
                flex: 12,
                alignment: Alignment.center,
                child: header
                    ? value(
                        openHandStatusLabel(context),
                        align: TextAlign.center,
                      )
                    : Tooltip(
                        message:
                            '${openHandStatusLabel(context)}: ${_usageRequestStatusLabel(context, record!.status)}'
                            '${record.errorType == null ? '' : '\n${openHandErrorLabel(context)}: ${record.errorType}'}'
                            '\n$traceLabel: ${record.traceId}',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: kOpenHandPillBorderRadius,
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              kOpenHandHGap6,
                              Text(
                                _usageRequestStatusLabel(
                                  context,
                                  record.status,
                                ),
                                maxLines: 1,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
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

  Future<void> _showDetails(AiUsageRequestRecord record) {
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
              zh: '发起线程对话、知识库索引、翻译或智能体任务后，这里会自动更新。',
              en: 'Start a thread, knowledge indexing, translation, or agent task and analytics will update automatically.',
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
    AiUsageRange.today => openHandTodayLabel(context),
    AiUsageRange.sevenDays => openHandLocalizedText(
      context,
      zh: '7 天',
      en: '7 Days',
    ),
    AiUsageRange.thirtyDays => openHandLocalizedText(
      context,
      zh: '30 天',
      en: '30 Days',
    ),
    AiUsageRange.year => openHandLocalizedText(context, zh: '一年', en: 'Year'),
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
    AiUsageSource.selfLearning => openHandLocalizedText(
      context,
      zh: '自学习',
      en: 'Self Learning',
    ),
    AiUsageSource.agent => openHandAgentLabel(context),
    AiUsageSource.webSearch => 'WebSearch',
    AiUsageSource.webFetch => 'WebFetch',
    AiUsageSource.modelTest => openHandLocalizedText(
      context,
      zh: '模型测试',
      en: 'Model Test',
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
    'subagent_round' || 'agent_worker_round' => openHandLocalizedText(
      context,
      zh: '智能体轮次',
      en: 'Agent Round',
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

Color _usageRequestStatusColor(ColorScheme colors, String status) {
  return switch (status) {
    AiUsageRequestStatus.success => OpenHandStatusColors.success,
    AiUsageRequestStatus.timeout => OpenHandStatusColors.warning,
    AiUsageRequestStatus.cancelled => colors.onSurfaceVariant,
    AiUsageRequestStatus.failed ||
    AiUsageRequestStatus.error => OpenHandStatusColors.error,
    _ => colors.onSurfaceVariant,
  };
}

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

String _usageCompactNumber(int value, {int decimals = 1}) {
  final abs = value.abs();
  if (abs >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(decimals)}亿';
  }
  if (abs >= 10000) {
    return '${(value / 10000).toStringAsFixed(decimals)}万';
  }
  if (abs >= 1000) {
    return '${(value / 1000).toStringAsFixed(decimals)}k';
  }
  return '$value';
}

String _usageInteger(int value) {
  final text = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) buffer.write(',');
    buffer.write(text[index]);
  }
  return buffer.toString();
}

String _usageMoney(double value) {
  if (value == 0) return r'$0.0000';
  if (value.abs() < 0.0001) return r'<$0.0001';
  return '\$${value.toStringAsFixed(value.abs() < 1 ? 4 : 2)}';
}

String _usagePercent(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _usageDuration(double milliseconds) {
  if (milliseconds < 1000) return '${milliseconds.round()}ms';
  if (milliseconds < 60000) {
    return '${(milliseconds / 1000).toStringAsFixed(1)}s';
  }
  return '${(milliseconds / 60000).toStringAsFixed(1)}m';
}

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

// ── 本文件内复用的文案 ──
// 同一标签在本文件里出现两次以上；抽成函数后措辞只有一个改动点。

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
