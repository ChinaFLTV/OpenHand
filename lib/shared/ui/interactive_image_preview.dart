import 'package:flutter/material.dart';

import 'motion_durations.dart';
import 'motion_preference.dart';

/// 预览弹窗复用的图片交互层，支持触控缩放、平移和桌面触控板手势。
class OpenHandInteractiveImagePreview extends StatefulWidget {
  const OpenHandInteractiveImagePreview({
    super.key,
    required this.child,
    this.minScale = 1.0,
    this.maxScale = 6.0,
  });

  final Widget child;
  final double minScale;
  final double maxScale;

  @override
  State<OpenHandInteractiveImagePreview> createState() =>
      _OpenHandInteractiveImagePreviewState();
}

class _OpenHandInteractiveImagePreviewState
    extends State<OpenHandInteractiveImagePreview>
    with SingleTickerProviderStateMixin {
  static const Duration _kResetDuration = kOpenHandMotion180;
  static const Curve _kResetCurve = kOpenHandSwitchInCurve;

  late final TransformationController _controller = TransformationController();
  AnimationController? _resetController;
  Animation<Matrix4>? _resetAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!openHandTickerMotionEnabled(context)) {
      _stopResetAnimation(settleToIdentity: _resetAnimation != null);
    }
  }

  @override
  void didUpdateWidget(covariant OpenHandInteractiveImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child.key != widget.child.key) {
      _stopResetAnimation();
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _resetController?.dispose();
    _resetController = null;
    _controller.dispose();
    super.dispose();
  }

  AnimationController _ensureResetController() {
    return _resetController ??= AnimationController(
      vsync: this,
      duration: _kResetDuration,
    )..addListener(_applyResetAnimationFrame);
  }

  void _applyResetAnimationFrame() {
    final animation = _resetAnimation;
    if (animation == null) return;
    _controller.value = animation.value;
  }

  void _stopResetAnimation({bool settleToIdentity = false}) {
    _resetController?.stop();
    _resetAnimation = null;
    if (settleToIdentity) {
      _controller.value = Matrix4.identity();
    }
  }

  void _animateReset() {
    if (!openHandTickerMotionEnabled(context)) {
      _stopResetAnimation(settleToIdentity: true);
      return;
    }
    final resetController = _ensureResetController();
    resetController.stop();
    _resetAnimation = Matrix4Tween(
      begin: _controller.value.clone(),
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: resetController, curve: _kResetCurve));
    resetController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final minScale = widget.minScale.isFinite && widget.minScale > 0
        ? widget.minScale
        : 1.0;
    final maxScale = widget.maxScale.isFinite && widget.maxScale >= minScale
        ? widget.maxScale
        : minScale;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: _animateReset,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: minScale,
        maxScale: maxScale,
        onInteractionStart: (_) => _stopResetAnimation(),
        trackpadScrollCausesScale: true,
        child: widget.child,
      ),
    );
  }
}
