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
      return RotatedBox(quarterTurns: expanded ? 1 : 0, child: icon);
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
const double kOpenHandCircularExpansionToggleSize = 34;

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
    this.suppressHoverOverlay = false,
    this.circularToggle = false,
    this.headerAlignment = CrossAxisAlignment.center,
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

  /// 是否关闭磁贴的悬停、按下和水波纹覆盖色。
  final bool suppressHoverOverlay;

  /// 是否使用圆角方形折叠/展开指示器替代默认三角箭头。
  final bool circularToggle;

  /// 标题行与指示器的交叉轴对齐；决策卡顶部把指示器贴在问题行。
  final CrossAxisAlignment headerAlignment;

  @override
  State<OpenHandExpansionTile> createState() => _OpenHandExpansionTileState();
}

class _OpenHandExpansionTileState extends State<OpenHandExpansionTile> {
  late bool _expanded = widget.initiallyExpanded;
  bool _userToggled = false;

  void _toggle() {
    final next = !_expanded;
    final armSwitcher = !_userToggled && openHandTickerMotionEnabled(context);
    if (armSwitcher) {
      setState(() => _userToggled = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _expanded = next);
        widget.onExpansionChanged?.call(next);
      });
      return;
    }
    setState(() {
      _userToggled = true;
      _expanded = next;
    });
    widget.onExpansionChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = _expanded
        ? Padding(
            padding: widget.childrenPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          )
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggle,
          hoverColor: widget.suppressHoverOverlay ? Colors.transparent : null,
          splashColor: widget.suppressHoverOverlay ? Colors.transparent : null,
          highlightColor: widget.suppressHoverOverlay
              ? Colors.transparent
              : null,
          overlayColor: widget.suppressHoverOverlay
              ? const WidgetStatePropertyAll<Color>(Colors.transparent)
              : null,
          child: Padding(
            padding: widget.tilePadding,
            child: Row(
              crossAxisAlignment: widget.headerAlignment,
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
                if (widget.circularToggle)
                  IgnorePointer(
                    child: _CircularExpansionToggle(expanded: _expanded),
                  )
                else
                  AnimatedExpandChevron(
                    expanded: _expanded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
        if (!_userToggled)
          body ?? const SizedBox.shrink()
        else
          OpenHandVerticalRevealSwitcher(
            duration: kOpenHandExpansionRevealDuration,
            reverseDuration: kOpenHandExpansionCollapseDuration,
            presentKey: const ValueKey<String>('expanded'),
            child: body,
          ),
      ],
    );
  }
}

class _CircularExpansionToggle extends StatelessWidget {
  const _CircularExpansionToggle({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = openHandMotionDuration(context, kOpenHandMotion240);
    final icon = expanded
        ? Icons.keyboard_arrow_up_rounded
        : Icons.keyboard_arrow_down_rounded;
    return AnimatedContainer(
      duration: duration,
      curve: kOpenHandSwitchInCurve,
      width: kOpenHandCircularExpansionToggleSize,
      height: kOpenHandCircularExpansionToggleSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.76),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.8)),
      ),
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: kOpenHandSwitchInCurve,
        switchOutCurve: kOpenHandSwitchInCurve,
        child: Icon(
          icon,
          key: ValueKey<bool>(expanded),
          size: 20,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 折叠区在完全展开前屏蔽命中测试的阈值：动画尾段才放开交互，
/// 避免用户在内容还在滑动时误触。
const double _kCollapsibleInteractiveThreshold = 0.98;

/// 顶部锚定的「高度 + 淡出」折叠动效。
/// 遵循全局动效设置，禁用时立即切换。
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
      curve: kOpenHandEmphasizedCurve,
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
