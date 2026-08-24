import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app/support/silent_log.dart';
import '../util/bounded_log_buffer.dart';
import '../util/timer_safety.dart';
import 'auto_follow_scroll_guard.dart';
import 'motion_preference.dart';

/// 刷新后贴底的默认动画时长。
const Duration kBufferedConsoleFollowDuration = Duration(milliseconds: 120);

/// 把高频子进程输出按帧批量刷入 UI 的控制台日志宿主。
///
/// 按帧合并高频日志，避免逐行重建；刷新后自动跟随到底部。
mixin BufferedConsoleLogHost<T extends StatefulWidget> on State<T> {
  /// 已落地、可直接渲染的日志行。
  final BoundedLogBuffer logLines = BoundedLogBuffer();

  final ScrollController logScrollController = ScrollController();
  final AutoFollowScrollGuard logScrollGuard = AutoFollowScrollGuard();

  final BoundedLogBuffer _pendingLines = BoundedLogBuffer();
  Timer? _flushTimer;

  /// [silentLog] 使用的组件标签。
  String get consoleLogTag;

  /// 刷新后贴底的动画时长；会再经全局动效设置换算。
  Duration get consoleFollowDuration => kBufferedConsoleFollowDuration;

  /// 追加一行；同一帧内的多行合并为一次重建。
  void appendConsoleLine(String line) {
    if (!mounted) return;
    _pendingLines.add(line);
    _flushTimer ??= startSafeTimer(
      kOpenHandFramePeriodicTimerInterval,
      _flushPendingLines,
      onError: (error, stack) =>
          silentLog(consoleLogTag, '刷新控制台日志', error, stack),
    );
  }

  /// 丢弃缓冲与已落地的日志，用于重跑前重置；调用方自行包在 setState 里。
  void resetConsoleLog() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingLines.clear();
    logLines.clear();
  }

  void _flushPendingLines() {
    _flushTimer = null;
    if (!mounted || _pendingLines.isEmpty) {
      _pendingLines.clear();
      return;
    }
    final pending = _pendingLines.snapshot();
    _pendingLines.clear();
    setState(() => logLines.addAll(pending));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      logScrollGuard.followToBottom(
        logScrollController,
        animated: true,
        animationDuration: openHandMotionDuration(
          context,
          consoleFollowDuration,
        ),
      );
    });
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingLines.clear();
    logScrollController.dispose();
    super.dispose();
  }
}
