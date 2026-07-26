import 'package:flutter/material.dart';

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
