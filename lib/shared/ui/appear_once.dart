import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../app/model/dialog_animation_settings.dart';
import '../../app/state/settings_controller.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';

const Duration _kDefaultAppearDuration = kOpenHandMotion320;
const double _kDefaultAppearSlideOffset = 12.0;

/// 一次性淡入上移动画；完成后释放控制器，后续重建直接返回静态子树。
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
    final ctrl = AnimationController(
      duration: _safeAppearDuration(widget.duration),
      vsync: this,
    );
    _opacity = CurvedAnimation(parent: ctrl, curve: Curves.easeOut);
    _translate = CurvedAnimation(parent: ctrl, curve: kOpenHandEmphasizedCurve);
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
    final opacity = _opacity;
    final translate = _translate;
    if (opacity == null || translate == null) {
      return widget.child;
    }
    if (!openHandTickerMotionEnabled(context)) {
      // 延后释放，避免在构建阶段触发状态变更。
      _disposeControllerAfterBuild();
      return widget.child;
    }
    return FadeTransition(
      opacity: opacity,
      child: _AppearTranslate(
        animation: translate,
        slideOffset: _safeAppearSlideOffset(widget.slideOffset),
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

class _AppearTranslateRender extends RenderProxyBox {
  _AppearTranslateRender({
    required Animation<double> animation,
    required double slideOffset,
  }) : _animation = animation,
       _slideOffset = _safeAppearSlideOffset(slideOffset);

  Animation<double> _animation;
  double _slideOffset;

  set animation(Animation<double> value) {
    if (identical(_animation, value)) return;
    if (attached) {
      _animation.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _animation = value;
    markNeedsPaint();
  }

  set slideOffset(double value) {
    final safeValue = _safeAppearSlideOffset(value);
    if (_slideOffset == safeValue) return;
    _slideOffset = safeValue;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final value = _animation.value.clamp(0.0, 1.0);
    final dy = (1 - value) * _slideOffset;
    super.paint(context, offset + Offset(0, dy));
  }
}

Duration _safeAppearDuration(Duration duration) {
  if (duration <= Duration.zero) return _kDefaultAppearDuration;
  return duration;
}

double _safeAppearSlideOffset(double value) {
  if (!value.isFinite) return _kDefaultAppearSlideOffset;
  return value;
}

/// 按全局列表项动效设置包装 [child]；禁用动效时直接返回原组件。
class SettingsAwareAppearOnce extends StatelessWidget {
  const SettingsAwareAppearOnce({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .select<SettingsController, DialogAnimationSettings>(
          (c) => c.listItemAnimationSettings,
        );
    if (settings.entranceStyle == DialogAnimationStyle.none) {
      return child;
    }
    final double slide;
    switch (settings.entranceStyle) {
      case DialogAnimationStyle.slideUp:
        slide = 12.0;
      case DialogAnimationStyle.slideDown:
        slide = -12.0;
      case DialogAnimationStyle.fade:
      case DialogAnimationStyle.fadeScale:
      case DialogAnimationStyle.expand:
      case DialogAnimationStyle.elastic:
      case DialogAnimationStyle.springScale:
      case DialogAnimationStyle.flipX:
      case DialogAnimationStyle.rotateScale:
      case DialogAnimationStyle.slideLeft:
      case DialogAnimationStyle.slideRight:
        slide = 0.0;
      case DialogAnimationStyle.none:
        return child;
    }
    return AppearOnce(
      duration: settings.entranceDuration,
      slideOffset: slide,
      child: child,
    );
  }
}
