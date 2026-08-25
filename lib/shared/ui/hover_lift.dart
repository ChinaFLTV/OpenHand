import 'package:flutter/material.dart';

import 'motion_preference.dart';

mixin OpenHandHoverState<W extends StatefulWidget> on State<W> {
  bool _openHandHovered = false;
  bool _openHandHoverUpdateScheduled = false;

  bool get openHandHovered => _openHandHovered;

  void setOpenHandHovered(bool value) {
    if (_openHandHovered == value) return;
    _openHandHovered = value;
    if (_openHandHoverUpdateScheduled) return;
    _openHandHoverUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openHandHoverUpdateScheduled = false;
      if (mounted) setState(() {});
    });
  }

  void clearOpenHandHovered() {
    _openHandHovered = false;
  }
}

/// 为子组件提供轻微上浮的指针悬浮反馈，并遵循全局动效偏好。
/// 内部预留上浮空间，避免滚动容器裁掉卡片边框。
class HoverLift extends StatefulWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.liftDistance = 2.0,
    this.duration = const Duration(milliseconds: 180),
    this.curve = kOpenHandSwitchInCurve,
  });

  final Widget child;

  /// 悬浮时向上移动的像素距离。
  final double liftDistance;

  final Duration duration;
  final Curve curve;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift>
    with OpenHandHoverState<HoverLift> {
  double get _safeLiftDistance {
    return widget.liftDistance.isFinite && widget.liftDistance > 0
        ? widget.liftDistance
        : 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!openHandTickerMotionEnabled(context)) {
      clearOpenHandHovered();
    }
  }

  @override
  Widget build(BuildContext context) {
    final liftDistance = _safeLiftDistance;
    if (!openHandTickerMotionEnabled(context)) {
      return Padding(
        padding: EdgeInsets.only(top: liftDistance),
        child: widget.child,
      );
    }
    final lift = openHandHovered ? -liftDistance : 0.0;
    return Padding(
      padding: EdgeInsets.only(top: liftDistance),
      child: MouseRegion(
        onEnter: (_) => setOpenHandHovered(true),
        onExit: (_) => setOpenHandHovered(false),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: lift),
          duration: openHandMotionDuration(context, widget.duration),
          curve: widget.curve,
          builder: (context, value, child) {
            return Transform.translate(offset: Offset(0, value), child: child);
          },
          child: widget.child,
        ),
      ),
    );
  }
}
