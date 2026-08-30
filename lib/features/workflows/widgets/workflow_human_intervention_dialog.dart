import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_safe_markdown_body.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/timer_safety.dart';
import '../model/workflow_definition.dart';
import '../service/workflow_node_executor.dart';

Future<WorkflowHumanInterventionResponse> showWorkflowHumanInterventionDialog(
  BuildContext context,
  WorkflowHumanInterventionRequest request,
) async {
  final result = await showAnimatedDialog<WorkflowHumanInterventionResponse>(
    context: context,
    barrierDismissible: false,
    dismissOnEscape: false,
    builder: (_) => _WorkflowHumanInterventionDialog(request: request),
  );
  if (result == null) {
    throw const WorkflowNodeExecutionException('人工介入窗口已意外关闭。');
  }
  return result;
}

class _WorkflowHumanInterventionDialog extends StatefulWidget {
  const _WorkflowHumanInterventionDialog({required this.request});

  final WorkflowHumanInterventionRequest request;

  @override
  State<_WorkflowHumanInterventionDialog> createState() =>
      _WorkflowHumanInterventionDialogState();
}

class _WorkflowHumanInterventionDialogState
    extends State<_WorkflowHumanInterventionDialog> {
  late final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{
        for (final field in widget.request.fields)
          field.name.trim(): TextEditingController(
            text: _displayValue(
              widget.request.initialValues[field.name.trim()],
            ),
          ),
      };
  late final OpenHandDebouncer _timeout;
  bool _completed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timeout = OpenHandDebouncer(
      delay: widget.request.timeout,
      maxDelay: widget.request.timeout,
    )..schedule(_handleTimeout);
    final cancelSignal = widget.request.cancelSignal;
    if (cancelSignal != null) {
      unawaited(cancelSignal.then<void>((_) => _cancel()));
    }
  }

  @override
  void dispose() {
    _timeout.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: false,
      child: buildOpenHandDialog(
        width: 680,
        maxHeight: viewport.height * 0.86,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kOpenHandDialogDefaultRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    colors.primaryContainer.withValues(alpha: 0.9),
                    colors.tertiaryContainer.withValues(alpha: 0.56),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(kOpenHandRadius14),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.32),
                      ),
                    ),
                    child: Icon(
                      Icons.front_hand_outlined,
                      color: colors.primary,
                      size: 25,
                    ),
                  ),
                  kOpenHandHGap12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.request.nodeTitle.trim().isEmpty
                              ? '需要人工介入'
                              : widget.request.nodeTitle.trim(),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        kOpenHandGap3,
                        Text(
                          '工作流已暂停，请确认信息并选择下一步。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: OpenHandStatusColors.warning.withValues(
                        alpha: 0.14,
                      ),
                      borderRadius: BorderRadius.circular(kOpenHandRadius10),
                    ),
                    child: Text(
                      '等待处理',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: OpenHandStatusColors.warning,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(kOpenHandRadius16),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: OpenHandSafeMarkdownBody(
                        data: widget.request.content,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet.fromTheme(theme)
                            .copyWith(
                              p: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.55,
                              ),
                              code: theme.textTheme.bodyMedium?.copyWith(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                backgroundColor: colors.surfaceContainerHighest,
                              ),
                            ),
                      ),
                    ),
                    if (widget.request.fields.isNotEmpty) ...[
                      kOpenHandGap18,
                      Text(
                        '补充信息',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      kOpenHandGap10,
                      ...widget.request.fields.map(
                        (field) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OpenHandFormLabel(
                                field.name.trim(),
                                required: field.required,
                              ),
                              if (field.description.trim().isNotEmpty) ...[
                                kOpenHandGap3,
                                Text(
                                  field.description.trim(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              kOpenHandGap7,
                              TextField(
                                controller: _controllers[field.name.trim()],
                                minLines:
                                    field.type == WorkflowOutputType.object ||
                                        field.type.isArray
                                    ? 3
                                    : 1,
                                maxLines:
                                    field.type == WorkflowOutputType.object ||
                                        field.type.isArray
                                    ? 7
                                    : 3,
                                decoration: InputDecoration(
                                  hintText: _fieldHint(field.type),
                                  suffixIcon: Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: Center(
                                      widthFactor: 1,
                                      child: Text(
                                        field.type.label,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: colors.primary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(
                                      kOpenHandRadius12,
                                    ),
                                  ),
                                ),
                                onChanged: (_) {
                                  if (_error != null) {
                                    setState(() => _error = null);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    AnimatedSize(
                      duration: openHandMotionDuration(
                        context,
                        kOpenHandMotion180,
                      ),
                      curve: Curves.easeOutCubic,
                      child: _error == null
                          ? const SizedBox.shrink()
                          : Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: colors.errorContainer,
                                borderRadius: BorderRadius.circular(
                                  kOpenHandRadius12,
                                ),
                              ),
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onErrorContainer,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.request.actions
                      .map(_actionButton)
                      .toList(growable: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(WorkflowHumanAction action) {
    void onPressed() => _submit(action.id);
    return switch (action.style) {
      WorkflowHumanActionStyle.primary => FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.check_rounded, size: 18),
        label: Text(action.title.trim()),
      ),
      WorkflowHumanActionStyle.accent => FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
        child: Text(action.title.trim()),
      ),
      WorkflowHumanActionStyle.ghost => TextButton(
        onPressed: onPressed,
        child: Text(action.title.trim()),
      ),
      WorkflowHumanActionStyle.defaultStyle => OutlinedButton(
        onPressed: onPressed,
        child: Text(action.title.trim()),
      ),
    };
  }

  void _submit(String actionId) {
    final values = <String, Object?>{
      for (final field in widget.request.fields)
        if ((_controllers[field.name.trim()]?.text.trim() ?? '').isNotEmpty)
          field.name.trim(): _controllers[field.name.trim()]!.text,
    };
    try {
      WorkflowStructuredOutputParser.resolveValues(
        widget.request.fields,
        values,
        label: '人工输入参数',
      );
    } catch (error) {
      setState(() => _error = '$error');
      return;
    }
    _complete(
      WorkflowHumanInterventionResponse(actionId: actionId, inputs: values),
    );
  }

  void _handleTimeout() {
    _complete(
      const WorkflowHumanInterventionResponse(
        actionId: workflowHumanTimeoutHandleId,
      ),
    );
  }

  void _cancel() {
    if (!mounted || _completed) return;
    _completed = true;
    _timeout.cancel();
    Navigator.of(context).pop();
  }

  void _complete(WorkflowHumanInterventionResponse response) {
    if (!mounted || _completed) return;
    _completed = true;
    _timeout.cancel();
    Navigator.of(context).pop(response);
  }
}

String _displayValue(Object? value) {
  if (value == null) return '';
  if (value is Map || value is List) {
    return const JsonEncoder.withIndent('  ').convert(value);
  }
  return '$value';
}

String _fieldHint(WorkflowOutputType type) => switch (type) {
  WorkflowOutputType.boolean => '输入 true 或 false',
  WorkflowOutputType.integer => '输入整数',
  WorkflowOutputType.number => '输入数字',
  WorkflowOutputType.object => '输入 JSON 对象',
  WorkflowOutputType.array ||
  WorkflowOutputType.arrayString ||
  WorkflowOutputType.arrayNumber ||
  WorkflowOutputType.arrayObject ||
  WorkflowOutputType.arrayBoolean => '输入 JSON 数组',
  WorkflowOutputType.string => '请输入内容',
};
