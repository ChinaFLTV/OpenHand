import 'package:flutter/material.dart';

import 'bounded_animation.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';

const double kOpenHandSpringEntranceMinScale = 0.5;
const double kOpenHandSpringEntranceMaxScale = 1.0;

/// Reusable fade + scale + slide entrance used by transient content that should
/// feel tactile without inventing a bespoke animation controller at each call.
class OpenHandSpringEntrance extends StatefulWidget {
  const OpenHandSpringEntrance({
    super.key,
    required this.child,
    this.duration = kOpenHandMotion420,
    this.opacityIntervalEnd = 0.55,
    this.scaleBegin = 0.94,
    this.slideBegin = const Offset(0.0, 0.04),
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final Duration duration;
  final double opacityIntervalEnd;
  final double scaleBegin;
  final Offset slideBegin;
  final Alignment alignment;

  @override
  State<OpenHandSpringEntrance> createState() => _OpenHandSpringEntranceState();
}

class _OpenHandSpringEntranceState extends State<OpenHandSpringEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _scale;
  late Animation<Offset> _slide;

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: _safeDuration(widget.duration),
      vsync: this,
    );
    _configureAnimations();
  }

  @override
  void didUpdateWidget(covariant OpenHandSpringEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = _safeDuration(widget.duration);
    }
    if (oldWidget.opacityIntervalEnd != widget.opacityIntervalEnd ||
        oldWidget.scaleBegin != widget.scaleBegin ||
        oldWidget.slideBegin != widget.slideBegin) {
      _configureAnimations();
    }
    _syncMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _configureAnimations() {
    _opacity = OpenHandBoundedDoubleAnimation(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(
          0.0,
          _safeOpacityIntervalEnd(widget.opacityIntervalEnd),
          curve: Curves.easeOut,
        ),
      ),
    );
    _scale = Tween<double>(
      begin: _safeScaleBegin(widget.scaleBegin),
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _slide = Tween<Offset>(
      begin: _safeOffset(widget.slideBegin),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: kOpenHandSwitchInCurve));
  }

  void _syncMotion() {
    if (!openHandTickerMotionEnabled(context) ||
        (_controller.duration ?? Duration.zero) <= Duration.zero) {
      _controller.value = 1.0;
      _controller.stop();
      _started = true;
      return;
    }
    if (_started) return;
    _started = true;
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (!openHandTickerMotionEnabled(context)) return widget.child;
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        alignment: widget.alignment,
        child: SlideTransition(position: _slide, child: widget.child),
      ),
    );
  }
}

Duration _safeDuration(Duration duration) {
  return duration < Duration.zero ? Duration.zero : duration;
}

double _safeOpacityIntervalEnd(double value) {
  if (!value.isFinite || value <= 0) return 1.0;
  return value.clamp(0.05, 1.0).toDouble();
}

double _safeScaleBegin(double value) {
  if (!value.isFinite || value <= 0) return 1.0;
  return value
      .clamp(kOpenHandSpringEntranceMinScale, kOpenHandSpringEntranceMaxScale)
      .toDouble();
}

Offset _safeOffset(Offset value) {
  final dx = value.dx.isFinite ? value.dx : 0.0;
  final dy = value.dy.isFinite ? value.dy : 0.0;
  return Offset(dx, dy);
}
