import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'motion_durations.dart';
import 'motion_preference.dart';

/// 传输进度由实际计量驱动；总量未知时仅显示状态与已传输量。
class OpenHandTransferProgress extends StatelessWidget {
  const OpenHandTransferProgress({
    super.key,
    required this.label,
    required this.detail,
    this.value,
  });

  final String label, detail;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = value;
    final progress = raw != null && raw.isFinite ? raw.clamp(0.0, 1.0) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            if (progress != null)
              Text(
                NumberFormat.decimalPercentPattern(
                  locale: Localizations.localeOf(context).toString(),
                  decimalDigits: 1,
                ).format(progress),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              borderRadius: BorderRadius.circular(6),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
