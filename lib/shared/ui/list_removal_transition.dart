import 'package:flutter/material.dart';

import 'motion_preference.dart';

/// 按全局列表动效设置淡出并收起行高，退场结束后由调用方删除数据。
class OpenHandListRemovalTransition extends StatelessWidget {
  const OpenHandListRemovalTransition({
    super.key,
    required this.collapsed,
    required this.child,
    this.shrinkExtent = true,
  });

  /// 为 true 时开始退场。
  final bool collapsed;

  /// 是否连同占位一起收起。
  ///
  /// 纵向列表传 true：行高收到 0，下方内容平滑跟上。定高网格传 false——格子
  /// 的尺寸由 delegate 决定，收起高度只会在原位留一个洞，就地淡出缩小才对。
  final bool shrinkExtent;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.listItem,
    );
    final duration = motion.exitDuration;
    if (duration <= Duration.zero) {
      return collapsed ? const SizedBox.shrink() : child;
    }
    final curve = motion.curve.reverseCurve;
    if (!shrinkExtent) {
      return AnimatedScale(
        duration: duration,
        curve: curve,
        scale: collapsed ? 0.94 : 1,
        child: AnimatedOpacity(
          duration: duration,
          curve: curve,
          opacity: collapsed ? 0 : 1,
          child: IgnorePointer(ignoring: collapsed, child: child),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: collapsed ? 0 : 1),
      duration: duration,
      curve: curve,
      builder: (context, value, content) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          widthFactor: 1,
          heightFactor: value,
          child: Opacity(opacity: value, child: content),
        ),
      ),
      child: IgnorePointer(
        ignoring: collapsed,
        child: ExcludeSemantics(excluding: collapsed, child: child),
      ),
    );
  }
}

/// 等待一次列表项退场动效走完。
///
/// 调用方在标记退场后 await 它，再执行真正的删除；关掉动效时立即返回，不会
/// 平白给删除操作加延迟。
Future<void> awaitOpenHandListRemoval(BuildContext context) {
  final duration = openHandMotionSettingsOf(
    context,
    OpenHandMotionSettingsScope.listItem,
  ).exitDuration;
  if (duration <= Duration.zero) return Future<void>.value();
  return Future<void>.delayed(duration);
}

/// 统一管理列表项退场状态，避免列表页重复维护删除标记。
class OpenHandRemovableListScope extends StatefulWidget {
  const OpenHandRemovableListScope({super.key, required this.builder});

  final Widget Function(BuildContext context, OpenHandListRemoval removal)
  builder;

  @override
  State<OpenHandRemovableListScope> createState() =>
      _OpenHandRemovableListScopeState();
}

/// 交给列表页的句柄：查询某行是否退场中，以及「收起后再删」的执行入口。
class OpenHandListRemoval {
  const OpenHandListRemoval._(this._state);

  final _OpenHandRemovableListScopeState _state;

  bool isRemoving(String id) => _state._removingIds.contains(id);

  /// 标记 [id] 退场 → 等动效走完 → 执行 [delete]。
  ///
  /// [delete] 抛出时同样解除标记：否则那一行会永久停在收起态，看起来像丢了
  /// 数据，实际只是没删成。
  Future<void> run(String id, Future<void> Function() delete) {
    return _state._run(id, delete);
  }
}

class _OpenHandRemovableListScopeState
    extends State<OpenHandRemovableListScope> {
  final Set<String> _removingIds = <String>{};

  Future<void> _run(String id, Future<void> Function() delete) async {
    if (!mounted || _removingIds.contains(id)) return;
    setState(() => _removingIds.add(id));
    await awaitOpenHandListRemoval(context);
    try {
      await delete();
    } finally {
      if (mounted) setState(() => _removingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, OpenHandListRemoval._(this));
  }
}
