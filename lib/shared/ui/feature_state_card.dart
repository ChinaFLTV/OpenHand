import 'package:flutter/material.dart';

enum FeatureStateTone { neutral, primary, secondary, error }

enum FeatureStateCardStyle { centered, inline }

class FeatureStateCard extends StatelessWidget {
  const FeatureStateCard.centered({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.tone = FeatureStateTone.primary,
    this.action,
    this.maxWidth = 560,
  }) : style = FeatureStateCardStyle.centered,
       trailing = null;

  const FeatureStateCard.inline({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.tone = FeatureStateTone.neutral,
    this.trailing,
    this.maxWidth,
  }) : style = FeatureStateCardStyle.inline,
       action = null;

  final FeatureStateCardStyle style;
  final FeatureStateTone tone;
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final Widget? trailing;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = _FeatureStateToneColors.resolve(context, tone);
    final content = switch (style) {
      FeatureStateCardStyle.centered => _buildCentered(context, colors),
      FeatureStateCardStyle.inline => _buildInline(context, colors),
    };
    if (maxWidth == null) {
      return content;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth!),
      child: content,
    );
  }

  Widget _buildCentered(BuildContext context, _FeatureStateToneColors colors) {
    final theme = Theme.of(context);
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.iconBackground,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: colors.iconForeground),
              ),
              const SizedBox(height: 18),
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInline(BuildContext context, _FeatureStateToneColors colors) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.iconForeground),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.text,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

class _FeatureStateToneColors {
  const _FeatureStateToneColors({
    required this.background,
    required this.border,
    required this.iconBackground,
    required this.iconForeground,
    required this.text,
  });

  final Color background;
  final Color border;
  final Color iconBackground;
  final Color iconForeground;
  final Color text;

  static _FeatureStateToneColors resolve(
    BuildContext context,
    FeatureStateTone tone,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (tone) {
      FeatureStateTone.primary => _FeatureStateToneColors(
        background: colorScheme.primaryContainer.withValues(alpha: 0.55),
        border: colorScheme.primary.withValues(alpha: 0.22),
        iconBackground: colorScheme.primaryContainer,
        iconForeground: colorScheme.onPrimaryContainer,
        text: colorScheme.onPrimaryContainer,
      ),
      FeatureStateTone.secondary => _FeatureStateToneColors(
        background: colorScheme.secondaryContainer,
        border: colorScheme.secondary.withValues(alpha: 0.2),
        iconBackground: colorScheme.secondaryContainer,
        iconForeground: colorScheme.onSecondaryContainer,
        text: colorScheme.onSecondaryContainer,
      ),
      FeatureStateTone.error => _FeatureStateToneColors(
        background: colorScheme.errorContainer.withValues(alpha: 0.72),
        border: colorScheme.error.withValues(alpha: 0.22),
        iconBackground: colorScheme.errorContainer,
        iconForeground: colorScheme.onErrorContainer,
        text: colorScheme.onErrorContainer,
      ),
      FeatureStateTone.neutral => _FeatureStateToneColors(
        background: colorScheme.surfaceContainerHigh,
        border: colorScheme.outlineVariant,
        iconBackground: colorScheme.surfaceContainerHighest,
        iconForeground: colorScheme.onSurfaceVariant,
        text: colorScheme.onSurfaceVariant,
      ),
    };
  }
}
