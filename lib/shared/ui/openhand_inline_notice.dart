import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_notice_actions.dart';
import 'openhand_reveal_switcher.dart';

/// 内联通知卡片：用于在页面内展示错误、警告、提示等反馈。
/// 支持 Q弹进场退场动画（size + fade + 轻微 slide），受全局 reduce-motion
/// 和 TickerMode 偏好控制。
class OpenHandInlineNotice extends StatefulWidget {
  const OpenHandInlineNotice({
    super.key,
    required this.icon,
    required this.color,
    required this.foregroundColor,
    required this.message,
    this.copyText,
    this.onDismiss,
    this.showCopyAction = true,
    this.showCloseAction = true,
    this.messageStyle,
    this.maxMessageHeight,
  });

  final IconData icon;
  final Color color;
  final Color foregroundColor;
  final String message;
  final String? copyText;
  final VoidCallback? onDismiss;
  final bool showCopyAction;
  final bool showCloseAction;
  final TextStyle? messageStyle;
  final double? maxMessageHeight;

  @override
  State<OpenHandInlineNotice> createState() => _OpenHandInlineNoticeState();
}

class _OpenHandInlineNoticeState extends State<OpenHandInlineNotice> {
  bool _locallyDismissed = false;

  @override
  void didUpdateWidget(covariant OpenHandInlineNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.copyText != widget.copyText ||
        oldWidget.color != widget.color) {
      _locallyDismissed = false;
    }
  }

  void _dismiss() {
    final onDismiss = widget.onDismiss;
    if (onDismiss != null) {
      onDismiss();
      return;
    }
    setState(() => _locallyDismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    final child = _locallyDismissed
        ? const SizedBox.shrink(key: ValueKey('notice-dismissed'))
        : _buildNoticeCard(context);
    if (!openHandTickerMotionEnabled(context)) {
      return child;
    }
    final duration = openHandMotionDuration(context, kOpenHandMotion220);
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: kOpenHandSwitchInCurve,
      switchOutCurve: kOpenHandSwitchOutCurve,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.04),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildNoticeCard(BuildContext context) {
    return Container(
      key: ValueKey<Object>(widget.message),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.icon, color: widget.foregroundColor),
          kOpenHandHGap10,
          Expanded(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: widget.maxMessageHeight ?? double.infinity,
              ),
              child: SingleChildScrollView(
                primary: false,
                child: SelectableText(
                  widget.message,
                  style:
                      widget.messageStyle ??
                      Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: widget.foregroundColor,
                      ),
                ),
              ),
            ),
          ),
          kOpenHandHGap8,
          OpenHandNoticeActionButtons(
            copyText: widget.copyText ?? widget.message,
            onDismiss: widget.showCloseAction ? _dismiss : null,
            foregroundColor: widget.foregroundColor,
            showCopy: widget.showCopyAction,
            showClose: widget.showCloseAction,
          ),
        ],
      ),
    );
  }
}

/// 工厂：按语气自动选择图标与配色，避免各处重复硬编码。
class OpenHandInlineNoticeFactory {
  const OpenHandInlineNoticeFactory._();

  static OpenHandInlineNotice error(
    BuildContext context,
    String message, {
    String? copyText,
    VoidCallback? onDismiss,
    bool showCopyAction = true,
    bool showCloseAction = true,
    TextStyle? messageStyle,
    double? maxMessageHeight,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return OpenHandInlineNotice(
      icon: Icons.error_outline_rounded,
      color: scheme.errorContainer,
      foregroundColor: scheme.onErrorContainer,
      message: message,
      copyText: copyText,
      onDismiss: onDismiss,
      showCopyAction: showCopyAction,
      showCloseAction: showCloseAction,
      messageStyle: messageStyle,
      maxMessageHeight: maxMessageHeight,
    );
  }

  static OpenHandInlineNotice warning(
    BuildContext context,
    String message, {
    String? copyText,
    VoidCallback? onDismiss,
    bool showCopyAction = true,
    bool showCloseAction = true,
    TextStyle? messageStyle,
    double? maxMessageHeight,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return OpenHandInlineNotice(
      icon: Icons.warning_amber_rounded,
      color: scheme.tertiaryContainer,
      foregroundColor: scheme.onTertiaryContainer,
      message: message,
      copyText: copyText,
      onDismiss: onDismiss,
      showCopyAction: showCopyAction,
      showCloseAction: showCloseAction,
      messageStyle: messageStyle,
      maxMessageHeight: maxMessageHeight,
    );
  }
}

/// 通知卡片容器：用 AnimatedSwitcher + SizeTransition + FadeTransition + SlideTransition
/// 组合实现 Q弹丝滑的进场退场动画。
/// 用法：
/// ```
/// OpenHandInlineNoticeSlot(
///   child: condition ? OpenHandInlineNoticeFactory.error(ctx, msg) : null,
/// )
/// ```
class OpenHandInlineNoticeSlot extends StatelessWidget {
  const OpenHandInlineNoticeSlot({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return OpenHandVerticalRevealSwitcher(
      reverseDuration: kOpenHandVerticalRevealReverseDuration,
      slideBeginOffsetY: -0.06,
      presentKey: const ValueKey<String>('notice-on'),
      child: child,
    );
  }
}

/// 行内错误文本的默认外边距。
const EdgeInsets kOpenHandInlineErrorPadding = EdgeInsets.fromLTRB(
  20,
  0,
  20,
  8,
);

/// 面板内的一行错误文本：出现与消失走全局动效的纵向展开。
///
/// 插件服务与 MCP STDIO 的依赖弹窗各写了一份 `if (_error != null) Padding(...)`，
/// 报错出现时整块内容会被硬生生顶下去一次；重试期间错误反复出现 / 消失，
/// 观感就是列表在跳。
class OpenHandInlineErrorText extends StatelessWidget {
  const OpenHandInlineErrorText({
    super.key,
    required this.message,
    this.padding = kOpenHandInlineErrorPadding,
  });

  /// 为 null 表示无错误，此时收起为零高度。
  final String? message;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = message;
    return OpenHandVerticalRevealSwitcher(
      duration: kOpenHandInlineErrorRevealDuration,
      presentKey: ValueKey<String>(text ?? ''),
      child: text == null
          ? null
          : Padding(
              padding: padding,
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
    );
  }
}

/// 行内错误展开 / 收起的时长。
const Duration kOpenHandInlineErrorRevealDuration = Duration(milliseconds: 180);
