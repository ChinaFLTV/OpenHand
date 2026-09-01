import 'package:flutter/material.dart';

import 'motion_durations.dart';
import 'motion_preference.dart';

const double kOpenHandMicroPressMinScale = 0.5;
const double kOpenHandMicroPressMaxScale = 1.0;

/// 为可点击子组件提供 80 毫秒按压缩放和 140 毫秒回弹。
///
/// 透明命中测试不会消费手势；禁用动效或 `TickerMode` 时直接渲染子组件。
class MicroPressFeedback extends StatefulWidget {
  const MicroPressFeedback({
    super.key,
    required this.child,
    this.scale = 0.88,
    this.enabled = true,
  });

  final Widget child;

  /// 按压峰值缩放比例；1 表示不缩放。
  final double scale;

  /// 关闭后不再响应按压动效。
  final bool enabled;

  @override
  State<MicroPressFeedback> createState() => _MicroPressFeedbackState();
}

class _MicroPressFeedbackState extends State<MicroPressFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  double get _safeScale {
    if (!widget.scale.isFinite || widget.scale <= 0) return 1.0;
    return widget.scale
        .clamp(kOpenHandMicroPressMinScale, kOpenHandMicroPressMaxScale)
        .toDouble();
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: kOpenHandMotion80,
      reverseDuration: kOpenHandMotion140,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!openHandTickerMotionEnabled(context)) {
      _reset();
    }
  }

  @override
  void didUpdateWidget(covariant MicroPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled && !widget.enabled) {
      _reset();
    }
  }

  void _reset() {
    _ctrl
      ..stop()
      ..value = 0;
  }

  void _onDown() {
    if (!widget.enabled) return;
    if (!openHandTickerMotionEnabled(context)) return;
    _ctrl.forward();
  }

  void _onUp() {
    if (_ctrl.value == 0) return;
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !openHandTickerMotionEnabled(context)) {
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onDown(),
      onPointerUp: (_) => _onUp(),
      onPointerCancel: (_) => _onUp(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = kOpenHandSwitchInCurve.transform(_ctrl.value);
          final s = 1.0 - (1.0 - _safeScale) * t;
          return Transform.scale(scale: s, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
