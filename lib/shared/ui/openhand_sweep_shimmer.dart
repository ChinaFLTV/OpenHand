import 'package:flutter/material.dart';

import 'motion_preference.dart';

const Duration _kOpenHandSweepShimmerDuration = Duration(milliseconds: 1350);

class OpenHandSweepShimmer extends StatefulWidget {
  const OpenHandSweepShimmer({
    super.key,
    required this.child,
    required this.sweepColor,
    this.duration = _kOpenHandSweepShimmerDuration,
    this.enabled = true,
  });

  final Widget child;
  final Color sweepColor;
  final Duration duration;
  final bool enabled;

  @override
  State<OpenHandSweepShimmer> createState() => _OpenHandSweepShimmerState();
}

class _OpenHandSweepShimmerState extends State<OpenHandSweepShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didUpdateWidget(covariant OpenHandSweepShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController(openHandTickerMotionEnabled(context));
  }

  void _syncController(bool motionEnabled) {
    final enabled = widget.enabled && motionEnabled;
    if (enabled) {
      if (!_controller.isAnimating) _controller.repeat();
      return;
    }
    _controller.stop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motionEnabled = openHandTickerMotionEnabled(context);
    _syncController(motionEnabled);
    if (!widget.enabled || !motionEnabled) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final progress = _controller.value;
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(-1.8 + progress * 2.8, 0),
                    end: Alignment(-0.9 + progress * 2.8, 0),
                    colors: [
                      Colors.transparent,
                      widget.sweepColor,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            child ?? const SizedBox.shrink(),
          ],
        );
      },
    );
  }
}
