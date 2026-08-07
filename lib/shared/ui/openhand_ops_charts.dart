/// 运维面板共用的折线趋势图与占比环画笔。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 图表四周留白与底部标签区高度。
const double _kChartInset = 8;
const double _kChartBottomLabelHeight = 24;

/// 网格线数量：4 条水平、6 条垂直。
const int _kHorizontalGridLines = 4;
const int _kVerticalGridLines = 6;

/// 峰值之上保留的顶部余量比例，避免折线贴着上沿。
const double _kMaxValueHeadroom = 1.14;

const double _kLineStrokeWidth = 2.6;
const double _kAreaFillAlpha = 0.08;
const double _kEndpointDotRadius = 3.4;
const double _kPeakLabelFontSize = 11;
const double _kEmptyLabelFontSize = 12;

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

/// 平滑折线趋势图画笔：网格 + 面积渐隐 + 平滑折线 + 端点圆点 + 峰值标签。
class OpenHandSmoothLineChartPainter extends CustomPainter {
  const OpenHandSmoothLineChartPainter({
    required this.series,
    required this.gridColor,
    required this.labelColor,
    required this.emptyLabel,
    required this.valueSuffix,
    required this.textDirection,
    this.interpolation = OpenHandChartInterpolation.smooth,
  });

  final List<OpenHandChartSeries> series;
  final Color gridColor;
  final Color labelColor;

  /// 全部序列都为零时居中展示的空态文案；留空表示不展示。
  final String emptyLabel;

  /// 峰值标签的单位后缀，如 `ms`。
  final String valueSuffix;

  final TextDirection textDirection;
  final OpenHandChartInterpolation interpolation;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final chart = Rect.fromLTWH(
      _kChartInset,
      _kChartInset,
      math.max(0, size.width - _kChartInset * 2),
      math.max(0, size.height - _kChartBottomLabelHeight),
    );
    // 面板折叠或首帧布局时画布可能为零尺寸，继续画会算出 NaN 坐标。
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

    final maxValue = series
        .expand((item) => item.values)
        .fold<double>(0, math.max);
    if (maxValue <= 0) {
      _paintText(canvas, emptyLabel, bounds.center, centered: true);
      return;
    }

    final normalizedMax = maxValue <= 1 ? 1.0 : maxValue * _kMaxValueHeadroom;
    for (final item in series) {
      if (item.values.isEmpty) continue;
      final denominator = math.max(1, item.values.length - 1);
      final points = List<Offset>.generate(item.values.length, (index) {
        final x = chart.left + chart.width * index / denominator;
        final ratio = (item.values[index] / normalizedMax).clamp(0.0, 1.0);
        return Offset(x, chart.bottom - chart.height * ratio);
      });
      // 单点无法构成折线，向右补一个同高度端点画成水平线。
      if (points.length == 1) {
        points.add(Offset(chart.right, points.first.dy));
      }
      final area = _linePath(points)
        ..lineTo(points.last.dx, chart.bottom)
        ..lineTo(points.first.dx, chart.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()..color = item.color.withValues(alpha: _kAreaFillAlpha),
      );
      canvas.drawPath(
        _linePath(points),
        Paint()
          ..color = item.color
          ..strokeWidth = _kLineStrokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawCircle(
        points.last,
        _kEndpointDotRadius,
        Paint()..color = item.color,
      );
    }

    _paintText(
      canvas,
      '${maxValue.round()}$valueSuffix',
      Offset(chart.left + 2, chart.top + 2),
    );
  }

  /// 相邻点取中点作为二次贝塞尔终点，得到过渡自然且不过冲的折线。
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

  Path _linePath(List<Offset> points) => switch (interpolation) {
    OpenHandChartInterpolation.linear => _linearPath(points),
    OpenHandChartInterpolation.smooth => _smoothPath(points),
    OpenHandChartInterpolation.step => _stepPath(points),
  };

  void _paintText(
    Canvas canvas,
    String value,
    Offset offset, {
    bool centered = false,
  }) {
    if (value.trim().isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: labelColor,
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
          ? Offset(
              offset.dx - painter.width / 2,
              offset.dy - painter.height / 2,
            )
          : offset,
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
        oldDelegate.textDirection != textDirection;
  }
}

/// 占比环的线宽区间与相对尺寸。
const double _kDonutMinStroke = 10;
const double _kDonutMaxStroke = 18;
const double _kDonutStrokeRatio = 0.16;

/// 相邻扇区之间留出的角度缝隙，以及扇区的最小可见角度（弧度）。
const double _kDonutSegmentGap = 0.018;
const double _kDonutMinSweep = 0.03;

/// 运维面板共用的占比环画笔。
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
    final total = values.fold<double>(
      0,
      (sum, value) => sum + math.max(0, value.toDouble()),
    );
    final stroke = math.max(
      _kDonutMinStroke,
      math.min(size.shortestSide * _kDonutStrokeRatio, _kDonutMaxStroke),
    );
    final rect =
        Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2,
      false,
      paint..color = trackColor,
    );
    if (total <= 0 || colors.isEmpty) return;

    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = math.pi * 2 * math.max(0, values[index].toDouble()) / total;
      if (sweep <= 0) continue;
      canvas.drawArc(
        rect,
        start,
        math.max(_kDonutMinSweep, sweep - _kDonutSegmentGap),
        false,
        paint..color = colors[index % colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant OpenHandDonutChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.trackColor != trackColor;
  }
}
