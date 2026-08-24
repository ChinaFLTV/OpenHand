import 'dart:async';

import 'package:flutter/material.dart';

import '../util/timer_safety.dart';
import 'bounded_animation.dart';
import 'collision_safe_animated_switcher.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'rolling_text.dart';

const Duration kOpenHandLiveValueDuration = kOpenHandMotion360;
const int kOpenHandLiveValueRollerMaxChars = 72;
const String kOpenHandLiveValueEmpty = '-';
const double kOpenHandLiveStatusDotSize = 8;
const double kOpenHandLiveStatusDotPulseScale = 1.28;
const double kOpenHandLiveStatusDotMinOpacity = 0.42;
const String kOpenHandLiveConsoleMarker = '➜';
const String kOpenHandLiveConsoleArrowMarker = '→';
const Duration kOpenHandLiveClockInterval = Duration(seconds: 1);

/// 短指标串走字符滚轮；URL / 长文案走整段交叉淡入，避免 IP 与路径被拆成滚轮。
bool openHandLiveValuePrefersRoller(String text) {
  if (text.isEmpty || text.length > kOpenHandLiveValueRollerMaxChars) {
    return false;
  }
  if (text.contains('://')) return false;
  for (final code in text.codeUnits) {
    if (code >= 0x30 && code <= 0x39) return true;
  }
  return false;
}

Alignment _liveValueAlignment(TextAlign? textAlign) {
  return switch (textAlign) {
    TextAlign.right || TextAlign.end => Alignment.centerRight,
    TextAlign.center => Alignment.center,
    _ => Alignment.centerLeft,
  };
}

/// 实时文案：数字混排用 Q 弹滚轮，状态短语用回弹交叉淡入。
class OpenHandLiveValue extends StatelessWidget {
  const OpenHandLiveValue(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
    this.selectable = false,
    this.placeholder = kOpenHandLiveValueEmpty,
    this.duration = kOpenHandLiveValueDuration,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;
  final bool selectable;
  final String placeholder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final display = text.trim().isEmpty ? placeholder : text;
    final resolvedStyle = (style ?? DefaultTextStyle.of(context).style)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final motionDuration = openHandMotionDuration(context, duration);
    final alignment = _liveValueAlignment(textAlign);
    final prefersRoller = openHandLiveValuePrefersRoller(display);
    Widget child;
    if (motionDuration <= Duration.zero) {
      child = _staticText(display, resolvedStyle);
    } else if (prefersRoller) {
      final roller = RollingText(
        text: display,
        style: resolvedStyle,
        duration: motionDuration,
      );
      child = overflow == null
          ? roller
          : ClipRect(
              child: Align(alignment: alignment, child: roller),
            );
    } else {
      child = AnimatedSwitcher(
        duration: motionDuration,
        switchInCurve: kOpenHandSwitchInCurve,
        switchOutCurve: kOpenHandSwitchOutCurve,
        layoutBuilder: (currentChild, previousChildren) {
          return buildCollisionSafeAnimatedSwitcherLayout(
            currentChild,
            previousChildren,
            alignment: alignment,
          );
        },
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
        child: KeyedSubtree(
          key: ValueKey<String>(display),
          child: _staticText(display, resolvedStyle),
        ),
      );
    }
    if (prefersRoller &&
        overflow == null &&
        textAlign != null &&
        textAlign != TextAlign.left) {
      child = Align(alignment: alignment, child: child);
    }
    if (!selectable) return child;
    return SelectionArea(child: child);
  }

  Widget _staticText(String display, TextStyle style) {
    return Text(
      display,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap,
      style: style,
    );
  }
}

/// 仅刷新时长文案，避免整页运维弹窗每秒重建。
class OpenHandLiveDuration extends StatefulWidget {
  const OpenHandLiveDuration({
    super.key,
    required this.startedAt,
    required this.running,
    required this.format,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final DateTime? startedAt;
  final bool running;
  final String Function(Duration elapsed) format;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<OpenHandLiveDuration> createState() => _OpenHandLiveDurationState();
}

class _OpenHandLiveDurationState extends State<OpenHandLiveDuration> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant OpenHandLiveDuration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running ||
        oldWidget.startedAt != widget.startedAt) {
      _syncClock();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _syncClock() {
    final shouldTick = widget.running && widget.startedAt != null;
    if (!shouldTick) {
      _clock?.cancel();
      _clock = null;
      return;
    }
    if (_clock != null) return;
    _clock = startNonOverlappingPeriodicTimer(kOpenHandLiveClockInterval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.startedAt;
    final elapsed = !widget.running || start == null
        ? Duration.zero
        : DateTime.now().difference(start);
    return OpenHandLiveValue(
      widget.format(elapsed.isNegative ? Duration.zero : elapsed),
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}

/// 运维终端一行：提示符静态，命令与明细走实时动效。
class OpenHandLiveConsoleLine extends StatelessWidget {
  const OpenHandLiveConsoleLine({
    super.key,
    this.marker = kOpenHandLiveConsoleMarker,
    required this.prompt,
    this.command = '',
    this.detail = '',
    required this.promptColor,
    this.markerColor,
    this.commandColor,
    this.detailColor,
  });

  final String marker;
  final String prompt;
  final String command;
  final String detail;
  final Color promptColor;
  final Color? markerColor;
  final Color? commandColor;
  final Color? detailColor;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final commandStyle = base.copyWith(
      color: commandColor,
      fontWeight: FontWeight.w900,
    );
    final detailStyle = base.copyWith(
      color: detailColor ?? Colors.white.withValues(alpha: 0.72),
      fontWeight: FontWeight.w700,
    );
    final detailText = detail.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$marker ',
                style: base.copyWith(
                  color: markerColor ?? promptColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(
                text: '$prompt ',
                style: base.copyWith(
                  color: promptColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (command.isNotEmpty)
          detailText.isEmpty
              ? Expanded(
                  child: OpenHandLiveValue(
                    command,
                    style: commandStyle,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                )
              : OpenHandLiveValue(
                  command,
                  style: commandStyle,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
        if (detailText.isNotEmpty) ...[
          if (command.isNotEmpty) Text('  ', style: detailStyle),
          Expanded(
            child: OpenHandLiveValue(
              detailText,
              style: detailStyle,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
          ),
        ],
      ],
    );
  }
}

/// 运行态呼吸圆点；关闭动效或非运行时退回静态圆点。
class OpenHandLiveStatusDot extends StatefulWidget {
  const OpenHandLiveStatusDot({
    super.key,
    required this.color,
    this.pulse = false,
    this.size = kOpenHandLiveStatusDotSize,
  });

  final Color color;
  final bool pulse;
  final double size;

  @override
  State<OpenHandLiveStatusDot> createState() => _OpenHandLiveStatusDotState();
}

class _OpenHandLiveStatusDotState extends State<OpenHandLiveStatusDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant OpenHandLiveStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulse != widget.pulse) _syncPulse();
  }

  void _syncPulse() {
    final shouldPulse = widget.pulse && openHandTickerMotionEnabled(context);
    if (!shouldPulse) {
      _ctrl?.stop();
      return;
    }
    final ctrl = _ctrl ??= AnimationController(
      vsync: this,
      duration: kOpenHandMotion1400,
    );
    if (!ctrl.isAnimating) ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size.isFinite && widget.size > 0
        ? widget.size
        : kOpenHandLiveStatusDotSize;
    final dot = DecoratedBox(
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    final ctrl = _ctrl;
    if (!widget.pulse ||
        ctrl == null ||
        !openHandTickerMotionEnabled(context)) {
      return SizedBox(width: size, height: size, child: dot);
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(ctrl.value);
          final scale = 1.0 + (kOpenHandLiveStatusDotPulseScale - 1.0) * t;
          final opacity = 1.0 - (1.0 - kOpenHandLiveStatusDotMinOpacity) * t;
          return SizedBox(
            width: size,
            height: size,
            child: Transform.scale(
              scale: scale,
              filterQuality: FilterQuality.low,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.color.withValues(
                    alpha: opacity.clamp(0.0, 1.0),
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
