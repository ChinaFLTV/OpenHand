// 安全 Scrollbar 包装：当 controller 未 attach、无 dimensions 或挂载多个
// ScrollPosition 时透传 child（不绘制 thumb），仅在状态干净时委托给 framework
// Scrollbar。用于规避 'has no ScrollPosition attached' FlutterError，同时让
// 已 attach 场景的视觉/手感与原生 Scrollbar 完全一致。
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final controller = _resolveController(context);
    final safe = _evaluateSafe(controller);
    _lastSafe = safe;
    _scheduleResync();

    final Widget content = safe
        ? Scrollbar(
            controller: controller,
            thumbVisibility: widget.thumbVisibility,
            trackVisibility: widget.trackVisibility,
            thickness: widget.thickness,
            radius: widget.radius,
            interactive: widget.interactive,
            scrollbarOrientation: widget.scrollbarOrientation,
            notificationPredicate: widget.notificationPredicate ??
                defaultScrollNotificationPredicate,
            child: widget.child,
          )
        : widget.child;

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onScrollMetrics,
      child: content,
    );
  }
}
