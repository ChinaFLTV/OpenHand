import 'package:flutter/material.dart';

import '../../shared/ui/animated_menu.dart';

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
  });

  final T value;
  final List<WebReverseSelectOption<T>> options;
  final ValueChanged<T>? onChanged;
  final String? tooltip;
  final IconData icon;
  final bool dense;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final current = _currentOption;
    final enabled = onChanged != null && options.isNotEmpty;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final height = dense ? 32.0 : 36.0;
    return AnimatedPopupMenuButton<T>(
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
                  const SizedBox(width: 8),
                  Icon(Icons.check_rounded, size: 16, color: cs.primary),
                ],
              ],
            ),
          ),
      ],
      child: AnimatedContainer(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: height,
        constraints: BoxConstraints(minWidth: minWidth ?? 0),
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10),
        decoration: BoxDecoration(
          color: enabled ? Colors.transparent : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: enabled
                ? cs.outlineVariant
                : cs.outlineVariant.withValues(alpha: 0.5),
          ),
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
            const SizedBox(width: 6),
            Icon(
              icon,
              size: dense ? 15 : 16,
              color: enabled ? cs.onSurfaceVariant : cs.outline,
            ),
          ],
        ),
      ),
    );
  }

  WebReverseSelectOption<T> get _currentOption {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return WebReverseSelectOption<T>(value: value, label: '$value');
  }
}
