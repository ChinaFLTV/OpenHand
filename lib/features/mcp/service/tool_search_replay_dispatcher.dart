import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/util/timer_safety.dart';

/// 创建独立会话成功后重放 ToolSearch 查询。
Future<void> replayToolSearchInFreshSession({
  required List<String> names,
  required Future<bool> Function() createSession,
  required Future<void> Function(List<String> names) replayInCurrentSession,
}) async {
  if (names.isEmpty) return;
  final created = await createSession();
  if (!created) return;
  await replayInCurrentSession(names);
}

class ToolSearchReplayDispatcher {
  ToolSearchReplayDispatcher({this.defaultWindow = const Duration(seconds: 3)});

  /// 默认反悔窗口，可由 [schedule] 单次覆盖。
  final Duration defaultWindow;

  Timer? _timer;
  bool _settled = false;
  bool _disposed = false;

  /// 当前反悔窗口截止时间；空闲时为 null。
  ValueListenable<DateTime?> get pendingDeadlineListenable => _deadlineNotifier;
  final ValueNotifier<DateTime?> _deadlineNotifier = ValueNotifier<DateTime?>(
    null,
  );

  /// 调度一次重放。已有待执行调度会被静默替换。
  /// [onFire] 在窗口耗尽后触发；[onCancel] 在窗口内被 [cancel] 时触发。
  void schedule({
    required FutureOr<void> Function() onFire,
    required void Function() onCancel,
    Duration? window,
  }) {
    if (_disposed) return;
    _timer?.cancel();
    _settled = false;
    // 新调度不能重放已被覆盖的旧回调。
    _lastCancelledFire = null;
    _replayableNotifier.value = false;
    final effectiveWindow = window ?? defaultWindow;
    _timer = startSafeTimer(effectiveWindow, () async {
      if (_disposed || _settled) return;
      _settled = true;
      _timer = null;
      _deadlineNotifier.value = null;
      // 执行后清除所有回调，保证至多触发一次。
      _pendingCancel = null;
      _pendingFire = null;
      _lastCancelledFire = null;
      _replayableNotifier.value = false;
      await onFire();
    });
    _pendingCancel = onCancel;
    _pendingFire = onFire;
    _deadlineNotifier.value = DateTime.now().add(effectiveWindow);
  }

  FutureOr<void> Function()? _pendingFire;

  void Function()? _pendingCancel;

  /// 上次被 [cancel] 取消、仍可重放的回调。
  FutureOr<void> Function()? _lastCancelledFire;
  final ValueNotifier<bool> _replayableNotifier = ValueNotifier<bool>(false);

  /// 是否存在可重放的已取消调度。
  ValueListenable<bool> get replayableListenable => _replayableNotifier;

  /// 重发上次被 [cancel] 取消的回调；没有时返回 false。
  /// 不影响当前 pending 的调度。
  Future<bool> replayLastCancelled() async {
    if (_disposed) return false;
    final cb = _lastCancelledFire;
    if (cb == null) return false;
    _lastCancelledFire = null;
    _replayableNotifier.value = false;
    await cb();
    return true;
  }

  /// 取消待执行调度；已结束时不执行。
  void cancel() {
    if (_disposed || _settled || _timer == null) return;
    _timer?.cancel();
    _timer = null;
    _settled = true;
    final cb = _pendingCancel;
    _pendingCancel = null;
    // 保留本次回调，供用户主动重放。
    _lastCancelledFire = _pendingFire;
    _pendingFire = null;
    _replayableNotifier.value = _lastCancelledFire != null;
    _deadlineNotifier.value = null;
    cb?.call();
  }

  /// 释放资源并丢弃待执行调度。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pendingCancel = null;
    _pendingFire = null;
    _lastCancelledFire = null;
    _deadlineNotifier.value = null;
    _deadlineNotifier.dispose();
    _replayableNotifier.dispose();
  }
}
