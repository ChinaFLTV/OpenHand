import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../../features/ai/model/ai_model_config.dart';
import '../util/localized_text.dart';
import 'animated_menu.dart';
import 'collision_safe_animated_switcher.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';

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
const Duration _kCapsuleAnimDuration = kOpenHandMotion420;
const Duration _kLabelSwitchDuration = kOpenHandMotion280;

/// Progress at which the capsule starts blending into the max-tier palette.
const double _kCapsuleMaxBlendStart = 0.72;

// ── Particles ───────────────────────────────────────────────────────────────
const int _kBaseParticleCount = 18;
const int _kMaximumParticleCount = 42;
const int _kMaxThumbSparks = 64;
const int _kThumbBurstCount = 28;
const double _kThumbRingPeriodSeconds = 10.0;
const double _kThumbEmberInterval = 0.065;
const double _kThumbSparkMaxDist = 58;

/// Void Aurora — cool deep-space prestige.
/// Deep ink → navy → electric blue → ice cyan. No gold/purple "VIP bar" look.
abstract final class _MaximumEffortPalette {
  static const Color voidInk = Color(0xFF05070E);
  static const Color deepNavy = Color(0xFF0B1A33);
  static const Color royalBlue = Color(0xFF1D4ED8);
  static const Color electric = Color(0xFF38BDF8);
  static const Color ice = Color(0xFFBAE6FD);
  static const Color platinum = Color(0xFFF8FAFC);

  static const List<Color> gradientStops = <Color>[
    voidInk,
    deepNavy,
    royalBlue,
    electric,
  ];

  static const List<Color> particleColors = <Color>[
    platinum,
    ice,
    electric,
    Color(0xFF93C5FD),
  ];

  static const List<Color> sweepRing = <Color>[
    electric,
    ice,
    platinum,
    Color(0xFF60A5FA),
    electric,
  ];
}

enum _ParticleKind { dust, spark, flare }

bool _isMaximumProgress(double progress) =>
    progress >= _kMaximumProgressThreshold;

bool _isEnergyProgress(double progress) =>
    progress >= _kEnergyParticleThreshold;

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
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kOpenHandRadius24)),
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
            kOpenHandGap4,
            SizedBox(
              height: 68,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: <Widget>[
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: progress),
                    duration: openHandMotionDuration(
                      context,
                      _kProgressAnimDuration,
                    ),
                    curve: kOpenHandEntranceCurve,
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
            kOpenHandGap4,
            Center(
              child: _ReasoningEffortCapsule(
                label: option.labelForLocaleName(localeName),
                valueKey: option.value,
                progress: progress,
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

// ── Capsule badge ───────────────────────────────────────────────────────────

/// 0→1 blend into the max-tier palette. Starts near high energy, fully on at max.
double _capsuleMaxBlend(double progress) {
  final raw =
      ((progress - _kCapsuleMaxBlendStart) / (1 - _kCapsuleMaxBlendStart))
          .clamp(0.0, 1.0);
  return Curves.easeInOutCubic.transform(raw);
}

/// Continuous 4-stop gradient: mid tiers ease through theme containers,
/// then gently dissolve into Void Aurora as progress approaches 1.
List<Color> _capsuleGradientStops(double progress, ColorScheme colors) {
  final blend = _capsuleMaxBlend(progress);
  final base = <Color>[
    Color.lerp(
      colors.primaryContainer,
      colors.tertiaryContainer,
      progress * 0.28,
    )!,
    Color.lerp(
      colors.primaryContainer,
      colors.tertiaryContainer,
      progress * 0.52,
    )!,
    Color.lerp(
      colors.primaryContainer,
      colors.tertiaryContainer,
      progress * 0.74,
    )!,
    Color.lerp(colors.primaryContainer, colors.tertiaryContainer, progress)!,
  ];
  const maxStops = _MaximumEffortPalette.gradientStops;
  return <Color>[
    for (var i = 0; i < maxStops.length; i++)
      Color.lerp(base[i], maxStops[i], blend)!,
  ];
}

class _ReasoningEffortCapsule extends StatelessWidget {
  const _ReasoningEffortCapsule({
    required this.label,
    required this.valueKey,
    required this.progress,
    required this.colorScheme,
    required this.textStyle,
  });

  final String label;
  final String valueKey;
  final double progress;
  final ColorScheme colorScheme;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    // Tween discrete slider steps so fill / border / label colors ease together.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: progress.clamp(0.0, 1.0)),
      duration: openHandMotionDuration(context, _kCapsuleAnimDuration),
      curve: kOpenHandSwitchInCurve,
      builder: (context, animatedProgress, _) {
        final blend = _capsuleMaxBlend(animatedProgress);
        final stops = _capsuleGradientStops(animatedProgress, colorScheme);
        final midAccent = Color.lerp(
          colorScheme.primary,
          colorScheme.tertiary,
          animatedProgress,
        )!;
        final midOn = Color.lerp(
          colorScheme.onPrimaryContainer,
          colorScheme.onTertiaryContainer,
          animatedProgress,
        )!;
        final borderColor = Color.lerp(
          midAccent.withValues(alpha: 0.5),
          _MaximumEffortPalette.ice.withValues(alpha: 0.55),
          blend,
        )!;
        final shadowA = Color.lerp(
          midAccent,
          _MaximumEffortPalette.electric,
          blend,
        )!;
        final labelColor = Color.lerp(midOn, Colors.white, blend)!;

        // Plain Container: color is already eased by the outer TweenAnimationBuilder.
        final badge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: stops,
            ),
            borderRadius: kOpenHandPillBorderRadius,
            border: Border.all(color: borderColor),
            // Fixed shadow slots so intensity can fade without layer pop-in.
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: shadowA.withValues(alpha: 0.16 + blend * 0.22),
                blurRadius: 16 + blend * 6,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: _MaximumEffortPalette.ice.withValues(alpha: blend * 0.2),
                blurRadius: 12 + blend * 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: openHandMotionDuration(context, _kLabelSwitchDuration),
            switchInCurve: kOpenHandSwitchInCurve,
            switchOutCurve: kOpenHandSwitchOutCurve,
            layoutBuilder: buildCollisionSafeAnimatedSwitcherLayout,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(0, 0.12),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: kOpenHandSwitchInCurve,
                        ),
                      ),
                  child: child,
                ),
              );
            },
            child: Text(
              label,
              key: ValueKey<String>(valueKey),
              style: textStyle?.copyWith(
                color: labelColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.35 * blend,
                shadows: blend > 0.08
                    ? <Shadow>[
                        Shadow(
                          color: const Color(
                            0x66000000,
                          ).withValues(alpha: 0.4 * blend),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );

        return _MaximumPulseAura(intensity: blend, child: badge);
      },
    );
  }
}

/// Soft dual-tone breathing glow; [intensity] 0 hides it without mount flicker.
class _MaximumPulseAura extends StatefulWidget {
  const _MaximumPulseAura({required this.child, required this.intensity});

  final Widget child;
  final double intensity;

  @override
  State<_MaximumPulseAura> createState() => _MaximumPulseAuraState();
}

class _MaximumPulseAuraState extends State<_MaximumPulseAura>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _MaximumPulseAura oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.intensity > 0.02) != (widget.intensity > 0.02)) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    final want =
        widget.intensity > 0.02 && openHandTickerMotionEnabled(context);
    if (want) {
      if (!_clock.isAnimating) _clock.repeat();
      return;
    }
    _clock
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncPulse();
    final intensity = widget.intensity.clamp(0.0, 1.0);
    if (intensity <= 0.001) return widget.child;

    return AnimatedBuilder(
      animation: _clock,
      builder: (context, child) {
        final t = _clock.value * math.pi * 2;
        final glow =
            (0.5 +
                    0.22 * math.sin(t * 1.1) +
                    0.16 * math.sin(t * 1.87) +
                    0.1 * math.sin(t * 0.61))
                .clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: kOpenHandPillBorderRadius,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: _MaximumEffortPalette.royalBlue.withValues(
                  alpha: (0.28 + glow * 0.22) * intensity,
                ),
                blurRadius: 14 + glow * 12,
                spreadRadius: glow * 1.2 * intensity,
              ),
              BoxShadow(
                color: _MaximumEffortPalette.electric.withValues(
                  alpha: (0.16 + glow * 0.18) * intensity,
                ),
                blurRadius: 20 + glow * 14,
                spreadRadius: (-1 + glow * 1.6) * intensity,
              ),
            ],
          ),
          child: child,
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
  late final Ticker _energyTicker = createTicker(_onTick);

  void _onTick(Duration elapsed) {
    _particles.advance(elapsed, maximum: _isMaximumProgress(widget.progress));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncEnergyAnimation();
  }

  @override
  void didUpdateWidget(covariant _AnimatedReasoningTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isEnergyProgress(oldWidget.progress) !=
            _isEnergyProgress(widget.progress) ||
        _isMaximumProgress(oldWidget.progress) !=
            _isMaximumProgress(widget.progress)) {
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
    for (var index = 0; index < _kMaximumParticleCount; index++) {
      particles.add(_newParticle(initial: true, maximum: false));
    }
  }

  final math.Random _random = math.Random();
  final List<_ReasoningParticle> particles = <_ReasoningParticle>[];
  final List<_ThumbSpark> thumbSparks = <_ThumbSpark>[];
  Duration? _previousElapsed;
  bool _wasMaximum = false;
  double _seconds = 0;
  double _emberAcc = 0;

  /// Soft multi-harmonic glow (0..1) — no obvious reverse loop.
  double glow = 0.55;

  /// Continuous ring rotation angle in radians (always forward).
  double ringAngle = 0;

  void resetClock() {
    _previousElapsed = null;
    _seconds = 0;
    _emberAcc = 0;
    glow = 0.55;
    ringAngle = 0;
    _wasMaximum = false;
    thumbSparks.clear();
  }

  void advance(Duration elapsed, {required bool maximum}) {
    final previous = _previousElapsed;
    _previousElapsed = elapsed;
    if (previous == null) return;
    final deltaSeconds = ((elapsed - previous).inMicroseconds / 1000000)
        .clamp(0.001, 0.05)
        .toDouble();
    _seconds += deltaSeconds;

    // Incommensurate sines → seamless organic breath, no hard loop seams.
    glow =
        (0.52 +
                0.24 * math.sin(_seconds * 1.07) +
                0.16 * math.sin(_seconds * 1.91) +
                0.10 * math.sin(_seconds * 0.63))
            .clamp(0.0, 1.0);
    ringAngle =
        (_seconds * math.pi * 2 / _kThumbRingPeriodSeconds) % (math.pi * 2);

    if (maximum && !_wasMaximum) {
      _emitThumbBurst(count: _kThumbBurstCount, speedScale: 1.15);
    }
    _wasMaximum = maximum;

    if (maximum) {
      _emberAcc += deltaSeconds;
      while (_emberAcc >= _kThumbEmberInterval) {
        _emberAcc -= _kThumbEmberInterval + _random.nextDouble() * 0.04;
        _emitThumbBurst(
          count: 1 + _random.nextInt(3),
          speedScale: 0.45 + _random.nextDouble() * 0.35,
        );
      }
      _advanceThumbSparks(deltaSeconds);
    } else {
      _emberAcc = 0;
      if (thumbSparks.isNotEmpty) thumbSparks.clear();
    }

    final activeCount = maximum ? _kMaximumParticleCount : _kBaseParticleCount;
    final speedBoost = maximum ? 1.55 : 1.0;
    final flowBias = maximum ? 0.055 : 0.02;

    for (var index = 0; index < particles.length; index++) {
      final active = index < activeCount;
      final particle = particles[index];
      if (!active) {
        particle.opacity = 0;
        continue;
      }

      particle.life -= deltaSeconds;
      if (particle.life <= 0 ||
          particle.x < -0.1 ||
          particle.x > 1.12 ||
          particle.y < -0.22 ||
          particle.y > 1.22) {
        particles[index] = _newParticle(initial: false, maximum: maximum);
        continue;
      }

      particle.vx += flowBias * deltaSeconds;
      final jitterX = (_random.nextDouble() - 0.5) * (maximum ? 0.55 : 0.32);
      final jitterY = (_random.nextDouble() - 0.5) * (maximum ? 0.72 : 0.46);
      final maxVx = maximum ? 0.22 : 0.13;
      final maxVy = maximum ? 0.28 : 0.2;
      particle.vx = (particle.vx + jitterX * deltaSeconds)
          .clamp(-maxVx * 0.45, maxVx)
          .toDouble();
      particle.vy = (particle.vy + jitterY * deltaSeconds)
          .clamp(-maxVy, maxVy)
          .toDouble();
      final damping = math.pow(maximum ? 0.78 : 0.72, deltaSeconds).toDouble();
      particle.vx *= damping;
      particle.vy *= damping;
      particle.x += particle.vx * deltaSeconds * speedBoost;
      particle.y += particle.vy * deltaSeconds * speedBoost;
      particle.age += deltaSeconds;
      final opacityFloor = switch (particle.kind) {
        _ParticleKind.dust => 0.22,
        _ParticleKind.spark => 0.38,
        _ParticleKind.flare => 0.5,
      };
      final opacityCeil = switch (particle.kind) {
        _ParticleKind.dust => 0.78,
        _ParticleKind.spark => 0.96,
        _ParticleKind.flare => 1.0,
      };
      particle.opacity =
          (particle.opacity +
                  (_random.nextDouble() - 0.45) * deltaSeconds * 1.15)
              .clamp(opacityFloor, opacityCeil)
              .toDouble();
    }
    notifyListeners();
  }

  void _emitThumbBurst({required int count, required double speedScale}) {
    final room = _kMaxThumbSparks - thumbSparks.length;
    if (room <= 0) return;
    final emit = math.min(count, room);
    for (var i = 0; i < emit; i++) {
      final angle = _random.nextDouble() * math.pi * 2;
      final speed = (95 + _random.nextDouble() * 150) * speedScale; // px/s
      final life = 0.35 + _random.nextDouble() * 0.55;
      thumbSparks.add(
        _ThumbSpark(
          angle: angle,
          dist: _kReasoningThumbRadius * (0.55 + _random.nextDouble() * 0.25),
          speed: speed,
          life: life,
          maxLife: life,
          radius: 1.1 + _random.nextDouble() * 2.4,
          colorIndex: _random.nextInt(
            _MaximumEffortPalette.particleColors.length,
          ),
          streak: 0.35 + _random.nextDouble() * 0.85,
        ),
      );
    }
  }

  void _advanceThumbSparks(double deltaSeconds) {
    final drag = math.pow(0.18, deltaSeconds).toDouble();
    for (var i = thumbSparks.length - 1; i >= 0; i--) {
      final spark = thumbSparks[i];
      spark.life -= deltaSeconds;
      if (spark.life <= 0 || spark.dist > _kThumbSparkMaxDist) {
        thumbSparks.removeAt(i);
        continue;
      }
      spark.dist += spark.speed * deltaSeconds;
      spark.speed *= drag;
      // Slight angular drift for organic scatter.
      spark.angle += (_random.nextDouble() - 0.5) * deltaSeconds * 1.4;
    }
  }

  _ReasoningParticle _newParticle({
    required bool initial,
    required bool maximum,
  }) {
    final roll = _random.nextDouble();
    final kind = !maximum
        ? (roll < 0.72 ? _ParticleKind.dust : _ParticleKind.spark)
        : roll < 0.52
        ? _ParticleKind.dust
        : roll < 0.86
        ? _ParticleKind.spark
        : _ParticleKind.flare;

    final (minR, maxR) = switch (kind) {
      _ParticleKind.dust => (0.55, 1.35),
      _ParticleKind.spark => (1.15, 2.35),
      _ParticleKind.flare => (2.1, 3.6),
    };

    return _ReasoningParticle(
      x: _random.nextDouble(),
      y: 0.1 + _random.nextDouble() * 0.8,
      vx: (_random.nextDouble() - 0.28) * (maximum ? 0.12 : 0.075),
      vy: (_random.nextDouble() - 0.5) * (maximum ? 0.16 : 0.11),
      radius: minR + _random.nextDouble() * (maxR - minR),
      opacity: initial
          ? 0.4 + _random.nextDouble() * 0.5
          : 0.22 + _random.nextDouble() * 0.2,
      age: initial ? 0.35 + _random.nextDouble() * 1.3 : 0,
      life: switch (kind) {
        _ParticleKind.dust => 1.4 + _random.nextDouble() * 3.8,
        _ParticleKind.spark => 1.1 + _random.nextDouble() * 2.8,
        _ParticleKind.flare => 0.7 + _random.nextDouble() * 1.6,
      },
      kind: kind,
      colorIndex: _random.nextInt(_MaximumEffortPalette.particleColors.length),
      spill:
          maximum && kind != _ParticleKind.dust && _random.nextDouble() < 0.35,
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
    required this.kind,
    required this.colorIndex,
    required this.spill,
  });

  double x;
  double y;
  double vx;
  double vy;
  final double radius;
  double opacity;
  double age;
  double life;
  final _ParticleKind kind;
  final int colorIndex;

  /// When true, may render slightly outside the track clip (spark overflow).
  final bool spill;
}

/// Radial ember / burst spark emitted from the max-tier thumb.
class _ThumbSpark {
  _ThumbSpark({
    required this.angle,
    required this.dist,
    required this.speed,
    required this.life,
    required this.maxLife,
    required this.radius,
    required this.colorIndex,
    required this.streak,
  });

  double angle;
  double dist;
  double speed;
  double life;
  final double maxLife;
  final double radius;
  final int colorIndex;
  final double streak;
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
      kOpenHandPillRadius,
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
    final glow = isMaximum ? particles.glow : 0.0;
    const maxStops = _MaximumEffortPalette.gradientStops;

    if (activeRight > left) {
      final activeRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          left,
          centerY - _kReasoningTrackHalfHeight,
          activeRight,
          centerY + _kReasoningTrackHalfHeight,
        ),
        kOpenHandPillRadius,
      );
      final fillColors = isMaximum
          ? maxStops
          : <Color>[
              primaryColor,
              Color.lerp(primaryColor, tertiaryColor, progress)!,
              if (_isEnergyProgress(progress)) secondaryColor,
            ];

      if (isMaximum) {
        final bloomRect = RRect.fromRectAndRadius(
          Rect.fromLTRB(
            left - 2,
            centerY - _kReasoningTrackHalfHeight - 3 - glow * 2.5,
            activeRight + 2,
            centerY + _kReasoningTrackHalfHeight + 3 + glow * 2.5,
          ),
          kOpenHandPillRadius,
        );
        canvas.drawRRect(
          bloomRect,
          Paint()
            ..shader = LinearGradient(
              colors: <Color>[
                _MaximumEffortPalette.royalBlue.withValues(
                  alpha: 0.22 + glow * 0.2,
                ),
                _MaximumEffortPalette.electric.withValues(
                  alpha: 0.18 + glow * 0.22,
                ),
              ],
            ).createShader(bloomRect.outerRect)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + glow * 6),
        );
        canvas.drawRRect(
          activeRect,
          Paint()
            ..shader = LinearGradient(
              colors: maxStops
                  .map((c) => c.withValues(alpha: 0.48 + glow * 0.2))
                  .toList(growable: false),
            ).createShader(activeRect.outerRect)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }

      canvas.drawRRect(
        activeRect,
        Paint()
          ..shader = LinearGradient(
            colors: fillColors,
          ).createShader(activeRect.outerRect),
      );

      // Soft top-edge specular — static, color-matched; no gray sweep band.
      if (isMaximum) {
        final specular = Rect.fromLTRB(
          left,
          centerY - _kReasoningTrackHalfHeight,
          activeRight,
          centerY - _kReasoningTrackHalfHeight + 7,
        );
        canvas.save();
        canvas.clipRRect(activeRect);
        canvas.drawRect(
          specular,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                _MaximumEffortPalette.ice.withValues(alpha: 0.12 + glow * 0.06),
                _MaximumEffortPalette.electric.withValues(alpha: 0),
              ],
            ).createShader(specular),
        );
        canvas.restore();
      }
    }

    // Intermediate ticks only (Codex-style): skip head/tail so rounded
    // track caps stay clean — no ugly endpoint dots on either end.
    final safeDivisions = math.max(1, divisions);
    if (safeDivisions >= 2) {
      for (var index = 1; index < safeDivisions; index++) {
        final tickProgress = index / safeDivisions;
        // Align with thumb travel path (inset from capsule ends).
        final x = thumbLeft + (thumbRight - thumbLeft) * tickProgress;
        final active = tickProgress <= progress + 0.001;
        canvas.drawCircle(
          Offset(x, centerY),
          active ? 2.4 : 2.1,
          Paint()
            ..color = active
                ? (isMaximum
                      ? _MaximumEffortPalette.platinum.withValues(
                          alpha: 0.58 + glow * 0.12,
                        )
                      : Colors.white.withValues(alpha: 0.55))
                : outlineColor.withValues(alpha: 0.42),
        );
      }
    }

    if (_isEnergyProgress(progress)) {
      _paintParticles(
        canvas: canvas,
        trackRect: trackRect,
        left: left,
        centerY: centerY,
        activeRight: activeRight,
        isMaximum: isMaximum,
        glow: glow,
      );
    }

    final thumbCenter = Offset(thumbX, centerY);
    if (isMaximum) {
      _paintThumbSparks(canvas, thumbCenter);
    }
    _paintThumb(canvas, thumbCenter, isMaximum, glow);
  }

  void _paintParticles({
    required Canvas canvas,
    required RRect trackRect,
    required double left,
    required double centerY,
    required double activeRight,
    required bool isMaximum,
    required double glow,
  }) {
    final energy =
        ((progress - _kEnergyParticleThreshold) /
                (1 - _kEnergyParticleThreshold))
            .clamp(0.0, 1.0);
    final particleRight = math.max(left, activeRight - 3);
    final activeCount = isMaximum
        ? _kMaximumParticleCount
        : _kBaseParticleCount;

    void drawOne(_ReasoningParticle particle, {required bool clipped}) {
      if (particle.opacity <= 0.01) return;
      if (clipped && particle.spill) return;
      if (!clipped && !particle.spill) return;

      final x = left + (particleRight - left) * particle.x;
      final y = centerY - 11 + particle.y * 22;
      final fadeIn = (particle.age / 0.32).clamp(0.0, 1.0);
      final fadeOut = (particle.life / 0.45).clamp(0.0, 1.0);
      final alpha =
          (particle.opacity *
                  fadeIn *
                  fadeOut *
                  energy *
                  (isMaximum ? 0.88 + glow * 0.2 : 0.85) *
                  (clipped ? 1.0 : 0.55))
              .clamp(0.0, 1.0);
      if (alpha < 0.02) return;

      final color = isMaximum
          ? _MaximumEffortPalette.particleColors[particle.colorIndex %
                _MaximumEffortPalette.particleColors.length]
          : Colors.white;
      final radius =
          particle.radius *
          (isMaximum ? 1.0 + glow * 0.12 : 1.0) *
          (clipped ? 1.0 : 0.85);
      final center = Offset(x, y);

      // Soft bloom under spark / flare.
      if (particle.kind != _ParticleKind.dust) {
        final bloomScale = particle.kind == _ParticleKind.flare ? 2.8 : 2.1;
        canvas.drawCircle(
          center,
          radius * bloomScale,
          Paint()
            ..color = color.withValues(alpha: alpha * 0.28)
            ..maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              particle.kind == _ParticleKind.flare ? 4.5 : 2.6,
            ),
        );
      }

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..maskFilter = particle.kind == _ParticleKind.dust
              ? null
              : const MaskFilter.blur(BlurStyle.normal, 0.8),
      );

      // Bright core for flares.
      if (particle.kind == _ParticleKind.flare) {
        canvas.drawCircle(
          center,
          radius * 0.38,
          Paint()..color = Colors.white.withValues(alpha: alpha * 0.9),
        );
        // Tiny cross sparkle.
        final arm = radius * 1.6;
        final sparkPaint = Paint()
          ..color = Colors.white.withValues(alpha: alpha * 0.55)
          ..strokeWidth = 0.9
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(center.dx - arm, center.dy),
          Offset(center.dx + arm, center.dy),
          sparkPaint,
        );
        canvas.drawLine(
          Offset(center.dx, center.dy - arm),
          Offset(center.dx, center.dy + arm),
          sparkPaint,
        );
      }
    }

    // Clipped layer inside the track.
    canvas.save();
    canvas.clipRRect(trackRect);
    for (var index = 0; index < activeCount; index++) {
      drawOne(particles.particles[index], clipped: true);
    }
    canvas.restore();

    // Unclipped overflow sparks around the track at max.
    if (isMaximum) {
      for (var index = 0; index < activeCount; index++) {
        drawOne(particles.particles[index], clipped: false);
      }
    }
  }

  void _paintThumbSparks(Canvas canvas, Offset center) {
    for (final spark in particles.thumbSparks) {
      final lifeT = (spark.life / spark.maxLife).clamp(0.0, 1.0);
      // Ease-out fade so sparks die softly, not pop off.
      final fade = kOpenHandSwitchInCurve.transform(lifeT);
      final color =
          _MaximumEffortPalette.particleColors[spark.colorIndex %
              _MaximumEffortPalette.particleColors.length];
      final dx = math.cos(spark.angle) * spark.dist;
      final dy = math.sin(spark.angle) * spark.dist;
      final pos = center + Offset(dx, dy);
      final alpha = (0.15 + fade * 0.85).clamp(0.0, 1.0);

      // Soft bloom
      canvas.drawCircle(
        pos,
        spark.radius * 2.4,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );

      // Streak along radial direction (fireworks trail).
      final trail = spark.radius * (2.2 + spark.streak * 3.5) * fade;
      final tail = Offset(
        pos.dx - math.cos(spark.angle) * trail,
        pos.dy - math.sin(spark.angle) * trail,
      );
      canvas.drawLine(
        tail,
        pos,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.72)
          ..strokeWidth = math.max(0.8, spark.radius * 0.55)
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
      );

      // Hot core
      canvas.drawCircle(
        pos,
        spark.radius * (0.55 + fade * 0.45),
        Paint()..color = Colors.white.withValues(alpha: alpha * 0.92),
      );
    }
  }

  void _paintThumb(Canvas canvas, Offset center, bool isMaximum, double glow) {
    if (isMaximum) {
      // Soft multi-layer aura — continuous multi-harmonic glow, no hard pulse.
      canvas.drawCircle(
        center,
        _kReasoningThumbRadius + 10 + glow * 3,
        Paint()
          ..color = _MaximumEffortPalette.electric.withValues(
            alpha: 0.1 + glow * 0.12,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 + glow * 4),
      );
      canvas.drawCircle(
        center,
        _kReasoningThumbRadius + 5 + glow * 1.5,
        Paint()
          ..color = _MaximumEffortPalette.royalBlue.withValues(
            alpha: 0.14 + glow * 0.1,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 + glow * 2.5),
      );
    }

    // Porcelain disc with subtle cool tint edge via outer soft ring.
    canvas.drawCircle(
      center,
      _kReasoningThumbRadius,
      Paint()..color = Colors.white,
    );

    if (isMaximum) {
      // Continuous forward-rotating prestige ring (linear time, seamless).
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..shader =
            SweepGradient(
              startAngle: particles.ringAngle,
              endAngle: particles.ringAngle + math.pi * 2,
              colors: _MaximumEffortPalette.sweepRing,
              stops: const <double>[0, 0.28, 0.52, 0.78, 1],
            ).createShader(
              Rect.fromCircle(center: center, radius: _kReasoningThumbRadius),
            );
      canvas.drawCircle(center, _kReasoningThumbRadius, ringPaint);

      // Quiet inner ice rim — stable alpha, slightly breathing with glow.
      canvas.drawCircle(
        center,
        _kReasoningThumbRadius - 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = _MaximumEffortPalette.ice.withValues(
            alpha: 0.28 + glow * 0.16,
          ),
      );
    } else {
      canvas.drawCircle(
        center,
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
