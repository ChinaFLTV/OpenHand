import 'package:flutter/material.dart';

import 'motion_preference.dart';

/// 列表项删除时的收起退场。
///
/// `ListView.builder` 的数据一旦从源列表里消失，那一行就是瞬间不见、下方内容
/// 整体上跳——这正是「生硬的 UI 变换」。配合 [awaitOpenHandListRemoval] 使用：
/// 先把 id 标记为退场中让本组件把行高收到 0，等动效走完再真正删数据。
///
/// 时长与曲线取全局动效设置的 listItem 档，关掉动效时退化为立即消失。
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
    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        duration: duration,
        curve: curve,
        opacity: collapsed ? 0 : 1,
        child: collapsed
            ? const SizedBox(width: double.infinity, height: 0)
            : child,
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

/// 列表项删除退场的作用域。
///
/// 退场需要有人记住「哪些行正在收起」，但 Hooks / 定时任务 / 指令 / 记忆这些
/// 列表页本身是 StatelessWidget。与其逐页改成 StatefulWidget，不如由这个作用域
/// 持有那份集合，把句柄交给 [builder]。
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
