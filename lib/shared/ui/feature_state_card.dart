import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import 'openhand_notice_actions.dart';

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
    this.copyText,
    this.onDismiss,
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
    this.copyText,
    this.onDismiss,
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
  final String? copyText;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = _FeatureStateToneColors.resolve(context, tone);
    return switch (style) {
      FeatureStateCardStyle.centered => _buildCentered(context, colors),
      FeatureStateCardStyle.inline => _buildInline(context, colors),
    };
  }

  Widget _buildCentered(BuildContext context, _FeatureStateToneColors colors) {
    final theme = Theme.of(context);
    final noticeActions = _buildNoticeActions(context, colors);
    return Center(
      child: _constrain(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors.iconBackground,
                      borderRadius: BorderRadius.circular(kOpenHandRadius24),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: colors.iconForeground),
                  ),
                  kOpenHandGap18,
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  kOpenHandGap10,
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (action != null || noticeActions != null) ...[
                    kOpenHandGap20,
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (noticeActions != null) noticeActions,
                        if (action != null) action!,
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInline(BuildContext context, _FeatureStateToneColors colors) {
    final theme = Theme.of(context);
    final noticeActions = _buildNoticeActions(context, colors);
    final trailingActions = trailing == null && noticeActions == null
        ? null
        : Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (noticeActions != null) noticeActions,
              if (trailing != null) trailing!,
            ],
          );
    final textArea = _InlineTextArea(
      title: title,
      body: body,
      titleStyle: theme.textTheme.titleLarge?.copyWith(color: colors.text),
      bodyStyle: theme.textTheme.bodyMedium?.copyWith(color: colors.text),
    );
    final card = Container(
      width: maxWidth == null ? double.infinity : null,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(kOpenHandRadius18),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: maxWidth == null ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.iconForeground),
          kOpenHandHGap14,
          if (maxWidth == null)
            Expanded(child: textArea)
          else
            Flexible(child: textArea),
          if (trailingActions != null) ...[kOpenHandHGap12, trailingActions],
        ],
      ),
    );
    return maxWidth == null
        ? card
        : Align(alignment: Alignment.centerLeft, child: _constrain(card));
  }

  Widget _constrain(Widget child) {
    final width = maxWidth;
    if (width == null) {
      return child;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    );
  }

  Widget? _buildNoticeActions(
    BuildContext context,
    _FeatureStateToneColors colors,
  ) {
    final effectiveCopyText =
        copyText ?? (tone == FeatureStateTone.error ? body : null);
    final hasCopy = effectiveCopyText?.trim().isNotEmpty == true;
    final hasClose = onDismiss != null;
    if (!hasCopy && !hasClose) return null;
    return OpenHandNoticeActionButtons(
      copyText: effectiveCopyText,
      onDismiss: onDismiss,
      foregroundColor: colors.text,
      showCopy: hasCopy,
      showClose: hasClose,
    );
  }
}

class _InlineTextArea extends StatelessWidget {
  const _InlineTextArea({
    required this.title,
    required this.body,
    required this.titleStyle,
    required this.bodyStyle,
  });

  final String title;
  final String body;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      primary: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
          kOpenHandGap6,
          SelectableText(body, style: bodyStyle),
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
