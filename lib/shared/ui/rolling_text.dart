// 数字滚轮：只翻连续数字位；个位先动；变大向上、变小向下。
// 高频更新合并到一次翻牌，避免每帧 Opacity/OverflowBox 把主线程打满。
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'bounded_animation.dart';
import 'collision_safe_animated_switcher.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';

const Curve kOpenHandDigitRollOutCurve = Cubic(0.2, 0, 0, 1);
const int kOpenHandDigitRollStaggerMs = 28;
const int kOpenHandDigitRollStaggerMaxSlots = 5;
const int kOpenHandDigitRollMaxSlots = 18;
const int kOpenHandDigitRollGlyphCacheLimit = 48;
const double kOpenHandDigitRollWindow = 0.2;
const double kOpenHandDigitRollOvershoot = 0.08;
const double kOpenHandDigitRollPeakT = 0.56;
const double kOpenHandDigitRollPunch = 0.04;
const double kOpenHandDigitRollFromScale = 0.96;

final Map<int, _GlyphMetrics> _glyphMetricsCache = <int, _GlyphMetrics>{};

class RollingText extends StatelessWidget {
  const RollingText({
    super.key,
    required this.text,
    required this.style,
    this.duration = kOpenHandMotion360,
  });

  final String text;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final resolvedDuration = openHandMotionDuration(context, duration);
    final segments = _segmentRollingText(text);
    final metrics = _measureRollingGlyphs(
      resolvedStyle,
      MediaQuery.textScalerOf(context),
    );
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < segments.length; i++)
            segments[i].digits
                ? _RollingDigitGroup(
                    key: ValueKey<int>(i),
                    value: segments[i].value,
                    style: resolvedStyle,
                    duration: resolvedDuration,
                    metrics: metrics,
                  )
                : _RollingStaticRun(
                    key: ValueKey<int>(i),
                    value: segments[i].value,
                    style: resolvedStyle,
                    duration: resolvedDuration,
                  ),
        ],
      ),
    );
  }
}

class _RollingSegment {
  const _RollingSegment({required this.digits, required this.value});

  final bool digits;
  final String value;
}

bool _isRollingDigitChar(String ch) {
  if (ch.isEmpty) return false;
  final code = ch.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) || code == 0x2c || code == 0x2e;
}

bool _isRollingSeparator(String ch) => ch == '.' || ch == ',';

List<_RollingSegment> _segmentRollingText(String text) {
  if (text.isEmpty) return const [];
  final segments = <_RollingSegment>[];
  final buffer = StringBuffer();
  var digits = _isRollingDigitChar(text[0]);
  for (var i = 0; i < text.length; i += 1) {
    final ch = text[i];
    final isDigit = _isRollingDigitChar(ch);
    if (isDigit != digits && buffer.isNotEmpty) {
      segments.add(_RollingSegment(digits: digits, value: buffer.toString()));
      buffer.clear();
      digits = isDigit;
    }
    buffer.write(ch);
  }
  segments.add(_RollingSegment(digits: digits, value: buffer.toString()));
  return segments;
}

int _digitRollDirection(String from, String to) {
  final a = num.tryParse(from.replaceAll(',', ''));
  final b = num.tryParse(to.replaceAll(',', ''));
  if (a == null || b == null || b == a) return 1;
  return b > a ? 1 : -1;
}

String _charFromRight(String value, int fromRight) {
  final index = value.length - 1 - fromRight;
  if (index < 0 || index >= value.length) return '';
  return value[index];
}

class _GlyphMetrics {
  const _GlyphMetrics({
    required this.digitWidth,
    required this.dotWidth,
    required this.commaWidth,
    required this.height,
  });

  final double digitWidth;
  final double dotWidth;
  final double commaWidth;
  final double height;

  double widthOf(String ch) {
    if (ch == '.') return dotWidth;
    if (ch == ',') return commaWidth;
    if (ch.isEmpty) return 0;
    return digitWidth;
  }
}

_GlyphMetrics _measureRollingGlyphs(TextStyle style, TextScaler scaler) {
  final key = Object.hash(
    style.fontSize,
    style.fontFamily,
    style.fontWeight,
    style.fontStyle,
    style.height,
    style.letterSpacing,
    scaler.scale(100),
  );
  final cached = _glyphMetricsCache[key];
  if (cached != null) return cached;
  final fallback = style.fontSize ?? 14;
  ({double width, double height}) paint(String ch) {
    final painter = TextPainter(
      text: TextSpan(text: ch, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final size = (width: painter.width, height: painter.height);
    painter.dispose();
    return size;
  }

  final zero = paint('0');
  final dot = paint('.');
  final comma = paint(',');
  final metrics = (zero.width <= 0 || zero.height <= 0)
      ? _GlyphMetrics(
          digitWidth: fallback * 0.62,
          dotWidth: fallback * 0.32,
          commaWidth: fallback * 0.32,
          height: fallback * (style.height ?? 1.2),
        )
      : _GlyphMetrics(
          digitWidth: zero.width,
          dotWidth: dot.width <= 0 ? zero.width * 0.45 : dot.width,
          commaWidth: comma.width <= 0 ? zero.width * 0.45 : comma.width,
          height: zero.height,
        );
  if (_glyphMetricsCache.length >= kOpenHandDigitRollGlyphCacheLimit) {
    _glyphMetricsCache.clear();
  }
  _glyphMetricsCache[key] = metrics;
  return metrics;
}

double _staggerLocalT(double parentT, double start, double end) {
  final t = parentT.isFinite ? parentT : 1.0;
  if (end <= start) return t >= end ? 1.0 : 0.0;
  if (t <= start) return 0.0;
  if (t >= end) return 1.0;
  return ((t - start) / (end - start)).clamp(0.0, 1.0);
}

({
  double inY,
  double outY,
  double inScale,
  double outScale,
  double inOpacity,
  double outOpacity,
})
_digitRollFrame(double rawT, double height, int direction) {
  final t = rawT.isFinite ? rawT.clamp(0.0, 1.0) : 1.0;
  final peak = kOpenHandDigitRollPeakT.clamp(0.2, 0.85);
  final h = height.isFinite && height > 0 ? height : 0.0;
  final dir = direction >= 0 ? 1.0 : -1.0;

  late final double inShift;
  late final double inScale;
  if (t <= peak) {
    final u = kOpenHandSwitchInCurve.transform((t / peak).clamp(0.0, 1.0));
    inShift = lerpDouble(1.0, -kOpenHandDigitRollOvershoot, u) ?? 0;
    inScale =
        lerpDouble(
          kOpenHandDigitRollFromScale,
          1.0 + kOpenHandDigitRollPunch,
          u,
        ) ??
        1;
  } else {
    final u = Curves.easeInOutCubic.transform(
      ((t - peak) / (1.0 - peak)).clamp(0.0, 1.0),
    );
    inShift = lerpDouble(-kOpenHandDigitRollOvershoot, 0.0, u) ?? 0;
    inScale = lerpDouble(1.0 + kOpenHandDigitRollPunch, 1.0, u) ?? 1;
  }

  final outU = kOpenHandDigitRollOutCurve.transform(t);
  return (
    inY: h * inShift * dir,
    outY:
        h *
        (lerpDouble(0.0, -(1.0 + kOpenHandDigitRollOvershoot), outU) ?? 0) *
        dir,
    inScale: inScale.isFinite && inScale > 0 ? inScale : 1.0,
    outScale: (lerpDouble(1.0, kOpenHandDigitRollFromScale, outU) ?? 1).clamp(
      0.5,
      2.0,
    ),
    inOpacity: const Interval(0.0, 0.36, curve: Curves.easeOut).transform(t),
    outOpacity:
        1.0 - const Interval(0.1, 0.78, curve: Curves.easeIn).transform(t),
  );
}

class _RollingStaticRun extends StatelessWidget {
  const _RollingStaticRun({
    super.key,
    required this.value,
    required this.style,
    required this.duration,
  });

  final String value;
  final TextStyle style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      value,
      key: ValueKey<String>(value),
      style: style,
      maxLines: 1,
      softWrap: false,
    );
    if (duration <= Duration.zero) return child;
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: kOpenHandSwitchInCurve,
      switchOutCurve: kOpenHandSwitchOutCurve,
      layoutBuilder: buildCollisionSafeAnimatedSwitcherLayout,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: openHandBoundedCurveAnimation(
            parent: animation,
            curve: kOpenHandSwitchInCurve,
            reverseCurve: kOpenHandSwitchOutCurve,
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}

class _RollingDigitGroup extends StatefulWidget {
  const _RollingDigitGroup({
    super.key,
    required this.value,
    required this.style,
    required this.duration,
    required this.metrics,
  });

  final String value;
  final TextStyle style;
  final Duration duration;
  final _GlyphMetrics metrics;

  @override
  State<_RollingDigitGroup> createState() => _RollingDigitGroupState();
}

class _RollingDigitGroupState extends State<_RollingDigitGroup>
    with SingleTickerProviderStateMixin {
  late String _current = widget.value;
  late String _previous = widget.value;
  String? _pending;
  int _direction = 1;
  bool _rolling = false;
  AnimationController? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!openHandTickerMotionEnabled(context)) {
      _pending = null;
      _stop(reset: true);
    }
  }

  @override
  void didUpdateWidget(covariant _RollingDigitGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.value;
    if (next == _current && _pending == null) return;
    if (_rolling) {
      _pending = next;
      return;
    }
    _commit(next);
  }

  @override
  void dispose() {
    _ctrl?.removeStatusListener(_onStatus);
    _ctrl?.dispose();
    _ctrl = null;
    super.dispose();
  }

  void _commit(String next) {
    if (next == _current) {
      _pending = null;
      return;
    }
    _pending = null;
    _previous = _current;
    _current = next;
    _direction = _digitRollDirection(_previous, _current);
    if (widget.duration <= Duration.zero ||
        !openHandTickerMotionEnabled(context) ||
        math.max(_previous.length, _current.length) >
            kOpenHandDigitRollMaxSlots) {
      _stop(reset: true);
      return;
    }
    _play();
  }

  void _play() {
    final extraSlots = math.min(
      _changingMaxFromRight(),
      kOpenHandDigitRollStaggerMaxSlots,
    );
    final duration =
        widget.duration +
        Duration(milliseconds: kOpenHandDigitRollStaggerMs * extraSlots);
    if (duration <= Duration.zero) {
      _stop(reset: true);
      return;
    }
    _rolling = true;
    final ctrl = _ctrl ??= AnimationController(vsync: this, duration: duration);
    ctrl.duration = duration;
    ctrl.removeStatusListener(_onStatus);
    ctrl.addStatusListener(_onStatus);
    ctrl.forward(from: 0);
  }

  int _changingMaxFromRight() {
    final slotCount = math.max(_previous.length, _current.length);
    var maxFromRight = 0;
    for (var fromRight = 0; fromRight < slotCount; fromRight += 1) {
      if (_charFromRight(_previous, fromRight) ==
          _charFromRight(_current, fromRight)) {
        continue;
      }
      maxFromRight = fromRight;
    }
    return maxFromRight;
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final pending = _pending;
    _pending = null;
    if (pending != null && pending != _current) {
      _previous = _current;
      _current = pending;
      _direction = _digitRollDirection(_previous, _current);
      _play();
      setState(() {});
      return;
    }
    _stop(reset: true, notify: true);
  }

  void _stop({required bool reset, bool notify = false}) {
    _rolling = false;
    final ctrl = _ctrl;
    if (ctrl != null) {
      ctrl.removeStatusListener(_onStatus);
      if (ctrl.isAnimating) ctrl.stop();
    }
    if (reset) _previous = _current;
    if (notify && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    final motion =
        _rolling && ctrl != null && openHandTickerMotionEnabled(context);
    final slotCount = math.max(_previous.length, _current.length);
    final totalMs = ctrl?.duration?.inMilliseconds ?? 0;
    final rollMs = widget.duration.inMilliseconds;
    return RepaintBoundary(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var fromRight = slotCount - 1; fromRight >= 0; fromRight--)
            _RollingSlot(
              previous: _charFromRight(_previous, fromRight),
              current: _charFromRight(_current, fromRight),
              style: widget.style,
              metrics: widget.metrics,
              direction: _direction,
              animation: motion ? ctrl : null,
              staggerStart: _staggerStart(fromRight, totalMs, rollMs),
              staggerEnd: _staggerEnd(fromRight, totalMs, rollMs),
            ),
        ],
      ),
    );
  }

  double _staggerStart(int fromRight, int totalMs, int rollMs) {
    if (totalMs <= 0 || rollMs <= 0) return 0;
    final delayMs =
        math.min(fromRight, kOpenHandDigitRollStaggerMaxSlots) *
        kOpenHandDigitRollStaggerMs;
    return (delayMs / totalMs).clamp(0.0, 0.99);
  }

  double _staggerEnd(int fromRight, int totalMs, int rollMs) {
    if (totalMs <= 0 || rollMs <= 0) return 1;
    final delayMs =
        math.min(fromRight, kOpenHandDigitRollStaggerMaxSlots) *
        kOpenHandDigitRollStaggerMs;
    final start = (delayMs / totalMs).clamp(0.0, 0.99);
    return ((delayMs + rollMs) / totalMs).clamp(start + 0.01, 1.0);
  }
}

class _RollingSlot extends StatelessWidget {
  const _RollingSlot({
    required this.previous,
    required this.current,
    required this.style,
    required this.metrics,
    required this.direction,
    required this.animation,
    required this.staggerStart,
    required this.staggerEnd,
  });

  final String previous;
  final String current;
  final TextStyle style;
  final _GlyphMetrics metrics;
  final int direction;
  final Animation<double>? animation;
  final double staggerStart;
  final double staggerEnd;

  @override
  Widget build(BuildContext context) {
    final display = current.isEmpty ? previous : current;
    final width = metrics.widthOf(display);
    if (width <= 0) return const SizedBox.shrink();
    if (animation == null || previous == current) {
      return SizedBox(
        width: width,
        height: metrics.height,
        child: Center(
          child: Text(display, style: style, maxLines: 1, softWrap: false),
        ),
      );
    }
    final extra = metrics.height * kOpenHandDigitRollWindow;
    final fallbackColor =
        style.color ?? DefaultTextStyle.of(context).style.color;
    return SizedBox(
      width: width,
      height: metrics.height,
      child: ClipRect(
        clipper: _RollingSlotClipper(extra),
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: animation!,
            builder: (context, _) {
              final t = _staggerLocalT(
                animation!.value,
                staggerStart,
                staggerEnd,
              );
              final fadeOnly =
                  _isRollingSeparator(previous) || _isRollingSeparator(current);
              final frame = fadeOnly
                  ? (
                      inY: 0.0,
                      outY: 0.0,
                      inScale: 1.0,
                      outScale: 1.0,
                      inOpacity: t,
                      outOpacity: 1.0 - t,
                    )
                  : _digitRollFrame(t, metrics.height, direction);
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  if (previous.isNotEmpty)
                    _rollLayer(
                      text: previous,
                      y: frame.outY,
                      scale: frame.outScale,
                      opacity: frame.outOpacity,
                      color: fallbackColor,
                    ),
                  if (current.isNotEmpty)
                    _rollLayer(
                      text: current,
                      y: frame.inY,
                      scale: frame.inScale,
                      opacity: frame.inOpacity,
                      color: fallbackColor,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _rollLayer({
    required String text,
    required double y,
    required double scale,
    required double opacity,
    required Color? color,
  }) {
    final dy = y.isFinite ? y : 0.0;
    final s = scale.isFinite && scale > 0 ? scale : 1.0;
    final a = opacity.isFinite ? opacity.clamp(0.0, 1.0) : 1.0;
    final painted = color == null
        ? style
        : style.copyWith(color: color.withValues(alpha: color.a * a));
    return Transform(
      alignment: Alignment.center,
      filterQuality: FilterQuality.low,
      transform: Matrix4.identity()
        ..translateByDouble(0.0, dy, 0.0, 1.0)
        ..scaleByDouble(s, s, 1.0, 1.0),
      child: Text(text, style: painted, maxLines: 1, softWrap: false),
    );
  }
}

class _RollingSlotClipper extends CustomClipper<Rect> {
  const _RollingSlotClipper(this.extra);

  final double extra;

  @override
  Rect getClip(Size size) {
    final pad = extra.isFinite && extra > 0 ? extra : 0.0;
    return Rect.fromLTRB(0, -pad, size.width, size.height + pad);
  }

  @override
  bool shouldReclip(covariant _RollingSlotClipper oldClipper) {
    return extra != oldClipper.extra;
  }
}
