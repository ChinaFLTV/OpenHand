import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../model/session_cache_hit_trend.dart';

class TokenPopupCacheHitTrendChart extends StatefulWidget {
  const TokenPopupCacheHitTrendChart({
    super.key,
    required this.trend,
    this.height = 168,
  });

  final SessionCacheHitTrend trend;
  final double height;

  @override
  State<TokenPopupCacheHitTrendChart> createState() =>
      _TokenPopupCacheHitTrendChartState();
}

class _TokenPopupCacheHitTrendChartState
    extends State<TokenPopupCacheHitTrendChart>
    with SingleTickerProviderStateMixin {
  late SessionCacheHitViewport _viewport;
  late final AnimationController _controller;
  double _wheelScaleAccumulator = 1;

  @override
  void initState() {
    super.initState();
    _viewport = SessionCacheHitViewport.full(widget.trend.points.length);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant TokenPopupCacheHitTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trend.points.length != widget.trend.points.length) {
      _viewport = SessionCacheHitViewport.full(widget.trend.points.length);
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _zoom(double anchor, double scale) {
    setState(() {
      _viewport = _viewport.zoomAround(anchor: anchor, scale: scale);
    });
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
    final visiblePoints = _visiblePoints(widget.trend.points, _viewport);
    final valueStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    if (!widget.trend.hasEnoughPoints) {
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
                '${l10n.sessMetaCacheHitAvg}: ${(widget.trend.averageHitRatio * 100).round()}%',
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
                        widget.trend.averageHitRatio.clamp(0.0, 1.0);
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
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) {
                              return CustomPaint(
                                painter: _TokenPopupCacheHitTrendPainter(
                                  points: visiblePoints,
                                  averageHitRatio: widget.trend.averageHitRatio,
                                  progress: reduceMotion
                                      ? 1
                                      : _controller.value,
                                  colorScheme: colorScheme,
                                ),
                                child: const SizedBox.expand(),
                              );
                            },
                          ),
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
}

class _TokenPopupCacheHitTrendPainter extends CustomPainter {
  const _TokenPopupCacheHitTrendPainter({
    required this.points,
    required this.averageHitRatio,
    required this.progress,
    required this.colorScheme,
  });

  final List<SessionCacheHitTurnPoint> points;
  final double averageHitRatio;
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
    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final dashedPaint = Paint()
      ..color = Colors.green.shade600.withValues(alpha: 0.75)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
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

    for (var i = 0; i <= 4; i++) {
      final ratio = i / 4;
      final y = chart.bottom - chart.height * ratio;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }

    final averageY =
        chart.bottom - chart.height * averageHitRatio.clamp(0.0, 1.0);
    _drawDashedLine(
      canvas,
      Offset(chart.left, averageY),
      Offset(chart.right, averageY),
      dashedPaint,
    );

    final visibleCount = (points.length * progress)
        .clamp(1, points.length)
        .toInt();
    final visible = points.take(visibleCount).toList(growable: false);
    final stepX = visible.length <= 1
        ? chart.width
        : chart.width / (visible.length - 1);
    final linePath = Path();
    final fillPath = Path();
    for (var i = 0; i < visible.length; i++) {
      final x = chart.left + stepX * i;
      final y =
          chart.bottom - chart.height * visible[i].hitRatio.clamp(0.0, 1.0);
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath
          ..moveTo(x, chart.bottom)
          ..lineTo(x, y);
      } else {
        final prevX = chart.left + stepX * (i - 1);
        final prevY =
            chart.bottom -
            chart.height * visible[i - 1].hitRatio.clamp(0.0, 1.0);
        final cp1 = Offset(prevX + stepX * 0.35, prevY);
        final cp2 = Offset(x - stepX * 0.35, y);
        linePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, x, y);
        fillPath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, x, y);
      }
      if (i == visible.length - 1) {
        fillPath
          ..lineTo(x, chart.bottom)
          ..close();
      }
    }
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);

    final last = visible.last;
    final lastOffset = Offset(
      chart.left + stepX * (visible.length - 1),
      chart.bottom - chart.height * last.hitRatio.clamp(0.0, 1.0),
    );
    canvas.drawCircle(lastOffset, 3.6, Paint()..color = colorScheme.primary);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
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

  @override
  bool shouldRepaint(covariant _TokenPopupCacheHitTrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.averageHitRatio != averageHitRatio ||
        oldDelegate.progress != progress ||
        oldDelegate.colorScheme != colorScheme;
  }
}
