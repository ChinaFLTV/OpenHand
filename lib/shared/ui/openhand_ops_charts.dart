/// 主题无关的运维图表和数据展示组件。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../shared/ui/openhand_spacing.dart';
import '../util/date_time_format.dart';
import '../util/localized_text.dart';
import '../util/timer_safety.dart';
import 'animated_dialog.dart';
import 'appear_once.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_safe_scrollbar.dart';
import 'openhand_table_metric_cells.dart';
import 'openhand_table_pagination.dart';

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
const double _kFillTrackHeight = 10;
const double _kFillTrackRadius = 5;
const double _kVerticalBarChartHeight = 156;
const double _kVerticalBarMaxSlotWidth = 76;
const double _kTrendLaneTrackHeight = 8;
const double _kTrendLaneTimeWidth = 56;
const double _kTrendLaneValueWidth = 72;
const double _kTrendLaneSeriesWidth = 72;
const double _kTrendLaneMaxHeight = 320;
const double _kTrendLaneCompactBreakpoint = 360;
const double _kVerticalBarSlotGap = 14;
const double _kVerticalBarBodyMaxWidth = 42;
const double _kStatusStripHeight = 38;
const double _kStatusStripNamedMaxWidth = 96;
const double _kStatusStripRadius = 4;
const double _kHeatmapHoverMinWidth = 292;
const double _kHeatmapHoverMaxWidth = 372;
const double _kHeatmapHoverMaxHeight = 468;
const double _kHeatmapHoverContentHorizontalPadding = 14;
const double _kHeatmapHoverMetricGap = 8;
const double _kHeatmapHoverMetricMinWidth = 132;
const double _kHeatmapHoverMetricMaxWidth =
    (_kHeatmapHoverMaxWidth -
        _kHeatmapHoverContentHorizontalPadding * 2 -
        _kHeatmapHoverMetricGap) /
    2;
const double _kHeatmapHoverAnchorGap = 10;
const double _kHeatmapHoverViewportPadding = 12;
const double _kHeatmapHoverPreferAboveMin = 168;
const Duration _kHeatmapHoverShowDelay = Duration(milliseconds: 90);
const Duration _kHeatmapHoverExitGrace = Duration(milliseconds: 80);
const double _kRankHeaderHeight = 46;
const double _kRankRowHeight = 58;
const double _kRankBodyMaxHeight = 348;
const int _kRankWidthSampleCap = 400;
const double _kRankCellPadding = 12;
const double _kRankValueMinWidth = 64;
const double _kRankMetricMinWidth = 128;
const double _kRankMetricMaxWidth = 196;
const double _kRankLeadingMinWidth = 148;
const double _kRankLeadingMaxWidth = 280;
const double _kRankCompactMaxWidth = 120;
const double _kRankTextMinWidth = 96;
const double _kRankTextMaxWidth = 280;
const double _kRankDateTimeMinWidth = 168;
const double _kRankResizeHandleWidth = 8;
const double _kRankUserMinWidth = 56;
const double _kRankUserMaxWidth = 720;
final RegExp _kRankDateTimePattern = RegExp(
  r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$',
);
final RegExp _kRankPlaceholderPattern = RegExp(r'^(?:—|--|-|–)$');
final RegExp _kRankCompactCellPattern = RegExp(
  r'^(?:\d+(?:\.\d+)?%|\d+(?:\.\d+)?\s*(?:ms|s|B|KB|MB|GB|TB|PB)|\d+(?:\.\d+)?|\d{1,2}:\d{2}(?::\d{2})?|(?:成功|失败|启用|停用|OK|Fail|On|Off)(?:\s+\d{1,3})?)$',
  caseSensitive: false,
);

KeyEventResult _handleChartNavigationKey({
  required KeyEvent event,
  required bool enabled,
  required ValueChanged<int> moveSelection,
  required VoidCallback activateSelection,
}) {
  if (!enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.arrowDown) {
    moveSelection(1);
  } else if (key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowUp) {
    moveSelection(-1);
  } else if (key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.space) {
    activateSelection();
  } else {
    return KeyEventResult.ignored;
  }
  return KeyEventResult.handled;
}

enum _RankColumnKind { datetime, compact, metric, leading, text }

bool _isRankDateTimeCell(String text) => _kRankDateTimePattern.hasMatch(text);

bool _isRankCompactCell(String text) {
  final value = text.trim();
  if (value.isEmpty || _kRankPlaceholderPattern.hasMatch(value)) return true;
  return _kRankCompactCellPattern.hasMatch(value);
}

bool _rankHeaderPrefersText(String header) {
  final value = header.trim().toLowerCase();
  return value.contains('原因') ||
      value.contains('reason') ||
      value.contains('错误') ||
      value.contains('error');
}

_RankColumnKind _rankColumnKind({
  required int index,
  required String header,
  required Iterable<String> cells,
}) {
  var datetime = _isRankDateTimeCell(header);
  var seen = false;
  var allCompact = true;
  for (final cell in cells) {
    if (_isRankDateTimeCell(cell)) datetime = true;
    final trimmed = cell.trim();
    if (trimmed.isEmpty) continue;
    seen = true;
    if (!_isRankCompactCell(trimmed)) allCompact = false;
  }
  if (datetime) return _RankColumnKind.datetime;
  if (_rankHeaderPrefersText(header)) return _RankColumnKind.text;
  if (openHandIsTableMetricHeader(header)) return _RankColumnKind.metric;
  if (seen && allCompact) return _RankColumnKind.compact;
  if (index == 0) return _RankColumnKind.leading;
  return _RankColumnKind.text;
}

Alignment _rankCellAlignment(int index, String header) {
  if (index == 0) return Alignment.centerLeft;
  if (openHandTableMetricHeaderCenters(header)) return Alignment.center;
  return Alignment.centerRight;
}

double _rankFitColumnWidth(_RankColumnKind kind, double padded) {
  final minWidth = switch (kind) {
    _RankColumnKind.datetime => _kRankDateTimeMinWidth,
    _RankColumnKind.compact => _kRankValueMinWidth,
    _RankColumnKind.metric => _kRankMetricMinWidth,
    _RankColumnKind.leading => _kRankLeadingMinWidth,
    _RankColumnKind.text => _kRankTextMinWidth,
  };
  final maxWidth = switch (kind) {
    _RankColumnKind.datetime => double.infinity,
    _RankColumnKind.compact => _kRankCompactMaxWidth,
    _RankColumnKind.metric => _kRankMetricMaxWidth,
    _RankColumnKind.leading => _kRankLeadingMaxWidth,
    _RankColumnKind.text => _kRankTextMaxWidth,
  };
  if (!maxWidth.isFinite) return math.max(padded, minWidth);
  return padded.clamp(minWidth, maxWidth).toDouble();
}

double _rankTextWidth(
  String text,
  TextStyle? style, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (text.isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

double _nonNegative(num value) {
  final result = value.toDouble();
  return result.isFinite && result > 0 ? result : 0;
}

double _finite(num value, {double fallback = 0}) {
  final result = value.toDouble();
  return result.isFinite ? result : fallback;
}

Color _heatmapForeground(Color tone, ColorScheme colors) {
  final blend = colors.brightness == Brightness.light ? 0.32 : 0.14;
  return Color.lerp(tone, colors.onSurface, blend) ?? tone;
}

/// 热力条着色策略：强度用透明度表达，状态用分段原色表达。
enum OpenHandHeatmapTone { intensity, categorical }

/// 热力悬停卡中的一条指标。
class OpenHandChartTooltipMetric {
  const OpenHandChartTooltipMetric({
    required this.label,
    required this.value,
    this.hint,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData? icon;
  final Color? color;
}

/// 热力色块悬停时的结构化说明，避免只丢两个数字。
class OpenHandChartTooltip {
  const OpenHandChartTooltip({
    required this.title,
    this.subtitle,
    this.badge,
    this.badgeColor,
    this.summary,
    this.metrics = const <OpenHandChartTooltipMetric>[],
    this.notes = const <String>[],
  });

  final String title;
  final String? subtitle;
  final String? badge;
  final Color? badgeColor;
  final String? summary;
  final List<OpenHandChartTooltipMetric> metrics;
  final List<String> notes;

  String get semanticsLabel {
    return [
      title,
      if (badge != null && badge!.trim().isNotEmpty) badge!.trim(),
      if (subtitle != null && subtitle!.trim().isNotEmpty) subtitle!.trim(),
      if (summary != null && summary!.trim().isNotEmpty) summary!.trim(),
      for (final metric in metrics) '${metric.label} ${metric.value}',
      ...notes,
    ].join('，');
  }
}

Rect? _chartTooltipAnchorRect(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

Timer _startChartTooltipShowTimer({
  required BuildContext context,
  required bool Function() shouldShow,
  required OverlayPortalController portal,
  required AnimationController transition,
}) {
  final delay = openHandTickerMotionEnabled(context)
      ? _kHeatmapHoverShowDelay
      : Duration.zero;
  return startSafeTimer(delay, () {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!shouldShow()) return;
      if (!portal.isShowing) portal.show();
      transition.forward();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  });
}

Timer _startChartTooltipHideTimer({
  required bool Function() shouldHide,
  required OverlayPortalController portal,
  required AnimationController transition,
  VoidCallback? onHidden,
}) {
  return startSafeTimer(_kHeatmapHoverExitGrace, () {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!shouldHide()) return;
      try {
        await transition.reverse().orCancel;
      } on TickerCanceled {
        return;
      }
      if (!shouldHide()) return;
      if (portal.isShowing) portal.hide();
      onHidden?.call();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  });
}

Widget _buildChartTooltipOverlay({
  required Rect? anchor,
  required OpenHandChartTooltip tooltip,
  required Color accent,
  required AnimationController transition,
  required DialogAnimationSettings settings,
  required VoidCallback onEnter,
  required VoidCallback onExit,
}) {
  return Positioned.fill(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final metrics = _HeatmapHoverMetrics.resolve(
          context: context,
          overlaySize: Size(constraints.maxWidth, constraints.maxHeight),
          anchor: anchor,
        );
        return CustomSingleChildLayout(
          delegate: _HeatmapHoverLayoutDelegate(metrics),
          child: MouseRegion(
            onEnter: (_) => onEnter(),
            onExit: (_) => onExit(),
            child: AnimatedBuilder(
              animation: transition,
              child: _HeatmapHoverCard(tooltip: tooltip, accent: accent),
              builder: (context, child) => buildAnimationStyleTransition(
                animation: transition,
                settings: settings,
                profile: OpenHandAnimationTransitionProfile(
                  alignment: metrics.placedAbove
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
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

/// 复用运维热力图悬停卡片的通用触发器。
///
/// 适用于状态条、紧凑指标等非图表控件，保持与热力图相同的定位、动画和
/// 边界处理。鼠标移入内容卡片时会保留显示，避免跨越间隙时闪烁。
class OpenHandChartTooltipTrigger extends StatefulWidget {
  const OpenHandChartTooltipTrigger({
    super.key,
    required this.child,
    required this.tooltip,
    required this.accent,
  });

  final Widget child;
  final OpenHandChartTooltip tooltip;
  final Color accent;

  @override
  State<OpenHandChartTooltipTrigger> createState() =>
      _OpenHandChartTooltipTriggerState();
}

class _OpenHandChartTooltipTriggerState
    extends State<OpenHandChartTooltipTrigger>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  late final AnimationController _transition;
  DialogAnimationSettings _settings = OpenHandMotionDefaults.menu;
  Timer? _showTimer;
  Timer? _hideTimer;
  int _generation = 0;
  bool _showQueued = false;
  Rect? _anchorGlobal;

  @override
  void initState() {
    super.initState();
    _transition = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.menu,
    );
    _transition
      ..duration = _settings.entranceDuration
      ..reverseDuration = _settings.exitDuration;
  }

  @override
  void dispose() {
    _generation += 1;
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _transition.dispose();
    super.dispose();
  }

  void _captureAnchor(BuildContext childContext) {
    _anchorGlobal = _chartTooltipAnchorRect(childContext) ?? _anchorGlobal;
  }

  void _show(BuildContext childContext) {
    _hideTimer?.cancel();
    _captureAnchor(childContext);
    _showQueued = true;
    if (_portal.isShowing) {
      _transition.forward();
      return;
    }
    final generation = ++_generation;
    _showTimer?.cancel();
    _showTimer = _startChartTooltipShowTimer(
      context: context,
      shouldShow: () => mounted && _showQueued && generation == _generation,
      portal: _portal,
      transition: _transition,
    );
  }

  void _scheduleHide() {
    _showQueued = false;
    _showTimer?.cancel();
    final generation = ++_generation;
    _hideTimer?.cancel();
    _hideTimer = _startChartTooltipHideTimer(
      shouldHide: () => mounted && !_showQueued && generation == _generation,
      portal: _portal,
      transition: _transition,
    );
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    return _buildChartTooltipOverlay(
      anchor: _anchorGlobal,
      tooltip: widget.tooltip,
      accent: widget.accent,
      transition: _transition,
      settings: _settings,
      onEnter: () {
        _hideTimer?.cancel();
        _showQueued = true;
      },
      onExit: _scheduleHide,
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: Builder(
        builder: (childContext) => MouseRegion(
          cursor: SystemMouseCursors.precise,
          onEnter: (_) => _show(childContext),
          onHover: (_) => _captureAnchor(childContext),
          onExit: (_) => _scheduleHide(),
          child: Semantics(
            label: widget.tooltip.semanticsLabel,
            button: true,
            child: widget.child,
          ),
        ),
      ),
    );
  }
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
    this.tooltip,
  });

  final String label;
  final num value;
  final Color color;
  final String? valueLabel;
  final IconData? icon;
  final OpenHandChartTooltip? tooltip;

  double get safeValue => _nonNegative(value);
}

/// 折线趋势图的一条数据序列。
enum OpenHandTrendAggregation { average, sum, maximum, latest }

class OpenHandChartSeries {
  const OpenHandChartSeries({
    required this.label,
    required this.values,
    required this.color,
    this.aggregation = OpenHandTrendAggregation.average,
  });

  final String label;
  final List<double> values;
  final Color color;
  final OpenHandTrendAggregation aggregation;
}

/// 趋势图当前可见的数据窗口。
class OpenHandTrendViewport {
  const OpenHandTrendViewport({
    required this.startIndex,
    required this.endIndex,
    required this.itemCount,
    this.sampleStride = 1,
  });

  final int startIndex;
  final int endIndex;
  final int itemCount;
  final int sampleStride;

  int get visibleItemCount => math.max(0, endIndex - startIndex);
  int get displayedItemCount => visibleItemCount == 0
      ? 0
      : (visibleItemCount / math.max(1, sampleStride)).ceil();

  List<T> slice<T>(List<T> values) {
    if (values.isEmpty || visibleItemCount == 0) {
      return List<T>.empty();
    }
    final start = startIndex.clamp(0, values.length);
    final end = endIndex.clamp(start, values.length);
    if (sampleStride <= 1) return values.sublist(start, end);
    return [
      for (var index = start; index < end; index += sampleStride)
        values[math.min(end, index + sampleStride) - 1],
    ];
  }

  int sourceIndexForDisplayedIndex(int displayedIndex) {
    final index = startIndex + (displayedIndex + 1) * sampleStride - 1;
    return index.clamp(startIndex, math.max(startIndex, endIndex - 1));
  }

  List<OpenHandChartSeries> sliceSeries(List<OpenHandChartSeries> series) {
    return [
      for (final item in series)
        OpenHandChartSeries(
          label: item.label,
          values: _aggregateTrendValues(item),
          color: item.color,
          aggregation: item.aggregation,
        ),
    ];
  }

  List<double> _aggregateTrendValues(OpenHandChartSeries series) {
    final values = series.values;
    if (values.isEmpty || visibleItemCount == 0) return const <double>[];
    final start = startIndex.clamp(0, values.length);
    final end = endIndex.clamp(start, values.length);
    if (sampleStride <= 1) return values.sublist(start, end);
    final aggregated = <double>[];
    for (var index = start; index < end; index += sampleStride) {
      final bucketEnd = math.min(end, index + sampleStride);
      var count = 0;
      var sum = 0.0;
      var maximum = 0.0;
      var latest = 0.0;
      for (var valueIndex = index; valueIndex < bucketEnd; valueIndex++) {
        final value = values[valueIndex];
        if (!value.isFinite) continue;
        count += 1;
        sum += value;
        maximum = count == 1 ? value : math.max(maximum, value);
        latest = value;
      }
      if (count == 0) {
        aggregated.add(0);
        continue;
      }
      aggregated.add(switch (series.aggregation) {
        OpenHandTrendAggregation.average => sum / count,
        OpenHandTrendAggregation.sum => sum,
        OpenHandTrendAggregation.maximum => maximum,
        OpenHandTrendAggregation.latest => latest,
      });
    }
    return aggregated;
  }
}

typedef OpenHandTrendZoomBuilder =
    Widget Function(BuildContext context, OpenHandTrendViewport viewport);

/// 仅在双指或触控板手势下参与缩放竞争，避免单指拖动阻断弹窗滚动。
class OpenHandTwoFingerScaleGestureDetector extends StatelessWidget {
  const OpenHandTwoFingerScaleGestureDetector({
    super.key,
    required this.child,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.onDoubleTap,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;
  final GestureTapCallback? onDoubleTap;
  final HitTestBehavior behavior;

  @override
  Widget build(BuildContext context) {
    final scale = RawGestureDetector(
      behavior: behavior,
      gestures: <Type, GestureRecognizerFactory>{
        _OpenHandTwoFingerScaleGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _OpenHandTwoFingerScaleGestureRecognizer
            >(_OpenHandTwoFingerScaleGestureRecognizer.new, (recognizer) {
              recognizer
                ..onStart = onScaleStart
                ..onUpdate = onScaleUpdate
                ..onEnd = onScaleEnd
                ..trackpadScrollCausesScale = true;
            }),
      },
      child: child,
    );
    if (onDoubleTap == null) return scale;
    return GestureDetector(
      behavior: behavior,
      onDoubleTap: onDoubleTap,
      child: scale,
    );
  }
}

class _OpenHandTwoFingerScaleGestureRecognizer extends ScaleGestureRecognizer {
  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted && pointerCount < 2) return;
    super.resolve(disposition);
  }
}

/// 统一趋势图双指缩放区域。
///
/// 缩放以双指焦点为锚点，并允许缩放过程中横向移动焦点来平移时间窗口。
/// 单指滚动仍交给外层弹窗；触控板滚动手势按缩放处理。
class OpenHandTrendZoomRegion extends StatefulWidget {
  const OpenHandTrendZoomRegion({
    super.key,
    required this.itemCount,
    required this.builder,
    this.sampleTimes = const <DateTime>[],
    this.sampleLabels = const <String>[],
    this.initialVisibleItemCount,
    this.minVisibleItemCount = 3,
    this.maxDisplayedItemCount = 120,
    this.showToolbar = true,
    this.semanticLabel = '趋势图时间窗口',
  });

  final int itemCount;
  final OpenHandTrendZoomBuilder builder;
  final List<DateTime> sampleTimes;
  final List<String> sampleLabels;
  final int? initialVisibleItemCount;
  final int minVisibleItemCount;
  final int maxDisplayedItemCount;
  final bool showToolbar;
  final String semanticLabel;

  @override
  State<OpenHandTrendZoomRegion> createState() =>
      _OpenHandTrendZoomRegionState();
}

class _OpenHandTrendZoomRegionState extends State<OpenHandTrendZoomRegion> {
  late int _startIndex;
  late int _visibleItemCount;
  int _scaleStartIndex = 0;
  int _scaleStartItemCount = 0;
  double _scaleAnchorIndex = 0;

  int get _safeItemCount => math.max(0, widget.itemCount);

  int get _minimumVisibleItemCount {
    if (_safeItemCount <= 1) return _safeItemCount;
    return widget.minVisibleItemCount.clamp(2, _safeItemCount);
  }

  int get _initialVisibleItemCount {
    if (_safeItemCount == 0) return 0;
    return (widget.initialVisibleItemCount ?? _safeItemCount).clamp(
      _minimumVisibleItemCount,
      _safeItemCount,
    );
  }

  OpenHandTrendViewport get _viewport => OpenHandTrendViewport(
    startIndex: _startIndex,
    endIndex: math.min(_safeItemCount, _startIndex + _visibleItemCount),
    itemCount: _safeItemCount,
    sampleStride: math.max(
      1,
      (_visibleItemCount / math.max(12, widget.maxDisplayedItemCount)).ceil(),
    ),
  );

  bool get _isAtInitialWindow {
    final initialCount = _initialVisibleItemCount;
    return _visibleItemCount == initialCount &&
        _startIndex == math.max(0, _safeItemCount - initialCount);
  }

  @override
  void initState() {
    super.initState();
    _visibleItemCount = _initialVisibleItemCount;
    _startIndex = math.max(0, _safeItemCount - _visibleItemCount);
  }

  @override
  void didUpdateWidget(covariant OpenHandTrendZoomRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCount = math.max(0, oldWidget.itemCount);
    final oldMinimum = oldCount <= 1
        ? oldCount
        : oldWidget.minVisibleItemCount.clamp(2, oldCount);
    final oldInitial = oldCount == 0
        ? 0
        : (oldWidget.initialVisibleItemCount ?? oldCount).clamp(
            oldMinimum,
            oldCount,
          );
    final wasAtInitialWindow =
        _visibleItemCount == oldInitial &&
        _startIndex == math.max(0, oldCount - oldInitial);
    if (wasAtInitialWindow) {
      _visibleItemCount = _initialVisibleItemCount;
      _startIndex = math.max(0, _safeItemCount - _visibleItemCount);
      return;
    }
    final wasPinnedToEnd = _startIndex + _visibleItemCount >= oldCount;
    final minimum = _minimumVisibleItemCount;
    _visibleItemCount = _visibleItemCount.clamp(minimum, _safeItemCount);
    if (wasPinnedToEnd) {
      _startIndex = math.max(0, _safeItemCount - _visibleItemCount);
    } else {
      _startIndex = _startIndex.clamp(
        0,
        math.max(0, _safeItemCount - _visibleItemCount),
      );
    }
  }

  void _handleScaleStart(ScaleStartDetails details, double width) {
    if (_safeItemCount <= _minimumVisibleItemCount || width <= 0) return;
    _scaleStartIndex = _startIndex;
    _scaleStartItemCount = _visibleItemCount;
    final ratio = (details.localFocalPoint.dx / width).clamp(0.0, 1.0);
    _scaleAnchorIndex =
        _scaleStartIndex + ratio * math.max(0, _scaleStartItemCount - 1);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, double width) {
    if (_safeItemCount <= _minimumVisibleItemCount ||
        width <= 0 ||
        details.scale <= 0 ||
        (details.scale - 1).abs() < 0.008) {
      return;
    }
    final visible = (_scaleStartItemCount / details.scale).round().clamp(
      _minimumVisibleItemCount,
      _safeItemCount,
    );
    final ratio = (details.localFocalPoint.dx / width).clamp(0.0, 1.0);
    final start = (_scaleAnchorIndex - ratio * math.max(0, visible - 1))
        .round()
        .clamp(0, math.max(0, _safeItemCount - visible))
        .toInt();
    if (visible == _visibleItemCount && start == _startIndex) return;
    setState(() {
      _visibleItemCount = visible;
      _startIndex = start;
    });
  }

  void _reset() {
    if (_isAtInitialWindow) return;
    setState(() {
      _visibleItemCount = _initialVisibleItemCount;
      _startIndex = math.max(0, _safeItemCount - _visibleItemCount);
    });
  }

  String _windowLabel(BuildContext context, OpenHandTrendViewport viewport) {
    if (viewport.visibleItemCount == 0) {
      return openHandLocalizedText(context, zh: '暂无样本', en: 'No samples');
    }
    final times = widget.sampleTimes;
    if (times.length >= viewport.endIndex) {
      final start = times[viewport.startIndex].toLocal();
      final end = times[viewport.endIndex - 1].toLocal();
      final localizations = MaterialLocalizations.of(context);
      final sameDay =
          start.year == end.year &&
          start.month == end.month &&
          start.day == end.day;
      final startTime = localizations.formatTimeOfDay(
        TimeOfDay.fromDateTime(start),
        alwaysUse24HourFormat: true,
      );
      final endTime = localizations.formatTimeOfDay(
        TimeOfDay.fromDateTime(end),
        alwaysUse24HourFormat: true,
      );
      final range = sameDay
          ? '$startTime–$endTime'
          : '${localizations.formatShortDate(start)} $startTime – '
                '${localizations.formatShortDate(end)} $endTime';
      final intervalMs = viewport.displayedItemCount <= 1
          ? 0
          : end.difference(start).inMilliseconds.abs() ~/
                (viewport.displayedItemCount - 1);
      return openHandLocalizedText(
        context,
        zh: '$range · ${_trendGranularityLabel(intervalMs, true)}',
        en: '$range · ${_trendGranularityLabel(intervalMs, false)}',
      );
    }
    final labels = widget.sampleLabels;
    if (labels.length >= viewport.endIndex) {
      final visible = viewport.slice(labels);
      return openHandLocalizedText(
        context,
        zh: '${visible.first}–${visible.last} · 每点 ${viewport.sampleStride} 个样本',
        en: '${visible.first}–${visible.last} · ${viewport.sampleStride} samples/point',
      );
    }
    return openHandLocalizedText(
      context,
      zh: '显示 ${viewport.visibleItemCount}/${viewport.itemCount} 个样本 · 每点 ${viewport.sampleStride} 个样本',
      en: '${viewport.visibleItemCount}/${viewport.itemCount} samples · ${viewport.sampleStride} samples/point',
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewport = _viewport;
    final colors = Theme.of(context).colorScheme;
    final toolbar = widget.showToolbar
        ? Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  Icons.zoom_in_map_rounded,
                  size: 15,
                  color: colors.primary,
                ),
                kOpenHandHGap6,
                Expanded(
                  child: Text(
                    _windowLabel(context, viewport),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  openHandLocalizedText(
                    context,
                    zh: '双指缩放',
                    en: 'Pinch to zoom',
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                kOpenHandHGap4,
                Tooltip(
                  message: openHandLocalizedText(
                    context,
                    zh: '恢复默认时间窗口',
                    en: 'Reset time window',
                  ),
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: _isAtInitialWindow ? null : _reset,
                    icon: const Icon(
                      Icons.center_focus_strong_rounded,
                      size: 17,
                    ),
                  ),
                ),
              ],
            ),
          )
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Semantics(
          container: true,
          label: widget.semanticLabel,
          hint: _safeItemCount > _minimumVisibleItemCount
              ? openHandLocalizedText(
                  context,
                  zh: '双指缩放调整日期时间范围与粒度，双击恢复默认',
                  en: 'Pinch to adjust the date range and granularity; double tap to reset',
                )
              : null,
          child: OpenHandTwoFingerScaleGestureDetector(
            onDoubleTap: _isAtInitialWindow ? null : _reset,
            onScaleStart: (details) =>
                _handleScaleStart(details, constraints.maxWidth),
            onScaleUpdate: (details) =>
                _handleScaleUpdate(details, constraints.maxWidth),
            child: widget.builder(context, viewport),
          ),
        );
        if (toolbar == null) return content;
        if (constraints.hasBoundedHeight) {
          return Column(
            children: [
              toolbar,
              Expanded(child: content),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [toolbar, content],
        );
      },
    );
  }
}

String _trendGranularityLabel(int milliseconds, bool chinese) {
  if (milliseconds <= 0) return chinese ? '单点' : 'single point';
  final duration = Duration(milliseconds: milliseconds);
  if (duration.inDays >= 1) {
    return chinese ? '每点 ${duration.inDays} 天' : '${duration.inDays} d/point';
  }
  if (duration.inHours >= 1) {
    return chinese
        ? '每点 ${duration.inHours} 小时'
        : '${duration.inHours} h/point';
  }
  if (duration.inMinutes >= 1) {
    return chinese
        ? '每点 ${duration.inMinutes} 分钟'
        : '${duration.inMinutes} min/point';
  }
  return chinese
      ? '每点 ${math.max(1, duration.inSeconds)} 秒'
      : '${math.max(1, duration.inSeconds)} s/point';
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
      _paintTrendAxisLabels(
        canvas,
        chart,
        xLabels,
        color: labelColor,
        textDirection: textDirection,
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

typedef OpenHandTrendTooltipLabelBuilder =
    String Function(OpenHandOperationalTrendSelection selection);

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
    this.tooltipLabelBuilder,
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

  /// 多序列时是否请求内部图例；没有外部图例或表格时仍会显示。
  final bool showLegend;
  final bool externalLegendProvided;
  final double? fixedMaximum;
  final String Function(double value)? formatValue;
  final OpenHandTrendTooltipLabelBuilder? tooltipLabelBuilder;
  final String semanticLabel;

  @override
  State<OpenHandOperationalTrendChart> createState() =>
      _OpenHandOperationalTrendChartState();
}

class _OpenHandOperationalTrendChartState
    extends State<OpenHandOperationalTrendChart> {
  OpenHandOperationalTrendSelection? _selection;
  Offset? _lastTooltipAnchor;

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
    final tooltipLabel = widget.tooltipLabelBuilder?.call(selection).trim();
    if (tooltipLabel?.isNotEmpty == true) return tooltipLabel!;
    final value =
        widget.formatValue?.call(selection.value) ??
        '${selection.value.toStringAsFixed(1)}${widget.valueSuffix}';
    final time = selection.xLabel == null ? '' : '，${selection.xLabel}';
    return '${selection.series.label} $value$time';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tooltipMotion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
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
          onKeyEvent: (_, event) => _handleChartNavigationKey(
            event: event,
            enabled: hasDrawableData,
            moveSelection: _moveSelection,
            activateSelection: () =>
                _activate(_selection ?? _selectionForIndex(0)),
          ),
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
                      final tooltipAnchor = _selectionOffset(size);
                      if (tooltipAnchor != null) {
                        _lastTooltipAnchor = tooltipAnchor;
                      }
                      return MouseRegion(
                        cursor: hasDrawableData
                            ? SystemMouseCursors.precise
                            : MouseCursor.defer,
                        onExit: hasDrawableData
                            ? (_) => _setSelection(null)
                            : null,
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
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomSingleChildLayout(
                                    delegate: _TrendTooltipLayoutDelegate(
                                      anchor:
                                          tooltipAnchor ?? _lastTooltipAnchor,
                                    ),
                                    child: AnimatedSwitcher(
                                      duration: tooltipMotion.entranceDuration,
                                      reverseDuration:
                                          tooltipMotion.exitDuration,
                                      transitionBuilder: (child, animation) =>
                                          buildAnimationStyleTransition(
                                            animation: animation,
                                            settings: tooltipMotion,
                                            profile:
                                                const OpenHandAnimationTransitionProfile(
                                                  alignment:
                                                      Alignment.bottomCenter,
                                                  fadeScaleBegin: 0.9,
                                                  elasticScaleBegin: 0.9,
                                                  springScaleBegin: 0.9,
                                                ),
                                            child: child,
                                          ),
                                      child: _selection == null
                                          ? const SizedBox.shrink(
                                              key: ValueKey<String>(
                                                'trend-tooltip-hidden',
                                              ),
                                            )
                                          : _ChartTooltip(
                                              key: const ValueKey<String>(
                                                'trend-tooltip-visible',
                                              ),
                                              label: _selectionText(_selection),
                                              color: _selection!.series.color,
                                            ),
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

  Offset? _selectionOffset(Size size) {
    final selection = _selection;
    if (selection == null ||
        selection.seriesIndex < 0 ||
        selection.seriesIndex >= widget.series.length) {
      return null;
    }
    final chart = _lineChartRect(size);
    final points = _linePoints(
      widget.series[selection.seriesIndex].values,
      chart,
      _normalizedMaximum(_drawableMaximum),
    );
    if (selection.pointIndex < 0 || selection.pointIndex >= points.length) {
      return null;
    }
    return points[selection.pointIndex];
  }
}

/// 具备统一双指缩放、时间窗口与粒度提示的运维趋势图。
class OpenHandZoomableOperationalTrendChart extends StatelessWidget {
  const OpenHandZoomableOperationalTrendChart({
    super.key,
    required this.series,
    required this.valueSuffix,
    required this.onSelectionChanged,
    this.onSelectionActivated,
    this.xLabels = const <String>[],
    this.sampleTimes = const <DateTime>[],
    this.height = 250,
    this.emptyLabel = '暂无可用趋势数据',
    this.interpolation = OpenHandChartInterpolation.smooth,
    this.area = false,
    this.showLegend = true,
    this.externalLegendProvided = false,
    this.fixedMaximum,
    this.formatValue,
    this.tooltipLabelBuilder,
    this.semanticLabel = '运维趋势图',
    this.initialVisibleItemCount,
    this.minVisibleItemCount = 3,
    this.showZoomToolbar = true,
  });

  final List<OpenHandChartSeries> series;
  final String valueSuffix;
  final ValueChanged<OpenHandOperationalTrendSelection?>? onSelectionChanged;
  final ValueChanged<OpenHandOperationalTrendSelection>? onSelectionActivated;
  final List<String> xLabels;
  final List<DateTime> sampleTimes;
  final double height;
  final String emptyLabel;
  final OpenHandChartInterpolation interpolation;
  final bool area;
  final bool showLegend;
  final bool externalLegendProvided;
  final double? fixedMaximum;
  final String Function(double value)? formatValue;
  final OpenHandTrendTooltipLabelBuilder? tooltipLabelBuilder;
  final String semanticLabel;
  final int? initialVisibleItemCount;
  final int minVisibleItemCount;
  final bool showZoomToolbar;

  int get _itemCount {
    var count = math.max(xLabels.length, sampleTimes.length);
    for (final item in series) {
      count = math.max(count, item.values.length);
    }
    return count;
  }

  OpenHandOperationalTrendSelection? _sourceSelection(
    OpenHandOperationalTrendSelection? selection,
    OpenHandTrendViewport viewport,
  ) {
    if (selection == null ||
        selection.seriesIndex < 0 ||
        selection.seriesIndex >= series.length) {
      return null;
    }
    final sourceIndex = viewport.sourceIndexForDisplayedIndex(
      selection.pointIndex,
    );
    final sourceSeries = series[selection.seriesIndex];
    if (sourceIndex < 0 || sourceIndex >= sourceSeries.values.length) {
      return null;
    }
    return OpenHandOperationalTrendSelection(
      seriesIndex: selection.seriesIndex,
      pointIndex: sourceIndex,
      series: sourceSeries,
      value: sourceSeries.values[sourceIndex],
      xLabel: sourceIndex < xLabels.length ? xLabels[sourceIndex] : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedHeight = height.isFinite && height > 0 ? height : 250.0;
    return SizedBox(
      height: resolvedHeight,
      child: OpenHandTrendZoomRegion(
        itemCount: _itemCount,
        sampleTimes: sampleTimes,
        sampleLabels: xLabels,
        initialVisibleItemCount: initialVisibleItemCount,
        minVisibleItemCount: minVisibleItemCount,
        showToolbar: showZoomToolbar,
        semanticLabel: semanticLabel,
        builder: (context, viewport) {
          final visibleSeries = viewport.sliceSeries(series);
          final visibleLabels = viewport.slice(xLabels);
          return LayoutBuilder(
            builder: (context, constraints) => OpenHandOperationalTrendChart(
              key: ValueKey<(int, int)>((
                viewport.startIndex,
                viewport.endIndex,
              )),
              series: visibleSeries,
              valueSuffix: valueSuffix,
              xLabels: visibleLabels,
              height: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : resolvedHeight,
              emptyLabel: emptyLabel,
              interpolation: interpolation,
              area: area,
              showLegend: showLegend,
              externalLegendProvided: externalLegendProvided,
              fixedMaximum: fixedMaximum,
              formatValue: formatValue,
              tooltipLabelBuilder: tooltipLabelBuilder == null
                  ? null
                  : (selection) => tooltipLabelBuilder!(
                      _sourceSelection(selection, viewport) ?? selection,
                    ),
              semanticLabel: semanticLabel,
              onSelectionChanged: onSelectionChanged == null
                  ? null
                  : (selection) => onSelectionChanged!(
                      _sourceSelection(selection, viewport),
                    ),
              onSelectionActivated: onSelectionActivated == null
                  ? null
                  : (selection) {
                      final source = _sourceSelection(selection, viewport);
                      if (source != null) onSelectionActivated!(source);
                    },
            ),
          );
        },
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

  /// 多分段时是否请求内部图例；没有外部图例或表格时仍会显示。
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
          onKeyEvent: (_, event) => _handleChartNavigationKey(
            event: event,
            enabled: hasDrawableData,
            moveSelection: _moveSelection,
            activateSelection: _activateCurrentSelection,
          ),
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

class _TrendTooltipLayoutDelegate extends SingleChildLayoutDelegate {
  const _TrendTooltipLayoutDelegate({required this.anchor});

  final Offset? anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(0, math.min(300, constraints.maxWidth - 16)),
      maxHeight: math.max(0, constraints.maxHeight - 16),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final point = anchor ?? Offset(size.width / 2, 8);
    final left = (point.dx - childSize.width / 2)
        .clamp(8.0, math.max(8.0, size.width - childSize.width - 8))
        .toDouble();
    final preferredTop = point.dy - childSize.height - 14;
    final top = preferredTop >= 8
        ? preferredTop
        : math.min(size.height - childSize.height - 8, point.dy + 14);
    return Offset(left, math.max(8.0, top).toDouble());
  }

  @override
  bool shouldRelayout(covariant _TrendTooltipLayoutDelegate oldDelegate) =>
      oldDelegate.anchor != anchor;
}

class _ChartTooltip extends StatelessWidget {
  const _ChartTooltip({super.key, required this.label, required this.color});

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
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              kOpenHandHGap8,
              Flexible(
                child: Text(
                  label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 运维图表共用的圆点图例标签。
class OpenHandChartLegendLabel extends StatelessWidget {
  const OpenHandChartLegendLabel({
    super.key,
    required this.label,
    required this.color,
    this.indicatorSize = 8,
    this.gap = 5,
    this.textStyle,
  });

  final String label;
  final Color color;
  final double indicatorSize;
  final double gap;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: indicatorSize,
          height: indicatorSize,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: gap),
        Text(label, style: textStyle ?? Theme.of(context).textTheme.labelSmall),
      ],
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
    final gaugeHeight = semicircular ? box * 0.62 : box;
    return Semantics(
      label: '$label，$display',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: box,
            height: gaugeHeight,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minWidth: box,
                maxWidth: box,
                minHeight: box,
                maxHeight: box,
                child: SizedBox(
                  width: box,
                  height: box,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _MeterPainter(
                        ratio: ratio,
                        color: color,
                        trackColor: colors.onSurface.withValues(alpha: 0.12),
                        semicircular: semicircular,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          kOpenHandGap8,
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

/// 趋势图配套的分钟泳道：按时间铺满宽度，用色条表达各序列，而不是窄列表。
class OpenHandOperationalTrendLanes extends StatelessWidget {
  const OpenHandOperationalTrendLanes({
    super.key,
    required this.series,
    required this.xLabels,
    this.valueSuffix = '',
    this.formatValue,
  });

  final List<OpenHandChartSeries> series;
  final List<String> xLabels;
  final String valueSuffix;
  final String Function(double value)? formatValue;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) return const SizedBox.shrink();
    final length = math.max(
      xLabels.length,
      series.fold<int>(0, (max, item) => math.max(max, item.values.length)),
    );
    final indexes = <int>[
      for (var i = length - 1; i >= 0; i--)
        if (series.any((item) => i < item.values.length && item.values[i] > 0))
          i,
    ];
    if (indexes.isEmpty) return const SizedBox.shrink();
    var maximum = 0.0;
    for (final item in series) {
      for (final value in item.values) {
        maximum = math.max(maximum, _nonNegative(value));
      }
    }
    if (maximum <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final text = openHandTextResolver(context);
    final track = theme.colorScheme.onSurface.withValues(alpha: 0.08);
    final named = series.length > 1;
    return Semantics(
      label: text(
        zh: '趋势明细，共 ${indexes.length} 个时段',
        en: 'Trend detail, ${indexes.length} intervals',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          kOpenHandGap14,
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _kTrendLaneMaxHeight),
            child: ListView.separated(
              shrinkWrap: true,
              primary: false,
              padding: EdgeInsets.zero,
              physics: openHandDialogAwareScrollPhysics(context),
              itemCount: indexes.length,
              separatorBuilder: (_, index) => kOpenHandGap8,
              itemBuilder: (context, n) {
                final index = indexes[n];
                return _laneCard(
                  theme: theme,
                  track: track,
                  named: named,
                  maximum: maximum,
                  label: index < xLabels.length ? xLabels[index] : '$index',
                  values: [
                    for (final item in series)
                      index < item.values.length
                          ? _nonNegative(item.values[index])
                          : 0.0,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _laneValue(double value) {
    if (formatValue != null) return formatValue!(value);
    final rounded = value.round();
    return valueSuffix.isEmpty ? '$rounded' : '$rounded$valueSuffix';
  }

  Widget _laneCard({
    required ThemeData theme,
    required Color track,
    required bool named,
    required double maximum,
    required String label,
    required List<double> values,
  }) {
    var lead = series.first.color;
    var leadValue = 0.0;
    for (var i = 0; i < series.length && i < values.length; i++) {
      if (values[i] >= leadValue) {
        leadValue = values[i];
        lead = series[i].color;
      }
    }
    final tracks = <Widget>[
      for (var i = 0; i < series.length; i++) ...[
        if (i != 0) kOpenHandGap6,
        Row(
          children: [
            if (named) ...[
              SizedBox(
                width: _kTrendLaneSeriesWidth,
                child: Text(
                  series[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: series[i].color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              kOpenHandHGap8,
            ],
            Expanded(
              child: _ChartFillTrack(
                ratio: maximum <= 0 || i >= values.length
                    ? 0
                    : values[i] / maximum,
                color: series[i].color,
                trackColor: track,
                height: _kTrendLaneTrackHeight,
              ),
            ),
            kOpenHandHGap8,
            SizedBox(
              width: _kTrendLaneValueWidth,
              child: Text(
                _laneValue(i < values.length ? values[i] : 0),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: series[i].color,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ],
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: lead.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
        border: Border.all(color: lead.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final time = Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            );
            if (constraints.maxWidth < _kTrendLaneCompactBreakpoint) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [time, kOpenHandGap8, ...tracks],
              );
            }
            return Row(
              children: [
                SizedBox(width: _kTrendLaneTimeWidth, child: time),
                kOpenHandHGap10,
                Expanded(child: Column(children: tracks)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 将趋势图、时间窗口缩放和同轴明细统一为一个可复用组件。
class OpenHandOperationalTrendDetail extends StatelessWidget {
  const OpenHandOperationalTrendDetail({
    super.key,
    required this.title,
    required this.series,
    required this.sampleTimes,
    required this.emptyLabel,
    this.valueSuffix = '',
    this.initialVisibleItemCount,
  });

  final String title;
  final List<OpenHandChartSeries> series;
  final List<DateTime> sampleTimes;
  final String emptyLabel;
  final String valueSuffix;
  final int? initialVisibleItemCount;

  @override
  Widget build(BuildContext context) {
    return OpenHandTrendZoomRegion(
      itemCount: series.fold<int>(
        sampleTimes.length,
        (count, item) => math.max(count, item.values.length),
      ),
      sampleTimes: sampleTimes,
      initialVisibleItemCount: initialVisibleItemCount,
      semanticLabel: '$title，支持双指缩放',
      builder: (context, viewport) {
        final visibleSeries = viewport.sliceSeries(series);
        final labels = List<String>.generate(viewport.displayedItemCount, (
          index,
        ) {
          final sourceIndex = viewport.sourceIndexForDisplayedIndex(index);
          return sourceIndex < sampleTimes.length
              ? formatHourMinuteLocal(sampleTimes[sourceIndex])
              : '#${sourceIndex + 1}';
        }, growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OpenHandOperationalTrendChart(
              series: visibleSeries,
              valueSuffix: valueSuffix,
              xLabels: labels,
              emptyLabel: emptyLabel,
              area: true,
              showLegend: false,
              externalLegendProvided: true,
              onSelectionChanged: null,
            ),
            OpenHandOperationalTrendLanes(
              series: visibleSeries,
              xLabels: labels,
              valueSuffix: valueSuffix,
            ),
          ],
        );
      },
    );
  }
}

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

class _ChartFillTrack extends StatelessWidget {
  const _ChartFillTrack({
    required this.ratio,
    required this.color,
    required this.trackColor,
    this.height = _kFillTrackHeight,
  });

  final double ratio;
  final Color color;
  final Color trackColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final factor = ratio.isFinite ? ratio.clamp(0.0, 1.0).toDouble() : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_kFillTrackRadius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: factor),
              duration: kOpenHandMotion420,
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                if (value <= 0) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: value,
                    heightFactor: 1,
                    child: ColoredBox(color: color),
                  ),
                );
              },
            ),
          ],
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
    final track = colors.onSurface.withValues(alpha: 0.08);
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
                  child: _ChartFillTrack(
                    ratio: maximum <= 0 ? 0 : segment.safeValue / maximum,
                    color: segment.color,
                    trackColor: track,
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
    final track = colors.onSurface.withValues(alpha: 0.08);
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = math.max(1, segments.length);
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _kVerticalBarMaxSlotWidth * n;
        final even = (available - _kVerticalBarSlotGap * (n - 1)) / n;
        final slotWidth = even.clamp(4.0, _kVerticalBarMaxSlotWidth);
        final total = slotWidth * n + _kVerticalBarSlotGap * (n - 1);
        final bodyWidth = math.min(
          _kVerticalBarBodyMaxWidth,
          math.max(8.0, slotWidth - 8),
        );
        return SizedBox(
          height: _kVerticalBarChartHeight,
          width: double.infinity,
          child: Align(
            child: SizedBox(
              width: math.min(total, available),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < segments.length; i++) ...[
                    if (i != 0) const SizedBox(width: _kVerticalBarSlotGap),
                    SizedBox(
                      width: slotWidth,
                      child: _ChartActionSurface(
                        semanticLabel:
                            '${segments[i].label}，${valueLabel(segments[i])}',
                        onTap: onSegmentTap == null
                            ? null
                            : () => onSegmentTap!(segments[i]),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              valueLabel(segments[i]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            kOpenHandGap5,
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: SizedBox(
                                  width: bodyWidth,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: track,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(
                                                  kOpenHandRadius6,
                                                ),
                                              ),
                                        ),
                                      ),
                                      TweenAnimationBuilder<double>(
                                        tween: Tween<double>(
                                          begin: 0,
                                          end: segments[i].safeValue <= 0
                                              ? 0
                                              : (segments[i].safeValue /
                                                        maximum)
                                                    .clamp(0.04, 1.0),
                                        ),
                                        duration: kOpenHandMotion420,
                                        curve: Curves.easeOutCubic,
                                        builder: (context, value, _) {
                                          if (value <= 0) {
                                            return const SizedBox.shrink();
                                          }
                                          return Align(
                                            alignment: Alignment.bottomCenter,
                                            child: FractionallySizedBox(
                                              heightFactor: value,
                                              widthFactor: 1,
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: segments[i].color,
                                                  borderRadius:
                                                      const BorderRadius.vertical(
                                                        top: Radius.circular(
                                                          kOpenHandRadius6,
                                                        ),
                                                      ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            kOpenHandGap5,
                            Text(
                              segments[i].label,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
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

/// 通用排行表的一行。
class OpenHandOperationalRankRow {
  const OpenHandOperationalRankRow({
    required this.cells,
    required this.value,
    this.subtitle = '',
    this.cellSubtitles,
    this.cellWidgets,
    this.data,
    this.rowKey,
  });

  final List<String> cells;
  final num value;
  final String subtitle;
  final List<String>? cellSubtitles;
  final List<Widget?>? cellWidgets;
  final Object? data;
  final Object? rowKey;
}

/// 可用于任意运维实体的排名表。视觉对齐用量分析表：圆角边框、表头灰底、奇偶行。
/// 列宽按列类型适配：时间列完整展示，数值列紧凑，原因等文本列限宽省略；表头可拖拽调宽，省略内容悬停看全文。
class OpenHandOperationalRankTable extends StatefulWidget {
  const OpenHandOperationalRankTable({
    super.key,
    required this.headers,
    required this.rows,
    this.emptyLabel = '暂无可用数据',
    this.onRowTap,
    this.sortByValue = true,
    this.maxBodyHeight = _kRankBodyMaxHeight,
    this.minimumColumnWidths = const <int, double>{},
    this.columnAlignments = const <int, Alignment>{},
    this.paginate = true,
    this.footer,
    this.animateRows = false,
    this.semanticsLabel = '排行表',
    this.scrollResetKey,
  });

  final List<String> headers;
  final List<OpenHandOperationalRankRow> rows;
  final String emptyLabel;
  final ValueChanged<OpenHandOperationalRankRow>? onRowTap;
  final bool sortByValue;
  final double maxBodyHeight;
  final Map<int, double> minimumColumnWidths;
  final Map<int, Alignment> columnAlignments;
  final bool paginate;
  final Widget? footer;
  final bool animateRows;
  final String semanticsLabel;
  final Object? scrollResetKey;

  @override
  State<OpenHandOperationalRankTable> createState() =>
      _OpenHandOperationalRankTableState();
}

class _OpenHandOperationalRankTableState
    extends State<OpenHandOperationalRankTable>
    with SingleTickerProviderStateMixin {
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();
  final OverlayPortalController _portal = OverlayPortalController();
  late final AnimationController _transition;
  DialogAnimationSettings _motion = OpenHandMotionDefaults.menu;
  List<double>? _userWidths;
  bool _userResized = false;
  int? _dragColumn;
  int? _hoverHandle;
  double _dragOriginWidth = 0;
  double _dragStartX = 0;
  Timer? _showTimer;
  Timer? _hideTimer;
  int _generation = 0;
  bool _showQueued = false;
  Rect? _anchorGlobal;
  OpenHandChartTooltip? _activeTooltip;
  Color? _activeAccent;
  int _page = 1;
  int _pageSize = kOpenHandTableDefaultPageSize;

  @override
  void initState() {
    super.initState();
    _transition = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.menu,
    );
    _motion = settings;
    _transition
      ..duration = settings.entranceDuration
      ..reverseDuration = settings.exitDuration;
  }

  @override
  void didUpdateWidget(covariant OpenHandOperationalRankTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.headers.length != widget.headers.length) {
      _userWidths = null;
      _userResized = false;
    }
    if (oldWidget.scrollResetKey != widget.scrollResetKey) {
      _scheduleHideTip();
      if (_vertical.hasClients && _vertical.offset > 0) {
        _vertical.jumpTo(0);
      }
    }
    final window = OpenHandPageWindow.normalize(
      page: _page,
      pageSize: _pageSize,
      total: widget.rows.length,
    );
    _page = window.page;
    _pageSize = window.pageSize;
  }

  @override
  void dispose() {
    _generation += 1;
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _transition.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  List<double> _syncWidths(List<double> natural) {
    final current = _userWidths;
    if (_userResized && current != null && current.length == natural.length) {
      return current;
    }
    if (current != null && current.length == natural.length) {
      var close = true;
      for (var i = 0; i < current.length; i++) {
        if ((current[i] - natural[i]).abs() > 0.5) {
          close = false;
          break;
        }
      }
      if (close) return current;
    }
    final next = List<double>.from(natural);
    _userWidths = next;
    return next;
  }

  void _captureAnchor(BuildContext cellContext) {
    _anchorGlobal = _chartTooltipAnchorRect(cellContext) ?? _anchorGlobal;
  }

  void _showCellTip({
    required BuildContext cellContext,
    required String title,
    required String body,
    String note = '',
    required Color accent,
  }) {
    if (_dragColumn != null) return;
    _hideTimer?.cancel();
    _activeTooltip = OpenHandChartTooltip(
      title: title,
      badge: '完整内容',
      badgeColor: accent,
      summary: body,
      notes: note.trim().isEmpty ? const <String>[] : <String>[note.trim()],
    );
    _activeAccent = accent;
    _captureAnchor(cellContext);
    _showQueued = true;
    if (_portal.isShowing) {
      _transition.forward();
      return;
    }
    final generation = ++_generation;
    _showTimer?.cancel();
    _showTimer = _startChartTooltipShowTimer(
      context: context,
      shouldShow: () => mounted && _showQueued && generation == _generation,
      portal: _portal,
      transition: _transition,
    );
  }

  void _scheduleHideTip() {
    _showQueued = false;
    _showTimer?.cancel();
    final generation = ++_generation;
    _hideTimer?.cancel();
    _hideTimer = _startChartTooltipHideTimer(
      shouldHide: () => mounted && !_showQueued && generation == _generation,
      portal: _portal,
      transition: _transition,
    );
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final tooltip = _activeTooltip;
    final accent =
        _activeAccent ?? Theme.of(overlayContext).colorScheme.primary;
    if (tooltip == null) return const SizedBox.shrink();
    return _buildChartTooltipOverlay(
      anchor: _anchorGlobal,
      tooltip: tooltip,
      accent: accent,
      transition: _transition,
      settings: _motion,
      onEnter: () {
        _hideTimer?.cancel();
        _showQueued = true;
      },
      onExit: _scheduleHideTip,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.headers.isEmpty || widget.rows.isEmpty) {
      return _EmptyChartLabel(label: widget.emptyLabel);
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sortedRows = [...widget.rows];
    if (widget.sortByValue) {
      sortedRows.sort(
        (left, right) =>
            _nonNegative(right.value).compareTo(_nonNegative(left.value)),
      );
    }
    final window = OpenHandPageWindow.normalize(
      page: _page,
      pageSize: _pageSize,
      total: sortedRows.length,
    );
    final pageRows = widget.paginate ? window.slice(sortedRows) : sortedRows;
    var usesMetricRows = false;
    for (final row in widget.rows) {
      final widgets = row.cellWidgets;
      if (widgets == null) continue;
      for (final cell in widgets) {
        if (cell == null) continue;
        usesMetricRows = true;
        break;
      }
      if (usesMetricRows) break;
    }
    final rowHeight = usesMetricRows
        ? kOpenHandTableMetricRowHeight
        : _kRankRowHeight;
    final defaultBodyMax = usesMetricRows
        ? kOpenHandTableMetricBodyMaxHeight
        : _kRankBodyMaxHeight;
    final widthRows = sortedRows.length <= _kRankWidthSampleCap
        ? sortedRows
        : pageRows;
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
      fontWeight: FontWeight.w800,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final subtitleStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final columnCount = widget.headers.length;
    String subtitleFor(OpenHandOperationalRankRow row, int index) {
      final subtitles = row.cellSubtitles;
      if (subtitles != null && index < subtitles.length) {
        return subtitles[index].trim();
      }
      return index == 0 ? row.subtitle.trim() : '';
    }

    final natural = List<double>.filled(columnCount, 0);
    for (var i = 0; i < columnCount; i++) {
      var content = _rankTextWidth(
        widget.headers[i],
        headerStyle,
        textScaler: scaler,
      );
      final samples = <String>[
        for (final row in widthRows) i < row.cells.length ? row.cells[i] : '--',
      ];
      for (final cell in samples) {
        content = math.max(
          content,
          _rankTextWidth(cell, valueStyle, textScaler: scaler),
        );
      }
      for (final row in widthRows) {
        content = math.max(
          content,
          _rankTextWidth(
            subtitleFor(row, i),
            subtitleStyle,
            textScaler: scaler,
          ),
        );
      }
      final fitted = _rankFitColumnWidth(
        _rankColumnKind(index: i, header: widget.headers[i], cells: samples),
        content + _kRankCellPadding * 2,
      );
      natural[i] = math.max(fitted, widget.minimumColumnWidths[i] ?? 0);
    }
    final widths = _syncWidths(natural);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: RepaintBoundary(
        child: Semantics(
          label: '${widget.semanticsLabel}，共 ${sortedRows.length} 行',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = widths.fold<double>(
                0,
                (sum, width) => sum + width,
              );
              final viewportWidth = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : contentWidth;
              final widthScale =
                  contentWidth > 0 && viewportWidth > contentWidth
                  ? viewportWidth / contentWidth
                  : 1.0;
              final displayWidths = widthScale == 1
                  ? widths
                  : <double>[for (final width in widths) width * widthScale];
              final tableWidth = math.max(contentWidth, viewportWidth);
              final bodyCap =
                  widget.maxBodyHeight.isFinite &&
                      widget.maxBodyHeight > rowHeight
                  ? widget.maxBodyHeight
                  : defaultBodyMax;
              final bodyHeight = math.min(
                bodyCap,
                math.max(pageRows.length, 1) * rowHeight,
              );
              Widget paintedCell({
                required int index,
                required String text,
                required TextStyle? style,
                required TextAlign align,
                String note = '',
              }) {
                final inner = math.max(
                  0.0,
                  displayWidths[index] - _kRankCellPadding * 2,
                );
                final overflow =
                    _rankTextWidth(text, style, textScaler: scaler) >
                    inner + 0.5;
                final label = Text(
                  text,
                  maxLines: 1,
                  overflow: overflow
                      ? TextOverflow.ellipsis
                      : TextOverflow.visible,
                  softWrap: false,
                  textAlign: align,
                  style: style,
                );
                if (!overflow) return label;
                return Builder(
                  builder: (cellContext) => MouseRegion(
                    onEnter: (_) => _showCellTip(
                      cellContext: cellContext,
                      title: widget.headers[index],
                      body: text,
                      note: note,
                      accent: colors.primary,
                    ),
                    onHover: (_) => _captureAnchor(cellContext),
                    onExit: (_) => _scheduleHideTip(),
                    child: label,
                  ),
                );
              }

              Widget cellBody({
                required bool header,
                required int index,
                required OpenHandOperationalRankRow? row,
              }) {
                final headerText = widget.headers[index];
                final alignment =
                    widget.columnAlignments[index] ??
                    _rankCellAlignment(index, headerText);
                final textAlign = alignment.x < 0
                    ? TextAlign.left
                    : alignment.x > 0
                    ? TextAlign.right
                    : TextAlign.center;
                if (header) {
                  return Align(
                    alignment: alignment,
                    child: paintedCell(
                      index: index,
                      text: headerText,
                      style: headerStyle,
                      align: textAlign,
                    ),
                  );
                }
                final widgets = row?.cellWidgets;
                final metric = widgets != null && index < widgets.length
                    ? widgets[index]
                    : null;
                if (metric != null) {
                  return Align(
                    alignment: alignment,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: alignment,
                      child: metric,
                    ),
                  );
                }
                final subtitle = row == null ? '' : subtitleFor(row, index);
                if (subtitle.isNotEmpty) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      paintedCell(
                        index: index,
                        text: row == null || index >= row.cells.length
                            ? '--'
                            : row.cells[index],
                        style: valueStyle,
                        align: textAlign,
                        note: subtitle,
                      ),
                      if (subtitle.isNotEmpty) ...[
                        kOpenHandGap3,
                        paintedCell(
                          index: index,
                          text: subtitle,
                          style: subtitleStyle,
                          align: textAlign,
                        ),
                      ],
                    ],
                  );
                }
                return Align(
                  alignment: alignment,
                  child: paintedCell(
                    index: index,
                    text: row != null && index < row.cells.length
                        ? row.cells[index]
                        : '--',
                    style: valueStyle,
                    align: textAlign,
                  ),
                );
              }

              Widget rowFor(
                OpenHandOperationalRankRow? row, {
                required bool header,
              }) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: colors.outlineVariant,
                        width: 0.7,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < columnCount; i++)
                        SizedBox(
                          width: displayWidths[i],
                          height: header ? _kRankHeaderHeight : rowHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: _kRankCellPadding,
                                ),
                                child: cellBody(
                                  header: header,
                                  index: i,
                                  row: row,
                                ),
                              ),
                              if (header)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.resizeColumn,
                                    onEnter: (_) =>
                                        setState(() => _hoverHandle = i),
                                    onExit: (_) {
                                      if (_hoverHandle == i) {
                                        setState(() => _hoverHandle = null);
                                      }
                                    },
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onHorizontalDragStart: (details) {
                                        _scheduleHideTip();
                                        _userResized = true;
                                        _dragColumn = i;
                                        _dragOriginWidth = widths[i];
                                        _dragStartX = details.globalPosition.dx;
                                      },
                                      onHorizontalDragUpdate: (details) {
                                        final current = _userWidths;
                                        if (current == null ||
                                            current.length != columnCount) {
                                          return;
                                        }
                                        final next =
                                            (_dragOriginWidth +
                                                    details.globalPosition.dx -
                                                    _dragStartX)
                                                .clamp(
                                                  _kRankUserMinWidth,
                                                  _kRankUserMaxWidth,
                                                )
                                                .toDouble();
                                        if ((current[i] - next).abs() < 0.5) {
                                          return;
                                        }
                                        setState(() => current[i] = next);
                                      },
                                      onHorizontalDragEnd: (_) {
                                        setState(() => _dragColumn = null);
                                      },
                                      onHorizontalDragCancel: () {
                                        setState(() => _dragColumn = null);
                                      },
                                      child: SizedBox(
                                        width: _kRankResizeHandleWidth,
                                        child: Center(
                                          child: AnimatedContainer(
                                            duration: openHandMotionDuration(
                                              context,
                                              kOpenHandMotion180,
                                            ),
                                            curve: kOpenHandSwitchInCurve,
                                            width: 2,
                                            height: _kRankHeaderHeight - 12,
                                            decoration: BoxDecoration(
                                              color:
                                                  _dragColumn == i ||
                                                      _hoverHandle == i
                                                  ? colors.primary
                                                  : colors.outlineVariant
                                                        .withValues(alpha: 0.0),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    kOpenHandRadius2,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              }

              return ClipRRect(
                borderRadius: kOpenHandBorderRadius16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: kOpenHandBorderRadius16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OpenHandSafeScrollbar(
                        controller: _horizontal,
                        scrollbarOrientation: ScrollbarOrientation.bottom,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          physics: _dragColumn == null
                              ? const ClampingScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          child: SizedBox(
                            width: tableWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ColoredBox(
                                  color: colors.surfaceContainerHighest,
                                  child: rowFor(null, header: true),
                                ),
                                SizedBox(
                                  height: bodyHeight,
                                  width: tableWidth,
                                  child: OpenHandSafeScrollbar(
                                    controller: _vertical,
                                    thumbVisibility:
                                        pageRows.length * rowHeight > bodyCap,
                                    child: ListView.builder(
                                      controller: _vertical,
                                      primary: false,
                                      padding: EdgeInsets.zero,
                                      itemCount: pageRows.length,
                                      itemExtent: rowHeight,
                                      physics: openHandDialogAwareScrollPhysics(
                                        context,
                                        fallback: const ClampingScrollPhysics(),
                                      ),
                                      itemBuilder: (context, index) {
                                        final row = pageRows[index];
                                        final painted = ColoredBox(
                                          color: index.isEven
                                              ? colors.surfaceContainerLowest
                                              : colors.surfaceContainerLow,
                                          child: rowFor(row, header: false),
                                        );
                                        Widget interactive = painted;
                                        if (widget.onRowTap != null) {
                                          interactive = MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () =>
                                                  widget.onRowTap!(row),
                                              child: painted,
                                            ),
                                          );
                                        }
                                        if (widget.animateRows) {
                                          interactive = SettingsAwareAppearOnce(
                                            key: ValueKey<Object>(
                                              row.rowKey ?? row,
                                            ),
                                            child: interactive,
                                          );
                                        }
                                        return interactive;
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (widget.footer != null)
                        widget.footer!
                      else if (widget.paginate)
                        OpenHandTablePagination(
                          total: window.total,
                          page: window.page,
                          pageSize: window.pageSize,
                          bar: true,
                          onPageChanged: (page) {
                            setState(() => _page = page);
                            if (_vertical.hasClients) {
                              _vertical.jumpTo(0);
                            }
                          },
                          onPageSizeChanged: (size) {
                            setState(() {
                              _pageSize = size;
                              _page = 1;
                            });
                            if (_vertical.hasClients) {
                              _vertical.jumpTo(0);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 状态条热力：等高校色圆角条；强度或离散状态着色，悬停展示结构化说明卡。
class OpenHandOperationalHeatmap extends StatefulWidget {
  const OpenHandOperationalHeatmap({
    super.key,
    required this.segments,
    required this.color,
    this.emptyLabel = '暂无可用数据',
    this.valueLabel,
    this.tone = OpenHandHeatmapTone.intensity,
    this.keepIdleCells = false,
  });

  final List<OpenHandChartSegment> segments;
  final Color color;
  final String emptyLabel;
  final String Function(OpenHandChartSegment segment)? valueLabel;
  final OpenHandHeatmapTone tone;
  final bool keepIdleCells;

  @override
  State<OpenHandOperationalHeatmap> createState() =>
      _OpenHandOperationalHeatmapState();
}

class _OpenHandOperationalHeatmapState extends State<OpenHandOperationalHeatmap>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  late final AnimationController _transition;
  DialogAnimationSettings _settings = OpenHandMotionDefaults.menu;
  Timer? _showTimer;
  Timer? _hideTimer;
  int _generation = 0;
  int? _hoveredIndex;
  int? _pressedIndex;
  bool _showQueued = false;
  bool _pinned = false;
  Rect? _anchorGlobal;
  OpenHandChartTooltip? _activeTooltip;
  Color? _activeAccent;

  @override
  void initState() {
    super.initState();
    _transition = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.menu,
    );
    _settings = settings;
    _transition
      ..duration = settings.entranceDuration
      ..reverseDuration = settings.exitDuration;
  }

  @override
  void didUpdateWidget(covariant OpenHandOperationalHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _hoveredIndex;
    if (index == null ||
        (identical(oldWidget.segments, widget.segments) &&
            oldWidget.tone == widget.tone &&
            oldWidget.color == widget.color)) {
      return;
    }
    if (index >= widget.segments.length) {
      _pinned = false;
      _scheduleHide();
      return;
    }
    final segment = widget.segments[index];
    final maximum = widget.segments.fold<double>(
      0,
      (value, item) => math.max(value, item.safeValue),
    );
    _activeTooltip = _tooltipFor(segment);
    _activeAccent = _fillFor(segment, maximum);
  }

  @override
  void dispose() {
    _generation += 1;
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _transition.dispose();
    super.dispose();
  }

  String _labelFor(OpenHandChartSegment segment) =>
      widget.valueLabel?.call(segment) ??
      segment.valueLabel ??
      _finite(segment.value).toStringAsFixed(0);

  OpenHandChartTooltip _tooltipFor(OpenHandChartSegment segment) {
    return segment.tooltip ??
        OpenHandChartTooltip(
          title: segment.label,
          badge: _labelFor(segment),
          badgeColor: segment.color,
          summary: '该分段当前观测值为 ${_labelFor(segment)}。',
          metrics: [
            OpenHandChartTooltipMetric(
              label: '观测值',
              value: _labelFor(segment),
              icon: Icons.insights_rounded,
              color: segment.color,
            ),
          ],
        );
  }

  Color _fillFor(OpenHandChartSegment segment, double maximum) {
    final base = segment.color;
    if (widget.tone == OpenHandHeatmapTone.categorical) {
      return segment.safeValue <= 0 ? base.withValues(alpha: 0.32) : base;
    }
    if (segment.safeValue <= 0 || maximum <= 0) {
      return base.withValues(alpha: 0.12);
    }
    final ratio = (segment.safeValue / maximum).clamp(0.0, 1.0);
    return base.withValues(alpha: 0.22 + ratio * 0.78);
  }

  void _captureAnchor(BuildContext cellContext) {
    _anchorGlobal = _chartTooltipAnchorRect(cellContext) ?? _anchorGlobal;
  }

  void _showAt(int index, BuildContext cellContext) {
    if (index < 0 || index >= widget.segments.length) return;
    _hideTimer?.cancel();
    final segment = widget.segments[index];
    _hoveredIndex = index;
    _activeTooltip = _tooltipFor(segment);
    _activeAccent = _fillFor(
      segment,
      widget.segments.fold<double>(
        0,
        (maximum, item) => math.max(maximum, item.safeValue),
      ),
    );
    _captureAnchor(cellContext);
    _showQueued = true;
    if (mounted) setState(() {});
    if (_portal.isShowing) {
      _transition.forward();
      return;
    }
    final generation = ++_generation;
    _showTimer?.cancel();
    _showTimer = _startChartTooltipShowTimer(
      context: context,
      shouldShow: () => mounted && _showQueued && generation == _generation,
      portal: _portal,
      transition: _transition,
    );
  }

  void _scheduleHide() {
    if (_pinned) return;
    _showQueued = false;
    _showTimer?.cancel();
    final generation = ++_generation;
    _hideTimer?.cancel();
    _hideTimer = _startChartTooltipHideTimer(
      shouldHide: () => mounted && !_showQueued && generation == _generation,
      portal: _portal,
      transition: _transition,
      onHidden: () {
        setState(() {
          _hoveredIndex = null;
          _pressedIndex = null;
        });
      },
    );
  }

  void _togglePin(int index, BuildContext cellContext) {
    if (_pinned && _hoveredIndex == index) {
      _pinned = false;
      _scheduleHide();
      return;
    }
    _pinned = true;
    _showAt(index, cellContext);
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final tooltip = _activeTooltip;
    final accent = _activeAccent ?? widget.color;
    if (tooltip == null) return const SizedBox.shrink();
    return _buildChartTooltipOverlay(
      anchor: _anchorGlobal,
      tooltip: tooltip,
      accent: accent,
      transition: _transition,
      settings: _settings,
      onEnter: () {
        _hideTimer?.cancel();
        _showQueued = true;
      },
      onExit: _scheduleHide,
    );
  }

  @override
  Widget build(BuildContext context) {
    final segments = widget.segments;
    final maximum = segments.fold<double>(
      0,
      (maximum, segment) => math.max(maximum, segment.safeValue),
    );
    final hourPattern = RegExp(r'^\d{1,2}$');
    final hourStrip =
        (segments.length == 12 || segments.length == 24) &&
        segments.every((segment) => hourPattern.hasMatch(segment.label));
    final keepIdle = widget.keepIdleCells || hourStrip;
    if (segments.isEmpty || (maximum <= 0 && !keepIdle)) {
      return _EmptyChartLabel(label: widget.emptyLabel);
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: RepaintBoundary(
        child: Semantics(
          label:
              '热力条，${segments.map((segment) => '${segment.label} ${_labelFor(segment)}').join('，')}',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final n = segments.length;
              final available = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : _kStatusStripNamedMaxWidth * n;
              final gap = hourStrip ? 3.0 : 10.0;
              final even = n <= 1 ? available : (available - gap * (n - 1)) / n;
              final slotWidth = hourStrip
                  ? math.max(4.0, even)
                  : even.clamp(8.0, _kStatusStripNamedMaxWidth);
              final glyphWidth = hourStrip
                  ? slotWidth
                  : math.min(28.0, slotWidth);
              final total = slotWidth * n + gap * (n - 1);
              final tickEvery = n == 24
                  ? 6
                  : n == 12
                  ? 3
                  : 1;
              Widget cell(int index) {
                final segment = segments[index];
                final fill = _fillFor(segment, maximum);
                final hovered = _hoveredIndex == index;
                final pressed = _pressedIndex == index;
                final showTick =
                    !hourStrip ||
                    index == 0 ||
                    index == n - 1 ||
                    index % tickEvery == 0;
                final tooltip = _tooltipFor(segment);
                return SizedBox(
                  width: slotWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (cellContext) => Focus(
                          onFocusChange: (focused) {
                            if (focused) {
                              _showAt(index, cellContext);
                            } else if (_hoveredIndex == index) {
                              _pinned = false;
                              _scheduleHide();
                            }
                          },
                          onKeyEvent: (_, event) {
                            if (event is! KeyDownEvent ||
                                (event.logicalKey != LogicalKeyboardKey.enter &&
                                    event.logicalKey !=
                                        LogicalKeyboardKey.space)) {
                              return KeyEventResult.ignored;
                            }
                            _togglePin(index, cellContext);
                            return KeyEventResult.handled;
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            onEnter: (_) => _showAt(index, cellContext),
                            onHover: (_) => _captureAnchor(cellContext),
                            onExit: (_) => _scheduleHide(),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) {
                                setState(() => _pressedIndex = index);
                              },
                              onTapUp: (_) {
                                if (_pressedIndex == index) {
                                  setState(() => _pressedIndex = null);
                                }
                              },
                              onTapCancel: () {
                                if (_pressedIndex == index) {
                                  setState(() => _pressedIndex = null);
                                }
                              },
                              onTap: () => _togglePin(index, cellContext),
                              child: Semantics(
                                label: tooltip.semanticsLabel,
                                button: true,
                                child: Center(
                                  child: AnimatedScale(
                                    scale: pressed
                                        ? 0.92
                                        : hovered
                                        ? 1.08
                                        : 1.0,
                                    duration: openHandMotionDuration(
                                      context,
                                      kOpenHandMotion180,
                                    ),
                                    curve: hovered
                                        ? kOpenHandEntranceCurve
                                        : kOpenHandSwitchOutCurve,
                                    child: AnimatedContainer(
                                      duration: openHandMotionDuration(
                                        context,
                                        kOpenHandMotion180,
                                      ),
                                      curve: kOpenHandSwitchInCurve,
                                      width: glyphWidth,
                                      height: _kStatusStripHeight,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          _kStatusStripRadius,
                                        ),
                                        color: fill,
                                        border: Border.all(
                                          color: fill.withValues(
                                            alpha: hovered ? 0.98 : 0.42,
                                          ),
                                          width: hovered ? 1.5 : 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: fill.withValues(
                                              alpha: hovered ? 0.42 : 0.16,
                                            ),
                                            blurRadius: hovered ? 14 : 5,
                                            offset: Offset(0, hovered ? 5 : 1),
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
                      ),
                      kOpenHandGap8,
                      SizedBox(
                        height: hourStrip ? 16 : 32,
                        child: showTick
                            ? Text(
                                segment.label,
                                maxLines: hourStrip ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: hovered
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                );
              }

              return Align(
                alignment: hourStrip ? Alignment.centerLeft : Alignment.center,
                child: SizedBox(
                  width: math.min(total, available),
                  child: Row(
                    children: [
                      for (var i = 0; i < n; i++) ...[
                        if (i != 0) SizedBox(width: gap),
                        cell(i),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HeatmapHoverMetrics {
  const _HeatmapHoverMetrics({
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

  static _HeatmapHoverMetrics resolve({
    required BuildContext context,
    required Size overlaySize,
    required Rect? anchor,
  }) {
    final padding = MediaQuery.paddingOf(context);
    final width = overlaySize.width.isFinite && overlaySize.width > 0
        ? overlaySize.width
        : 0.0;
    final height = overlaySize.height.isFinite && overlaySize.height > 0
        ? overlaySize.height
        : 0.0;
    final left = (padding.left + _kHeatmapHoverViewportPadding)
        .clamp(0, width)
        .toDouble();
    final top = (padding.top + _kHeatmapHoverViewportPadding)
        .clamp(0, height)
        .toDouble();
    final right = math.max(
      left,
      width - padding.right - _kHeatmapHoverViewportPadding,
    );
    final bottom = math.max(
      top,
      height - padding.bottom - _kHeatmapHoverViewportPadding,
    );
    final safeRect = Rect.fromLTRB(left, top, right, bottom);
    final overlayBox = Overlay.maybeOf(context)?.context.findRenderObject();
    Rect anchorRect;
    if (anchor == null) {
      anchorRect = Rect.fromLTWH(safeRect.left, safeRect.top, 0, 0);
    } else if (overlayBox is RenderBox && overlayBox.attached) {
      final origin = overlayBox.localToGlobal(Offset.zero);
      anchorRect = anchor.translate(-origin.dx, -origin.dy);
    } else {
      anchorRect = anchor;
    }
    final belowHeight =
        safeRect.bottom - anchorRect.bottom - _kHeatmapHoverAnchorGap;
    final aboveHeight = anchorRect.top - safeRect.top - _kHeatmapHoverAnchorGap;
    final placedAbove =
        belowHeight < _kHeatmapHoverPreferAboveMin && aboveHeight > belowHeight;
    final rawHeight = placedAbove ? aboveHeight : belowHeight;
    final maxHeight = rawHeight.isFinite
        ? rawHeight
              .clamp(96.0, math.min(_kHeatmapHoverMaxHeight, safeRect.height))
              .toDouble()
        : math.min(_kHeatmapHoverMaxHeight, safeRect.height);
    final maxWidth = math.min(
      _kHeatmapHoverMaxWidth,
      math.max(0.0, safeRect.width),
    );
    final minWidth = math.min(_kHeatmapHoverMinWidth, maxWidth);
    return _HeatmapHoverMetrics(
      safeRect: safeRect,
      anchorRect: anchorRect,
      placedAbove: placedAbove,
      maxHeight: math.max(0.0, maxHeight),
      minWidth: minWidth,
      maxWidth: maxWidth,
    );
  }
}

class _HeatmapHoverLayoutDelegate extends SingleChildLayoutDelegate {
  const _HeatmapHoverLayoutDelegate(this.metrics);

  final _HeatmapHoverMetrics metrics;

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
    final rawLeft = metrics.anchorRect.center.dx - childSize.width / 2;
    final left = _clampHeatmapCoord(
      rawLeft,
      lower: safe.left,
      upper: safe.right - childSize.width,
    );
    final rawTop = metrics.placedAbove
        ? metrics.anchorRect.top - childSize.height - _kHeatmapHoverAnchorGap
        : metrics.anchorRect.bottom + _kHeatmapHoverAnchorGap;
    final top = _clampHeatmapCoord(
      rawTop,
      lower: safe.top,
      upper: safe.bottom - childSize.height,
    );
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _HeatmapHoverLayoutDelegate oldDelegate) {
    return oldDelegate.metrics.safeRect != metrics.safeRect ||
        oldDelegate.metrics.anchorRect != metrics.anchorRect ||
        oldDelegate.metrics.placedAbove != metrics.placedAbove ||
        oldDelegate.metrics.maxHeight != metrics.maxHeight ||
        oldDelegate.metrics.minWidth != metrics.minWidth ||
        oldDelegate.metrics.maxWidth != metrics.maxWidth;
  }
}

double _clampHeatmapCoord(
  double value, {
  required double lower,
  required double upper,
}) {
  if (!value.isFinite) return lower;
  if (upper <= lower) return lower;
  return value.clamp(lower, upper).toDouble();
}

class _HeatmapHoverCard extends StatelessWidget {
  const _HeatmapHoverCard({required this.tooltip, required this.accent});

  final OpenHandChartTooltip tooltip;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final badge = tooltip.badge?.trim();
    final subtitle = tooltip.subtitle?.trim();
    final summary = tooltip.summary?.trim();
    final badgeColor = tooltip.badgeColor ?? accent;
    final accentForeground = _heatmapForeground(accent, colors);
    final badgeForeground = _heatmapForeground(badgeColor, colors);
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kHeatmapHoverMaxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kOpenHandRadius16),
            color: colors.surfaceContainerHigh,
            border: Border.all(color: accent.withValues(alpha: 0.42)),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kOpenHandRadius16),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _kHeatmapHoverContentHorizontalPadding,
                    12,
                    _kHeatmapHoverContentHorizontalPadding,
                    14,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 34,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(
                                kOpenHandRadius4,
                              ),
                            ),
                          ),
                          kOpenHandHGap10,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tooltip.title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    height: 1.2,
                                  ),
                                ),
                                if (subtitle != null &&
                                    subtitle.isNotEmpty) ...[
                                  kOpenHandGap3,
                                  Text(
                                    subtitle,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      height: 1.3,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (badge != null && badge.isNotEmpty) ...[
                            kOpenHandHGap8,
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(
                                  kOpenHandRadius20,
                                ),
                                border: Border.all(
                                  color: badgeColor.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Text(
                                badge,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: badgeForeground,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (summary != null && summary.isNotEmpty) ...[
                        kOpenHandGap10,
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(
                              kOpenHandRadius10,
                            ),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            child: Text(
                              summary,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (tooltip.metrics.isNotEmpty) ...[
                        kOpenHandGap12,
                        Wrap(
                          spacing: _kHeatmapHoverMetricGap,
                          runSpacing: _kHeatmapHoverMetricGap,
                          children: [
                            for (final metric in tooltip.metrics)
                              _HeatmapHoverMetricTile(
                                metric: metric,
                                fallback: accent,
                              ),
                          ],
                        ),
                      ],
                      if (tooltip.notes.isNotEmpty) ...[
                        kOpenHandGap12,
                        for (var i = 0; i < tooltip.notes.length; i++) ...[
                          if (i != 0) kOpenHandGap6,
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Icon(
                                  Icons.info_outline_rounded,
                                  size: 13,
                                  color: accentForeground,
                                ),
                              ),
                              kOpenHandHGap6,
                              Expanded(
                                child: Text(
                                  tooltip.notes[i],
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeatmapHoverMetricTile extends StatelessWidget {
  const _HeatmapHoverMetricTile({required this.metric, required this.fallback});

  final OpenHandChartTooltipMetric metric;
  final Color fallback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tone = metric.color ?? fallback;
    final foreground = _heatmapForeground(tone, colors);
    final hint = metric.hint?.trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: _kHeatmapHoverMetricMinWidth,
        maxWidth: _kHeatmapHoverMetricMaxWidth,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(kOpenHandRadius12),
          border: Border.all(color: tone.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    metric.icon ?? Icons.analytics_outlined,
                    size: 14,
                    color: foreground,
                  ),
                  kOpenHandHGap5,
                  Expanded(
                    child: Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              kOpenHandGap4,
              Text(
                metric.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: foreground,
                  height: 1.15,
                ),
              ),
              if (hint != null && hint.isNotEmpty) ...[
                kOpenHandGap3,
                Text(
                  hint,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
                    child: _ChartFillTrack(
                      ratio: segment.safeValue / maximum,
                      color: segment.color,
                      trackColor: colors.onSurface.withValues(alpha: 0.08),
                      height: 12,
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
