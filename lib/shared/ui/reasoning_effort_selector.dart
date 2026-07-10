import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/ai/model/ai_model_config.dart';
import '../util/localized_text.dart';
import 'animated_menu.dart';
import 'motion_preference.dart';

const double _kReasoningPopupWidth = 356;
const double _kReasoningPopupEntryHeight = 190;
const double _kReasoningPopupEstimatedHeight = 206;
const double _kReasoningPopupGap = 8;
const double _kReasoningThumbRadius = 22;

Future<void> showReasoningEffortSelector({
  required BuildContext context,
  required BuildContext anchorContext,
  required List<AiReasoningEffortOption> options,
  required String? currentValue,
  required Future<bool> Function(String effort) onChanged,
}) async {
  final selectable = options
      .where((option) => option.isSelectable)
      .toList(growable: false);
  if (selectable.isEmpty) return;
  final anchorBox = anchorContext.findRenderObject();
  final overlayBox = Overlay.maybeOf(anchorContext)?.context.findRenderObject();
  if (anchorBox is! RenderBox ||
      overlayBox is! RenderBox ||
      !anchorBox.hasSize ||
      !overlayBox.hasSize) {
    return;
  }
  final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
  final popupTop = math.max(
    8,
    topLeft.dy - _kReasoningPopupEstimatedHeight - _kReasoningPopupGap,
  );
  final anchorRect = Rect.fromLTWH(
    topLeft.dx,
    popupTop.toDouble(),
    anchorBox.size.width,
    0,
  );
  final popupWidth = math
      .min(_kReasoningPopupWidth, math.max(112, overlayBox.size.width - 16))
      .toDouble();
  await showAnimatedMenu<String>(
    context: context,
    position: RelativeRect.fromRect(anchorRect, Offset.zero & overlayBox.size),
    constraints: BoxConstraints(minWidth: popupWidth, maxWidth: popupWidth),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    items: <PopupMenuEntry<String>>[
      _ReasoningEffortPopupEntry(
        width: popupWidth,
        options: selectable,
        currentValue: currentValue,
        onChanged: onChanged,
      ),
    ],
  );
}

class _ReasoningEffortPopupEntry extends PopupMenuEntry<String> {
  const _ReasoningEffortPopupEntry({
    required this.width,
    required this.options,
    required this.currentValue,
    required this.onChanged,
  });

  final double width;
  final List<AiReasoningEffortOption> options;
  final String? currentValue;
  final Future<bool> Function(String effort) onChanged;

  @override
  double get height => _kReasoningPopupEntryHeight;

  @override
  bool represents(String? value) => false;

  @override
  State<_ReasoningEffortPopupEntry> createState() =>
      _ReasoningEffortPopupEntryState();
}

class _ReasoningEffortPopupEntryState
    extends State<_ReasoningEffortPopupEntry> {
  late int _selectedIndex;
  late String _persistedValue;
  String? _pendingValue;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final normalizedCurrent = widget.currentValue?.trim().toLowerCase();
    final resolved = widget.options.indexWhere(
      (option) => option.value.toLowerCase() == normalizedCurrent,
    );
    _selectedIndex = resolved < 0 ? widget.options.length ~/ 2 : resolved;
    _persistedValue = widget.options[_selectedIndex].value;
  }

  void _select(double value) {
    final next = value.round().clamp(0, widget.options.length - 1);
    if (next == _selectedIndex) return;
    setState(() => _selectedIndex = next);
    HapticFeedback.selectionClick();
  }

  void _commit(double value) {
    final next = value.round().clamp(0, widget.options.length - 1);
    final effort = widget.options[next].value;
    if (!_saving && effort.toLowerCase() == _persistedValue.toLowerCase()) {
      return;
    }
    if (_pendingValue?.toLowerCase() == effort.toLowerCase()) return;
    _pendingValue = effort;
    if (_saving) return;
    _saving = true;
    unawaited(_drainPendingChanges());
  }

  Future<void> _drainPendingChanges() async {
    try {
      while (_pendingValue != null) {
        final effort = _pendingValue!;
        _pendingValue = null;
        final saved = await widget.onChanged(effort);
        if (saved) {
          _persistedValue = effort;
          continue;
        }
        if (_pendingValue == null && mounted) {
          final persistedIndex = widget.options.indexWhere(
            (option) =>
                option.value.toLowerCase() == _persistedValue.toLowerCase(),
          );
          if (persistedIndex >= 0) {
            setState(() => _selectedIndex = persistedIndex);
          }
        }
      }
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final option = widget.options[_selectedIndex];
    final maxIndex = math.max(1, widget.options.length - 1);
    final progress = _selectedIndex / maxIndex;
    final isMaximum = progress >= 0.96;
    final maximumColors = _maximumEffortColors(colorScheme);
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
                      overlayColor: Colors.transparent,
                      thumbShape: const _InvisibleSliderThumbShape(),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 0,
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
                  color: isMaximum
                      ? null
                      : Color.lerp(
                          colorScheme.primaryContainer,
                          colorScheme.tertiaryContainer,
                          progress,
                        ),
                  gradient: isMaximum
                      ? LinearGradient(
                          begin: AlignmentDirectional.centerStart,
                          end: AlignmentDirectional.centerEnd,
                          colors: maximumColors,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isMaximum
                        ? Colors.white.withValues(alpha: 0.5)
                        : Color.lerp(
                            colorScheme.primary,
                            colorScheme.tertiary,
                            progress,
                          )!.withValues(alpha: 0.5),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color:
                          (isMaximum
                                  ? maximumColors.last
                                  : Color.lerp(
                                      colorScheme.primary,
                                      colorScheme.tertiary,
                                      progress,
                                    ))!
                              .withValues(alpha: isMaximum ? 0.3 : 0.16),
                      blurRadius: isMaximum ? 22 : 16,
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
                      color: isMaximum
                          ? Colors.white
                          : Color.lerp(
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

List<Color> _maximumEffortColors(ColorScheme colors) {
  return _maximumEffortColorsFromSeeds(
    colors.primary,
    colors.secondary,
    colors.tertiary,
  );
}

List<Color> _maximumEffortColorsFromSeeds(
  Color primary,
  Color secondary,
  Color tertiary,
) {
  final seed = Color.lerp(primary, tertiary, 0.28)!;
  return <Color>[
    Color.lerp(_shiftVividHue(seed, -18), primary, 0.22)!,
    Color.lerp(_shiftVividHue(seed, 82), tertiary, 0.18)!,
    Color.lerp(_shiftVividHue(seed, 188), secondary, 0.16)!,
  ];
}

Color _shiftVividHue(Color color, double degrees) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withHue((hsl.hue + degrees) % 360)
      .withSaturation(math.max(0.72, hsl.saturation).clamp(0.0, 1.0).toDouble())
      .withLightness(hsl.lightness.clamp(0.46, 0.62).toDouble())
      .toColor();
}

const List<_ReasoningParticleSeed> _reasoningParticleSeeds =
    <_ReasoningParticleSeed>[
      _ReasoningParticleSeed(0.03, -5.2, 1.2, 0.3, 0.72, 1.4, 1.1),
      _ReasoningParticleSeed(0.08, 4.1, 0.8, 1.8, 1.14, 2.2, 0.8),
      _ReasoningParticleSeed(0.14, -0.8, 1.5, 3.1, 0.86, 1.2, 1.7),
      _ReasoningParticleSeed(0.21, 6.3, 0.7, 4.7, 1.31, 2.8, 1.0),
      _ReasoningParticleSeed(0.27, -6.8, 1.0, 2.2, 0.67, 1.8, 1.4),
      _ReasoningParticleSeed(0.34, 2.6, 1.3, 5.4, 1.08, 2.4, 0.9),
      _ReasoningParticleSeed(0.42, -3.7, 0.7, 0.9, 1.42, 1.3, 1.8),
      _ReasoningParticleSeed(0.49, 6.9, 1.6, 3.8, 0.78, 2.6, 1.2),
      _ReasoningParticleSeed(0.57, -7.1, 0.9, 5.9, 1.19, 1.6, 1.5),
      _ReasoningParticleSeed(0.63, 0.7, 1.2, 1.5, 0.91, 2.1, 1.0),
      _ReasoningParticleSeed(0.71, 5.4, 0.8, 4.3, 1.36, 2.7, 1.6),
      _ReasoningParticleSeed(0.78, -4.9, 1.5, 2.7, 0.63, 1.4, 0.8),
      _ReasoningParticleSeed(0.85, 3.8, 1.0, 5.1, 1.02, 2.3, 1.3),
      _ReasoningParticleSeed(0.92, -1.8, 1.3, 0.5, 1.27, 1.7, 1.7),
      _ReasoningParticleSeed(0.97, 6.1, 0.7, 3.5, 0.83, 2.5, 0.9),
    ];

class _ReasoningParticleSeed {
  const _ReasoningParticleSeed(
    this.x,
    this.y,
    this.radius,
    this.phase,
    this.speed,
    this.driftX,
    this.driftY,
  );

  final double x;
  final double y;
  final double radius;
  final double phase;
  final double speed;
  final double driftX;
  final double driftY;
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
    const left = 0.0;
    final right = math.max(left, size.width);
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

    final thumbLeft = math.min(right, left + _kReasoningThumbRadius);
    final thumbRight = math.max(thumbLeft, right - _kReasoningThumbRadius);
    final thumbX = thumbLeft + (thumbRight - thumbLeft) * progress;
    final activeRight = progress >= 1
        ? right
        : progress <= 0
        ? left
        : thumbX;
    final isMaximum = progress >= 0.96;
    final maximumColors = _maximumEffortColorsFromSeeds(
      primaryColor,
      secondaryColor,
      tertiaryColor,
    );
    if (activeRight > left) {
      final activeRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(left, centerY - 13, activeRight, centerY + 13),
        const Radius.circular(999),
      );
      final fillColors = isMaximum
          ? maximumColors
          : <Color>[
              primaryColor,
              Color.lerp(primaryColor, tertiaryColor, progress)!,
              if (progress >= 0.72) secondaryColor,
            ];
      if (isMaximum) {
        canvas.drawRRect(
          activeRect,
          Paint()
            ..shader = LinearGradient(
              colors: fillColors
                  .map((color) {
                    return color.withValues(alpha: 0.72);
                  })
                  .toList(growable: false),
            ).createShader(activeRect.outerRect)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        );
      }
      canvas.drawRRect(
        activeRect,
        Paint()
          ..shader = LinearGradient(
            colors: fillColors,
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
      final particleRight = math.max(left, activeRight - 3);
      canvas.save();
      canvas.clipRRect(trackRect);
      for (var index = 0; index < _reasoningParticleSeeds.length; index++) {
        final seed = _reasoningParticleSeeds[index];
        final theta = phase * math.pi * 2 * seed.speed + seed.phase;
        final x =
            left +
            (particleRight - left) * seed.x +
            math.sin(theta) * seed.driftX;
        final y = centerY + seed.y + math.cos(theta * 0.83) * seed.driftY;
        final pulse = (math.sin(theta * 1.17) + 1) / 2;
        final alpha = (0.24 + pulse * 0.58) * energy;
        final particleColor = isMaximum
            ? Color.lerp(
                Colors.white,
                maximumColors[index % maximumColors.length],
                0.22,
              )!
            : Colors.white;
        canvas.drawCircle(
          Offset(x, y),
          seed.radius * (0.82 + pulse * 0.3),
          Paint()..color = particleColor.withValues(alpha: alpha),
        );
      }
      canvas.restore();
    }

    canvas.drawCircle(
      Offset(thumbX, centerY),
      _kReasoningThumbRadius,
      Paint()..color = Colors.white,
    );
    final thumbBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isMaximum ? 2.2 : 1.5;
    if (isMaximum) {
      thumbBorderPaint.shader =
          SweepGradient(
            colors: <Color>[...maximumColors, maximumColors.first],
          ).createShader(
            Rect.fromCircle(
              center: Offset(thumbX, centerY),
              radius: _kReasoningThumbRadius,
            ),
          );
    } else {
      thumbBorderPaint.color = Color.lerp(
        primaryColor,
        tertiaryColor,
        progress,
      )!.withValues(alpha: 0.32);
    }
    canvas.drawCircle(
      Offset(thumbX, centerY),
      _kReasoningThumbRadius,
      thumbBorderPaint,
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
