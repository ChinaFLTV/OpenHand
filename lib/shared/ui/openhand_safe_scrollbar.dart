// 安全 Scrollbar 包装：始终保持滚动条与子树层级稳定；当 controller 未挂载、
// 无尺寸或挂载多个 ScrollPosition 时关闭滑块与交互，状态干净后原位启用。
// 用于同时规避控制器未挂载异常和滚动子树跨层级迁移导致的 GlobalKey 冲突。
import 'dart:async';

import 'package:flutter/material.dart';

import '../util/timer_safety.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';

const Duration _kStableScrollbarSettleDelay = kOpenHandMotion140;
const Duration _kStableScrollbarSettleDuration = kOpenHandMotion180;
const Duration _kStableScrollbarFadeDelay = Duration(milliseconds: 360);
const Duration _kStableScrollbarFadeDuration = kOpenHandMotion240;

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
///     仍为 null 时保留滚动条层级，但关闭滑块绘制与交互。
///   * `controller.hasClients == false`、`controller.positions.length != 1`、
///     `controller.position.haveDimensions == false` 时同样关闭绘制与交互。
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
    final thumbVisibility = safe ? widget.thumbVisibility : false;
    final trackVisibility = safe ? widget.trackVisibility : false;
    final interactive = safe ? widget.interactive : false;
    final Widget content = widget.stabilizeMetrics
        ? _OpenHandStableRawScrollbar(
            controller: controller,
            thumbVisibility: thumbVisibility,
            trackVisibility: trackVisibility,
            thickness: widget.thickness,
            radius: widget.radius,
            interactive: interactive,
            scrollbarOrientation: widget.scrollbarOrientation,
            sourceNotificationPredicate: predicate,
            child: child,
          )
        : Scrollbar(
            controller: controller,
            thumbVisibility: thumbVisibility,
            trackVisibility: trackVisibility,
            thickness: widget.thickness,
            radius: widget.radius,
            interactive: interactive,
            scrollbarOrientation: widget.scrollbarOrientation,
            notificationPredicate: predicate,
            child: child,
          );

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
  final Stopwatch _settleClock = Stopwatch()..start();
  int _settleDeadlineMs = 0;
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

  /// 防抖改为「推进截止时间 + 单常驻计时器」：滚动期间每帧都有通知，
  /// 逐通知 cancel+新建 Timer 会产生每秒上百个定时器对象churn。
  void _scheduleSettle() {
    _settleDeadlineMs =
        _settleClock.elapsedMilliseconds +
        _kStableScrollbarSettleDelay.inMilliseconds;
    if (_settleTimer != null) return;
    _armSettleTimer(_kStableScrollbarSettleDelay);
  }

  void _armSettleTimer(Duration wait) {
    _settleTimer = startSafeTimer(wait, () {
      _settleTimer = null;
      final remainingMs = _settleDeadlineMs - _settleClock.elapsedMilliseconds;
      if (remainingMs > 0) {
        _armSettleTimer(Duration(milliseconds: remainingMs));
        return;
      }
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
    final t = kOpenHandSwitchInCurve.transform(_settleController.value);
    _displayMaxScrollExtent =
        _settleStartMaxScrollExtent +
        (_settleTargetMaxScrollExtent - _settleStartMaxScrollExtent) * t;
    _paintMetrics(metrics);
  }

  void _paintMetrics(ScrollMetrics metrics) {
    final minExtent = metrics.minScrollExtent;
    final maxExtent = (_displayMaxScrollExtent ?? metrics.maxScrollExtent)
        .clamp(minExtent, double.infinity);
    final paintMaxExtent = maxExtent < metrics.pixels
        ? metrics.pixels
        : maxExtent;
    scrollbarPainter.update(
      FixedScrollMetrics(
        minScrollExtent: minExtent,
        maxScrollExtent: paintMaxExtent,
        pixels: metrics.pixels.clamp(minExtent, paintMaxExtent),
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
