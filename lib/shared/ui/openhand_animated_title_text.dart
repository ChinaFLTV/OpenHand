import 'package:flutter/material.dart';

import 'bounded_animation.dart';
import 'motion_preference.dart';

/// 为会话标题提供统一的淡入、纵向切换与轻微弹性缩放动效。
class OpenHandAnimatedTitleText extends StatefulWidget {
  const OpenHandAnimatedTitleText({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.softWrap = false,
    this.tooltip = true,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final bool softWrap;
  final bool tooltip;

  @override
  State<OpenHandAnimatedTitleText> createState() =>
      _OpenHandAnimatedTitleTextState();
}

class _OpenHandAnimatedTitleTextState extends State<OpenHandAnimatedTitleText>
    with SingleTickerProviderStateMixin {
  static const Duration _fallbackDuration = Duration(milliseconds: 360);
  static const Curve _incomingMotionCurve = Cubic(0.22, 1.22, 0.36, 1);

  late String _currentText = widget.text;
  String? _previousText;
  bool _motionEnabled = true;
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _fallbackDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed &&
              mounted &&
              _previousText != null) {
            setState(() => _previousText = null);
          }
        });

  @override
  void initState() {
    super.initState();
    _controller.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionSettings();
  }

  @override
  void didUpdateWidget(covariant OpenHandAnimatedTitleText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotionSettings();
    if (oldWidget.text == widget.text) return;
    if (!_motionEnabled) {
      _currentText = widget.text;
      _previousText = null;
      _controller.value = 1;
      return;
    }
    _previousText = _currentText;
    _currentText = widget.text;
    _controller.forward(from: 0);
  }

  void _syncMotionSettings() {
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.listItem,
    );
    final duration = settings.duration;
    _motionEnabled = duration > Duration.zero;
    if (_motionEnabled) {
      if (_controller.duration != duration) {
        _controller.duration = duration;
      }
      return;
    }
    _previousText = null;
    _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = _currentText.trim();
    final animatedBody = _buildAnimatedBody();
    if (trimmed.isEmpty || !widget.tooltip) return animatedBody;
    return Tooltip(
      message: trimmed,
      waitDuration: const Duration(milliseconds: 380),
      child: Semantics(
        label: trimmed,
        child: ExcludeSemantics(child: animatedBody),
      ),
    );
  }

  Widget _titleText(String value) {
    return Text(
      value,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      softWrap: widget.softWrap,
      style: widget.style,
    );
  }

  Widget _buildAnimatedBody() {
    final previousText = _previousText;
    if (!_motionEnabled || previousText == null) {
      return _titleText(_currentText);
    }
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final raw = openHandBoundedProgress(_controller.value);
          final incomingMotion = _incomingMotionCurve.transform(raw);
          final incomingOpacity = openHandBoundedProgress(
            Curves.easeOutCubic.transform(raw),
          );
          final outgoing = openHandBoundedProgress(
            Curves.easeInCubic.transform(raw),
          );
          return Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              Opacity(
                opacity: 1 - outgoing,
                child: Transform.translate(
                  offset: Offset(0, -7 * outgoing),
                  child: Transform.scale(
                    alignment: AlignmentDirectional.centerStart,
                    scale: 1 - 0.015 * outgoing,
                    child: _titleText(previousText),
                  ),
                ),
              ),
              Opacity(
                opacity: incomingOpacity,
                child: Transform.translate(
                  offset: Offset(0, 7 * (1 - incomingMotion)),
                  child: Transform.scale(
                    alignment: AlignmentDirectional.centerStart,
                    scale: 0.985 + 0.015 * incomingMotion,
                    child: _titleText(_currentText),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
