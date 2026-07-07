import 'package:flutter/material.dart';

/// Error-container banner that surfaces a data persistence issue (recovered /
/// sanitized / save-failed) with a dismiss affordance.
///
/// Callers resolve the localized [title], [body] and [dismissLabel] from their
/// own feature l10n, so this widget stays free of any feature-specific strings.
/// When [dismissLabel] is null the dismiss control renders as a close icon
/// button (using [dismissTooltip]) instead of a text button.
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
            Icon(Icons.warning_amber_rounded, color: colorScheme.onErrorContainer),
            const SizedBox(width: 14),
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
                  const SizedBox(height: 6),
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
