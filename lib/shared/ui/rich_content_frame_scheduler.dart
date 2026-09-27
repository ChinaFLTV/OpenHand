import 'package:flutter/widgets.dart';

/// 各渲染队列共用每帧一个任务的额度，同优先级队列轮流执行。
/// 单条任务仍需自行限制输入规模，分帧不能中断正在执行的同步解析。
class RichContentFrameScheduler {
  RichContentFrameScheduler({this.isPaused, int maxPending = 2048})
    : maxPending = maxPending.clamp(1, 8192);

  static const int _maxInvalidTasksPerFrame = 64;
  static final _active = <RichContentFrameScheduler>{};
  static bool _frameScheduled = false;

  final bool Function()? isPaused;
  final int maxPending;
  final _priorityPending = <_FrameTask>{};
  final _pending = <_FrameTask>{};

  VoidCallback schedule(
    VoidCallback task, {
    bool priority = false,
    bool Function()? isValid,
    VoidCallback? onDropped,
  }) {
    if (_priorityPending.length + _pending.length >= maxPending) {
      if (_pending.isNotEmpty) {
        _drop(_pending.first);
      } else if (priority) {
        _drop(_priorityPending.last);
      }
      // 淘汰回调可能同步补入任务，不能再次突破容量上限。
      if (_priorityPending.length + _pending.length >= maxPending) {
        onDropped?.call();
        return () {};
      }
    }
    final entry = _FrameTask(task, isValid, onDropped);
    if (priority) {
      // 同级任务先进先出，持续进入的新卡片不能饿死已在等待的正文。
      _priorityPending.add(entry);
    } else {
      _pending.add(entry);
    }
    _active.add(this);
    _scheduleFrame();
    return () => _drop(entry);
  }

  void _drop(_FrameTask entry) {
    if (!_priorityPending.remove(entry) && !_pending.remove(entry)) return;
    if (_priorityPending.isEmpty && _pending.isEmpty) _active.remove(this);
    entry.drop();
  }

  void clear() {
    final dropped = <_FrameTask>[..._priorityPending, ..._pending];
    _priorityPending.clear();
    _pending.clear();
    _active.remove(this);
    for (final entry in dropped) {
      entry.drop();
    }
  }

  /// 暂停源恢复后唤醒积压任务。
  static void resume() => _scheduleFrame();

  static void _scheduleFrame() {
    if (_frameScheduled || _active.isEmpty) return;
    _frameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _drain());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  static void _drain() {
    // 执行期间保留标记，任务内新增工作也只能进入下一帧。
    var allPaused = false;
    try {
      for (var invalid = 0; invalid < _maxInvalidTasksPerFrame; invalid++) {
        RichContentFrameScheduler? selected;
        for (final scheduler in _active) {
          if (scheduler.isPaused?.call() ?? false) continue;
          selected ??= scheduler;
          if (scheduler._priorityPending.isNotEmpty) {
            selected = scheduler;
            break;
          }
        }
        if (selected == null) {
          allPaused = true;
          return;
        }
        final queue = selected._priorityPending.isNotEmpty
            ? selected._priorityPending
            : selected._pending;
        final entry = queue.first;
        queue.remove(entry);
        _active.remove(selected);
        if (selected._priorityPending.isNotEmpty ||
            selected._pending.isNotEmpty) {
          _active.add(selected);
        }
        if (!entry.run()) continue;
        return;
      }
    } finally {
      _frameScheduled = false;
      // 全部队列暂停时不逐帧空转，由新任务或 [resume] 重新唤醒。
      if (!allPaused) _scheduleFrame();
    }
  }
}

class _FrameTask {
  _FrameTask(this.task, this.isValid, this.onDropped);

  VoidCallback? task;
  bool Function()? isValid;
  VoidCallback? onDropped;

  // 取消句柄可能比任务存活更久，结束前解除对正文与组件的引用。
  void _release() {
    task = null;
    isValid = null;
    onDropped = null;
  }

  void drop() {
    final notify = onDropped;
    _release();
    notify?.call();
  }

  bool run() {
    final execute = task;
    final validate = isValid;
    final notifyDropped = onDropped;
    _release();
    if (!(validate?.call() ?? true)) {
      notifyDropped?.call();
      return false;
    }
    execute?.call();
    return true;
  }
}
