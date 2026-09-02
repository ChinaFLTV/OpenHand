import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_metric_cells.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/date_time_format.dart';
import '../../ai/index.dart';
import '../model/workflow_definition.dart';
import '../workflow_node_presentation.dart';
import 'workflow_minimap.dart';

const double _workflowDetailsDialogMaxHeightFactor = 0.9;
const double _workflowDetailsDialogMaxHeight = 860;
const double _workflowDetailsMiniMapHeight = 220;
const double _workflowDetailsDescriptionMaxHeight = 180;

Future<void> showWorkflowDetailsDialog(
  BuildContext context, {
  required WorkflowDefinition workflow,
  required AiToolUsagePromotionStore usageStore,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) =>
        _WorkflowDetailsDialog(workflow: workflow, usageStore: usageStore),
  );
}

class _WorkflowDetailsDialog extends StatelessWidget {
  const _WorkflowDetailsDialog({
    required this.workflow,
    required this.usageStore,
  });

  final WorkflowDefinition workflow;
  final AiToolUsagePromotionStore usageStore;

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final maxHeight = math.min(
      _workflowDetailsDialogMaxHeight,
      mediaSize.height * _workflowDetailsDialogMaxHeightFactor,
    );
    return buildOpenHandDialog(
      maxWidth: kOpenHandDialogWidthPanel,
      maxHeight: maxHeight,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: ValueListenableBuilder<int>(
        valueListenable: usageStore.changes,
        builder: (context, _, _) {
          final recentCalls = usageStore.recentEventsFor(
            kind: AiResourceUsageKind.workflow,
            resourceId: workflow.id,
          );
          return Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
                  child: _buildBody(context, recentCalls),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(kOpenHandRadius15),
            ),
            child: Icon(
              Icons.account_tree_rounded,
              color: colors.onPrimaryContainer,
            ),
          ),
          kOpenHandHGap12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workflow.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                kOpenHandGap4,
                Row(
                  children: [
                    Icon(
                      workflow.enabled
                          ? Icons.check_circle_rounded
                          : Icons.pause_circle_rounded,
                      size: 15,
                      color: workflow.enabled
                          ? OpenHandStatusColors.success
                          : colors.onSurfaceVariant,
                    ),
                    kOpenHandHGap5,
                    Text(
                      workflow.enabled ? '已启用' : '已停用',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭详情',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<AiResourceUsageEvent> recentCalls,
  ) {
    final description = workflow.description.trim().isEmpty
        ? '暂无简要介绍。'
        : workflow.description.trim();
    final details = workflow.details.trim().isEmpty
        ? '暂无详细介绍。'
        : workflow.details.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DescriptionPanel(
          title: '简要介绍',
          icon: Icons.subject_rounded,
          content: description,
          maxHeight: _workflowDetailsDescriptionMaxHeight,
        ),
        kOpenHandGap12,
        _DescriptionPanel(
          title: '详细介绍',
          icon: Icons.notes_rounded,
          content: details,
          maxHeight: _workflowDetailsDescriptionMaxHeight,
        ),
        kOpenHandGap16,
        _buildSummary(context),
        kOpenHandGap16,
        _buildNodeDistribution(context),
        kOpenHandGap16,
        _buildMiniMap(context),
        kOpenHandGap16,
        _buildRecentCalls(context, recentCalls),
        if (workflow.tags.isNotEmpty) ...[kOpenHandGap16, _buildTags(context)],
        kOpenHandGap18,
        Center(
          child: OpenHandDialogActionButton.primary(
            label: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final metrics = <({IconData icon, String label, String value})>[
      (
        icon: Icons.account_tree_outlined,
        label: '节点数',
        value: '${workflow.nodes.length}',
      ),
      (
        icon: Icons.route_outlined,
        label: '连线数',
        value: '${workflow.connections.length}',
      ),
      (
        icon: Icons.sticky_note_2_outlined,
        label: '注释数',
        value: '${workflow.annotations.length}',
      ),
      (
        icon: Icons.update_rounded,
        label: '最近更新',
        value: formatYearMonthDayHmLocal(workflow.updatedAt),
      ),
    ];
    return _DetailsPanel(
      title: '关键信息',
      icon: Icons.insights_rounded,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 560
              ? constraints.maxWidth
              : (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(kOpenHandRadius13),
                    ),
                    child: Row(
                      children: [
                        Icon(metric.icon, size: 19, color: colors.primary),
                        kOpenHandHGap9,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                metric.label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              kOpenHandGap3,
                              Text(
                                metric.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNodeDistribution(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final counts = <WorkflowNodeKind, int>{};
    for (final node in workflow.nodes) {
      counts.update(node.kind, (value) => value + 1, ifAbsent: () => 1);
    }
    final entries = counts.entries.toList(growable: false)
      ..sort((left, right) => right.value.compareTo(left.value));
    final slices = [
      for (var index = 0; index < entries.length; index++)
        (
          kind: entries[index].key,
          count: entries[index].value,
          color: _nodeTypeColor(colors, entries[index].key, index),
        ),
    ];
    return _DetailsPanel(
      title: '节点类型分布',
      icon: Icons.pie_chart_outline_rounded,
      child: entries.isEmpty
          ? Text(
              '暂无节点。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 540;
                final chart = SizedBox(
                  width: 172,
                  height: 172,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _WorkflowNodeTypePiePainter(
                          slices: slices,
                          total: workflow.nodes.length,
                          holeColor: colors.surfaceContainerLow,
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${workflow.nodes.length}',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '节点',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
                final legend = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final slice in slices) ...[
                      _NodeTypeLegendItem(
                        label: workflowNodeDescriptor(slice.kind, colors).label,
                        count: slice.count,
                        color: slice.color,
                      ),
                      if (slice != slices.last) kOpenHandGap8,
                    ],
                  ],
                );
                if (!wide) {
                  return Column(children: [chart, kOpenHandGap14, legend]);
                }
                return Row(
                  children: [
                    chart,
                    kOpenHandHGap20,
                    Expanded(child: legend),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildMiniMap(BuildContext context) {
    return _DetailsPanel(
      title: '工作流全貌',
      icon: Icons.map_outlined,
      child: SizedBox(
        height: _workflowDetailsMiniMapHeight,
        child: WorkflowMiniMap(
          nodes: workflow.nodes,
          connections: workflow.connections,
          annotations: workflow.annotations,
        ),
      ),
    );
  }

  Widget _buildRecentCalls(
    BuildContext context,
    List<AiResourceUsageEvent> recentCalls,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _DetailsPanel(
      title: '最近的调用记录',
      icon: Icons.history_rounded,
      trailing: Text(
        '${recentCalls.length} 条',
        style: theme.textTheme.labelMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      child: recentCalls.isEmpty
          ? Text(
              '暂无调用记录。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < recentCalls.length; index++) ...[
                  _WorkflowCallRecordTile(event: recentCalls[index]),
                  if (index < recentCalls.length - 1) kOpenHandGap8,
                ],
              ],
            ),
    );
  }

  Widget _buildTags(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _DetailsPanel(
      title: '标签',
      icon: Icons.sell_outlined,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in workflow.tags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(kOpenHandRadius10),
              ),
              child: Text(
                tag,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DescriptionPanel extends StatelessWidget {
  const _DescriptionPanel({
    required this.title,
    required this.icon,
    required this.content,
    required this.maxHeight,
  });

  final String title;
  final IconData icon;
  final String content;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return _DetailsPanel(
      title: title,
      icon: icon,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: SelectableText(
            content,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ),
      ),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius15),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: colors.primary),
              kOpenHandHGap7,
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          kOpenHandGap11,
          child,
        ],
      ),
    );
  }
}

class _NodeTypeLegendItem extends StatelessWidget {
  const _NodeTypeLegendItem({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        kOpenHandHGap7,
        Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
        Text(
          '$count',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _WorkflowCallRecordTile extends StatelessWidget {
  const _WorkflowCallRecordTile({required this.event});

  final AiResourceUsageEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = openHandTableMetricRequestStatusColor(
      colors,
      event.status,
    );
    final executionId = event.subResourceId.trim();
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  executionId.isEmpty ? '工作流调用' : executionId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFamily: kOpenHandMonospaceFontFamily,
                  ),
                ),
              ),
              kOpenHandHGap8,
              OpenHandTableStatusBadge(
                label: _workflowCallStatusLabel(event.status),
                color: statusColor,
              ),
            ],
          ),
          kOpenHandGap7,
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              OpenHandInlineIconLabel(
                icon: Icons.schedule_rounded,
                label: formatYearMonthDayHmsLocal(event.occurredAt),
              ),
              OpenHandInlineIconLabel(
                icon: Icons.timer_outlined,
                label: openHandTableMetricDuration(event.durationMs),
              ),
              if (event.source.trim().isNotEmpty)
                OpenHandInlineIconLabel(
                  icon: Icons.route_outlined,
                  label: event.source.trim(),
                ),
            ],
          ),
          if (event.errorSummary.trim().isNotEmpty) ...[
            kOpenHandGap6,
            Text(
              event.errorSummary.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkflowNodeTypePiePainter extends CustomPainter {
  const _WorkflowNodeTypePiePainter({
    required this.slices,
    required this.total,
    required this.holeColor,
  });

  final List<({WorkflowNodeKind kind, int count, Color color})> slices;
  final int total;
  final Color holeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || slices.isEmpty) return;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var startAngle = -math.pi / 2;
    for (final slice in slices) {
      final sweepAngle = math.pi * 2 * slice.count / total;
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        true,
        Paint()..color = slice.color,
      );
      startAngle += sweepAngle;
    }
    canvas.drawCircle(center, radius * 0.54, Paint()..color = holeColor);
  }

  @override
  bool shouldRepaint(covariant _WorkflowNodeTypePiePainter oldDelegate) {
    return oldDelegate.total != total ||
        oldDelegate.slices != slices ||
        oldDelegate.holeColor != holeColor;
  }
}

Color _nodeTypeColor(ColorScheme colors, WorkflowNodeKind kind, int index) {
  final descriptor = workflowNodeDescriptor(kind, colors);
  const fallback = <Color>[
    Color(0xFF2563EB),
    Color(0xFF0D9488),
    Color(0xFFF59E0B),
    Color(0xFFDB2777),
    Color(0xFF7C3AED),
    Color(0xFFEA580C),
  ];
  return Color.lerp(
        descriptor.color,
        fallback[index % fallback.length],
        0.38,
      ) ??
      descriptor.color;
}

String _workflowCallStatusLabel(String status) {
  return switch (status.trim().toLowerCase()) {
    'success' => '成功',
    'failed' || 'error' => '失败',
    'running' || 'pending' => '进行中',
    _ => status.trim().isEmpty ? '未知' : status.trim(),
  };
}
