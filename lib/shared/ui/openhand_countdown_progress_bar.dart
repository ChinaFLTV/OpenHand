import 'package:flutter/material.dart';

import '../util/localized_text.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';

String formatOpenHandAutoRejectCountdown(
  BuildContext context,
  Duration remaining,
) {
  final seconds = remaining.inSeconds;
  if (seconds <= 0) {
    return openHandLocalizedText(context, zh: '即将超时', en: 'Expiring now');
  }
  if (seconds < 60) {
    return openHandLocalizedText(
      context,
      zh: '${seconds}s 后自动拒绝',
      en: 'Auto-reject in ${seconds}s',
    );
  }
  final minutes = seconds ~/ 60;
  final tail = seconds % 60;
  return openHandLocalizedText(
    context,
    zh: '${minutes}m ${tail}s 后自动拒绝',
    en: 'Auto-reject in ${minutes}m ${tail}s',
  );
}

class OpenHandCountdownProgressBar extends StatefulWidget {
  const OpenHandCountdownProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 8,
    this.animationDuration = const Duration(milliseconds: 760),
    this.semanticLabel,
  });

  final double value;
  final Color? color;
  final double height;
  final Duration animationDuration;
  final String? semanticLabel;

  @override
  State<OpenHandCountdownProgressBar> createState() =>
      _OpenHandCountdownProgressBarState();
}

class _OpenHandCountdownProgressBarState
    extends State<OpenHandCountdownProgressBar> {
  double _begin = 0;
  double _end = 0;

  @override
  void initState() {
    super.initState();
    final initial = _normalizedValue(widget.value);
    _begin = initial;
    _end = initial;
  }

  @override
  void didUpdateWidget(covariant OpenHandCountdownProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _normalizedValue(widget.value);
    if (next == _end) return;
    _begin = _end;
    _end = next;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = widget.color ?? cs.primary;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _begin, end: _end),
      duration: openHandMotionDuration(context, widget.animationDuration),
      curve: kOpenHandSwitchInCurve,
      builder: (context, value, _) {
        final progress = _normalizedValue(value);
        return Semantics(
          label: widget.semanticLabel,
          value: '${(progress * 100).round()}%',
          child: RepaintBoundary(
            child: SizedBox(
              height: widget.height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.78),
                  borderRadius: kOpenHandPillBorderRadius,
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.42),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: kOpenHandPillBorderRadius,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : 0.0;
                      final fillWidth = maxWidth * progress;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SizedBox(
                              width: fillWidth,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      accent.withValues(alpha: 0.98),
                                      accent.withValues(alpha: 0.74),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.22),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: fillWidth > 18
                                    ? Align(
                                        alignment:
                                            AlignmentDirectional.centerEnd,
                                        child: Container(
                                          width: 18,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.white.withValues(
                                                  alpha: 0,
                                                ),
                                                Colors.white.withValues(
                                                  alpha: 0.32,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _normalizedValue(double value) {
    if (!value.isFinite) return 0;
    return value.clamp(0.0, 1.0);
  }
}
