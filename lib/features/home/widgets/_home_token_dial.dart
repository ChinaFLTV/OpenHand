part of '../openhand_home_page.dart';

class _TokenDial extends StatefulWidget {
  const _TokenDial({
    required this.session,
    required this.statistics,
    this.activeProfile,
    this.claudeStyle = true,
  });

  final AiSession session;
  final AiSessionStatistics statistics;
  final AiModelProfile? activeProfile;
  final bool claudeStyle;

  int get totalTokens => statistics.totalTokens ?? 0;
  int? get cacheReadTokens => statistics.cacheReadTokens;
  int? get cacheCreationTokens => statistics.cacheCreationTokens;

  /// 当前会话的 cache 命中率，范围 0..1。
  ///
  /// 与浮窗完全同一公式：优先读取持久化趋势点；缺失时才从当前消息窗口
  /// 兜底重算。默认口径剔除首轮冷请求和过期异常，避免历史预计算字段在
  /// 规则升级后带来跨端数字漂移。
  double get cacheHitRatio {
    final trend = SessionCacheHitTrend.fromStatisticsOrSession(
      session,
      claudeStyle: claudeStyle,
    );
    final ratio = trend
        .displayData(SessionCacheHitDisplayMode.excludeExpiredMisses)
        .averageHitRatio;
    final precomputed = session.statistics.cacheHitRatio;
    if (ratio <= 0 && precomputed != null && trend.points.isEmpty) {
      return finiteUnitInterval(precomputed);
    }
    return ratio;
  }

  @override
  State<_TokenDial> createState() => _TokenDialState();
}

class _TokenDialState extends State<_TokenDial>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portalController = OverlayPortalController();
  final GlobalKey _anchorKey = GlobalKey();
  late final AnimationController _transitionController;
  Timer? _hideTimer;
  bool _showQueued = false;

  void _runAfterFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback();
    });
  }

  bool get _useTapSheet =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// WEB 端同时支持悬停预览和点击切换；点击后 pin 住浮窗直到再次点击或光标移出。
  bool _webClickPinned = false;

  DialogAnimationSettings _dialogSettings(BuildContext context) {
    return openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
  }

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _transitionController.duration = _dialogSettings(context).duration;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _transitionController.dispose();
    super.dispose();
  }

  void _showPopup() {
    _hideTimer?.cancel();
    _showQueued = true;
    _runAfterFrame(() {
      if (!_showQueued) return;
      if (!_portalController.isShowing) {
        _portalController.show();
      }
      _transitionController.forward();
    });
  }

  void _schedulePopupHide() {
    _hideTimer?.cancel();
    _showQueued = false;
    _webClickPinned = false;
    _hideTimer = startSafeTimer(const Duration(milliseconds: 60), () {
      _runAfterFrame(() async {
        await _transitionController.reverse();
        if (!mounted || _showQueued) return;
        if (_portalController.isShowing) {
          _portalController.hide();
        }
      });
    });
  }

  Future<void> _showTouchPopupSheet() async {
    await showAnimatedModalSheet<void>(
      context: context,
      settings: _dialogSettings(context),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: _TokenDialPopup(
          session: widget.session,
          statistics: widget.statistics,
          activeProfile: widget.activeProfile,
          claudeStyle: widget.claudeStyle,
          cacheHitRatio: widget.cacheHitRatio,
          compact: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final numberStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: colorScheme.onSurface,
    );
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: colorScheme.onSurfaceVariant,
    );
    final hasCache = (widget.cacheReadTokens ?? 0) > 0;
    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (overlayContext) {
        return _TokenDialPopupOverlay(
          anchorKey: _anchorKey,
          animation: _transitionController,
          settings: _dialogSettings(overlayContext),
          onEnter: _showPopup,
          onExit: () {
            if (!_webClickPinned) _schedulePopupHide();
          },
          builder: (context, metrics) => _TokenDialPopup(
            session: widget.session,
            statistics: widget.statistics,
            activeProfile: widget.activeProfile,
            claudeStyle: widget.claudeStyle,
            cacheHitRatio: widget.cacheHitRatio,
            maxHeight: metrics.maxHeight,
            minWidth: metrics.minWidth,
            maxWidth: metrics.maxWidth,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) {
          if (!_useTapSheet) _showPopup();
        },
        onExit: (_) {
          if (!_useTapSheet && !_webClickPinned) _schedulePopupHide();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _useTapSheet
              ? _showTouchPopupSheet
              : kIsWeb
              ? () {
                  if (_webClickPinned) {
                    _webClickPinned = false;
                    _schedulePopupHide();
                  } else {
                    _webClickPinned = true;
                    _showPopup();
                  }
                }
              : null,
          child: Container(
            key: _anchorKey,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hasCache
                  ? Colors.green.withValues(alpha: 0.08)
                  : colorScheme.surfaceContainerHighest,
              borderRadius: _borderRadius999,
              border: Border.all(
                color: hasCache
                    ? Colors.green.withValues(alpha: 0.4)
                    : colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasCache
                      ? Icons.bolt_rounded
                      : Icons.confirmation_number_rounded,
                  size: 14,
                  color: hasCache ? Colors.green.shade600 : colorScheme.primary,
                ),
                const SizedBox(width: 6),
                if (hasCache) ...[
                  _CacheSavingsBadge(percent: widget.cacheHitRatio),
                  Container(
                    width: 1,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: colorScheme.outlineVariant,
                  ),
                ],
                RollingText(
                  text: _formatThousands(widget.totalTokens),
                  style: numberStyle ?? const TextStyle(),
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context)!.tokenDialUnit,
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const double _kTokenDialPopupCompactMinWidth = 320;
const double _kTokenDialPopupExpandedMinWidth = 360;
const double _kTokenDialPopupCompactMaxWidth = 420;
const double _kTokenDialPopupExpandedMaxWidth = 520;
const double _kTokenDialPopupViewportPadding = 12;
const double _kTokenDialPopupAnchorGap = 8;
const double _kTokenDialPopupMinScrollableHeight = 180;

double? _positivePopupExtent(double? value) {
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}

class _TokenDialPopupOverlay extends StatelessWidget {
  const _TokenDialPopupOverlay({
    required this.anchorKey,
    required this.animation,
    required this.settings,
    required this.onEnter,
    required this.onExit,
    required this.builder,
  });

  final GlobalKey anchorKey;
  final Animation<double> animation;
  final DialogAnimationSettings settings;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final Widget Function(BuildContext context, _TokenDialPopupMetrics metrics)
  builder;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final overlaySize = Size(constraints.maxWidth, constraints.maxHeight);
          final metrics = _TokenDialPopupMetrics.resolve(
            context: context,
            anchorKey: anchorKey,
            overlaySize: overlaySize,
          );
          return CustomSingleChildLayout(
            delegate: _TokenDialPopupLayoutDelegate(metrics),
            child: MouseRegion(
              onEnter: (_) => onEnter(),
              onExit: (_) => onExit(),
              child: buildAnimationStyleTransition(
                animation: animation,
                settings: settings,
                profile: OpenHandAnimationTransitionProfile(
                  alignment: metrics.placedAbove
                      ? Alignment.bottomRight
                      : Alignment.topRight,
                ),
                child: builder(context, metrics),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TokenDialPopupMetrics {
  const _TokenDialPopupMetrics({
    required this.safeRect,
    required this.anchorRect,
    required this.placedAbove,
    required this.maxHeight,
    required this.minWidth,
    required this.maxWidth,
  });

  final Rect safeRect;
  final Rect anchorRect;
  final bool placedAbove;
  final double maxHeight;
  final double minWidth;
  final double maxWidth;

  static _TokenDialPopupMetrics resolve({
    required BuildContext context,
    required GlobalKey anchorKey,
    required Size overlaySize,
  }) {
    final media = MediaQuery.of(context);
    final safeRect = _safePopupRect(overlaySize, media.padding);
    final anchorRect =
        _anchorRect(anchorKey) ??
        Rect.fromLTWH(safeRect.right, safeRect.top, 0, 0);
    final belowHeight =
        safeRect.bottom - anchorRect.bottom - _kTokenDialPopupAnchorGap;
    final aboveHeight =
        anchorRect.top - safeRect.top - _kTokenDialPopupAnchorGap;
    final placedAbove =
        belowHeight < _kTokenDialPopupMinScrollableHeight &&
        aboveHeight > belowHeight;
    final rawHeight = placedAbove ? aboveHeight : belowHeight;
    final maxHeight = rawHeight.isFinite && rawHeight > 0
        ? rawHeight
              .clamp(
                0.0,
                math.max(_kTokenDialPopupMinScrollableHeight, safeRect.height),
              )
              .toDouble()
        : safeRect.height;
    final maxWidth = math.min(
      _kTokenDialPopupCompactMaxWidth,
      math.max(0.0, safeRect.width),
    );
    final minWidth = math.min(_kTokenDialPopupCompactMinWidth, maxWidth);

    return _TokenDialPopupMetrics(
      safeRect: safeRect,
      anchorRect: anchorRect,
      placedAbove: placedAbove,
      maxHeight: math.max(0.0, maxHeight.toDouble()),
      minWidth: minWidth,
      maxWidth: maxWidth,
    );
  }

  static Rect _safePopupRect(Size size, EdgeInsets padding) {
    final width = size.width.isFinite && size.width > 0 ? size.width : 0.0;
    final height = size.height.isFinite && size.height > 0 ? size.height : 0.0;
    final left = (padding.left + _kTokenDialPopupViewportPadding)
        .clamp(0, width)
        .toDouble();
    final top = (padding.top + _kTokenDialPopupViewportPadding)
        .clamp(0, height)
        .toDouble();
    final right = math.max(
      left,
      width - padding.right - _kTokenDialPopupViewportPadding,
    );
    final bottom = math.max(
      top,
      height - padding.bottom - _kTokenDialPopupViewportPadding,
    );
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static Rect? _anchorRect(GlobalKey key) {
    final context = key.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    final size = renderObject.size;
    if (size.isEmpty) return null;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & size;
  }
}

class _TokenDialPopupLayoutDelegate extends SingleChildLayoutDelegate {
  const _TokenDialPopupLayoutDelegate(this.metrics);

  final _TokenDialPopupMetrics metrics;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: metrics.minWidth,
      maxWidth: metrics.maxWidth,
      maxHeight: metrics.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final safe = metrics.safeRect;
    final rawLeft = metrics.anchorRect.right - childSize.width;
    final left = rawLeft.clamp(safe.left, safe.right - childSize.width);
    final rawTop = metrics.placedAbove
        ? metrics.anchorRect.top - childSize.height - _kTokenDialPopupAnchorGap
        : metrics.anchorRect.bottom + _kTokenDialPopupAnchorGap;
    final top = rawTop.clamp(safe.top, safe.bottom - childSize.height);
    return Offset(left.toDouble(), top.toDouble());
  }

  @override
  bool shouldRelayout(covariant _TokenDialPopupLayoutDelegate oldDelegate) {
    return oldDelegate.metrics.safeRect != metrics.safeRect ||
        oldDelegate.metrics.anchorRect != metrics.anchorRect ||
        oldDelegate.metrics.placedAbove != metrics.placedAbove ||
        oldDelegate.metrics.maxHeight != metrics.maxHeight ||
        oldDelegate.metrics.minWidth != metrics.minWidth ||
        oldDelegate.metrics.maxWidth != metrics.maxWidth;
  }
}

/// 千位分隔符格式化。TopBar Token 胶囊需要带 `,` 的可读数字（17,075），
/// 而缓存收益百分比 / 浮窗行项都不需要分隔符，所以这里只暴露给一个
/// 显式调用点，避免给不需要的场景强加视觉差异。
String _formatThousands(int value) {
  final raw = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i += 1) {
    final remaining = raw.length - i;
    if (i != 0 && remaining % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(raw[i]);
  }
  return value < 0 ? '-${buffer.toString()}' : buffer.toString();
}

/// 悬浮在 `_TokenDial` 下方的结构化 token 详情浮窗。
///
/// 内容分组：
/// - 输入侧：Prompt / Cache Read / Cache Write
/// - 输出侧：Completion
/// - 总计：Total
/// - 会话累计 (消息数 / prompt 字符 / 构建次数)
class _TokenDialPopup extends StatefulWidget {
  const _TokenDialPopup({
    required this.session,
    required this.statistics,
    required this.cacheHitRatio,
    this.activeProfile,
    this.claudeStyle = true,
    this.compact = true,
    this.maxHeight,
    this.minWidth,
    this.maxWidth,
  });

  final AiSession session;
  final AiSessionStatistics statistics;
  final double cacheHitRatio;
  final AiModelProfile? activeProfile;
  final bool claudeStyle;
  final bool compact;
  final double? maxHeight;
  final double? minWidth;
  final double? maxWidth;

  @override
  State<_TokenDialPopup> createState() => _TokenDialPopupState();
}

class _TokenDialPopupState extends State<_TokenDialPopup> {
  final ScrollController _scrollController = ScrollController();
  SessionCacheHitDisplayMode _displayMode =
      SessionCacheHitDisplayMode.excludeExpiredMisses;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final headStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: colorScheme.onSurfaceVariant,
      letterSpacing: 0.4,
    );
    final keyStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final cacheValueStyle = valueStyle?.copyWith(color: Colors.green.shade700);
    final reasoningValueStyle = valueStyle?.copyWith(
      color: Colors.purple.shade400,
    );
    final promptTokensTotal = widget.statistics.totalPromptTokens ?? 0;
    final firstPrompt = widget.statistics.firstPromptTokens ?? 0;
    final promptTokens = (promptTokensTotal - firstPrompt).clamp(
      0,
      promptTokensTotal,
    );
    final completionTokens = widget.statistics.totalCompletionTokens ?? 0;
    final cacheRead = widget.statistics.cacheReadTokens ?? 0;
    final cacheWrite = widget.statistics.cacheCreationTokens ?? 0;
    final reasoning = widget.statistics.reasoningTokens ?? 0;
    final total = widget.statistics.totalTokens ?? 0;
    final trend = SessionCacheHitTrend.fromStatisticsOrSession(
      widget.session,
      claudeStyle: widget.claudeStyle,
    );
    final displayData = trend.displayData(_displayMode);
    final cacheHitRatio = trend.points.isEmpty
        ? widget.cacheHitRatio
        : displayData.averageHitRatio;
    final hasCacheUsageTelemetry =
        widget.statistics.cacheReadTokens != null ||
        widget.statistics.cacheCreationTokens != null ||
        trend.points.isNotEmpty;
    final showCacheHitMetrics = shouldShowSessionCacheHitMetrics(
      totalPromptTokens: promptTokensTotal,
      totalTokens: total,
      cacheReadTokens: cacheRead,
      cacheWriteTokens: cacheWrite,
      hasTrendPoints: trend.points.isNotEmpty,
    );
    final fallbackUncachedRaw = promptTokens - cacheRead - cacheWrite;
    final fallbackUncachedPromptTokens = widget.claudeStyle
        ? promptTokens
        : (fallbackUncachedRaw > 0 ? fallbackUncachedRaw : 0);
    final cacheBarPromptTokens = trend.points.isNotEmpty
        ? displayData.uncachedPromptTokens
        : fallbackUncachedPromptTokens;
    final defaultMinWidth = widget.compact
        ? _kTokenDialPopupCompactMinWidth
        : _kTokenDialPopupExpandedMinWidth;
    final defaultMaxWidth = widget.compact
        ? _kTokenDialPopupCompactMaxWidth
        : _kTokenDialPopupExpandedMaxWidth;
    final maxWidth = _positivePopupExtent(widget.maxWidth) ?? defaultMaxWidth;
    final minWidth = math.min(
      _positivePopupExtent(widget.minWidth) ?? defaultMinWidth,
      maxWidth,
    );
    final maxHeight = _positivePopupExtent(widget.maxHeight) ?? double.infinity;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppLocalizations.of(context)!.tokenPopupInputHeading.toUpperCase(),
          style: headStyle,
        ),
        const SizedBox(height: 6),
        _PopupRow(
          label: AppLocalizations.of(context)!.tokenPopupPrompt,
          value: promptTokens,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
        ),
        if (hasCacheUsageTelemetry) ...[
          _PopupRow(
            label: AppLocalizations.of(context)!.tokenPopupCacheRead,
            value: cacheRead,
            keyStyle: keyStyle,
            valueStyle: cacheValueStyle,
            accent: Colors.green,
          ),
          _PopupRow(
            label: AppLocalizations.of(context)!.tokenPopupCacheWrite,
            value: cacheWrite,
            keyStyle: keyStyle,
            valueStyle: cacheValueStyle,
            accent: Colors.green,
          ),
        ],
        const SizedBox(height: 10),
        Text(
          AppLocalizations.of(context)!.tokenPopupOutputHeading.toUpperCase(),
          style: headStyle,
        ),
        const SizedBox(height: 6),
        _PopupRow(
          label: AppLocalizations.of(context)!.tokenPopupCompletion,
          value: completionTokens,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
        ),
        if (reasoning > 0)
          _PopupRow(
            label: AppLocalizations.of(context)!.tokenPopupReasoning,
            value: reasoning,
            keyStyle: keyStyle,
            valueStyle: reasoningValueStyle,
            accent: Colors.purple,
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        _PopupRow(
          label: AppLocalizations.of(context)!.tokenPopupGrandTotal,
          value: total,
          keyStyle: keyStyle?.copyWith(fontWeight: FontWeight.w700),
          valueStyle: valueStyle?.copyWith(
            color: colorScheme.primary,
            fontSize: (valueStyle.fontSize ?? 14) + 1,
          ),
        ),
        if (showCacheHitMetrics) ...[
          const SizedBox(height: 6),
          _PopupRow(
            label: AppLocalizations.of(context)!.tokenPopupCacheHit,
            value: (cacheHitRatio * 100).round(),
            suffix: '%',
            keyStyle: keyStyle,
            valueStyle: cacheValueStyle,
            accent: Colors.green,
          ),
          const SizedBox(height: 6),
          _CacheHitBar(
            ratio: cacheHitRatio,
            cacheRead: displayData.cacheReadTokens,
            cacheWrite: displayData.cacheWriteTokens,
            prompt: cacheBarPromptTokens,
          ),
        ],
        if (trend.points.isNotEmpty) ...[
          const SizedBox(height: 10),
          TokenPopupCacheHitTrendChart(
            trend: trend,
            displayMode: _displayMode,
            onDisplayModeChanged: (mode) {
              if (_displayMode == mode) return;
              setState(() {
                _displayMode = mode;
              });
            },
            height: widget.compact ? 176 : 220,
          ),
        ] else if (cacheRead > 0) ...[
          const SizedBox(height: 10),
          _CompactCacheHitSparkline(
            cacheHitRatio: cacheHitRatio,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            promptTokens: cacheBarPromptTokens,
          ),
        ],
        const SizedBox(height: 10),
        Text(
          AppLocalizations.of(context)!.tokenPopupSessionHeading.toUpperCase(),
          style: headStyle,
        ),
        const SizedBox(height: 6),
        _PopupRow(
          label: AppLocalizations.of(context)!.tokenPopupMessages,
          value: widget.statistics.totalMessageCount,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
        ),
        _PopupRow(
          label: AppLocalizations.of(context)!.tokenPopupPromptBuilds,
          value: widget.statistics.promptBuildCount,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
        ),
        _PopupRow(
          label: AppLocalizations.of(context)!.tokenPopupPromptChars,
          value: widget.statistics.totalPromptCharacters,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
        ),
        ..._buildCostSection(
          context: context,
          headStyle: headStyle,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
          colorScheme: colorScheme,
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          cacheRead: cacheRead,
          cacheWrite: cacheWrite,
        ),
      ],
    );
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minWidth,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          child: buildOpenHandDialogScrollConfiguration(
            child: OpenHandSafeScrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: kOpenHandDialogScrollPhysics,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 1C-B：在累计统计末尾追加成本拆解。当 [activeProfile] 为 null 或
  /// 没有任一价格字段时返回空 list — UI 不渲染该分区。
  List<Widget> _buildCostSection({
    required BuildContext context,
    required TextStyle? headStyle,
    required TextStyle? keyStyle,
    required TextStyle? valueStyle,
    required ColorScheme colorScheme,
    required int promptTokens,
    required int completionTokens,
    required int cacheRead,
    required int cacheWrite,
  }) {
    if (widget.activeProfile == null) return const <Widget>[];
    final breakdown = AiCostBreakdown.compute(
      usage: AiTokenUsage(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        cacheReadTokens: cacheRead,
        cacheCreationTokens: cacheWrite,
      ),
      profile: widget.activeProfile,
      claudeStyle: widget.claudeStyle,
    );
    if (breakdown == null || breakdown.isEmpty) return const <Widget>[];

    final amberStyle = valueStyle?.copyWith(color: Colors.amber.shade700);
    final l10n = AppLocalizations.of(context)!;

    return <Widget>[
      Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        height: 1,
        color: colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
      Text(l10n.tokenPopupCostHeading.toUpperCase(), style: headStyle),
      const SizedBox(height: 6),
      if (breakdown.inputUsd != null)
        _CostPopupRow(
          label: l10n.tokenPopupCostInput,
          usd: breakdown.inputUsd!,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
        ),
      if (breakdown.outputUsd != null)
        _CostPopupRow(
          label: l10n.tokenPopupCostOutput,
          usd: breakdown.outputUsd!,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
        ),
      if (breakdown.cacheReadUsd != null)
        _CostPopupRow(
          label: l10n.tokenPopupCostCacheRead,
          usd: breakdown.cacheReadUsd!,
          keyStyle: keyStyle,
          valueStyle: amberStyle,
        ),
      if (breakdown.cacheWriteUsd != null)
        _CostPopupRow(
          label: l10n.tokenPopupCostCacheWrite,
          usd: breakdown.cacheWriteUsd!,
          keyStyle: keyStyle,
          valueStyle: amberStyle,
        ),
      if (breakdown.totalUsd != null) ...[
        const SizedBox(height: 4),
        _CostPopupRow(
          label: l10n.tokenPopupCostTotal,
          usd: breakdown.totalUsd!,
          keyStyle: keyStyle?.copyWith(fontWeight: FontWeight.w800),
          valueStyle: valueStyle?.copyWith(color: colorScheme.primary),
        ),
      ],
    ];
  }
}

/// 单价行专用：USD 格式化展示（最高精度 4 位小数；总计/小数据时切到更密）。
class _CostPopupRow extends StatefulWidget {
  const _CostPopupRow({
    required this.label,
    required this.usd,
    this.keyStyle,
    this.valueStyle,
  });

  final String label;
  final double usd;
  final TextStyle? keyStyle;
  final TextStyle? valueStyle;

  @override
  State<_CostPopupRow> createState() => _CostPopupRowState();
}

class _CostPopupRowState extends State<_CostPopupRow> {
  bool _hovered = false;

  String _format(double v) {
    if (v == 0) return r'$0.0000';
    if (v >= 1) return '\$${v.toStringAsFixed(2)}';
    if (v >= 0.01) return '\$${v.toStringAsFixed(4)}';
    return '\$${v.toStringAsFixed(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final highlight = _hovered
        ? accent.withValues(alpha: 0.10)
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) {
        if (_hovered) return;
        _hovered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      onExit: (_) {
        if (!_hovered) return;
        _hovered = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: highlight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label, style: widget.keyStyle),
            Text(_format(widget.usd), style: widget.valueStyle),
          ],
        ),
      ),
    );
  }
}

/// TopBar Token 胶囊里的常驻「缓存收益」徽标：闪电图标 + 百分比 + 流体进度条。
/// 比例越高背景越绿、越饱和，给用户一眼可读的「省了多少」反馈。
class _CacheSavingsBadge extends StatelessWidget {
  const _CacheSavingsBadge({required this.percent});

  /// 0..1 之间的命中率。
  final double percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 0 命中时弱化显示；命中越高饱和度越强。
    final clamped = finiteUnitInterval(percent);
    final intensity = (0.5 + clamped * 0.5).clamp(0.5, 1.0);
    final fg = Color.lerp(
      Colors.green.shade400,
      Colors.green.shade700,
      clamped,
    )!;
    final bg = Colors.green.withValues(alpha: 0.12 + clamped * 0.18);
    final percentInt = (clamped * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.savings_rounded, size: 11, color: fg),
          const SizedBox(width: 3),
          RollingText(
            text: '$percentInt',
            style: theme.textTheme.labelSmall!.copyWith(
              fontWeight: FontWeight.w800,
              color: fg.withValues(alpha: intensity),
            ),
          ),
          Text(
            '%',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: fg.withValues(alpha: intensity),
            ),
          ),
        ],
      ),
    );
  }
}

/// 缓存命中比例可视化条：左侧绿色 = cache_read（命中），中间金色 =
/// cache_creation（写入），右侧灰色 = 未缓存的 prompt。Hover 时整体亮度提升，
/// 让用户一眼看出当前 session 的缓存收益。
class _CacheHitBar extends StatefulWidget {
  const _CacheHitBar({
    required this.ratio,
    required this.cacheRead,
    required this.cacheWrite,
    required this.prompt,
  });

  final double ratio;
  final int cacheRead;
  final int cacheWrite;
  final int prompt;

  @override
  State<_CacheHitBar> createState() => _CacheHitBarState();
}

class _CacheHitBarState extends State<_CacheHitBar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 分母：cache_read + cache_write + 未缓存 prompt（promptTokens 已扣除
    // cache_read，与 read/write 不重叠）。
    final total = widget.cacheRead + widget.cacheWrite + widget.prompt;
    final readWeight = unitRatio(widget.cacheRead, total);
    final writeWeight = unitRatio(widget.cacheWrite, total);
    final promptWeight = unitRatio(widget.prompt, total);
    final intensify = _hovered ? 1.10 : 1.0;
    final readColor = Colors.green.shade500;
    final writeColor = Colors.amber.shade600;
    final missColor = colorScheme.surfaceContainerHighest;
    return MouseRegion(
      onEnter: (_) {
        if (_hovered) return;
        _hovered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      onExit: (_) {
        if (!_hovered) return;
        _hovered = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: 8,
        decoration: BoxDecoration(
          color: missColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
          boxShadow: _hovered
              ? <BoxShadow>[
                  BoxShadow(
                    color: readColor.withValues(alpha: 0.18),
                    blurRadius: 4,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            if (readWeight > 0)
              Expanded(
                flex: (readWeight * 1000).round(),
                child: Container(
                  color: readColor.withValues(
                    alpha: clampUnitInterval(0.85 * intensify),
                  ),
                ),
              ),
            if (writeWeight > 0)
              Expanded(
                flex: (writeWeight * 1000).round(),
                child: Container(
                  color: writeColor.withValues(
                    alpha: clampUnitInterval(0.78 * intensify),
                  ),
                ),
              ),
            if (promptWeight > 0)
              Expanded(
                flex: (promptWeight * 1000).round(),
                child: const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }
}

class _PopupRow extends StatefulWidget {
  const _PopupRow({
    required this.label,
    required this.value,
    this.suffix,
    this.keyStyle,
    this.valueStyle,
    this.accent,
  });

  final String label;
  final int value;
  final String? suffix;
  final TextStyle? keyStyle;
  final TextStyle? valueStyle;

  /// Tinted hover highlight (defaults to theme primary when null).
  final Color? accent;

  @override
  State<_PopupRow> createState() => _PopupRowState();
}

class _PopupRowState extends State<_PopupRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? Theme.of(context).colorScheme.primary;
    final highlight = _hovered
        ? accent.withValues(alpha: 0.10)
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) {
        if (_hovered) return;
        _hovered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      onExit: (_) {
        if (!_hovered) return;
        _hovered = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: highlight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label, style: widget.keyStyle),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RollingText(
                  text: '${widget.value}',
                  style: widget.valueStyle ?? const TextStyle(),
                ),
                if (widget.suffix != null) ...[
                  const SizedBox(width: 2),
                  Text(widget.suffix!, style: widget.valueStyle),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 紧凑型缓存命中率微缩图 — 当逐轮次趋势数据不足（走势图退避）时，
/// 用作浮窗内缓存可视化的兜底展示，避免缓存区完全空白。
class _CompactCacheHitSparkline extends StatelessWidget {
  const _CompactCacheHitSparkline({
    required this.cacheHitRatio,
    required this.cacheRead,
    required this.cacheWrite,
    required this.promptTokens,
  });

  final double cacheHitRatio;
  final int cacheRead;
  final int cacheWrite;
  final int promptTokens;

  String _k(int v) {
    if (v < 1000) return '$v';
    return '${(v / 1000).toStringAsFixed(1)}k';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final hitPercent = (cacheHitRatio * 100).round();
    final total = cacheRead + cacheWrite + promptTokens;
    final readFrac = total == 0 ? 0.0 : cacheRead / total;
    final writeFrac = total == 0 ? 0.0 : cacheWrite / total;
    final promptFrac = total == 0 ? 1.0 : promptTokens / total;
    final uncachedLabel = openHandLocalizedText(
      context,
      zh: '未缓存',
      en: 'Uncached',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: Colors.green.shade500,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${l10n.tokenPopupCacheHit} $hitPercent%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.green.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (readFrac > 0)
                  Flexible(
                    flex: (readFrac * 1000).round().clamp(1, 1000),
                    child: Container(color: Colors.green.shade400),
                  ),
                if (writeFrac > 0)
                  Flexible(
                    flex: (writeFrac * 1000).round().clamp(1, 1000),
                    child: Container(color: Colors.amber.shade400),
                  ),
                if (promptFrac > 0)
                  Flexible(
                    flex: (promptFrac * 1000).round().clamp(1, 1000),
                    child: Container(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _LegendDot(
              color: Colors.green.shade400,
              label: '${l10n.tokenPopupCacheRead} ${_k(cacheRead)}',
            ),
            const SizedBox(width: 10),
            _LegendDot(
              color: Colors.amber.shade400,
              label: '${l10n.tokenPopupCacheWrite} ${_k(cacheWrite)}',
            ),
            const SizedBox(width: 10),
            _LegendDot(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              label: '$uncachedLabel ${_k(promptTokens)}',
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
