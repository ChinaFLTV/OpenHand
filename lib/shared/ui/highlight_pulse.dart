import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Generic top-edge / inline highlight pulse driven by an external
/// `ValueListenable<int>` signal. Each time the signal increments the
/// pulse fades in and decays over ~660 ms, drawing a soft primary-tinted
/// gradient bar (with optional box-shadow halo). Used to give positive
/// confirmation after an action lands without stealing focus or layout.
///
/// Honors `MediaQuery.maybeDisableAnimationsOf` (reduceMotion).
class HighlightPulse extends StatefulWidget {
  const HighlightPulse({
    super.key,
    required this.signal,
    this.height = 3,
    this.color,
    this.borderRadius = BorderRadius.zero,
  });

  /// Increment-this-and-the-pulse-fires notifier.
  final ValueListenable<int> signal;

  /// Bar thickness in logical pixels. 3 px is the default for top-edge
  /// pane indicators; bump higher for inline field highlights.
  final double height;

  /// Optional override; defaults to `Theme.of(context).colorScheme.primary`.
  final Color? color;

  /// Optional rounded corners — useful when the pulse sits on top of a
  /// rounded container instead of a panel edge.
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
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
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
        // Two-stage envelope: 0..0.22 = ramp in, 0.22..1 = decay.
        final double opacity;
        if (v < 0.22) {
          opacity = (v / 0.22).clamp(0.0, 1.0);
        } else {
          final t = (1 - (v - 0.22) / 0.78).clamp(0.0, 1.0);
          opacity = Curves.easeOutCubic.transform(t);
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
