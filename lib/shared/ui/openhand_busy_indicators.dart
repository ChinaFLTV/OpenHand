import 'package:flutter/material.dart';

import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_reveal_switcher.dart';

/// 忙碌指示条的默认高度与出入场时长。
const double kOpenHandBusyBarHeight = 3;
const Duration kOpenHandBusyBarRevealDuration = kOpenHandMotion200;
const Duration kOpenHandBusyBarCollapseDuration = kOpenHandMotion160;

/// 面板顶部的忙碌指示条：出现与消失走全局动效的纵向展开。
class OpenHandBusyProgressBar extends StatelessWidget {
  const OpenHandBusyProgressBar({
    super.key,
    required this.busy,
    this.value,
    this.minHeight = kOpenHandBusyBarHeight,
  });

  final bool busy;

  /// 有确定进度时传 0..1；为 null 时走不确定的循环动画。
  ///
  /// 越界或 NaN 会触发 LinearProgressIndicator 的断言，这里统一夹紧后再传入。
  final double? value;

  final double minHeight;

  double? get _clampedValue {
    final raw = value;
    if (raw == null || raw.isNaN) return null;
    return raw.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return OpenHandVerticalRevealSwitcher(
      duration: kOpenHandBusyBarRevealDuration,
      reverseDuration: kOpenHandBusyBarCollapseDuration,
      presentKey: const ValueKey<String>('busy'),
      child: busy
          ? LinearProgressIndicator(value: _clampedValue, minHeight: minHeight)
          : null,
    );
  }
}

/// 忙碌指示图标的默认边长与切换时长。
const double kOpenHandBusyIconSize = 18;
const Duration kOpenHandBusyIconSwapDuration = kOpenHandMotion200;

/// 忙碌态的前导指示：转圈与状态图标之间做淡入淡出 + 轻微缩放的切换。
class OpenHandBusyStatusIcon extends StatelessWidget {
  const OpenHandBusyStatusIcon({
    super.key,
    required this.busy,
    required this.icon,
    this.color,
    this.size = kOpenHandBusyIconSize,
    this.strokeWidth = 2,
  });

  final bool busy;

  /// 非忙碌时展示的状态图标；null 表示仅占位。
  final IconData? icon;

  final Color? color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final Widget child = busy
        ? SizedBox(
            key: const ValueKey<String>('busy'),
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: strokeWidth,
              color: color,
            ),
          )
        : SizedBox(
            key: const ValueKey<String>('idle'),
            width: size,
            height: size,
            child: icon == null ? null : Icon(icon, size: size, color: color),
          );
    final duration = openHandMotionDuration(
      context,
      kOpenHandBusyIconSwapDuration,
    );
    if (duration == Duration.zero) return child;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: kOpenHandSwitchOutCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: child,
    );
  }
}
