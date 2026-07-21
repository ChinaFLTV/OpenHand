import 'package:flutter/material.dart';

import 'motion_preference.dart';

/// 随展开状态旋转 0 到 90 度，并遵循全局减少动画设置。
class AnimatedExpandChevron extends StatelessWidget {
  const AnimatedExpandChevron({
    super.key,
    required this.expanded,
    this.size = 18,
    this.color,
    this.duration = const Duration(milliseconds: 240),
  });

  final bool expanded;
  final double size;
  final Color? color;
  final Duration duration;

  double get _safeSize {
    return size.isFinite && size > 0 ? size : 0;
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      Icons.keyboard_arrow_right_rounded,
      size: _safeSize,
      color: color,
    );
    if (!openHandTickerMotionEnabled(context)) {
      return icon;
    }
    return AnimatedRotation(
      turns: expanded ? 0.25 : 0.0,
      duration: openHandMotionDuration(context, duration),
      curve: Curves.easeOutCubic,
      child: icon,
    );
  }
}
