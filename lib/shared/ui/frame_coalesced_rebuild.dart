import 'package:flutter/widgets.dart';

/// 把一帧内的多次重建请求合并为下一帧的一次 setState。
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
