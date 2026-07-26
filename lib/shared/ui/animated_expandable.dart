import 'package:flutter/material.dart';

import 'motion_preference.dart';
import 'openhand_reveal_switcher.dart';

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

/// 展开磁贴的默认内边距与展开时长。
const EdgeInsetsGeometry kOpenHandExpansionTilePadding = EdgeInsets.symmetric(
  horizontal: 16,
  vertical: 8,
);
const Duration kOpenHandExpansionRevealDuration = Duration(milliseconds: 280);
const Duration kOpenHandExpansionCollapseDuration = Duration(milliseconds: 200);

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
                  const SizedBox(width: 12),
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
                  const SizedBox(width: 8),
                  widget.trailing!,
                ],
                const SizedBox(width: 8),
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
