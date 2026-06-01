import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/model/dialog_animation_settings.dart';
import '../../../app/state/settings_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../model/session_cache_hit_trend.dart';

const Curve _tokenPopupCacheHitTrendEntranceCurve = Curves.easeOutCubic;

@visibleForTesting
double tokenPopupCacheHitTrendAnimationProgress(double t) {
  final clamped = t.clamp(0.0, 1.0);
  return _tokenPopupCacheHitTrendEntranceCurve
      .transform(clamped)
      .clamp(0.0, 1.0);
}

@visibleForTesting
List<Offset> tokenPopupCacheHitTrendAnimatedPolyline({
  required List<double> ratios,
  required Rect chartRect,
  required double progress,
}) {
  if (ratios.isEmpty) return const <Offset>[];
  final easedProgress = tokenPopupCacheHitTrendAnimationProgress(progress);
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
    final ratio = ratios[index].clamp(0.0, 1.0);
    return Offset(
      chartRect.left + stepX * index,
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

class TokenPopupCacheHitTrendChart extends StatefulWidget {
  const TokenPopupCacheHitTrendChart({
    super.key,
    required this.trend,
    this.height = 168,
    this.displayMode = SessionCacheHitDisplayMode.excludeExtremeMisses,
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

class _TokenPopupCacheHitTrendChartState
    extends State<TokenPopupCacheHitTrendChart>
    with SingleTickerProviderStateMixin {
  late SessionCacheHitViewport _viewport;
  late final AnimationController _controller;
  // 2026-06-01 — hover 状态专用的进退场控制器：
  // - 悬停进入：0 → 1（沿用全局 DialogAnimationSettings.springScale，
  //   带 easeOutBack 微弹）；
  // - 悬停退出：1 → 0（同一曲线的 reverse）；
  // - 移动到不同点：data 立即更新但 controller 保持 1.0，不重启。
  late final AnimationController _hoverController;
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
      // 数据集换新时立刻让浮窗退场，避免残留。
      if (_hoveredPointIndex != null) {
        _hoveredPointIndex = null;
        _hoverController.value = 0.0;
      }
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

  /// 2026-06-01 — 给 hover tooltip 专用的进退场设置：
  /// - 风格锁为 `springScale`（Q 弹微弹），不再沿用全局默认 fadeScale，
  ///   让 tooltip 的进程退场天然具备"轻拂鼠标入场/退场"丝滑感；
  /// - 时长 / 曲线沿用全局设置，保留用户在"弹窗动画"里的全局风格选择；
  /// - 尊重 `MediaQuery.disableAnimationsOf`：0ms + none 风格直出直入。
  DialogAnimationSettings _hoverSettingsFor(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return const DialogAnimationSettings(
        entranceStyle: DialogAnimationStyle.none,
        exitStyle: DialogAnimationStyle.none,
        durationMs: 0,
      );
    }
    final global = context.read<SettingsController>().dialogAnimationSettings;
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final displayData = widget.trend.displayData(widget.displayMode);
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

    if (!displayData.trend.hasEnoughPoints) {
      return const SizedBox.shrink();
    }

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
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _CacheHitModeChip(
                    label: isZh ? '排除极端值' : 'Exclude extremes',
                    selected:
                        widget.displayMode ==
                        SessionCacheHitDisplayMode.excludeExtremeMisses,
                    onTap: () {
                      _viewport = SessionCacheHitViewport.full(
                        displayData.trend.points.length,
                      );
                      widget.onDisplayModeChanged?.call(
                        SessionCacheHitDisplayMode.excludeExtremeMisses,
                      );
                    },
                  ),
                  _CacheHitModeChip(
                    label: isZh ? '包括全部' : 'Include all',
                    selected: widget.displayMode == SessionCacheHitDisplayMode.includeAll,
                    onTap: () {
                      _viewport = SessionCacheHitViewport.full(
                        widget.trend.points.length,
                      );
                      widget.onDisplayModeChanged?.call(
                        SessionCacheHitDisplayMode.includeAll,
                      );
                    },
                  ),
                ],
              ),
              const Spacer(),
              if (displayData.excludedPointCount > 0)
                Text(
                  '已排除 ${displayData.excludedPointCount} 轮',
                  textAlign: TextAlign.right,
                  style: valueStyle,
                ),
            ],
          ),
          const SizedBox(height: 10),
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
                        displayData.averageHitRatio.clamp(0.0, 1.0);
                final startTurn = visiblePoints.first.turnIndex;
                final middleTurn =
                    visiblePoints[visiblePoints.length ~/ 2].turnIndex;
                final endTurn = visiblePoints.last.turnIndex;
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
                      final localDx = (event.localPosition.dx - chartRect.left)
                          .clamp(0.0, chartRect.width);
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
                        final localDx = (event.localPosition.dx - chartRect.left)
                            .clamp(0.0, chartRect.width);
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
                        final idx = raw.clamp(
                          0,
                          visiblePoints.length - 1,
                        ).toInt();
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
                              painter: _TokenPopupCacheHitTrendStaticPainter(
                                averageHitRatio: displayData.averageHitRatio,
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
                                        progress: reduceMotion
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
                        // 2026-06-01 — hover 高亮 + tooltip：把鼠标位置
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
                        Positioned(
                          left: 8,
                          top: averageY - 8,
                          child: Text(
                            l10n.sessMetaCacheHitAvg,
                            style: valueStyle?.copyWith(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          bottom: 14,
                          child: Text('0%', style: valueStyle),
                        ),
                        Positioned(
                          left: chartRect.left - 8,
                          right: 0,
                          bottom: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('$startTurn', style: valueStyle),
                              Text('$middleTurn', style: valueStyle),
                              Text('$endTurn', style: valueStyle),
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

  /// 2026-06-01 — hover 高亮 + tooltip：
  /// - 渲染当前鼠标位置对应的数据点（发光圆 + tooltip 浮窗）；
  /// - 圆点 + 浮窗共用 [_hoverController] 走 springScale 风格的 Q 弹
  ///   进退场（_SpringScaleTransition 内部用 Curves.easeOutBack / easeInBack
  ///   ，带微弹），时长 / 曲线沿用全局 DialogAnimationSettings 并尊重
  ///   `MediaQuery.disableAnimationsOf` 走 0ms 关闭动画；
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
    final ratio = point.hitRatio.clamp(0.0, 1.0).toDouble();
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
    const tooltipWidth = 132.0;
    const tooltipHeight = 46.0;
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
    // 把 hover 设置同步到控制器时长（duration / reverseDuration 独立维护，
    // 退出用稍短时长让"轻拂鼠标离开"更利落）。
    _hoverController.duration = hoverSettings.duration;
    _hoverController.reverseDuration = hoverSettings.duration ~/ 5 * 4;

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
                          color: ratio >= 0.95
                              ? Colors.green.shade700
                              : ratio >= 0.5
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1.0,
                        ),
                      ),
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
      ..color = Colors.green.shade600.withValues(alpha: 0.75)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    for (var i = 0; i <= 4; i++) {
      final ratio = i / 4;
      final y = chart.bottom - chart.height * ratio;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    final averageY =
        chart.bottom - chart.height * averageHitRatio.clamp(0.0, 1.0);
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
    if (points.length < 2) {
      return;
    }
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

    final polyline = tokenPopupCacheHitTrendAnimatedPolyline(
      ratios: points.map((point) => point.hitRatio).toList(growable: false),
      chartRect: chart,
      progress: progress,
    );
    if (polyline.length < 2) {
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
    canvas.drawCircle(polyline.last, 3.6, Paint()..color = colorScheme.primary);
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
        duration: const Duration(milliseconds: 220),
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
