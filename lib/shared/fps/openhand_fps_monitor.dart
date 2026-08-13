import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';

/// 进程级帧健康监视器（单例）。
///
/// 节流自动模式需要"设备卡顿时自动降速"的能力；UI 端也可用它来感知
/// 卡顿并主动降级。设计目标：
///   * 不依赖第三方包；
///   * 被动采样真实产生的帧（[SchedulerBinding.addTimingsCallback]），
///     不强制引擎持续出帧——此前的常驻 Ticker 会让应用永远无法进入
///     idle，静止界面也以满帧率空转整条渲染管线；
///   * 被动采样下「帧产出率 ≠ 设备能力」：节流流式约 12.5 帧/秒也完全
///     健康。降速决策因此只看帧耗时——统计活跃窗口内超预算帧占比
///     （jank ratio），而不是把稀疏渲染误判为卡顿；
///   * 窗口结果带有效期：空闲期不产帧，陈旧值过期归零，避免用旧状态
///     误导决策与展示。
///
/// 使用方法：
/// ```
/// OpenHandFpsMonitor.instance.start();
/// final fps = OpenHandFpsMonitor.instance.recentFps;          // 0 = 空闲/无数据
/// final busy = OpenHandFpsMonitor.instance.isStrugglingRecently;
/// ```
class OpenHandFpsMonitor {
  OpenHandFpsMonitor._();

  static final OpenHandFpsMonitor instance = OpenHandFpsMonitor._();

  /// 相邻帧间隔超过该阈值视为「空闲边界」而非掉帧：被动采样下应用静止时
  /// 没有帧产生，若把空闲间隙计入窗口，恢复渲染的第一帧会把统计拉偏。
  static const int _idleGapMicroseconds = 300 * 1000;

  /// 单帧总耗时（build+raster 跨度）超过该值计为卡顿帧，约等于在 60Hz
  /// 下连丢 2 个 vsync；与刷新率无关的保守阈值，120Hz 设备同样适用。
  static const int _jankFrameThresholdMicroseconds = 32 * 1000;

  /// 卡顿帧占比超过该值判定为「设备吃紧」。
  static const double _strugglingJankRatio = 0.25;

  /// 最近窗口的有效期：超过后视为无数据（空闲），[recentFps] 归零、
  /// [isStrugglingRecently] 归 false。
  static const Duration _windowStaleAfter = Duration(seconds: 2);

  TimingsCallback? _timingsCallback;
  int? _windowStartMicroseconds;
  int? _lastFrameMicroseconds;
  int _windowFrames = 0;
  int _windowJankFrames = 0;
  double _recentFps = 0;
  double _recentJankRatio = 0;
  final Stopwatch _sinceLastWindow = Stopwatch();

  bool get _hasFreshWindow =>
      _sinceLastWindow.isRunning &&
      _sinceLastWindow.elapsed < _windowStaleAfter;

  /// 最近一段活跃渲染期观测到的帧率（移动平均）。0 表示当前空闲或尚未
  /// 采样到完整窗口；被动采样下该值反映"实际产出"而非设备能力，不应
  /// 单独用于降速决策。
  double get recentFps => _hasFreshWindow ? _recentFps : 0;

  /// 最近活跃渲染期是否处于卡顿状态（超预算帧占比过高且数据未过期）。
  /// 节流自动模式据此降速。
  bool get isStrugglingRecently =>
      _hasFreshWindow && _recentJankRatio >= _strugglingJankRatio;

  /// 启动监视器，如已启动则忽略。需要在 WidgetsFlutterBinding 初始化
  /// 之后调用。
  void start() {
    if (_timingsCallback != null) return;
    _resetWindow();
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
    _resetWindow();
    _sinceLastWindow
      ..stop()
      ..reset();
  }

  void _resetWindow() {
    _windowStartMicroseconds = null;
    _lastFrameMicroseconds = null;
    _windowFrames = 0;
    _windowJankFrames = 0;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final frameMicroseconds = timing.timestampInMicroseconds(
        FramePhase.rasterFinish,
      );
      final last = _lastFrameMicroseconds;
      _lastFrameMicroseconds = frameMicroseconds;
      final isJank =
          timing.totalSpan.inMicroseconds >= _jankFrameThresholdMicroseconds;
      if (last == null ||
          frameMicroseconds - last >= _idleGapMicroseconds ||
          _windowStartMicroseconds == null) {
        _windowStartMicroseconds = frameMicroseconds;
        _windowFrames = 1;
        _windowJankFrames = isJank ? 1 : 0;
        continue;
      }
      _windowFrames += 1;
      if (isJank) _windowJankFrames += 1;
      final deltaMicroseconds = frameMicroseconds - _windowStartMicroseconds!;
      if (deltaMicroseconds >= Duration.microsecondsPerSecond) {
        // 用更稳的指数平滑做移动平均：alpha=0.5 让突发卡顿不会立刻把
        // 自动模式拽到极端低速，又能在持续掉帧时快速反应。
        final instantFps = _windowFrames * 1000000 / deltaMicroseconds;
        _recentFps = _recentFps == 0
            ? instantFps
            : (_recentFps * 0.5 + instantFps * 0.5);
        _recentJankRatio = _windowFrames <= 0
            ? 0
            : _windowJankFrames / _windowFrames;
        _sinceLastWindow
          ..reset()
          ..start();
        _windowStartMicroseconds = frameMicroseconds;
        _windowFrames = 0;
        _windowJankFrames = 0;
      }
    }
  }
}
