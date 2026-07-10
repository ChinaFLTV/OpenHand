// ToolSearch 重放的撤销窗口，只维护 Timer 与取消状态。
// 行为契约：
// - schedule(onFire, onCancel) 启动一个 [window] 后触发 onFire 的 Timer。
//   若在窗口内调用 cancel()，Timer 取消、onCancel 被调用。否则 Timer 触发
//   时调用 onFire。
// - 两个回调互斥且各自至多触发一次。
// - 重复 schedule 会无声覆盖：上一个 pending 的回调既不被 fire 也不被
//   cancel（视为「被新调度替换」），由调用方决定要不要先 cancel()。
// - dispose() 等价于 cancel() 并标记 disposed；此后 schedule/cancel 都是
//   no-op，避免在 State.dispose 后回调里访问已销毁资源。

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/util/timer_safety.dart';

/// 在「新建一个独立 AI session 后再重放 select: 查询」这个两步流程中，
/// 保证先创建 session，再执行 replay。
///
/// 参数：
/// - [names]：本轮要 select: 的工具名列表。空列表直接返回。
/// - [createSession]：创建独立 session 的入口；返回是否成功。
/// - [replayInCurrentSession]：在当前 session 里组合 query + 发送的入口。
///
/// 行为：
/// - names 为空：什么也不做，立即返回。
/// - createSession 返回 false：跳过 replay（会话创建失败时不污染当前会话）。
/// - createSession 返回 true：紧接着调用 replayInCurrentSession(names)。
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

  /// 反悔窗口默认值。3 秒。可被 [schedule] 的 `window` 参数覆盖。
  final Duration defaultWindow;

  Timer? _timer;
  bool _settled = false;
  bool _disposed = false;

  /// 广播本次反悔窗口的截止时刻。订阅者可以基于 `deadline.difference(now)`
  /// 渲染倒计时（harness phase header、托盘指示器等）。idle 时为 null。
  ValueListenable<DateTime?> get pendingDeadlineListenable => _deadlineNotifier;
  final ValueNotifier<DateTime?> _deadlineNotifier = ValueNotifier<DateTime?>(
    null,
  );

  /// 调度一次重放。会取消之前任何 pending 的调度（不触发其回调）。
  /// [onFire] 在窗口耗尽后触发；[onCancel] 在窗口内被 [cancel] 时触发。
  /// 可选 [window] 覆盖本次调度的反悔窗口长度。
  void schedule({
    required FutureOr<void> Function() onFire,
    required void Function() onCancel,
    Duration? window,
  }) {
    if (_disposed) return;
    _timer?.cancel();
    _settled = false;
    // 新一轮 schedule 会丢弃先前记忆的 lastCancelledFire，避免
    // 「重发一个已被覆盖的旧调度」这种诡异语义。
    _lastCancelledFire = null;
    _replayableNotifier.value = false;
    final effectiveWindow = window ?? defaultWindow;
    _timer = startSafeTimer(effectiveWindow, () async {
      if (_disposed || _settled) return;
      _settled = true;
      _timer = null;
      _deadlineNotifier.value = null;
      // 成功 fire 后不再保留 onFire—「已发出」不应该被「重发」。
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

  /// 上次被 [cancel] 取消的 `onFire` 回调副本。`replayLastCancelled` 用
  /// 它来「再发一次」。每次新 [schedule] 会清空它（避免
  /// 重发已被覆盖的旧调度）；每次 [cancel] 会写入；首次成功 `fire` 时
  /// 也清空（避免误以为还能再放一次）。
  FutureOr<void> Function()? _lastCancelledFire;
  final ValueNotifier<bool> _replayableNotifier = ValueNotifier<bool>(false);

  /// 是否记忆了一次「可重放的」上次取消。设置页订阅这个
  /// listenable 决定按钮置灰 / 高亮。
  ValueListenable<bool> get replayableListenable => _replayableNotifier;

  /// 重发上次被 [cancel] 掉的 `onFire`；没有时 no-op。
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

  /// 在窗口内取消调度。已 fire 或已 cancel 的调度调用此方法是 no-op。
  void cancel() {
    if (_disposed || _settled || _timer == null) return;
    _timer?.cancel();
    _timer = null;
    _settled = true;
    final cb = _pendingCancel;
    _pendingCancel = null;
    // 记忆本次被取消的 onFire，给「Replay last cancel」快捷用。
    _lastCancelledFire = _pendingFire;
    _pendingFire = null;
    _replayableNotifier.value = _lastCancelledFire != null;
    _deadlineNotifier.value = null;
    cb?.call();
  }

  /// 释放：等同于不触发任何回调地丢弃 pending timer，并阻塞后续调度。
  void dispose() {
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
