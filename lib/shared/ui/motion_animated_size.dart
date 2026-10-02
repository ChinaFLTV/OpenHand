import 'package:flutter/material.dart';

/// 关闭尺寸动效时跳过动画布局，并保留子树的输入和焦点状态。
class OpenHandMotionAnimatedSize extends StatefulWidget {
  const OpenHandMotionAnimatedSize({
    super.key,
    required this.duration,
    required this.child,
    this.reverseDuration,
    this.curve = Curves.linear,
    this.alignment = Alignment.center,
    this.clipBehavior = Clip.hardEdge,
  });

  final Duration duration;
  final Duration? reverseDuration;
  final Widget child;
  final Curve curve;
  final AlignmentGeometry alignment;
  final Clip clipBehavior;

  @override
  State<OpenHandMotionAnimatedSize> createState() =>
      _OpenHandMotionAnimatedSizeState();
}

class _OpenHandMotionAnimatedSizeState
    extends State<OpenHandMotionAnimatedSize> {
  final _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (widget.duration <= Duration.zero) return child;
    return AnimatedSize(
      duration: widget.duration,
      reverseDuration: widget.reverseDuration,
      curve: widget.curve,
      alignment: widget.alignment,
      clipBehavior: widget.clipBehavior,
      child: child,
    );
  }
}
