import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../features/ai/model/ai_model_config.dart';
import '../util/localized_text.dart';
import 'animated_menu.dart';
import 'collision_safe_animated_switcher.dart';
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
        var saved = false;
        try {
          saved = await widget.onChanged(effort);
        } catch (_) {
          // The selector must remain usable even if persistence fails. The
          // caller owns user-facing error reporting; here we safely roll back.
        }
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
    final capsuleColor = Color.lerp(
      colorScheme.primaryContainer,
      colorScheme.tertiaryContainer,
      progress,
    )!;
    final capsuleColors = isMaximum
        ? maximumColors
        : List<Color>.filled(maximumColors.length, capsuleColor);
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
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: capsuleColors,
                  ),
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
                  layoutBuilder: buildCollisionSafeAnimatedSwitcherLayout,
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
  late final _ReasoningParticleField _particles = _ReasoningParticleField();
  late final Ticker _energyTicker = createTicker(_particles.advance);

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
    if (shouldAnimate && !_energyTicker.isActive) {
      _particles.resetClock();
      _energyTicker.start();
    } else if (!shouldAnimate && _energyTicker.isActive) {
      _energyTicker.stop();
      _particles.resetClock();
    }
  }

  @override
  void dispose() {
    _energyTicker.dispose();
    _particles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _ReasoningTrackPainter(
        progress: widget.progress,
        divisions: widget.divisions,
        particles: _particles,
        surfaceColor: colors.surfaceContainerHighest,
        outlineColor: colors.outlineVariant,
        primaryColor: colors.primary,
        secondaryColor: colors.secondary,
        tertiaryColor: colors.tertiary,
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
  const obsidianTeal = Color(0xFF082C3A);
  const abyssalBlue = Color(0xFF0B5870);
  const royalIndigo = Color(0xFF3348B8);
  const imperialViolet = Color(0xFF683A88);
  return <Color>[
    Color.lerp(primary, obsidianTeal, 0.82)!,
    Color.lerp(secondary, abyssalBlue, 0.78)!,
    Color.lerp(primary, royalIndigo, 0.76)!,
    Color.lerp(tertiary, imperialViolet, 0.78)!,
  ];
}

class _ReasoningParticleField extends ChangeNotifier {
  _ReasoningParticleField() {
    for (var index = 0; index < _particleCount; index++) {
      particles.add(_newParticle(initial: true));
    }
  }

  static const int _particleCount = 17;
  final math.Random _random = math.Random();
  final List<_ReasoningParticle> particles = <_ReasoningParticle>[];
  Duration? _previousElapsed;

  void resetClock() => _previousElapsed = null;

  void advance(Duration elapsed) {
    final previous = _previousElapsed;
    _previousElapsed = elapsed;
    if (previous == null) return;
    final deltaSeconds = ((elapsed - previous).inMicroseconds / 1000000)
        .clamp(0.001, 0.05)
        .toDouble();
    for (var index = 0; index < particles.length; index++) {
      final particle = particles[index];
      particle.life -= deltaSeconds;
      if (particle.life <= 0 ||
          particle.x < -0.08 ||
          particle.x > 1.08 ||
          particle.y < -0.18 ||
          particle.y > 1.18) {
        particles[index] = _newParticle(initial: false);
        continue;
      }
      final randomX = (_random.nextDouble() - 0.5) * 0.32;
      final randomY = (_random.nextDouble() - 0.5) * 0.46;
      particle.vx = (particle.vx + randomX * deltaSeconds)
          .clamp(-0.13, 0.13)
          .toDouble();
      particle.vy = (particle.vy + randomY * deltaSeconds)
          .clamp(-0.2, 0.2)
          .toDouble();
      final damping = math.pow(0.72, deltaSeconds).toDouble();
      particle.vx *= damping;
      particle.vy *= damping;
      particle.x += particle.vx * deltaSeconds;
      particle.y += particle.vy * deltaSeconds;
      particle.age += deltaSeconds;
      particle.opacity =
          (particle.opacity +
                  (_random.nextDouble() - 0.48) * deltaSeconds * 0.9)
              .clamp(0.28, 0.96)
              .toDouble();
    }
    notifyListeners();
  }

  _ReasoningParticle _newParticle({required bool initial}) {
    return _ReasoningParticle(
      x: _random.nextDouble(),
      y: 0.14 + _random.nextDouble() * 0.72,
      vx: (_random.nextDouble() - 0.42) * 0.075,
      vy: (_random.nextDouble() - 0.5) * 0.11,
      radius: 0.75 + _random.nextDouble() * 1.45,
      opacity: initial ? 0.36 + _random.nextDouble() * 0.55 : 0.28,
      age: initial ? 0.4 + _random.nextDouble() * 1.2 : 0,
      life: 1.8 + _random.nextDouble() * 4.6,
    );
  }
}

class _ReasoningParticle {
  _ReasoningParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.opacity,
    required this.age,
    required this.life,
  });

  double x;
  double y;
  double vx;
  double vy;
  final double radius;
  double opacity;
  double age;
  double life;
}

class _ReasoningTrackPainter extends CustomPainter {
  const _ReasoningTrackPainter({
    required this.progress,
    required this.divisions,
    required this.particles,
    required this.surfaceColor,
    required this.outlineColor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.tertiaryColor,
  }) : super(repaint: particles);

  final double progress;
  final int divisions;
  final _ReasoningParticleField particles;
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
      for (var index = 0; index < particles.particles.length; index++) {
        final particle = particles.particles[index];
        final x = left + (particleRight - left) * particle.x;
        final y = centerY - 10 + particle.y * 20;
        final fadeIn = (particle.age / 0.38).clamp(0.0, 1.0);
        final fadeOut = (particle.life / 0.5).clamp(0.0, 1.0);
        final alpha = particle.opacity * fadeIn * fadeOut * energy;
        final particleColor = isMaximum
            ? Color.lerp(
                Colors.white,
                maximumColors[index % maximumColors.length],
                0.16,
              )!
            : Colors.white;
        canvas.drawCircle(
          Offset(x, y),
          particle.radius,
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
        particles != oldDelegate.particles ||
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
