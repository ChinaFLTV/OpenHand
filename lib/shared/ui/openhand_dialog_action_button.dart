import 'package:flutter/material.dart';

const double kOpenHandDialogActionButtonWidth = 164;
const double kOpenHandDialogActionButtonHeight = 54;

class OpenHandDialogActionButton extends StatelessWidget {
  const OpenHandDialogActionButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  }) : _variant = _OpenHandDialogActionButtonVariant.primary;

  const OpenHandDialogActionButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  }) : _variant = _OpenHandDialogActionButtonVariant.destructive;

  const OpenHandDialogActionButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  }) : _variant = _OpenHandDialogActionButtonVariant.secondary;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final _OpenHandDialogActionButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonStyle = ButtonStyle(
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle?>(
        theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final label = Text(
      this.label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
      textAlign: TextAlign.center,
    );
    Widget child = label;
    if (busy) {
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Flexible(child: label),
        ],
      );
    } else if (icon != null) {
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Flexible(child: label),
        ],
      );
    }
    return SizedBox(
      width: kOpenHandDialogActionButtonWidth,
      height: kOpenHandDialogActionButtonHeight,
      child: switch (_variant) {
        _OpenHandDialogActionButtonVariant.primary => FilledButton(
          onPressed: onPressed,
          style: buttonStyle,
          child: child,
        ),
        _OpenHandDialogActionButtonVariant.destructive => FilledButton(
          onPressed: onPressed,
          style: buttonStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll<Color>(
              theme.colorScheme.error,
            ),
            foregroundColor: WidgetStatePropertyAll<Color>(
              theme.colorScheme.onError,
            ),
          ),
          child: child,
        ),
        _OpenHandDialogActionButtonVariant.secondary => FilledButton.tonal(
          onPressed: onPressed,
          style: buttonStyle,
          child: child,
        ),
      },
    );
  }
}

enum _OpenHandDialogActionButtonVariant { primary, secondary, destructive }
