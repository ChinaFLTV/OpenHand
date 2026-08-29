import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../model/workflow_definition.dart';
import '../service/workflow_node_executor.dart';

const RoundedRectangleBorder _workflowTestButtonShape = RoundedRectangleBorder(
  borderRadius: kOpenHandBorderRadius12,
);

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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  colors.primaryContainer.withValues(alpha: 0.92),
                  colors.tertiaryContainer.withValues(alpha: 0.58),
                ],
              ),
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
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
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
              mainAxisAlignment: MainAxisAlignment.end,
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
                  icon: Icons.play_arrow_rounded,
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
    final decoration = InputDecoration(
      hintText: _hint(field.type),
      filled: true,
      fillColor: colors.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
      ),
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
    final detail = report.error?.trim().isNotEmpty == true
        ? report.error!.trim()
        : _formatOutput(report.output);
    return buildOpenHandDialog(
      width: 760,
      maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      insetPadding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 19, 18, 17),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  statusColor.withValues(alpha: 0.2),
                  colors.tertiaryContainer.withValues(alpha: 0.54),
                ],
              ),
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
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ResultMetric(
                        label: '成功节点',
                        value: report.succeededNodes,
                        icon: Icons.check_circle_outline_rounded,
                        color: OpenHandStatusColors.success,
                      ),
                      _ResultMetric(
                        label: '异常节点',
                        value: report.warningNodes,
                        icon: Icons.warning_amber_rounded,
                        color: OpenHandStatusColors.warning,
                      ),
                      _ResultMetric(
                        label: '失败节点',
                        value: report.failedNodes,
                        icon: Icons.error_outline_rounded,
                        color: OpenHandStatusColors.error,
                      ),
                      _ResultMetric(
                        label: '跳过节点',
                        value: report.skippedNodes,
                        icon: Icons.skip_next_rounded,
                        color: colors.outline,
                      ),
                    ],
                  ),
                  kOpenHandGap18,
                  Text(
                    report.succeeded ? '最终输出' : '失败原因',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  kOpenHandGap8,
                  Container(
                    constraints: const BoxConstraints(minHeight: 90),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(kOpenHandRadius14),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: SelectableText(
                      detail.isEmpty ? '无输出内容' : detail,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: kOpenHandMonospaceFontFamily,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
            child: Align(
              alignment: Alignment.centerRight,
              child: OpenHandDialogActionButton.primary(
                label: '完成',
                onPressed: () => Navigator.of(context).pop(),
                icon: Icons.done_rounded,
                shape: _workflowTestButtonShape,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 162,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
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

String _formatOutput(Object? output) {
  if (output == null) return '';
  if (output is String) return output;
  try {
    return const JsonEncoder.withIndent('  ').convert(output);
  } on JsonUnsupportedObjectError {
    return '$output';
  }
}
