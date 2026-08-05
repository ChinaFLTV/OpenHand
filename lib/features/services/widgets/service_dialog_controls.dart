import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/hover_lift.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/util/localized_text.dart';
import '../model/ai_exposure_models.dart';
import '../services_controller.dart';

const double kServiceDialogItemActionGap = 8;
const BorderRadius kServiceInteractiveBorderRadius = BorderRadius.all(
  Radius.circular(8),
);

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
      child: SelectionArea(child: child),
    );
  }
}

class ServiceDetailField {
  const ServiceDetailField({required this.label, required this.value});

  final String label;
  final String value;
}

String formatServiceDetailValue(Object? value) {
  if (value == null) return '--';
  if (value is String) return value.trim().isEmpty ? '--' : value;
  if (value is DateTime) return value.toLocal().toIso8601String();
  if (value is Map || value is Iterable) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } on JsonUnsupportedObjectError {
      return '$value';
    }
  }
  return '$value';
}

List<ServiceDetailField> serviceDetailFieldsFromMap(
  Map<String, Object?> values, {
  Map<String, String> labels = const <String, String>{},
}) => values.entries
    .map(
      (entry) => ServiceDetailField(
        label: labels[entry.key] ?? entry.key,
        value: formatServiceDetailValue(entry.value),
      ),
    )
    .toList(growable: false);

Future<void> showServiceDetailsDialog(
  BuildContext context, {
  required String title,
  required List<ServiceDetailField> fields,
  String? subtitle,
  IconData icon = Icons.manage_search_rounded,
}) => showAnimatedDialog<void>(
  context: context,
  builder: (dialogContext) => buildOpenHandResponsiveDialogShell(
    context: dialogContext,
    maxWidth: kOpenHandDialogWidthStandard,
    maxHeight: kOpenHandDialogHeightStandard,
    minAvailableWidth: 300,
    horizontalMargin: 28,
    verticalMargin: 72,
    expandToMax: true,
    child: ServiceDialogInteractionTheme(
      child: _ServiceDetailsDialog(
        title: title,
        subtitle: subtitle,
        icon: icon,
        fields: fields,
      ),
    ),
  ),
);

class ServiceInteractiveSurface extends StatelessWidget {
  const ServiceInteractiveSurface({
    super.key,
    required this.onTap,
    required this.child,
    this.tooltip,
    this.padding = const EdgeInsets.all(10),
    this.margin = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.showDetailsIcon = true,
  });

  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final Color? borderColor;
  final bool showDetailsIcon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label =
        tooltip ??
        openHandLocalizedText(context, zh: '查看完整详情', en: 'View full details');
    final content = Row(
      children: [
        Expanded(child: child),
        if (showDetailsIcon) ...[
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: colors.onSurfaceVariant,
          ),
        ],
      ],
    );
    final surface = Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: kServiceInteractiveBorderRadius,
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!),
      ),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        color: color ?? Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: kServiceInteractiveBorderRadius,
          child: Padding(padding: padding, child: content),
        ),
      ),
    );
    return Padding(
      padding: margin,
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: HoverLift(liftDistance: 1, child: surface),
        ),
      ),
    );
  }
}

class _ServiceDetailsDialog extends StatelessWidget {
  const _ServiceDetailsDialog({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fields,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<ServiceDetailField> fields;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    final copyPayload = fields
        .map((field) => '${field.label}: ${field.value}')
        .join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: kServiceInteractiveBorderRadius,
                ),
                child: Icon(icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ServiceDialogHeaderIconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.outlineVariant),
        Expanded(
          child: fields.isEmpty
              ? Center(
                  child: Text(
                    text(zh: '暂无可用详情。', en: 'No details available.'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: fields.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _ServiceDetailFieldTile(field: fields[index]),
                ),
        ),
        Divider(height: 1, color: colors.outlineVariant),
        buildOpenHandDialogActionsBar(
          actions: [
            OpenHandDialogActionButton.secondary(
              label: text(zh: '关闭', en: 'Close'),
              icon: Icons.close_rounded,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            OpenHandDialogActionButton.primary(
              label: text(zh: '复制全部', en: 'Copy all'),
              icon: Icons.copy_all_rounded,
              onPressed: fields.isEmpty
                  ? null
                  : () => copyOpenHandTextToClipboard(
                      context: context,
                      text: copyPayload,
                      logTag: 'service_details',
                      logAction: '复制全部详情',
                    ),
            ),
          ],
          padding: const EdgeInsets.all(14),
        ),
      ],
    );
  }
}

class _ServiceDetailFieldTile extends StatelessWidget {
  const _ServiceDetailFieldTile({required this.field});

  final ServiceDetailField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 6, 11),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: kServiceInteractiveBorderRadius,
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ServiceDialogCompactIconButton(
                tooltip: openHandLocalizedText(
                  context,
                  zh: '复制此字段',
                  en: 'Copy field',
                ),
                size: 34,
                icon: const Icon(Icons.copy_rounded, size: 17),
                onPressed: () => copyOpenHandTextToClipboard(
                  context: context,
                  text: field.value,
                  logTag: 'service_details',
                  logAction: '复制详情字段',
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          SelectableText(
            field.value,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
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
