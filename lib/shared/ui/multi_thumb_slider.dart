// 2026-05-04 — N-1 个滑块的横向多拇指 slider，用于让用户自定义
// 前 N-1 个静态缓存断点在消息流中的位置（百分比 0..1）。最后一个
// 断点固定在尾部，由调用方在 UI 上单独标注。
//
// 设计要点：
// - 拇指数量由 `values.length` 决定，调用方负责保证升序；本组件在
//   拖拽时也维持升序（被拖动的拇指会被相邻拇指的位置 clamp）。
// - 拖拽过程中通过 `onChanged` 实时回流；`onChangeEnd` 在拖拽结束时
//   调用，方便调用方仅在 release 时持久化。
// - 渲染：浅色 track + 每个拇指一颗带主题色描边的圆形，便于点击。
//
// 使用约束：
// - 调用方应将本组件包裹进有限宽度容器（Row/Expanded/SizedBox 等）。
// - `min`/`max` 留作硬保留参数，目前固定为 [0, 1]，但语义清晰，方便后续
//   扩展为非归一化的位置（例如真实 token 数）。

import 'package:flutter/material.dart';

class MultiThumbSlider extends StatefulWidget {
  const MultiThumbSlider({
    super.key,
    required this.values,
    required this.onChanged,
    this.onChangeEnd,
    this.height = 36,
    this.thumbRadius = 9,
    this.trackHeight = 4,
    this.disabled = false,
  });

  final List<double> values;
  final ValueChanged<List<double>> onChanged;
  final ValueChanged<List<double>>? onChangeEnd;
  final double height;
  final double thumbRadius;
  final double trackHeight;
  final bool disabled;

  @override
  State<MultiThumbSlider> createState() => _MultiThumbSliderState();
}

class _MultiThumbSliderState extends State<MultiThumbSlider> {
  int? _draggingIndex;

  double _xToValue(double dx, double width) {
    final usable = width - widget.thumbRadius * 2;
    if (usable <= 0) return 0;
    final raw = (dx - widget.thumbRadius) / usable;
    if (raw.isNaN) return 0;
    return raw.clamp(0.0, 1.0);
  }

  int _nearestIndex(double v) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < widget.values.length; i++) {
      final d = (widget.values[i] - v).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  void _updateValue(int index, double next) {
    final clone = List<double>.from(widget.values);
    final lower = index == 0 ? 0.0 : clone[index - 1];
    final upper = index == clone.length - 1 ? 1.0 : clone[index + 1];
    clone[index] = next.clamp(lower, upper);
    widget.onChanged(List<double>.unmodifiable(clone));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disabledColor = colorScheme.onSurface.withValues(alpha: 0.3);
    final trackColor = widget.disabled
        ? disabledColor
        : colorScheme.surfaceContainerHighest;
    final accent = widget.disabled
        ? disabledColor
        : colorScheme.primary;
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: widget.disabled
                ? null
                : (details) {
                    final v =
                        _xToValue(details.localPosition.dx, width);
                    final idx = _nearestIndex(v);
                    setState(() => _draggingIndex = idx);
                    _updateValue(idx, v);
                  },
            onPanUpdate: widget.disabled
                ? null
                : (details) {
                    final idx = _draggingIndex;
                    if (idx == null) return;
                    final v =
                        _xToValue(details.localPosition.dx, width);
                    _updateValue(idx, v);
                  },
            onPanEnd: widget.disabled
                ? null
                : (_) {
                    setState(() => _draggingIndex = null);
                    widget.onChangeEnd?.call(widget.values);
                  },
            onTapDown: widget.disabled
                ? null
                : (details) {
                    final v =
                        _xToValue(details.localPosition.dx, width);
                    final idx = _nearestIndex(v);
                    _updateValue(idx, v);
                    widget.onChangeEnd?.call(widget.values);
                  },
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Track
                Center(
                  child: Container(
                    height: widget.trackHeight,
                    margin: EdgeInsets.symmetric(
                      horizontal: widget.thumbRadius,
                    ),
                    decoration: BoxDecoration(
                      color: trackColor,
                      borderRadius: BorderRadius.circular(
                        widget.trackHeight / 2,
                      ),
                    ),
                  ),
                ),
                // 末尾固定断点示意（视觉锚点，不可拖拽）
                Positioned(
                  left: width - widget.thumbRadius * 2,
                  top: (widget.height - widget.thumbRadius * 2) / 2,
                  child: _AnchorEnd(
                    radius: widget.thumbRadius,
                    color: accent,
                  ),
                ),
                // 拖拽拇指
                for (var i = 0; i < widget.values.length; i++)
                  Positioned(
                    left: widget.values[i] *
                        (width - widget.thumbRadius * 2),
                    top: (widget.height - widget.thumbRadius * 2) / 2,
                    child: _Thumb(
                      radius: widget.thumbRadius,
                      color: accent,
                      isActive: _draggingIndex == i,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.radius,
    required this.color,
    required this.isActive,
  });

  final double radius;
  final Color color;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: isActive ? 3 : 2),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
    );
  }
}

class _AnchorEnd extends StatelessWidget {
  const _AnchorEnd({required this.radius, required this.color});

  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.lock_rounded,
        size: radius,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}
