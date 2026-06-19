import 'package:flutter/material.dart';

/// Reusable image interaction shell for preview dialogs.
///
/// `InteractiveViewer` supplies native pinch zoom and one-finger pan on touch
/// devices, while `trackpadScrollCausesScale` keeps desktop trackpad pinch
/// gestures responsive.
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
  static const Duration _kResetDuration = Duration(milliseconds: 180);
  static const Curve _kResetCurve = Curves.easeOutCubic;

  late final TransformationController _controller = TransformationController();
  late final AnimationController _resetController = AnimationController(
    vsync: this,
    duration: _kResetDuration,
  )..addListener(_applyResetAnimationFrame);
  Animation<Matrix4>? _resetAnimation;

  @override
  void didUpdateWidget(covariant OpenHandInteractiveImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child.key != widget.child.key) {
      _resetController.stop();
      _resetAnimation = null;
      _controller.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _resetController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _applyResetAnimationFrame() {
    final animation = _resetAnimation;
    if (animation == null) return;
    _controller.value = animation.value;
  }

  void _animateReset() {
    _resetController.stop();
    _resetAnimation = Matrix4Tween(
      begin: _controller.value.clone(),
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _resetController, curve: _kResetCurve));
    _resetController.forward(from: 0);
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
        onInteractionStart: (_) => _resetController.stop(),
        trackpadScrollCausesScale: true,
        child: widget.child,
      ),
    );
  }
}
