import 'package:flutter/widgets.dart';

/// 把一帧内的多次重建请求合并为下一帧的一次 setState。
///
/// 会话控制器、CDP 会话这类数据源在单帧内可能连续 notifyListeners 十数次；
/// 逐次 setState 会把 build 打满，交互随之掉帧。各个仪表盘此前都各写了一份
/// 「布尔标志 + addPostFrameCallback」的合并逻辑，这里收敛为一个混入。
mixin FrameCoalescedRebuild<T extends StatefulWidget> on State<T> {
  bool _coalescedRebuildScheduled = false;

  /// 请求一次重建；同一帧内的重复请求只触发一次。
  ///
  /// [beforeRebuild] 在 setState 之前执行，用于同步由控制器派生的本地状态。
  void scheduleCoalescedRebuild([VoidCallback? beforeRebuild]) {
    if (!mounted || _coalescedRebuildScheduled) return;
    _coalescedRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _coalescedRebuildScheduled = false;
      if (!mounted) return;
      beforeRebuild?.call();
      setState(() {});
    });
  }
}
