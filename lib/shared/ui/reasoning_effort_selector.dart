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

// ── Layout ──────────────────────────────────────────────────────────────────
const double _kReasoningPopupWidth = 356;
const double _kReasoningPopupEntryHeight = 190;
const double _kReasoningPopupEstimatedHeight = 206;
const double _kReasoningPopupGap = 8;
const double _kReasoningThumbRadius = 22;
const double _kReasoningTrackHalfHeight = 13;

// ── Energy thresholds ───────────────────────────────────────────────────────
const double _kEnergyParticleThreshold = 0.72;
const double _kMaximumProgressThreshold = 0.96;

// ── Motion ──────────────────────────────────────────────────────────────────
const Duration _kProgressAnimDuration = Duration(milliseconds: 360);
const Duration _kCapsuleAnimDuration = Duration(milliseconds: 280);
const Duration _kLabelSwitchDuration = Duration(milliseconds: 220);
const Duration _kMaximumPulsePeriod = Duration(milliseconds: 1500);

/// Imperial Apex palette — fixed prestige stops so the top tier never
/// inherits a muddy theme primary (e.g. teal) that makes max look cheap.
abstract final class _MaximumEffortPalette {
  static const Color voidCore = Color(0xFF0C0618);
  static const Color royalAmethyst = Color(0xFF4C1D95);
  static const Color plasmaViolet = Color(0xFFA855F7);
  static const Color prestigeGold = Color(0xFFF5C542);
  static const Color platinum = Color(0xFFFFF4D6);
  static const Color auroraCyan = Color(0xFF67E8F9);

  static const List<Color> gradientStops = <Color>[
    voidCore,
    royalAmethyst,
    plasmaViolet,
    prestigeGold,
  ];

  static const List<Color> particleColors = <Color>[
    platinum,
    prestigeGold,
    auroraCyan,
    plasmaViolet,
  ];

  static const List<Color> sweepRing = <Color>[
    prestigeGold,
    plasmaViolet,
    auroraCyan,
    prestigeGold,
  ];
}

bool _isMaximumProgress(double progress) =>
    progress >= _kMaximumProgressThreshold;

bool _isEnergyProgress(double progress) => progress >= _kEnergyParticleThreshold;

/// Opens the reasoning-effort selector popup above [anchorContext].
///
/// Entrance / exit motion follows global menu animation settings via
/// [showAnimatedMenu] — never hard-coded.
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

class _ReasoningEffortPopupEntryState extends State<_ReasoningEffortPopupEntry> {
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
          // Caller owns error UX; roll back to last persisted value.
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
    final isMaximum = _isMaximumProgress(progress);

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
                      _kProgressAnimDuration,
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
              child: _ReasoningEffortCapsule(
                label: option.labelForLocaleName(localeName),
                valueKey: option.value,
                progress: progress,
                isMaximum: isMaximum,
                colorScheme: colorScheme,
                textStyle: theme.textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Capsule badge (label under the track) ───────────────────────────────────

class _ReasoningEffortCapsule extends StatelessWidget {
  const _ReasoningEffortCapsule({
    required this.label,
    required this.valueKey,
    required this.progress,
    required this.isMaximum,
    required this.colorScheme,
    required this.textStyle,
  });

  final String label;
  final String valueKey;
  final double progress;
  final bool isMaximum;
  final ColorScheme colorScheme;
  final TextStyle? textStyle;

  List<Color> get _capsuleColors {
    if (isMaximum) return _MaximumEffortPalette.gradientStops;
    final solid = Color.lerp(
      colorScheme.primaryContainer,
      colorScheme.tertiaryContainer,
      progress,
    )!;
    return List<Color>.filled(
      _MaximumEffortPalette.gradientStops.length,
      solid,
    );
  }

  Color get _borderColor {
    if (isMaximum) {
      return _MaximumEffortPalette.platinum.withValues(alpha: 0.55);
    }
    return Color.lerp(
      colorScheme.primary,
      colorScheme.tertiary,
      progress,
    )!.withValues(alpha: 0.5);
  }

  Color get _shadowColor {
    if (isMaximum) return _MaximumEffortPalette.plasmaViolet;
    return Color.lerp(colorScheme.primary, colorScheme.tertiary, progress)!;
  }

  Color get _labelColor {
    if (isMaximum) return Colors.white;
    return Color.lerp(
      colorScheme.onPrimaryContainer,
      colorScheme.onTertiaryContainer,
      progress,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final badge = AnimatedContainer(
      duration: openHandMotionDuration(context, _kCapsuleAnimDuration),
      curve: Curves.easeOutBack,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: _capsuleColors,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _borderColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: _shadowColor.withValues(alpha: isMaximum ? 0.36 : 0.16),
            blurRadius: isMaximum ? 24 : 16,
            offset: const Offset(0, 6),
          ),
          if (isMaximum)
            BoxShadow(
              color: _MaximumEffortPalette.prestigeGold.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: openHandMotionDuration(context, _kLabelSwitchDuration),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: buildCollisionSafeAnimatedSwitcherLayout,
        child: Text(
          label,
          key: ValueKey<String>(valueKey),
          style: textStyle?.copyWith(
            color: _labelColor,
            fontWeight: FontWeight.w800,
            letterSpacing: isMaximum ? 0.4 : 0,
            shadows: isMaximum
                ? const <Shadow>[
                    Shadow(
                      color: Color(0x66000000),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );

    if (!isMaximum) return badge;
    return _MaximumPulseAura(child: badge);
  }
}

/// Soft dual-tone breathing glow around the max-tier capsule.
class _MaximumPulseAura extends StatefulWidget {
  const _MaximumPulseAura({required this.child});

  final Widget child;

  @override
  State<_MaximumPulseAura> createState() => _MaximumPulseAuraState();
}

class _MaximumPulseAuraState extends State<_MaximumPulseAura>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: _kMaximumPulsePeriod,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  void _syncPulse() {
    if (openHandTickerMotionEnabled(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
      return;
    }
    _pulse
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncPulse();
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = Curves.easeInOutCubic.transform(_pulse.value);
        return Transform.scale(
          scale: 1.0 + t * 0.04,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: _MaximumEffortPalette.plasmaViolet.withValues(
                    alpha: 0.28 + t * 0.32,
                  ),
                  blurRadius: 16 + t * 22,
                  spreadRadius: t * 2.2,
                ),
                BoxShadow(
                  color: _MaximumEffortPalette.prestigeGold.withValues(
                    alpha: 0.16 + t * 0.28,
                  ),
                  blurRadius: 22 + t * 26,
                  spreadRadius: -1 + t * 3,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ── Track ───────────────────────────────────────────────────────────────────

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
    if (_isEnergyProgress(oldWidget.progress) !=
        _isEnergyProgress(widget.progress)) {
      _syncEnergyAnimation();
    }
  }

  void _syncEnergyAnimation() {
    final shouldAnimate =
        _isEnergyProgress(widget.progress) &&
        openHandTickerMotionEnabled(context);
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

class _ReasoningParticleField extends ChangeNotifier {
  _ReasoningParticleField() {
    for (var index = 0; index < _particleCount; index++) {
      particles.add(_newParticle(initial: true));
    }
  }

  static const int _particleCount = 20;
  static const double _pulsePeriodSeconds = 1.5;

  final math.Random _random = math.Random();
  final List<_ReasoningParticle> particles = <_ReasoningParticle>[];
  Duration? _previousElapsed;

  /// Smooth 0→1→0 breathing phase driven by the energy ticker.
  double pulse = 0;

  void resetClock() {
    _previousElapsed = null;
    pulse = 0;
  }

  void advance(Duration elapsed) {
    final previous = _previousElapsed;
    _previousElapsed = elapsed;
    if (previous == null) return;
    final deltaSeconds = ((elapsed - previous).inMicroseconds / 1000000)
        .clamp(0.001, 0.05)
        .toDouble();
    // Continuous sine pulse (independent of reverse AnimationController).
    final seconds = elapsed.inMicroseconds / 1000000;
    pulse = 0.5 + 0.5 * math.sin(seconds * math.pi * 2 / _pulsePeriodSeconds);

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
      radius: 0.75 + _random.nextDouble() * 1.55,
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
      Rect.fromLTRB(
        left,
        centerY - _kReasoningTrackHalfHeight,
        right,
        centerY + _kReasoningTrackHalfHeight,
      ),
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
    final isMaximum = _isMaximumProgress(progress);
    final pulse = isMaximum ? particles.pulse : 0.0;
    const maxStops = _MaximumEffortPalette.gradientStops;

    if (activeRight > left) {
      final activeRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          left,
          centerY - _kReasoningTrackHalfHeight,
          activeRight,
          centerY + _kReasoningTrackHalfHeight,
        ),
        const Radius.circular(999),
      );
      final fillColors = isMaximum
          ? maxStops
          : <Color>[
              primaryColor,
              Color.lerp(primaryColor, tertiaryColor, progress)!,
              if (_isEnergyProgress(progress)) secondaryColor,
            ];

      if (isMaximum) {
        // Outer imperial bloom — breathes with pulse.
        final bloomRect = RRect.fromRectAndRadius(
          Rect.fromLTRB(
            left - 2,
            centerY - _kReasoningTrackHalfHeight - 4 - pulse * 3,
            activeRight + 2,
            centerY + _kReasoningTrackHalfHeight + 4 + pulse * 3,
          ),
          const Radius.circular(999),
        );
        canvas.drawRRect(
          bloomRect,
          Paint()
            ..shader = LinearGradient(
              colors: <Color>[
                _MaximumEffortPalette.plasmaViolet.withValues(
                  alpha: 0.22 + pulse * 0.28,
                ),
                _MaximumEffortPalette.prestigeGold.withValues(
                  alpha: 0.18 + pulse * 0.26,
                ),
              ],
            ).createShader(bloomRect.outerRect)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              10 + pulse * 8,
            ),
        );
        // Inner sheen edge.
        canvas.drawRRect(
          activeRect,
          Paint()
            ..shader = LinearGradient(
              colors: maxStops
                  .map((c) => c.withValues(alpha: 0.55 + pulse * 0.25))
                  .toList(growable: false),
            ).createShader(activeRect.outerRect)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }

      canvas.drawRRect(
        activeRect,
        Paint()
          ..shader = LinearGradient(
            colors: fillColors,
          ).createShader(activeRect.outerRect),
      );

      // Sliding highlight band across the max fill.
      if (isMaximum && activeRight - left > 24) {
        final sheenWidth = (activeRight - left) * 0.28;
        final sheenX =
            left + (activeRight - left - sheenWidth) * pulse.clamp(0.0, 1.0);
        final sheenRect = Rect.fromLTWH(
          sheenX,
          centerY - _kReasoningTrackHalfHeight,
          sheenWidth,
          _kReasoningTrackHalfHeight * 2,
        );
        canvas.save();
        canvas.clipRRect(activeRect);
        canvas.drawRect(
          sheenRect,
          Paint()
            ..shader = LinearGradient(
              colors: <Color>[
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0.22 + pulse * 0.12),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(sheenRect),
        );
        canvas.restore();
      }
    }

    final safeDivisions = math.max(1, divisions);
    for (var index = 0; index <= safeDivisions; index++) {
      final tickProgress = index / safeDivisions;
      final x = left + (right - left) * tickProgress;
      final active = tickProgress <= progress + 0.001;
      canvas.drawCircle(
        Offset(x, centerY),
        isMaximum && active ? 3.4 : 3,
        Paint()
          ..color = active
              ? (isMaximum
                    ? _MaximumEffortPalette.platinum.withValues(
                        alpha: 0.7 + pulse * 0.25,
                      )
                    : Colors.white.withValues(alpha: 0.52))
              : outlineColor.withValues(alpha: 0.86),
      );
    }

    if (_isEnergyProgress(progress)) {
      final energy =
          ((progress - _kEnergyParticleThreshold) /
                  (1 - _kEnergyParticleThreshold))
              .clamp(0.0, 1.0);
      final particleRight = math.max(left, activeRight - 3);
      canvas.save();
      canvas.clipRRect(trackRect);
      final particlePalette = isMaximum
          ? _MaximumEffortPalette.particleColors
          : null;
      for (var index = 0; index < particles.particles.length; index++) {
        final particle = particles.particles[index];
        final x = left + (particleRight - left) * particle.x;
        final y = centerY - 10 + particle.y * 20;
        final fadeIn = (particle.age / 0.38).clamp(0.0, 1.0);
        final fadeOut = (particle.life / 0.5).clamp(0.0, 1.0);
        final alpha =
            particle.opacity *
            fadeIn *
            fadeOut *
            energy *
            (isMaximum ? 0.85 + pulse * 0.35 : 1.0);
        final particleColor = particlePalette == null
            ? Colors.white
            : particlePalette[index % particlePalette.length];
        canvas.drawCircle(
          Offset(x, y),
          particle.radius * (isMaximum ? 1.0 + pulse * 0.25 : 1.0),
          Paint()
            ..color = particleColor.withValues(alpha: alpha.clamp(0.0, 1.0))
            ..maskFilter = isMaximum
                ? const MaskFilter.blur(BlurStyle.normal, 1.2)
                : null,
        );
      }
      canvas.restore();
    }

    _paintThumb(canvas, Offset(thumbX, centerY), isMaximum, pulse);
  }

  void _paintThumb(Canvas canvas, Offset center, bool isMaximum, double pulse) {
    if (isMaximum) {
      // Soft prestige halo behind the thumb.
      canvas.drawCircle(
        center,
        _kReasoningThumbRadius + 6 + pulse * 5,
        Paint()
          ..color = _MaximumEffortPalette.prestigeGold.withValues(
            alpha: 0.14 + pulse * 0.22,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 + pulse * 6),
      );
      canvas.drawCircle(
        center,
        _kReasoningThumbRadius + 4 + pulse * 3,
        Paint()
          ..color = _MaximumEffortPalette.plasmaViolet.withValues(
            alpha: 0.16 + pulse * 0.2,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + pulse * 4),
      );
    }

    canvas.drawCircle(center, _kReasoningThumbRadius, Paint()..color = Colors.white);

    final thumbBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isMaximum ? 2.6 : 1.5;
    if (isMaximum) {
      // Rotating prestige ring driven by pulse phase.
      final angle = pulse * math.pi * 2;
      thumbBorderPaint.shader = SweepGradient(
        startAngle: angle,
        endAngle: angle + math.pi * 2,
        colors: _MaximumEffortPalette.sweepRing,
      ).createShader(
        Rect.fromCircle(center: center, radius: _kReasoningThumbRadius),
      );
    } else {
      thumbBorderPaint.color = Color.lerp(
        primaryColor,
        tertiaryColor,
        progress,
      )!.withValues(alpha: 0.32);
    }
    canvas.drawCircle(center, _kReasoningThumbRadius, thumbBorderPaint);

    if (isMaximum) {
      // Inner gold rim for a jewelry-like finish.
      canvas.drawCircle(
        center,
        _kReasoningThumbRadius - 3.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = _MaximumEffortPalette.prestigeGold.withValues(
            alpha: 0.35 + pulse * 0.35,
          ),
      );
    }
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
