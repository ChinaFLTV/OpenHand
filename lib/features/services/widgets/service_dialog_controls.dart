import 'package:flutter/material.dart';

const double kServiceDialogItemActionGap = 8;

enum ServiceDialogHeaderActionTone { neutral, primary }

class ServiceDialogHeaderIconButton extends StatelessWidget {
  const ServiceDialogHeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.tone = ServiceDialogHeaderActionTone.neutral,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final ServiceDialogHeaderActionTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isPrimary = tone == ServiceDialogHeaderActionTone.primary;
    final background = isPrimary
        ? colors.primary
        : colors.surfaceContainerHighest;
    final foreground = isPrimary ? colors.onPrimary : colors.onSurfaceVariant;
    final interactionColor = isPrimary ? colors.onPrimary : colors.primary;

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.surfaceContainerHighest.withValues(alpha: 0.48);
          }
          final opacity = states.contains(WidgetState.pressed)
              ? 0.14
              : states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
              ? 0.08
              : 0.0;
          return opacity == 0
              ? background
              : Color.alphaBlend(
                  interactionColor.withValues(alpha: opacity),
                  background,
                );
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: 0.38)
              : foreground,
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
    );
  }
}

class ServiceDialogInteractionTheme extends StatelessWidget {
  const ServiceDialogInteractionTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    );
    return Theme(
      data: theme.copyWith(
        hoverColor: Colors.transparent,
        cardTheme: theme.cardTheme.copyWith(
          margin: const EdgeInsets.all(0),
          color: colors.surfaceContainerHighest.withValues(alpha: 0.24),
          surfaceTintColor: Colors.transparent,
          shape: shape.copyWith(side: BorderSide(color: colors.outlineVariant)),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.28),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: colors.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: colors.primary, width: 1.4),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: const WidgetStatePropertyAll(shape),
            side: WidgetStatePropertyAll(
              BorderSide(color: colors.outlineVariant),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest.withValues(alpha: 0.2);
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant;
            }),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
            shape: const WidgetStatePropertyAll(shape),
          ),
        ),
      ),
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
