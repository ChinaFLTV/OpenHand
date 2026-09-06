import 'package:flutter/material.dart';

import 'openhand_spacing.dart';

/// 面板或卡片内的轻量空态提示。
class OpenHandInlineEmptyState extends StatelessWidget {
  const OpenHandInlineEmptyState({
    super.key,
    required this.message,
    this.icon,
    this.dense = false,
    this.textAlign = TextAlign.center,
  }) : compact = false;

  const OpenHandInlineEmptyState.compact({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.textAlign = TextAlign.start,
  }) : dense = true,
       compact = true;

  final String message;

  /// 可选前导图标。
  final IconData? icon;

  /// 紧凑档：用于卡片内、侧栏这类空间本就局促的位置。
  final bool dense;

  final TextAlign textAlign;

  final bool compact;

  /// 两档内边距。标准档给主面板留出呼吸，紧凑档只留最小间隙。
  static const double _kStandardPadding = 24;
  static const double _kDensePadding = 16;
  static const double _kIconSize = 40;
  static const double _kIconGap = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (compact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.62),
          borderRadius: kOpenHandBorderRadius7,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.62),
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
              kOpenHandHGap8,
            ],
            Expanded(
              child: Text(
                message,
                textAlign: textAlign,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final style =
        (dense ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4);
    final text = Text(message, textAlign: textAlign, style: style);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(dense ? _kDensePadding : _kStandardPadding),
        child: icon == null
            ? text
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: _kIconSize,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                  const SizedBox(height: _kIconGap),
                  text,
                ],
              ),
      ),
    );
  }
}
