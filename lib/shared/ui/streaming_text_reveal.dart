// 2026-05-24 — 流式消息文本「精灵登场」reveal v2：时间驱动多 delta 级联。
//
// v1 用单一 AnimationController 驱动整条波前，新 delta 到达即 forward(from:0)
// 会强制刷新整条 ShaderMask gradient，导致前一批字符的 fade 被截断，肉眼
// 看到的就是「一刀切」式追加。v2 改为时间驱动：维护一支 (boundary, t0)
// 队列，每个 delta 独立计时，新 delta 进入只是「在尾部多一段渐变带」，
// 旧 delta 的 fade 继续完成。LinearGradient 多 stop 一次性表达整条级联。
//
// reduceMotion 与超长文本直接 passthrough，保持零 GPU 开销退路。

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class StreamingTextReveal extends StatefulWidget {
  const StreamingTextReveal({
    super.key,
    required this.textLength,
    required this.streaming,
    required this.child,
  });

  /// 当前已渲染文本长度。新增即触发尾部 fade。
  final int textLength;

  /// streaming==false 时停止入队，已有段继续完成后停 Ticker。
  final bool streaming;

  final Widget child;

  @override
  State<StreamingTextReveal> createState() => _StreamingTextRevealState();
}

class _FadeSegment {
  _FadeSegment({required this.boundary, required this.startedAtMs});

  /// 该 delta 截止时的累计字符数（即段尾位置，含）。
  final int boundary;

  /// 入队的 Ticker 相对毫秒时间戳。
  final int startedAtMs;
}

class _StreamingTextRevealState extends State<StreamingTextReveal>
    with SingleTickerProviderStateMixin {
  /// 单 delta fade-in 时长。Gemini 网页端实测约 450-600ms，
  /// 取 520ms：长到能看到 Q 弹「亮」起来，又不至于压住下一批的登场感。
  static const int _fadeMs = 520;
  static const Duration _heightDuration = Duration(milliseconds: 220);

  /// 超长文本停用 ShaderMask（避免对 GPU 合成层产生大开销）。
  static const int _kRevealMaxLength = 32 * 1024;

  /// 段队列上限：超出后丢弃最早段（其 alpha 早已=1，肉眼无差）。
  static const int _kMaxSegments = 24;

  final List<_FadeSegment> _segments = <_FadeSegment>[];
  late final Ticker _ticker;
  int _nowMs = 0;

  /// 初始挂载或截断后已有的稳定文本长度，永远 alpha=1。
  int _stablePrefixLength = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _stablePrefixLength = widget.textLength;
  }

  @override
  void didUpdateWidget(covariant StreamingTextReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.textLength > _kRevealMaxLength) {
      _segments.clear();
      _stablePrefixLength = widget.textLength;
      if (_ticker.isActive) _ticker.stop();
      return;
    }

    if (widget.textLength > oldWidget.textLength) {
      _segments.add(
        _FadeSegment(boundary: widget.textLength, startedAtMs: _nowMs),
      );
      while (_segments.length > _kMaxSegments) {
        // 丢弃最早段，把它视作稳定前缀。
        _stablePrefixLength = _segments.first.boundary;
        _segments.removeAt(0);
      }
      if (!_ticker.isActive) {
        _ticker.start();
      }
    } else if (widget.textLength < oldWidget.textLength) {
      _segments.clear();
      _stablePrefixLength = widget.textLength;
      if (_ticker.isActive) _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    _nowMs = elapsed.inMilliseconds;
    // 清理已完成段：并入稳定前缀。
    while (_segments.isNotEmpty &&
        _nowMs - _segments.first.startedAtMs >= _fadeMs) {
      _stablePrefixLength = _segments.first.boundary;
      _segments.removeAt(0);
    }
    if (_segments.isEmpty) {
      _ticker.stop();
    }
    if (mounted) {
      // ignore: invalid_use_of_protected_member
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double _alphaForSegment(_FadeSegment seg) {
    final dt = (_nowMs - seg.startedAtMs).clamp(0, _fadeMs);
    final t = dt / _fadeMs;
    // easeOutCubic：开头亮起快、尾部柔和落位。
    final eased = 1 - (1 - t) * (1 - t) * (1 - t);
    return eased.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final disable = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final total = widget.textLength;
    final revealEnabled = total <= _kRevealMaxLength;
    final hasActiveFade = _segments.isNotEmpty && total > 0;

    Widget body = widget.child;
    if (!disable && revealEnabled && hasActiveFade) {
      body = _buildMask(total);
    }

    return AnimatedSize(
      duration: _heightDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: body,
    );
  }

  /// 把 (_stablePrefixLength, segments[]) 转成一条 LinearGradient。
  ///
  /// 段 i 覆盖 (prevBoundary, segments[i].boundary]，
  /// 段头 alpha = 上一段尾 alpha（连续），段尾 alpha = ease(now - t_i)。
  /// stops 内 LinearGradient 自动线性插值，呈现「head→tail」级联：
  /// 段头紧跟稳定区，已 opaque；段尾刚到达，alpha=0；中间字符按比例 lerp。
  Widget _buildMask(int total) {
    final stops = <double>[];
    final colors = <Color>[];

    final stableFraction = (_stablePrefixLength.clamp(0, total) / total)
        .clamp(0.0, 1.0);
    stops.add(0.0);
    colors.add(Colors.white);
    if (stableFraction > 0.0) {
      stops.add(stableFraction);
      colors.add(Colors.white);
    }

    double prevAlpha = 1.0;
    double prevFraction = stableFraction;
    for (final seg in _segments) {
      final boundary = seg.boundary.clamp(0, total);
      final fraction = (boundary / total).clamp(0.0, 1.0);
      final endAlpha = _alphaForSegment(seg);
      if (fraction <= prevFraction + 1e-5) {
        // 极小段：跳过 stop 插入，仅更新 prevAlpha 让下一段继承。
        prevAlpha = endAlpha;
        continue;
      }
      stops.add(fraction);
      colors.add(Colors.white.withValues(alpha: endAlpha));
      prevFraction = fraction;
      prevAlpha = endAlpha;
    }
    // 末端补齐到 1.0（最后一段已经覆盖到 total，理论上 prevFraction==1.0；
    // 但 clamp/精度误差可能差几位）。
    if (prevFraction < 1.0 - 1e-5) {
      stops.add(1.0);
      colors.add(Colors.white.withValues(alpha: prevAlpha));
    }

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: stops,
        colors: colors,
      ).createShader(bounds),
      child: widget.child,
    );
  }
}
