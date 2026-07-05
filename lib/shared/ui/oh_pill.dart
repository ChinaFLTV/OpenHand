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
