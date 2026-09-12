/// 会话元数据弹窗共用的摘要磁贴、分组卡片与键值行。
///
/// 主会话（`_SessionMetadataDialog`）与 Harness 工程会话
/// （`_HeSessionMetadataDialog`）共用这一份实现，避免视觉分叉。
library;

import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_form_fields.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

/// 摘要磁贴的固定宽度：多个磁贴在 Wrap 中并排时保持列对齐。
const double kOpenHandMetadataSummaryTileWidth = 188;
const double kOpenHandMetadataEntryLabelWidth = 132;

/// 元数据分组卡片：着色分区头 + 纵向排列的条目。
class OpenHandMetadataSection extends StatelessWidget {
  const OpenHandMetadataSection({
    super.key,
    required this.title,
    required this.children,
    this.icon = Icons.layers_rounded,
    this.accent,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? accent;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return OpenHandDialogSectionCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accent: accent,
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// 顶部摘要磁贴：图标徽章 + 小标题 + 强调色数值。
class OpenHandMetadataSummaryTile extends StatelessWidget {
  const OpenHandMetadataSummaryTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tone = accent ?? colorScheme.primary;
    final display = value.trim().isEmpty ? '-' : value.trim();
    return SizedBox(
      width: kOpenHandMetadataSummaryTileWidth,
      child: OpenHandTintedPanel(
        accent: tone,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            if (icon != null) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.18),
                  borderRadius: kOpenHandBorderRadius10,
                ),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(child: Icon(icon, size: 18, color: tone)),
                ),
              ),
              kOpenHandHGap10,
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  kOpenHandGap2,
                  Text(
                    display,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 元数据条目行：左侧字段名、右侧可选中的字段值。
class OpenHandMetadataEntryRow extends StatelessWidget {
  const OpenHandMetadataEntryRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = kOpenHandMetadataEntryLabelWidth,
  });

  final String label;
  final String value;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final display = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          kOpenHandHGap12,
          Expanded(
            child: SelectableText(
              display,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
