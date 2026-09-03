import 'package:flutter/material.dart';

import 'micro_press_feedback.dart';
import 'motion_durations.dart';
import 'motion_preference.dart';
import 'openhand_spacing.dart';

const Radius kOpenHandPillRadius = Radius.circular(999);
const BorderRadius kOpenHandPillBorderRadius = BorderRadius.all(
  kOpenHandPillRadius,
);

/// 左侧图标、右侧文本的通用胶囊。
class OhPill extends StatelessWidget {
  const OhPill({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedForeground = foregroundColor ?? theme.colorScheme.primary;
    final child = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: kOpenHandPillBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: resolvedForeground),
          kOpenHandHGap6,
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor ?? theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return MicroPressFeedback(
      child: Material(
        color: Colors.transparent,
        borderRadius: kOpenHandPillBorderRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: kOpenHandPillBorderRadius,
          overlayColor: WidgetStatePropertyAll<Color>(
            theme.colorScheme.primary.withValues(alpha: 0.08),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 带强调色边框的图标状态胶囊。
class OpenHandStatusPill extends StatelessWidget {
  const OpenHandStatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            kOpenHandHGap7,
            // Flexible：在卡片等窄约束下收缩省略，避免固定 maxWidth 把 Row 撑爆。
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 行内计量胶囊：高对比容器底上的一行次级小字，用于超时、条数这类数值标注。
class OpenHandMetricChip extends StatelessWidget {
  const OpenHandMetricChip({super.key, required this.label, this.tooltip});

  final String label;

  /// 非空时整体套一层 Tooltip。
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
    final message = tooltip;
    if (message == null) return chip;
    return Tooltip(message: message, child: chip);
  }
}

/// 列表行尾的「编辑 + 删除」按钮对。
class OpenHandRowEditDeleteActions extends StatelessWidget {
  const OpenHandRowEditDeleteActions({
    super.key,
    required this.editTooltip,
    required this.deleteTooltip,
    required this.onEdit,
    required this.onDelete,
  });

  final String editTooltip;
  final String deleteTooltip;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onEdit,
          tooltip: editTooltip,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          onPressed: onDelete,
          tooltip: deleteTooltip,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

/// 工具执行状态胶囊；图标随状态平滑切换。
class OpenHandToolChip extends StatelessWidget {
  const OpenHandToolChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  /// 图标切换时长：状态在 preparing → running → done 之间流转，硬切会很跳。
  static const Duration _kIconMorphDuration = kOpenHandMotion220;

  static const double _kIconSize = 14;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: kOpenHandPillBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 淡入 + 90° 旋转的同位切换，让状态流转看起来是一次形变而不是硬切。
          // key 取图标码点，AnimatedSwitcher 才认得出「换了一个图标」。
          AnimatedSwitcher(
            duration: openHandMotionDuration(context, _kIconMorphDuration),
            switchInCurve: kOpenHandSwitchInCurve,
            switchOutCurve: kOpenHandSwitchOutCurve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: RotationTransition(
                turns: Tween<double>(begin: -0.25, end: 0).animate(animation),
                child: child,
              ),
            ),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.center,
              children: <Widget>[...previous, if (current != null) current],
            ),
            child: Icon(
              icon,
              size: _kIconSize,
              key: ValueKey<int>(icon.codePoint),
            ),
          ),
          kOpenHandHGap6,
          // 工作目录、耗时这类长文案在窄 Wrap 行里会撑爆 chip 触发 RenderFlex
          // 溢出；缩略展示并让上层 Wrap 自行换行。
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
