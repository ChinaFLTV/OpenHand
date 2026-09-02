import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import 'motion_durations.dart';
import 'motion_preference.dart';

const double kOpenHandToolbarIconButtonSize = 44;
const double kOpenHandToolbarIconSize = 22;

/// 运维与控制台头部共用的动画图标按钮。
class OpenHandToolbarIconButton extends StatelessWidget {
  const OpenHandToolbarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.radius = kOpenHandRadius12,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final borderRadius = BorderRadius.circular(radius);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          hoverColor: colors.primary.withValues(alpha: 0.08),
          splashColor: colors.primary.withValues(alpha: 0.10),
          highlightColor: colors.primary.withValues(alpha: 0.06),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: openHandMotionDuration(context, kOpenHandMotion160),
            curve: kOpenHandSwitchInCurve,
            width: kOpenHandToolbarIconButtonSize,
            height: kOpenHandToolbarIconButtonSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled
                  ? colors.surfaceContainerHigh.withValues(alpha: 0.80)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.40),
              borderRadius: borderRadius,
              border: Border.all(
                color: colors.outlineVariant.withValues(
                  alpha: enabled ? 0.72 : 0.40,
                ),
              ),
            ),
            child: Icon(
              icon,
              size: kOpenHandToolbarIconSize,
              color: enabled
                  ? colors.onSurfaceVariant
                  : colors.onSurfaceVariant.withValues(alpha: 0.42),
            ),
          ),
        ),
      ),
    );
  }
}

/// 右对齐的横向工具栏。空间不足时从左侧溢出，优先保留末端操作可见。
class OpenHandTrailingToolbar extends StatelessWidget {
  const OpenHandTrailingToolbar({
    super.key,
    required this.children,
    this.spacing = 8,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 0.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0) SizedBox(width: spacing),
                  children[index],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 运维面板头部布局：宽度足够时「标识 + 操作」并排，压缩后改为上下两行且
/// 操作靠右对齐。
///
/// [compactBreakpoint] 是切换到窄屏排布的宽度阈值。
class OpenHandResponsiveHeaderLayout extends StatelessWidget {
  const OpenHandResponsiveHeaderLayout({
    super.key,
    required this.identity,
    required this.actions,
    required this.compactBreakpoint,
    this.spacing = 12,
    this.compactSpacing = 10,
  });

  final Widget identity;
  final Widget actions;
  final double compactBreakpoint;
  final double spacing;
  final double compactSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < compactBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              SizedBox(height: compactSpacing),
              Align(alignment: AlignmentDirectional.centerEnd, child: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: identity),
            SizedBox(width: spacing),
            actions,
          ],
        );
      },
    );
  }
}

/// 会话头部条的固定内边距、最小高度与圆角。
const double kOpenHandSessionHeaderMinHeight = 48;
const EdgeInsets kOpenHandSessionHeaderPadding = EdgeInsets.symmetric(
  horizontal: 14,
  vertical: 6,
);
const BorderRadius kOpenHandSessionHeaderRadius = BorderRadius.all(
  Radius.circular(kOpenHandRadius16),
);

/// 会话头部条：左侧标题占两份宽，右侧尾部工具条占三份宽。
///
/// 主会话工具条与 Harness 会话头部此前各写了一份同样的外框与栅格比例，
/// 改一处圆角或内边距就会两边不一致。
class OpenHandSessionHeaderBar extends StatelessWidget {
  const OpenHandSessionHeaderBar({
    super.key,
    required this.title,
    required this.toolbarItems,
    this.toolbarSpacing = 8,
    this.below,
  });

  /// 已经排好版式的标题组件（通常是 OpenHandAnimatedTitleText）。
  final Widget title;

  final List<Widget> toolbarItems;
  final double toolbarSpacing;

  /// 标题行下方的附加内容；为 null 时头部只有一行。
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final headerRow = Row(
      children: [
        Expanded(flex: 2, child: title),
        kOpenHandHGap10,
        Expanded(
          flex: 3,
          child: OpenHandTrailingToolbar(
            spacing: toolbarSpacing,
            children: toolbarItems,
          ),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(
        minHeight: kOpenHandSessionHeaderMinHeight,
      ),
      padding: kOpenHandSessionHeaderPadding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: kOpenHandSessionHeaderRadius,
      ),
      child: below == null
          ? headerRow
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [headerRow, below!],
            ),
    );
  }
}
