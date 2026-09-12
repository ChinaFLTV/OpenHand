/// 会话元数据弹窗共用的摘要磁贴、分组卡片与键值行。
///
/// 主会话（`_SessionMetadataDialog`）与 Harness 工程会话
/// （`_HeSessionMetadataDialog`）共用这一份实现，避免视觉分叉。
library;

import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_form_fields.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

const double kOpenHandMetadataEntryLabelWidth = 132;
const double kOpenHandMetadataSummaryGridWideMinWidth = 720;
const double kOpenHandMetadataSummaryGridMediumMinWidth = 480;
const int kOpenHandMetadataSummaryGridMaxColumns = 4;

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

/// 摘要磁贴网格：按可用宽度均分列，每一行都铺满父布局。
class OpenHandMetadataSummaryGrid extends StatelessWidget {
  const OpenHandMetadataSummaryGrid({
    super.key,
    required this.children,
    this.maxColumns = kOpenHandMetadataSummaryGridMaxColumns,
  });

  final List<Widget> children;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemCount = children.length;
        final maxWidth = constraints.maxWidth;
        final columns = _columnsFor(maxWidth, itemCount);
        if (columns <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < itemCount; index += 1) ...[
                if (index > 0) kOpenHandGap12,
                children[index],
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var start = 0; start < itemCount; start += columns) {
          final end = start + columns > itemCount ? itemCount : start + columns;
          final rowItems = children.sublist(start, end);
          if (rows.isNotEmpty) {
            rows.add(kOpenHandGap12);
          }
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < rowItems.length; index += 1) ...[
                  if (index > 0) kOpenHandHGap12,
                  Expanded(child: rowItems[index]),
                ],
              ],
            ),
          );
        }
        return SizedBox(
          width: maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        );
      },
    );
  }

  int _columnsFor(double maxWidth, int itemCount) {
    if (itemCount <= 1) return 1;
    if (!maxWidth.isFinite) return 1;
    final wanted = maxWidth >= kOpenHandMetadataSummaryGridWideMinWidth
        ? maxColumns
        : maxWidth >= kOpenHandMetadataSummaryGridMediumMinWidth
        ? 2
        : 1;
    return wanted > itemCount ? itemCount : wanted;
  }
}

/// 顶部摘要磁贴：图标徽章 + 小标题 + 强调色数值，铺满所在网格格。
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
      width: double.infinity,
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
