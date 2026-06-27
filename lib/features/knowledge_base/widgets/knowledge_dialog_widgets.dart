import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/theme/openhand_status_colors.dart';

const double kKnowledgeDialogSectionSpacing = 12;
const double kKnowledgeDialogFieldWidth = 212;
const double kKnowledgeDialogWideFieldWidth = 328;

class KnowledgeDialogSection extends StatelessWidget {
  const KnowledgeDialogSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.84),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.78,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!.trim(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.28,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class KnowledgeDialogKeyValueList extends StatelessWidget {
  const KnowledgeDialogKeyValueList({
    super.key,
    required this.rows,
    this.labelWidth = 156,
  });

  final Map<String, Object?> rows;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entries = rows.entries.toList(growable: false);
    if (entries.isEmpty) {
      return Text(
        '-',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < entries.length; index++)
          Container(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : 7,
              bottom: index == entries.length - 1 ? 0 : 7,
            ),
            decoration: BoxDecoration(
              border: index == entries.length - 1
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.52,
                        ),
                      ),
                    ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(
                    entries[index].key,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      height: 1.28,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SelectableText(
                    knowledgeDialogValue(entries[index].value),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class KnowledgeDialogJsonBox extends StatelessWidget {
  const KnowledgeDialogJsonBox({
    super.key,
    required this.value,
    this.maxHeight,
  });

  final Object? value;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final text = const JsonEncoder.withIndent('  ').convert(value);
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight ?? 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.56),
        ),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.38,
          ),
        ),
      ),
    );
  }
}

enum KnowledgeDialogNoticeTone { neutral, warning, error }

class KnowledgeDialogNotice extends StatelessWidget {
  const KnowledgeDialogNotice({
    super.key,
    required this.icon,
    required this.message,
    this.error = false,
    this.tone,
    this.trailing,
  });

  final IconData icon;
  final String message;
  final bool error;
  final KnowledgeDialogNoticeTone? tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _KnowledgeDialogNoticeColors.resolve(
      context,
      tone ??
          (error
              ? KnowledgeDialogNoticeTone.error
              : KnowledgeDialogNoticeTone.neutral),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: colors.icon),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.foreground,
                height: 1.32,
                fontWeight: colors.fontWeight,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Align(alignment: Alignment.centerRight, child: trailing),
          ],
        ],
      ),
    );
  }
}

class KnowledgeDialogNoticeAction extends StatelessWidget {
  const KnowledgeDialogNoticeAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tone = KnowledgeDialogNoticeTone.neutral,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final KnowledgeDialogNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _KnowledgeDialogNoticeColors.resolve(context, tone);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17, color: colors.icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.foreground,
        backgroundColor: colors.actionBackground,
        side: BorderSide(color: colors.actionBorder),
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

class _KnowledgeDialogNoticeColors {
  const _KnowledgeDialogNoticeColors({
    required this.background,
    required this.border,
    required this.foreground,
    required this.icon,
    required this.actionBackground,
    required this.actionBorder,
    this.fontWeight,
  });

  final Color background;
  final Color border;
  final Color foreground;
  final Color icon;
  final Color actionBackground;
  final Color actionBorder;
  final FontWeight? fontWeight;

  static _KnowledgeDialogNoticeColors resolve(
    BuildContext context,
    KnowledgeDialogNoticeTone tone,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (tone == KnowledgeDialogNoticeTone.neutral) {
      return _KnowledgeDialogNoticeColors(
        background: scheme.surfaceContainerHighest.withValues(alpha: 0.56),
        border: scheme.outlineVariant.withValues(alpha: 0.62),
        foreground: scheme.onSurfaceVariant,
        icon: scheme.onSurfaceVariant,
        actionBackground: scheme.surfaceContainerHighest,
        actionBorder: scheme.outlineVariant,
      );
    }
    final surface = scheme.surfaceContainerHigh;
    final foreground = scheme.onSurface;
    final accent = switch (tone) {
      KnowledgeDialogNoticeTone.neutral => scheme.onSurfaceVariant,
      KnowledgeDialogNoticeTone.warning => OpenHandStatusColors.warning,
      KnowledgeDialogNoticeTone.error => OpenHandStatusColors.error,
    };
    final tintAlpha = switch (tone) {
      KnowledgeDialogNoticeTone.neutral => 0.10,
      KnowledgeDialogNoticeTone.warning => 0.10,
      KnowledgeDialogNoticeTone.error => 0.10,
    };
    final borderAlpha = switch (tone) {
      KnowledgeDialogNoticeTone.neutral => 0.30,
      KnowledgeDialogNoticeTone.warning => 0.34,
      KnowledgeDialogNoticeTone.error => 0.30,
    };
    return _KnowledgeDialogNoticeColors(
      background: Color.alphaBlend(
        accent.withValues(alpha: tintAlpha),
        surface.withValues(alpha: 0.92),
      ),
      border: accent.withValues(alpha: borderAlpha),
      foreground: foreground,
      icon: accent,
      fontWeight: FontWeight.w600,
      actionBackground: Color.alphaBlend(
        accent.withValues(alpha: 0.10),
        scheme.surfaceContainerHighest,
      ),
      actionBorder: accent.withValues(alpha: 0.28),
    );
  }
}

class KnowledgeDialogTextBox extends StatelessWidget {
  const KnowledgeDialogTextBox({
    super.key,
    required this.text,
    this.maxHeight = 280,
    this.emptyText = '-',
  });

  final String text;
  final double maxHeight;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final value = text.trim().isEmpty ? emptyText : text;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.56),
        ),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.38,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class KnowledgeDialogChip extends StatelessWidget {
  const KnowledgeDialogChip({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration knowledgeDialogInputDecoration(
  BuildContext context,
  String label, {
  bool alignLabelWithHint = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: label,
    alignLabelWithHint: alignLabelWithHint,
    isDense: true,
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.84),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
    ),
  );
}

String knowledgeDialogValue(Object? value) {
  if (value == null) return '-';
  if (value is Map || value is List) return jsonEncode(value);
  final text = '$value'.trim();
  return text.isEmpty ? '-' : text;
}
