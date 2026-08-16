import 'package:flutter/material.dart';

import '../../shared/ui/openhand_spacing.dart';
import 'highlight_pulse.dart';

/// 把 [child] 套上一个「首帧后自动 pulse 一次」的高亮条。用于在用户首次
/// 看到某个区块（例如 Settings 滚动到某段落、首次打开某个 dialog tab）时，
/// 让目标行/卡片短暂高亮一下，引导视线但不抢焦点。
///
/// 触发策略：[State.initState] 注册 [WidgetsBinding.addPostFrameCallback]，
/// 下一帧 mounted 时自增内部 `ValueNotifier<int>`。[HighlightPulse] 监听到
/// 自增即 fadeIn+decay。同一个 State 实例只会 pulse 一次；切换/重建会重新
/// 生成 State，因此每次进入页面都会高亮一次。
///
/// 共享 motion preference 由内部的 [HighlightPulse] 自动处理（直接跳过动画）。
class FirstFramePulseBox extends StatefulWidget {
  const FirstFramePulseBox({
    super.key,
    required this.child,
    this.borderRadius = kOpenHandBorderRadius2,
  });

  final Widget child;
  final BorderRadiusGeometry borderRadius;

  @override
  State<FirstFramePulseBox> createState() => _FirstFramePulseBoxState();
}

class _FirstFramePulseBoxState extends State<FirstFramePulseBox> {
  final ValueNotifier<int> _pulse = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pulse.value = _pulse.value + 1;
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            child: HighlightPulse(
              signal: _pulse,
              borderRadius: widget.borderRadius,
            ),
          ),
        ),
      ],
    );
  }
}
