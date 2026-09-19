import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/ui/animated_appearance.dart';
import '../../../shared/ui/bounded_animation.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/util/timer_safety.dart';
import '../service/workflow_node_executor.dart';

const _refreshInterval = Duration(milliseconds: 100);
const _digitDuration = Duration(milliseconds: 80);

/// 独立刷新耗时，避免计时触发画布和连线重建。
class WorkflowNodeElapsedBadge extends StatefulWidget {
  const WorkflowNodeElapsedBadge({super.key, required this.event});

  final WorkflowNodeExecutionEvent? event;

  @override
  State<WorkflowNodeElapsedBadge> createState() =>
      _WorkflowNodeElapsedBadgeState();
}

class _WorkflowNodeElapsedBadgeState extends State<WorkflowNodeElapsedBadge> {
  final _stopwatch = Stopwatch();
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  bool get _running =>
      widget.event?.phase == WorkflowNodeExecutionPhase.running;

  @override
  void initState() {
    super.initState();
    _updateEvent();
  }

  @override
  void didUpdateWidget(covariant WorkflowNodeElapsedBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.event, widget.event)) {
      _updateEvent();
      _syncTimer();
    }
  }

  void _updateEvent() {
    _timer?.cancel();
    _timer = null;
    _stopwatch
      ..stop()
      ..reset();
    _elapsed = widget.event?.duration ?? Duration.zero;
    if (_running) _stopwatch.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimer();
  }

  void _syncTimer() {
    if (!_running || !TickerMode.valuesOf(context).enabled) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null) return;
    _elapsed = (widget.event?.duration ?? Duration.zero) + _stopwatch.elapsed;
    _timer = startSafePeriodicTimer(_refreshInterval, (_) {
      setState(
        () => _elapsed =
            (widget.event?.duration ?? Duration.zero) + _stopwatch.elapsed,
      );
    }, min: _refreshInterval);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = widget.event?.phase;
    final visible =
        phase != null &&
        phase != WorkflowNodeExecutionPhase.pending &&
        phase != WorkflowNodeExecutionPhase.skipped;
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.chip,
    );
    final colors = Theme.of(context).colorScheme;
    final text = (_elapsed.inMilliseconds / 1000).toStringAsFixed(3);
    final duration = settings.disablesAnimation
        ? Duration.zero
        : Duration(
            milliseconds: math.min(
              settings.entranceDuration.inMilliseconds,
              _digitDuration.inMilliseconds,
            ),
          );
    final style = TextStyle(
      fontSize: 10,
      height: 1,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: colors.onSecondaryContainer,
    );
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedAppearance(
          settings: settings,
          present: visible,
          collapseSize: false,
          child: Semantics(
            label: '执行耗时 ${_elapsed.inMilliseconds} 毫秒',
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: colors.secondary.withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 10,
                      color: colors.onSecondaryContainer,
                    ),
                    const SizedBox(width: 3),
                    for (var index = 0; index < text.length; index++)
                      if (duration == Duration.zero)
                        Text(text[index], style: style)
                      else
                        ClipRect(
                          key: ValueKey(text.length - index),
                          child: AnimatedSwitcher(
                            duration: duration,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: OpenHandBoundedDoubleAnimation(
                                    animation,
                                  ),
                                  child: SlideTransition(
                                    position:
                                        Tween<Offset>(
                                          begin:
                                              child.key == ValueKey(text[index])
                                              ? const Offset(0, 0.8)
                                              : const Offset(0, -0.8),
                                          end: Offset.zero,
                                        ).animate(
                                          openHandCurveAnimation(
                                            parent: animation,
                                            curve: settings.curve.curve,
                                          ),
                                        ),
                                    child: child,
                                  ),
                                ),
                            child: Text(
                              text[index],
                              key: ValueKey(text[index]),
                              style: style,
                            ),
                          ),
                        ),
                    Text(' 秒', style: style),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
