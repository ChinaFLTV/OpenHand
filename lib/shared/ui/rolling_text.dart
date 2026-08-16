// Q 弹字符滚轮，按字符位置切换。每个槽位用
// AnimatedSwitcher 在字符变化时做"上滚出 / 下滚入" + easeOutBack 动效，
// 给 byte 数 / 计数等动态数字一个柔软的轮盘感。支持任意字符（小数点、空格、
// 字母），适合 "12.3 MB" / "5 项" 这种单位混排的文本。
// Props 仅有两个：
// - [text]: 要展示的完整字符串；
// - [style]: 字符样式（推荐启用 tabular 数字以避免抖动）。
// 使用约束：
// - 内部以 Row 横向铺开；调用方应保证它能拿到 horizontal intrinsic 宽度，
//   否则 Stack 子元素会以最小宽度收缩。
// - 字符长度变化（如 "9 KB" → "10 KB"）会让后续槽位"键值"变更，所有
//   后续字符都会触发滚动；这正是预期行为：长度跳变也保留视觉连续性。
import 'package:flutter/material.dart';

import 'bounded_animation.dart';
import 'collision_safe_animated_switcher.dart';
import 'motion_preference.dart';

class RollingText extends StatelessWidget {
  const RollingText({
    super.key,
    required this.text,
    required this.style,
    this.duration = const Duration(milliseconds: 360),
  });

  final String text;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final motionEnabled = openHandTickerMotionEnabled(context);
    final children = <Widget>[];
    final graphemes = text.characters.toList(growable: false);
    for (var i = 0; i < graphemes.length; i += 1) {
      final ch = graphemes[i];
      children.add(
        motionEnabled
            ? _RollingChar(char: ch, slot: i, style: style, duration: duration)
            : _RollingStaticChar(char: ch, slot: i, style: style),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _RollingStaticChar extends StatelessWidget {
  const _RollingStaticChar({
    required this.char,
    required this.slot,
    required this.style,
  });

  final String char;
  final int slot;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return _RollingCharText(char: char, slot: slot, style: style);
  }
}

class _RollingCharText extends StatelessWidget {
  const _RollingCharText({
    required this.char,
    required this.slot,
    required this.style,
  });

  final String char;
  final int slot;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text(
      char,
      key: ValueKey<String>('s$slot:$char'),
      style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

class _RollingChar extends StatelessWidget {
  const _RollingChar({
    required this.char,
    required this.slot,
    required this.style,
    required this.duration,
  });

  final String char;
  final int slot;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      transitionBuilder: (child, animation) {
        final outgoing = animation.status == AnimationStatus.reverse;
        final opacity = openHandBoundedCurveAnimation(
          parent: animation,
          curve: kOpenHandSwitchInCurve,
          reverseCurve: kOpenHandSwitchOutCurve,
        );
        final motion = openHandCurveAnimation(
          parent: animation,
          curve: kOpenHandEntranceCurve,
          reverseCurve: kOpenHandSwitchOutCurve,
        );
        final slide = Tween<Offset>(
          begin: Offset(0, outgoing ? -0.6 : 0.6),
          end: Offset.zero,
        ).animate(motion);
        return ClipRect(
          child: SlideTransition(
            position: slide,
            child: FadeTransition(opacity: opacity, child: child),
          ),
        );
      },
      layoutBuilder: buildCollisionSafeAnimatedSwitcherLayout,
      // Slot index 让相同字符在不同位置时也有独立 key，避免
      // "12 KB" → "21 KB" 这种重排被误判为无变化。
      child: _RollingCharText(char: char, slot: slot, style: style),
    );
  }
}
