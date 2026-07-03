import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'openhand_snack_bar.dart';

class OpenHandNoticeActionButtons extends StatelessWidget {
  const OpenHandNoticeActionButtons({
    super.key,
    required this.copyText,
    this.onDismiss,
    this.foregroundColor,
    this.showCopy = true,
    this.showClose = true,
  });

  static const double _buttonSize = 32;
  static const double _iconSize = 16;

  final String? copyText;
  final VoidCallback? onDismiss;
  final Color? foregroundColor;
  final bool showCopy;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final text = copyText;
    final canCopy = showCopy && text != null && text.trim().isNotEmpty;
    final canClose = showClose && onDismiss != null;
    if (!canCopy && !canClose) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final color = foregroundColor ?? IconTheme.of(context).color;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (canCopy)
          _NoticeIconButton(
            tooltip: l10n?.commonCopy ?? 'Copy',
            icon: Icons.content_copy_rounded,
            color: color,
            onPressed: () => _copy(context, text),
          ),
        if (canClose)
          _NoticeIconButton(
            tooltip:
                l10n?.commonClose ??
                MaterialLocalizations.of(context).closeButtonTooltip,
            icon: Icons.close_rounded,
            color: color,
            onPressed: onDismiss!,
          ),
      ],
    );
  }

  static Future<void> _copy(BuildContext context, String text) async {
    final l10n = AppLocalizations.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!context.mounted) return;
      OpenHandSnackBar.showInContext(
        context,
        OpenHandSnackBar.success(
          context,
          l10n?.commonCopiedToClipboard ?? 'Copied to clipboard',
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      OpenHandSnackBar.showInContext(
        context,
        OpenHandSnackBar.error(context, 'Copy failed: $error', maxLines: 2),
      );
    }
  }
}

class _NoticeIconButton extends StatelessWidget {
  const _NoticeIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color? color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: OpenHandNoticeActionButtons._buttonSize,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: OpenHandNoticeActionButtons._iconSize,
          color: color,
        ),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        splashRadius: 18,
      ),
    );
  }
}
