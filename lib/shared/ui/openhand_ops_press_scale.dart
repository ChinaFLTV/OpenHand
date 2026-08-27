import 'package:flutter/material.dart';

import 'motion_durations.dart';
import 'motion_preference.dart';

const double kOpenHandOpsHoverScale = 1.016;
const double kOpenHandOpsPressScale = 0.97;
const double kOpenHandOpsHoverOverlay = 0.05;
const double kOpenHandOpsPressOverlay = 0.1;
const double kOpenHandOpsMotionClearance = 6;
const Duration kOpenHandOpsPressDuration = kOpenHandMotion120;

/// 运维卡片按压/悬停缩放。子树先打进独立图层，避免带动内部滚轮和图表一起重绘。
class OpenHandOpsPressScale extends StatefulWidget {
  const OpenHandOpsPressScale({
    super.key,
    required this.child,
    required this.tone,
    this.onTap,
    this.radius = 16,
    this.borderRadius,
    this.hoverScale = kOpenHandOpsHoverScale,
    this.pressScale = kOpenHandOpsPressScale,
    this.showHoverOverlay = true,
    this.showFocusRing = false,
    this.motionClearance,
  });

  final Widget child;
  final Color tone;
  final VoidCallback? onTap;
  final double radius;
  final BorderRadiusGeometry? borderRadius;
  final double hoverScale;
  final double pressScale;
  final bool showHoverOverlay;
  final bool showFocusRing;
  final EdgeInsetsGeometry? motionClearance;

  @override
  State<OpenHandOpsPressScale> createState() => _OpenHandOpsPressScaleState();
}

class _OpenHandOpsPressScaleState extends State<OpenHandOpsPressScale> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  BorderRadiusGeometry get _radius {
    return widget.borderRadius ?? BorderRadius.circular(widget.radius);
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() {
      _hovered = value;
      if (!value) _pressed = false;
    });
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    final duration = openHandMotionDuration(context, kOpenHandOpsPressDuration);
    final hoverScale = widget.hoverScale.isFinite && widget.hoverScale > 0
        ? widget.hoverScale
        : kOpenHandOpsHoverScale;
    final pressScale = widget.pressScale.isFinite && widget.pressScale > 0
        ? widget.pressScale
        : kOpenHandOpsPressScale;
    final scale = _pressed
        ? pressScale
        : _hovered
        ? hoverScale
        : 1.0;
    final overlay = widget.tone.withValues(
      alpha: _pressed
          ? kOpenHandOpsPressOverlay
          : _hovered && widget.showHoverOverlay
          ? kOpenHandOpsHoverOverlay
          : 0,
    );
    Widget body = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: duration,
          curve: kOpenHandSwitchInCurve,
          child: Stack(
            children: [
              RepaintBoundary(child: widget.child),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: duration,
                    curve: kOpenHandSwitchInCurve,
                    decoration: BoxDecoration(
                      color: overlay,
                      borderRadius: _radius,
                      // 外层卡片通常已经有自己的边框，悬停/按压时不再叠加
                      // 第二层边框；仅在键盘焦点态显示可访问性提示。
                      border: widget.showFocusRing && _focused
                          ? Border.all(
                              color: widget.tone.withValues(alpha: 0.68),
                              width: 2,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (widget.showFocusRing) {
      body = FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) {
          if (_focused == value) return;
          setState(() => _focused = value);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: body,
      );
    }
    return Semantics(
      button: true,
      child: Padding(
        padding:
            widget.motionClearance ??
            const EdgeInsets.all(kOpenHandOpsMotionClearance),
        child: body,
      ),
    );
  }
}
