import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import 'motion_preference.dart';

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
            color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
          kOpenHandHGap10,
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
    );
  }
}
