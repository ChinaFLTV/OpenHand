import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/collision_safe_animated_switcher.dart';
import '../../../shared/ui/motion_preference.dart';

/// 正文与状态卡共用尺寸过渡，退场内容不再撑住布局或接收点击。
class DingTalkMessageContentTransition extends StatelessWidget {
  const DingTalkMessageContentTransition({
    super.key,
    required this.expanded,
    required this.child,
    this.streaming = false,
    this.alignment = Alignment.topLeft,
  });

  final bool expanded;
  final bool streaming;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = openHandMotionSettingsOf(
      context,
      OpenHandMotionSettingsScope.dialog,
    );
    final duration = streaming
        ? Duration.zero
        : expanded
        ? settings.entranceDuration
        : settings.exitDuration;
    if (duration == Duration.zero) return child;

    return LayoutBuilder(
      builder: (context, constraints) => AnimatedSize(
        duration: duration,
        alignment: alignment,
        curve: expanded ? settings.curve.curve : settings.curve.reverseCurve,
        child: AnimatedSwitcher(
          duration: duration,
          layoutBuilder: (currentChild, previousChildren) =>
              buildCollisionSafeAnimatedSwitcherLayout(
                currentChild,
                // 退场正文保持原布局宽度，避免收窄时文字、图片瞬间重排。
                previousChildren
                    .map(
                      (child) => OverflowBox(
                        key: child.key,
                        alignment: alignment,
                        minWidth: constraints.minWidth,
                        maxWidth: constraints.maxWidth,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        fit: OverflowBoxFit.deferToChild,
                        child: child,
                      ),
                    )
                    .toList(growable: false),
                alignment: alignment,
                sizeToCurrentChild: true,
              ),
          transitionBuilder: (child, animation) => AnimatedBuilder(
            animation: animation,
            child: child,
            builder: (context, child) => buildAnimationStyleTransition(
              animation: animation,
              settings: settings,
              profile: OpenHandAnimationTransitionProfile(alignment: alignment),
              child: child!,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
