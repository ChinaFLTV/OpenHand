import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import 'animated_dialog.dart';
import 'hover_lift.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'oh_pill.dart';
import 'openhand_dialog_action_button.dart';
import 'openhand_typography.dart';

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
  });

  final IconData icon;
  final IconData? disabledIcon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
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
                    kOpenHandGap3,
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
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

/// 编辑弹窗顶栏摘要胶囊：名称、状态、版本等一眼可扫。
class OpenHandSummaryChip extends StatelessWidget {
  const OpenHandSummaryChip({
    super.key,
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    this.monospace = false,
    this.maxWidth = 280,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final bool monospace;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: kOpenHandPillBorderRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            kOpenHandHGap6,
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontFamily: monospace ? kOpenHandMonospaceFontFamily : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分区列表卡：悬浮上浮 + 点击，不再画左侧色条。
class OpenHandHoverCard extends StatelessWidget {
  const OpenHandHoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 18, 18),
    this.elevation,
    this.shape,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double? elevation;
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      child: Card(
        elevation: elevation,
        clipBehavior: Clip.antiAlias,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
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
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
  });

  final Color accent;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.08),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// 编辑弹窗公共骨架：工具头 + 可选摘要 + 滚动分区 + 固定页脚。
///
/// 进退场走 [showAnimatedDialog] 的全局弹窗动画；页脚钉住避免长表单挡住保存。
class OpenHandEditorDialogScaffold extends StatelessWidget {
  const OpenHandEditorDialogScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    required this.actions,
    this.subtitle,
    this.iconColor,
    this.summary,
    this.busy = false,
    this.closeEnabled = true,
    this.canPop = true,
    this.maxWidth = kOpenHandDialogWidthWide,
    this.maxHeight = kOpenHandDialogHeightTall,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final Widget? summary;
  final Widget body;
  final List<Widget> actions;
  final bool busy;
  final bool closeEnabled;
  final bool canPop;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: canPop,
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        safeAreaMinimum: kOpenHandDialogDefaultInsetPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildOpenHandToolDialogHeader(
              context: context,
              icon: icon,
              iconColor: iconColor ?? colorScheme.primary,
              title: title,
              subtitle: subtitle,
              closeEnabled: closeEnabled,
            ),
            if (summary != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: summary,
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: body,
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.94),
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
