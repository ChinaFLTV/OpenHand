import 'package:flutter/material.dart';

const double kOpenHandDialogActionButtonWidth = 164;
const double kOpenHandDialogActionButtonHeight = 54;

class OpenHandDialogActionButton extends StatelessWidget {
  const OpenHandDialogActionButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
  }) : _variant = _OpenHandDialogActionButtonVariant.primary;

  const OpenHandDialogActionButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
  }) : _variant = _OpenHandDialogActionButtonVariant.secondary;

  final String label;
  final VoidCallback? onPressed;
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
    final child = Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
      textAlign: TextAlign.center,
    );
    return SizedBox(
      width: kOpenHandDialogActionButtonWidth,
      height: kOpenHandDialogActionButtonHeight,
      child: switch (_variant) {
        _OpenHandDialogActionButtonVariant.primary => FilledButton(
          onPressed: onPressed,
          style: buttonStyle,
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

enum _OpenHandDialogActionButtonVariant { primary, secondary }
