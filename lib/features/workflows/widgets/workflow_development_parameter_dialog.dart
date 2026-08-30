import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../model/workflow_definition.dart';
import '../service/workflow_development_parameters.dart';
import 'workflow_parameter_reference_field.dart';

const double _developmentParameterActionSize = 42;
const double _developmentParameterListMaxHeight = 480;
const RoundedRectangleBorder _developmentParameterButtonShape =
    RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius12);

Future<List<WorkflowDevelopmentParameter>?>
showWorkflowDevelopmentParameterDialog(
  BuildContext context, {
  required List<WorkflowDevelopmentParameter> parameters,
  required FutureOr<List<WorkflowDevelopmentParameter>> Function(
    List<WorkflowDevelopmentParameter> parameters,
  )
  onRefresh,
  required List<WorkflowParameterReference> Function(
    WorkflowDevelopmentParameter parameter,
  )
  referencesFor,
  required String Function(WorkflowDevelopmentParameter parameter)
  ownerLabelFor,
}) => showAnimatedDialog<List<WorkflowDevelopmentParameter>>(
  context: context,
  barrierDismissible: false,
  dismissOnEscape: false,
  builder: (_) => _WorkflowDevelopmentParameterDialog(
    parameters: parameters,
    onRefresh: onRefresh,
    referencesFor: referencesFor,
    ownerLabelFor: ownerLabelFor,
  ),
);

class _WorkflowDevelopmentParameterDialog extends StatefulWidget {
  const _WorkflowDevelopmentParameterDialog({
    required this.parameters,
    required this.onRefresh,
    required this.referencesFor,
    required this.ownerLabelFor,
  });

  final List<WorkflowDevelopmentParameter> parameters;
  final FutureOr<List<WorkflowDevelopmentParameter>> Function(
    List<WorkflowDevelopmentParameter> parameters,
  )
  onRefresh;
  final List<WorkflowParameterReference> Function(
    WorkflowDevelopmentParameter parameter,
  )
  referencesFor;
  final String Function(WorkflowDevelopmentParameter parameter) ownerLabelFor;

  @override
  State<_WorkflowDevelopmentParameterDialog> createState() =>
      _WorkflowDevelopmentParameterDialogState();
}

class _WorkflowDevelopmentParameterDialogState
    extends State<_WorkflowDevelopmentParameterDialog> {
  late List<WorkflowDevelopmentParameter> _parameters = List.of(
    widget.parameters,
  );
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final parameters = await widget.onRefresh(_parameters);
      if (mounted) setState(() => _parameters = List.of(parameters));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _addParameter() async {
    final field = await _showCreateParameterDialog(
      context,
      usedNames: _parameters
          .map((parameter) => parameter.name)
          .where((name) => name.isNotEmpty)
          .toSet(),
    );
    if (!mounted || field == null) return;
    setState(() {
      _parameters = <WorkflowDevelopmentParameter>[
        ..._parameters,
        WorkflowDevelopmentParameter(
          id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
          field: field,
          source: WorkflowDevelopmentParameterSource.manual,
        ),
      ];
    });
  }

  void _replace(WorkflowDevelopmentParameter updated) {
    setState(() {
      _parameters = _parameters
          .map((parameter) => parameter.id == updated.id ? updated : parameter)
          .toList(growable: false);
    });
  }

  void _delete(WorkflowDevelopmentParameter parameter) {
    if (!parameter.canDelete) return;
    setState(() {
      _parameters = _parameters
          .where((item) => item.id != parameter.id)
          .toList(growable: false);
    });
  }

  void _close() => Navigator.of(context).pop(_parameters);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final listHeight = math.min(
      _developmentParameterListMaxHeight,
      viewport.height * 0.52,
    );
    final actionStyle = IconButton.styleFrom(
      fixedSize: const Size.square(_developmentParameterActionSize),
      padding: EdgeInsets.zero,
      shape: _developmentParameterButtonShape,
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurfaceVariant,
      side: BorderSide(color: colors.outlineVariant),
    );
    return buildOpenHandDialog(
      width: math.min(kOpenHandDialogWidthPanel, viewport.width - 36),
      maxHeight: viewport.height * 0.9,
      insetPadding: const EdgeInsets.all(18),
      child: Column(
        key: const ValueKey<String>('workflow-development-parameter-dialog'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 16, 16),
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
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(kOpenHandRadius14),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: colors.onPrimaryContainer,
                    size: 24,
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '参数列表',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      kOpenHandGap3,
                      Text(
                        '用于单节点运行的临时数据，关闭编辑器后会自动清空。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '刷新参数列表',
                  onPressed: _refreshing ? null : _refresh,
                  style: actionStyle,
                  icon: AnimatedSwitcher(
                    duration: openHandMotionDuration(
                      context,
                      kOpenHandMotion180,
                    ),
                    child: _refreshing
                        ? const SizedBox.square(
                            key: ValueKey<String>('refreshing'),
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            key: ValueKey<String>('idle'),
                          ),
                  ),
                ),
                kOpenHandHGap8,
                IconButton(
                  tooltip: '关闭',
                  onPressed: _close,
                  style: actionStyle,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '当前参数',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addParameter,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新增参数'),
                  style: OutlinedButton.styleFrom(
                    shape: _developmentParameterButtonShape,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: listHeight,
            child: _parameters.isEmpty
                ? _DevelopmentParameterEmptyState(onAdd: _addParameter)
                : Scrollbar(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                      itemCount: _parameters.length,
                      separatorBuilder: (_, _) => kOpenHandGap10,
                      itemBuilder: (context, index) {
                        final parameter = _parameters[index];
                        return _DevelopmentParameterItem(
                          key: ValueKey<String>(
                            '${parameter.id}:${parameter.name}:${parameter.field.type.storageValue}:${parameter.field.description}',
                          ),
                          parameter: parameter,
                          ownerLabel: widget.ownerLabelFor(parameter),
                          references: widget.referencesFor(parameter),
                          onValueChanged: (value) =>
                              _replace(parameter.copyWith(value: value)),
                          onDelete: parameter.canDelete
                              ? () => _delete(parameter)
                              : null,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DevelopmentParameterEmptyState extends StatelessWidget {
  const _DevelopmentParameterEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(kOpenHandRadius16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.data_array_rounded, size: 34, color: colors.primary),
            kOpenHandGap10,
            Text(
              '暂未配置临时参数',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            kOpenHandGap4,
            Text(
              '可新增参数，或在开始节点添加输入参数后刷新。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            kOpenHandGap14,
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新增参数'),
              style: OutlinedButton.styleFrom(
                shape: _developmentParameterButtonShape,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DevelopmentParameterItem extends StatelessWidget {
  const _DevelopmentParameterItem({
    super.key,
    required this.parameter,
    required this.ownerLabel,
    required this.references,
    required this.onValueChanged,
    this.onDelete,
  });

  final WorkflowDevelopmentParameter parameter;
  final String ownerLabel;
  final List<WorkflowParameterReference> references;
  final ValueChanged<String> onValueChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final field = parameter.field;
    final decoration = _developmentParameterInputDecoration(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final deleteButton = IconButton.filledTonal(
            tooltip: parameter.canDelete ? '删除参数' : '开始节点参数不可删除',
            onPressed: onDelete,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(44),
              padding: EdgeInsets.zero,
              shape: _developmentParameterButtonShape,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
          );
          final nameField = TextFormField(
            initialValue: field.name,
            enabled: false,
            decoration: decoration.copyWith(labelText: '参数名称'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: kOpenHandMonospaceFontFamily,
              fontWeight: FontWeight.w800,
            ),
          );
          final typeField = TextFormField(
            initialValue: field.type.storageValue,
            enabled: false,
            decoration: decoration.copyWith(labelText: '类型'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: kOpenHandMonospaceFontFamily,
            ),
          );
          final descriptionField = TextFormField(
            initialValue: field.description,
            enabled: false,
            decoration: decoration.copyWith(labelText: '参数介绍'),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(kOpenHandRadius8),
                    ),
                    child: Text(
                      ownerLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _DevelopmentParameterMeta(
                    label: field.required ? '必需' : '可选',
                  ),
                  kOpenHandHGap6,
                  _DevelopmentParameterMeta(
                    label: field.valueSource == WorkflowValueSource.constant
                        ? '常量'
                        : '变量',
                  ),
                ],
              ),
              kOpenHandGap10,
              if (compact) ...[
                SizedBox(height: 52, child: nameField),
                kOpenHandGap8,
                Row(
                  children: [
                    Expanded(child: SizedBox(height: 52, child: typeField)),
                    kOpenHandHGap8,
                    deleteButton,
                  ],
                ),
                kOpenHandGap8,
                SizedBox(height: 52, child: descriptionField),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: SizedBox(height: 52, child: nameField),
                    ),
                    kOpenHandHGap8,
                    SizedBox(width: 154, height: 52, child: typeField),
                    kOpenHandHGap8,
                    deleteButton,
                  ],
                ),
                kOpenHandGap8,
                SizedBox(height: 52, child: descriptionField),
              ],
              kOpenHandGap10,
              Text(
                '参数值',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              kOpenHandGap6,
              WorkflowParameterReferenceField(
                key: ValueKey<String>('development-value-${parameter.id}'),
                value: parameter.value,
                references: references,
                maxLines: 4,
                decoration: decoration.copyWith(
                  hintText: references.isEmpty ? '输入参数值' : '输入参数值，按 / 引用可用参数',
                ),
                onChanged: onValueChanged,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DevelopmentParameterMeta extends StatelessWidget {
  const _DevelopmentParameterMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: null,
    style: OutlinedButton.styleFrom(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: _developmentParameterButtonShape,
    ),
    child: Text(label),
  );
}

InputDecoration _developmentParameterInputDecoration(BuildContext context) =>
    InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
      ),
    );

Future<WorkflowOutputField?> _showCreateParameterDialog(
  BuildContext context, {
  required Set<String> usedNames,
}) => showAnimatedDialog<WorkflowOutputField>(
  context: context,
  builder: (_) => _CreateDevelopmentParameterDialog(usedNames: usedNames),
);

class _CreateDevelopmentParameterDialog extends StatefulWidget {
  const _CreateDevelopmentParameterDialog({required this.usedNames});

  final Set<String> usedNames;

  @override
  State<_CreateDevelopmentParameterDialog> createState() =>
      _CreateDevelopmentParameterDialogState();
}

class _CreateDevelopmentParameterDialogState
    extends State<_CreateDevelopmentParameterDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  WorkflowOutputType _type = WorkflowOutputType.string;
  bool _required = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (!workflowParameterNamePattern.hasMatch(name)) {
      setState(() => _error = '参数名称须以英文字母或下划线开头，仅包含字母、数字和下划线。');
      return;
    }
    if (widget.usedNames.contains(name)) {
      setState(() => _error = '参数“$name”已存在。');
      return;
    }
    Navigator.of(context).pop(
      WorkflowOutputField(
        id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        description: _descriptionController.text.trim(),
        type: _type,
        required: _required,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return buildOpenHandDialog(
      width: 620,
      insetPadding: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(kOpenHandRadius12),
                  ),
                  child: Icon(
                    Icons.add_chart_rounded,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Text(
                    '新增临时参数',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(
                      _developmentParameterActionSize,
                    ),
                    padding: EdgeInsets.zero,
                    shape: _developmentParameterButtonShape,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            kOpenHandGap18,
            TextField(
              controller: _nameController,
              autofocus: true,
              maxLength: 64,
              buildCounter: openHandHiddenTextFieldCounter,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: _developmentParameterInputDecoration(context)
                  .copyWith(
                    labelText: '参数名称',
                    hintText: '例如：test_token',
                    errorText: _error,
                  ),
            ),
            kOpenHandGap10,
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 460;
                final typeField = DropdownButtonFormField<WorkflowOutputType>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: _developmentParameterInputDecoration(
                    context,
                  ).copyWith(labelText: '类型'),
                  items: WorkflowOutputType.values
                      .map(
                        (type) => DropdownMenuItem<WorkflowOutputType>(
                          value: type,
                          child: Text(type.storageValue),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (type) =>
                      setState(() => _type = type ?? WorkflowOutputType.string),
                );
                final requiredField = SwitchListTile.adaptive(
                  value: _required,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  title: const Text('必需参数'),
                  onChanged: (value) => setState(() => _required = value),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(kOpenHandRadius12),
                  ),
                );
                return compact
                    ? Column(
                        children: [typeField, kOpenHandGap8, requiredField],
                      )
                    : Row(
                        children: [
                          Expanded(child: typeField),
                          kOpenHandHGap10,
                          Expanded(child: requiredField),
                        ],
                      );
              },
            ),
            kOpenHandGap10,
            TextField(
              controller: _descriptionController,
              maxLength: 120,
              buildCounter: openHandHiddenTextFieldCounter,
              decoration: _developmentParameterInputDecoration(
                context,
              ).copyWith(labelText: '参数介绍', hintText: '可选，说明参数的用途'),
            ),
            kOpenHandGap18,
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    shape: _developmentParameterButtonShape,
                  ),
                  child: const Text('取消'),
                ),
                kOpenHandHGap10,
                FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    shape: _developmentParameterButtonShape,
                  ),
                  child: const Text('添加参数'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
