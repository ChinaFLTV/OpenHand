import 'package:flutter/material.dart';

import 'motion_durations.dart';
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

/// 历史「悬停上浮」包装。上浮会被当成卡片阴影，因此直接返回子组件。
class HoverLift extends StatelessWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.liftDistance = 2.0,
    this.duration = kOpenHandMotion180,
    this.curve = kOpenHandSwitchInCurve,
  });

  final Widget child;

  /// 保留参数以兼容既有调用点。
  final double liftDistance;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final _ = (liftDistance, duration, curve);
    return child;
  }
}
