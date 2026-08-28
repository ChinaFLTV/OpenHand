import 'package:flutter/material.dart';

import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_live_value.dart';
import 'openhand_ops_press_scale.dart';
import 'openhand_spacing.dart';

/// 运维页面统一信息面板，集中维护表面、标题区与点击反馈。
class OpenHandOperationsPanel extends StatelessWidget {
  const OpenHandOperationsPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    required this.radius,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.expandWidth = false,
  });

  final IconData icon;
  final Widget title;
  final Widget child;
  final double radius;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool expandWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final subtitleText = subtitle?.trim();
    final panel = AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion180),
      curve: kOpenHandSwitchInCurve,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.62),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(kOpenHandRadius11),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Icon(icon, size: 19, color: colors.primary),
                ),
                kOpenHandHGap11,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      if (subtitleText != null && subtitleText.isNotEmpty) ...[
                        kOpenHandGap3,
                        OpenHandLiveValue(
                          subtitleText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[kOpenHandHGap8, trailing!],
                if (trailing == null && onTap != null) ...[
                  kOpenHandHGap8,
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.primary.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
            kOpenHandGap14,
            child,
          ],
        ),
      ),
    );
    final content = expandWidth
        ? SizedBox(width: double.infinity, child: panel)
        : panel;
    if (onTap == null) return content;
    return OpenHandOpsPressScale(
      onTap: onTap,
      radius: radius,
      tone: colors.primary,
      child: content,
    );
  }
}
