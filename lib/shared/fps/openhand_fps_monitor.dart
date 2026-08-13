import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';

/// 进程级 FPS 监视器（单例）。
///
/// 节流自动模式需要"FPS<55 自动降速"的能力；UI 端也可用
/// 它来感知卡顿并主动降级。设计目标：
///   * 不依赖第三方包；
///   * 被动采样真实产生的帧（[SchedulerBinding.addTimingsCallback]），
///     不强制引擎持续出帧——此前的常驻 Ticker 会让应用永远无法进入
///     idle，静止界面也以满帧率空转整条渲染管线，持续耗电并挤占
///     真实工作的帧预算；
///   * 1Hz 计算移动平均，避免 60fps 抖动导致频繁降速。
///
/// 使用方法：
/// ```
/// OpenHandFpsMonitor.instance.start();
/// final fps = OpenHandFpsMonitor.instance.recentFps;
/// ```
class OpenHandFpsMonitor {
  OpenHandFpsMonitor._();

  static final OpenHandFpsMonitor instance = OpenHandFpsMonitor._();

  /// 相邻帧间隔超过该阈值视为「空闲边界」而非掉帧：被动采样下应用静止时
  /// 没有帧产生，若把空闲间隙计入窗口，恢复渲染的第一帧会把 FPS 拉到
  /// 接近 0，误触发自动降速。
  static const int _idleGapMicroseconds = 300 * 1000;

  TimingsCallback? _timingsCallback;
  int? _windowStartMicroseconds;
  int? _lastFrameMicroseconds;
  int _windowFrames = 0;

  /// 最近一段活跃渲染期观测到的 FPS（移动平均）。0 表示尚未采样到任何帧；
  /// 应用空闲时保留最后一次活跃期的值。
  double _recentFps = 0;
  double get recentFps => _recentFps;

  /// 启动监视器，如已启动则忽略。需要在 WidgetsFlutterBinding 初始化
  /// 之后调用。
  void start() {
    if (_timingsCallback != null) return;
    _windowStartMicroseconds = null;
    _lastFrameMicroseconds = null;
    _windowFrames = 0;
    final callback = _onTimings;
    _timingsCallback = callback;
    SchedulerBinding.instance.addTimingsCallback(callback);
  }

  void stop() {
    final callback = _timingsCallback;
    if (callback != null) {
      SchedulerBinding.instance.removeTimingsCallback(callback);
    }
    _timingsCallback = null;
    _windowFrames = 0;
    _windowStartMicroseconds = null;
    _lastFrameMicroseconds = null;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final frameMicroseconds = timing.timestampInMicroseconds(
        FramePhase.rasterFinish,
      );
      final last = _lastFrameMicroseconds;
      _lastFrameMicroseconds = frameMicroseconds;
      if (last == null ||
          frameMicroseconds - last >= _idleGapMicroseconds ||
          _windowStartMicroseconds == null) {
        _windowStartMicroseconds = frameMicroseconds;
        _windowFrames = 1;
        continue;
      }
      _windowFrames += 1;
      final deltaMicroseconds = frameMicroseconds - _windowStartMicroseconds!;
      if (deltaMicroseconds >= Duration.microsecondsPerSecond) {
        // 用更稳的指数平滑做移动平均：alpha=0.5 让突发卡顿不会立刻把
        // 自动模式拽到极端低速，又能在持续掉帧时快速反应。
        final instantFps = _windowFrames * 1000000 / deltaMicroseconds;
        _recentFps = _recentFps == 0
            ? instantFps
            : (_recentFps * 0.5 + instantFps * 0.5);
        _windowStartMicroseconds = frameMicroseconds;
        _windowFrames = 0;
      }
    }
  }
}
