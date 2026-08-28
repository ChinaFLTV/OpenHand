import 'package:flutter/widgets.dart';

import '../../app/model/dialog_animation_settings.dart';
import 'animated_dialog.dart';
import 'bounded_animation.dart';
import 'motion_preference.dart';

/// 复用全局弹窗设置的进退场动画；隐藏后回调 [onDismissed]，重新显示时重播进场。
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

  /// 退场完成后调用；提前释放组件时不调用。
  final VoidCallback? onDismissed;

  /// 是否在进退场期间同步展开或收缩布局槽。
  final bool collapseSize;

  /// 布局槽收缩方向。
  final Axis collapseAxis;

  /// 收缩轴对齐方式：-1 为起点，0 为居中，1 为终点。
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
      // 初始隐藏的节点直接保持隐藏，避免为退场而闪现。
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
      // 从当前进度重启动画，让运行时修改的时长立即生效。
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
