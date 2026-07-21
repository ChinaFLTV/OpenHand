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
