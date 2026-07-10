import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/ai/model/ai_model_config.dart';
import '../util/localized_text.dart';
import 'animated_menu.dart';
import 'motion_preference.dart';

const double _kReasoningPopupWidth = 356;
const double _kReasoningTrackHorizontalInset = 24;
const double _kReasoningThumbRadius = 22;

Future<String?> showReasoningEffortSelector({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<AiReasoningEffortOption> options,
  required String? currentValue,
}) {
  final selectable = options
      .where((option) => option.isSelectable)
      .toList(growable: false);
  if (selectable.isEmpty) return Future<String?>.value();
  final anchorBox = anchorContext.findRenderObject();
  final overlayBox = Overlay.maybeOf(anchorContext)?.context.findRenderObject();
  if (anchorBox is! RenderBox ||
      overlayBox is! RenderBox ||
      !anchorBox.hasSize ||
      !overlayBox.hasSize) {
    return Future<String?>.value();
  }
  final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  final anchorRect = topLeft & anchorBox.size;
  final popupWidth = math
      .min(_kReasoningPopupWidth, math.max(112, overlayBox.size.width - 16))
      .toDouble();
  return showAnimatedMenu<String>(
    context: context,
    position: RelativeRect.fromRect(anchorRect, Offset.zero & overlayBox.size),
    constraints: BoxConstraints(minWidth: popupWidth, maxWidth: popupWidth),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    items: <PopupMenuEntry<String>>[
      _ReasoningEffortPopupEntry(
        width: popupWidth,
        options: selectable,
        currentValue: currentValue,
      ),
    ],
  );
}

class _ReasoningEffortPopupEntry extends PopupMenuEntry<String> {
  const _ReasoningEffortPopupEntry({
    required this.width,
    required this.options,
    required this.currentValue,
  });

  final double width;
  final List<AiReasoningEffortOption> options;
  final String? currentValue;

  @override
  double get height => 190;

  @override
  bool represents(String? value) => false;

  @override
  State<_ReasoningEffortPopupEntry> createState() =>
      _ReasoningEffortPopupEntryState();
}

class _ReasoningEffortPopupEntryState
    extends State<_ReasoningEffortPopupEntry> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    final normalizedCurrent = widget.currentValue?.trim().toLowerCase();
    final resolved = widget.options.indexWhere(
      (option) => option.value.toLowerCase() == normalizedCurrent,
    );
    _selectedIndex = resolved < 0 ? widget.options.length ~/ 2 : resolved;
  }

  void _select(double value) {
    final next = value.round().clamp(0, widget.options.length - 1);
    if (next == _selectedIndex) return;
    setState(() => _selectedIndex = next);
    HapticFeedback.selectionClick();
  }

  void _commit(double value) {
    final next = value.round().clamp(0, widget.options.length - 1);
    Navigator.of(context).pop(widget.options[next].value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final option = widget.options[_selectedIndex];
    final maxIndex = math.max(1, widget.options.length - 1);
    final progress = _selectedIndex / maxIndex;
    return SizedBox(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  openHandLocalizedText(context, zh: '更快', en: 'Faster'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  openHandLocalizedText(context, zh: '更智能', en: 'Smarter'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 68,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: <Widget>[
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: progress),
                    duration: openHandMotionDuration(
                      context,
                      const Duration(milliseconds: 360),
                    ),
                    curve: Curves.easeOutBack,
                    builder: (context, animatedProgress, _) =>
                        _AnimatedReasoningTrack(
                          progress: animatedProgress.clamp(0, 1),
                          divisions: maxIndex,
                        ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 0,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      disabledActiveTrackColor: Colors.transparent,
                      disabledInactiveTrackColor: Colors.transparent,
                      thumbColor: Colors.transparent,
                      overlayColor: colorScheme.primary.withValues(alpha: 0.08),
                      thumbShape: const _InvisibleSliderThumbShape(),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 28,
                      ),
                      tickMarkShape: SliderTickMarkShape.noTickMark,
                    ),
                    child: Slider(
                      value: _selectedIndex.toDouble(),
                      max: maxIndex.toDouble(),
                      divisions: maxIndex,
                      semanticFormatterCallback: (value) => widget
                          .options[value.round()]
                          .labelForLocaleName(localeName),
                      onChanged: _select,
                      onChangeEnd: _commit,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: AnimatedContainer(
                duration: openHandMotionDuration(
                  context,
                  const Duration(milliseconds: 280),
                ),
                curve: Curves.easeOutBack,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Color.lerp(
                    colorScheme.primaryContainer,
                    colorScheme.tertiaryContainer,
                    progress,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Color.lerp(
                      colorScheme.primary,
                      colorScheme.tertiary,
                      progress,
                    )!.withValues(alpha: 0.5),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Color.lerp(
                        colorScheme.primary,
                        colorScheme.tertiary,
                        progress,
                      )!.withValues(alpha: 0.16),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: openHandMotionDuration(
                    context,
                    const Duration(milliseconds: 220),
                  ),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  child: Text(
                    option.labelForLocaleName(localeName),
                    key: ValueKey<String>(option.value),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Color.lerp(
                        colorScheme.onPrimaryContainer,
                        colorScheme.onTertiaryContainer,
                        progress,
                      ),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedReasoningTrack extends StatefulWidget {
  const _AnimatedReasoningTrack({
    required this.progress,
    required this.divisions,
  });

  final double progress;
  final int divisions;

  @override
  State<_AnimatedReasoningTrack> createState() =>
      _AnimatedReasoningTrackState();
}

class _AnimatedReasoningTrackState extends State<_AnimatedReasoningTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _energyController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncEnergyAnimation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedReasoningTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.progress >= 0.72) != (widget.progress >= 0.72)) {
      _syncEnergyAnimation();
    }
  }

  void _syncEnergyAnimation() {
    final shouldAnimate =
        widget.progress >= 0.72 && openHandTickerMotionEnabled(context);
    if (shouldAnimate && !_energyController.isAnimating) {
      _energyController.repeat();
    } else if (!shouldAnimate && _energyController.isAnimating) {
      _energyController.stop();
    }
  }

  @override
  void dispose() {
    _energyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _energyController,
      builder: (context, _) => CustomPaint(
        painter: _ReasoningTrackPainter(
          progress: widget.progress,
          divisions: widget.divisions,
          phase: _energyController.value,
          surfaceColor: colors.surfaceContainerHighest,
          outlineColor: colors.outlineVariant,
          primaryColor: colors.primary,
          secondaryColor: colors.secondary,
          tertiaryColor: colors.tertiary,
        ),
      ),
    );
  }
}

class _ReasoningTrackPainter extends CustomPainter {
  const _ReasoningTrackPainter({
    required this.progress,
    required this.divisions,
    required this.phase,
    required this.surfaceColor,
    required this.outlineColor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.tertiaryColor,
  });

  final double progress;
  final int divisions;
  final double phase;
  final Color surfaceColor;
  final Color outlineColor;
  final Color primaryColor;
  final Color secondaryColor;
  final Color tertiaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const left = _kReasoningTrackHorizontalInset;
    final right = math.max(left, size.width - _kReasoningTrackHorizontalInset);
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(left, centerY - 13, right, centerY + 13),
      const Radius.circular(999),
    );
    canvas.drawRRect(trackRect, Paint()..color = surfaceColor);
    canvas.drawRRect(
      trackRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outlineColor,
    );

    final thumbX = left + (right - left) * progress;
    if (thumbX > left) {
      final activeRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left, centerY - 13, thumbX, centerY + 13),
        const Radius.circular(999),
      );
      canvas.drawRRect(
        activeRect,
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              primaryColor,
              Color.lerp(primaryColor, tertiaryColor, progress)!,
              if (progress >= 0.72) secondaryColor,
            ],
          ).createShader(activeRect.outerRect),
      );
    }

    final safeDivisions = math.max(1, divisions);
    for (var index = 0; index <= safeDivisions; index++) {
      final tickProgress = index / safeDivisions;
      final x = left + (right - left) * tickProgress;
      final active = tickProgress <= progress + 0.001;
      canvas.drawCircle(
        Offset(x, centerY),
        3,
        Paint()
          ..color = active
              ? Colors.white.withValues(alpha: 0.52)
              : outlineColor.withValues(alpha: 0.86),
      );
    }

    if (progress >= 0.72) {
      final energy = ((progress - 0.72) / 0.28).clamp(0.0, 1.0);
      for (var index = 0; index < 11; index++) {
        final base = (index * 0.087 + phase * (0.08 + index * 0.002)) % 1;
        final x = left + (thumbX - left) * base;
        final wave = math.sin((phase * math.pi * 2) + index * 1.7);
        final y = centerY + wave * (5 + (index % 3));
        final alpha = (0.28 + (wave + 1) * 0.22) * energy;
        canvas.drawCircle(
          Offset(x, y),
          1.2 + (index % 3) * 0.35,
          Paint()..color = Colors.white.withValues(alpha: alpha),
        );
      }
    }

    canvas.drawCircle(
      Offset(thumbX, centerY + 4),
      _kReasoningThumbRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawCircle(
      Offset(thumbX, centerY),
      _kReasoningThumbRadius,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(thumbX, centerY),
      _kReasoningThumbRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Color.lerp(
          primaryColor,
          tertiaryColor,
          progress,
        )!.withValues(alpha: 0.32),
    );
  }

  @override
  bool shouldRepaint(covariant _ReasoningTrackPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        divisions != oldDelegate.divisions ||
        phase != oldDelegate.phase ||
        surfaceColor != oldDelegate.surfaceColor ||
        outlineColor != oldDelegate.outlineColor ||
        primaryColor != oldDelegate.primaryColor ||
        secondaryColor != oldDelegate.secondaryColor ||
        tertiaryColor != oldDelegate.tertiaryColor;
  }
}

class _InvisibleSliderThumbShape extends SliderComponentShape {
  const _InvisibleSliderThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(_kReasoningThumbRadius * 2);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {}
}
