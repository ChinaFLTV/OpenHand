import 'package:flutter/material.dart';

const Radius kOpenHandPillRadius = Radius.circular(999);
const BorderRadius kOpenHandPillBorderRadius = BorderRadius.all(
  kOpenHandPillRadius,
);

/// 通用的 32px 高、圆角药丸状 chip：左侧小图标 + 右侧文本，可选 onTap。
///
/// 设计来自 harness session header 的 `_HePill`，这里抽到 shared 让
/// settings / mcp 等其他面板也能复用同一视觉。
///
/// - [foregroundColor] 同时控制图标颜色和文本颜色（默认 primary）；传入
///   `null` 时文本回落到 `onSurface`，图标始终用 [foregroundColor] ?? primary。
/// - [onTap] 非空时整体可点击，套一层 InkWell + 8% primary overlay。
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
          const SizedBox(width: 6),
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
    return Material(
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
    );
  }
}

/// 行内计量胶囊：高对比容器底上的一行次级小字，用于超时、条数这类数值标注。
///
/// Hooks 与定时任务列表此前各内联一份逐字相同的实现。这是个视觉 token，散着
/// 写迟早分叉——两处并排出现在同类列表里，看起来必须是一回事。
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
        borderRadius: BorderRadius.circular(12),
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
///
/// 命令规则与沙箱规则两处列表各写了一份，连 tooltip 取的 l10n 键都一样。
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
