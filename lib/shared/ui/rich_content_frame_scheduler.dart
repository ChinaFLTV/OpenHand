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
        final dropped = _pending.first;
        _pending.remove(dropped);
        dropped.onDropped?.call();
      } else if (priority) {
        final dropped = _priorityPending.last;
        _priorityPending.remove(dropped);
        dropped.onDropped?.call();
      } else {
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
    return () {
      if (!_priorityPending.remove(entry) && !_pending.remove(entry)) return;
      if (_priorityPending.isEmpty && _pending.isEmpty) _active.remove(this);
      entry.onDropped?.call();
    };
  }

  void clear() {
    final dropped = <_FrameTask>[..._priorityPending, ..._pending];
    _priorityPending.clear();
    _pending.clear();
    _active.remove(this);
    for (final entry in dropped) {
      entry.onDropped?.call();
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
        if (!(entry.isValid?.call() ?? true)) {
          entry.onDropped?.call();
          continue;
        }
        entry.task();
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
  const _FrameTask(this.task, this.isValid, this.onDropped);

  final VoidCallback task;
  final bool Function()? isValid;
  final VoidCallback? onDropped;
}
