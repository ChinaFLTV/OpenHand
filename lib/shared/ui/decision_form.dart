import 'package:flutter/material.dart';

import '../util/decision_payload.dart';
import 'decision_copy.dart';
import 'micro_press_feedback.dart';
import 'openhand_spacing.dart';

Color openHandDecisionAccent(ColorScheme colors, String type) => switch (type) {
  DecisionPayload.typeChoice => colors.tertiary,
  DecisionPayload.typeScore => colors.secondary,
  _ => colors.primary,
};

Color openHandDecisionContainer(ColorScheme colors, String type) =>
    switch (type) {
      DecisionPayload.typeChoice => colors.tertiaryContainer,
      DecisionPayload.typeScore => colors.secondaryContainer,
      _ => colors.primaryContainer,
    };

Color openHandDecisionOnContainer(ColorScheme colors, String type) =>
    switch (type) {
      DecisionPayload.typeChoice => colors.onTertiaryContainer,
      DecisionPayload.typeScore => colors.onSecondaryContainer,
      _ => colors.onPrimaryContainer,
    };

IconData openHandDecisionTypeIcon(String type) => switch (type) {
  DecisionPayload.typeChoice => Icons.list_alt_rounded,
  DecisionPayload.typeScore => Icons.star_rounded,
  _ => Icons.verified_rounded,
};

TextStyle? openHandDecisionFieldLabelStyle(
  BuildContext context, {
  Color? color,
}) {
  final colors = Theme.of(context).colorScheme;
  return Theme.of(context).textTheme.labelSmall?.copyWith(
    color: color ?? colors.onSurfaceVariant,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
  );
}

InputDecoration openHandDecisionInputDecoration({
  required ColorScheme colors,
  String? hintText,
}) {
  final border = OutlineInputBorder(
    borderRadius: kOpenHandBorderRadius14,
    borderSide: BorderSide(
      color: colors.outlineVariant.withValues(alpha: 0.72),
    ),
  );
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: colors.surface,
    hoverColor: Colors.transparent,
    floatingLabelBehavior: FloatingLabelBehavior.never,
    isDense: true,
    counterText: '',
    contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: kOpenHandBorderRadius14,
      borderSide: BorderSide(color: colors.primary, width: 1.6),
    ),
  );
}

/// 决策输入区外壳：纯色分层、无渐变、无左侧色条、无悬停阴影。
class OpenHandDecisionFormShell extends StatelessWidget {
  const OpenHandDecisionFormShell({
    super.key,
    required this.type,
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.children,
    this.icon,
  });

  final String type;
  final String kicker;
  final String title;
  final String subtitle;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = openHandDecisionAccent(colors, type);
    final resolvedIcon = icon ?? openHandDecisionTypeIcon(type);
    return Material(
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: kOpenHandBorderRadius18,
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: openHandDecisionContainer(colors, type),
                      borderRadius: kOpenHandBorderRadius12,
                    ),
                    child: Icon(
                      resolvedIcon,
                      size: 20,
                      color: openHandDecisionOnContainer(colors, type),
                    ),
                  ),
                  kOpenHandHGap10,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kicker,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                        kOpenHandGap4,
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                        kOpenHandGap4,
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (children.isNotEmpty) ...[kOpenHandGap12, ...children],
            ],
          ),
        ),
      ),
    );
  }
}

class OpenHandDecisionLabeledField extends StatelessWidget {
  const OpenHandDecisionLabeledField({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: openHandDecisionFieldLabelStyle(context)),
        kOpenHandGap6,
        child,
      ],
    );
  }
}

/// 判断 / 选择 / 评分三段纯色切换，选中项使用类型色容器。
class OpenHandDecisionTypeSwitch extends StatelessWidget {
  const OpenHandDecisionTypeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final copy = DecisionCopy.of(context);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: copy.typeGroupLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: kOpenHandBorderRadius16,
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.62),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (final type in DecisionPayload.types)
                Expanded(
                  child: _DecisionTypeTab(
                    type: type,
                    label: copy.typeLabel(type),
                    selected: value == type,
                    enabled: enabled,
                    onTap: () => onChanged(type),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecisionTypeTab extends StatelessWidget {
  const _DecisionTypeTab({
    required this.type,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String type;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected
        ? openHandDecisionOnContainer(colors, type)
        : colors.onSurfaceVariant;
    return MicroPressFeedback(
      enabled: enabled,
      child: Material(
        color: selected
            ? openHandDecisionContainer(colors, type)
            : Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        borderRadius: kOpenHandBorderRadius12,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: kOpenHandBorderRadius12,
          hoverColor: Colors.transparent,
          overlayColor: WidgetStatePropertyAll(
            openHandDecisionAccent(colors, type).withValues(alpha: 0.08),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  openHandDecisionTypeIcon(type),
                  size: 16,
                  color: foreground,
                ),
                kOpenHandHGap6,
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
