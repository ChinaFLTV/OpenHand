import 'package:flutter/material.dart';

import '../../shared/ui/animated_menu.dart';
import '../../shared/ui/motion_durations.dart';
import '../../shared/ui/motion_preference.dart';
import '../../shared/ui/oh_pill.dart';
import '../../shared/ui/openhand_spacing.dart';

class WebReverseSelectOption<T> {
  const WebReverseSelectOption({required this.value, required this.label});

  final T value;
  final String label;
}

class WebReverseSelectButton<T> extends StatelessWidget {
  const WebReverseSelectButton({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.tooltip,
    this.icon = Icons.expand_more_rounded,
    this.dense = false,
    this.minWidth,
    this.outlined = true,
    this.fillWidth = false,
  });

  final T value;
  final List<WebReverseSelectOption<T>> options;
  final ValueChanged<T>? onChanged;
  final String? tooltip;
  final IconData icon;
  final bool dense;
  final double? minWidth;
  final bool outlined;
  final bool fillWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final current = _currentOption;
    final enabled = onChanged != null && options.isNotEmpty;
    final height = dense ? 32.0 : 36.0;
    final button = AnimatedPopupMenuButton<T>(
      enabled: enabled,
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final option in options)
          PopupMenuItem<T>(
            value: option.value,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: option.value == value
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: option.value == value ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
                if (option.value == value) ...[
                  kOpenHandHGap8,
                  Icon(Icons.check_rounded, size: 16, color: cs.primary),
                ],
              ],
            ),
          ),
      ],
      child: AnimatedContainer(
        duration: openHandMotionDuration(context, kOpenHandMotion180),
        curve: kOpenHandSwitchInCurve,
        height: height,
        constraints: BoxConstraints(minWidth: minWidth ?? 0),
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10),
        decoration: BoxDecoration(
          color: outlined && !enabled
              ? cs.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: kOpenHandPillBorderRadius,
          border: outlined
              ? Border.all(
                  color: enabled
                      ? cs.outlineVariant
                      : cs.outlineVariant.withValues(alpha: 0.5),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                current.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ),
            kOpenHandHGap6,
            Icon(
              icon,
              size: dense ? 15 : 16,
              color: enabled ? cs.onSurfaceVariant : cs.outline,
            ),
          ],
        ),
      ),
    );
    if (!fillWidth) return button;
    return SizedBox(width: double.infinity, child: button);
  }

  WebReverseSelectOption<T> get _currentOption {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return WebReverseSelectOption<T>(value: value, label: '$value');
  }
}

class WebReverseSelectFormField<T> extends FormField<T> {
  WebReverseSelectFormField({
    super.key,
    required T initialValue,
    required List<WebReverseSelectOption<T>> options,
    ValueChanged<T>? onChanged,
    InputDecoration decoration = const InputDecoration(),
    String? tooltip,
    super.enabled = true,
    bool dense = true,
    double? menuMinWidth,
  }) : super(
         initialValue: initialValue,
         builder: (state) {
           final theme = Theme.of(state.context);
           final effectiveDecoration = decoration
               .applyDefaults(theme.inputDecorationTheme)
               .copyWith(errorText: state.errorText, enabled: enabled);
           final currentValue = state.value ?? initialValue;
           return InputDecorator(
             decoration: effectiveDecoration,
             child: WebReverseSelectButton<T>(
               value: currentValue,
               options: options,
               dense: dense,
               minWidth: menuMinWidth,
               outlined: false,
               fillWidth: true,
               tooltip: tooltip,
               onChanged: enabled
                   ? (value) {
                       state.didChange(value);
                       onChanged?.call(value);
                     }
                   : null,
             ),
           );
         },
       );
}
