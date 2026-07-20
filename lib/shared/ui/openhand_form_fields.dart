import 'package:flutter/material.dart';

import 'motion_preference.dart';

class OpenHandFormLabel extends StatelessWidget {
  const OpenHandFormLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class OpenHandDirectoryField extends StatelessWidget {
  const OpenHandDirectoryField({
    super.key,
    required this.controller,
    required this.label,
    required this.hintText,
    required this.browseTooltip,
    required this.onBrowse,
    this.helperText,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final String browseTooltip;
  final VoidCallback onBrowse;
  final String? helperText;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hintText,
              helperText: helperText,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: browseTooltip,
          child: SizedBox(
            width: 44,
            height: 52,
            child: OutlinedButton(
              onPressed: onBrowse,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.6),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
              child: const Icon(Icons.folder_open_rounded, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

class OpenHandAnimatedSwitchTile extends StatelessWidget {
  const OpenHandAnimatedSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    this.disabledIcon,
  });

  static const Duration _animationDuration = Duration(milliseconds: 220);

  final IconData icon;
  final IconData? disabledIcon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AnimatedContainer(
      duration: openHandMotionDuration(context, _animationDuration),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: value
            ? colorScheme.primaryContainer.withValues(alpha: 0.42)
            : colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value
              ? colorScheme.primary.withValues(alpha: 0.46)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            value ? icon : disabledIcon ?? icon,
            size: 18,
            color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
