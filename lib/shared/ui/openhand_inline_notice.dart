import 'package:flutter/material.dart';

import 'motion_preference.dart';

/// 内联通知卡片：用于在页面内展示错误、警告、提示等反馈。
/// 支持 Q弹进场退场动画（size + fade + 轻微 slide），受全局 reduce-motion 偏好控制。
class OpenHandInlineNotice extends StatelessWidget {
  const OpenHandInlineNotice({
    super.key,
    required this.icon,
    required this.color,
    required this.foregroundColor,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final Color foregroundColor;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foregroundColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foregroundColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// 错误 / 警告 / 信息三类通知的语义色调。
enum OpenHandNoticeTone { error, warning, info, success }

/// 工厂：按语气自动选择图标与配色，避免各处重复硬编码。
class OpenHandInlineNoticeFactory {
  const OpenHandInlineNoticeFactory._();

  static OpenHandInlineNotice error(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return OpenHandInlineNotice(
      icon: Icons.error_outline_rounded,
      color: scheme.errorContainer,
      foregroundColor: scheme.onErrorContainer,
      message: message,
    );
  }

  static OpenHandInlineNotice warning(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return OpenHandInlineNotice(
      icon: Icons.warning_amber_rounded,
      color: scheme.tertiaryContainer,
      foregroundColor: scheme.onTertiaryContainer,
      message: message,
    );
  }

  static OpenHandInlineNotice info(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return OpenHandInlineNotice(
      icon: Icons.info_outline_rounded,
      color: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      message: message,
    );
  }

  static OpenHandInlineNotice success(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return OpenHandInlineNotice(
      icon: Icons.check_circle_outline_rounded,
      color: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      message: message,
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
    final inMs = openHandMotionDurationMs(context, 320).inMilliseconds;
    final outMs = (openHandMotionDurationMs(context, 240).inMilliseconds)
        .clamp(0, inMs);
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
