import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../util/input_value_parsing.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_reveal_switcher.dart';

/// 随展开状态旋转 0 到 90 度，并遵循全局减少动画设置。
class AnimatedExpandChevron extends StatelessWidget {
  const AnimatedExpandChevron({
    super.key,
    required this.expanded,
    this.size = 18,
    this.color,
    this.duration = kOpenHandMotion240,
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
      curve: kOpenHandSwitchInCurve,
      child: icon,
    );
  }
}

/// 展开磁贴的默认内边距与展开时长。
const EdgeInsetsGeometry kOpenHandExpansionTilePadding = EdgeInsets.symmetric(
  horizontal: 16,
  vertical: 8,
);
const Duration kOpenHandExpansionRevealDuration = kOpenHandMotion280;
const Duration kOpenHandExpansionCollapseDuration = kOpenHandMotion200;

/// 遵循全局动效设置的展开磁贴。
///
/// 替代 Material 的 `ExpansionTile`：后者的展开时长写死在框架内部，全局动效
/// 设置调慢或关闭时它依旧按自己的节奏展开，和应用其余展开动作对不上拍。这里
/// 复用 [OpenHandVerticalRevealSwitcher]，与设置页、弹窗内的展开保持同一条
/// 曲线；关闭动效时直接切换，不挂载 Ticker。
class OpenHandExpansionTile extends StatefulWidget {
  const OpenHandExpansionTile({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.leading,
    this.trailing,
    this.initiallyExpanded = false,
    this.tilePadding = kOpenHandExpansionTilePadding,
    this.childrenPadding = EdgeInsets.zero,
    this.onExpansionChanged,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;

  /// 排在展开箭头之前的附加内容（状态徽标、耗时等）。
  final Widget? trailing;

  final List<Widget> children;
  final bool initiallyExpanded;
  final EdgeInsetsGeometry tilePadding;
  final EdgeInsetsGeometry childrenPadding;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<OpenHandExpansionTile> createState() => _OpenHandExpansionTileState();
}

class _OpenHandExpansionTileState extends State<OpenHandExpansionTile> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: widget.tilePadding,
            child: Row(
              children: [
                if (widget.leading != null) ...[
                  widget.leading!,
                  kOpenHandHGap12,
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle.merge(
                        style: theme.textTheme.titleSmall,
                        child: widget.title,
                      ),
                      if (widget.subtitle != null) widget.subtitle!,
                    ],
                  ),
                ),
                if (widget.trailing != null) ...[
                  kOpenHandHGap8,
                  widget.trailing!,
                ],
                kOpenHandHGap8,
                AnimatedExpandChevron(
                  expanded: _expanded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        OpenHandVerticalRevealSwitcher(
          duration: kOpenHandExpansionRevealDuration,
          reverseDuration: kOpenHandExpansionCollapseDuration,
          presentKey: const ValueKey<String>('expanded'),
          child: _expanded
              ? Padding(
                  padding: widget.childrenPadding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

/// 折叠区在完全展开前屏蔽命中测试的阈值：动画尾段才放开交互，
/// 避免用户在内容还在滑动时误触。
const double _kCollapsibleInteractiveThreshold = 0.98;

/// 顶部锚定的「高度 + 淡出」折叠动效。
///
/// 主会话输入区与 Harness 输入区的展开内容此前各写了一份完全相同的
/// TweenAnimationBuilder：两处都直接用了原始时长常量，绕过全局动效设置，
/// 于是关闭动效后相邻的 AnimatedContainer 立刻收起、内容却仍在淡出 260ms。
class OpenHandCollapsibleFade extends StatelessWidget {
  const OpenHandCollapsibleFade({
    super.key,
    required this.collapsed,
    required this.child,
    this.duration = kOpenHandMotion260,
  });

  final bool collapsed;
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = openHandMotionDuration(context, duration);
    if (effectiveDuration == Duration.zero) {
      return collapsed ? const SizedBox.shrink() : child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: collapsed ? 1 : 0, end: collapsed ? 0 : 1),
      duration: effectiveDuration,
      curve: Curves.easeInOutCubicEmphasized,
      child: child,
      builder: (context, value, animatedChild) {
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: value,
            child: IgnorePointer(
              ignoring: value < _kCollapsibleInteractiveThreshold,
              child: Opacity(
                opacity: clampUnitInterval(value),
                child: animatedChild,
              ),
            ),
          ),
        );
      },
    );
  }
}
