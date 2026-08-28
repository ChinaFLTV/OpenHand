import 'package:flutter/material.dart';

import 'animated_dialog.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_live_value.dart';
import 'openhand_ops_press_scale.dart';
import 'openhand_spacing.dart';

class OpenHandOperationsCopyText extends StatelessWidget {
  const OpenHandOperationsCopyText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.selectable = true,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final content = Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: style,
    );
    return selectable ? SelectionArea(child: content) : content;
  }
}

List<Widget> buildOpenHandOperationsInsightContent({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String subtitle,
  required Color tone,
  required List<Widget> sections,
  required double sectionSpacing,
}) {
  final theme = Theme.of(context);
  final colors = theme.colorScheme;
  return [
    Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(kOpenHandRadius13),
            border: Border.all(color: tone.withValues(alpha: 0.26)),
          ),
          child: Icon(icon, color: tone),
        ),
        kOpenHandHGap10,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OpenHandOperationsCopyText(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle.trim().isNotEmpty) ...[
                kOpenHandGap3,
                OpenHandLiveValue(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
    kOpenHandGap14,
    Flexible(
      child: ListView.separated(
        shrinkWrap: true,
        physics: openHandDialogAwareScrollPhysics(context),
        padding: EdgeInsets.zero,
        itemCount: sections.length,
        separatorBuilder: (_, _) => SizedBox(height: sectionSpacing),
        itemBuilder: (_, index) => sections[index],
      ),
    ),
  ];
}

class OpenHandOperationsDetailRows extends StatelessWidget {
  const OpenHandOperationsDetailRows({
    super.key,
    required this.rows,
    this.empty,
    this.labelWidth = 180,
  });

  final Map<String, String> rows;
  final Widget? empty;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final visibleRows = rows.entries
        .where((row) => row.value.trim().isNotEmpty)
        .toList(growable: false);
    if (visibleRows.isEmpty) return empty ?? const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in visibleRows.indexed)
          Padding(
            padding: EdgeInsets.only(
              bottom: row.$1 == visibleRows.length - 1 ? 0 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth,
                  child: OpenHandOperationsCopyText(
                    row.$2.key,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: OpenHandLiveValue(
                    row.$2.value,
                    selectable: true,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 运维页面统一信息面板，集中维护表面、标题区与点击反馈。
class OpenHandOperationsPanel extends StatelessWidget {
  const OpenHandOperationsPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    required this.radius,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.expandWidth = false,
  });

  final IconData icon;
  final Widget title;
  final Widget child;
  final double radius;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool expandWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final subtitleText = subtitle?.trim();
    final panel = AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion180),
      curve: kOpenHandSwitchInCurve,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.62),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(kOpenHandRadius11),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Icon(icon, size: 19, color: colors.primary),
                ),
                kOpenHandHGap11,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      if (subtitleText != null && subtitleText.isNotEmpty) ...[
                        kOpenHandGap3,
                        OpenHandLiveValue(
                          subtitleText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[kOpenHandHGap8, trailing!],
                if (trailing == null && onTap != null) ...[
                  kOpenHandHGap8,
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.primary.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
            kOpenHandGap14,
            child,
          ],
        ),
      ),
    );
    final content = expandWidth
        ? SizedBox(width: double.infinity, child: panel)
        : panel;
    if (onTap == null) return content;
    return OpenHandOpsPressScale(
      onTap: onTap,
      radius: radius,
      tone: colors.primary,
      child: content,
    );
  }
}

/// 运维子弹窗统一双层表面，外层提供浮层边界，内层负责状态过渡。
class OpenHandOperationsDialogFrame extends StatelessWidget {
  const OpenHandOperationsDialogFrame({
    super.key,
    required this.outerRadius,
    required this.innerRadius,
    required this.child,
  });

  final double outerRadius;
  final double innerRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(outerRadius),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.72),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.18),
            blurRadius: 38,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AnimatedContainer(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          curve: kOpenHandSwitchInCurve,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(innerRadius),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.74),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
