import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';
import 'animated_dialog.dart';
import 'motion_preference.dart';

const double _kDefaultOverlayScaleBegin = 0.95;
const double _kMinOverlayScaleBegin = 0.5;
const double _kMaxOverlayScaleBegin = 1.0;

/// Builds one animated overlay entry owned by an
/// [AnimatedOverlayEntryController].
///
/// The supplied visibility signal and exit callback should be forwarded to
/// [AnimatedOverlayContent].
typedef AnimatedOverlayEntryBuilder =
    Widget Function(
      BuildContext context,
      ValueListenable<bool> visibility,
      VoidCallback onExitCompleted,
    );

/// Owns an [OverlayEntry] and its animated visibility signal as one resource.
///
/// Calling [show] while an exit is in flight reopens the same entry. [close]
/// reverses its transition, while [dispose] removes it synchronously. Late
/// completion callbacks are guarded by both session identity and generation,
/// so they cannot remove a replacement entry.
class AnimatedOverlayEntryController {
  _AnimatedOverlayEntrySession? _session;
  int _generation = 0;
  bool _disposed = false;

  bool get hasEntry => _session != null;

  /// Reopens the current entry without creating a replacement.
  bool reopen({bool rebuild = false}) {
    if (_disposed) return false;
    final session = _session;
    if (session == null) return false;
    if (!session.visibility.value) {
      session.visibility.value = true;
    }
    if (rebuild) {
      session.entry.markNeedsBuild();
    }
    return true;
  }

  /// Inserts a new entry, or reopens and rebuilds the current entry.
  ///
  /// Returns false after this controller has been disposed. Insert failures
  /// are rethrown after the controller releases the uninserted session.
  bool show({
    required OverlayState overlay,
    required AnimatedOverlayEntryBuilder builder,
    VoidCallback? onRemoved,
    bool rebuildIfPresent = true,
  }) {
    if (_disposed) return false;
    final current = _session;
    if (current != null) {
      current.builder = builder;
      current.onRemoved = onRemoved;
      reopen();
      if (rebuildIfPresent) {
        current.entry.markNeedsBuild();
      }
      return true;
    }

    final session = _AnimatedOverlayEntrySession(
      generation: ++_generation,
      builder: builder,
      onRemoved: onRemoved,
    );
    session.onExitCompleted = () => _completeExit(session);
    session.entry = OverlayEntry(
      builder: (context) =>
          session.builder(context, session.visibility, session.onExitCompleted),
    );
    _session = session;
    try {
      overlay.insert(session.entry);
    } catch (_) {
      if (identical(_session, session)) {
        _session = null;
        _generation += 1;
      }
      session.entry.dispose();
      session.visibility.dispose();
      rethrow;
    }
    return true;
  }

  /// Rebuilds the current entry without changing its visibility.
  void markNeedsBuild() => _session?.entry.markNeedsBuild();

  /// Starts the reverse transition, or removes the entry synchronously when
  /// [immediately] is true. Repeated calls are safe.
  void close({bool immediately = false}) {
    final session = _session;
    if (session == null) return;
    if (immediately || _disposed) {
      _removeSession(session);
      return;
    }
    if (session.visibility.value) {
      session.visibility.value = false;
    }
  }

  void _completeExit(_AnimatedOverlayEntrySession session) {
    if (_disposed ||
        !identical(_session, session) ||
        session.generation != _generation ||
        session.visibility.value) {
      return;
    }
    _removeSession(session);
  }

  void _removeSession(_AnimatedOverlayEntrySession session) {
    if (!identical(_session, session) || session.generation != _generation) {
      return;
    }
    _session = null;
    _generation += 1;
    session.entry.remove();
    session.entry.dispose();
    session.visibility.dispose();
    session.onRemoved?.call();
  }

  /// Permanently releases the owned entry. Repeated calls are safe.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final session = _session;
    if (session != null) {
      _removeSession(session);
    } else {
      _generation += 1;
    }
  }
}

class _AnimatedOverlayEntrySession {
  _AnimatedOverlayEntrySession({
    required this.generation,
    required this.builder,
    required this.onRemoved,
  });

  final int generation;
  final ValueNotifier<bool> visibility = ValueNotifier<bool>(true);
  AnimatedOverlayEntryBuilder builder;
  VoidCallback? onRemoved;
  late final OverlayEntry entry;
  late final VoidCallback onExitCompleted;
}

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
    this.useMenuSettings = true,
    this.customDuration,
    this.customCurve,
    this.enableScaleAnimation = true,
    this.scaleBegin = _kDefaultOverlayScaleBegin,
    this.alignment = Alignment.center,
    this.customSettings,
    this.visibility,
    this.onExitCompleted,
  });

  final Widget child;

  /// 是否读取 [SettingsController.menuAnimationSettings]。
  /// 默认读取全局菜单动画设置；显式关闭时使用快速默认动画。
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

  final Alignment alignment;

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
  SettingsController? _settingsController;
  bool _exitCompletionScheduled = false;
  bool _exitCompletionDelivered = false;
  int _exitCompletionGeneration = 0;

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
    _bindSettingsController();
    _syncAnimationPreference();
  }

  @override
  void didUpdateWidget(covariant AnimatedOverlayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindSettingsController();
    if (oldWidget.visibility != widget.visibility) {
      oldWidget.visibility?.removeListener(_handleVisibilityChanged);
      widget.visibility?.addListener(_handleVisibilityChanged);
      _cancelExitCompletion();
      _exitCompletionDelivered = false;
    }
    if (oldWidget.onExitCompleted != widget.onExitCompleted &&
        !_exitCompletionDelivered) {
      // A pending post-frame completion must never retain an obsolete owner.
      // Resetting here makes a dismissed overlay schedule the current callback
      // from [_syncAnimationPreference] below.
      _cancelExitCompletion();
    }
    if (oldWidget.useMenuSettings != widget.useMenuSettings ||
        oldWidget.customDuration != widget.customDuration ||
        oldWidget.customCurve != widget.customCurve ||
        oldWidget.customSettings != widget.customSettings ||
        oldWidget.enableScaleAnimation != widget.enableScaleAnimation ||
        oldWidget.alignment != widget.alignment ||
        oldWidget.visibility != widget.visibility ||
        oldWidget.onExitCompleted != widget.onExitCompleted) {
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

  void _bindSettingsController() {
    final shouldListen = widget.useMenuSettings && widget.customSettings == null;
    SettingsController? nextController;
    if (shouldListen) {
      try {
        nextController = context.read<SettingsController>();
      } on ProviderNotFoundException {
        nextController = null;
      }
    }
    if (identical(_settingsController, nextController)) return;
    _settingsController?.removeListener(_handleSettingsChanged);
    _settingsController = nextController;
    _settingsController?.addListener(_handleSettingsChanged);
  }

  void _handleSettingsChanged() {
    if (!mounted) return;
    final resolved = _resolveSettings();
    final disabled =
        !openHandTickerMotionEnabled(context) || openHandMotionDisabled(resolved);
    if (resolved == _settings && disabled == _animationsDisabled) return;
    setState(_syncAnimationPreference);
  }

  void _syncAnimationPreference() {
    final resolved = _resolveSettings();
    final disabled =
        !openHandTickerMotionEnabled(context) ||
        openHandMotionDisabled(resolved);
    _settings = resolved;
    _animationsDisabled = disabled;
    _controller
      ..duration = resolved.entranceDuration
      ..reverseDuration = resolved.exitDuration;
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
      _cancelExitCompletion();
      _exitCompletionDelivered = false;
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
    if (_exitCompletionScheduled || _exitCompletionDelivered || _isVisible) {
      return;
    }
    final callback = widget.onExitCompleted;
    if (callback == null) return;
    _exitCompletionScheduled = true;
    final generation = ++_exitCompletionGeneration;
    final visibility = widget.visibility;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_exitCompletionScheduled ||
          generation != _exitCompletionGeneration ||
          widget.visibility != visibility) {
        return;
      }
      if (!_isVisible) {
        _exitCompletionScheduled = false;
        _exitCompletionDelivered = true;
        callback();
      } else {
        _cancelExitCompletion();
      }
    });
    // A disabled transition has no ticker to request another frame. Ensure
    // the post-frame completion still runs so the entry cannot get stuck.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _cancelExitCompletion() {
    _exitCompletionScheduled = false;
    _exitCompletionGeneration += 1;
  }

  @override
  void dispose() {
    widget.visibility?.removeListener(_handleVisibilityChanged);
    _settingsController?.removeListener(_handleSettingsChanged);
    _controller.removeStatusListener(_handleAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  OpenHandAnimationTransitionProfile _transitionProfile() {
    final scaleBegin = _safeOverlayScaleBegin(widget.scaleBegin);
    return OpenHandAnimationTransitionProfile(
      alignment: widget.alignment,
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
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => buildAnimationStyleTransition(
        animation: _controller,
        settings: _settings,
        profile: _transitionProfile(),
        curveOverride: widget.customCurve,
        reverseCurveOverride: widget.customCurve,
        child: child!,
      ),
    );
  }
}

double _safeOverlayScaleBegin(double value) {
  if (!value.isFinite || value <= 0) return _kDefaultOverlayScaleBegin;
  return value.clamp(_kMinOverlayScaleBegin, _kMaxOverlayScaleBegin).toDouble();
}
