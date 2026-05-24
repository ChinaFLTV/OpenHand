// 2026-05-24 — 流式消息文本「精灵登场」逐字浮现遮罩（Gemini 风格强化版）。
//
// 让 streaming 状态下追加的新字符从旧/新文本边界处以锐利波前扫过 +
// easeOutBack Q 弹 overshoot 的方式淡入浮现，对标 Gemini 网页端的
// 增量文本精灵登场动画。
//
// 渐变停靠点：[0, oldFraction, waveFront, 1.0]
//  * oldFraction 以上：始终完全不透明（旧文本不受影响）
//  * oldFraction → waveFront：从 opaque 过渡到 waveAlpha，波前扫过
//    新字符逐批"亮相"
//  * waveFront → 1.0：从 waveAlpha 过渡到 tailAlpha，最新字符从
//    "幽灵态"温和浮现
// easeOutBack 的轻微 overshoot 让波前冲过底部再弹回，肉眼呈 Q 弹落位。
//
// 外层 `AnimatedSize`（220ms easeOutCubic）负责高度增长；内层 reveal
// 动画 420ms。`MediaQuery.disableAnimationsOf` 为 true 时 passthrough。

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

  /// 上一次动画触发时 widget 的 textLength，用于计算旧文本占比。
  int _prevRenderLength = 0;

  /// 精灵登场动画时长：比标准 320ms 略长，让 easeOutBack 的 Q 弹
  /// overshoot 有足够时间展现，用户能感知到"弹"的美感。
  static const Duration _kRevealDuration = Duration(milliseconds: 420);

  /// 高度补间保持短促干脆，不与 reveal 动画争抢注意力。
  static const Duration _kHeightDuration = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _kRevealDuration,
      value: 1.0,
    );
    _prevRenderLength = widget.textLength;
  }

  @override
  void didUpdateWidget(covariant StreamingTextReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streaming) {
      if (widget.textLength > oldWidget.textLength) {
        // 新字符到达：以旧 widget 长度作为稳定基线，从该边界向下扫波前。
        _prevRenderLength = oldWidget.textLength;
        _ctrl.forward(from: 0.0);
      } else if (widget.textLength < oldWidget.textLength) {
        // 截断（极罕见）：直接重置基线。
        _prevRenderLength = widget.textLength;
      }
    } else if (oldWidget.streaming) {
      // streaming 结束：让 mask 平滑回到完全不透明。
      _ctrl.forward(from: _ctrl.value);
      _prevRenderLength = widget.textLength;
    } else {
      _prevRenderLength = widget.textLength;
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
                final rawT = _ctrl.value;
                // 动画已稳定 → 跳过 ShaderMask，避免无意义 GPU 合成层。
                if (rawT >= 1.0) return child!;

                // Q 弹 spring 曲线：easeOutBack 在 1.0 处有轻微 overshoot
                // 再回弹，视觉上"字符从边界弹出来 → 落位"，精灵登场感。
                final t = Curves.easeOutBack.transform(rawT);

                // 旧文本在整体中的高度占比（按字符数近似，对流式追加场景
                // 足够精准——新字符永远追加在末尾）。
                final curLen = widget.textLength;
                final oldFraction = _prevRenderLength > 0 && curLen > 0
                    ? (_prevRenderLength / curLen).clamp(0.0, 1.0)
                    : 0.0;

                // 波前位置：从旧文本边界扫向底部。
                // equaeOutBack 的 overshoot 让波前冲过底部再弹回，
                // 肉眼呈"字符从边界弹出来 → 落位"的精灵登场感。
                final newZone = 1.0 - oldFraction;
                final waveFront = (oldFraction + newZone * t).clamp(0.0, 1.0);

                // 尾部（最新字符）alpha 从 0.28 弹升至 1.0。
                final tailAlpha = 0.28 + 0.72 * t;

                // 波前处 alpha：略低于 1.0 的软过渡，避免一条硬切线。
                final waveAlpha = 0.58 + 0.42 * t;

                // 梯度停靠点：[0, oldFraction, waveFront, 1.0]
                //  * oldFraction 以上：始终完全不透明（旧文本不受影响）
                //  * oldFraction → waveFront：从 opaque 线性过渡到 waveAlpha
                //  * waveFront → 1.0：从 waveAlpha 线性过渡到 tailAlpha
                // 波前扫过后渐变收窄，新字符逐批"亮相"。
                return ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [
                      0.0,
                      oldFraction,
                      waveFront,
                      1.0,
                    ],
                    colors: [
                      Colors.white,
                      Colors.white,
                      Colors.white.withValues(alpha: waveAlpha),
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
