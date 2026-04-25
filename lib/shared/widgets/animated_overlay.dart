import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';

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
  });

  final Widget child;

  /// If true, reads animation settings from [SettingsController.menuAnimationSettings].
  /// If false, uses quick default animations (150ms, easeOutCubic).
  final bool useMenuSettings;

  /// Override the animation duration.
  final Duration? customDuration;

  /// Override the animation curve.
  final Curve? customCurve;

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
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _controller.forward();
  }

  void _initAnimations() {
    final Duration duration;
    final Curve curve;

    if (widget.useMenuSettings) {
      // Try to get settings from context if available.
      // Since initState doesn't have access to context with inherited widgets yet,
      // we use default values and update in didChangeDependencies if needed.
      duration = widget.customDuration ?? const Duration(milliseconds: 200);
      curve = widget.customCurve ?? Curves.easeOutCubic;
    } else {
      duration = widget.customDuration ?? const Duration(milliseconds: 150);
      curve = widget.customCurve ?? Curves.easeOutCubic;
    }

    _controller = AnimationController(vsync: this, duration: duration);

    _fadeAnimation = CurvedAnimation(parent: _controller, curve: curve);

    _scaleAnimation = Tween<double>(
      begin: widget.scaleBegin,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: curve));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.useMenuSettings &&
        widget.customDuration == null &&
        _controller.duration != null) {
      // Update duration from settings if available.
      try {
        final settings = context
            .read<SettingsController>()
            .menuAnimationSettings;
        if (settings.entranceStyle != DialogAnimationStyle.none) {
          final newDuration = settings.duration;
          if (_controller.duration != newDuration && !_controller.isAnimating) {
            _controller.duration = newDuration;
          }
        }
      } catch (_) {
        // SettingsController not available, use defaults.
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget result = FadeTransition(
      opacity: _fadeAnimation,
      child: widget.child,
    );

    if (widget.enableScaleAnimation) {
      result = ScaleTransition(scale: _scaleAnimation, child: result);
    }

    return result;
  }
}

/// A simpler variant that only provides fade animation for very lightweight
/// overlays like file stat popups.
class FadeInOverlayContent extends StatefulWidget {
  const FadeInOverlayContent({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 120),
    this.curve = Curves.easeOut,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;

  @override
  State<FadeInOverlayContent> createState() => _FadeInOverlayContentState();
}

class _FadeInOverlayContentState extends State<FadeInOverlayContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = CurvedAnimation(parent: _controller, curve: widget.curve);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _animation, child: widget.child);
  }
}
