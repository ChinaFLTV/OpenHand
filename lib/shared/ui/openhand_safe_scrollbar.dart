// 安全 Scrollbar 包装：当 controller 未 attach、无 dimensions 或挂载多个
// ScrollPosition 时透传 child（不绘制 thumb），仅在状态干净时委托给 framework
// Scrollbar。用于规避 'has no ScrollPosition attached' FlutterError，同时让
// 已 attach 场景的视觉/手感与原生 Scrollbar 完全一致。
import 'dart:async';

import 'package:flutter/material.dart';

import '../util/timer_safety.dart';
import 'oh_pill.dart';

const Duration _kStableScrollbarSettleDelay = Duration(milliseconds: 140);
const Duration _kStableScrollbarSettleDuration = Duration(milliseconds: 180);
const Duration _kStableScrollbarFadeDelay = Duration(milliseconds: 360);
const Duration _kStableScrollbarFadeDuration = Duration(milliseconds: 240);

bool openHandPlatformUsesImplicitScrollbars(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
      return true;
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.iOS:
      return false;
  }
}

Widget buildOpenHandImplicitScrollbar({
  required TargetPlatform platform,
  required Widget child,
  required ScrollableDetails details,
}) {
  if (!openHandPlatformUsesImplicitScrollbars(platform)) {
    return child;
  }
  final controller = details.controller;
  if (controller == null) {
    return child;
  }
  return OpenHandSafeScrollbar(controller: controller, child: child);
}

/// API 与 framework [Scrollbar] 兼容；调用点零认知成本切换。
///
/// 行为说明：
///   * `controller` 为 null 时退回到 `PrimaryScrollController.maybeOf(context)`；
///     仍为 null 时透传 child，不喂给 framework Scrollbar。
///   * `controller.hasClients == false`、`controller.positions.length != 1`、
///     `controller.position.haveDimensions == false` 时透传 child。
///   * 全部条件满足后委托给 framework `Scrollbar`，参数原样透传。
///
/// 通过 [NotificationListener<ScrollMetricsNotification>] + post-frame 检测
/// 状态变化触发重建，无需手写 painter。
class OpenHandSafeScrollbar extends StatefulWidget {
  const OpenHandSafeScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility,
    this.trackVisibility,
    this.thickness,
    this.radius,
    this.interactive,
    this.scrollbarOrientation,
    this.notificationPredicate,
    this.stabilizeMetrics = false,
  });

  final Widget child;
  final ScrollController? controller;
  final bool? thumbVisibility;
  final bool? trackVisibility;
  final double? thickness;
  final Radius? radius;
  final bool? interactive;
  final ScrollbarOrientation? scrollbarOrientation;
  final ScrollNotificationPredicate? notificationPredicate;
  final bool stabilizeMetrics;

  @override
  State<OpenHandSafeScrollbar> createState() => _OpenHandSafeScrollbarState();
}

class _OpenHandSafeScrollbarState extends State<OpenHandSafeScrollbar> {
  bool _lastSafe = false;
  bool _resyncScheduled = false;

  ScrollController? _resolveController(BuildContext context) {
    return widget.controller ?? PrimaryScrollController.maybeOf(context);
  }

  bool _evaluateSafe(ScrollController? controller) {
    if (controller == null) return false;
    if (!controller.hasClients) return false;
    if (controller.positions.length != 1) return false;
    final ScrollPosition position;
    try {
      position = controller.position;
    } catch (_) {
      return false;
    }
    return position.haveDimensions;
  }

  void _scheduleResync() {
    if (_resyncScheduled) return;
    _resyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resyncScheduled = false;
      if (!mounted) return;
      final next = _evaluateSafe(_resolveController(context));
      if (next != _lastSafe) {
        setState(() {});
      }
    });
  }

  bool _onScrollMetrics(ScrollMetricsNotification _) {
    _scheduleResync();
    return false;
  }

  bool _onScrollNotification(ScrollNotification _) {
    _scheduleResync();
    return false;
  }

  Widget _withoutImplicitScrollbars(BuildContext context, Widget child) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _resolveController(context);
    final safe = _evaluateSafe(controller);
    _lastSafe = safe;
    _scheduleResync();
    final child = _withoutImplicitScrollbars(context, widget.child);

    final predicate =
        widget.notificationPredicate ?? defaultScrollNotificationPredicate;
    final Widget content;
    if (!safe) {
      content = child;
    } else if (widget.stabilizeMetrics) {
      content = _OpenHandStableRawScrollbar(
        controller: controller,
        thumbVisibility: widget.thumbVisibility,
        trackVisibility: widget.trackVisibility,
        thickness: widget.thickness,
        radius: widget.radius,
        interactive: widget.interactive,
        scrollbarOrientation: widget.scrollbarOrientation,
        sourceNotificationPredicate: predicate,
        child: child,
      );
    } else {
      content = Scrollbar(
        controller: controller,
        thumbVisibility: widget.thumbVisibility,
        trackVisibility: widget.trackVisibility,
        thickness: widget.thickness,
        radius: widget.radius,
        interactive: widget.interactive,
        scrollbarOrientation: widget.scrollbarOrientation,
        notificationPredicate: predicate,
        child: child,
      );
    }

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onScrollMetrics,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: content,
      ),
    );
  }
}

class _OpenHandStableRawScrollbar extends RawScrollbar {
  const _OpenHandStableRawScrollbar({
    required super.child,
    required super.controller,
    required this.sourceNotificationPredicate,
    super.thumbVisibility,
    super.trackVisibility,
    super.thickness,
    super.radius,
    super.interactive,
    super.scrollbarOrientation,
  }) : super(
         notificationPredicate: sourceNotificationPredicate,
         fadeDuration: _kStableScrollbarFadeDuration,
         timeToFade: _kStableScrollbarFadeDelay,
         pressDuration: Duration.zero,
       );

  final ScrollNotificationPredicate sourceNotificationPredicate;

  @override
  RawScrollbarState<_OpenHandStableRawScrollbar> createState() =>
      _OpenHandStableRawScrollbarState();
}

class _OpenHandStableRawScrollbarState
    extends RawScrollbarState<_OpenHandStableRawScrollbar> {
  late final AnimationController _settleController;
  Timer? _settleTimer;
  ScrollMetrics? _latestMetrics;
  double? _displayMaxScrollExtent;
  double _settleStartMaxScrollExtent = 0;
  double _settleTargetMaxScrollExtent = 0;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: _kStableScrollbarSettleDuration,
    )..addListener(_paintSettlingMetrics);
  }

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    final theme = ScrollbarTheme.of(context);
    final states = <WidgetState>{};
    scrollbarPainter
      ..color =
          theme.thumbColor?.resolve(states) ??
          Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
      ..thickness = widget.thickness ?? theme.thickness?.resolve(states) ?? 6
      ..radius = widget.radius ?? theme.radius ?? kOpenHandPillRadius;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.sourceNotificationPredicate(notification)) return false;
    _latestMetrics = notification.metrics;
    _lockMetrics(notification.metrics);
    _scheduleSettle();
    return false;
  }

  bool _handleMetricsNotification(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    _latestMetrics = notification.metrics;
    if (_settleTimer != null || _settleController.isAnimating) {
      _paintMetrics(notification.metrics);
    } else {
      _startSettle();
    }
    return false;
  }

  void _lockMetrics(ScrollMetrics metrics) {
    if (_settleController.isAnimating) {
      _settleController.stop();
    }
    _displayMaxScrollExtent ??= metrics.maxScrollExtent;
    _paintMetrics(metrics);
  }

  void _scheduleSettle() {
    _settleTimer?.cancel();
    _settleTimer = startSafeTimer(_kStableScrollbarSettleDelay, () {
      _settleTimer = null;
      _startSettle();
    });
  }

  void _startSettle() {
    final metrics = _latestMetrics;
    if (metrics == null) return;
    final current = _displayMaxScrollExtent ?? metrics.maxScrollExtent;
    final target = metrics.maxScrollExtent;
    if ((target - current).abs() < 0.5) {
      _displayMaxScrollExtent = target;
      _paintMetrics(metrics);
      return;
    }
    _settleStartMaxScrollExtent = current;
    _settleTargetMaxScrollExtent = target;
    _settleController.forward(from: 0);
  }

  void _paintSettlingMetrics() {
    final metrics = _latestMetrics;
    if (metrics == null) return;
    final t = Curves.easeOutCubic.transform(_settleController.value);
    _displayMaxScrollExtent =
        _settleStartMaxScrollExtent +
        (_settleTargetMaxScrollExtent - _settleStartMaxScrollExtent) * t;
    _paintMetrics(metrics);
  }

  void _paintMetrics(ScrollMetrics metrics) {
    final minExtent = metrics.minScrollExtent;
    final maxExtent = (_displayMaxScrollExtent ?? metrics.maxScrollExtent)
        .clamp(minExtent, double.infinity)
        .toDouble();
    final paintMaxExtent = maxExtent < metrics.pixels
        ? metrics.pixels
        : maxExtent;
    scrollbarPainter.update(
      FixedScrollMetrics(
        minScrollExtent: minExtent,
        maxScrollExtent: paintMaxExtent,
        pixels: metrics.pixels.clamp(minExtent, paintMaxExtent).toDouble(),
        viewportDimension: metrics.viewportDimension,
        axisDirection: metrics.axisDirection,
        devicePixelRatio: metrics.devicePixelRatio,
      ),
      metrics.axisDirection,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _handleMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: super.build(context),
      ),
    );
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _settleController.dispose();
    super.dispose();
  }
}
