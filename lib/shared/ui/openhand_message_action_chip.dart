import 'package:flutter/material.dart';

const double kOpenHandMessageActionChipHeight = 34;
const double kOpenHandMessageActionChipHorizontalPadding = 10;
const double kOpenHandMessageActionChipVerticalPadding = 6;
const double kOpenHandMessageActionIconSize = 16;

ButtonStyle openHandMessageActionChipStyle(BuildContext context) {
  final theme = Theme.of(context);
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, kOpenHandMessageActionChipHeight),
    padding: const EdgeInsets.symmetric(
      horizontal: kOpenHandMessageActionChipHorizontalPadding,
      vertical: kOpenHandMessageActionChipVerticalPadding,
    ),
    textStyle: theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

class OpenHandMessageActionChip extends StatelessWidget {
  const OpenHandMessageActionChip({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseStyle = openHandMessageActionChipStyle(context);
    final style = selected
        ? baseStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(
              colors.primaryContainer.withValues(alpha: 0.72),
            ),
            foregroundColor: WidgetStatePropertyAll(colors.onPrimaryContainer),
            iconColor: WidgetStatePropertyAll(colors.onPrimaryContainer),
            side: WidgetStatePropertyAll(
              BorderSide(color: colors.primary.withValues(alpha: 0.62)),
            ),
          )
        : baseStyle;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: kOpenHandMessageActionIconSize),
      label: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
  }
}
