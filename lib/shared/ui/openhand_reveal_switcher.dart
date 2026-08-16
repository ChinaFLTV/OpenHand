import 'package:flutter/material.dart';

import 'motion_durations.dart';
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
      switchInCurve: kOpenHandSwitchInCurve,
      switchOutCurve: kOpenHandSwitchOutCurve,
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

/// 行内展开档默认时长：比纵向档略短，行内元素的宽度变化不宜拖沓。
const Duration kOpenHandInlineRevealDuration = Duration(milliseconds: 220);
const Duration kOpenHandInlineRevealReverseDuration = Duration(
  milliseconds: 180,
);

/// 行内（横向）展开/收起切换动效，[OpenHandVerticalRevealSwitcher] 的同轴兄弟。
///
/// 用于工具栏、状态行里「只在忙碌/有内容时才出现」的进度片：直接
/// `if (busy) ...[chip]` 会让同一行的其余元素在忙碌翻转的瞬间整体平移一次，
/// 而这类状态常在数百毫秒内反复翻转，观感就是抖动。这里让宽度随动效平滑
/// 增减，并与全局动效设置保持一致。
class OpenHandInlineRevealSwitcher extends StatelessWidget {
  const OpenHandInlineRevealSwitcher({
    super.key,
    required this.child,
    this.duration = kOpenHandInlineRevealDuration,
    this.reverseDuration = kOpenHandInlineRevealReverseDuration,
    this.presentKey,
  });

  /// 为 null 时收起为零宽度。
  final Widget? child;

  final Duration duration;
  final Duration? reverseDuration;

  /// 存在态的 key；仅在调用方未自行给 [child] 挂 key 时使用。
  final Key? presentKey;

  static const Key _absentKey = ValueKey<String>(
    'openhand-inline-reveal-absent',
  );

  @override
  Widget build(BuildContext context) {
    final hasChild = child != null;
    final present = hasChild && presentKey != null
        ? KeyedSubtree(key: presentKey, child: child!)
        : child;
    if (!openHandTickerMotionEnabled(context)) {
      return present ?? const SizedBox.shrink(key: _absentKey);
    }
    return AnimatedSwitcher(
      duration: openHandMotionDuration(
        context,
        hasChild ? duration : (reverseDuration ?? duration),
      ),
      switchInCurve: kOpenHandSwitchInCurve,
      switchOutCurve: kOpenHandSwitchOutCurve,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        axis: Axis.horizontal,
        axisAlignment: -1,
        child: FadeTransition(opacity: animation, child: child),
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: present ?? const SizedBox.shrink(key: _absentKey),
    );
  }
}

/// 同位交叉切换的默认时长与上滑幅度。
const Duration kOpenHandCrossFadeDuration = kOpenHandMotion280;
const double kOpenHandCrossFadeSlideOffsetY = 0.05;

/// 顶部锚定的「淡入 + 轻微上滑」同位交叉切换。
///
/// 与 [OpenHandVerticalRevealSwitcher] 的分工：那个负责「有 / 无」的展开收起
/// 并带尺寸动画；这个负责同一位置上两块内容的互换，高度交给外层的
/// AnimatedSize 管，自身只做淡入与位移。主会话工具卡片与 Harness 工具轨迹
/// 此前各写了一份同样的配置。
class OpenHandCrossFadeSwitcher extends StatelessWidget {
  const OpenHandCrossFadeSwitcher({
    super.key,
    required this.child,
    this.duration = kOpenHandCrossFadeDuration,
    this.slideBeginOffsetY = kOpenHandCrossFadeSlideOffsetY,
    this.switchInCurve = kOpenHandSwitchInCurve,
  });

  /// 按 AnimatedSwitcher 约定挂 key 区分两侧内容。
  final Widget child;

  final Duration duration;

  /// 入场时自下方滑入的相对幅度。
  final double slideBeginOffsetY;

  final Curve switchInCurve;

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = openHandMotionDuration(context, duration);
    if (effectiveDuration == Duration.zero) return child;
    return AnimatedSwitcher(
      duration: effectiveDuration,
      switchInCurve: switchInCurve,
      switchOutCurve: kOpenHandSwitchOutCurve,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (transitionChild, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: Offset(0, slideBeginOffsetY),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: kOpenHandSwitchInCurve),
              ),
          child: transitionChild,
        ),
      ),
      child: child,
    );
  }
}

/// 内容态切换的默认时长。
const Duration kOpenHandContentStateDuration = Duration(milliseconds: 220);

/// 「加载中 / 空态 / 正文」这类内容态之间的淡入淡出切换。
///
/// 与 [OpenHandCrossFadeSwitcher] 的分工：那个用于同尺寸内容互换；这里三态
/// 高度往往差很多（转圈一行、空态一行、列表整屏），所以默认连高度一起过渡。
/// 放在 Expanded / 固定高度容器里时把 [animateSize] 关掉——那种场景外层已经
/// 定好尺寸，再套 AnimatedSize 只会得到一个无界约束。
class OpenHandContentStateSwitcher extends StatelessWidget {
  const OpenHandContentStateSwitcher({
    super.key,
    required this.stateKey,
    required this.child,
    this.duration = kOpenHandContentStateDuration,
    this.alignment = Alignment.topCenter,
    this.animateSize = true,
  });

  /// 区分内容态的标识；变化时触发切换。
  final String stateKey;

  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;
  final bool animateSize;

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = openHandMotionDuration(context, duration);
    if (effectiveDuration == Duration.zero) return child;
    final switcher = AnimatedSwitcher(
      duration: effectiveDuration,
      switchInCurve: kOpenHandSwitchInCurve,
      switchOutCurve: kOpenHandSwitchOutCurve,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: alignment,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: KeyedSubtree(key: ValueKey<String>(stateKey), child: child),
    );
    if (!animateSize) return switcher;
    return AnimatedSize(
      duration: effectiveDuration,
      curve: kOpenHandSwitchInCurve,
      alignment: alignment,
      child: switcher,
    );
  }
}
