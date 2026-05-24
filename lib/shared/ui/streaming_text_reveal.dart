// 2026-05-24 — 流式消息文本「精灵登场」diff reveal。
//
// 旧内容静态垫底，新内容只在追加区域用弹性波前淡入；极少数截断场景
// 则让旧内容淡出。这样旧文本不会跟着 mask 一起闪，新增 diff 才像真正
// 登场。`MediaQuery.disableAnimationsOf` 为 true 时直接 passthrough。

import 'package:flutter/material.dart';

enum _StreamingRevealPhase { append, remove }

class StreamingTextReveal extends StatefulWidget {
  const StreamingTextReveal({
    super.key,
    required this.textLength,
    required this.streaming,
    required this.child,
  });

  /// 当前已渲染文本长度。仅用作"是否触发新一轮淡入"的脏标记。
  final int textLength;

  /// streaming==false 时直接 passthrough，仅保留外层高度补间。
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

  Widget? _outgoingChild;
  _StreamingRevealPhase _phase = _StreamingRevealPhase.append;

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
    )..addStatusListener(_handleStatusChanged);
    _prevRenderLength = widget.textLength;
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || _outgoingChild == null) {
      return;
    }
    if (mounted) {
      setState(() => _outgoingChild = null);
    } else {
      _outgoingChild = null;
    }
  }

  @override
  void didUpdateWidget(covariant StreamingTextReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streaming) {
      if (widget.textLength > oldWidget.textLength) {
        // 新字符到达：以旧 widget 长度作为稳定基线，从该边界向下扫波前。
        _prevRenderLength = oldWidget.textLength;
        _outgoingChild = oldWidget.child;
        _phase = _StreamingRevealPhase.append;
        _ctrl.forward(from: 0.0);
      } else if (widget.textLength < oldWidget.textLength) {
        // 截断（极罕见）：新内容先落底，旧内容在上层淡出。
        _outgoingChild = oldWidget.child;
        _phase = _StreamingRevealPhase.remove;
        _ctrl.forward(from: 0.0);
        _prevRenderLength = widget.textLength;
      }
    } else if (oldWidget.streaming) {
      _prevRenderLength = widget.textLength;
      _outgoingChild = null;
    } else {
      _prevRenderLength = widget.textLength;
      _outgoingChild = null;
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
      child: widget.streaming || _outgoingChild != null
          ? AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                final rawT = _ctrl.value;
                final outgoingChild = _outgoingChild;
                // 动画已稳定 → 跳过 ShaderMask，避免无意义 GPU 合成层。
                if (rawT >= 1.0 || outgoingChild == null) return child!;

                if (_phase == _StreamingRevealPhase.remove) {
                  return Stack(
                    fit: StackFit.passthrough,
                    clipBehavior: Clip.none,
                    children: [
                      child!,
                      IgnorePointer(
                        child: ExcludeSemantics(
                          child: FadeTransition(
                            opacity: ReverseAnimation(_ctrl),
                            child: outgoingChild,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                // Q 弹 spring 曲线：easeOutBack 在 1.0 处有轻微 overshoot
                // 再回弹，视觉上"字符从边界弹出来 → 落位"，精灵登场感。
                final springT = Curves.easeOutBack.transform(rawT);
                final alphaT = springT.clamp(0.0, 1.0);

                // 旧文本在整体中的高度占比（按字符数近似，对流式追加场景
                // 足够精准——新字符永远追加在末尾）。
                final curLen = widget.textLength;
                final oldFraction = _prevRenderLength > 0 && curLen > 0
                    ? (_prevRenderLength / curLen).clamp(0.0, 1.0)
                    : 0.0;

                // 波前位置：从旧文本边界扫向底部。easeOutBack 的 overshoot
                // 让波前冲过底部再弹回，肉眼呈 Q 弹落位。
                final newZone = 1.0 - oldFraction;
                final waveFront = (oldFraction + newZone * springT).clamp(
                  0.0,
                  1.0,
                );

                // 尾部（最新字符）alpha 从 0.28 弹升至 1.0。
                final tailAlpha = 0.28 + 0.72 * alphaT;

                // 波前处 alpha：略低于 1.0 的软过渡，避免一条硬切线。
                final waveAlpha = 0.58 + 0.42 * alphaT;

                // 梯度停靠点：[0, oldFraction, waveFront, 1.0]
                //  * oldFraction 以上：始终完全不透明（旧文本不受影响）
                //  * oldFraction → waveFront：从 opaque 线性过渡到 waveAlpha
                //  * waveFront → 1.0：从 waveAlpha 线性过渡到 tailAlpha
                // 波前扫过后渐变收窄，新字符逐批"亮相"。
                return Stack(
                  fit: StackFit.passthrough,
                  clipBehavior: Clip.none,
                  children: [
                    IgnorePointer(
                      child: ExcludeSemantics(child: outgoingChild),
                    ),
                    ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.0, oldFraction, waveFront, 1.0],
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.white.withValues(alpha: waveAlpha),
                          Colors.white.withValues(alpha: tailAlpha),
                        ],
                      ).createShader(bounds),
                      child: child,
                    ),
                  ],
                );
              },
              child: widget.child,
            )
          : widget.child,
    );
  }
}
