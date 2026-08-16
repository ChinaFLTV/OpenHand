import 'package:flutter/material.dart';

import '../../shared/ui/openhand_spacing.dart';
import 'motion_preference.dart';

const Duration _kOpenHandSweepShimmerDuration = Duration(milliseconds: 1350);

class OpenHandSweepShimmer extends StatefulWidget {
  const OpenHandSweepShimmer({
    super.key,
    required this.child,
    required this.sweepColor,
    this.duration = _kOpenHandSweepShimmerDuration,
    this.enabled = true,
    this.maskToChildAlpha = false,
  });

  final Widget child;
  final Color sweepColor;
  final Duration duration;
  final bool enabled;
  final bool maskToChildAlpha;

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
        final gradient = LinearGradient(
          begin: Alignment(-1.8 + progress * 2.8, 0),
          end: Alignment(-0.9 + progress * 2.8, 0),
          colors: [Colors.transparent, widget.sweepColor, Colors.transparent],
        );
        if (widget.maskToChildAlpha) {
          return ShaderMask(
            shaderCallback: gradient.createShader,
            blendMode: BlendMode.srcATop,
            child: child,
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: gradient),
              ),
            ),
            child ?? const SizedBox.shrink(),
          ],
        );
      },
    );
  }
}

/// 骨架屏高光扫过一轮的周期。
const Duration kOpenHandSkeletonShimmerPeriod = Duration(milliseconds: 1350);

/// 骨架屏占位块：在容器底色上左右扫过一道高光。
///
/// 与 [OpenHandSweepShimmer] 的区别在于这里本身就是占位块，而不是给已有内容
/// 叠一层扫光。审计弹窗的文本骨架与消息气泡的图片骨架此前各写了一份控制器
/// 生命周期、动效开关判定与渐变计算。
class OpenHandSkeletonShimmer extends StatefulWidget {
  const OpenHandSkeletonShimmer({
    super.key,
    this.width,
    this.height,
    this.expand = false,
    this.borderRadius = kOpenHandBorderRadius8,
    this.period = kOpenHandSkeletonShimmerPeriod,
    this.child,
  });

  /// 固定宽度；为 null 时占满可用宽度。[expand] 为 true 时忽略。
  final double? width;
  final double? height;

  /// 撑满父级约束，用于图片这类需要占位整块区域的场景。
  final bool expand;

  final BorderRadius borderRadius;
  final Duration period;

  /// 叠在骨架上的内容，例如居中的占位图标。
  final Widget? child;

  @override
  State<OpenHandSkeletonShimmer> createState() =>
      _OpenHandSkeletonShimmerState();
}

class _OpenHandSkeletonShimmerState extends State<OpenHandSkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didUpdateWidget(covariant OpenHandSkeletonShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _controller.duration = widget.period;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.surfaceContainerHighest;
    final highlightColor = colorScheme.surfaceContainerLow;
    if (!openHandTickerMotionEnabled(context)) {
      _controller.stop();
      // 关闭动效时停在高光居中的静态形态，仍能看出这是占位。
      return _buildBlock(baseColor, highlightColor, 0.5);
    }
    if (!_controller.isAnimating) _controller.repeat();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          _buildBlock(baseColor, highlightColor, _controller.value),
    );
  }

  Widget _buildBlock(Color baseColor, Color highlightColor, double progress) {
    final block = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        gradient: LinearGradient(
          begin: Alignment(-1.0 + 2.0 * progress, 0),
          end: Alignment(2.0 * progress, 0),
          colors: [baseColor, highlightColor, baseColor],
        ),
      ),
      child: widget.child,
    );
    if (widget.expand) return SizedBox.expand(child: block);
    return SizedBox(
      width: widget.width ?? double.infinity,
      height: widget.height,
      child: block,
    );
  }
}
