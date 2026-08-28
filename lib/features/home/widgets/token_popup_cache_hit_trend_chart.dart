import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../app/model/dialog_animation_settings.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_token_usage_capsule.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/session_cache_hit_trend.dart';

const Curve _tokenPopupCacheHitTrendEntranceCurve = kOpenHandSwitchInCurve;
const Duration _tokenPopupCacheHitTrendEntranceDuration = Duration(
  milliseconds: 560,
);
const Duration _tokenPopupCacheHitModeChipDuration = Duration(
  milliseconds: 220,
);
const double _tokenPopupCacheHitZoomInScale = 1.12;
const double _tokenPopupCacheHitZoomOutScale = 0.88;
const double _tokenPopupCacheHitScaleEpsilon = 0.001;
const double _tokenPopupCacheHitPanEpsilon = 0.01;
const double _tokenPopupCacheHitTooltipGap = 12;
const double _tokenPopupCacheHitTooltipWidth = 132;
const double _tokenPopupCacheHitFirstRequestTooltipWidth = 148;
const double _tokenPopupCacheHitReuseTooltipWidth = 172;
const double _tokenPopupCacheHitTooltipHeight = 46;
const double _tokenPopupCacheHitFirstRequestTooltipHeight = 58;
const double _tokenPopupCacheHitReuseTooltipHeight = 60;

String _compactTokenCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '${(value / 1000000).toStringAsFixed(1)}m';
}

double _clampTokenPopupOverlayOrigin({
  required double desired,
  required double minimum,
  required double maximum,
}) {
  return desired.clamp(minimum, math.max(minimum, maximum)).toDouble();
}

double _tokenPopupCacheHitTrendAnimationProgress(double t) {
  final clamped = clampUnitInterval(t);
  return clampUnitInterval(
    _tokenPopupCacheHitTrendEntranceCurve.transform(clamped),
  );
}

List<Offset> _tokenPopupCacheHitTrendAnimatedPolyline({
  required List<double> ratios,
  required Rect chartRect,
  required double progress,
}) {
  if (ratios.isEmpty) return const <Offset>[];
  final easedProgress = _tokenPopupCacheHitTrendAnimationProgress(progress);
  final visibleCount = (ratios.length * easedProgress).clamp(
    1.0,
    ratios.length.toDouble(),
  );
  final fullCount = visibleCount.floor();
  final partial = visibleCount - fullCount;
  final points = <Offset>[];
  final stepX = ratios.length <= 1
      ? chartRect.width
      : chartRect.width / (ratios.length - 1);

  Offset pointFor(int index) {
    final ratio = clampUnitInterval(ratios[index]);
    return Offset(
      ratios.length <= 1 ? chartRect.center.dx : chartRect.left + stepX * index,
      chartRect.bottom - chartRect.height * ratio,
    );
  }

  for (var i = 0; i < fullCount && i < ratios.length; i++) {
    points.add(pointFor(i));
  }
  if (partial > 0 && fullCount < ratios.length && fullCount >= 1) {
    final start = pointFor(fullCount - 1);
    final end = pointFor(fullCount);
    points.add(
      Offset(
        start.dx + (end.dx - start.dx) * partial,
        start.dy + (end.dy - start.dy) * partial,
      ),
    );
  }
  if (points.isEmpty) {
    points.add(pointFor(0));
  }
  return points;
}

void _drawTokenPopupCacheHitTrendDashedLine(
  Canvas canvas,
  Offset start,
  Offset end,
  Paint paint,
) {
  const dash = 4.0;
  const gap = 4.0;
  final total = end.dx - start.dx;
  var x = 0.0;
  while (x < total) {
    final next = math.min(x + dash, total);
    canvas.drawLine(
      Offset(start.dx + x, start.dy),
      Offset(start.dx + next, end.dy),
      paint,
    );
    x += dash + gap;
  }
}

String _cacheHitExclusionHint(
  AppLocalizations l10n,
  SessionCacheHitDisplayData displayData,
) {
  if (displayData.mode == SessionCacheHitDisplayMode.includeExpiredMisses ||
      displayData.excludedExpiredMissCount <= 0) {
    return '';
  }
  return l10n.tokenPopupExcludedRounds(displayData.excludedPointCount);
}

bool _sameCacheHitTrendPointIdentity(
  List<SessionCacheHitTurnPoint> previous,
  List<SessionCacheHitTurnPoint> current,
) {
  if (identical(previous, current)) return true;
  if (previous.length != current.length) return false;
  for (var index = 0; index < previous.length; index += 1) {
    final left = previous[index];
    final right = current[index];
    if (left.turnIndex != right.turnIndex ||
        left.starterMessageId != right.starterMessageId) {
      return false;
    }
  }
  return true;
}

SessionCacheHitViewport _fullCacheHitViewport(
  SessionCacheHitTrend trend,
  SessionCacheHitDisplayMode mode,
) {
  return SessionCacheHitViewport.full(
    trend.displayData(mode).trend.points.length,
  );
}

class TokenPopupCacheHitTrendChart extends StatefulWidget {
  const TokenPopupCacheHitTrendChart({
    super.key,
    required this.trend,
    this.height = 168,
    this.displayMode = SessionCacheHitDisplayMode.excludeExpiredMisses,
    this.onDisplayModeChanged,
    this.onPointSelected,
  });

  final SessionCacheHitTrend trend;
  final double height;
  final SessionCacheHitDisplayMode displayMode;
  final ValueChanged<SessionCacheHitDisplayMode>? onDisplayModeChanged;

  /// Called after a concrete trend point is tapped/clicked. The point keeps
  /// the round starter message id so callers can reveal the matching turn.
  final ValueChanged<SessionCacheHitTurnPoint>? onPointSelected;

  @override
  State<TokenPopupCacheHitTrendChart> createState() =>
      _TokenPopupCacheHitTrendChartState();
}

// Uses two AnimationControllers: the chart entrance and the hover tooltip.
class _TokenPopupCacheHitTrendChartState
    extends State<TokenPopupCacheHitTrendChart>
    with TickerProviderStateMixin {
  late SessionCacheHitViewport _viewport;
  late final AnimationController _controller;
  // hover 状态专用的进退场控制器：
  // - 悬停进入：0 → 1（沿用全局 DialogAnimationSettings）；
  // - 悬停退出：1 → 0（同一曲线的 reverse）；
  // - 移动到不同点：data 立即更新但 controller 保持 1.0，不重启。
  late final AnimationController _hoverController;
  // 缓存上一次应用的 hover 设置，用于跳过重复同步，并识别需要按当前
  // 进度重启的方向动画。
  DialogAnimationSettings? _lastAppliedHoverSettings;
  int _hoverMotionGeneration = 0;
  double _gestureAppliedScale = 1;
  int? _hoveredPointIndex;
  int? _displayedPointIndex;

  @override
  void initState() {
    super.initState();
    _viewport = _fullCacheHitViewport(widget.trend, widget.displayMode);
    _controller = AnimationController(
      vsync: this,
      duration: _tokenPopupCacheHitTrendEntranceDuration,
    )..forward();
    _hoverController = AnimationController(
      vsync: this,
      duration: Duration.zero,
      reverseDuration: Duration.zero,
      value: 0.0,
    )..addStatusListener(_handleHoverAnimationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!openHandTickerMotionEnabled(context) && !_controller.isCompleted) {
      _controller
        ..stop()
        ..value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant TokenPopupCacheHitTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousVisiblePoints = oldWidget.trend
        .displayData(oldWidget.displayMode)
        .trend
        .points;
    final currentVisiblePoints = widget.trend
        .displayData(widget.displayMode)
        .trend
        .points;
    final viewportSourceChanged =
        oldWidget.displayMode != widget.displayMode ||
        !_sameCacheHitTrendPointIdentity(
          previousVisiblePoints,
          currentVisiblePoints,
        );
    if (viewportSourceChanged) {
      _viewport = _fullCacheHitViewport(widget.trend, widget.displayMode);
      _controller.reset();
      if (openHandTickerMotionEnabled(context)) {
        _controller.forward();
      } else {
        _controller.value = 1.0;
      }
    }
    if (viewportSourceChanged) {
      // 数据集或展示口径换新时立刻清理浮窗。即使点数未变，旧索引也
      // 可能已指向另一轮数据；继续展示会把旧命中态套到新数据上。
      _resetHoverTooltip();
    }
  }

  @override
  void dispose() {
    _hoverController.removeStatusListener(_handleHoverAnimationStatus);
    _controller.dispose();
    _hoverController.dispose();
    super.dispose();
  }

  void _zoom(double anchor, double scale) {
    _resetHoverTooltip();
    setState(() {
      _viewport = _viewport.zoomAround(anchor: anchor, scale: scale);
    });
  }

  /// Hover tooltip follows the global menu motion in both directions.
  DialogAnimationSettings _hoverSettingsFor(BuildContext context) {
    return openHandMotionSettingsOf(context, OpenHandMotionSettingsScope.menu);
  }

  void _handleHoverAnimationStatus(AnimationStatus status) {
    if (!mounted ||
        status != AnimationStatus.dismissed ||
        _hoveredPointIndex != null ||
        _displayedPointIndex == null) {
      return;
    }
    setState(() => _displayedPointIndex = null);
  }

  void _hideHoverTooltip() {
    if (_hoveredPointIndex == null) return;
    _hoverMotionGeneration += 1;
    setState(() => _hoveredPointIndex = null);
    _hoverController.reverse();
  }

  void _resetHoverTooltip() {
    _hoverMotionGeneration += 1;
    _hoveredPointIndex = null;
    _displayedPointIndex = null;
    _hoverController
      ..stop()
      ..value = 0.0;
    _lastAppliedHoverSettings = null;
  }

  void _applyHoverSettings(DialogAnimationSettings settings) {
    final previous = _lastAppliedHoverSettings;
    if (previous == settings) return;
    _hoverController
      ..duration = settings.entranceDuration
      ..reverseDuration = settings.exitDuration;
    _lastAppliedHoverSettings = settings;
    if (previous == null ||
        (_hoveredPointIndex == null && _displayedPointIndex == null)) {
      return;
    }
    final activeDirectionTimingChanged = _hoveredPointIndex != null
        ? previous.entranceDuration != settings.entranceDuration
        : previous.exitDuration != settings.exitDuration;
    if (!activeDirectionTimingChanged) return;
    final generation = ++_hoverMotionGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _hoverMotionGeneration) return;
      if (_hoveredPointIndex != null) {
        if (settings.entranceDisabled) {
          _hoverController
            ..stop()
            ..value = 1.0;
        } else if (!_hoverController.isCompleted) {
          _hoverController.forward();
        }
      } else if (_displayedPointIndex != null) {
        if (settings.exitDisabled) {
          _hoverController
            ..stop()
            ..value = 0.0;
        } else if (!_hoverController.isDismissed) {
          _hoverController.reverse();
        }
      }
    });
  }

  void _pan(double deltaPoints) {
    _resetHoverTooltip();
    setState(() {
      _viewport = _viewport.panBy(deltaPoints);
    });
  }

  void _selectPoint({
    required int index,
    required List<SessionCacheHitTurnPoint> visiblePoints,
  }) {
    if (index < 0 || index >= visiblePoints.length) return;
    final point = visiblePoints[index];
    final wasHovering = _hoveredPointIndex != null;
    setState(() {
      _hoveredPointIndex = index;
      _displayedPointIndex = index;
    });
    if (!wasHovering) {
      _hoverMotionGeneration += 1;
      _hoverController.forward();
    }
    widget.onPointSelected?.call(point);
  }

  int? _pointIndexAtPosition({
    required Offset position,
    required Rect chartRect,
    required List<SessionCacheHitTurnPoint> visiblePoints,
  }) {
    if (visiblePoints.isEmpty || !chartRect.contains(position)) return null;
    final step = visiblePoints.length <= 1
        ? 0.0
        : chartRect.width / (visiblePoints.length - 1);
    var nearest = 0;
    var nearestDistance = double.infinity;
    for (var index = 0; index < visiblePoints.length; index += 1) {
      final x = visiblePoints.length <= 1
          ? chartRect.center.dx
          : chartRect.left + step * index;
      final y =
          chartRect.bottom -
          chartRect.height * clampUnitInterval(visiblePoints[index].hitRatio);
      final distance = (position - Offset(x, y)).distance;
      if (distance < nearestDistance) {
        nearest = index;
        nearestDistance = distance;
      }
    }
    // Keep the touch target forgiving while avoiding accidental selections
    // from taps on the axis labels or surrounding controls.
    return nearestDistance <= 30 ? nearest : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final motionDisabled = !openHandTickerMotionEnabled(context);
    final hoverSettings = _hoverSettingsFor(context);
    _applyHoverSettings(hoverSettings);
    final displayData = widget.trend.displayData(widget.displayMode);
    final exclusionHint = _cacheHitExclusionHint(l10n, displayData);
    final effectiveViewport =
        _viewport.totalPoints == displayData.trend.points.length
        ? _viewport
        : SessionCacheHitViewport.full(displayData.trend.points.length);
    final visiblePoints = _visiblePoints(
      displayData.trend.points,
      effectiveViewport,
    );
    final valueStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Container(
      padding: kOpenHandTokenPanelCardPadding,
      decoration: openHandTokenPanelCardDecoration(colorScheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.sessMetaCacheHitTrend,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${l10n.sessMetaCacheHitAvg}: ${(displayData.averageHitRatio * 100).round()}%',
                style: valueStyle?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              // 平均前缀复用率：衡量 Prompt 装配是否保持前缀延展的健康口径。
              // 命中率会被本轮新增（必然未缓存）的输入稀释，复用率不会。
              if (displayData.averagePrefixReuseRatio != null) ...[
                kOpenHandHGap8,
                Text(
                  '${l10n.tokenPopupPrefixReuse}: ${(displayData.averagePrefixReuseRatio! * 100).round()}%',
                  style: valueStyle?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              kOpenHandHGap8,
              InkWell(
                onTap: () {
                  final anchor = _viewport.start + _viewport.span / 2;
                  _zoom(anchor, 1.35);
                },
                borderRadius: BorderRadius.circular(kOpenHandRadius8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    l10n.imageEditorZoomLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (!_viewport.isFullRange) ...[
                kOpenHandHGap8,
                InkWell(
                  onTap: () {
                    _resetHoverTooltip();
                    setState(() {
                      _viewport = SessionCacheHitViewport.full(
                        displayData.trend.points.length,
                      );
                    });
                  },
                  borderRadius: BorderRadius.circular(kOpenHandRadius8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Text(
                      l10n.settingsReset,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          kOpenHandGap10,
          _CacheHitCompositionSummary(
            cacheRead: displayData.cacheReadTokens,
            cacheWrite: displayData.cacheWriteTokens,
            uncachedPrompt: displayData.uncachedPromptTokens,
            averageRatio: displayData.averageHitRatio,
          ),
          kOpenHandGap12,
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CacheHitModeChip(
                        label: l10n.tokenPopupCacheHitModeExcludeExpired,
                        selected:
                            widget.displayMode ==
                            SessionCacheHitDisplayMode.excludeExpiredMisses,
                        onTap: () {
                          widget.onDisplayModeChanged?.call(
                            SessionCacheHitDisplayMode.excludeExpiredMisses,
                          );
                        },
                      ),
                      kOpenHandHGap8,
                      _CacheHitModeChip(
                        label: l10n.tokenPopupCacheHitModeIncludeExpired,
                        selected:
                            widget.displayMode ==
                            SessionCacheHitDisplayMode.includeExpiredMisses,
                        onTap: () {
                          widget.onDisplayModeChanged?.call(
                            SessionCacheHitDisplayMode.includeExpiredMisses,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (exclusionHint.isNotEmpty) ...[
                kOpenHandHGap8,
                Flexible(
                  child: Text(
                    exclusionHint,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
                ),
              ],
            ],
          ),
          kOpenHandGap10,
          if (displayData.trend.points.isEmpty)
            _CacheHitTrendEmptyState(
              hasAnyPoints: widget.trend.points.isNotEmpty,
              displayMode: widget.displayMode,
              height: math.min(84, widget.height),
            )
          else
            SizedBox(
              height: widget.height,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const chartPadding = EdgeInsets.fromLTRB(30, 8, 8, 22);
                  final chartRect = Rect.fromLTWH(
                    chartPadding.left,
                    chartPadding.top,
                    math.max(1, constraints.maxWidth - chartPadding.horizontal),
                    math.max(1, widget.height - chartPadding.vertical),
                  );
                  final averageY =
                      chartRect.bottom -
                      chartRect.height *
                          clampUnitInterval(displayData.averageHitRatio);
                  final startTurn = visiblePoints.first.turnIndex;
                  final middleTurn =
                      visiblePoints[visiblePoints.length ~/ 2].turnIndex;
                  final endTurn = visiblePoints.last.turnIndex;
                  // X 轴标签按对应数据点的真实坐标居中放置。
                  final singlePoint = visiblePoints.length == 1;
                  final startX = singlePoint
                      ? chartRect.center.dx
                      : chartRect.left;
                  final endX = chartRect.right;
                  final middleIndex = visiblePoints.length ~/ 2;
                  final middleX = visiblePoints.length > 1
                      ? chartRect.left +
                            chartRect.width /
                                (visiblePoints.length - 1) *
                                middleIndex
                      : chartRect.center.dx;
                  // 仅当中间标签与首/尾不重复时才渲染（例如 4 点时显示 1/3/4，
                  // 2 点时只显示首尾避免视觉重复）。
                  final showMiddleLabel =
                      visiblePoints.length > 2 &&
                      middleTurn != startTurn &&
                      middleTurn != endTurn;
                  final firstRequestIndex = visiblePoints.indexWhere(
                    (point) => point.isFirstRequest,
                  );
                  final firstRequestBadgeText =
                      l10n.tokenPopupFirstRequestShort;
                  final firstRequestDx = firstRequestIndex < 0
                      ? 0.0
                      : (singlePoint
                            ? chartRect.center.dx
                            : chartRect.left +
                                  chartRect.width /
                                      (visiblePoints.length - 1) *
                                      firstRequestIndex);
                  final firstRequestDy = firstRequestIndex < 0
                      ? 0.0
                      : chartRect.bottom -
                            chartRect.height *
                                clampUnitInterval(
                                  visiblePoints[firstRequestIndex].hitRatio,
                                );
                  return Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        final direction = event.scrollDelta.dy;
                        if (direction.abs() <=
                            _tokenPopupCacheHitScaleEpsilon) {
                          return;
                        }
                        final scale = direction > 0
                            ? _tokenPopupCacheHitZoomOutScale
                            : _tokenPopupCacheHitZoomInScale;
                        final localDx =
                            (event.localPosition.dx - chartRect.left).clamp(
                              0.0,
                              chartRect.width,
                            );
                        final anchor =
                            _viewport.start +
                            (chartRect.width <= 0
                                ? 0
                                : localDx / chartRect.width * _viewport.span);
                        _zoom(anchor, scale);
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        final index = _pointIndexAtPosition(
                          position: details.localPosition,
                          chartRect: chartRect,
                          visiblePoints: visiblePoints,
                        );
                        if (index == null) {
                          _hideHoverTooltip();
                          return;
                        }
                        _selectPoint(
                          index: index,
                          visiblePoints: visiblePoints,
                        );
                      },
                      onScaleStart: (_) {
                        _gestureAppliedScale = 1;
                      },
                      onScaleUpdate: (details) {
                        final localDx =
                            (details.localFocalPoint.dx - chartRect.left).clamp(
                              0.0,
                              chartRect.width,
                            );
                        final anchor =
                            _viewport.start +
                            (chartRect.width <= 0
                                ? 0
                                : localDx / chartRect.width * _viewport.span);
                        final incrementalScale =
                            details.scale / _gestureAppliedScale;
                        if (details.scale.isFinite &&
                            details.scale > 0 &&
                            (incrementalScale - 1).abs() >
                                _tokenPopupCacheHitScaleEpsilon) {
                          _gestureAppliedScale = details.scale;
                          _zoom(anchor, incrementalScale);
                          return;
                        }
                        final deltaPoints = chartRect.width <= 0
                            ? 0.0
                            : -details.focalPointDelta.dx /
                                  chartRect.width *
                                  _viewport.span;
                        if (deltaPoints.abs() > _tokenPopupCacheHitPanEpsilon) {
                          _pan(deltaPoints);
                        }
                      },
                      onScaleEnd: (_) {
                        _gestureAppliedScale = 1;
                      },
                      child: MouseRegion(
                        onHover: (event) {
                          // 边界：visiblePoints 为空（理论上 hasEnoughPoints
                          // 已守住，但作为 onHover 顶层保护，避免驱动空动画
                          // 与 setState 不必要的 rebuild）。
                          if (visiblePoints.isEmpty) {
                            _hideHoverTooltip();
                            return;
                          }
                          final rawLocalDx =
                              event.localPosition.dx - chartRect.left;
                          if (rawLocalDx < 0 || rawLocalDx > chartRect.width) {
                            _hideHoverTooltip();
                            return;
                          }
                          final localDx = rawLocalDx.clamp(
                            0.0,
                            chartRect.width,
                          );
                          // 把鼠标横向位置映射到 visiblePoints 索引。
                          final span = visiblePoints.length <= 1
                              ? 0.0
                              : chartRect.width / (visiblePoints.length - 1);
                          final raw = span <= 0
                              ? 0.0
                              : (localDx / span).round();
                          // 上面已 guard visiblePoints.isEmpty，这里 length-1
                          // 一定 >= 0，clamp 区间合法。
                          final idx = raw
                              .clamp(0, visiblePoints.length - 1)
                              .toInt();
                          if (_hoveredPointIndex != idx) {
                            final wasHovering = _hoveredPointIndex != null;
                            setState(() {
                              _hoveredPointIndex = idx;
                              _displayedPointIndex = idx;
                            });
                            if (!wasHovering) {
                              // 第一次入场或退场中再次入场：从当前值 forward，
                              // 已完全显示时（value==1）forward 是 no-op，
                              // 退场中（0<value<1）则继续推进到 1，保证
                              // 进出衔接自然不闪。
                              _hoverMotionGeneration += 1;
                              _hoverController.forward();
                            }
                          }
                        },
                        onExit: (_) {
                          _hideHoverTooltip();
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter:
                                      _TokenPopupCacheHitTrendStaticPainter(
                                        averageHitRatio:
                                            displayData.averageHitRatio,
                                        colorScheme: colorScheme,
                                      ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: AnimatedBuilder(
                                animation: _controller,
                                builder: (context, _) {
                                  return RepaintBoundary(
                                    child: CustomPaint(
                                      painter:
                                          _TokenPopupCacheHitTrendDynamicPainter(
                                            points: visiblePoints,
                                            progress: motionDisabled
                                                ? 1
                                                : _controller.value,
                                            colorScheme: colorScheme,
                                          ),
                                      child: const SizedBox.expand(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (firstRequestIndex >= 0)
                              Positioned(
                                left: (firstRequestDx + 8)
                                    .clamp(
                                      chartRect.left,
                                      math.max(
                                        chartRect.left,
                                        chartRect.right - 76,
                                      ),
                                    )
                                    .toDouble(),
                                top: (firstRequestDy - 10)
                                    .clamp(
                                      chartRect.top,
                                      math.max(
                                        chartRect.top,
                                        chartRect.bottom - 18,
                                      ),
                                    )
                                    .toDouble(),
                                child: IgnorePointer(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface.withValues(
                                        alpha: 0.92,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        kOpenHandRadius4,
                                      ),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant
                                            .withValues(alpha: 0.55),
                                      ),
                                    ),
                                    child: Text(
                                      firstRequestBadgeText,
                                      style: valueStyle?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // hover 高亮 + tooltip：把鼠标位置
                            // 映射到最近的 visiblePoints 索引，叠一个发光圆点
                            // + 浮窗，整组由 [_hoverController] 驱动进退场，
                            // 与全局 DialogAnimationSettings 的方向、时长和
                            // 曲线保持一致。
                            if (_displayedPointIndex != null &&
                                !(_hoveredPointIndex == null &&
                                    hoverSettings.exitDisabled))
                              _buildHoverOverlay(
                                visiblePoints: visiblePoints,
                                hoveredIndex: _displayedPointIndex!,
                                chartRect: chartRect,
                                colorScheme: colorScheme,
                                l10n: l10n,
                                hoverSettings: hoverSettings,
                              ),
                            Positioned(
                              left: 0,
                              top: chartRect.top - 7,
                              child: Text('100%', style: valueStyle),
                            ),
                            // 平均值标签贴近虚线右端，避开 Y 轴刻度与数据点。
                            Positioned(
                              right: 12,
                              top: averageY - 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(
                                    kOpenHandRadius4,
                                  ),
                                ),
                                child: Text(
                                  l10n.sessMetaCacheHitAvg,
                                  style: valueStyle?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 8,
                              bottom: 14,
                              child: Text('0%', style: valueStyle),
                            ),
                            // 每个标签在固定宽度单元格内按数据点坐标居中。
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: SizedBox(
                                height: 18,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      left: startX - 16,
                                      width: 32,
                                      child: Center(
                                        child: Text(
                                          '$startTurn',
                                          style: valueStyle,
                                        ),
                                      ),
                                    ),
                                    if (showMiddleLabel)
                                      Positioned(
                                        left: middleX - 16,
                                        width: 32,
                                        child: Center(
                                          child: Text(
                                            '$middleTurn',
                                            style: valueStyle,
                                          ),
                                        ),
                                      ),
                                    if (!singlePoint)
                                      Positioned(
                                        left: endX - 16,
                                        width: 32,
                                        child: Center(
                                          child: Text(
                                            '$endTurn',
                                            style: valueStyle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  List<SessionCacheHitTurnPoint> _visiblePoints(
    List<SessionCacheHitTurnPoint> points,
    SessionCacheHitViewport viewport,
  ) {
    if (points.isEmpty) return const <SessionCacheHitTurnPoint>[];
    final start = viewport.start.floor().clamp(0, points.length - 1);
    final end = viewport.end.ceil().clamp(0, points.length - 1);
    return points.sublist(start, end + 1);
  }

  /// hover 高亮 + tooltip：
  /// - 渲染当前鼠标位置对应的数据点（发光圆 + tooltip 浮窗）；
  /// - 圆点 + 浮窗共用 [_hoverController] 和全局 DialogAnimationSettings，
  ///   并按方向尊重 0ms motion preference；
  /// - tooltip 内部“上方 / 下方”翻转时沿用共享 transition 的缩放锚点，
  ///   避免侵入 chart 边缘。
  Widget _buildHoverOverlay({
    required List<SessionCacheHitTurnPoint> visiblePoints,
    required int hoveredIndex,
    required Rect chartRect,
    required ColorScheme colorScheme,
    required AppLocalizations l10n,
    required DialogAnimationSettings hoverSettings,
  }) {
    if (hoveredIndex < 0 || hoveredIndex >= visiblePoints.length) {
      return const SizedBox.shrink();
    }
    final point = visiblePoints[hoveredIndex];
    final ratio = clampUnitInterval(point.hitRatio);
    final span = visiblePoints.length <= 1
        ? 0.0
        : chartRect.width / (visiblePoints.length - 1);
    final cx = span <= 0
        ? chartRect.center.dx
        : chartRect.left + span * hoveredIndex;
    final cy = chartRect.bottom - chartRect.height * ratio;
    final theme = Theme.of(context);
    final tooltipBg = colorScheme.surfaceContainerHigh;
    final tooltipBorder = colorScheme.outlineVariant.withValues(alpha: 0.7);
    final percentText = '${(ratio * 100).round()}%';
    final turnLabel = l10n.sessMetaCacheHitPoint(point.turnIndex);
    final firstRequestNote = point.isFirstRequest
        ? l10n.tokenPopupFirstRequestNotAveraged
        : '';
    // 非首轮补充"本轮新增 + 前缀复用"：新增输入必然未缓存，命中率被其
    // 稀释属正常现象；复用率才反映装配是否破坏了缓存前缀。
    final prefixReuseRatio = point.prefixReuseRatio;
    final freshReuseNote = !point.isFirstRequest && prefixReuseRatio != null
        ? l10n.tokenPopupTooltipFreshReuse(
            _compactTokenCount(point.freshInputTokens),
            (prefixReuseRatio * 100).round(),
          )
        : '';
    final tooltipWidth = point.isFirstRequest
        ? _tokenPopupCacheHitFirstRequestTooltipWidth
        : freshReuseNote.isNotEmpty
        ? _tokenPopupCacheHitReuseTooltipWidth
        : _tokenPopupCacheHitTooltipWidth;
    final tooltipHeight = point.isFirstRequest
        ? _tokenPopupCacheHitFirstRequestTooltipHeight
        : freshReuseNote.isNotEmpty
        ? _tokenPopupCacheHitReuseTooltipHeight
        : _tokenPopupCacheHitTooltipHeight;
    // tooltip 优先放在点的上方；空间不足时翻转到下方。
    final showAbove =
        (cy - tooltipHeight - _tokenPopupCacheHitTooltipGap) >= chartRect.top;
    final tooltipTop = showAbove
        ? cy - tooltipHeight - _tokenPopupCacheHitTooltipGap
        : _clampTokenPopupOverlayOrigin(
            desired: cy + _tokenPopupCacheHitTooltipGap,
            minimum: chartRect.top,
            maximum: chartRect.bottom - tooltipHeight,
          );
    // 横向避免超出 chartRect。
    final tooltipLeft = _clampTokenPopupOverlayOrigin(
      desired: cx - tooltipWidth / 2,
      minimum: chartRect.left,
      maximum: chartRect.right - tooltipWidth,
    );

    Widget transition(Widget child) => buildAnimationStyleTransition(
      animation: _hoverController,
      settings: hoverSettings,
      child: child,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 命中点发光圆 + 实心圆与 tooltip 同步进退场。
        Positioned(
          left: cx - 9,
          top: cy - 9,
          child: IgnorePointer(
            child: transition(
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary.withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: cx - 4,
          top: cy - 4,
          child: IgnorePointer(
            child: transition(
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary,
                  border: Border.all(color: colorScheme.surface, width: 1.4),
                ),
              ),
            ),
          ),
        ),
        // tooltip 浮窗。
        Positioned(
          left: tooltipLeft,
          top: tooltipTop,
          child: IgnorePointer(
            child: SizedBox(
              width: tooltipWidth,
              height: tooltipHeight,
              child: transition(
                Container(
                  width: tooltipWidth,
                  height: tooltipHeight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tooltipBg.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(kOpenHandRadius8),
                    border: Border.all(color: tooltipBorder),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        turnLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                      kOpenHandGap2,
                      Text(
                        percentText,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: ratio >= 0.5
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1.0,
                        ),
                      ),
                      if (firstRequestNote.isNotEmpty) ...[
                        kOpenHandGap3,
                        Text(
                          firstRequestNote,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                          ),
                        ),
                      ],
                      if (freshReuseNote.isNotEmpty) ...[
                        kOpenHandGap3,
                        Text(
                          freshReuseNote,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: point.reachedTheoreticalCeiling
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.error,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TokenPopupCacheHitTrendStaticPainter extends CustomPainter {
  const _TokenPopupCacheHitTrendStaticPainter({
    required this.averageHitRatio,
    required this.colorScheme,
  });

  final double averageHitRatio;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = EdgeInsets.fromLTRB(30, 8, 8, 22);
    final chart = Rect.fromLTWH(
      padding.left,
      padding.top,
      math.max(1, size.width - padding.horizontal),
      math.max(1, size.height - padding.vertical),
    );
    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final dashedPaint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.62)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    for (var i = 0; i <= 4; i++) {
      final ratio = i / 4;
      final y = chart.bottom - chart.height * ratio;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    final averageY =
        chart.bottom - chart.height * clampUnitInterval(averageHitRatio);
    _drawTokenPopupCacheHitTrendDashedLine(
      canvas,
      Offset(chart.left, averageY),
      Offset(chart.right, averageY),
      dashedPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _TokenPopupCacheHitTrendStaticPainter oldDelegate,
  ) {
    return oldDelegate.averageHitRatio != averageHitRatio ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _TokenPopupCacheHitTrendDynamicPainter extends CustomPainter {
  const _TokenPopupCacheHitTrendDynamicPainter({
    required this.points,
    required this.progress,
    required this.colorScheme,
  });

  final List<SessionCacheHitTurnPoint> points;
  final double progress;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = EdgeInsets.fromLTRB(30, 8, 8, 22);
    final chart = Rect.fromLTWH(
      padding.left,
      padding.top,
      math.max(1, size.width - padding.horizontal),
      math.max(1, size.height - padding.vertical),
    );
    final linePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          colorScheme.primary.withValues(alpha: 0.18),
          colorScheme.primary.withValues(alpha: 0.02),
        ],
      ).createShader(chart);

    final polyline = _tokenPopupCacheHitTrendAnimatedPolyline(
      ratios: points.map((point) => point.hitRatio).toList(growable: false),
      chartRect: chart,
      progress: progress,
    );
    if (polyline.length < 2) {
      if (polyline.length == 1) {
        _drawPointMarker(canvas, polyline.single, points.first);
      }
      return;
    }

    final linePath = Path()..moveTo(polyline.first.dx, polyline.first.dy);
    final fillPath = Path()
      ..moveTo(polyline.first.dx, chart.bottom)
      ..lineTo(polyline.first.dx, polyline.first.dy);
    for (var i = 1; i < polyline.length; i++) {
      final prev = polyline[i - 1];
      final current = polyline[i];
      final deltaX = current.dx - prev.dx;
      final cp1 = Offset(prev.dx + deltaX * 0.35, prev.dy);
      final cp2 = Offset(current.dx - deltaX * 0.35, current.dy);
      linePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, current.dx, current.dy);
      fillPath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, current.dx, current.dy);
    }
    fillPath
      ..lineTo(polyline.last.dx, chart.bottom)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);
    if (points.first.isFirstRequest) {
      _drawPointMarker(canvas, polyline.first, points.first);
    }
    if (!points.last.isFirstRequest) {
      _drawPointMarker(canvas, polyline.last, points.last);
    }
  }

  void _drawPointMarker(
    Canvas canvas,
    Offset center,
    SessionCacheHitTurnPoint point,
  ) {
    if (point.isFirstRequest) {
      canvas.drawCircle(
        center,
        4.4,
        Paint()..color = colorScheme.surface.withValues(alpha: 0.92),
      );
      canvas.drawCircle(
        center,
        4.4,
        Paint()
          ..color = colorScheme.outline.withValues(alpha: 0.78)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(
        center,
        1.7,
        Paint()..color = colorScheme.outline.withValues(alpha: 0.68),
      );
      return;
    }
    canvas.drawCircle(center, 3.6, Paint()..color = colorScheme.primary);
  }

  @override
  bool shouldRepaint(
    covariant _TokenPopupCacheHitTrendDynamicPainter oldDelegate,
  ) {
    return oldDelegate.points != points ||
        oldDelegate.progress != progress ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _CacheHitCompositionSummary extends StatelessWidget {
  const _CacheHitCompositionSummary({
    required this.cacheRead,
    required this.cacheWrite,
    required this.uncachedPrompt,
    required this.averageRatio,
  });

  final int cacheRead;
  final int cacheWrite;
  final int uncachedPrompt;
  final double averageRatio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final total = cacheRead + cacheWrite + uncachedPrompt;
    final fallbackRatio = clampUnitInterval(averageRatio);
    final readRatio = total <= 0 ? fallbackRatio : cacheRead / total;
    final cachedRatio = total <= 0
        ? fallbackRatio
        : (cacheRead + cacheWrite) / total;
    final readColor = colorScheme.primary;
    final writeColor = Color.lerp(
      colorScheme.primary,
      colorScheme.surfaceContainerHighest,
      0.45,
    )!;
    final missColor = colorScheme.outlineVariant.withValues(alpha: 0.62);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: kOpenHandPillBorderRadius,
          child: ColoredBox(
            color: missColor,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: cachedRatio),
              duration: openHandMotionDuration(context, kOpenHandMotion520),
              curve: kOpenHandEntranceCurve,
              builder: (context, animatedCached, _) {
                return TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: readRatio),
                  duration: openHandMotionDuration(context, kOpenHandMotion520),
                  curve: kOpenHandEntranceCurve,
                  builder: (context, animatedRead, _) => SizedBox(
                    height: 8,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: animatedCached.clamp(0.0, 1.0),
                            heightFactor: 1,
                            child: ColoredBox(color: writeColor),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: animatedRead.clamp(0.0, 1.0),
                            heightFactor: 1,
                            child: ColoredBox(color: readColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        kOpenHandGap7,
        Wrap(
          spacing: 10,
          runSpacing: 5,
          children: [
            _CacheHitCompositionLegend(
              color: readColor,
              label:
                  '${l10n.tokenPopupCacheRead} ${_compactTokenCount(cacheRead)}',
            ),
            _CacheHitCompositionLegend(
              color: writeColor,
              label:
                  '${l10n.tokenPopupCacheWrite} ${_compactTokenCount(cacheWrite)}',
            ),
            _CacheHitCompositionLegend(
              color: missColor,
              label:
                  '${l10n.tokenPopupUncached} ${_compactTokenCount(uncachedPrompt)}',
            ),
          ],
        ),
      ],
    );
  }
}

class _CacheHitCompositionLegend extends StatelessWidget {
  const _CacheHitCompositionLegend({required this.color, required this.label});

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
        kOpenHandHGap4,
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _CacheHitTrendEmptyState extends StatelessWidget {
  const _CacheHitTrendEmptyState({
    required this.hasAnyPoints,
    required this.displayMode,
    required this.height,
  });

  final bool hasAnyPoints;
  final SessionCacheHitDisplayMode displayMode;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final text = !hasAnyPoints
        ? l10n.tokenPopupTrendNoData
        : displayMode == SessionCacheHitDisplayMode.excludeExpiredMisses
        ? l10n.tokenPopupTrendOnlyFirstIgnored
        : l10n.tokenPopupTrendFirstReferenceOnly;
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _CacheHitModeChip extends StatelessWidget {
  const _CacheHitModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: kOpenHandPillBorderRadius,
      child: AnimatedContainer(
        duration: openHandMotionDuration(
          context,
          _tokenPopupCacheHitModeChipDuration,
        ),
        curve: kOpenHandSwitchInCurve,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: kOpenHandPillBorderRadius,
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
