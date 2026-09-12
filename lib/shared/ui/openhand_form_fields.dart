import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import 'animated_dialog.dart';
import 'hover_lift.dart';
import 'micro_press_feedback.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_dialog_action_button.dart';

/// 隐藏 TextField 的 `maxLength` 计数器。
///
/// 用于既要靠 `maxLength` 做硬性截断、又不想让 "12/200" 计数占位撑高布局的
/// 输入框：`TextField(buildCounter: openHandHiddenTextFieldCounter)`。
Widget? openHandHiddenTextFieldCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) => null;

/// 把外部状态回填到文本控制器，用于 `build` / `didUpdateWidget` 中的受控输入。
///
/// 依次跳过三类无需回填的场景，避免打断输入或触发多余重建：
/// - [previous] 与 [value] 相同：外部值未变化，保留用户正在编辑的内容；
/// - [focusNode] 持有焦点：光标停留在该输入框上；
/// - 控制器文本已与 [value] 一致。
///
/// 回填后光标落到文本末尾，规避直接赋值 `controller.text` 造成的光标丢失。
void syncTextControllerText(
  TextEditingController controller,
  String value, {
  String? previous,
  FocusNode? focusNode,
}) {
  if (previous == value) return;
  if (focusNode?.hasFocus ?? false) return;
  if (controller.text == value) return;
  controller.value = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );
}

class OpenHandFormLabel extends StatelessWidget {
  const OpenHandFormLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          if (required)
            TextSpan(
              text: '* ',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          TextSpan(text: text),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
        kOpenHandHGap8,
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
                  borderRadius: BorderRadius.circular(kOpenHandRadius6),
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
    this.badge,
    this.enabled = true,
  });

  final IconData icon;
  final IconData? disabledIcon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? badge;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        borderRadius: BorderRadius.circular(kOpenHandRadius10),
        child: AnimatedContainer(
          duration: openHandMotionDuration(context, kOpenHandMotion220),
          curve: kOpenHandSwitchInCurve,
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: value
                ? colorScheme.primaryContainer.withValues(alpha: 0.42)
                : colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(kOpenHandRadius10),
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
                color: value
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (badge != null) ...[kOpenHandHGap8, badge!],
                      ],
                    ),
                    if (description.trim().isNotEmpty) ...[
                      kOpenHandGap3,
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch(value: value, onChanged: enabled ? onChanged : null),
            ],
          ),
        ),
      ),
    );
  }
}

/// 二选一/多选手写卡片：图标 + 标题 + 可选说明，选中态走主题色。
class OpenHandSelectTile extends StatelessWidget {
  const OpenHandSelectTile({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
    this.enabled = true,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final String? hint;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tone = selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    final hint = this.hint?.trim();
    return MicroPressFeedback(
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: kOpenHandBorderRadius16,
          child: AnimatedContainer(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            curve: kOpenHandSwitchInCurve,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.72)
                  : colorScheme.surface,
              borderRadius: kOpenHandBorderRadius16,
              border: Border.all(
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.62)
                    : colorScheme.outlineVariant,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primary.withValues(alpha: 0.16)
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: kOpenHandBorderRadius12,
                  ),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(child: Icon(icon, size: 18, color: tone)),
                  ),
                ),
                kOpenHandHGap10,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                        ),
                      ),
                      if (hint != null && hint.isNotEmpty) ...[
                        kOpenHandGap2,
                        Text(
                          hint,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected) ...[
                  kOpenHandHGap8,
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹窗表单的分组卡片：色点图标 + 标题/说明 + 可选尾部动作 + 内容区。
///
/// 长表单此前各自手写一份浅底圆角容器，标题层级和间距容易分叉。
/// 这里收敛为一份，按 [accent] 给分组上色，保证结构一眼可扫。
class OpenHandDialogSectionCard extends StatelessWidget {
  const OpenHandDialogSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.accent,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tone = accent ?? colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tone.withValues(alpha: 0.07),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: kOpenHandBorderRadius20,
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.16),
                    borderRadius: kOpenHandBorderRadius12,
                  ),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(child: Icon(icon, size: 18, color: tone)),
                  ),
                ),
                kOpenHandHGap10,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        kOpenHandGap2,
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[kOpenHandHGap8, trailing!],
              ],
            ),
            kOpenHandGap14,
            child,
          ],
        ),
      ),
    );
  }
}

const double kOpenHandListIdentityExtent = 64;
const double kOpenHandListIdentityIconSize = 31;
const double kOpenHandListCardRadius = 22;
const double kOpenHandListCardHeaderBreakpoint = 820;
const double kOpenHandIdentityStatusDotSize = 18;
const EdgeInsets kOpenHandListCardPadding = EdgeInsets.all(18);
const EdgeInsets kOpenHandMetricsStripPadding = EdgeInsets.symmetric(
  horizontal: 14,
  vertical: 14,
);
const double kOpenHandMetricsStripBreakpoint = 720;
const double kOpenHandMetricsStripTwoColumnMinWidth = 220;

typedef OpenHandMetricItem = ({String label, String value, Color accent});

/// 列表卡身份徽标：与消息网关同族，主题色实心底 + 可选状态点。
class OpenHandIdentityBadge extends StatelessWidget {
  const OpenHandIdentityBadge({
    super.key,
    required this.icon,
    this.statusColor,
    this.extent = kOpenHandListIdentityExtent,
    this.iconSize = kOpenHandListIdentityIconSize,
    this.topStart,
  });

  final IconData icon;
  final Color? statusColor;
  final double extent;
  final double iconSize;
  final Widget? topStart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final motionEnabled = openHandTickerMotionEnabled(context);
    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: kOpenHandBorderRadius18,
      ),
      child: SizedBox(
        width: extent,
        height: extent,
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
    final statusColor = this.statusColor;
    if (topStart == null && statusColor == null) return badge;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        badge,
        if (topStart != null) Positioned(left: -4, top: -4, child: topStart!),
        if (statusColor != null)
          Positioned(
            right: -3,
            bottom: -3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                shape: BoxShape.circle,
                boxShadow: motionEnabled
                    ? [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.32),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                Icons.circle,
                color: statusColor,
                size: kOpenHandIdentityStatusDotSize,
              ),
            ),
          ),
      ],
    );
  }
}

/// 列表卡标题区：标题 + 说明，可选左侧功能控件（如拖拽手柄）。
class OpenHandListIdentity extends StatelessWidget {
  const OpenHandListIdentity({
    super.key,
    required this.title,
    this.description,
    this.leading,
    this.descriptionMaxLines = 3,
  });

  final String title;
  final String? description;
  final Widget? leading;
  final int descriptionMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final description = this.description?.trim();
    final maxLines = descriptionMaxLines < 1 ? 1 : descriptionMaxLines;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (description != null && description.isNotEmpty) ...[
          kOpenHandGap8,
          Text(
            description,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
    if (leading == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading!,
        kOpenHandHGap12,
        Expanded(child: text),
      ],
    );
  }
}

/// 卡片底部指标条：圆点标签 + 强调色数值，与消息网关运行指标同族。
class OpenHandMetricsStrip extends StatelessWidget {
  const OpenHandMetricsStrip({super.key, required this.items});

  final List<OpenHandMetricItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= kOpenHandMetricsStripBreakpoint &&
            items.length > 1;
        final innerWidth =
            constraints.maxWidth > kOpenHandMetricsStripPadding.horizontal
            ? constraints.maxWidth - kOpenHandMetricsStripPadding.horizontal
            : constraints.maxWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(kOpenHandRadius16),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: kOpenHandMetricsStripPadding,
            child: wide
                ? IntrinsicHeight(
                    child: Row(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                          Expanded(child: _OpenHandMetricCell(item: items[i])),
                        ],
                      ],
                    ),
                  )
                : Wrap(
                    spacing: 10,
                    runSpacing: 12,
                    children: [
                      for (final item in items)
                        SizedBox(
                          width:
                              innerWidth >=
                                      kOpenHandMetricsStripTwoColumnMinWidth &&
                                  items.length > 1
                              ? (innerWidth - 10) / 2
                              : innerWidth,
                          child: _OpenHandMetricCell(item: item),
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _OpenHandMetricCell extends StatelessWidget {
  const _OpenHandMetricCell({required this.item});

  final OpenHandMetricItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final value = item.value.trim().isEmpty ? '—' : item.value.trim();
    return AnimatedContainer(
      duration: openHandMotionDuration(context, kOpenHandMotion180),
      curve: kOpenHandSwitchInCurve,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: item.accent,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 8, height: 8),
              ),
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: item.accent,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 分区列表卡：悬浮上浮 + 点击，圆角与描边对齐消息网关平台卡。
class OpenHandHoverCard extends StatelessWidget {
  const OpenHandHoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = kOpenHandListCardPadding,
    this.elevation = 0,
    this.shape,
    this.color,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double? elevation;
  final ShapeBorder? shape;
  final Color? color;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return HoverLift(
      child: Card(
        elevation: elevation,
        color: color,
        clipBehavior: Clip.antiAlias,
        shape:
            shape ??
            RoundedRectangleBorder(
              borderRadius:
                  borderRadius ??
                  BorderRadius.circular(kOpenHandListCardRadius),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

const double _kFeatureIconDisabledBackgroundAlpha = 0.42;
const double _kFeatureIconDisabledForegroundAlpha = 0.45;

/// 列表卡圆形操作钮，配色对齐全局 [IconButtonTheme]（surfaceContainerHigh）。
ButtonStyle openHandFeatureCircleIconButtonStyle(ColorScheme colorScheme) {
  return IconButton.styleFrom(
    shape: const CircleBorder(),
    backgroundColor: colorScheme.surfaceContainerHigh,
    foregroundColor: colorScheme.onSurfaceVariant,
    disabledBackgroundColor: colorScheme.surfaceContainerHighest.withValues(
      alpha: _kFeatureIconDisabledBackgroundAlpha,
    ),
    disabledForegroundColor: colorScheme.onSurfaceVariant.withValues(
      alpha: _kFeatureIconDisabledForegroundAlpha,
    ),
  );
}

class OpenHandFeatureIconButton extends StatelessWidget {
  const OpenHandFeatureIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      style: openHandFeatureCircleIconButtonStyle(
        Theme.of(context).colorScheme,
      ),
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
    );
  }
}

/// 功能列表卡骨架：身份带 / 状态胶囊 / 事实芯片 / 可选脚注 / 底部指标条。
///
/// 版式对齐消息网关平台卡，避免各模块再手写一套分层。
class OpenHandFeatureListCard extends StatelessWidget {
  const OpenHandFeatureListCard({
    super.key,
    required this.identity,
    this.actions = const <Widget>[],
    this.statusPills = const <Widget>[],
    this.factChips = const <Widget>[],
    this.footer,
    this.metrics = const <OpenHandMetricItem>[],
    this.onTap,
    this.headerBreakpoint = kOpenHandListCardHeaderBreakpoint,
    this.fillHeight = false,
  });

  final Widget identity;
  final List<Widget> actions;
  final List<Widget> statusPills;
  final List<Widget> factChips;
  final Widget? footer;
  final List<OpenHandMetricItem> metrics;
  final VoidCallback? onTap;
  final double headerBreakpoint;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final actionBar = actions.isEmpty
        ? null
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: actions,
            ),
          );
    final header = actionBar == null
        ? identity
        : LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  headerBreakpoint > 0 &&
                  constraints.maxWidth < headerBreakpoint;
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    kOpenHandGap16,
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: actionBar,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  kOpenHandHGap16,
                  actionBar,
                ],
              );
            },
          );
    final body = <Widget>[
      header,
      if (statusPills.isNotEmpty) ...[
        kOpenHandGap16,
        Wrap(spacing: 10, runSpacing: 10, children: statusPills),
      ],
      if (factChips.isNotEmpty) ...[
        kOpenHandGap12,
        Wrap(spacing: 8, runSpacing: 8, children: factChips),
      ],
      if (footer != null) ...[kOpenHandGap14, footer!],
    ];
    final metricsStrip = metrics.isEmpty
        ? null
        : OpenHandMetricsStrip(items: metrics);
    return OpenHandHoverCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (fillHeight && metricsStrip != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...body, const Spacer()],
              ),
            )
          else ...[
            ...body,
            if (fillHeight) const Spacer(),
          ],
          if (metricsStrip != null) ...[kOpenHandGap16, metricsStrip],
        ],
      ),
    );
  }
}

/// 卡片内的浅色信息块：标题/正文分区用色块分层，不用竖条。
class OpenHandTintedPanel extends StatelessWidget {
  const OpenHandTintedPanel({
    super.key,
    required this.accent,
    required this.child,
    this.icon,
    this.title,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
  });

  final Color accent;
  final Widget child;
  final IconData? icon;
  final String? title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final heading = title?.trim();
    final body = heading == null || heading.isEmpty
        ? child
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: accent),
                    kOpenHandHGap8,
                  ],
                  Expanded(
                    child: Text(
                      heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              kOpenHandGap8,
              child,
            ],
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.12),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Padding(padding: padding, child: body),
    );
  }
}

/// 编辑弹窗公共骨架：工具头 + 正文 + 固定页脚。
///
/// 进退场走 [showAnimatedDialog] 的全局弹窗动画；页脚钉住避免长表单挡住保存。
/// [scrollBody] 为 true 时高度按内容收缩，超过 [maxHeight] 后正文滚动，
/// 宽高变化走 [OpenHandAnimatedDialogSize]；为 false 时撑满最大高度，
/// 供 Tab 等需要 [Expanded] 的布局使用。
class OpenHandEditorDialogScaffold extends StatelessWidget {
  const OpenHandEditorDialogScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    required this.actions,
    this.subtitle,
    this.iconColor,
    this.headerActions = const <Widget>[],
    this.busy = false,
    this.closeEnabled = true,
    this.canPop = true,
    this.scrollBody = true,
    this.maxWidth = kOpenHandDialogWidthWide,
    this.maxHeight = kOpenHandDialogHeightTall,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final List<Widget> headerActions;
  final Widget body;
  final List<Widget> actions;
  final bool busy;
  final bool closeEnabled;
  final bool canPop;
  final bool scrollBody;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fillHeight = !scrollBody;
    return PopScope(
      canPop: canPop,
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        expandToMax: fillHeight,
        safeAreaMinimum: kOpenHandDialogDefaultInsetPadding,
        child: Column(
          mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildOpenHandToolDialogHeader(
              context: context,
              icon: icon,
              iconColor: iconColor ?? colorScheme.primary,
              title: title,
              subtitle: subtitle,
              actions: headerActions,
              closeEnabled: closeEnabled,
            ),
            Flexible(
              fit: fillHeight ? FlexFit.tight : FlexFit.loose,
              child: scrollBody
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      child: body,
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: body,
                    ),
            ),
            if (actions.isEmpty)
              const SizedBox.shrink()
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh.withValues(
                    alpha: 0.94,
                  ),
                  border: Border(
                    top: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OpenHandDialogBusyBar(busy: busy, topGap: 0),
                      if (busy) kOpenHandGap10,
                      buildOpenHandDialogActionsBar(
                        padding: EdgeInsets.zero,
                        actions: actions,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
