import 'package:flutter/material.dart';

import '../../shared/ui/openhand_spacing.dart';
import '../util/input_value_parsing.dart';
import 'motion_preference.dart';

/// 通用左右分栏，可拖拽中缝调整左侧宽度（右侧自适应剩余空间）。
///
/// - `initialLeftFraction`：初始左侧占比（0..1，默认 0.5）。
/// - `minLeft` / `minRight`：左右最小像素宽度，拖拽不会越界。
/// - `handleWidth`：中缝命中区宽度（视觉上是 1px 分隔线 + 透明握把）。
/// - 鼠标指针 hover 中缝时切换为 `SystemMouseCursors.resizeColumn`；
///   拖拽中显示主题色高亮的握把指示。
/// - 暂不持久化拖拽结果（每次打开恢复到 initialLeftFraction）。
class ResizableSplitter extends StatefulWidget {
  const ResizableSplitter({
    super.key,
    required this.left,
    required this.right,
    this.initialLeftFraction = 0.5,
    this.minLeft = 200,
    this.minRight = 200,
    this.handleWidth = 8,
  });

  final Widget left;
  final Widget right;
  final double initialLeftFraction;
  final double minLeft;
  final double minRight;
  final double handleWidth;

  @override
  State<ResizableSplitter> createState() => _ResizableSplitterState();
}

class _ResizableSplitterState extends State<ResizableSplitter> {
  static const double _fallbackInitialLeftFraction = 0.5;

  double? _leftWidth;
  bool _hovering = false;
  bool _dragging = false;

  double _nonNegativeFinite(double value) {
    return value.isFinite && value > 0 ? value : 0;
  }

  double _safeInitialLeftFraction(double value) {
    return finiteUnitInterval(value, fallback: _fallbackInitialLeftFraction);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final handleMotionDuration = openHandTickerMotionEnabled(context)
        ? const Duration(milliseconds: 140)
        : Duration.zero;
    return LayoutBuilder(
      builder: (context, c) {
        final total = _nonNegativeFinite(c.maxWidth);
        final handle = _nonNegativeFinite(widget.handleWidth);
        final minLeft = _nonNegativeFinite(widget.minLeft);
        final minRight = _nonNegativeFinite(widget.minRight);
        final availForLeft = total - handle - minRight;
        final maxLeft = availForLeft < minLeft ? minLeft : availForLeft;
        _leftWidth ??=
            (total * _safeInitialLeftFraction(widget.initialLeftFraction))
                .clamp(minLeft, maxLeft);
        final leftW = _leftWidth!.clamp(minLeft, maxLeft);
        return Row(
          children: [
            SizedBox(width: leftW, child: widget.left),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              onEnter: (_) {
                if (_hovering) return;
                _hovering = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
              },
              onExit: (_) {
                if (!_hovering) return;
                _hovering = false;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => setState(() => _dragging = true),
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    final next = (leftW + d.delta.dx).clamp(minLeft, maxLeft);
                    _leftWidth = next;
                  });
                },
                onHorizontalDragEnd: (_) => setState(() => _dragging = false),
                onHorizontalDragCancel: () => setState(() => _dragging = false),
                child: SizedBox(
                  width: handle,
                  height: double.infinity,
                  child: Center(
                    child: AnimatedContainer(
                      duration: handleMotionDuration,
                      curve: kOpenHandSwitchInCurve,
                      width: _dragging ? 3 : 1,
                      decoration: BoxDecoration(
                        color: _dragging
                            ? cs.primary
                            : (_hovering
                                  ? cs.primary.withValues(alpha: 0.55)
                                  : cs.outlineVariant),
                        borderRadius: BorderRadius.circular(kOpenHandRadius2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: widget.right),
          ],
        );
      },
    );
  }
}
