import 'package:flutter/material.dart';

import 'motion_preference.dart';

/// 垂直展开档默认时长：入场略长于退场，收起时更干脆。
const Duration kOpenHandVerticalRevealDuration = Duration(milliseconds: 320);
const Duration kOpenHandVerticalRevealReverseDuration = Duration(
  milliseconds: 240,
);

/// 顶部锚定的垂直展开/收起切换动效。
///
/// 收敛全库重复的 `AnimatedSwitcher + SizeTransition + FadeTransition
/// (+ SlideTransition)` 组合：统一曲线、轴对齐与堆叠对齐，并强制经过
/// [openHandMotionDuration]，保证与全局动效设置一致——关闭动效时直接返回
/// 子树，连 AnimatedSwitcher 都不挂载，避免无谓的 Ticker 与图层开销。
///
/// 调用方按 AnimatedSwitcher 约定给 [child] 挂 key；只有需要“有/无”两态切换
/// 时才传 [presentKey]，由本组件补齐存在态的 key。
class OpenHandVerticalRevealSwitcher extends StatelessWidget {
  const OpenHandVerticalRevealSwitcher({
    super.key,
    required this.child,
    this.duration = kOpenHandVerticalRevealDuration,
    this.reverseDuration,
    this.slideBeginOffsetY = 0,
    this.presentKey,
  });

  /// 为 null 时收起为零高度（配合 [presentKey] 表达“有/无”两态）。
  final Widget? child;

  /// 展开时长；退场时长缺省与之相同，且始终被夹在展开时长以内。
  final Duration duration;
  final Duration? reverseDuration;

  /// 入场时叠加的纵向位移（负值＝自上方滑入）；0 表示只做尺寸与淡入。
  final double slideBeginOffsetY;

  /// 存在态的 key；仅在调用方未自行给 [child] 挂 key 时使用。
  final Key? presentKey;

  static const Key _absentKey = ValueKey<String>('openhand-reveal-absent');

  @override
  Widget build(BuildContext context) {
    final hasChild = child != null;
    final present = hasChild && presentKey != null
        ? KeyedSubtree(key: presentKey, child: child!)
        : child;
    if (!openHandTickerMotionEnabled(context)) {
      return present ?? const SizedBox.shrink(key: _absentKey);
    }
    final inDuration = openHandMotionDuration(context, duration);
    final outDuration = openHandMotionDuration(
      context,
      reverseDuration ?? duration,
    );
    return AnimatedSwitcher(
      duration: hasChild
          ? inDuration
          : Duration(
              microseconds: outDuration.inMicroseconds.clamp(
                0,
                inDuration.inMicroseconds,
              ),
            ),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final faded = FadeTransition(opacity: animation, child: child);
        return SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: slideBeginOffsetY == 0
              ? faded
              : SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0, slideBeginOffsetY),
                    end: Offset.zero,
                  ).animate(animation),
                  child: faded,
                ),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: present ?? const SizedBox.shrink(key: _absentKey),
    );
  }
}
