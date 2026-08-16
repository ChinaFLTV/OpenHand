import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/openhand_status_colors.dart';
import '../util/input_value_parsing.dart';
import 'motion_preference.dart';

/// 由外部计数信号驱动的高亮脉冲，遵循减少动态效果和 `TickerMode` 设置。
class HighlightPulse extends StatefulWidget {
  const HighlightPulse({
    super.key,
    required this.signal,
    this.height = 3,
    this.color,
    this.borderRadius = BorderRadius.zero,
  });

  /// 每次递增都会触发一次脉冲。
  final ValueListenable<int> signal;

  /// 高亮条厚度。
  final double height;

  /// 默认使用主题主色。
  final Color? color;

  /// 高亮条圆角。
  final BorderRadiusGeometry borderRadius;

  @override
  State<HighlightPulse> createState() => _HighlightPulseState();
}

class _HighlightPulseState extends State<HighlightPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int? _lastSeen;

  double get _safeHeight {
    return widget.height.isFinite && widget.height > 0 ? widget.height : 0;
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 660),
    );
    _lastSeen = widget.signal.value;
    widget.signal.addListener(_onSignal);
  }

  @override
  void didUpdateWidget(covariant HighlightPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signal != widget.signal) {
      oldWidget.signal.removeListener(_onSignal);
      _lastSeen = widget.signal.value;
      widget.signal.addListener(_onSignal);
    }
  }

  void _onSignal() {
    if (!mounted) return;
    final next = widget.signal.value;
    if (_lastSeen == next) return;
    _lastSeen = next;
    if (!openHandTickerMotionEnabled(context)) {
      _ctrl.stop();
      return;
    }
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    widget.signal.removeListener(_onSignal);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = _ctrl.value;
        if (v == 0) return const SizedBox.shrink();
        // 两段式包络：前 22% 渐入，其余时段衰减。
        final double opacity;
        if (v < 0.22) {
          opacity = unitRatio(v, 0.22);
        } else {
          final t = clampUnitInterval(1 - (v - 0.22) / 0.78);
          opacity = kOpenHandSwitchInCurve.transform(t);
        }
        return Container(
          height: _safeHeight,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              colors: [
                base.withValues(alpha: 0),
                base.withValues(alpha: 0.85 * opacity),
                base.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: base.withValues(alpha: 0.45 * opacity),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 在堆叠布局顶部统一叠加成功与失败反馈脉冲。
class FeedbackHighlightPulseOverlay extends StatelessWidget {
  const FeedbackHighlightPulseOverlay({
    super.key,
    required this.successSignal,
    required this.errorSignal,
  });

  final ValueListenable<int> successSignal;
  final ValueListenable<int> errorSignal;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            HighlightPulse(
              signal: successSignal,
              color: OpenHandStatusColors.success,
            ),
            HighlightPulse(
              signal: errorSignal,
              color: OpenHandStatusColors.error,
            ),
          ],
        ),
      ),
    );
  }
}
