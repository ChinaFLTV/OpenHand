/// 主题无关的运维图表和数据展示组件。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/ui/openhand_spacing.dart';
import 'motion_durations.dart';

/// 图表四周留白与底部标签区高度。
const double _kChartInset = 8;
const double _kChartBottomLabelHeight = 32;
const int _kHorizontalGridLines = 4;
const int _kVerticalGridLines = 6;
const double _kMaxValueHeadroom = 1.14;
const double _kLineStrokeWidth = 2.6;
const double _kAreaFillAlpha = 0.08;
const double _kEndpointDotRadius = 3.4;
const double _kPeakLabelFontSize = 11;
const double _kEmptyLabelFontSize = 12;
const double _kTrendHitRadius = 22;
const double _kDonutMaxStroke = 18;
const double _kDonutStrokeRatio = 0.16;
const double _kDonutSegmentGap = 0.018;
const double _kHeatmapMinCellHeight = 56;
const double _kHeatmapSpacing = 8;
const double _kHeatmapCellPadding = 8;

double _nonNegative(num value) {
  final result = value.toDouble();
  return result.isFinite && result > 0 ? result : 0;
}

double _finite(num value, {double fallback = 0}) {
  final result = value.toDouble();
  return result.isFinite ? result : fallback;
}

/// 固定颜色、标签和值的通用运维图表分段。
///
/// 调用者应为每个分段提供稳定颜色；图表不会循环复用颜色。
class OpenHandChartSegment {
  const OpenHandChartSegment({
    required this.label,
    required this.value,
    required this.color,
    this.valueLabel,
    this.icon,
  });

  final String label;
  final num value;
  final Color color;
  final String? valueLabel;
  final IconData? icon;

  double get safeValue => _nonNegative(value);
}

/// 折线趋势图的一条数据序列。
class OpenHandChartSeries {
  const OpenHandChartSeries({
    required this.label,
    required this.values,
    required this.color,
  });

  final String label;
  final List<double> values;
  final Color color;
}

enum OpenHandChartInterpolation { linear, smooth, step }

/// 平滑折线趋势图画笔：网格 + 面积渐隐 + 折线 + 端点圆点 + 峰值标签。
///
/// 此公共画笔没有交互状态；使用 [OpenHandOperationalTrendChart] 获得可访问的
/// 指针、键盘和语义交互。
class OpenHandSmoothLineChartPainter extends CustomPainter {
  const OpenHandSmoothLineChartPainter({
    required this.series,
    required this.gridColor,
    required this.labelColor,
    required this.emptyLabel,
    required this.valueSuffix,
    required this.textDirection,
    this.interpolation = OpenHandChartInterpolation.smooth,
    this.area = true,
    this.fixedMaximum,
    this.xLabels = const <String>[],
  });

  final List<OpenHandChartSeries> series;
  final Color gridColor;
  final Color labelColor;

  /// 全部序列都为空、非有限或不大于零时居中展示的空态文案；留空表示不展示。
  final String emptyLabel;

  /// 峰值标签的单位后缀，如 `ms`。
  final String valueSuffix;

  final TextDirection textDirection;
  final OpenHandChartInterpolation interpolation;
  final bool area;
  final double? fixedMaximum;
  final List<String> xLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = _lineChartRect(size);
    if (chart.width <= 0 || chart.height <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var index = 0; index < _kHorizontalGridLines; index++) {
      final y = chart.top + chart.height * index / (_kHorizontalGridLines - 1);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    for (var index = 0; index < _kVerticalGridLines; index++) {
      final x = chart.left + chart.width * index / (_kVerticalGridLines - 1);
      canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), gridPaint);
    }

    final seriesMaximum = _seriesMaximum(series);
    final configuredMaximum = fixedMaximum == null
        ? 0.0
        : _nonNegative(fixedMaximum!);
    final maxValue = math.max(seriesMaximum, configuredMaximum);
    if (maxValue <= 0) {
      _paintChartText(
        canvas,
        emptyLabel,
        (Offset.zero & size).center,
        color: labelColor,
        textDirection: textDirection,
        centered: true,
      );
      return;
    }

    final normalizedMax = _normalizedMaximum(maxValue);
    for (final item in series) {
      final points = _linePoints(item.values, chart, normalizedMax);
      final segments = _contiguousLineSegments(points);
      for (final segment in segments) {
        final linePoints = segment.length == 1
            ? <Offset>[
                segment.first,
                Offset(segment.first.dx + 1, segment.first.dy),
              ]
            : segment;
        if (area) {
          final areaPath = _linePath(linePoints, interpolation)
            ..lineTo(linePoints.last.dx, chart.bottom)
            ..lineTo(linePoints.first.dx, chart.bottom)
            ..close();
          canvas.drawPath(
            areaPath,
            Paint()..color = item.color.withValues(alpha: _kAreaFillAlpha),
          );
        }
        canvas.drawPath(
          _linePath(linePoints, interpolation),
          Paint()
            ..color = item.color
            ..strokeWidth = _kLineStrokeWidth
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      final endpoint = points.whereType<Offset>().lastOrNull;
      if (endpoint != null) {
        canvas.drawCircle(
          endpoint,
          _kEndpointDotRadius,
          Paint()..color = item.color,
        );
      }
    }

    _paintChartText(
      canvas,
      '${maxValue.round()}$valueSuffix',
      Offset(chart.left + 2, chart.top + 2),
      color: labelColor,
      textDirection: textDirection,
    );
    _paintTrendAxisLabels(
      canvas,
      chart,
      xLabels,
      color: labelColor,
      textDirection: textDirection,
    );
  }

  @override
  bool shouldRepaint(covariant OpenHandSmoothLineChartPainter oldDelegate) {
    return oldDelegate.series != series ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.emptyLabel != emptyLabel ||
        oldDelegate.valueSuffix != valueSuffix ||
        oldDelegate.interpolation != interpolation ||
        oldDelegate.area != area ||
        oldDelegate.fixedMaximum != fixedMaximum ||
        oldDelegate.xLabels != xLabels ||
        oldDelegate.textDirection != textDirection;
  }
}

Rect _lineChartRect(Size size) {
  return Rect.fromLTWH(
    _kChartInset,
    _kChartInset,
    math.max(0, size.width - _kChartInset * 2),
    math.max(0, size.height - _kChartInset - _kChartBottomLabelHeight),
  );
}

void _paintTrendAxisLabels(
  Canvas canvas,
  Rect chart,
  List<String> labels, {
  required Color color,
  required TextDirection textDirection,
}) {
  if (labels.isEmpty) return;
  final y = chart.bottom + 6;
  _paintChartText(
    canvas,
    labels.first,
    Offset(chart.left, y),
    color: color,
    textDirection: textDirection,
  );
  if (labels.length > 1) {
    _paintChartText(
      canvas,
      labels.last,
      Offset(chart.right, y),
      color: color,
      textDirection: textDirection,
      alignEnd: true,
    );
  }
}

double _seriesMaximum(List<OpenHandChartSeries> series) {
  var maximum = 0.0;
  for (final item in series) {
    for (final value in item.values) {
      maximum = math.max(maximum, _nonNegative(value));
    }
  }
  return maximum;
}

double _normalizedMaximum(double maximum) =>
    maximum <= 1 ? 1 : maximum * _kMaxValueHeadroom;

List<Offset?> _linePoints(
  List<double> values,
  Rect chart,
  double normalizedMaximum,
) {
  if (values.isEmpty || chart.width <= 0 || chart.height <= 0) {
    return const <Offset?>[];
  }
  final denominator = math.max(1, values.length - 1);
  return List<Offset?>.generate(values.length, (index) {
    final value = values[index];
    if (!value.isFinite || value < 0) return null;
    final x = chart.left + chart.width * index / denominator;
    final ratio = (value / normalizedMaximum).clamp(0.0, 1.0);
    return Offset(x, chart.bottom - chart.height * ratio);
  });
}

List<List<Offset>> _contiguousLineSegments(List<Offset?> points) {
  final segments = <List<Offset>>[];
  var current = <Offset>[];
  for (final point in points) {
    if (point == null) {
      if (current.isNotEmpty) segments.add(current);
      current = <Offset>[];
      continue;
    }
    current.add(point);
  }
  if (current.isNotEmpty) segments.add(current);
  return segments;
}

Path _linePath(List<Offset> points, OpenHandChartInterpolation interpolation) {
  if (points.isEmpty) return Path();
  if (points.length == 1) {
    return Path()..moveTo(points.first.dx, points.first.dy);
  }
  return switch (interpolation) {
    OpenHandChartInterpolation.linear => _linearPath(points),
    OpenHandChartInterpolation.smooth => _smoothPath(points),
    OpenHandChartInterpolation.step => _stepPath(points),
  };
}

Path _smoothPath(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var index = 0; index < points.length - 1; index++) {
    final current = points[index];
    final next = points[index + 1];
    final midpoint = Offset(
      (current.dx + next.dx) / 2,
      (current.dy + next.dy) / 2,
    );
    path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
  }
  return path..lineTo(points.last.dx, points.last.dy);
}

Path _linearPath(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final point in points.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  return path;
}

Path _stepPath(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  var previous = points.first;
  for (final point in points.skip(1)) {
    path
      ..lineTo(point.dx, previous.dy)
      ..lineTo(point.dx, point.dy);
    previous = point;
  }
  return path;
}

void _paintChartText(
  Canvas canvas,
  String value,
  Offset offset, {
  required Color color,
  required TextDirection textDirection,
  bool centered = false,
  bool alignEnd = false,
}) {
  if (value.trim().isEmpty) return;
  final painter = TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(
        color: color,
        fontSize: centered ? _kEmptyLabelFontSize : _kPeakLabelFontSize,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: textDirection,
    maxLines: 1,
  )..layout();
  painter.paint(
    canvas,
    centered
        ? Offset(offset.dx - painter.width / 2, offset.dy - painter.height / 2)
        : alignEnd
        ? Offset(offset.dx - painter.width, offset.dy)
        : offset,
  );
}

/// 运维面板共用的占比环画笔。
///
/// 颜色表长度允许与数据段不同；颜色不足时按索引循环，保证数据仍按占比绘制。
class OpenHandDonutChartPainter extends CustomPainter {
  const OpenHandDonutChartPainter({
    required this.values,
    required this.colors,
    required this.trackColor,
  });

  final List<num> values;
  final List<Color> colors;

  /// 底环颜色；总量为零时只画这一圈。
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _donutGeometry(size);
    if (geometry == null) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = geometry.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      geometry.rect,
      -math.pi / 2,
      math.pi * 2,
      false,
      paint..color = trackColor,
    );

    // 颜色表允许比数据段更长或更短；按索引循环取色，避免一个颜色数量
    // 不匹配就整圈回退为未着色轨道。
    if (values.isEmpty || colors.isEmpty) return;
    final count = values.length;
    final pairedValues = List<double>.generate(
      count,
      (index) => _nonNegative(values[index]),
      growable: false,
    );
    final total = pairedValues.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0 || !total.isFinite) return;

    var start = -math.pi / 2;
    for (var index = 0; index < count; index++) {
      final sweep = math.pi * 2 * pairedValues[index] / total;
      if (sweep <= 0 || !sweep.isFinite) continue;
      final gap = math.min(_kDonutSegmentGap, sweep / 3);
      final visibleSweep = math.max(0.0, sweep - gap).toDouble();
      if (visibleSweep > 0) {
        canvas.drawArc(
          geometry.rect,
          start,
          visibleSweep,
          false,
          paint..color = colors[index % colors.length],
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant OpenHandDonutChartPainter oldDelegate) {
    return !_sameNumValues(oldDelegate.values, values) ||
        !_sameColors(oldDelegate.colors, colors) ||
        oldDelegate.trackColor != trackColor;
  }
}

bool _sameNumValues(List<num> left, List<num> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameColors(List<Color> left, List<Color> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

class _DonutGeometry {
  const _DonutGeometry({required this.rect, required this.stroke});

  final Rect rect;
  final double stroke;
}

_DonutGeometry? _donutGeometry(Size size) {
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    return null;
  }
  final side = size.shortestSide;
  if (side <= 0) return null;
  final desired = (side * _kDonutStrokeRatio)
      .clamp(math.min(10.0, side / 2), math.min(_kDonutMaxStroke, side / 2))
      .toDouble();
  final stroke = desired;
  if (stroke <= 0) return null;
  final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
  final rect = Rect.fromLTWH(
    origin.dx + stroke / 2,
    origin.dy + stroke / 2,
    math.max(0, side - stroke),
    math.max(0, side - stroke),
  );
  if (rect.width <= 0 || rect.height <= 0) return null;
  return _DonutGeometry(rect: rect, stroke: stroke);
}

/// 折线图命中的数据点。
class OpenHandOperationalTrendSelection {
  const OpenHandOperationalTrendSelection({
    required this.seriesIndex,
    required this.pointIndex,
    required this.series,
    required this.value,
    this.xLabel,
  });

  final int seriesIndex;
  final int pointIndex;
  final OpenHandChartSeries series;
  final double value;
  final String? xLabel;
}

/// 带实际绘图区命中测试、键盘和语义支持的运维趋势图。
class OpenHandOperationalTrendChart extends StatefulWidget {
  const OpenHandOperationalTrendChart({
    super.key,
    required this.series,
    required this.valueSuffix,
    required this.onSelectionChanged,
    this.onSelectionActivated,
    this.xLabels = const <String>[],
    this.height = 224,
    this.emptyLabel = '暂无可用趋势数据',
    this.interpolation = OpenHandChartInterpolation.smooth,
    this.area = false,
    this.showLegend = true,
    this.externalLegendProvided = false,
    this.fixedMaximum,
    this.formatValue,
    this.semanticLabel = '运维趋势图',
  });

  final List<OpenHandChartSeries> series;
  final String valueSuffix;
  final ValueChanged<OpenHandOperationalTrendSelection?>? onSelectionChanged;
  final ValueChanged<OpenHandOperationalTrendSelection>? onSelectionActivated;
  final List<String> xLabels;
  final double height;
  final String emptyLabel;
  final OpenHandChartInterpolation interpolation;
  final bool area;

  /// Requests an internal legend when the chart has multiple series.
  ///
  /// An internal legend is still rendered when this is false unless the caller
  /// explicitly declares an external legend or table.
  final bool showLegend;
  final bool externalLegendProvided;
  final double? fixedMaximum;
  final String Function(double value)? formatValue;
  final String semanticLabel;

  @override
  State<OpenHandOperationalTrendChart> createState() =>
      _OpenHandOperationalTrendChartState();
}

class _OpenHandOperationalTrendChartState
    extends State<OpenHandOperationalTrendChart> {
  OpenHandOperationalTrendSelection? _selection;

  double get _drawableMaximum => math.max(
    _seriesMaximum(widget.series),
    widget.fixedMaximum == null ? 0.0 : _nonNegative(widget.fixedMaximum!),
  );

  bool get _hasDrawableData => _drawableMaximum > 0;

  @override
  void didUpdateWidget(covariant OpenHandOperationalTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selection;
    if (selected == null) return;
    final refreshed = _selectionFor(selected.seriesIndex, selected.pointIndex);
    if (refreshed == null) {
      _setSelection(null);
      return;
    }
    if (refreshed.value != selected.value ||
        refreshed.series.label != selected.series.label ||
        refreshed.series.color != selected.series.color ||
        refreshed.xLabel != selected.xLabel) {
      _selection = refreshed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSelectionChanged?.call(refreshed);
      });
    }
  }

  void _setSelection(OpenHandOperationalTrendSelection? value) {
    final current = _selection;
    if (current?.seriesIndex == value?.seriesIndex &&
        current?.pointIndex == value?.pointIndex) {
      return;
    }
    setState(() => _selection = value);
    widget.onSelectionChanged?.call(value);
  }

  void _activate(OpenHandOperationalTrendSelection? value) {
    if (value == null) return;
    _setSelection(value);
    widget.onSelectionActivated?.call(value);
  }

  OpenHandOperationalTrendSelection? _selectionFor(
    int seriesIndex,
    int pointIndex,
  ) {
    if (!_hasDrawableData) return null;
    if (seriesIndex < 0 || seriesIndex >= widget.series.length) return null;
    final series = widget.series[seriesIndex];
    if (pointIndex < 0 || pointIndex >= series.values.length) return null;
    final rawValue = series.values[pointIndex];
    if (!rawValue.isFinite || rawValue < 0) return null;
    final value = rawValue;
    return OpenHandOperationalTrendSelection(
      seriesIndex: seriesIndex,
      pointIndex: pointIndex,
      series: series,
      value: value,
      xLabel: pointIndex < widget.xLabels.length
          ? widget.xLabels[pointIndex]
          : null,
    );
  }

  OpenHandOperationalTrendSelection? _selectionForIndex(int index) {
    final preferred = _selection?.seriesIndex;
    if (preferred != null) {
      final value = _selectionFor(preferred, index);
      if (value != null) return value;
    }
    for (
      var seriesIndex = 0;
      seriesIndex < widget.series.length;
      seriesIndex++
    ) {
      final value = _selectionFor(seriesIndex, index);
      if (value != null) return value;
    }
    return null;
  }

  void _moveSelection(int direction) {
    final total = widget.series.fold<int>(
      0,
      (maximum, series) => math.max(maximum, series.values.length),
    );
    if (total == 0) return;
    var target = _selection?.pointIndex ?? (direction > 0 ? -1 : total);
    while (true) {
      target += direction;
      if (target < 0 || target >= total) return;
      final selection = _selectionForIndex(target);
      if (selection == null) continue;
      _setSelection(selection);
      return;
    }
  }

  OpenHandOperationalTrendSelection? _selectionFromOffset(
    Offset position,
    Size size,
  ) {
    final chart = _lineChartRect(size);
    if (position.dx < chart.left ||
        position.dx > chart.right ||
        position.dy < chart.top ||
        position.dy > chart.bottom) {
      return null;
    }
    final maximum = _drawableMaximum;
    if (maximum <= 0) return null;
    final normalizedMaximum = _normalizedMaximum(maximum);
    OpenHandOperationalTrendSelection? best;
    var bestDistanceSquared = _kTrendHitRadius * _kTrendHitRadius;
    for (
      var seriesIndex = 0;
      seriesIndex < widget.series.length;
      seriesIndex++
    ) {
      final points = _linePoints(
        widget.series[seriesIndex].values,
        chart,
        normalizedMaximum,
      );
      for (var pointIndex = 0; pointIndex < points.length; pointIndex++) {
        final point = points[pointIndex];
        if (point == null) continue;
        final distanceSquared = (point - position).distanceSquared;
        if (distanceSquared <= bestDistanceSquared) {
          bestDistanceSquared = distanceSquared;
          best = _selectionFor(seriesIndex, pointIndex);
        }
      }
    }
    return best;
  }

  String _selectionText(OpenHandOperationalTrendSelection? selection) {
    if (selection == null) return '未选择数据点';
    final value =
        widget.formatValue?.call(selection.value) ??
        '${selection.value.toStringAsFixed(1)}${widget.valueSuffix}';
    final time = selection.xLabel == null ? '' : '，${selection.xLabel}';
    return '${selection.series.label} $value$time';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final resolvedHeight = widget.height.isFinite && widget.height > 0
        ? widget.height
        : 224.0;
    final hasDrawableData = _hasDrawableData;
    return RepaintBoundary(
      child: Semantics(
        container: true,
        label: widget.semanticLabel,
        value: _selectionText(_selection),
        hint: hasDrawableData ? '点击或悬停数据点，使用左右方向键切换数据点' : null,
        onTap: hasDrawableData
            ? () => _activate(_selection ?? _selectionForIndex(0))
            : null,
        onIncrease: hasDrawableData ? () => _moveSelection(1) : null,
        onDecrease: hasDrawableData ? () => _moveSelection(-1) : null,
        increasedValue: hasDrawableData ? '下一个数据点' : null,
        decreasedValue: hasDrawableData ? '上一个数据点' : null,
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (!hasDrawableData || event is! KeyDownEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _moveSelection(1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _moveSelection(-1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              _activate(_selection ?? _selectionForIndex(0));
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: SizedBox(
            height: resolvedHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = Size(
                        constraints.maxWidth.isFinite
                            ? constraints.maxWidth
                            : 0,
                        constraints.maxHeight.isFinite
                            ? constraints.maxHeight
                            : 0,
                      );
                      return MouseRegion(
                        cursor: hasDrawableData
                            ? SystemMouseCursors.precise
                            : MouseCursor.defer,
                        onHover: hasDrawableData
                            ? (event) => _setSelection(
                                _selectionFromOffset(event.localPosition, size),
                              )
                            : null,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: hasDrawableData
                              ? (details) => _activate(
                                  _selectionFromOffset(
                                    details.localPosition,
                                    size,
                                  ),
                                )
                              : null,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: OpenHandSmoothLineChartPainter(
                                    series: widget.series,
                                    gridColor: colors.outlineVariant.withValues(
                                      alpha: 0.52,
                                    ),
                                    labelColor: colors.onSurfaceVariant,
                                    emptyLabel: widget.emptyLabel,
                                    valueSuffix: widget.valueSuffix,
                                    textDirection: Directionality.of(context),
                                    interpolation: widget.interpolation,
                                    area: widget.area,
                                    fixedMaximum: widget.fixedMaximum,
                                    xLabels: widget.xLabels,
                                  ),
                                  foregroundPainter: _TrendSelectionPainter(
                                    selection: _selection,
                                    series: widget.series,
                                    fixedMaximum: widget.fixedMaximum,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                              if (_selection != null)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: _ChartTooltip(
                                    label: _selectionText(_selection),
                                    color: _selection!.series.color,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (widget.series.length > 1 &&
                    (widget.showLegend || !widget.externalLegendProvided)) ...[
                  kOpenHandGap8,
                  _ChartLegend(
                    segments: widget.series
                        .map(
                          (series) => OpenHandChartSegment(
                            label: series.label,
                            value: 0,
                            color: series.color,
                          ),
                        )
                        .toList(growable: false),
                    onTap: (seriesIndex) {
                      final series = widget.series[seriesIndex];
                      _setSelection(
                        _selectionFor(
                          seriesIndex,
                          math.max(0, series.values.length - 1),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendSelectionPainter extends CustomPainter {
  const _TrendSelectionPainter({
    required this.selection,
    required this.series,
    required this.fixedMaximum,
    required this.color,
  });

  final OpenHandOperationalTrendSelection? selection;
  final List<OpenHandChartSeries> series;
  final double? fixedMaximum;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final selected = selection;
    if (selected == null || selected.seriesIndex >= series.length) return;
    final chart = _lineChartRect(size);
    final maximum = math.max(
      _seriesMaximum(series),
      fixedMaximum == null ? 0.0 : _nonNegative(fixedMaximum!),
    );
    if (maximum <= 0 || !chart.isFinite) return;
    final points = _linePoints(
      series[selected.seriesIndex].values,
      chart,
      _normalizedMaximum(maximum),
    );
    if (selected.pointIndex >= points.length) return;
    final point = points[selected.pointIndex];
    if (point == null) return;
    canvas.drawLine(
      Offset(point.dx, chart.top),
      Offset(point.dx, chart.bottom),
      Paint()
        ..color = color.withValues(alpha: 0.32)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(point, 5, Paint()..color = selected.series.color);
    canvas.drawCircle(point, 2.25, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrendSelectionPainter oldDelegate) {
    return oldDelegate.selection != selection ||
        oldDelegate.series != series ||
        oldDelegate.fixedMaximum != fixedMaximum ||
        oldDelegate.color != color;
  }
}

/// 占比环命中的分段。
class OpenHandOperationalDonutSelection {
  const OpenHandOperationalDonutSelection({
    required this.index,
    required this.segment,
  });

  final int index;
  final OpenHandChartSegment segment;
}

/// 带实际圆环命中测试、键盘、语义、图例和提示的运维占比环。
class OpenHandOperationalDonutChart extends StatefulWidget {
  const OpenHandOperationalDonutChart({
    super.key,
    required this.segments,
    required this.trackColor,
    required this.onSelectionChanged,
    this.onSegmentTap,
    this.height = 224,
    this.centerLabel,
    this.showLegend = true,
    this.externalLegendProvided = false,
    this.showSelectionHighlight = true,
    this.autofocus = false,
    this.formatValue,
    this.semanticLabel = '运维占比环图',
  });

  final List<OpenHandChartSegment> segments;
  final Color trackColor;
  final ValueChanged<OpenHandOperationalDonutSelection?>? onSelectionChanged;
  final ValueChanged<OpenHandOperationalDonutSelection>? onSegmentTap;
  final double height;
  final String? centerLabel;

  /// Requests an internal legend when the chart has multiple segments.
  ///
  /// An internal legend is still rendered when this is false unless the caller
  /// explicitly declares an external legend or table.
  final bool showLegend;
  final bool externalLegendProvided;
  final bool showSelectionHighlight;
  final bool autofocus;
  final String Function(OpenHandChartSegment segment)? formatValue;
  final String semanticLabel;

  @override
  State<OpenHandOperationalDonutChart> createState() =>
      _OpenHandOperationalDonutChartState();
}

class _OpenHandOperationalDonutChartState
    extends State<OpenHandOperationalDonutChart> {
  OpenHandOperationalDonutSelection? _selection;

  @override
  void didUpdateWidget(covariant OpenHandOperationalDonutChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selection;
    if (selected == null) return;
    if (selected.index >= widget.segments.length) {
      _setSelection(null);
      return;
    }
    final segment = widget.segments[selected.index];
    if (segment.safeValue <= 0) {
      _setSelection(null);
      return;
    }
    if (segment.label != selected.segment.label ||
        segment.value != selected.segment.value ||
        segment.color != selected.segment.color ||
        segment.valueLabel != selected.segment.valueLabel) {
      final refreshed = OpenHandOperationalDonutSelection(
        index: selected.index,
        segment: segment,
      );
      _selection = refreshed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSelectionChanged?.call(refreshed);
      });
    }
  }

  void _setSelection(OpenHandOperationalDonutSelection? value) {
    if (_selection?.index == value?.index) return;
    setState(() => _selection = value);
    widget.onSelectionChanged?.call(value);
  }

  void _activate(OpenHandOperationalDonutSelection value) {
    _setSelection(value);
    widget.onSegmentTap?.call(value);
  }

  OpenHandOperationalDonutSelection? _firstSelection() {
    for (var index = 0; index < widget.segments.length; index++) {
      if (widget.segments[index].safeValue <= 0) continue;
      return OpenHandOperationalDonutSelection(
        index: index,
        segment: widget.segments[index],
      );
    }
    return null;
  }

  void _activateCurrentSelection() {
    final selection = _selection ?? _firstSelection();
    if (selection != null) _activate(selection);
  }

  void _moveSelection(int direction) {
    final valid = <int>[
      for (var index = 0; index < widget.segments.length; index++)
        if (widget.segments[index].safeValue > 0) index,
    ];
    if (valid.isEmpty) return;
    final current = _selection == null ? -1 : valid.indexOf(_selection!.index);
    final target = (current + direction).clamp(0, valid.length - 1);
    _setSelection(
      OpenHandOperationalDonutSelection(
        index: valid[target],
        segment: widget.segments[valid[target]],
      ),
    );
  }

  void _selectFromOffset(Offset position, Size size, {bool activate = false}) {
    final geometry = _donutGeometry(size);
    if (geometry == null) return;
    final center = geometry.rect.center;
    final distance = (position - center).distance;
    final radius = geometry.rect.shortestSide / 2;
    if (distance < radius - geometry.stroke / 2 ||
        distance > radius + geometry.stroke / 2) {
      return;
    }
    final values = widget.segments.map((segment) => segment.safeValue).toList();
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0 || !total.isFinite) return;
    var angle =
        math.atan2(position.dy - center.dy, position.dx - center.dx) +
        math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    var start = 0.0;
    for (var index = 0; index < values.length; index++) {
      final sweep = math.pi * 2 * values[index] / total;
      final gap = math.min(_kDonutSegmentGap, sweep / 3);
      if (angle >= start && angle <= start + math.max(0.0, sweep - gap)) {
        final selection = OpenHandOperationalDonutSelection(
          index: index,
          segment: widget.segments[index],
        );
        if (activate) {
          _activate(selection);
        } else {
          _setSelection(selection);
        }
        return;
      }
      start += sweep;
    }
  }

  String _selectionText(OpenHandOperationalDonutSelection? selection) {
    if (selection == null) return '未选择分段';
    final value =
        widget.formatValue?.call(selection.segment) ??
        selection.segment.valueLabel ??
        _finite(selection.segment.value).toStringAsFixed(1);
    return '${selection.segment.label} $value';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final height = widget.height.isFinite && widget.height > 0
        ? widget.height
        : 224.0;
    final hasDrawableData = _firstSelection() != null;
    return RepaintBoundary(
      child: Semantics(
        container: true,
        label: widget.semanticLabel,
        value: _selectionText(_selection),
        hint: hasDrawableData ? '点击或悬停圆环分段，使用左右方向键切换分段' : null,
        onTap: hasDrawableData ? _activateCurrentSelection : null,
        onIncrease: hasDrawableData ? () => _moveSelection(1) : null,
        onDecrease: hasDrawableData ? () => _moveSelection(-1) : null,
        increasedValue: hasDrawableData ? '下一个分段' : null,
        decreasedValue: hasDrawableData ? '上一个分段' : null,
        child: Focus(
          autofocus: widget.autofocus,
          onKeyEvent: (node, event) {
            if (!hasDrawableData || event is! KeyDownEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _moveSelection(1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _moveSelection(-1);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              _activateCurrentSelection();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final finiteDimensions = <double>[
                        constraints.maxWidth,
                        constraints.maxHeight,
                      ].where((value) => value.isFinite && value > 0);
                      final side = finiteDimensions.isEmpty
                          ? 0.0
                          : finiteDimensions.reduce(math.min);
                      final size = Size.square(side);
                      if (side <= 0) return const SizedBox.shrink();
                      return Center(
                        child: SizedBox.square(
                          dimension: side,
                          child: MouseRegion(
                            cursor: hasDrawableData
                                ? SystemMouseCursors.precise
                                : MouseCursor.defer,
                            onHover: hasDrawableData
                                ? (event) => _selectFromOffset(
                                    event.localPosition,
                                    size,
                                  )
                                : null,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: hasDrawableData
                                  ? (details) => _selectFromOffset(
                                      details.localPosition,
                                      size,
                                      activate: true,
                                    )
                                  : null,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: OpenHandDonutChartPainter(
                                        values: widget.segments
                                            .map((segment) => segment.value)
                                            .toList(growable: false),
                                        colors: widget.segments
                                            .map((segment) => segment.color)
                                            .toList(growable: false),
                                        trackColor: widget.trackColor,
                                      ),
                                      foregroundPainter:
                                          widget.showSelectionHighlight
                                          ? _DonutSelectionPainter(
                                              selection: _selection,
                                              segments: widget.segments,
                                              color: colors.onSurface,
                                            )
                                          : null,
                                    ),
                                  ),
                                  if (widget.centerLabel?.trim().isNotEmpty ??
                                      false)
                                    Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: Text(
                                        widget.centerLabel!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelLarge,
                                      ),
                                    ),
                                  if (_selection != null)
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: _ChartTooltip(
                                        label: _selectionText(_selection),
                                        color: _selection!.segment.color,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (widget.segments.length > 1 &&
                    (widget.showLegend || !widget.externalLegendProvided)) ...[
                  kOpenHandGap8,
                  _ChartLegend(
                    segments: widget.segments,
                    onTap: (index) => _activate(
                      OpenHandOperationalDonutSelection(
                        index: index,
                        segment: widget.segments[index],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutSelectionPainter extends CustomPainter {
  const _DonutSelectionPainter({
    required this.selection,
    required this.segments,
    required this.color,
  });

  final OpenHandOperationalDonutSelection? selection;
  final List<OpenHandChartSegment> segments;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final selected = selection;
    final geometry = _donutGeometry(size);
    if (selected == null ||
        geometry == null ||
        selected.index < 0 ||
        selected.index >= segments.length) {
      return;
    }
    final values = segments.map((segment) => segment.safeValue).toList();
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0 || !total.isFinite) return;
    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = math.pi * 2 * values[index] / total;
      if (index == selected.index && sweep > 0) {
        final gap = math.min(_kDonutSegmentGap, sweep / 3);
        canvas.drawArc(
          geometry.rect.inflate(2),
          start,
          math.max(0.0, sweep - gap).toDouble(),
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
        return;
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutSelectionPainter oldDelegate) {
    return oldDelegate.selection != selection ||
        oldDelegate.segments != segments ||
        oldDelegate.color != color;
  }
}

class _ChartTooltip extends StatelessWidget {
  const _ChartTooltip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label: '提示：$label',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(kOpenHandRadius8),
          border: Border.all(color: color.withValues(alpha: 0.72)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.segments, required this.onTap});

  final List<OpenHandChartSegment> segments;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (var index = 0; index < segments.length; index++)
          Semantics(
            button: true,
            label: '${segments[index].label} 图例',
            child: InkWell(
              borderRadius: BorderRadius.circular(kOpenHandRadius6),
              onTap: () => onTap(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      segments[index].icon ?? Icons.circle,
                      size: 12,
                      color: segments[index].color,
                    ),
                    kOpenHandHGap5,
                    Text(segments[index].label, style: textStyle),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 主题无关的仪表/半圆仪表。颜色由调用者传入。
class OpenHandOperationalMeter extends StatelessWidget {
  const OpenHandOperationalMeter({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.minimum = 0,
    this.maximum = 1,
    this.valueLabel,
    this.helper,
    this.unavailable = false,
    this.semicircular = true,
    this.gaugeSize,
  });

  final String label;
  final num value;
  final Color color;
  final num minimum;
  final num maximum;
  final String? valueLabel;
  final String? helper;
  final bool unavailable;
  final bool semicircular;
  final double? gaugeSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ratio = _meterRatio(value, minimum, maximum);
    final display =
        valueLabel ??
        (unavailable ? '暂未接入' : '${(ratio * 100).toStringAsFixed(1)}%');
    final box = gaugeSize ?? (semicircular ? 96.0 : 112.0);
    final gaugeHeight = semicircular ? box * 0.58 : box;
    return Semantics(
      label: '$label，$display',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: box,
            height: gaugeHeight,
            child: ClipRect(
              child: Align(
                alignment: semicircular
                    ? Alignment.topCenter
                    : Alignment.center,
                child: SizedBox(
                  width: box,
                  height: box,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _MeterPainter(
                        ratio: ratio,
                        color: color,
                        trackColor: colors.surfaceContainerHighest,
                        semicircular: semicircular,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          kOpenHandGap2,
          Text(display, style: Theme.of(context).textTheme.titleMedium),
          if (helper?.trim().isNotEmpty ?? false) ...[
            kOpenHandGap3,
            Text(
              helper!,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

double _meterRatio(num value, num minimum, num maximum) {
  final lower = _finite(minimum);
  final upper = _finite(maximum, fallback: 1);
  final current = _finite(value);
  if (upper <= lower) return 0;
  return ((current - lower) / (upper - lower)).clamp(0.0, 1.0);
}

class _MeterPainter extends CustomPainter {
  const _MeterPainter({
    required this.ratio,
    required this.color,
    required this.trackColor,
    required this.semicircular,
  });

  final double ratio;
  final Color color;
  final Color trackColor;
  final bool semicircular;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final stroke = math.min(12.0, math.max(3.0, size.shortestSide * 0.12));
    final inset = stroke / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      math.max(0, size.width - stroke),
      math.max(0, size.height - stroke),
    );
    if (rect.width <= 0 || rect.height <= 0) return;
    final start = semicircular ? math.pi : -math.pi / 2;
    final sweep = semicircular ? math.pi : math.pi * 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, paint..color = trackColor);
    if (ratio > 0) {
      canvas.drawArc(rect, start, sweep * ratio, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _MeterPainter oldDelegate) {
    return oldDelegate.ratio != ratio ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.semicircular != semicircular;
  }
}

enum OpenHandComparisonBarOrientation { horizontal, vertical }

/// 通用的横向或纵向比较条；每个分段使用调用者提供的颜色。
class OpenHandOperationalComparisonBars extends StatelessWidget {
  const OpenHandOperationalComparisonBars({
    super.key,
    required this.segments,
    required this.orientation,
    this.emptyLabel = '暂无可用数据',
    this.valueLabel,
    this.onSegmentTap,
  });

  final List<OpenHandChartSegment> segments;
  final OpenHandComparisonBarOrientation orientation;
  final String emptyLabel;
  final String Function(OpenHandChartSegment segment)? valueLabel;
  final ValueChanged<OpenHandChartSegment>? onSegmentTap;

  @override
  Widget build(BuildContext context) {
    final maximum = segments.fold<double>(
      0,
      (maximum, segment) => math.max(maximum, segment.safeValue),
    );
    if (maximum <= 0) return _EmptyChartLabel(label: emptyLabel);
    return RepaintBoundary(
      child: Semantics(
        label:
            '比较图，${segments.map((item) => '${item.label} ${_segmentValueLabel(item)}').join('，')}',
        child: orientation == OpenHandComparisonBarOrientation.horizontal
            ? _HorizontalComparisonBars(
                segments: segments,
                maximum: maximum,
                valueLabel: _segmentValueLabel,
                onSegmentTap: onSegmentTap,
              )
            : _VerticalComparisonBars(
                segments: segments,
                maximum: maximum,
                valueLabel: _segmentValueLabel,
                onSegmentTap: onSegmentTap,
              ),
      ),
    );
  }

  String _segmentValueLabel(OpenHandChartSegment segment) {
    return valueLabel?.call(segment) ??
        segment.valueLabel ??
        _finite(segment.value).toStringAsFixed(1);
  }
}

class _ChartActionSurface extends StatefulWidget {
  const _ChartActionSurface({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
  });

  final String semanticLabel;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_ChartActionSurface> createState() => _ChartActionSurfaceState();
}

class _ChartActionSurfaceState extends State<_ChartActionSurface> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    final colors = Theme.of(context).colorScheme;
    final highlighted = _hovered || _focused || _pressed;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      onTap: widget.onTap,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap!();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: kOpenHandMotion120,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: highlighted
                  ? colors.primary.withValues(alpha: _pressed ? 0.14 : 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(kOpenHandRadius6),
              border: Border.all(
                color: _focused
                    ? colors.primary.withValues(alpha: 0.65)
                    : Colors.transparent,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _HorizontalComparisonBars extends StatelessWidget {
  const _HorizontalComparisonBars({
    required this.segments,
    required this.maximum,
    required this.valueLabel,
    required this.onSegmentTap,
  });

  final List<OpenHandChartSegment> segments;
  final double maximum;
  final String Function(OpenHandChartSegment segment) valueLabel;
  final ValueChanged<OpenHandChartSegment>? onSegmentTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final segment in segments) ...[
          _ChartActionSurface(
            semanticLabel: '${segment.label}，${valueLabel(segment)}',
            onTap: onSegmentTap == null ? null : () => onSegmentTap!(segment),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    segment.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                kOpenHandHGap8,
                Expanded(
                  flex: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(kOpenHandRadius4),
                    child: SizedBox(
                      height: 10,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(
                              color: colors.surfaceContainerHighest,
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: (segment.safeValue / maximum).clamp(
                              0.0,
                              1.0,
                            ),
                            child: ColoredBox(color: segment.color),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                kOpenHandHGap8,
                SizedBox(
                  width: 64,
                  child: Text(
                    valueLabel(segment),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
          if (segment != segments.last) kOpenHandGap10,
        ],
      ],
    );
  }
}

class _VerticalComparisonBars extends StatelessWidget {
  const _VerticalComparisonBars({
    required this.segments,
    required this.maximum,
    required this.valueLabel,
    required this.onSegmentTap,
  });

  final List<OpenHandChartSegment> segments;
  final double maximum;
  final String Function(OpenHandChartSegment segment) valueLabel;
  final ValueChanged<OpenHandChartSegment>? onSegmentTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 148,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final segment in segments)
            Expanded(
              child: _ChartActionSurface(
                semanticLabel: '${segment.label}，${valueLabel(segment)}',
                onTap: onSegmentTap == null
                    ? null
                    : () => onSegmentTap!(segment),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        valueLabel(segment),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      kOpenHandGap5,
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: segment.safeValue <= 0
                                ? 0
                                : (segment.safeValue / maximum).clamp(
                                    0.03,
                                    1.0,
                                  ),
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: segment.color,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(kOpenHandRadius4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      kOpenHandGap5,
                      Text(
                        segment.label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 状态分段带。标签、数值、颜色均由调用方明确提供。
class OpenHandOperationalStatusBand extends StatelessWidget {
  const OpenHandOperationalStatusBand({
    super.key,
    required this.segments,
    this.valueLabel,
    this.emptyLabel = '暂无状态数据',
  });

  final List<OpenHandChartSegment> segments;
  final String Function(OpenHandChartSegment segment)? valueLabel;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(
      0,
      (sum, segment) => sum + segment.safeValue,
    );
    if (total <= 0 || !total.isFinite) {
      return _EmptyChartLabel(label: emptyLabel);
    }
    final colors = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Semantics(
        label:
            '状态分布，${segments.map((segment) => '${segment.label} ${_labelFor(segment)}').join('，')}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(kOpenHandRadius7),
              child: SizedBox(
                height: 18,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    var offset = 0.0;
                    return Stack(
                      children: [
                        for (final segment in segments)
                          Builder(
                            builder: (context) {
                              final fraction = segment.safeValue / total;
                              final left = offset;
                              offset += fraction;
                              return Positioned(
                                left: constraints.maxWidth * left,
                                width: constraints.maxWidth * fraction,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1,
                                  ),
                                  color: segment.color,
                                ),
                              );
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            kOpenHandGap10,
            Wrap(
              spacing: 12,
              runSpacing: 7,
              children: [
                for (final segment in segments)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        segment.icon ?? Icons.circle,
                        size: 12,
                        color: segment.color,
                      ),
                      kOpenHandHGap5,
                      Text(
                        '${segment.label} ${_labelFor(segment)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _labelFor(OpenHandChartSegment segment) =>
      valueLabel?.call(segment) ??
      segment.valueLabel ??
      _finite(segment.value).toStringAsFixed(0);
}

/// 通用排行表的一行。警示颜色由调用方显式传入。
class OpenHandOperationalRankRow {
  const OpenHandOperationalRankRow({
    required this.cells,
    required this.value,
    this.highlightColor,
  });

  final List<String> cells;
  final num value;
  final Color? highlightColor;
}

/// 可用于任意运维实体的排名表。
class OpenHandOperationalRankTable extends StatelessWidget {
  const OpenHandOperationalRankTable({
    super.key,
    required this.headers,
    required this.rows,
    this.emptyLabel = '暂无可用数据',
    this.onRowTap,
  });

  final List<String> headers;
  final List<OpenHandOperationalRankRow> rows;
  final String emptyLabel;
  final ValueChanged<OpenHandOperationalRankRow>? onRowTap;

  @override
  Widget build(BuildContext context) {
    if (headers.isEmpty || rows.isEmpty) {
      return _EmptyChartLabel(label: emptyLabel);
    }
    final colors = Theme.of(context).colorScheme;
    final sortedRows = [...rows]
      ..sort(
        (left, right) =>
            _nonNegative(right.value).compareTo(_nonNegative(left.value)),
      );
    return RepaintBoundary(
      child: Semantics(
        label: '排行表，共 ${sortedRows.length} 行',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 0.0;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minWidth),
                child: DataTable(
                  headingRowColor: WidgetStatePropertyAll(
                    colors.surfaceContainerHigh,
                  ),
                  columns: [
                    for (final header in headers)
                      DataColumn(label: Text(header)),
                  ],
                  rows: [
                    for (final row in sortedRows)
                      DataRow(
                        onSelectChanged: onRowTap == null
                            ? null
                            : (_) => onRowTap!(row),
                        color: row.highlightColor == null
                            ? null
                            : WidgetStatePropertyAll(
                                row.highlightColor!.withValues(alpha: 0.08),
                              ),
                        cells: List<DataCell>.generate(
                          headers.length,
                          (index) => DataCell(
                            Text(
                              index < row.cells.length
                                  ? row.cells[index]
                                  : '--',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 网格热力图。单一强度颜色由 [color] 提供，透明度表达数值大小。
class OpenHandOperationalHeatmap extends StatelessWidget {
  const OpenHandOperationalHeatmap({
    super.key,
    required this.segments,
    required this.color,
    this.emptyLabel = '暂无可用数据',
    this.valueLabel,
    this.maxCrossAxisExtent = 150,
    this.columnCountForWidth,
  });

  final List<OpenHandChartSegment> segments;
  final Color color;
  final String emptyLabel;
  final String Function(OpenHandChartSegment segment)? valueLabel;
  final double maxCrossAxisExtent;
  final int Function(double width, int itemCount)? columnCountForWidth;

  @override
  Widget build(BuildContext context) {
    final maximum = segments.fold<double>(
      0,
      (maximum, segment) => math.max(maximum, segment.safeValue),
    );
    if (maximum <= 0) return _EmptyChartLabel(label: emptyLabel);
    final extent = maxCrossAxisExtent.isFinite && maxCrossAxisExtent > 32
        ? maxCrossAxisExtent
        : 150.0;
    return RepaintBoundary(
      child: Semantics(
        label:
            '热力图，${segments.map((segment) => '${segment.label} ${_labelFor(segment)}').join('，')}',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : extent;
            final requestedColumns =
                columnCountForWidth?.call(width, segments.length) ??
                (width / extent).floor();
            final columns = requestedColumns
                .clamp(1, math.max(1, segments.length))
                .toInt();
            final cellWidth = math.max(
              1.0,
              (width - _kHeatmapSpacing * (columns - 1)) / columns,
            );
            final cellHeight = math.max(
              _kHeatmapMinCellHeight,
              cellWidth / 1.65,
            );
            final aspect = cellWidth / cellHeight;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: _kHeatmapSpacing,
              crossAxisSpacing: _kHeatmapSpacing,
              childAspectRatio: aspect.isFinite && aspect > 0 ? aspect : 1,
              children: [
                for (final segment in segments)
                  Builder(
                    builder: (context) {
                      final ratio = (segment.safeValue / maximum).clamp(
                        0.0,
                        1.0,
                      );
                      return Semantics(
                        label: '${segment.label} ${_labelFor(segment)}',
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16 + ratio * 0.84),
                            borderRadius: BorderRadius.circular(
                              kOpenHandRadius9,
                            ),
                            border: Border.all(
                              color: color.withValues(
                                alpha: 0.24 + ratio * 0.5,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(_kHeatmapCellPadding),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    segment.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium,
                                  ),
                                  kOpenHandGap2,
                                  Text(
                                    _labelFor(segment),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _labelFor(OpenHandChartSegment segment) =>
      valueLabel?.call(segment) ??
      segment.valueLabel ??
      _finite(segment.value).toStringAsFixed(0);
}

/// 延迟分位数或范围比较组件。分位数和颜色由调用方提供，不依赖具体服务模型。
class OpenHandOperationalLatencyRange extends StatelessWidget {
  const OpenHandOperationalLatencyRange({
    super.key,
    required this.segments,
    this.emptyLabel = '暂无延迟数据',
    this.valueLabel,
  });

  final List<OpenHandChartSegment> segments;
  final String emptyLabel;
  final String Function(OpenHandChartSegment segment)? valueLabel;

  @override
  Widget build(BuildContext context) {
    final maximum = segments.fold<double>(
      0,
      (maximum, segment) => math.max(maximum, segment.safeValue),
    );
    if (maximum <= 0) return _EmptyChartLabel(label: emptyLabel);
    final colors = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Semantics(
        label:
            '延迟范围，${segments.map((segment) => '${segment.label} ${_labelFor(segment)}').join('，')}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final segment in segments) ...[
              Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      segment.label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: kOpenHandBorderRadius5,
                      child: SizedBox(
                        height: 12,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ColoredBox(
                                color: colors.surfaceContainerHighest,
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: (segment.safeValue / maximum).clamp(
                                0.0,
                                1.0,
                              ),
                              child: ColoredBox(color: segment.color),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  kOpenHandHGap8,
                  SizedBox(
                    width: 68,
                    child: Text(
                      _labelFor(segment),
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
              if (segment != segments.last) kOpenHandGap10,
            ],
          ],
        ),
      ),
    );
  }

  String _labelFor(OpenHandChartSegment segment) =>
      valueLabel?.call(segment) ??
      segment.valueLabel ??
      '${_finite(segment.value).toStringAsFixed(2)} ms';
}

class _EmptyChartLabel extends StatelessWidget {
  const _EmptyChartLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    excludeSemantics: true,
    child: Center(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
