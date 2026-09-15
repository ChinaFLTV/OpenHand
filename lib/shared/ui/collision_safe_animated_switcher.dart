import 'package:flutter/widgets.dart';

/// 构建不会挂载重复 Key 过渡节点的 [AnimatedSwitcher] 布局。
/// 快速执行 A → B → A 时，避免尚未退场的 A 与新 A 触发同级 Key 冲突。
/// 退场层默认不参与命中测试，避免淡出子树在尚未 layout 完成时被 hit-test。
Widget buildCollisionSafeAnimatedSwitcherLayout(
  Widget? currentChild,
  List<Widget> previousChildren, {
  AlignmentGeometry alignment = Alignment.center,
  bool sizeToCurrentChild = false,
  StackFit fit = StackFit.loose,
  Clip? clipBehavior,
}) {
  final usedKeys = <Key>{};
  final currentKey = currentChild?.key;
  if (currentKey != null) usedKeys.add(currentKey);

  final uniquePreviousReversed = <Widget>[];
  for (final child in previousChildren.reversed) {
    final key = child.key;
    if (key == null || usedKeys.add(key)) {
      uniquePreviousReversed.add(child);
    }
  }

  return Stack(
    alignment: alignment,
    fit: fit,
    clipBehavior:
        clipBehavior ?? (sizeToCurrentChild ? Clip.none : Clip.hardEdge),
    children: <Widget>[
      if (sizeToCurrentChild)
        for (final child in uniquePreviousReversed.reversed)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(key: child.key, child: child),
          )
      else
        for (final child in uniquePreviousReversed.reversed)
          IgnorePointer(key: child.key, child: child),
      if (currentChild != null) currentChild,
    ],
  );
}
