import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import 'openhand_reveal_switcher.dart';

const double kOpenHandDialogActionButtonWidth = 164;
const double kOpenHandDialogActionButtonHeight = 54;

/// 弹窗内的忙碌进度条：出现与消失都走全局动效，不做生硬的插入与移除。
class OpenHandDialogBusyBar extends StatelessWidget {
  const OpenHandDialogBusyBar({
    super.key,
    required this.busy,
    this.topGap = 12,
  });

  final bool busy;

  /// 展开时与上方内容的间距；收起时一并折叠，不留空洞。
  final double topGap;

  @override
  Widget build(BuildContext context) {
    return OpenHandVerticalRevealSwitcher(
      presentKey: const ValueKey<String>('openhand-dialog-busy-bar'),
      child: busy
          ? Padding(
              padding: EdgeInsets.only(top: topGap),
              child: const LinearProgressIndicator(),
            )
          : null,
    );
  }
}

/// 弹窗内的错误提示行：出现、切换与消失都走全局动效，不做生硬的插入与移除。
///
/// [message] 为空即收起并折叠掉 [topGap]；换成另一条错误时按内容重建，
/// 由 AnimatedSwitcher 完成交叉过渡。
class OpenHandDialogErrorText extends StatelessWidget {
  const OpenHandDialogErrorText({
    super.key,
    required this.message,
    this.topGap = 12,
    this.style,
  });

  final String? message;
  final double topGap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = message?.trim() ?? '';
    return OpenHandVerticalRevealSwitcher(
      presentKey: ValueKey<String>('openhand-dialog-error-$text'),
      child: text.isEmpty
          ? null
          : Padding(
              padding: EdgeInsets.only(top: topGap),
              child: Text(
                text,
                style:
                    style ??
                    theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
              ),
            ),
    );
  }
}

/// 弹窗底部的「取消 / 确认」动作区。
///
/// [busy] 期间禁用两个按钮以防重复提交，并平滑展开进度条。
/// [onCancel] 缺省为不携带结果关闭弹窗，避免与弹窗声明的结果类型冲突。
class OpenHandDialogSaveActions extends StatelessWidget {
  const OpenHandDialogSaveActions({
    super.key,
    required this.busy,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onConfirm,
    this.onCancel,
  });

  final bool busy;
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OpenHandDialogBusyBar(busy: busy),
        kOpenHandGap22,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OpenHandDialogActionButton.secondary(
              onPressed: busy
                  ? null
                  : (onCancel ?? () => Navigator.of(context).pop()),
              label: cancelLabel,
            ),
            kOpenHandHGap12,
            OpenHandDialogActionButton.primary(
              onPressed: busy ? null : onConfirm,
              label: confirmLabel,
            ),
          ],
        ),
      ],
    );
  }
}

class OpenHandDialogActionButton extends StatelessWidget {
  const OpenHandDialogActionButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.shape,
  }) : _variant = _OpenHandDialogActionButtonVariant.primary;

  const OpenHandDialogActionButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.shape,
  }) : _variant = _OpenHandDialogActionButtonVariant.destructive;

  const OpenHandDialogActionButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.shape,
  }) : _variant = _OpenHandDialogActionButtonVariant.secondary;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final OutlinedBorder? shape;
  final _OpenHandDialogActionButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonStyle = ButtonStyle(
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle?>(
        theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: shape == null
          ? null
          : WidgetStatePropertyAll<OutlinedBorder>(shape!),
    );
    final label = _OpenHandDialogActionButtonLabel(label: this.label);
    Widget child = label;
    if (busy) {
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          kOpenHandHGap10,
          Flexible(child: label),
        ],
      );
    } else if (icon != null) {
      child = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          kOpenHandHGap8,
          Flexible(child: label),
        ],
      );
    }
    return SizedBox(
      width: kOpenHandDialogActionButtonWidth,
      height: kOpenHandDialogActionButtonHeight,
      child: switch (_variant) {
        _OpenHandDialogActionButtonVariant.primary => FilledButton(
          onPressed: onPressed,
          style: buttonStyle,
          child: child,
        ),
        _OpenHandDialogActionButtonVariant.destructive => FilledButton(
          onPressed: onPressed,
          style: buttonStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll<Color>(
              theme.colorScheme.error,
            ),
            foregroundColor: WidgetStatePropertyAll<Color>(
              theme.colorScheme.onError,
            ),
          ),
          child: child,
        ),
        _OpenHandDialogActionButtonVariant.secondary => FilledButton.tonal(
          onPressed: onPressed,
          style: buttonStyle,
          child: child,
        ),
      },
    );
  }
}

enum _OpenHandDialogActionButtonVariant { primary, secondary, destructive }

class _OpenHandDialogActionButtonLabel extends StatelessWidget {
  const _OpenHandDialogActionButtonLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        textAlign: TextAlign.center,
      ),
    );
  }
}
