import 'package:flutter/material.dart';

import 'motion_preference.dart';
import 'openhand_notice_actions.dart';

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
    final duration = openHandMotionDuration(
      context,
      const Duration(milliseconds: 220),
    );
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
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
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.icon, color: widget.foregroundColor),
          const SizedBox(width: 10),
          Expanded(
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
          const SizedBox(width: 8),
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
    final hasChild = child != null;
    if (!openHandTickerMotionEnabled(context)) {
      return hasChild
          ? KeyedSubtree(key: const ValueKey('notice-on'), child: child!)
          : const SizedBox.shrink(key: ValueKey('notice-off'));
    }
    final inMs = openHandMotionDurationMs(context, 320).inMilliseconds;
    final outMs = (openHandMotionDurationMs(
      context,
      240,
    ).inMilliseconds).clamp(0, inMs);
    return AnimatedSwitcher(
      duration: Duration(milliseconds: hasChild ? inMs : outMs),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1.0,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.06),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: hasChild
          ? KeyedSubtree(key: const ValueKey('notice-on'), child: child!)
          : const SizedBox.shrink(key: ValueKey('notice-off')),
    );
  }
}
