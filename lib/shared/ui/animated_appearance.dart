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
/// 动态列表默认使用 [kOpenHandLayoutSafeTransitionProfile]，尺寸变化期间不会
/// 创建依赖布局状态的 `RenderFractionalTranslation`。
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
    this.transitionProfile = kOpenHandLayoutSafeTransitionProfile,
    this.keepContentVisibleDuringExitCollapse = false,
  }) : assert(!keepContentVisibleDuringExitCollapse || collapseSize);

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

  final OpenHandAnimationTransitionProfile transitionProfile;

  /// 退出时仅收缩布局槽并保持内容可见，避免透明内容继续占位。
  final bool keepContentVisibleDuringExitCollapse;

  @override
  State<AnimatedAppearance> createState() => _AnimatedAppearanceState();
}

class _AnimatedAppearanceState extends State<AnimatedAppearance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _dismissCallbackQueued = false;
  bool _suppressImmediateDismissCallback = false;
  int _dismissCallbackGeneration = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.settings.entranceDuration,
      reverseDuration: widget.settings.exitDuration,
      value: 0.0,
    );
    _ctrl.addStatusListener(_onStatus);
    if (widget.present) {
      if (widget.settings.entranceDisabled) {
        _showImmediately();
      } else {
        _ctrl.forward();
      }
    } else {
      // A node that starts absent was never presented, so making it flash in
      // merely to play an exit would violate the meaning of [present].
      _dismissImmediately();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_directionMotionAvailable(context, entering: widget.present)) {
      widget.present ? _showImmediately() : _dismissImmediately();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (!_suppressImmediateDismissCallback &&
        status == AnimationStatus.dismissed &&
        !widget.present) {
      _notifyDismissedNow();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedAppearance oldWidget) {
    super.didUpdateWidget(oldWidget);
    final durationsChanged =
        widget.settings.entranceDuration !=
            oldWidget.settings.entranceDuration ||
        widget.settings.exitDuration != oldWidget.settings.exitDuration;
    if (durationsChanged) {
      _ctrl.duration = widget.settings.entranceDuration;
      _ctrl.reverseDuration = widget.settings.exitDuration;
    }
    if (widget.present && !oldWidget.present) {
      _cancelPendingDismissCallback();
    }
    if (!_directionMotionAvailable(context, entering: widget.present)) {
      widget.present ? _showImmediately() : _dismissImmediately();
      return;
    }
    if (widget.present != oldWidget.present) {
      if (widget.present) {
        _ctrl.forward();
      } else {
        _startExit();
      }
    } else if (durationsChanged) {
      // AnimationController snapshots the duration when a simulation starts;
      // restart from the current value so a live preference change takes
      // effect instead of waiting out the stale duration.
      if (widget.present && !_ctrl.isCompleted) {
        _ctrl.forward();
      } else if (!widget.present && !_ctrl.isDismissed) {
        _startExit();
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
    return _animatedAppearanceMotionAvailable(context, widget.settings);
  }

  bool _directionMotionAvailable(
    BuildContext context, {
    required bool entering,
  }) {
    if (!_motionAvailable(context)) return false;
    return entering
        ? !widget.settings.entranceDisabled
        : !widget.settings.exitDisabled;
  }

  void _showImmediately() {
    _ctrl
      ..stop()
      ..value = 1.0;
  }

  void _dismissImmediately() {
    _suppressImmediateDismissCallback = true;
    _ctrl
      ..stop()
      ..value = 0.0;
    _suppressImmediateDismissCallback = false;
    _notifyDismissedSoon();
  }

  void _startExit() {
    if (_ctrl.value <= _ctrl.lowerBound) {
      _dismissImmediately();
    } else {
      _ctrl.reverse();
    }
  }

  void _cancelPendingDismissCallback() {
    _dismissCallbackGeneration += 1;
    _dismissCallbackQueued = false;
  }

  void _notifyDismissedSoon() {
    if (_dismissCallbackQueued) return;
    _dismissCallbackQueued = true;
    final generation = ++_dismissCallbackGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.present ||
          generation != _dismissCallbackGeneration) {
        return;
      }
      widget.onDismissed?.call();
    });
  }

  void _notifyDismissedNow() {
    if (_dismissCallbackQueued) return;
    _dismissCallbackQueued = true;
    _dismissCallbackGeneration += 1;
    widget.onDismissed?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.present && _ctrl.isDismissed) {
      _notifyDismissedSoon();
      return const SizedBox.shrink();
    }
    if (!_directionMotionAvailable(context, entering: widget.present)) {
      if (!widget.present) {
        _notifyDismissedSoon();
        return const SizedBox.shrink();
      }
      return widget.child;
    }
    Widget content =
        !widget.present && widget.keepContentVisibleDuringExitCollapse
        ? widget.child
        : buildAnimationStyleTransition(
            animation: _ctrl,
            settings: widget.settings,
            profile: widget.transitionProfile,
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

bool _animatedAppearanceMotionAvailable(
  BuildContext context,
  DialogAnimationSettings settings,
) {
  return openHandTickerMotionEnabled(context) &&
      !openHandMotionDisabled(settings) &&
      settings.duration > Duration.zero;
}

/// 可移除胶囊动效封装：先播放退场动画，再调用 [onRemove] 更新数据源。
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
