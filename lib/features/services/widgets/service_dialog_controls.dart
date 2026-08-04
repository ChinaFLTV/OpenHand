import 'package:flutter/material.dart';

import '../../../shared/util/localized_text.dart';
import '../model/ai_exposure_models.dart';
import '../services_controller.dart';

const double kServiceDialogItemActionGap = 8;

enum ServiceDialogHeaderActionTone { neutral, primary }

String serviceProxyRouteText(
  ServicesController controller,
  OpenHandLocalizedTextResolver text, {
  bool includePoolCount = true,
}) => switch (controller.proxyRoute) {
  AiExposureProxyRoute.pool =>
    includePoolCount
        ? text(
            zh: '代理池 ${controller.proxyConfiguration.activeEndpoints.length} 节点',
            en: 'Proxy pool · ${controller.proxyConfiguration.activeEndpoints.length} nodes',
          )
        : text(zh: '代理池', en: 'Proxy pool'),
  AiExposureProxyRoute.system => text(zh: '系统代理', en: 'System proxy'),
  AiExposureProxyRoute.direct => 'DIRECT',
};

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

class ServiceDialogCompactIconButton extends StatelessWidget {
  const ServiceDialogCompactIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.foregroundColor,
    this.size = 40,
  }) : assert(size > 0);

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final Color? foregroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = foregroundColor ?? colors.onSurfaceVariant;
    final buttonSize = Size.square(size);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(buttonSize),
        maximumSize: WidgetStatePropertyAll(buttonSize),
        fixedSize: WidgetStatePropertyAll(buttonSize),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: 0.38)
              : color,
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.transparent;
          if (states.contains(WidgetState.pressed)) {
            return color.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return color.withValues(alpha: 0.08);
          }
          return Colors.transparent;
        }),
        shape: const WidgetStatePropertyAll(CircleBorder()),
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
    this.accentColor,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? icon;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final chipTheme = ChipTheme.of(context);
    final backgroundColor =
        chipTheme.backgroundColor ?? colors.surfaceContainerHigh;
    final selectedColor = accentColor == null
        ? chipTheme.selectedColor ?? colors.primaryContainer
        : Color.alphaBlend(
            accentColor!.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.20 : 0.12,
            ),
            colors.surfaceContainerHigh,
          );
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
      side: accentColor == null
          ? null
          : BorderSide(
              color: accentColor!.withValues(alpha: selected ? 0.48 : 0.20),
            ),
      labelStyle: accentColor == null
          ? null
          : TextStyle(
              color: selected ? colors.onSurface : colors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
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
