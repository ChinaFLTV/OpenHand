import 'package:flutter/widgets.dart';

import '../../app/model/dialog_animation_settings.dart';
import 'animated_dialog.dart';
import 'bounded_animation.dart';
import 'motion_preference.dart';

/// Reusable enter/exit animation wrapper that consumes a
/// [DialogAnimationSettings] (the same struct that drives dialogs,
/// panels, menus, and pages) and re-uses the shared transition library
/// from [buildAnimationStyleTransition].
///
/// Behaviour:
/// - On first build, plays the [DialogAnimationSettings.entranceStyle]
///   forward.
/// - When [present] flips from `true` → `false`, plays the
///   [DialogAnimationSettings.exitStyle] in reverse, then invokes
///   [onDismissed] (typically used by the parent to remove this entry
///   from its data list, which makes the widget unmount on the next
///   rebuild).
/// - When [present] flips from `false` → `true` (resurrection /
///   re-add), plays the entrance again.
/// - When [collapseSize] is true (default), the widget is wrapped in a
///   [SizeTransition] that smoothly collapses the layout slot during
///   exit so neighbours flow into place rather than jumping.
///
/// Safe under `LayoutBuilder` / sliver contexts because the underlying
/// transitions in [buildAnimationStyleTransition] use only
/// [FadeTransition] / [SlideTransition] / [Opacity] / [Transform]
/// composed at paint-time.
enum AnimatedAppearancePhase { enter, exit }

class AnimatedAppearance extends StatefulWidget {
  const AnimatedAppearance({
    super.key,
    required this.child,
    required this.settings,
    this.present = true,
    this.onDismissed,
    this.collapseSize = true,
    this.collapseAxis = Axis.vertical,
    this.collapseAxisAlignment = -1.0,
  });

  final Widget child;
  final DialogAnimationSettings settings;
  final bool present;

  /// Called once the exit animation completes. Use this to remove the
  /// associated data entry from a list. Not called when the widget is
  /// disposed before the animation finishes (e.g. parent unmounts).
  final VoidCallback? onDismissed;

  /// When true, also collapses the widget's layout slot during exit /
  /// expands it during entrance — so neighbour items reflow smoothly.
  final bool collapseSize;

  /// Axis along which [collapseSize] collapses. Default vertical.
  final Axis collapseAxis;

  /// Alignment along the collapse axis (-1 = top/leading,
  /// 0 = center, 1 = bottom/trailing). Defaults to leading so a chip
  /// removed from a `Wrap` collapses leftward into the row.
  final double collapseAxisAlignment;

  @override
  State<AnimatedAppearance> createState() => _AnimatedAppearanceState();
}

class _AnimatedAppearanceState extends State<AnimatedAppearance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _dismissCallbackQueued = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.settings.duration,
      reverseDuration: widget.settings.duration,
      value: widget.present ? 0.0 : 1.0,
    );
    _ctrl.addStatusListener(_onStatus);
    if (widget.present) {
      _ctrl.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_motionAvailable(context)) {
      _ctrl
        ..stop()
        ..value = widget.present ? 1.0 : 0.0;
      if (!widget.present) {
        _notifyDismissedSoon();
      }
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.present) {
      _notifyDismissedNow();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedAppearance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settings.duration != oldWidget.settings.duration) {
      _ctrl.duration = widget.settings.duration;
      _ctrl.reverseDuration = widget.settings.duration;
    }
    if (widget.present != oldWidget.present) {
      if (widget.present) {
        _dismissCallbackQueued = false;
      }
      if (!_motionAvailable(context)) {
        _ctrl
          ..stop()
          ..value = widget.present ? 1.0 : 0.0;
        if (!widget.present) {
          _notifyDismissedSoon();
        }
        return;
      }
      if (widget.present) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  bool _motionAvailable(BuildContext context) {
    return openHandTickerMotionEnabled(context) &&
        !openHandMotionDisabled(widget.settings) &&
        widget.settings.duration > Duration.zero;
  }

  void _notifyDismissedSoon() {
    if (_dismissCallbackQueued) return;
    _dismissCallbackQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.present) return;
      widget.onDismissed?.call();
    });
  }

  void _notifyDismissedNow() {
    if (_dismissCallbackQueued) return;
    _dismissCallbackQueued = true;
    widget.onDismissed?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!_motionAvailable(context)) {
      if (!widget.present) {
        _notifyDismissedSoon();
        return const SizedBox.shrink();
      }
      return widget.child;
    }
    Widget content = buildAnimationStyleTransition(
      animation: _ctrl,
      settings: widget.settings,
      child: widget.child,
    );
    if (widget.collapseSize) {
      content = SizeTransition(
        sizeFactor: openHandBoundedCurveAnimation(
          parent: _ctrl,
          curve: widget.settings.curve.curve,
          reverseCurve: widget.settings.curve.reverseCurve,
        ),
        axis: widget.collapseAxis,
        axisAlignment: widget.collapseAxisAlignment,
        child: content,
      );
    }
    return content;
  }
}

/// Convenience: a chip-style removable wrapper. Owns its `present`
/// flag so the parent only has to provide a stable `key` and an
/// `onRemove` callback that mutates the data list. The `child`
/// builder receives a `requestRemove` callback to wire to the chip's
/// X button — calling it triggers the exit animation, then
/// `onRemove` once the animation completes.
class AnimatedListAppearance extends StatelessWidget {
  const AnimatedListAppearance({
    super.key,
    required this.animation,
    required this.settings,
    required this.phase,
    required this.child,
    this.collapseSize = true,
    this.collapseAxis = Axis.vertical,
    this.collapseAxisAlignment = -1.0,
  });

  final Animation<double> animation;
  final DialogAnimationSettings settings;
  final AnimatedAppearancePhase phase;
  final Widget child;
  final bool collapseSize;
  final Axis collapseAxis;
  final double collapseAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final effectiveSettings = openHandReduceMotionOf(context)
        ? OpenHandMotionDefaults.disabled
        : settings;
    final style = switch (phase) {
      AnimatedAppearancePhase.enter => effectiveSettings.entranceStyle,
      AnimatedAppearancePhase.exit => effectiveSettings.exitStyle,
    };
    final transitionSettings = effectiveSettings.copyWith(
      entranceStyle: style,
      exitStyle: style,
    );
    Widget content = buildAnimationStyleTransition(
      animation: animation,
      settings: transitionSettings,
      child: child,
    );
    if (collapseSize) {
      content = SizeTransition(
        sizeFactor: openHandBoundedCurveAnimation(
          parent: animation,
          curve: transitionSettings.curve.curve,
          reverseCurve: transitionSettings.curve.reverseCurve,
        ),
        axis: collapseAxis,
        axisAlignment: collapseAxisAlignment,
        child: content,
      );
    }
    return content;
  }
}

class AnimatedRemovableChip extends StatefulWidget {
  const AnimatedRemovableChip({
    super.key,
    required this.settings,
    required this.onRemove,
    required this.builder,
    this.collapseAxis = Axis.horizontal,
  });

  final DialogAnimationSettings settings;
  final VoidCallback onRemove;
  final Widget Function(BuildContext context, VoidCallback requestRemove)
  builder;
  final Axis collapseAxis;

  @override
  State<AnimatedRemovableChip> createState() => _AnimatedRemovableChipState();
}

class _AnimatedRemovableChipState extends State<AnimatedRemovableChip> {
  bool _present = true;

  void _requestRemove() {
    if (!_present) return;
    setState(() => _present = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedAppearance(
      settings: widget.settings,
      present: _present,
      collapseAxis: widget.collapseAxis,
      onDismissed: widget.onRemove,
      child: widget.builder(context, _requestRemove),
    );
  }
}
