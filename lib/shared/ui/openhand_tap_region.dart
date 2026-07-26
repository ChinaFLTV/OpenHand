import 'package:flutter/material.dart';

/// 自绘可点击区域：在手势识别之上补一个手型指针。
///
/// 桌面端最直接的「这块能点」信号就是指针形状。用 GestureDetector 包一个自绘
/// 容器时（展开条、折叠头、下拉字段这些非 Button 形态）不会自动带上，指针停
/// 在上面仍是箭头，观感就是"点不动"。这里把 MouseRegion + GestureDetector 的
/// 固定组合收成一处，[onTap] 为 null 时自动退回默认指针。
class OpenHandTapRegion extends StatelessWidget {
  const OpenHandTapRegion({
    super.key,
    required this.onTap,
    required this.child,
    this.behavior,
  });

  final VoidCallback? onTap;
  final Widget child;
  final HitTestBehavior? behavior;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: behavior,
        child: child,
      ),
    );
  }
}
