import 'package:flutter/material.dart';

const double kServiceDialogItemActionGap = 8;

class ServiceDialogInteractionTheme extends StatelessWidget {
  const ServiceDialogInteractionTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(hoverColor: Colors.transparent),
      child: child,
    );
  }
}

class ServiceFilterChip extends StatelessWidget {
  const ServiceFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final chipTheme = ChipTheme.of(context);
    final backgroundColor =
        chipTheme.backgroundColor ?? colors.surfaceContainerHigh;
    final selectedColor = chipTheme.selectedColor ?? colors.primaryContainer;
    return FilterChip(
      selected: selected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            IconTheme.merge(data: const IconThemeData(size: 17), child: icon!),
            const SizedBox(width: 7),
          ],
          label,
        ],
      ),
      onSelected: onSelected,
      showCheckmark: icon == null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      pressElevation: 0,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      color: WidgetStateProperty.resolveWith((states) {
        final base = states.contains(WidgetState.selected)
            ? selectedColor
            : backgroundColor;
        final alpha = states.contains(WidgetState.pressed)
            ? 0.10
            : states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
            ? 0.05
            : 0.0;
        return alpha == 0
            ? base
            : Color.alphaBlend(colors.primary.withValues(alpha: alpha), base);
      }),
    );
  }
}

class ServiceDialogIconActions extends StatelessWidget {
  const ServiceDialogIconActions({
    super.key,
    required this.children,
    this.spacing = kServiceDialogItemActionGap,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) SizedBox(width: spacing),
        children[index],
      ],
    ],
  );
}
