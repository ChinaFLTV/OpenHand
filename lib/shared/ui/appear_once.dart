import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';
import 'bounded_animation.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';

const Duration _kDefaultAppearDuration = kOpenHandMotion320;
const double _kDefaultAppearSlideOffset = 12.0;

/// 一次性淡入上移动画；完成后释放控制器，保持子树与交互状态。
class AppearOnce extends StatefulWidget {
  const AppearOnce({
    super.key,
    required this.child,
    this.duration = _kDefaultAppearDuration,
    this.slideOffset = _kDefaultAppearSlideOffset,
  });

  final Widget child;
  final Duration duration;

  /// 初始向下偏移的逻辑像素数，终点始终为 0。
  final double slideOffset;

  @override
  State<AppearOnce> createState() => _AppearOnceState();
}

class _AppearOnceState extends State<AppearOnce>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _opacity;
  Animation<double>? _translate;
  bool _deferredControllerCleanup = false;

  @override
  void initState() {
    super.initState();
    final duration = _safeAppearDuration(widget.duration);
    if (duration == Duration.zero) return;
    final ctrl = AnimationController(duration: duration, vsync: this);
    _opacity = openHandCurveAnimation(parent: ctrl, curve: Curves.easeOut);
    _translate = openHandCurveAnimation(
      parent: ctrl,
      curve: kOpenHandEmphasizedCurve,
    );
    ctrl.addStatusListener(_onStatus);
    _ctrl = ctrl;
    ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant AppearOnce oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ctrl = _ctrl;
    if (ctrl != null && widget.duration != oldWidget.duration) {
      ctrl.duration = _safeAppearDuration(widget.duration);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _disposeCompletedController();
  }

  void _disposeCompletedController() {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    ctrl.removeStatusListener(_onStatus);
    ctrl.dispose();
    _ctrl = null;
    _opacity = null;
    _translate = null;
    _deferredControllerCleanup = false;
    if (mounted) setState(() {});
  }

  void _disposeControllerAfterBuild() {
    if (_deferredControllerCleanup) return;
    _deferredControllerCleanup = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _disposeCompletedController();
    });
  }

  @override
  void dispose() {
    _ctrl?.removeStatusListener(_onStatus);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motionEnabled =
        openHandTickerMotionEnabled(context) && widget.duration > Duration.zero;
    if (!motionEnabled && _ctrl != null) {
      // 延后释放，避免在构建阶段触发状态变更。
      _disposeControllerAfterBuild();
    }
    const completed = AlwaysStoppedAnimation<double>(1);
    return _AppearTranslate(
      animation: motionEnabled ? _translate ?? completed : completed,
      slideOffset: _safeAppearSlideOffset(widget.slideOffset),
      child: FadeTransition(
        opacity: motionEnabled ? _opacity ?? completed : completed,
        child: widget.child,
      ),
    );
  }
}

/// 绘制阶段执行垂直位移，不在每帧调用 setState。
class _AppearTranslate extends SingleChildRenderObjectWidget {
  const _AppearTranslate({
    required this.animation,
    required this.slideOffset,
    required Widget super.child,
  });

  final Animation<double> animation;
  final double slideOffset;

  @override
  _AppearTranslateRender createRenderObject(BuildContext context) {
    return _AppearTranslateRender(
      animation: animation,
      slideOffset: slideOffset,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _AppearTranslateRender renderObject,
  ) {
    renderObject
      ..animation = animation
      ..slideOffset = slideOffset;
  }
}

class _AppearTranslateRender extends RenderTransform {
  _AppearTranslateRender({
    required this._animation,
    required double slideOffset,
  }) : _slideOffset = _safeAppearSlideOffset(slideOffset),
       super(transform: Matrix4.identity()) {
    _updateTransform();
  }

  Animation<double> _animation;
  double _slideOffset;

  set animation(Animation<double> value) {
    if (identical(_animation, value)) return;
    if (attached) {
      _animation.removeListener(_updateTransform);
      value.addListener(_updateTransform);
    }
    _animation = value;
    _updateTransform();
  }

  set slideOffset(double value) {
    final safeValue = _safeAppearSlideOffset(value);
    if (_slideOffset == safeValue) return;
    _slideOffset = safeValue;
    _updateTransform();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(_updateTransform);
  }

  @override
  void detach() {
    _animation.removeListener(_updateTransform);
    super.detach();
  }

  void _updateTransform() {
    final value = openHandBoundedProgress(_animation.value);
    final dy = (1 - value) * _slideOffset;
    transform = Matrix4.translationValues(0, dy, 0);
  }
}

Duration _safeAppearDuration(Duration duration) {
  return duration < Duration.zero ? Duration.zero : duration;
}

double _safeAppearSlideOffset(double value) {
  if (!value.isFinite) return _kDefaultAppearSlideOffset;
  return value;
}

/// 按全局列表项动效设置包装 [child]，切换设置时保留组件状态。
class SettingsAwareAppearOnce extends StatelessWidget {
  const SettingsAwareAppearOnce({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .select<SettingsController, DialogAnimationSettings>(
          (c) => c.listItemAnimationSettings,
        );
    final slide = switch (settings.entranceStyle) {
      DialogAnimationStyle.slideUp => _kDefaultAppearSlideOffset,
      DialogAnimationStyle.slideDown => -_kDefaultAppearSlideOffset,
      _ => 0.0,
    };
    return AppearOnce(
      duration: settings.entranceDuration,
      slideOffset: slide,
      child: child,
    );
  }
}
