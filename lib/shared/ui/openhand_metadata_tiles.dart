/// 会话元数据弹窗共用的三件套展示组件。
///
/// 主会话（`_SessionMetadataDialog`）与 Harness 工程会话
/// （`_HeSessionMetadataDialog`）此前各自维护了一份逐字节相同的实现，
/// 任何视觉调整都必须改两处且极易分叉。这里收敛为一份，两侧共用。
library;

import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

const BorderRadius _kSectionRadius = kOpenHandBorderRadius20;
const BorderRadius _kSummaryTileRadius = kOpenHandBorderRadius18;

/// 摘要磁贴的固定宽度：多个磁贴在 Wrap 中并排时保持列对齐。
const double kOpenHandMetadataSummaryTileWidth = 188;

/// 元数据分组卡片：标题 + 纵向排列的条目。
class OpenHandMetadataSection extends StatelessWidget {
  const OpenHandMetadataSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: _kSectionRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          kOpenHandGap14,
          ...children,
        ],
      ),
    );
  }
}

/// 顶部摘要磁贴：小标题 + 大号数值，宽度固定以便多列对齐。
class OpenHandMetadataSummaryTile extends StatelessWidget {
  const OpenHandMetadataSummaryTile({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: kOpenHandMetadataSummaryTileWidth,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: _kSummaryTileRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          kOpenHandGap6,
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// 元数据条目行：字段名 + 可选中的字段值。
class OpenHandMetadataEntryRow extends StatelessWidget {
  const OpenHandMetadataEntryRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          kOpenHandGap4,
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// 元数据弹窗头部：主标题 + 会话标题 + 关闭按钮。
///
/// 主会话与 Harness 工程会话的元数据弹窗此前各写了一份同样的标题行。
class OpenHandMetadataDialogHeader extends StatelessWidget {
  const OpenHandMetadataDialogHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;

  /// 会话标题，最多两行。
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              kOpenHandGap8,
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}
