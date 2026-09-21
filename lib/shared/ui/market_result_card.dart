import 'package:flutter/material.dart';

import 'micro_press_feedback.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_spacing.dart';

/// 市场结果共用选中态、强调色边条与按压反馈，动效遵循全局设置。
class MarketResultCard extends StatelessWidget {
  const MarketResultCard({
    super.key,
    required this.accent,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final Color accent;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const radius = kOpenHandBorderRadius18;
    return MicroPressFeedback(
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: Colors.transparent,
          splashColor: accent.withValues(alpha: 0.10),
          highlightColor: accent.withValues(alpha: 0.06),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: AnimatedContainer(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            curve: kOpenHandSwitchInCurve,
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(
                      accent.withValues(alpha: 0.16),
                      colors.surface,
                    )
                  : colors.surface,
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? accent
                    : colors.outlineVariant.withValues(alpha: 0.78),
              ),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  PositionedDirectional(
                    start: 0,
                    top: 0,
                    bottom: 0,
                    width: kOpenHandAccentBarWidth,
                    child: ColoredBox(color: accent),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
