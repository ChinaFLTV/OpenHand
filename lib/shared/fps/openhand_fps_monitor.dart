import 'package:flutter/scheduler.dart';

/// 进程级 FPS 监视器（单例）。
///
/// 2026-05-18 — 节流自动模式需要"FPS<55 自动降速"的能力；UI 端也可用
/// 它来感知卡顿并主动降级。设计目标：
///   * 不依赖第三方包；
///   * 单例 + Ticker 0 成本即开即用；
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

  Ticker? _ticker;
  Duration _windowStart = Duration.zero;
  int _windowFrames = 0;

  /// 最近 1s 内观测到的 FPS（移动平均）。0 表示尚未采样到任何帧。
  double _recentFps = 0;
  double get recentFps => _recentFps;

  /// 启动监视器，如已启动则忽略。需要在 WidgetsFlutterBinding 初始化
  /// 之后调用，否则 Ticker 无法创建。
  void start() {
    if (_ticker != null) return;
    final t = Ticker(_onTick, debugLabel: 'OpenHandFpsMonitor');
    _ticker = t;
    _windowStart = Duration.zero;
    _windowFrames = 0;
    t.start();
  }

  void stop() {
    _ticker?.dispose();
    _ticker = null;
    _windowFrames = 0;
    _windowStart = Duration.zero;
  }

  void _onTick(Duration elapsed) {
    if (_windowStart == Duration.zero) {
      _windowStart = elapsed;
      _windowFrames = 1;
      return;
    }
    _windowFrames += 1;
    final delta = elapsed - _windowStart;
    if (delta >= const Duration(seconds: 1)) {
      // 用更稳的指数平滑做移动平均：alpha=0.5 让突发卡顿不会立刻把
      // 自动模式拽到极端低速，又能在持续掉帧时快速反应。
      final instantFps = _windowFrames * 1000000 / delta.inMicroseconds;
      _recentFps = _recentFps == 0
          ? instantFps
          : (_recentFps * 0.5 + instantFps * 0.5);
      _windowStart = elapsed;
      _windowFrames = 0;
    }
  }
}
