import 'package:flutter/material.dart';

import 'motion_preference.dart';
import 'openhand_reveal_switcher.dart';

/// 忙碌指示条的默认高度与出入场时长。
const double kOpenHandBusyBarHeight = 3;
const Duration kOpenHandBusyBarRevealDuration = Duration(milliseconds: 200);
const Duration kOpenHandBusyBarCollapseDuration = Duration(milliseconds: 160);

/// 面板顶部的忙碌指示条：出现与消失走全局动效的纵向展开。
///
/// 此前八个运维弹窗都写成 `if (_busy) const LinearProgressIndicator(...)`，
/// 忙碌态切换时这一条 3px 会凭空出现 / 消失，把下方内容整体顶动一次；忙碌
/// 状态又往往在数百毫秒内反复翻转，观感就是持续抖动。改为随高度平滑展开，
/// 并与全局弹窗动效设置保持一致。
class OpenHandBusyProgressBar extends StatelessWidget {
  const OpenHandBusyProgressBar({
    super.key,
    required this.busy,
    this.value,
    this.minHeight = kOpenHandBusyBarHeight,
  });

  final bool busy;

  /// 有确定进度时传 0..1；为 null 时走不确定的循环动画。
  final double? value;

  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return OpenHandVerticalRevealSwitcher(
      duration: kOpenHandBusyBarRevealDuration,
      reverseDuration: kOpenHandBusyBarCollapseDuration,
      presentKey: const ValueKey<String>('busy'),
      child: busy
          ? LinearProgressIndicator(value: value, minHeight: minHeight)
          : null,
    );
  }
}

/// 忙碌指示图标的默认边长与切换时长。
const double kOpenHandBusyIconSize = 18;
const Duration kOpenHandBusyIconSwapDuration = Duration(milliseconds: 200);

/// 忙碌态的前导指示：转圈与状态图标之间做淡入淡出 + 轻微缩放的切换。
///
/// 安装 / 运行类弹窗此前都写成 `if (running) SizedBox(spinner) else Icon(...)`：
/// 状态翻转时图标硬切，且转圈与图标尺寸并不一致，整行文字会跟着横向抖一下。
/// 这里统一到同一边长并走平滑切换；[icon] 为 null 时占位但不绘制，用于那些
/// 只在忙碌时才显示指示、否则会让整行位移的场景。
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
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: child,
    );
  }
}
