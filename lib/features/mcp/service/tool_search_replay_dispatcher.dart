// 2026-05-09 — 把 ToolSearch 重放的「3 秒反悔窗口」从 openhand_home_page
// 抽出来，便于直接用 FakeAsync 单元测。任何调用方都可以构造一个实例
// （或多次复用），它内部只维护 Timer 与取消标志。
//
// 设计契约：
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
/// 把 createSession / replay 的回调编排抽到一个纯函数里，方便单元测试
/// 验证「session 一定先于 replay 创建」这条契约。
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

  /// 广播「当前是否有 pending 的反悔窗口在跑」。订阅者（例如 hardness phase
  /// header、托盘指示器）只读地监听此 [ValueListenable]：
  ///   - true：用户刚点过「重放」，正在 [defaultWindow] 内可以撤销
  ///   - false：要么从未调度过，要么已 fire / 已 cancel / 已 dispose
  /// 注意：这只是 hasPending 的镜像，不发任何业务负载（names/query 等）；
  /// 调用方若需要业务数据，请用 schedule 的回调闭包自行传递。
  ValueListenable<bool> get pendingListenable => _pendingNotifier;
  final ValueNotifier<bool> _pendingNotifier = ValueNotifier<bool>(false);

  /// 广播本次反悔窗口的截止时刻。订阅者可以基于 `deadline.difference(now)`
  /// 渲染倒计时（hardness phase header、托盘指示器等）。idle 时为 null。
  /// 始终与 [pendingListenable] 同步：true ⇒ deadline != null，false ⇒ null。
  ValueListenable<DateTime?> get pendingDeadlineListenable => _deadlineNotifier;
  final ValueNotifier<DateTime?> _deadlineNotifier = ValueNotifier<DateTime?>(
    null,
  );

  /// 是否还有 pending 的 timer 等待触发。
  bool get hasPending => _timer != null && !_settled;

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
      _setPending(false);
      // 成功 fire 后不再保留 onFire—「已发出」不应该被「重发」。
      _lastCancelledFire = null;
      _replayableNotifier.value = false;
      await onFire();
    });
    _pendingCancel = onCancel;
    _pendingFire = onFire;
    _deadlineNotifier.value = DateTime.now().add(effectiveWindow);
    _setPending(true);
  }

  FutureOr<void> Function()? _pendingFire;

  void Function()? _pendingCancel;

  /// 上次被 [cancel] 取消的 `onFire` 回调副本。`replayLastCancelled` 用
  /// 它来「再发一次」（快速调试入口）。每次新 [schedule] 会清空它（避免
  /// 重发已被覆盖的旧调度）；每次 [cancel] 会写入；首次成功 `fire` 时
  /// 也清空（避免误以为还能再放一次）。
  FutureOr<void> Function()? _lastCancelledFire;
  final ValueNotifier<bool> _replayableNotifier = ValueNotifier<bool>(false);

  /// 是否记忆了一次「可重放的」上次取消。Settings/调试入口订阅这个
  /// listenable 决定按钮置灰 / 高亮。
  ValueListenable<bool> get replayableListenable => _replayableNotifier;

  /// 是否有「上次被取消的 onFire」可以重发。
  bool get hasReplayable => _lastCancelledFire != null && !_disposed;

  /// 重发上次被 [cancel] 掉的 `onFire`；没有时 no-op。仅供调试 / 快速测试。
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
    _setPending(false);
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
    _setPending(false);
    _pendingNotifier.dispose();
    _deadlineNotifier.dispose();
    _replayableNotifier.dispose();
  }

  void _setPending(bool value) {
    if (_pendingNotifier.value == value) return;
    _pendingNotifier.value = value;
    if (!value && _deadlineNotifier.value != null) {
      _deadlineNotifier.value = null;
    }
  }
}
