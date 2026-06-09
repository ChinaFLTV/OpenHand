import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';
import 'animated_dialog.dart';

/// Provides animated entrance effects for overlay content (hover popups,
/// tooltips, autocomplete panels, etc.).
///
/// Wraps child content with configurable fade-in and scale animations that
/// respect global animation settings when [useMenuSettings] is true.
/// Otherwise uses faster default animations suitable for quick popups.
class AnimatedOverlayContent extends StatefulWidget {
  const AnimatedOverlayContent({
    super.key,
    required this.child,
    this.useMenuSettings = false,
    this.customDuration,
    this.customCurve,
    this.enableScaleAnimation = true,
    this.scaleBegin = 0.95,
    this.customSettings,
  });

  final Widget child;

  /// If true, reads animation settings from [SettingsController.menuAnimationSettings].
  /// If false, uses quick default animations (150ms, easeOutCubic).
  final bool useMenuSettings;

  /// Override the animation duration.
  final Duration? customDuration;

  /// Override the animation curve.
  final Curve? customCurve;

  /// Fully override the resolved animation settings.
  final DialogAnimationSettings? customSettings;

  /// Whether to include scale animation along with fade.
  final bool enableScaleAnimation;

  /// The starting scale value when [enableScaleAnimation] is true.
  final double scaleBegin;

  @override
  State<AnimatedOverlayContent> createState() => _AnimatedOverlayContentState();
}

class _AnimatedOverlayContentState extends State<AnimatedOverlayContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  DialogAnimationSettings _settings = const DialogAnimationSettings(
    durationMs: 150,
  );
  bool _animationsDisabled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimationPreference();
  }

  DialogAnimationSettings _resolveSettings() {
    if (widget.customSettings != null) {
      return widget.customSettings!;
    }
    if (widget.useMenuSettings) {
      try {
        final settings = context
            .read<SettingsController>()
            .menuAnimationSettings;
        return settings.copyWith(
          durationMs: widget.customDuration?.inMilliseconds,
        );
      } catch (_) {
        return OpenHandMotionDefaults.menu.copyWith(
          durationMs: widget.customDuration?.inMilliseconds,
        );
      }
    }
    return DialogAnimationSettings(
      entranceStyle: widget.enableScaleAnimation
          ? DialogAnimationStyle.fadeScale
          : DialogAnimationStyle.fade,
      exitStyle: widget.enableScaleAnimation
          ? DialogAnimationStyle.fadeScale
          : DialogAnimationStyle.fade,
      durationMs: widget.customDuration?.inMilliseconds ?? 150,
    );
  }

  void _syncAnimationPreference() {
    final resolved = _resolveSettings();
    final disabled =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled ||
        (resolved.entranceStyle == DialogAnimationStyle.none &&
            resolved.exitStyle == DialogAnimationStyle.none);
    _settings = resolved;
    _animationsDisabled = disabled;
    _controller
      ..duration = resolved.duration
      ..reverseDuration = resolved.duration;
    if (disabled) {
      _controller.stop();
      _controller.value = 1.0;
    } else if (_controller.value == 0 && !_controller.isAnimating) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_animationsDisabled) {
      return widget.child;
    }
    return buildAnimationStyleTransition(
      animation: _controller,
      settings: _settings,
      curveOverride: widget.customCurve,
      reverseCurveOverride: widget.customCurve,
      child: widget.child,
    );
  }
}

/// A simpler variant that only provides fade animation for very lightweight
/// overlays like file stat popups.
typedef FadeInOverlayContent = AnimatedOverlayContent;
