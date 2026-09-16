import 'package:flutter/material.dart';

import 'openhand_dialog_action_button.dart';
import 'openhand_spacing.dart';

/// 居中展示加载失败、空结果等状态，并可提供重试操作。
class OpenHandCenteredStateMessage extends StatelessWidget {
  const OpenHandCenteredStateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  static const double _maxWidth = 420;
  static const double _iconBoxSize = 72;
  static const double _iconSize = 34;
  static const EdgeInsets _padding = EdgeInsets.all(22);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: _padding,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(kOpenHandRadius22),
                ),
                child: SizedBox(
                  width: _iconBoxSize,
                  height: _iconBoxSize,
                  child: Icon(
                    icon,
                    size: _iconSize,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              kOpenHandGap16,
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              kOpenHandGap8,
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                kOpenHandGap16,
                OpenHandDialogActionButton.primary(
                  onPressed: onAction,
                  icon: Icons.refresh_rounded,
                  label: actionLabel!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
