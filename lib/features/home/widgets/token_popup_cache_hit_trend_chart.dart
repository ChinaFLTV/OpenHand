import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../app/model/dialog_animation_settings.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/session_cache_hit_trend.dart';

const Curve _tokenPopupCacheHitTrendEntranceCurve = Curves.easeOutCubic;
const Duration _tokenPopupCacheHitModeChipDuration = Duration(
  milliseconds: 220,
);

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

class TokenPopupCacheHitTrendChart extends StatefulWidget {
  const TokenPopupCacheHitTrendChart({
    super.key,
    required this.trend,
    this.height = 168,
    this.displayMode = SessionCacheHitDisplayMode.excludeExpiredMisses,
    this.onDisplayModeChanged,
  });

  final SessionCacheHitTrend trend;
  final double height;
  final SessionCacheHitDisplayMode displayMode;
  final ValueChanged<SessionCacheHitDisplayMode>? onDisplayModeChanged;

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
  // - 悬停进入：0 → 1（沿用全局 DialogAnimationSettings.springScale，
  //   带 easeOutBack 微弹）；
  // - 悬停退出：1 → 0（同一曲线的 reverse）；
  // - 移动到不同点：data 立即更新但 controller 保持 1.0，不重启。
  late final AnimationController _hoverController;
  // 缓存上一次应用到控制器的 hover 设置，避免每帧重设 duration /
  // reverseDuration（Flutter 内部会清零 _lastElapsedDuration，存在动画
  // 中点被踩扁的理论风险）。
  DialogAnimationSettings? _lastAppliedHoverSettings;
  double _wheelScaleAccumulator = 1;
  int? _hoveredPointIndex;

  @override
  void initState() {
    super.initState();
    _viewport = SessionCacheHitViewport.full(widget.trend.points.length);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    )..forward();
    _hoverController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
      value: 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant TokenPopupCacheHitTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trend.points.length != widget.trend.points.length) {
      _viewport = SessionCacheHitViewport.full(widget.trend.points.length);
      _controller
        ..reset()
        ..forward();
      // 数据集换新时立刻让浮窗退场，避免残留（旧 points 索引可能越界
      // 新数据集，悬停态必须复位）。
      if (_hoveredPointIndex != null) {
        _hoveredPointIndex = null;
        _hoverController.value = 0.0;
      }
      _lastAppliedHoverSettings = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _hoverController.dispose();
    super.dispose();
  }

  void _zoom(double anchor, double scale) {
    setState(() {
      _viewport = _viewport.zoomAround(anchor: anchor, scale: scale);
    });
  }

  /// Hover tooltip uses spring-scale while inheriting global duration / curve.
  DialogAnimationSettings _hoverSettingsFor(BuildContext context) {
    final global = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    return global.copyWith(
      entranceStyle: DialogAnimationStyle.springScale,
      exitStyle: DialogAnimationStyle.springScale,
    );
  }

  void _pan(double deltaPoints) {
    setState(() {
      _viewport = _viewport.panBy(deltaPoints);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final motionDisabled = !openHandTickerMotionEnabled(context);
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.sessMetaCacheHitTrend,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Text(
                '${l10n.sessMetaCacheHitAvg}: ${(displayData.averageHitRatio * 100).round()}%',
                style: valueStyle,
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  final anchor = _viewport.start + _viewport.span / 2;
                  _zoom(anchor, 1.35);
                },
                borderRadius: BorderRadius.circular(8),
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
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    setState(() {
                      _viewport = SessionCacheHitViewport.full(
                        widget.trend.points.length,
                      );
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 8),
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
                          _viewport = SessionCacheHitViewport.full(
                            displayData.trend.points.length,
                          );
                          widget.onDisplayModeChanged?.call(
                            SessionCacheHitDisplayMode.excludeExpiredMisses,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _CacheHitModeChip(
                        label: l10n.tokenPopupCacheHitModeIncludeExpired,
                        selected:
                            widget.displayMode ==
                            SessionCacheHitDisplayMode.includeExpiredMisses,
                        onTap: () {
                          _viewport = SessionCacheHitViewport.full(
                            widget.trend.points.length,
                          );
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
                const SizedBox(width: 8),
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
          const SizedBox(height: 10),
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
                  // 修复 X 轴刻度与数据点未对齐：按各数据点
                  // 真实 x 坐标（chartRect.left + stepX * index）居中放置。
                  // 旧实现用 Row + spaceBetween 会出现两类错位：
                  //   1) 首尾各偏 8px（Row 起点 = chartRect.left - 8，终点 = Stack 右边），
                  //   2) 中间标签落在 Row 几何中点，但可见点中点位于 chartRect.width
                  //      * (length/2) / (length-1) 处，对 4 点而言是 2/3 宽而非 1/2 宽。
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
                    onPointerPanZoomStart: (_) {
                      _wheelScaleAccumulator = 1;
                    },
                    onPointerPanZoomUpdate: (event) {
                      final localDx = (event.localPosition.dx - chartRect.left)
                          .clamp(0.0, chartRect.width);
                      final anchor =
                          _viewport.start +
                          (chartRect.width <= 0
                              ? 0
                              : localDx / chartRect.width * _viewport.span);
                      if ((event.scale - 1).abs() > 0.02) {
                        _zoom(anchor, event.scale);
                      }
                    },
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        final direction = event.scrollDelta.dy;
                        final scale = direction > 0 ? 0.88 : 1.12;
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
                        _wheelScaleAccumulator *= scale;
                        _zoom(anchor, _wheelScaleAccumulator);
                        _wheelScaleAccumulator = 1;
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
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
                        if ((details.scale - 1).abs() > 0.02) {
                          _zoom(anchor, details.scale);
                          return;
                        }
                        final deltaPoints = chartRect.width <= 0
                            ? 0.0
                            : -details.focalPointDelta.dx /
                                  chartRect.width *
                                  _viewport.span;
                        if (deltaPoints.abs() > 0.01) {
                          _pan(deltaPoints);
                        }
                      },
                      child: MouseRegion(
                        onHover: (event) {
                          // 边界：visiblePoints 为空（理论上 hasEnoughPoints
                          // 已守住，但作为 onHover 顶层保护，避免驱动空动画
                          // 与 setState 不必要的 rebuild）。
                          if (visiblePoints.isEmpty) {
                            if (_hoveredPointIndex != null) {
                              setState(() => _hoveredPointIndex = null);
                              _hoverController.reverse();
                            }
                            return;
                          }
                          final localDx =
                              (event.localPosition.dx - chartRect.left).clamp(
                                0.0,
                                chartRect.width,
                              );
                          if (localDx < 0 || localDx > chartRect.width) {
                            if (_hoveredPointIndex != null) {
                              setState(() => _hoveredPointIndex = null);
                              _hoverController.reverse();
                            }
                            return;
                          }
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
                            setState(() => _hoveredPointIndex = idx);
                            if (!wasHovering) {
                              // 第一次入场或退场中再次入场：从当前值 forward，
                              // 已完全显示时（value==1）forward 是 no-op，
                              // 退场中（0<value<1）则继续推进到 1，保证
                              // 进出衔接自然不闪。
                              _hoverController.forward();
                            }
                          }
                        },
                        onExit: (_) {
                          if (_hoveredPointIndex != null) {
                            setState(() => _hoveredPointIndex = null);
                            _hoverController.reverse();
                          }
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
                                      borderRadius: BorderRadius.circular(4),
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
                            // + 浮窗，整组走 springScale 的 Q 弹进退场（由
                            // [_hoverController] 驱动 forward / reverse），与
                            // 全局 DialogAnimationSettings 的时长 / 曲线保持
                            // 一致。
                            if (_hoveredPointIndex != null)
                              _buildHoverOverlay(
                                visiblePoints: visiblePoints,
                                hoveredIndex: _hoveredPointIndex!,
                                chartRect: chartRect,
                                colorScheme: colorScheme,
                                l10n: l10n,
                                hoverSettings: _hoverSettingsFor(context),
                              ),
                            Positioned(
                              left: 0,
                              top: chartRect.top - 7,
                              child: Text('100%', style: valueStyle),
                            ),
                            // 修复"平均"标签与左侧 Y 轴刻度视觉重叠：
                            // 旧位置 left:8 紧贴 y 轴 0%/100% 区域，当平均值接近
                            // 25%/50% 等网格刻度时，文字与网格线 / 0%-100% 标签
                            // 在同一水平条带叠加。改为贴虚线右端 + 轻量底色
                            // （用 surface 浮于 chart 半透明背景之上），既远离
                            // y 轴区域，又能在平均值贴近最后一个数据点时不被
                            // 发光圆 / 实心点遮挡。
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
                                  borderRadius: BorderRadius.circular(4),
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
                            // X 轴刻度改为按数据点真实 x 居中：
                            // 用 Stack + Positioned(left: dataX - 16, width: 32)
                            // 让每个标签在 32px 单元格内水平居中，单元格中心恰为
                            // 对应数据点 x 坐标；不再使用 Row + spaceBetween。
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
  /// - 圆点 + 浮窗共用 [_hoverController] 走 springScale 风格的 Q 弹
  ///   进退场（_SpringScaleTransition 内部用 Curves.easeOutBack / easeInBack
  ///   ，带微弹），时长 / 曲线沿用全局 DialogAnimationSettings 并尊重
  ///   全局 motion preference 走 0ms 关闭动画；
  /// - tooltip 内部"上方 / 下方"翻转时由 springScale 的 alignment 决定
  ///   scale 锚点（上方时从底部中心展开、避免侵入 chart 上沿；下方时
  ///   从顶部中心展开、避免侵入 chart 下沿）。
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
    final tooltipWidth = point.isFirstRequest ? 148.0 : 132.0;
    final tooltipHeight = point.isFirstRequest ? 58.0 : 46.0;
    // tooltip 优先放在点的上方；空间不足时翻转到下方。
    final showAbove = (cy - tooltipHeight - 12) >= chartRect.top;
    final tooltipTop = showAbove
        ? cy - tooltipHeight - 12
        : (cy + 12).clamp(chartRect.top, chartRect.bottom - tooltipHeight);
    // 横向避免超出 chartRect。
    final tooltipLeft = (cx - tooltipWidth / 2).clamp(
      chartRect.left,
      chartRect.right - tooltipWidth,
    );
    // 仅在 hoverSettings 实际变化时把 duration /
    // reverseDuration 同步到控制器。Flutter 内部对 controller.duration
    // 的 setter 会清零 _lastElapsedDuration，若每帧重设同一值虽然
    // 视觉无跳变，但属于无谓写入；这里加一个等价性 cache 规避。
    if (_lastAppliedHoverSettings != hoverSettings) {
      _hoverController.duration = hoverSettings.duration;
      _hoverController.reverseDuration = hoverSettings.duration ~/ 5 * 4;
      _lastAppliedHoverSettings = hoverSettings;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 命中点发光圆 + 实心圆：套在同一个 springScale transition 内，
        // 与 tooltip 同步 Q 弹进退场。
        Positioned(
          left: cx - 9,
          top: cy - 9,
          child: IgnorePointer(
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.primary.withValues(alpha: 0.18),
              ),
            ),
          ),
        ),
        Positioned(
          left: cx - 4,
          top: cy - 4,
          child: IgnorePointer(
            child: Container(
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
        // tooltip 浮窗。
        Positioned(
          left: tooltipLeft,
          top: tooltipTop,
          child: IgnorePointer(
            child: SizedBox(
              width: tooltipWidth,
              height: tooltipHeight,
              child: buildAnimationStyleTransition(
                animation: _hoverController,
                settings: hoverSettings,
                child: Container(
                  width: tooltipWidth,
                  height: tooltipHeight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tooltipBg.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(8),
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
                      const SizedBox(height: 2),
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
                        const SizedBox(height: 3),
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
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: openHandMotionDuration(
          context,
          _tokenPopupCacheHitModeChipDuration,
        ),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
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
