import 'package:flutter/material.dart';

import 'bounded_animation.dart';
import 'interaction_timings.dart';
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

  int _snapshotId = 0;
  late _TitleSnapshot _current = _snapshotFromWidget();
  _TitleSnapshot? _previous;
  bool _motionEnabled = true;
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _fallbackDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed &&
              mounted &&
              _previous != null) {
            setState(() => _previous = null);
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
    if (oldWidget.text == widget.text) {
      _current = _snapshotFromWidget(id: _current.id);
      return;
    }
    final next = _snapshotFromWidget();
    if (!_motionEnabled) {
      _current = next;
      _previous = null;
      _controller.value = 1;
      return;
    }
    _previous = _current;
    _current = next;
    _controller.forward(from: 0);
  }

  _TitleSnapshot _snapshotFromWidget({int? id}) {
    return _TitleSnapshot(
      id: id ?? ++_snapshotId,
      text: widget.text,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      softWrap: widget.softWrap,
    );
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
    _previous = null;
    _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = _current.text.trim();
    final animatedBody = _buildAnimatedBody();
    if (trimmed.isEmpty || !widget.tooltip) return animatedBody;
    return Tooltip(
      message: trimmed,
      waitDuration: kOpenHandTooltipWait,
      child: Semantics(
        label: trimmed,
        child: ExcludeSemantics(child: animatedBody),
      ),
    );
  }

  Widget _titleText(_TitleSnapshot snapshot, _TitleRole role) {
    return Text(
      key: ValueKey<(int, _TitleRole)>((snapshot.id, role)),
      snapshot.text,
      maxLines: snapshot.maxLines,
      overflow: snapshot.overflow,
      softWrap: snapshot.softWrap,
      style: snapshot.style,
    );
  }

  Widget _buildAnimatedBody() {
    final previous = _previous;
    if (!_motionEnabled || previous == null) {
      return _titleText(_current, _TitleRole.current);
    }
    final previousTitle = _titleText(previous, _TitleRole.previous);
    final currentTitle = _titleText(_current, _TitleRole.current);
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final raw = openHandBoundedProgress(_controller.value);
          final incomingMotion = _incomingMotionCurve.transform(raw);
          final incomingOpacity = openHandBoundedProgress(
            kOpenHandSwitchInCurve.transform(raw),
          );
          final outgoing = openHandBoundedProgress(
            kOpenHandSwitchOutCurve.transform(raw),
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
                    child: previousTitle,
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
                    child: currentTitle,
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

enum _TitleRole { current, previous }

class _TitleSnapshot {
  const _TitleSnapshot({
    required this.id,
    required this.text,
    required this.style,
    required this.maxLines,
    required this.overflow,
    required this.softWrap,
  });

  final int id;
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final bool softWrap;
}
