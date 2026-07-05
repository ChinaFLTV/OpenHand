// Streaming text reveal: time-driven fade bands for independently arriving
// deltas.
// Each delta gets its own fade window, so newer text can appear without
// restarting older fades. Reduced motion and very long text fall back to a
// plain child to avoid unnecessary GPU work.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'motion_preference.dart';

class StreamingTextReveal extends StatefulWidget {
  const StreamingTextReveal({
    super.key,
    required this.textLength,
    required this.streaming,
    required this.child,
    this.animateSize = true,
  });

  /// 当前已渲染文本长度。新增即触发尾部 fade。
  final int textLength;

  /// streaming==false 时停止入队，已有段继续完成后停 Ticker。
  final bool streaming;

  final Widget child;

  /// Whether this widget should animate its own height. Message/tool cards
  /// already wrapped in an outer AnimatedSize pass false to avoid competing
  /// height tweens while keeping the text reveal animation intact.
  final bool animateSize;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!openHandTickerMotionEnabled(context)) {
      _settleWithoutMotion();
    }
  }

  @override
  void didUpdateWidget(covariant StreamingTextReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!openHandTickerMotionEnabled(context)) {
      _settleWithoutMotion();
      return;
    }
    if (widget.textLength > _kRevealMaxLength) {
      _settleWithoutMotion();
      return;
    }

    if (widget.textLength > oldWidget.textLength) {
      final startMs = _ticker.isActive ? _nowMs : 0;
      if (!_ticker.isActive) _nowMs = 0;
      _segments.add(
        _FadeSegment(boundary: widget.textLength, startedAtMs: startMs),
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

  void _settleWithoutMotion() {
    _segments.clear();
    _stablePrefixLength = widget.textLength;
    if (_ticker.isActive) _ticker.stop();
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
    final motionEnabled = openHandTickerMotionEnabled(context);
    final total = widget.textLength;
    final revealEnabled = total <= _kRevealMaxLength;
    final hasActiveFade = _segments.isNotEmpty && total > 0;

    Widget body = widget.child;
    if (motionEnabled && revealEnabled && hasActiveFade) {
      body = _buildMask(total);
    }

    if (!widget.animateSize || !motionEnabled) return body;

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

    final stableFraction = (_stablePrefixLength.clamp(0, total) / total).clamp(
      0.0,
      1.0,
    );
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

typedef StreamingTextRevealBuilder =
    Widget Function(BuildContext context, String visibleText);

/// Text-driven streaming reveal.
///
/// The legacy [StreamingTextReveal] only fades the latest already-rendered
/// diff. This wrapper first stages the visible text by grapheme cluster, then
/// lets [StreamingTextReveal] fade each staged increment. Small deltas appear
/// character-by-character; large backlogs automatically catch up in bounded
/// batches so streaming cannot leave an unbounded animation queue behind.
class StreamingTextRevealText extends StatefulWidget {
  const StreamingTextRevealText({
    super.key,
    required this.text,
    required this.streaming,
    required this.builder,
    this.animateSize = true,
  });

  final String text;
  final bool streaming;
  final StreamingTextRevealBuilder builder;
  final bool animateSize;

  @override
  State<StreamingTextRevealText> createState() =>
      _StreamingTextRevealTextState();
}

class _StreamingTextRevealTextState extends State<StreamingTextRevealText>
    with SingleTickerProviderStateMixin {
  static const int _kRevealMaxLength = 32 * 1024;
  static const int _kSmallBacklogThreshold = 24;
  static const int _kMediumBacklogThreshold = 120;
  static const int _kLargeBacklogThreshold = 480;
  static const int _kMaxGraphemesPerTick = 24;
  static const int _kFrameBudgetMs = 16;
  static const int _kCatchUpFrameBudgetMs = 8;

  late final Ticker _ticker;
  List<int> _graphemeEnds = const <int>[];
  int _visibleGraphemes = 0;
  int _lastRevealMs = 0;

  int get _targetGraphemes => _graphemeEnds.length;
  bool get _bypassReveal =>
      !widget.streaming || widget.text.length > _kRevealMaxLength;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _rebuildGraphemeEnds();
    _visibleGraphemes = _bypassReveal ? _targetGraphemes : 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!openHandTickerMotionEnabled(context)) {
      _visibleGraphemes = _targetGraphemes;
      _stopTicker();
    } else {
      _startTickerIfNeeded();
    }
  }

  @override
  void didUpdateWidget(covariant StreamingTextRevealText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousText = oldWidget.text;
    _syncGraphemeEnds(previousText);
    if (_bypassReveal) {
      _visibleGraphemes = _targetGraphemes;
      _stopTicker();
      return;
    }
    if (!openHandTickerMotionEnabled(context)) {
      _visibleGraphemes = _targetGraphemes;
      _stopTicker();
      return;
    }
    if (widget.text.length < previousText.length) {
      _visibleGraphemes = _visibleGraphemes.clamp(0, _targetGraphemes);
    } else if (!widget.text.startsWith(previousText)) {
      _visibleGraphemes = 0;
    }
    _startTickerIfNeeded();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _rebuildGraphemeEnds() {
    if (widget.text.isEmpty) {
      _graphemeEnds = const <int>[];
      return;
    }
    var offset = 0;
    final ends = <int>[];
    for (final cluster in widget.text.characters) {
      offset += cluster.length;
      ends.add(offset);
    }
    _graphemeEnds = ends;
  }

  void _syncGraphemeEnds(String previousText) {
    final text = widget.text;
    if (text.isEmpty) {
      _graphemeEnds = const <int>[];
      return;
    }
    final appendOnly =
        text.startsWith(previousText) &&
        _isGraphemeBoundary(text, previousText.length) &&
        (_graphemeEnds.isEmpty
            ? previousText.isEmpty
            : _graphemeEnds.last == previousText.length);
    if (!appendOnly) {
      _rebuildGraphemeEnds();
      return;
    }
    if (text.length == previousText.length) {
      return;
    }
    final ends = _graphemeEnds.isEmpty ? <int>[] : _graphemeEnds;
    var offset = previousText.length;
    for (final cluster in text.substring(previousText.length).characters) {
      offset += cluster.length;
      ends.add(offset);
    }
    _graphemeEnds = ends;
  }

  void _startTickerIfNeeded() {
    if (mounted && !openHandTickerMotionEnabled(context)) return;
    if (_visibleGraphemes >= _targetGraphemes || _ticker.isActive) return;
    _lastRevealMs = 0;
    _ticker.start();
  }

  void _stopTicker() {
    if (_ticker.isActive) {
      _ticker.stop();
    }
    _lastRevealMs = 0;
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (_bypassReveal || _visibleGraphemes >= _targetGraphemes) {
      _stopTicker();
      return;
    }

    final backlog = _targetGraphemes - _visibleGraphemes;
    final frameBudgetMs = backlog > _kLargeBacklogThreshold
        ? _kCatchUpFrameBudgetMs
        : _kFrameBudgetMs;
    final nowMs = elapsed.inMilliseconds;
    if (nowMs - _lastRevealMs < frameBudgetMs) return;
    _lastRevealMs = nowMs;

    final step = _stepForBacklog(backlog);
    setState(() {
      _visibleGraphemes = _minInt(_targetGraphemes, _visibleGraphemes + step);
    });
    if (_visibleGraphemes >= _targetGraphemes) {
      _stopTicker();
    }
  }

  int _stepForBacklog(int backlog) {
    if (backlog <= _kSmallBacklogThreshold) return 1;
    if (backlog <= _kMediumBacklogThreshold) return 2;
    if (backlog <= _kLargeBacklogThreshold) return 6;
    return _kMaxGraphemesPerTick;
  }

  String _visibleText(bool motionEnabled) {
    if (!motionEnabled || _bypassReveal) return widget.text;
    if (_visibleGraphemes <= 0) return '';
    if (_visibleGraphemes >= _targetGraphemes) return widget.text;
    return widget.text.substring(0, _graphemeEnds[_visibleGraphemes - 1]);
  }

  @override
  Widget build(BuildContext context) {
    final motionEnabled = openHandTickerMotionEnabled(context);
    final visibleText = _visibleText(motionEnabled);
    if (!motionEnabled || _bypassReveal) {
      return widget.builder(context, visibleText);
    }
    return StreamingTextReveal(
      textLength: visibleText.length,
      streaming: widget.streaming,
      animateSize: widget.animateSize,
      child: widget.builder(context, visibleText),
    );
  }
}

int _minInt(int a, int b) => a < b ? a : b;

bool _isGraphemeBoundary(String text, int offset) {
  if (offset <= 0 || offset >= text.length) {
    return offset == 0 || offset == text.length;
  }
  var cursor = 0;
  for (final cluster in text.characters) {
    cursor += cluster.length;
    if (cursor >= offset) return cursor == offset;
  }
  return false;
}
