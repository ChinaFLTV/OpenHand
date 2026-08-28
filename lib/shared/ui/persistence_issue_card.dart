import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

/// 可关闭的数据持久化异常卡片；文案由调用方完成本地化。
class PersistenceIssueCard extends StatelessWidget {
  const PersistenceIssueCard({
    super.key,
    required this.title,
    required this.body,
    required this.onDismiss,
    this.dismissLabel,
    this.dismissTooltip,
  });

  final String title;
  final String body;
  final String? dismissLabel;
  final String? dismissTooltip;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: colorScheme.onErrorContainer,
            ),
            kOpenHandHGap14,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                  kOpenHandGap6,
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: dismissLabel == null ? 8 : 12),
            if (dismissLabel case final label?)
              TextButton(
                onPressed: onDismiss,
                child: Text(
                  label,
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              )
            else
              IconButton(
                onPressed: onDismiss,
                tooltip: dismissTooltip,
                icon: Icon(
                  Icons.close_rounded,
                  color: colorScheme.onErrorContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
