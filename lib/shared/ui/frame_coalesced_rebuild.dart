import 'package:flutter/widgets.dart';

/// 合并连续通知，在下一帧构建前同步状态并刷新界面。
mixin FrameCoalescedRebuild<T extends StatefulWidget> on State<T> {
  int? _rebuildCallbackId;
  VoidCallback? _beforeRebuild;

  /// 请求一次重建；同一帧内的重复请求只触发一次。
  ///
  /// [beforeRebuild] 保留最近一次非空回调，用于同步控制器派生状态。
  void scheduleCoalescedRebuild([VoidCallback? beforeRebuild]) {
    if (!mounted) return;
    _beforeRebuild = beforeRebuild ?? _beforeRebuild;
    if (_rebuildCallbackId != null) return;
    _rebuildCallbackId = WidgetsBinding.instance.scheduleFrameCallback((_) {
      _rebuildCallbackId = null;
      final synchronize = _beforeRebuild;
      _beforeRebuild = null;
      if (!mounted) return;
      synchronize?.call();
      setState(() {});
    });
  }

  @override
  void dispose() {
    final callbackId = _rebuildCallbackId;
    if (callbackId != null) {
      WidgetsBinding.instance.cancelFrameCallbackWithId(callbackId);
    }
    _rebuildCallbackId = null;
    _beforeRebuild = null;
    super.dispose();
  }
}
