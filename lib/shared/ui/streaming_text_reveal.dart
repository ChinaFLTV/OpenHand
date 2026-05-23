// 2026-05-23 — 流式消息文本「Q 弹进场」遮罩。
//
// 设计目标：让 streaming 状态下追加进来的字符不再"硬拼接到末尾"，而是从
// 卡片底部边缘以柔和渐变 + 高度增长的方式优雅浮现，与全局动画语言（短
// 时长 + easeOutCubic）保持一致。
//
// 实现路线：
// 1. 外层 `AnimatedSize`（220ms easeOutCubic）负责高度增长，避免新行
//    一次性弹出；
// 2. 内层 `ShaderMask(blendMode: dstIn)` 给整个 markdown body 加一道
//    底部 → 顶部的"完全不透明 → 轻微半透明"垂直 alpha 渐变。新字符到
//    达时把底部渐变拉得更长（≈40px）并在 320ms 内收回稳定带（≈14px），
//    肉眼呈"字符从下方淡入"的 Q 弹效果，且不会改变文本颜色。
// 3. `MediaQuery.disableAnimationsOf` 为 true 时直接 passthrough，
//    保证可访问性 / 性能模式下零动画。
//
// 设计取舍：刻意不做"按字符切分 + 逐个 AnimatedOpacity"——markdown 已
// 经把字符拆进若干 RichText/Widget，逐字符再切会爆 AnimationController
// 数量并且破坏排版。底部 mask 是行业惯例（ChatGPT / Claude / Gemini
// 都用类似手法），无需触及 markdown 解析器。

import 'package:flutter/material.dart';

class StreamingTextReveal extends StatefulWidget {
  const StreamingTextReveal({
    super.key,
    required this.textLength,
    required this.streaming,
    required this.child,
  });

  /// 当前已渲染文本长度。仅用作"是否触发新一轮淡入"的脏标记。
  final int textLength;

  /// streaming==false 时直接 passthrough（保留高度补间，给最后一帧
  /// 让 mask 平滑解除）。
  final bool streaming;

  final Widget child;

  @override
  State<StreamingTextReveal> createState() => _StreamingTextRevealState();
}

class _StreamingTextRevealState extends State<StreamingTextReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _lastLength = 0;

  static const Duration _kRevealDuration = Duration(milliseconds: 320);
  static const Duration _kHeightDuration = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _kRevealDuration,
      value: 1.0,
    );
    _lastLength = widget.textLength;
  }

  @override
  void didUpdateWidget(covariant StreamingTextReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streaming) {
      if (widget.textLength != _lastLength) {
        _lastLength = widget.textLength;
        // 只有增量（新增字符）才触发；纯重排或截断不触发。
        if (widget.textLength > oldWidget.textLength) {
          _ctrl.forward(from: 0.0);
        }
      }
    } else if (oldWidget.streaming) {
      // streaming 结束：让 mask 平滑回到完全不透明。
      _ctrl.forward(from: _ctrl.value);
      _lastLength = widget.textLength;
    } else {
      _lastLength = widget.textLength;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disable = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disable) {
      return widget.child;
    }
    return AnimatedSize(
      duration: _kHeightDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: widget.streaming
          ? AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                final t = Curves.easeOutCubic.transform(_ctrl.value);
                // 底部"淡入带"在新字符到达瞬间最大（更"虚"），随后收紧
                // 到稳定窄带；alpha 从 0.55 升到 1.0。
                final tailAlpha = 0.55 + 0.45 * t;
                final tailHeadAlpha = 0.85 + 0.15 * t;
                return ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.78, 0.92, 1.0],
                    colors: [
                      Colors.white,
                      Colors.white,
                      Colors.white.withValues(alpha: tailHeadAlpha),
                      Colors.white.withValues(alpha: tailAlpha),
                    ],
                  ).createShader(bounds),
                  child: child,
                );
              },
              child: widget.child,
            )
          : widget.child,
    );
  }
}
