import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/model/dialog_animation_settings.dart';
import 'animated_dialog.dart';
import 'motion_preference.dart';

const double _kDefaultOverlayScaleBegin = 0.95;
const double _kMinOverlayScaleBegin = 0.5;
const double _kMaxOverlayScaleBegin = 1.0;

/// Provides animated entrance and exit effects for overlay content (hover
/// popups, tooltips, autocomplete panels, etc.).
///
/// Wraps child content with configurable fade-in and scale animations that
/// respect global animation settings when [useMenuSettings] is true.
/// Otherwise uses faster default animations suitable for quick popups.
///
/// Pass [visibility] and [onExitCompleted] when the owner removes an
/// [OverlayEntry]. Setting the listenable to false reverses the configured
/// transition first; the callback is invoked only after that transition has
/// finished. This keeps entry ownership with the caller while preventing
/// abrupt removals and duplicated animation-controller plumbing.
class AnimatedOverlayContent extends StatefulWidget {
  const AnimatedOverlayContent({
    super.key,
    required this.child,
    this.useMenuSettings = false,
    this.customDuration,
    this.customCurve,
    this.enableScaleAnimation = true,
    this.scaleBegin = _kDefaultOverlayScaleBegin,
    this.customSettings,
    this.visibility,
    this.onExitCompleted,
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

  /// Optional visibility signal used to coordinate an [OverlayEntry] exit.
  ///
  /// When omitted, the overlay remains visible for its entire lifetime and
  /// only the entrance transition is driven.
  final ValueListenable<bool>? visibility;

  /// Called once after [visibility] changes to false and the reverse
  /// transition completes. The owner should remove and dispose its entry here.
  final VoidCallback? onExitCompleted;

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
  bool _exitCompletionScheduled = false;

  bool get _isVisible => widget.visibility?.value ?? true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener(_handleAnimationStatus);
    widget.visibility?.addListener(_handleVisibilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimationPreference();
  }

  @override
  void didUpdateWidget(covariant AnimatedOverlayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibility != widget.visibility) {
      oldWidget.visibility?.removeListener(_handleVisibilityChanged);
      widget.visibility?.addListener(_handleVisibilityChanged);
      _exitCompletionScheduled = false;
    }
    if (oldWidget.useMenuSettings != widget.useMenuSettings ||
        oldWidget.customDuration != widget.customDuration ||
        oldWidget.customCurve != widget.customCurve ||
        oldWidget.customSettings != widget.customSettings ||
        oldWidget.enableScaleAnimation != widget.enableScaleAnimation ||
        oldWidget.visibility != widget.visibility) {
      _syncAnimationPreference();
    }
  }

  DialogAnimationSettings _resolveSettings() {
    if (widget.customSettings != null) {
      return widget.customSettings!;
    }
    if (widget.useMenuSettings) {
      return openHandMotionSettingsFallbackOf(
        context,
        OpenHandMotionSettingsScope.menu,
      ).copyWith(durationMs: widget.customDuration?.inMilliseconds);
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
        !openHandTickerMotionEnabled(context) ||
        openHandMotionDisabled(resolved);
    _settings = resolved;
    _animationsDisabled = disabled;
    _controller
      ..duration = resolved.duration
      ..reverseDuration = resolved.duration;
    if (disabled) {
      _controller.stop();
      _controller.value = _isVisible ? 1.0 : 0.0;
      if (!_isVisible) {
        _scheduleExitCompletion();
      }
      return;
    }
    _driveVisibility();
  }

  void _handleVisibilityChanged() {
    if (!mounted) return;
    if (_isVisible) {
      _exitCompletionScheduled = false;
    }
    if (_animationsDisabled) {
      _controller.value = _isVisible ? 1.0 : 0.0;
      if (!_isVisible) {
        _scheduleExitCompletion();
      }
      return;
    }
    _driveVisibility();
  }

  void _driveVisibility() {
    if (_isVisible) {
      if (_controller.status != AnimationStatus.completed) {
        _controller.forward();
      }
      return;
    }
    if (_controller.status == AnimationStatus.dismissed) {
      _scheduleExitCompletion();
    } else {
      _controller.reverse();
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_isVisible) {
      _scheduleExitCompletion();
    }
  }

  void _scheduleExitCompletion() {
    if (_exitCompletionScheduled || _isVisible) return;
    final callback = widget.onExitCompleted;
    if (callback == null) return;
    _exitCompletionScheduled = true;
    final visibility = widget.visibility;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_exitCompletionScheduled ||
          widget.visibility != visibility) {
        return;
      }
      if (!_isVisible) {
        callback();
      } else {
        _exitCompletionScheduled = false;
      }
    });
  }

  @override
  void dispose() {
    widget.visibility?.removeListener(_handleVisibilityChanged);
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  OpenHandAnimationTransitionProfile _transitionProfile() {
    final scaleBegin = _safeOverlayScaleBegin(widget.scaleBegin);
    return OpenHandAnimationTransitionProfile(
      fadeScaleBegin: scaleBegin,
      expandScaleBegin: scaleBegin,
      rotateScaleBegin: scaleBegin,
      elasticScaleBegin: scaleBegin,
      springScaleBegin: scaleBegin,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_animationsDisabled) {
      return _isVisible ? widget.child : const SizedBox.shrink();
    }
    return buildAnimationStyleTransition(
      animation: _controller,
      settings: _settings,
      profile: _transitionProfile(),
      curveOverride: widget.customCurve,
      reverseCurveOverride: widget.customCurve,
      child: widget.child,
    );
  }
}

double _safeOverlayScaleBegin(double value) {
  if (!value.isFinite || value <= 0) return _kDefaultOverlayScaleBegin;
  return value.clamp(_kMinOverlayScaleBegin, _kMaxOverlayScaleBegin).toDouble();
}
