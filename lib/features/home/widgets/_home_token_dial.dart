part of '../openhand_home_page.dart';

class _TokenDial extends StatefulWidget {
  const _TokenDial({
    required this.session,
    required this.statistics,
    this.activeProfile,
    this.claudeStyle = true,
    this.onCacheHitTrendPointSelected,
  });

  final AiSession session;
  final AiSessionStatistics statistics;
  final AiModelProfile? activeProfile;
  final bool claudeStyle;
  final ValueChanged<SessionCacheHitTurnPoint>? onCacheHitTrendPointSelected;

  int get totalTokens => statistics.totalTokens ?? 0;
  int? get cacheReadTokens => statistics.cacheReadTokens;
  int? get cacheCreationTokens => statistics.cacheCreationTokens;

  @override
  State<_TokenDial> createState() => _TokenDialState();
}

const double _cacheWriteThemeColorBlend = 0.45;

double _tokenDialSummaryCacheHitRatio(
  AiSessionStatistics statistics, {
  required bool claudeStyle,
}) {
  final persisted = statistics.cacheHitRatio;
  if (persisted != null) return finiteUnitInterval(persisted);
  return computeCacheHitRatio(
    promptTokens: statistics.totalPromptTokens ?? 0,
    cacheReadTokens: statistics.cacheReadTokens ?? 0,
    cacheWriteTokens: statistics.cacheCreationTokens ?? 0,
    claudeStyle: claudeStyle,
  );
}

Color _cacheWriteThemeColor(ColorScheme colorScheme) {
  return Color.lerp(
    colorScheme.primary,
    colorScheme.surfaceContainerHighest,
    _cacheWriteThemeColorBlend,
  )!;
}

int _cacheHitBarFlex(double weight) {
  return (weight * 1000).round().clamp(1, 1000);
}

class _TokenDialState extends State<_TokenDial>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portalController = OverlayPortalController();
  final GlobalKey _anchorKey = GlobalKey();
  late final AnimationController _transitionController;
  Timer? _hideTimer;
  bool _showQueued = false;
  int _popupGeneration = 0;

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

  DialogAnimationSettings _menuSettings(BuildContext context) {
    return openHandMotionSettingsOf(context, OpenHandMotionSettingsScope.menu);
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
    final settings = _menuSettings(context);
    _transitionController
      ..duration = settings.entranceDuration
      ..reverseDuration = settings.exitDuration;
  }

  @override
  void dispose() {
    _popupGeneration += 1;
    _hideTimer?.cancel();
    _transitionController.dispose();
    super.dispose();
  }

  void _showPopup() {
    _hydrateCacheStatisticsOnDemand();
    _hideTimer?.cancel();
    _showQueued = true;
    final generation = ++_popupGeneration;
    _runAfterFrame(() {
      if (!_showQueued || generation != _popupGeneration) return;
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
    final generation = ++_popupGeneration;
    _hideTimer = startSafeTimer(const Duration(milliseconds: 60), () {
      _runAfterFrame(() async {
        try {
          await _transitionController.reverse().orCancel;
        } on TickerCanceled {
          return;
        }
        if (!mounted || _showQueued || generation != _popupGeneration) {
          return;
        }
        if (_portalController.isShowing) {
          _portalController.hide();
        }
      });
    });
  }

  Future<void> _showTouchPopupSheet() async {
    _hydrateCacheStatisticsOnDemand();
    SessionCacheHitTurnPoint? selectedPoint;
    var dismissQueued = false;
    await showAnimatedModalSheet<void>(
      context: context,
      settings: _dialogSettings(context),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: _TokenDialPopup(
          session: widget.session,
          statistics: widget.statistics,
          activeProfile: widget.activeProfile,
          claudeStyle: widget.claudeStyle,
          cacheHitRatio: _tokenDialSummaryCacheHitRatio(
            widget.statistics,
            claudeStyle: widget.claudeStyle,
          ),
          compact: false,
          onCacheHitTrendPointSelected: (point) {
            selectedPoint = point;
            if (dismissQueued) return;
            dismissQueued = true;
            unawaited(_dismissTouchPopupAfterPointSelection(sheetContext));
          },
        ),
      ),
    );
    if (selectedPoint != null && mounted) {
      widget.onCacheHitTrendPointSelected?.call(selectedPoint!);
    }
  }

  Future<void> _dismissTouchPopupAfterPointSelection(
    BuildContext sheetContext,
  ) async {
    final settings = _dialogSettings(sheetContext);
    final delay = settings.entranceDisabled
        ? Duration.zero
        : settings.entranceDuration + const Duration(milliseconds: 80);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!sheetContext.mounted) return;
    await Navigator.of(sheetContext).maybePop();
  }

  void _hydrateCacheStatisticsOnDemand() {
    unawaited(
      context.read<AiSessionController>().ensureSessionCacheStatisticsHydrated(
        widget.session.id,
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
    final cacheHitRatio = _tokenDialSummaryCacheHitRatio(
      widget.statistics,
      claudeStyle: widget.claudeStyle,
    );
    return OverlayPortal(
      controller: _portalController,
      overlayChildBuilder: (overlayContext) {
        return _TokenDialPopupOverlay(
          anchorKey: _anchorKey,
          animation: _transitionController,
          settings: _menuSettings(overlayContext),
          onEnter: _showPopup,
          onExit: () {
            if (!_webClickPinned) _schedulePopupHide();
          },
          builder: (context, metrics) => _TokenDialPopup(
            session: widget.session,
            statistics: widget.statistics,
            activeProfile: widget.activeProfile,
            claudeStyle: widget.claudeStyle,
            cacheHitRatio: cacheHitRatio,
            maxHeight: metrics.maxHeight,
            minWidth: metrics.minWidth,
            maxWidth: metrics.maxWidth,
            onCacheHitTrendPointSelected: widget.onCacheHitTrendPointSelected,
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
                  ? colorScheme.primary.withValues(alpha: 0.08)
                  : colorScheme.surfaceContainerHighest,
              borderRadius: _borderRadius999,
              border: Border.all(
                color: hasCache
                    ? colorScheme.primary.withValues(alpha: 0.38)
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
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                if (hasCache) ...[
                  _CacheSavingsBadge(percent: cacheHitRatio),
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
    this.onCacheHitTrendPointSelected,
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
  final ValueChanged<SessionCacheHitTurnPoint>? onCacheHitTrendPointSelected;

  @override
  State<_TokenDialPopup> createState() => _TokenDialPopupState();
}

class _TokenDialPopupState extends State<_TokenDialPopup> {
  final ScrollController _scrollController = ScrollController();
  SessionCacheHitDisplayMode _displayMode =
      SessionCacheHitDisplayMode.excludeExpiredMisses;
  late SessionCacheHitTrend _trend;

  @override
  void initState() {
    super.initState();
    _trend = _buildTrend();
  }

  @override
  void didUpdateWidget(covariant _TokenDialPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id ||
        !identical(oldWidget.session.messages, widget.session.messages) ||
        !identical(oldWidget.statistics, widget.statistics) ||
        oldWidget.claudeStyle != widget.claudeStyle) {
      _trend = _buildTrend();
    }
  }

  SessionCacheHitTrend _buildTrend() {
    return SessionCacheHitTrend.fromStatisticsOrSession(
      widget.session,
      claudeStyle: widget.claudeStyle,
    );
  }

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
    final accentValueStyle = valueStyle?.copyWith(color: colorScheme.primary);
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
    final audioInput = widget.statistics.audioInputTokens ?? 0;
    final imageInput = widget.statistics.imageInputTokens ?? 0;
    final videoInput = widget.statistics.videoInputTokens ?? 0;
    final webSearchCalls = widget.statistics.webSearchToolUsage ?? 0;
    final webSearchPages = widget.statistics.webSearchPageUsage ?? 0;
    final total = widget.statistics.totalTokens ?? 0;
    final contextUsage = AiContextUsageBreakdown.fromMetadata(
      widget.session.lastPromptMetadata,
    );
    final sectionMotionSettings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.menu,
    );
    final trend = _trend;
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
        if (audioInput > 0)
          _PopupRow(
            label: AppLocalizations.of(context)!.tokenPopupAudioInput,
            value: audioInput,
            keyStyle: keyStyle,
            valueStyle: valueStyle,
          ),
        if (imageInput > 0)
          _PopupRow(
            label: AppLocalizations.of(context)!.tokenPopupImageInput,
            value: imageInput,
            keyStyle: keyStyle,
            valueStyle: valueStyle,
          ),
        if (videoInput > 0)
          _PopupRow(
            label: AppLocalizations.of(context)!.tokenPopupVideoInput,
            value: videoInput,
            keyStyle: keyStyle,
            valueStyle: valueStyle,
          ),
        if (hasCacheUsageTelemetry) ...[
          _PopupRow(
            label: AppLocalizations.of(context)!.tokenPopupCacheRead,
            value: cacheRead,
            keyStyle: keyStyle,
            valueStyle: accentValueStyle,
          ),
          _PopupRow(
            label: AppLocalizations.of(context)!.tokenPopupCacheWrite,
            value: cacheWrite,
            keyStyle: keyStyle,
            valueStyle: accentValueStyle,
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
            valueStyle: valueStyle,
          ),
        if (webSearchCalls > 0 || webSearchPages > 0) ...[
          const SizedBox(height: 10),
          Text(
            AppLocalizations.of(
              context,
            )!.tokenPopupWebSearchHeading.toUpperCase(),
            style: headStyle,
          ),
          const SizedBox(height: 6),
          if (webSearchCalls > 0)
            _PopupRow(
              label: AppLocalizations.of(context)!.tokenPopupWebSearchCalls,
              value: webSearchCalls,
              keyStyle: keyStyle,
              valueStyle: accentValueStyle,
            ),
          if (webSearchPages > 0)
            _PopupRow(
              label: AppLocalizations.of(context)!.tokenPopupWebSearchPages,
              value: webSearchPages,
              keyStyle: keyStyle,
              valueStyle: accentValueStyle,
            ),
        ],
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
            valueStyle: accentValueStyle,
          ),
          const SizedBox(height: 6),
          _CacheHitBar(
            ratio: cacheHitRatio,
            cacheRead: displayData.cacheReadTokens,
            cacheWrite: displayData.cacheWriteTokens,
            prompt: cacheBarPromptTokens,
          ),
        ],
        _TokenPopupAnimatedSection(
          present: contextUsage?.hasData ?? false,
          settings: sectionMotionSettings,
          child: _ContextUsageOverview(usage: contextUsage),
        ),
        _TokenPopupAnimatedSection(
          present: trend.points.isNotEmpty || cacheRead > 0,
          settings: sectionMotionSettings,
          child: AnimatedSize(
            alignment: Alignment.topCenter,
            duration: sectionMotionSettings.entranceDuration,
            reverseDuration: sectionMotionSettings.exitDuration,
            curve: trend.points.isNotEmpty
                ? sectionMotionSettings.curve.curve
                : sectionMotionSettings.curve.reverseCurve,
            child: AnimatedSwitcher(
              duration: sectionMotionSettings.entranceDuration,
              reverseDuration: sectionMotionSettings.exitDuration,
              transitionBuilder: (child, animation) =>
                  buildAnimationStyleTransition(
                    animation: animation,
                    settings: sectionMotionSettings,
                    child: child,
                  ),
              layoutBuilder: (currentChild, previousChildren) =>
                  buildCollisionSafeAnimatedSwitcherLayout(
                    currentChild,
                    previousChildren,
                    alignment: Alignment.topCenter,
                    sizeToCurrentChild: true,
                  ),
              child: trend.points.isNotEmpty
                  ? TokenPopupCacheHitTrendChart(
                      key: const ValueKey<bool>(true),
                      trend: trend,
                      displayMode: _displayMode,
                      onDisplayModeChanged: (mode) {
                        if (_displayMode == mode) return;
                        setState(() {
                          _displayMode = mode;
                        });
                      },
                      onPointSelected: widget.onCacheHitTrendPointSelected,
                      height: widget.compact ? 176 : 220,
                    )
                  : _CompactCacheHitSparkline(
                      key: const ValueKey<bool>(false),
                      cacheHitRatio: cacheHitRatio,
                      cacheRead: cacheRead,
                      cacheWrite: cacheWrite,
                      promptTokens: cacheBarPromptTokens,
                    ),
            ),
          ),
        ),
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
              color: colorScheme.shadow.withValues(alpha: 0.10),
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
          valueStyle: valueStyle,
        ),
      if (breakdown.cacheWriteUsd != null)
        _CostPopupRow(
          label: l10n.tokenPopupCostCacheWrite,
          usd: breakdown.cacheWriteUsd!,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
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

/// 统一承接 Token 浮窗板块的进退场与高度折叠，隐藏期间保留退场内容。
class _TokenPopupAnimatedSection extends StatefulWidget {
  const _TokenPopupAnimatedSection({
    required this.present,
    required this.settings,
    required this.child,
  });

  final bool present;
  final DialogAnimationSettings settings;
  final Widget child;

  @override
  State<_TokenPopupAnimatedSection> createState() =>
      _TokenPopupAnimatedSectionState();
}

class _TokenPopupAnimatedSectionState
    extends State<_TokenPopupAnimatedSection> {
  Widget? _retainedChild;

  @override
  void initState() {
    super.initState();
    if (widget.present) _retainedChild = widget.child;
  }

  @override
  void didUpdateWidget(covariant _TokenPopupAnimatedSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.present) _retainedChild = widget.child;
  }

  void _releaseHiddenChild() {
    if (widget.present || _retainedChild == null) return;
    setState(() => _retainedChild = null);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedAppearance(
      present: widget.present,
      settings: widget.settings,
      onDismissed: _releaseHiddenChild,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: _retainedChild ?? const SizedBox.shrink(),
      ),
    );
  }
}

class _ContextUsageOverview extends StatelessWidget {
  const _ContextUsageOverview({required this.usage});

  final AiContextUsageBreakdown? usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final hasData = usage?.hasData ?? false;
    final items = hasData ? usage!.items : const <AiContextUsageItem>[];
    final activeItems = items
        .where((item) => item.tokenCount > 0)
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tokenPopupContextOverview,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasData
                          ? usage!.tokenSource == AiContextTokenSource.provider
                                ? l10n.tokenPopupContextMeasured
                                : l10n.tokenPopupContextEstimated
                          : l10n.tokenPopupContextEmpty,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasData) ...[
                const SizedBox(width: 12),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _formatThousands(usage!.totalTokens),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: colorScheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      TextSpan(
                        text: ' ${l10n.tokenDialUnit}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.end,
                ),
              ],
            ],
          ),
          if (hasData) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: _borderRadius999,
              child: SizedBox(
                height: 7,
                child: Row(
                  children: activeItems
                      .map(
                        (item) => Expanded(
                          flex: _contextUsageFlex(
                            item.tokenCount,
                            usage!.totalTokens,
                          ),
                          child: ColoredBox(
                            color: _contextUsageColor(
                              colorScheme,
                              item.category,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 360 ? 3 : 2;
                const gap = 8.0;
                final itemWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: items
                      .map(
                        (item) => SizedBox(
                          width: itemWidth,
                          child: _ContextUsageTile(
                            item: item,
                            totalTokens: usage!.totalTokens,
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ContextUsageTile extends StatelessWidget {
  const _ContextUsageTile({required this.item, required this.totalTokens});

  final AiContextUsageItem item;
  final int totalTokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _contextUsageColor(colorScheme, item.category);
    final active = item.tokenCount > 0;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: active ? 0.09 : 0.035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: active ? 0.24 : 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _contextUsageLabel(
                    AppLocalizations.of(context)!,
                    item.category,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: active
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  _formatThousands(item.tokenCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _contextUsagePercent(item.tokenCount, totalTokens),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

int _contextUsageFlex(int tokens, int totalTokens) {
  if (tokens <= 0 || totalTokens <= 0) return 1;
  return (tokens / totalTokens * 1000).round().clamp(1, 1000).toInt();
}

String _contextUsagePercent(int tokens, int totalTokens) {
  if (tokens <= 0 || totalTokens <= 0) return '0%';
  final value = tokens / totalTokens * 100;
  if (value < 0.1) return '<0.1%';
  return value >= 10 ? '${value.round()}%' : '${value.toStringAsFixed(1)}%';
}

String _contextUsageLabel(
  AppLocalizations l10n,
  AiContextUsageCategory category,
) {
  return switch (category) {
    AiContextUsageCategory.systemPrompt => l10n.tokenPopupContextSystemPrompt,
    AiContextUsageCategory.builtinTools => l10n.tokenPopupContextBuiltinTools,
    AiContextUsageCategory.mcp => l10n.tokenPopupContextMcp,
    AiContextUsageCategory.instructions => l10n.tokenPopupContextInstructions,
    AiContextUsageCategory.memory => l10n.tokenPopupContextMemory,
    AiContextUsageCategory.skills => l10n.tokenPopupContextSkills,
    AiContextUsageCategory.hooks => l10n.tokenPopupContextHooks,
    AiContextUsageCategory.conversation => l10n.tokenPopupContextConversation,
    AiContextUsageCategory.runtime => l10n.tokenPopupContextRuntime,
  };
}

Color _contextUsageColor(
  ColorScheme colorScheme,
  AiContextUsageCategory category,
) {
  return switch (category) {
    AiContextUsageCategory.systemPrompt => colorScheme.primary,
    AiContextUsageCategory.builtinTools => colorScheme.secondary,
    AiContextUsageCategory.mcp => colorScheme.tertiary,
    AiContextUsageCategory.instructions => Color.lerp(
      colorScheme.primary,
      colorScheme.tertiary,
      0.42,
    )!,
    AiContextUsageCategory.memory => Color.lerp(
      colorScheme.error,
      colorScheme.tertiary,
      0.58,
    )!,
    AiContextUsageCategory.skills => Color.lerp(
      colorScheme.secondary,
      colorScheme.tertiary,
      0.55,
    )!,
    AiContextUsageCategory.hooks => Color.lerp(
      colorScheme.error,
      colorScheme.primary,
      0.44,
    )!,
    AiContextUsageCategory.conversation => Color.lerp(
      colorScheme.primary,
      colorScheme.secondary,
      0.58,
    )!,
    AiContextUsageCategory.runtime => colorScheme.outline,
  };
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
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.keyStyle,
              ),
            ),
            const SizedBox(width: 8),
            Text(_format(widget.usd), style: widget.valueStyle),
          ],
        ),
      ),
    );
  }
}

/// TopBar Token 胶囊里的常驻「缓存收益」徽标：闪电图标 + 百分比。
/// 跟随当前主题主色，避免在不同主题下出现割裂的固定绿色。
class _CacheSavingsBadge extends StatelessWidget {
  const _CacheSavingsBadge({required this.percent});

  /// 0..1 之间的命中率。
  final double percent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 0 命中时弱化显示；命中越高强调越强。
    final clamped = finiteUnitInterval(percent);
    final intensity = (0.5 + clamped * 0.5).clamp(0.5, 1.0);
    final fg = colorScheme.primary;
    final bg = colorScheme.primary.withValues(alpha: 0.08 + clamped * 0.12);
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

/// 缓存命中比例可视化条：左侧主色 = cache_read（命中），中间浅主色 =
/// cache_creation（写入），右侧中性底色 = 未缓存的 prompt。
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
    final readColor = colorScheme.primary;
    final writeColor = _cacheWriteThemeColor(colorScheme);
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
                flex: _cacheHitBarFlex(readWeight),
                child: Container(
                  color: readColor.withValues(
                    alpha: clampUnitInterval(0.85 * intensify),
                  ),
                ),
              ),
            if (writeWeight > 0)
              Expanded(
                flex: _cacheHitBarFlex(writeWeight),
                child: Container(
                  color: writeColor.withValues(
                    alpha: clampUnitInterval(0.78 * intensify),
                  ),
                ),
              ),
            if (promptWeight > 0)
              Expanded(
                flex: _cacheHitBarFlex(promptWeight),
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
  });

  final String label;
  final int value;
  final String? suffix;
  final TextStyle? keyStyle;
  final TextStyle? valueStyle;

  @override
  State<_PopupRow> createState() => _PopupRowState();
}

class _PopupRowState extends State<_PopupRow> {
  bool _hovered = false;

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
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: widget.keyStyle,
              ),
            ),
            const SizedBox(width: 8),
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
    super.key,
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
    final uncachedLabel = l10n.tokenPopupUncached;
    final readColor = colorScheme.primary;
    final writeColor = _cacheWriteThemeColor(colorScheme);
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
                color: readColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${l10n.tokenPopupCacheHit} $hitPercent%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
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
                    child: Container(color: readColor.withValues(alpha: 0.72)),
                  ),
                if (writeFrac > 0)
                  Flexible(
                    flex: (writeFrac * 1000).round().clamp(1, 1000),
                    child: Container(color: writeColor.withValues(alpha: 0.72)),
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
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            _LegendDot(
              color: readColor.withValues(alpha: 0.72),
              label: '${l10n.tokenPopupCacheRead} ${_k(cacheRead)}',
            ),
            _LegendDot(
              color: writeColor.withValues(alpha: 0.72),
              label: '${l10n.tokenPopupCacheWrite} ${_k(cacheWrite)}',
            ),
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
