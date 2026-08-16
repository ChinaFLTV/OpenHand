part of '../openhand_home_page.dart';

class OpenHandSessionTokenUsageDial extends StatefulWidget {
  const OpenHandSessionTokenUsageDial({
    super.key,
    required this.session,
    required this.statistics,
    this.activeProfile,
    this.claudeStyle = true,
    this.enabled = true,
    this.hydrateSessionStatistics = true,
    this.allowManualCompaction = true,
    this.uncachedPromptTokens,
    this.onCacheHitTrendPointSelected,
  });

  final AiSession session;
  final AiSessionStatistics statistics;
  final AiModelProfile? activeProfile;
  final bool claudeStyle;
  final bool enabled;
  final bool hydrateSessionStatistics;
  final bool allowManualCompaction;
  final int? uncachedPromptTokens;
  final ValueChanged<SessionCacheHitTurnPoint>? onCacheHitTrendPointSelected;

  @override
  State<OpenHandSessionTokenUsageDial> createState() =>
      _OpenHandSessionTokenUsageDialState();
}

const double _cacheWriteThemeColorBlend = 0.45;
const Duration _kTokenDialPopupExitGraceDuration = Duration(milliseconds: 60);

double _tokenDialSummaryCacheHitRatio(
  AiSessionStatistics statistics, {
  required bool claudeStyle,
}) {
  final persisted = statistics.cacheHitRatio;
  if (persisted != null) return finiteUnitInterval(persisted);
  return computeCacheHitRatio(
    promptTokens: _fallbackCacheEligiblePromptTokens(statistics),
    cacheReadTokens: statistics.cacheReadTokens ?? 0,
    cacheWriteTokens: statistics.cacheCreationTokens ?? 0,
    claudeStyle: claudeStyle,
  );
}

int _fallbackCacheEligiblePromptTokens(AiSessionStatistics statistics) {
  final total = math.max(0, statistics.totalPromptTokens ?? 0);
  final first = (statistics.firstPromptTokens ?? 0).clamp(0, total);
  return total - first;
}

Color _cacheWriteThemeColor(ColorScheme colorScheme) {
  return Color.lerp(
    colorScheme.primary,
    colorScheme.surfaceContainerHighest,
    _cacheWriteThemeColorBlend,
  )!;
}

class _OpenHandSessionTokenUsageDialState
    extends State<OpenHandSessionTokenUsageDial>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portalController = OverlayPortalController();
  final GlobalKey _anchorKey = GlobalKey();
  late final AnimationController _transitionController;
  SettingsController? _menuSettingsController;
  DialogAnimationSettings? _menuSettingsSnapshot;
  Timer? _hideTimer;
  bool _showQueued = false;
  bool _touchSheetOpen = false;
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

  /// Web 端支持悬停预览，点击后固定浮窗，再次点击关闭。
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
    _transitionController = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindMenuSettingsController();
    _syncMenuMotionSettings();
  }

  void _bindMenuSettingsController() {
    SettingsController? nextController;
    try {
      nextController = context.read<SettingsController>();
    } on ProviderNotFoundException {
      nextController = null;
    }
    if (identical(_menuSettingsController, nextController)) return;
    _menuSettingsController?.removeListener(_handleMenuSettingsChanged);
    _menuSettingsController = nextController;
    _menuSettingsController?.addListener(_handleMenuSettingsChanged);
  }

  void _handleMenuSettingsChanged() {
    if (!mounted) return;
    final settings = _menuSettings(context);
    if (settings == _menuSettingsSnapshot) return;
    setState(() => _syncMenuMotionSettings(settings));
  }

  void _syncMenuMotionSettings([DialogAnimationSettings? value]) {
    final settings = value ?? _menuSettings(context);
    _menuSettingsSnapshot = settings;
    _transitionController
      ..duration = settings.entranceDuration
      ..reverseDuration = settings.exitDuration;
    if (_transitionController.status == AnimationStatus.forward) {
      _transitionController.forward();
    } else if (_transitionController.status == AnimationStatus.reverse) {
      _transitionController.reverse();
    }
  }

  @override
  void didUpdateWidget(covariant OpenHandSessionTokenUsageDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldClose =
        (!widget.enabled && oldWidget.enabled) ||
        widget.session.id != oldWidget.session.id;
    if (shouldClose &&
        (_showQueued || _portalController.isShowing || _webClickPinned)) {
      _schedulePopupHide();
    }
  }

  @override
  void dispose() {
    _popupGeneration += 1;
    _hideTimer?.cancel();
    _menuSettingsController?.removeListener(_handleMenuSettingsChanged);
    _transitionController.dispose();
    super.dispose();
  }

  void _showPopup() {
    if (!widget.enabled) return;
    if (!_showQueued && !_portalController.isShowing) {
      _hydrateCacheStatisticsOnDemand();
    }
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
    _hideTimer = startSafeTimer(_kTokenDialPopupExitGraceDuration, () {
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
    if (_touchSheetOpen) return;
    _touchSheetOpen = true;
    _hydrateCacheStatisticsOnDemand();
    SessionCacheHitTurnPoint? selectedPoint;
    var dismissQueued = false;
    try {
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
            allowManualCompaction: widget.allowManualCompaction,
            uncachedPromptTokens: widget.uncachedPromptTokens,
            onCacheHitTrendPointSelected: (point) {
              selectedPoint = point;
              if (dismissQueued) return;
              dismissQueued = true;
              unawaited(_dismissTouchPopupAfterPointSelection(sheetContext));
            },
          ),
        ),
      );
    } finally {
      _touchSheetOpen = false;
    }
    if (selectedPoint != null && mounted) {
      widget.onCacheHitTrendPointSelected?.call(selectedPoint!);
    }
  }

  Future<void> _dismissTouchPopupAfterPointSelection(
    BuildContext sheetContext,
  ) async {
    final navigator = Navigator.maybeOf(sheetContext);
    final route = ModalRoute.of(sheetContext);
    if (navigator == null || route == null) return;
    final settings = _dialogSettings(sheetContext);
    final delay = settings.entranceDisabled
        ? Duration.zero
        : settings.entranceDuration + _kTokenDialSelectionDismissBuffer;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!sheetContext.mounted || !navigator.mounted || !route.isCurrent) return;
    await navigator.maybePop();
  }

  void _hydrateCacheStatisticsOnDemand() {
    if (!widget.hydrateSessionStatistics) return;
    unawaited(
      context.read<AiSessionController>().ensureSessionCacheStatisticsHydrated(
        widget.session.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cacheHitRatio = _tokenDialSummaryCacheHitRatio(
      widget.statistics,
      claudeStyle: widget.claudeStyle,
    );
    final showCacheHitRate = shouldShowSessionCacheHitMetrics(
      cacheReadTokens: widget.statistics.cacheReadTokens ?? 0,
      cacheWriteTokens: widget.statistics.cacheCreationTokens ?? 0,
      hasTrendPoints: widget.statistics.cacheHitTrendPoints.isNotEmpty,
      hasCacheUsageTelemetry: widget.statistics.hasCacheUsageTelemetry,
      cacheHitRatio: widget.statistics.cacheHitRatio,
    );
    final contextWindowUsage = AiContextWindowUsage.fromMetadata(
      widget.session.lastPromptMetadata,
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
            allowManualCompaction: widget.allowManualCompaction,
            uncachedPromptTokens: widget.uncachedPromptTokens,
            onCacheHitTrendPointSelected: widget.onCacheHitTrendPointSelected,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) {
          if (widget.enabled && !_useTapSheet) _showPopup();
        },
        onExit: (_) {
          if (widget.enabled && !_useTapSheet && !_webClickPinned) {
            _schedulePopupHide();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: !widget.enabled
              ? null
              : _useTapSheet
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
          child: OpenHandTokenUsageCapsule(
            anchorKey: _anchorKey,
            showCacheHitRate: showCacheHitRate,
            cacheHitRatio: cacheHitRatio,
            contextWindowRatio: contextWindowUsage.ratio,
            contextWindowTooltip:
                '${AppLocalizations.of(context)!.tokenPopupContextWindow} '
                '${contextWindowUsage.percent}%',
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
const Duration _kTokenDialSelectionDismissBuffer = Duration(milliseconds: 80);

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
              child: AnimatedBuilder(
                animation: animation,
                child: builder(context, metrics),
                builder: (context, child) => buildAnimationStyleTransition(
                  animation: animation,
                  settings: settings,
                  profile: OpenHandAnimationTransitionProfile(
                    alignment: metrics.placedAbove
                        ? Alignment.bottomRight
                        : Alignment.topRight,
                  ),
                  child: child!,
                ),
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
    final safeRect = _safePopupRect(overlaySize, MediaQuery.paddingOf(context));
    final anchorRect =
        _anchorRect(anchorKey, context) ??
        Rect.fromLTWH(safeRect.right, safeRect.top, 0, 0);
    final belowHeight =
        safeRect.bottom - anchorRect.bottom - _kTokenDialPopupAnchorGap;
    final aboveHeight =
        anchorRect.top - safeRect.top - _kTokenDialPopupAnchorGap;
    final placedAbove =
        belowHeight < _kTokenDialPopupMinScrollableHeight &&
        aboveHeight > belowHeight;
    final rawHeight = placedAbove ? aboveHeight : belowHeight;
    final maxHeight = rawHeight.isFinite
        ? rawHeight.clamp(0.0, safeRect.height).toDouble()
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

  static Rect? _anchorRect(GlobalKey key, BuildContext overlayContext) {
    final renderObject = key.currentContext?.findRenderObject();
    final overlayObject = Overlay.maybeOf(
      overlayContext,
    )?.context.findRenderObject();
    if (renderObject is! RenderBox ||
        overlayObject is! RenderBox ||
        !renderObject.attached ||
        !overlayObject.attached ||
        !renderObject.hasSize ||
        !overlayObject.hasSize ||
        renderObject.size.isEmpty) {
      return null;
    }
    final size = renderObject.size;
    final topLeft = renderObject.localToGlobal(
      Offset.zero,
      ancestor: overlayObject,
    );
    return topLeft & size;
  }
}

double _clampTokenDialPopupCoordinate(
  double value, {
  required double lower,
  required double upper,
}) {
  if (!value.isFinite) return lower;
  if (upper <= lower) return lower;
  return value.clamp(lower, upper).toDouble();
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
    final left = _clampTokenDialPopupCoordinate(
      rawLeft,
      lower: safe.left,
      upper: safe.right - childSize.width,
    );
    final rawTop = metrics.placedAbove
        ? metrics.anchorRect.top - childSize.height - _kTokenDialPopupAnchorGap
        : metrics.anchorRect.bottom + _kTokenDialPopupAnchorGap;
    final top = _clampTokenDialPopupCoordinate(
      rawTop,
      lower: safe.top,
      upper: safe.bottom - childSize.height,
    );
    return Offset(left, top);
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

/// 将整数格式化为千位分隔形式。
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
  return value < 0 ? '-$buffer' : buffer.toString();
}

/// 悬浮在 Token 统计胶囊下方的结构化详情浮窗。
///
/// 统一展示累计用量、上下文占用、缓存趋势与费用。
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
    this.allowManualCompaction = true,
    this.uncachedPromptTokens,
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
  final bool allowManualCompaction;
  final int? uncachedPromptTokens;
  final ValueChanged<SessionCacheHitTurnPoint>? onCacheHitTrendPointSelected;

  @override
  State<_TokenDialPopup> createState() => _TokenDialPopupState();
}

class _TokenDialPopupState extends State<_TokenDialPopup> {
  final ScrollController _scrollController = ScrollController();
  SessionCacheHitDisplayMode _displayMode =
      SessionCacheHitDisplayMode.excludeExpiredMisses;
  late SessionCacheHitTrend _trend;
  bool _compacting = false;

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

  Future<void> _handleManualCompaction() async {
    if (_compacting) return;
    setState(() => _compacting = true);
    try {
      final result = await _requestSessionManualCompaction(
        context,
        widget.session.id,
      );
      if (!mounted) return;
      final feedback = _manualCompactionFeedback(context, result);
      showOpenHandInfoSnack(context, feedback.message, maxLines: 2);
    } catch (error, stack) {
      silentLog('home_token_dial', '主动压缩', error, stack);
      if (!mounted) return;
      showOpenHandInfoSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '压缩失败：$error',
          en: 'Compaction failed: $error',
        ),
        maxLines: 2,
      );
    } finally {
      if (mounted) setState(() => _compacting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveState = context
        .select<
          AiSessionController,
          ({AiSession? session, AiSendPhase sendPhase})
        >(
          (controller) => (
            session: controller.sessionById(widget.session.id),
            sendPhase: controller.sendPhaseForSession(widget.session.id),
          ),
        );
    final liveSession = liveState.session ?? widget.session;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
    final cacheEligiblePromptTokens = _fallbackCacheEligiblePromptTokens(
      widget.statistics,
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
      liveSession.lastPromptMetadata,
    );
    final contextWindowUsage = AiContextWindowUsage.fromMetadata(
      liveSession.lastPromptMetadata,
    );
    final sectionMotionSettings = openHandMotionSettingsOf(
      context,
      widget.compact
          ? OpenHandMotionSettingsScope.menu
          : OpenHandMotionSettingsScope.dialog,
    );
    final trend = _trend;
    final displayData = trend.displayData(_displayMode);
    final cacheHitRatio = trend.points.isEmpty
        ? widget.cacheHitRatio
        : displayData.averageHitRatio;
    final hasCacheUsageTelemetry =
        widget.statistics.hasCacheUsageTelemetry || trend.points.isNotEmpty;
    final showCacheHitMetrics = shouldShowSessionCacheHitMetrics(
      cacheReadTokens: cacheRead,
      cacheWriteTokens: cacheWrite,
      hasTrendPoints: trend.points.isNotEmpty,
      hasCacheUsageTelemetry: hasCacheUsageTelemetry,
      cacheHitRatio: widget.statistics.cacheHitRatio,
    );
    final fallbackUncachedPromptTokens =
        widget.uncachedPromptTokens ??
        computeUncachedPromptTokens(
          promptTokens: cacheEligiblePromptTokens,
          cacheReadTokens: cacheRead,
          cacheWriteTokens: cacheWrite,
          claudeStyle: widget.claudeStyle,
        );
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
        _TokenStatsPanel(
          title: AppLocalizations.of(context)!.tokenPopupInputHeading,
          icon: Icons.south_west_rounded,
          child: Column(
            children: [
              _PopupRow(
                label: AppLocalizations.of(context)!.tokenPopupPrompt,
                value: promptTokensTotal,
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
            ],
          ),
        ),
        kOpenHandGap10,
        _TokenStatsPanel(
          title: AppLocalizations.of(context)!.tokenPopupOutputHeading,
          icon: Icons.north_east_rounded,
          child: Column(
            children: [
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
            ],
          ),
        ),
        if (webSearchCalls > 0 || webSearchPages > 0) ...[
          kOpenHandGap10,
          _TokenStatsPanel(
            title: AppLocalizations.of(context)!.tokenPopupWebSearchHeading,
            icon: Icons.language_rounded,
            child: Column(
              children: [
                if (webSearchCalls > 0)
                  _PopupRow(
                    label: AppLocalizations.of(
                      context,
                    )!.tokenPopupWebSearchCalls,
                    value: webSearchCalls,
                    keyStyle: keyStyle,
                    valueStyle: accentValueStyle,
                  ),
                if (webSearchPages > 0)
                  _PopupRow(
                    label: AppLocalizations.of(
                      context,
                    )!.tokenPopupWebSearchPages,
                    value: webSearchPages,
                    keyStyle: keyStyle,
                    valueStyle: accentValueStyle,
                  ),
              ],
            ),
          ),
        ],
        kOpenHandGap10,
        _TokenStatsPanel(
          title: AppLocalizations.of(context)!.tokenPopupGrandTotal,
          icon: Icons.donut_large_rounded,
          emphasized: true,
          trailing: RollingText(
            text: _formatThousands(total),
            style:
                theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ) ??
                const TextStyle(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _ContextUsageOverview(
            usage: contextUsage,
            windowUsage: contextWindowUsage,
            showCompact:
                widget.allowManualCompaction &&
                contextWindowUsage.canManuallyCompact &&
                (liveState.sendPhase == AiSendPhase.idle || _compacting),
            compacting: _compacting,
            motionSettings: sectionMotionSettings,
            onCompact: _handleManualCompaction,
          ),
        ),
        _TokenPopupAnimatedSection(
          present: showCacheHitMetrics,
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
              transitionBuilder: (child, animation) => AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, animatedChild) =>
                    buildAnimationStyleTransition(
                      animation: animation,
                      settings: sectionMotionSettings,
                      child: animatedChild!,
                    ),
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
        kOpenHandGap10,
        _TokenStatsPanel(
          title: AppLocalizations.of(context)!.tokenPopupSessionHeading,
          icon: Icons.timeline_rounded,
          child: Column(
            children: [
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
            ],
          ),
        ),
        ..._buildCostSection(
          context: context,
          keyStyle: keyStyle,
          valueStyle: valueStyle,
          colorScheme: colorScheme,
          promptTokens: promptTokensTotal,
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
          borderRadius: kOpenHandBorderRadius14,
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
      kOpenHandGap10,
      _TokenStatsPanel(
        title: l10n.tokenPopupCostHeading,
        icon: Icons.payments_outlined,
        child: Column(
          children: [
            if (breakdown.inputUsd != null)
              _PopupRow.formatted(
                label: l10n.tokenPopupCostInput,
                formattedValue: _formatPopupUsd(breakdown.inputUsd!),
                keyStyle: keyStyle,
                valueStyle: valueStyle,
              ),
            if (breakdown.outputUsd != null)
              _PopupRow.formatted(
                label: l10n.tokenPopupCostOutput,
                formattedValue: _formatPopupUsd(breakdown.outputUsd!),
                keyStyle: keyStyle,
                valueStyle: valueStyle,
              ),
            if (breakdown.cacheReadUsd != null)
              _PopupRow.formatted(
                label: l10n.tokenPopupCostCacheRead,
                formattedValue: _formatPopupUsd(breakdown.cacheReadUsd!),
                keyStyle: keyStyle,
                valueStyle: valueStyle,
              ),
            if (breakdown.cacheWriteUsd != null)
              _PopupRow.formatted(
                label: l10n.tokenPopupCostCacheWrite,
                formattedValue: _formatPopupUsd(breakdown.cacheWriteUsd!),
                keyStyle: keyStyle,
                valueStyle: valueStyle,
              ),
            if (breakdown.totalUsd != null)
              _PopupRow.formatted(
                label: l10n.tokenPopupCostTotal,
                formattedValue: _formatPopupUsd(breakdown.totalUsd!),
                keyStyle: keyStyle?.copyWith(fontWeight: FontWeight.w800),
                valueStyle: valueStyle?.copyWith(color: colorScheme.primary),
              ),
          ],
        ),
      ),
    ];
  }
}

class _TokenStatsPanel extends StatelessWidget {
  const _TokenStatsPanel({
    required this.title,
    required this.icon,
    this.child,
    this.trailing,
    this.emphasized = false,
  });

  final String title;
  final IconData icon;
  final Widget? child;
  final Widget? trailing;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = colorScheme.primary;
    return Container(
      padding: kOpenHandTokenPanelCardPadding,
      decoration: openHandTokenPanelCardDecoration(
        colorScheme,
        emphasized: emphasized,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: emphasized ? 0.15 : 0.10),
                  borderRadius: kOpenHandBorderRadius8,
                ),
                child: Icon(icon, size: 15, color: accent),
              ),
              kOpenHandHGap9,
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) ...[kOpenHandHGap10, trailing!],
            ],
          ),
          if (child != null) ...[kOpenHandGap8, child!],
        ],
      ),
    );
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
  const _ContextUsageOverview({
    required this.usage,
    required this.windowUsage,
    required this.showCompact,
    required this.compacting,
    required this.motionSettings,
    required this.onCompact,
  });

  final AiContextUsageBreakdown? usage;
  final AiContextWindowUsage windowUsage;
  final bool showCompact;
  final bool compacting;
  final DialogAnimationSettings motionSettings;
  final VoidCallback onCompact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final hasData = usage?.hasData ?? false;
    final hasWindowData = windowUsage.windowTokens > 0;
    final items = hasData ? usage!.items : const <AiContextUsageItem>[];
    final activeItems = items
        .where((item) => item.tokenCount > 0)
        .toList(growable: false);
    return Container(
      padding: kOpenHandTokenPanelCardPadding,
      decoration: openHandTokenPanelCardDecoration(colorScheme),
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
                    if (hasData) ...[
                      kOpenHandGap2,
                      Text(
                        usage!.tokenSource == AiContextTokenSource.provider
                            ? l10n.tokenPopupContextMeasured
                            : l10n.tokenPopupContextEstimated,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasData) ...[
                kOpenHandHGap12,
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
          if (hasWindowData) ...[
            kOpenHandGap12,
            _ContextWindowUsageBar(
              usage: windowUsage,
              motionSettings: motionSettings,
            ),
            AnimatedAppearance(
              present: showCompact,
              settings: motionSettings,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: compacting ? null : onCompact,
                    icon: compacting
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.compress_rounded, size: 16),
                    label: Text(
                      compacting
                          ? l10n.tokenPopupCompacting
                          : l10n.tokenPopupCompactNow,
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (hasData) ...[
            kOpenHandGap10,
            ClipRRect(
              borderRadius: kOpenHandPillBorderRadius,
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
            kOpenHandGap10,
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
          ] else ...[
            kOpenHandGap10,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.46,
                ),
                borderRadius: kOpenHandBorderRadius10,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.46),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      l10n.tokenPopupContextEmpty,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContextWindowUsageBar extends StatelessWidget {
  const _ContextWindowUsageBar({
    required this.usage,
    required this.motionSettings,
  });

  final AiContextWindowUsage usage;
  final DialogAnimationSettings motionSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = openHandContextWindowUsageColor(colorScheme, usage.ratio);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(kOpenHandRadius11),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              OpenHandAnimatedContextUsageRing(
                ratio: usage.ratio,
                size: 18,
                strokeWidth: 2.6,
                settings: motionSettings,
              ),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  l10n.tokenPopupContextWindow,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Text(
                '${usage.percent}%',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          kOpenHandGap7,
          SizedBox(
            width: double.infinity,
            height: 7,
            child: ClipRRect(
              borderRadius: kOpenHandPillBorderRadius,
              child: ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: usage.ratio),
                  duration: motionSettings.entranceDuration,
                  curve: motionSettings.curve.curve,
                  builder: (context, value, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value.clamp(0.0, 1.0),
                    child: ColoredBox(color: color),
                  ),
                ),
              ),
            ),
          ),
          kOpenHandGap5,
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${_formatThousands(usage.usedTokens)} / '
              '${_formatThousands(usage.windowTokens)} ${l10n.tokenDialUnit}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
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
        borderRadius: kOpenHandBorderRadius10,
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
              kOpenHandHGap6,
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
              kOpenHandHGap4,
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

/// USD 展示：常规金额保留 2 至 4 位，小额保留 6 位。
String _formatPopupUsd(double value) {
  if (value == 0) return r'$0.0000';
  if (value >= 1) return '\$${value.toStringAsFixed(2)}';
  if (value >= 0.01) return '\$${value.toStringAsFixed(4)}';
  return '\$${value.toStringAsFixed(6)}';
}

class _PopupRow extends StatefulWidget {
  const _PopupRow({
    required this.label,
    required this.value,
    this.keyStyle,
    this.valueStyle,
  }) : formattedValue = null;

  const _PopupRow.formatted({
    required this.label,
    required this.formattedValue,
    this.keyStyle,
    this.valueStyle,
  }) : value = null;

  final String label;
  final int? value;
  final String? formattedValue;
  final TextStyle? keyStyle;
  final TextStyle? valueStyle;

  @override
  State<_PopupRow> createState() => _PopupRowState();
}

class _PopupRowState extends State<_PopupRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.primary;
    return MouseRegion(
      onEnter: (_) {
        if (_hovered) return;
        setState(() => _hovered = true);
      },
      onExit: (_) {
        if (!_hovered) return;
        setState(() => _hovered = false);
      },
      child: AnimatedContainer(
        duration: openHandMotionDuration(context, kOpenHandMotion180,
        ),
        curve: kOpenHandEntranceCurve,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _hovered
              ? accent.withValues(alpha: 0.10)
              : colorScheme.surface.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(kOpenHandRadius9),
          border: Border.all(
            color: _hovered
                ? accent.withValues(alpha: 0.22)
                : colorScheme.outlineVariant.withValues(alpha: 0.36),
          ),
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
            kOpenHandHGap8,
            if (widget.formattedValue case final formattedValue?)
              Text(formattedValue, style: widget.valueStyle)
            else
              RollingText(
                text: _formatThousands(widget.value!),
                style: widget.valueStyle ?? const TextStyle(),
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
    final readFrac = total == 0
        ? finiteUnitInterval(cacheHitRatio)
        : cacheRead / total;
    final writeFrac = total == 0 ? 0.0 : cacheWrite / total;
    final uncachedLabel = l10n.tokenPopupUncached;
    final readColor = colorScheme.primary;
    final writeColor = _cacheWriteThemeColor(colorScheme);
    final missColor = colorScheme.outlineVariant.withValues(alpha: 0.62);
    return Container(
      padding: kOpenHandTokenPanelCardPadding,
      decoration: openHandTokenPanelCardDecoration(colorScheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.sessMetaCacheHitTrend,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${l10n.sessMetaCacheHitAvg}: $hitPercent%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          kOpenHandGap10,
          ClipRRect(
            borderRadius: kOpenHandPillBorderRadius,
            child: ColoredBox(
              color: missColor,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: readFrac + writeFrac),
                duration: openHandMotionDuration(
                  context,
                  kOpenHandMotion520,
                ),
                curve: kOpenHandEntranceCurve,
                builder: (context, cached, _) => TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: readFrac),
                  duration: openHandMotionDuration(
                    context,
                    kOpenHandMotion520,
                  ),
                  curve: kOpenHandEntranceCurve,
                  builder: (context, read, _) => SizedBox(
                    height: 8,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: cached.clamp(0.0, 1.0),
                            heightFactor: 1,
                            child: ColoredBox(color: writeColor),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: read.clamp(0.0, 1.0),
                            heightFactor: 1,
                            child: ColoredBox(color: readColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          kOpenHandGap7,
          Wrap(
            spacing: 10,
            runSpacing: 5,
            children: [
              _LegendDot(
                color: readColor,
                label: '${l10n.tokenPopupCacheRead} ${_k(cacheRead)}',
              ),
              _LegendDot(
                color: writeColor,
                label: '${l10n.tokenPopupCacheWrite} ${_k(cacheWrite)}',
              ),
              _LegendDot(
                color: missColor,
                label: '$uncachedLabel ${_k(promptTokens)}',
              ),
            ],
          ),
        ],
      ),
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
        kOpenHandHGap3,
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
