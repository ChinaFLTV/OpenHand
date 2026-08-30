import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../model/workflow_definition.dart';
import '../service/workflow_node_executor.dart';

const RoundedRectangleBorder _workflowTestButtonShape = RoundedRectangleBorder(
  borderRadius: kOpenHandBorderRadius12,
);
const double _workflowTestMetricGap = 10;
const double _workflowTestMetricFourColumnWidth = 620;
const double _workflowTestMetricTwoColumnWidth = 320;

typedef _WorkflowTestOutputEntry = ({
  String name,
  Object? value,
  String? description,
});

class WorkflowTestNodeReport {
  const WorkflowTestNodeReport({required this.node, required this.event});

  final WorkflowNode node;
  final WorkflowNodeExecutionEvent event;
}

class WorkflowTestReport {
  const WorkflowTestReport({
    required this.succeeded,
    required this.hasWarnings,
    required this.duration,
    required this.executedSteps,
    required this.succeededNodes,
    required this.warningNodes,
    required this.failedNodes,
    required this.skippedNodes,
    this.output,
    this.error,
    this.nodeReports = const <WorkflowTestNodeReport>[],
    this.outputDescriptions = const <String, String>{},
  });

  final bool succeeded;
  final bool hasWarnings;
  final Duration duration;
  final int executedSteps;
  final int succeededNodes;
  final int warningNodes;
  final int failedNodes;
  final int skippedNodes;
  final Object? output;
  final String? error;
  final List<WorkflowTestNodeReport> nodeReports;
  final Map<String, String> outputDescriptions;
}

class _WorkflowTestCloseButton extends StatelessWidget {
  const _WorkflowTestCloseButton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: '关闭',
      onPressed: () => Navigator.of(context).pop(),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(42),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: colors.onSurfaceVariant,
        backgroundColor: colors.surface.withValues(alpha: 0.74),
        side: BorderSide(color: colors.outlineVariant),
        shape: _workflowTestButtonShape,
      ),
      icon: const Icon(Icons.close_rounded),
    );
  }
}

Future<Map<String, Object?>?> showWorkflowTestInputDialog(
  BuildContext context,
  WorkflowNode startNode,
) {
  return showAnimatedDialog<Map<String, Object?>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WorkflowTestInputDialog(fields: startNode.inputFields()),
  );
}

Future<void> showWorkflowTestResultDialog(
  BuildContext context,
  WorkflowTestReport report,
) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _WorkflowTestResultDialog(report: report),
  );
}

class _WorkflowTestInputDialog extends StatefulWidget {
  const _WorkflowTestInputDialog({required this.fields});

  final List<WorkflowOutputField> fields;

  @override
  State<_WorkflowTestInputDialog> createState() =>
      _WorkflowTestInputDialogState();
}

class _WorkflowTestInputDialogState extends State<_WorkflowTestInputDialog> {
  late final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{
        for (final field in widget.fields)
          field.id: TextEditingController(
            text: field.valueSource == WorkflowValueSource.constant
                ? field.defaultValue
                : '',
          ),
      };
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final raw = <String, Object?>{};
    for (final field in widget.fields) {
      final controller = _controllers[field.id]!;
      final value = controller.text;
      if (value.trim().isEmpty) {
        if (field.required && field.defaultValue.trim().isEmpty) {
          setState(() => _error = '请填写必需参数“${field.name.trim()}”。');
          return;
        }
        continue;
      }
      raw[field.name.trim()] = field.type == WorkflowOutputType.string
          ? value
          : value.trim();
    }
    try {
      final values = WorkflowStructuredOutputParser.resolveValues(
        widget.fields,
        raw,
        label: '工作流测试输入',
      );
      Navigator.of(context).pop(values);
    } on WorkflowNodeExecutionException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return buildOpenHandDialog(
      width: 720,
      maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        key: const ValueKey<String>('workflow-test-input-dialog'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey<String>('workflow-test-input-header'),
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(kOpenHandRadius14),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    Icons.rocket_launch_rounded,
                    color: colors.primary,
                    size: 24,
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '测试工作流',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      kOpenHandGap3,
                      Text(
                        '填写开始节点参数，确认后将按当前画布配置执行。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const _WorkflowTestCloseButton(),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
              child: widget.fields.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(kOpenHandRadius16),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.task_alt_rounded,
                            size: 34,
                            color: colors.primary,
                          ),
                          kOpenHandGap10,
                          Text(
                            '当前工作流无需起始参数',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          kOpenHandGap4,
                          Text(
                            '可以直接启动测试。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, field) in widget.fields.indexed) ...[
                          _WorkflowTestInputField(
                            field: field,
                            controller: _controllers[field.id]!,
                            autofocus: index == 0,
                            onChanged: () {
                              if (_error != null) {
                                setState(() => _error = null);
                              }
                            },
                          ),
                          if (index < widget.fields.length - 1) kOpenHandGap14,
                        ],
                      ],
                    ),
            ),
          ),
          AnimatedSize(
            duration: openHandMotionDuration(context, kOpenHandMotion180),
            curve: Curves.easeOutCubic,
            child: _error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(kOpenHandRadius12),
                      ),
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
            child: Row(
              key: const ValueKey<String>('workflow-test-input-actions'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OpenHandDialogActionButton.secondary(
                  label: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                  shape: _workflowTestButtonShape,
                ),
                kOpenHandHGap12,
                OpenHandDialogActionButton.primary(
                  label: '开始测试',
                  onPressed: _submit,
                  shape: _workflowTestButtonShape,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowTestInputField extends StatelessWidget {
  const _WorkflowTestInputField({
    required this.field,
    required this.controller,
    required this.autofocus,
    required this.onChanged,
  });

  final WorkflowOutputField field;
  final TextEditingController controller;
  final bool autofocus;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final complex =
        field.type == WorkflowOutputType.object || field.type.isArray;
    final enabledBorder = OutlineInputBorder(
      borderRadius: kOpenHandBorderRadius12,
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    final decoration = InputDecoration(
      hintText: _hint(field.type),
      filled: true,
      fillColor: colors.surfaceContainerLowest,
      border: enabledBorder,
      enabledBorder: enabledBorder,
      focusedBorder: enabledBorder.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 1.8),
      ),
      disabledBorder: enabledBorder,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OpenHandFormLabel(
                  field.name.trim(),
                  required: field.required,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.56),
                  borderRadius: BorderRadius.circular(kOpenHandRadius8),
                ),
                child: Text(
                  field.type.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (field.description.trim().isNotEmpty) ...[
            kOpenHandGap4,
            Text(
              field.description.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          kOpenHandGap8,
          if (field.type == WorkflowOutputType.boolean)
            AnimatedDropdownButtonFormField<String>(
              initialValue:
                  const <String>{
                    'true',
                    'false',
                  }.contains(controller.text.trim().toLowerCase())
                  ? controller.text.trim().toLowerCase()
                  : null,
              decoration: decoration,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'true', child: Text('true')),
                DropdownMenuItem(value: 'false', child: Text('false')),
              ],
              onChanged: (value) {
                controller.text = value ?? '';
                onChanged();
              },
            )
          else
            TextField(
              controller: controller,
              autofocus: autofocus,
              minLines: complex ? 3 : 1,
              maxLines: complex ? 7 : 1,
              keyboardType:
                  field.type == WorkflowOutputType.integer ||
                      field.type == WorkflowOutputType.number
                  ? const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    )
                  : complex
                  ? TextInputType.multiline
                  : TextInputType.text,
              style: complex
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: kOpenHandMonospaceFontFamily,
                      height: 1.4,
                    )
                  : null,
              decoration: decoration,
              onChanged: (_) => onChanged(),
            ),
        ],
      ),
    );
  }

  String _hint(WorkflowOutputType type) => switch (type) {
    WorkflowOutputType.string => '输入文本',
    WorkflowOutputType.integer => '输入整数',
    WorkflowOutputType.number => '输入数值',
    WorkflowOutputType.boolean => '选择 true 或 false',
    WorkflowOutputType.object => '{"key": "value"}',
    WorkflowOutputType.array ||
    WorkflowOutputType.arrayString ||
    WorkflowOutputType.arrayNumber ||
    WorkflowOutputType.arrayObject ||
    WorkflowOutputType.arrayBoolean => '["item"]',
  };
}

class _WorkflowTestResultDialog extends StatelessWidget {
  const _WorkflowTestResultDialog({required this.report});

  final WorkflowTestReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = !report.succeeded
        ? OpenHandStatusColors.error
        : report.hasWarnings
        ? OpenHandStatusColors.warning
        : OpenHandStatusColors.success;
    final title = !report.succeeded
        ? '工作流测试失败'
        : report.hasWarnings
        ? '工作流测试完成（含异常）'
        : '工作流测试成功';
    final outputEntries = report.succeeded
        ? _workflowTestOutputEntries(report.output, report.outputDescriptions)
        : _workflowTestFailureEntries(report);
    final metrics =
        <({String id, String label, int value, IconData icon, Color color})>[
          (
            id: 'success',
            label: '成功节点',
            value: report.succeededNodes,
            icon: Icons.check_circle_outline_rounded,
            color: OpenHandStatusColors.success,
          ),
          (
            id: 'warning',
            label: '异常节点',
            value: report.warningNodes,
            icon: Icons.warning_amber_rounded,
            color: OpenHandStatusColors.warning,
          ),
          (
            id: 'failure',
            label: '失败节点',
            value: report.failedNodes,
            icon: Icons.error_outline_rounded,
            color: OpenHandStatusColors.error,
          ),
          (
            id: 'skipped',
            label: '跳过节点',
            value: report.skippedNodes,
            icon: Icons.skip_next_rounded,
            color: colors.outline,
          ),
        ];
    return buildOpenHandDialog(
      width: 760,
      maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        key: const ValueKey<String>('workflow-test-result-dialog'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey<String>('workflow-test-result-header'),
            padding: const EdgeInsets.fromLTRB(22, 19, 18, 17),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.86),
                    borderRadius: BorderRadius.circular(kOpenHandRadius14),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.38),
                    ),
                  ),
                  child: Icon(
                    report.succeeded
                        ? Icons.task_alt_rounded
                        : Icons.error_outline_rounded,
                    color: statusColor,
                    size: 26,
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      kOpenHandGap3,
                      Text(
                        '运行 ${_formatDuration(report.duration)} · ${report.executedSteps} 个执行步骤',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const _WorkflowTestCloseButton(),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    key: const ValueKey<String>('workflow-test-result-metrics'),
                    builder: (context, constraints) {
                      final columns =
                          constraints.maxWidth >=
                              _workflowTestMetricFourColumnWidth
                          ? 4
                          : constraints.maxWidth >=
                                _workflowTestMetricTwoColumnWidth
                          ? 2
                          : 1;
                      final itemWidth =
                          (constraints.maxWidth -
                              _workflowTestMetricGap * (columns - 1)) /
                          columns;
                      return Wrap(
                        spacing: _workflowTestMetricGap,
                        runSpacing: _workflowTestMetricGap,
                        children: [
                          for (final metric in metrics)
                            SizedBox(
                              width: itemWidth,
                              child: _ResultMetric(
                                key: ValueKey<String>(
                                  'workflow-test-metric-${metric.id}',
                                ),
                                label: metric.label,
                                value: metric.value,
                                icon: metric.icon,
                                color: metric.color,
                                onTap: () => _showWorkflowTestNodeDetails(
                                  context,
                                  report,
                                  metric.id,
                                  metric.label,
                                  metric.color,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  kOpenHandGap18,
                  Text(
                    report.succeeded ? '最终输出' : '失败原因',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  kOpenHandGap8,
                  if (outputEntries.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(kOpenHandRadius14),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            color: colors.onSurfaceVariant,
                          ),
                          kOpenHandGap8,
                          Text(
                            report.succeeded ? '暂无输出参数' : '未提供失败详情',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final (index, entry) in outputEntries.indexed) ...[
                    _ResultOutputCard(
                      name: entry.name,
                      value: entry.value,
                      description: entry.description,
                      accentColor: statusColor,
                    ),
                    if (index < outputEntries.length - 1) kOpenHandGap10,
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
            child: Align(
              child: OpenHandDialogActionButton.primary(
                key: const ValueKey<String>('workflow-test-result-finish'),
                label: '完成',
                onPressed: () => Navigator.of(context).pop(),
                shape: _workflowTestButtonShape,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showWorkflowTestNodeDetails(
  BuildContext context,
  WorkflowTestReport report,
  String metricId,
  String title,
  Color accentColor,
) {
  final nodeReports = report.nodeReports
      .where((item) => _matchesWorkflowTestMetric(item.event.phase, metricId))
      .toList(growable: false);
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _WorkflowTestNodeDetailsDialog(
      title: title,
      accentColor: accentColor,
      nodeReports: nodeReports,
    ),
  );
}

bool _matchesWorkflowTestMetric(
  WorkflowNodeExecutionPhase phase,
  String metricId,
) => switch (metricId) {
  'success' => phase == WorkflowNodeExecutionPhase.succeeded,
  'warning' => phase == WorkflowNodeExecutionPhase.warning,
  'failure' => phase == WorkflowNodeExecutionPhase.failed,
  'skipped' => phase == WorkflowNodeExecutionPhase.skipped,
  _ => false,
};

class _WorkflowTestNodeDetailsDialog extends StatelessWidget {
  const _WorkflowTestNodeDetailsDialog({
    required this.title,
    required this.accentColor,
    required this.nodeReports,
  });

  final String title;
  final Color accentColor;
  final List<WorkflowTestNodeReport> nodeReports;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return buildOpenHandDialog(
      width: 820,
      maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(kOpenHandRadius12),
                  ),
                  child: Icon(
                    Icons.account_tree_rounded,
                    color: accentColor,
                    size: 23,
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      kOpenHandGap3,
                      Text(
                        '${nodeReports.length} 个节点执行记录',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const _WorkflowTestCloseButton(),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
              child: nodeReports.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 34,
                            color: colors.onSurfaceVariant,
                          ),
                          kOpenHandGap8,
                          Text(
                            '暂无节点记录',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, report) in nodeReports.indexed) ...[
                          _WorkflowTestNodeRecord(report: report),
                          if (index < nodeReports.length - 1) kOpenHandGap10,
                        ],
                      ],
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
            child: Align(
              child: OpenHandDialogActionButton.primary(
                label: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                shape: _workflowTestButtonShape,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowTestNodeRecord extends StatelessWidget {
  const _WorkflowTestNodeRecord({required this.report});

  final WorkflowTestNodeReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final node = report.node;
    final event = report.event;
    final meta = _workflowTestNodeMeta(node.kind);
    final inputValue = event.resolvedInputs.isEmpty
        ? '无可展示入参'
        : _serializeOutputValue(event.resolvedInputs);
    final returnValue = event.phase == WorkflowNodeExecutionPhase.failed
        ? (event.error?.trim().isNotEmpty == true
              ? event.error!.trim()
              : '执行失败')
        : _displayOutputValue(event.output);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.title.trim().isEmpty ? meta.label : node.title.trim(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _WorkflowTestPhaseBadge(event: event),
            ],
          ),
          kOpenHandGap8,
          Wrap(
            spacing: 14,
            runSpacing: 5,
            children: [
              _WorkflowTestMetaText(label: '节点类型', value: meta.label),
              _WorkflowTestMetaText(
                label: '节点耗时',
                value: _formatDuration(event.duration),
              ),
              if (event.attempts > 0)
                _WorkflowTestMetaText(
                  label: '执行次数',
                  value: '${event.attempts}',
                ),
            ],
          ),
          if (meta.description.isNotEmpty) ...[
            kOpenHandGap6,
            Text(
              meta.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          kOpenHandGap10,
          _WorkflowTestDetailBlock(label: '节点入参', value: inputValue),
          kOpenHandGap8,
          _WorkflowTestDetailBlock(label: '返回值', value: returnValue),
        ],
      ),
    );
  }
}

class _WorkflowTestPhaseBadge extends StatelessWidget {
  const _WorkflowTestPhaseBadge({required this.event});

  final WorkflowNodeExecutionEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (event.phase) {
      WorkflowNodeExecutionPhase.succeeded => OpenHandStatusColors.success,
      WorkflowNodeExecutionPhase.warning => OpenHandStatusColors.warning,
      WorkflowNodeExecutionPhase.failed => OpenHandStatusColors.error,
      WorkflowNodeExecutionPhase.skipped => colors.outline,
      WorkflowNodeExecutionPhase.running => OpenHandStatusColors.info,
      WorkflowNodeExecutionPhase.pending => colors.outlineVariant,
    };
    final label = switch (event.phase) {
      WorkflowNodeExecutionPhase.succeeded => '成功',
      WorkflowNodeExecutionPhase.warning => '异常',
      WorkflowNodeExecutionPhase.failed => '失败',
      WorkflowNodeExecutionPhase.skipped => '跳过',
      WorkflowNodeExecutionPhase.running => '运行',
      WorkflowNodeExecutionPhase.pending => '等待',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _WorkflowTestMetaText extends StatelessWidget {
  const _WorkflowTestMetaText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label：',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        TextSpan(
          text: value,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _WorkflowTestDetailBlock extends StatelessWidget {
  const _WorkflowTestDetailBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        kOpenHandGap4,
        SelectableText(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: kOpenHandMonospaceFontFamily,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

({String label, String description}) _workflowTestNodeMeta(
  WorkflowNodeKind kind,
) => switch (kind) {
  WorkflowNodeKind.start => (label: '开始', description: '定义工作流的输入参数'),
  WorkflowNodeKind.condition => (label: '条件分支', description: '依据表达式选择后续路径'),
  WorkflowNodeKind.loop => (label: '循环', description: '按上限重复执行节点组'),
  WorkflowNodeKind.iteration => (label: '迭代', description: '逐项处理数组输入'),
  WorkflowNodeKind.parameterAssignment => (
    label: '参数赋值',
    description: '生成可供后续节点引用的参数',
  ),
  WorkflowNodeKind.listOperation => (
    label: '列表操作',
    description: '筛选、截取、排序并限制数组',
  ),
  WorkflowNodeKind.codeExecution => (
    label: '代码执行',
    description: '运行 Python 3 或 JavaScript 代码',
  ),
  WorkflowNodeKind.humanIntervention => (
    label: '人工介入',
    description: '暂停工作流并等待用户确认',
  ),
  WorkflowNodeKind.loopExit => (label: '循环退出', description: '结束当前循环分支'),
  WorkflowNodeKind.llm => (label: '大语言模型', description: '调用模型生成内容'),
  WorkflowNodeKind.httpRequest => (
    label: 'HTTP 请求',
    description: '调用外部 HTTP 服务',
  ),
  WorkflowNodeKind.end => (label: '结束', description: '整理并输出工作流结果'),
};

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              kOpenHandHGap8,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$value',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultOutputCard extends StatelessWidget {
  const _ResultOutputCard({
    required this.name,
    required this.value,
    required this.description,
    required this.accentColor,
  });

  final String name;
  final Object? value;
  final String? description;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final displayValue = _displayOutputValue(value);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(kOpenHandRadius10),
                ),
                child: Icon(Icons.output_rounded, size: 18, color: accentColor),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _outputTypeLabel(value),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (description?.trim().isNotEmpty == true)
                      Text(
                        description!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '复制参数 $name',
                onPressed: () => unawaited(
                  copyOpenHandTextToClipboard(
                    context: context,
                    text: _serializeOutputValue(value),
                    logTag: 'workflow_test_result',
                    logAction: '复制输出参数',
                    successMessage: '已复制参数“$name”',
                    replaceCurrentSnack: true,
                  ),
                ),
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(38),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: colors.primary,
                  backgroundColor: colors.primaryContainer.withValues(
                    alpha: 0.5,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: kOpenHandBorderRadius10,
                  ),
                ),
                icon: const Icon(Icons.content_copy_rounded, size: 18),
              ),
            ],
          ),
          kOpenHandGap10,
          SelectableText(
            displayValue,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: value is String ? null : kOpenHandMonospaceFontFamily,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  if (duration.inMinutes > 0) {
    return '${duration.inMinutes} 分 ${duration.inSeconds.remainder(60)} 秒';
  }
  if (duration.inSeconds > 0) {
    return '${duration.inSeconds}.${duration.inMilliseconds.remainder(1000).toString().padLeft(3, '0')} 秒';
  }
  return '${duration.inMilliseconds} 毫秒';
}

List<_WorkflowTestOutputEntry> _workflowTestOutputEntries(
  Object? output,
  Map<String, String> descriptions,
) {
  if (output == null) return const <_WorkflowTestOutputEntry>[];
  if (output is Map) {
    var index = 0;
    return output.entries
        .map((entry) {
          final name = '${entry.key}'.trim();
          index += 1;
          return (
            name: name.isEmpty ? '输出参数 $index' : name,
            value: entry.value,
            description: descriptions[name],
          );
        })
        .toList(growable: false);
  }
  return <_WorkflowTestOutputEntry>[
    (name: '输出结果', value: output, description: null),
  ];
}

List<_WorkflowTestOutputEntry> _workflowTestFailureEntries(
  WorkflowTestReport report,
) {
  final error = report.error?.trim() ?? '';
  if (error.isNotEmpty) {
    return <_WorkflowTestOutputEntry>[
      (name: '错误详情', value: error, description: null),
    ];
  }
  if (report.output == null) return const <_WorkflowTestOutputEntry>[];
  return <_WorkflowTestOutputEntry>[
    (name: '失败详情', value: report.output, description: null),
  ];
}

String _outputTypeLabel(Object? value) => switch (value) {
  null => 'Null',
  String() => 'String',
  bool() => 'Boolean',
  int() => 'Integer',
  num() => 'Number',
  Map() => 'Object',
  Iterable() => 'Array',
  _ => 'Value',
};

String _serializeOutputValue(Object? value) {
  if (value == null) return 'null';
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on JsonUnsupportedObjectError {
    return '$value';
  }
}

String _displayOutputValue(Object? value) {
  if (value == null) return '空值';
  if (value is String && value.isEmpty) return '空字符串';
  return _serializeOutputValue(value);
}
