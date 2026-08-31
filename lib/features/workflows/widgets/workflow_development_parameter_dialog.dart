import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../model/workflow_definition.dart';
import '../service/workflow_development_parameters.dart';
import '../workflow_node_presentation.dart';
import 'workflow_parameter_reference_field.dart';

const double _developmentParameterActionSize = 44;
const double _developmentParameterFieldHeight = 52;
const double _developmentParameterListMaxHeight = 640;
const double _developmentParameterCompactWidth = 680;
const double _developmentParameterTargetItemHeight = 52;

/// 需容纳最长类型文案（如 array[boolean]）与下拉箭头。
const double _developmentParameterTypeFieldWidth = 220;
const RoundedRectangleBorder _developmentParameterButtonShape =
    RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius12);

@immutable
class WorkflowDevelopmentParameterTarget {
  const WorkflowDevelopmentParameterTarget({
    required this.nodeId,
    required this.nodeLabel,
    required this.direction,
  });

  final String nodeId;
  final String nodeLabel;
  final WorkflowParameterDirection direction;

  String get displayNodeLabel {
    final label = nodeLabel.trim();
    return label.isEmpty ? '未命名节点' : label;
  }

  String get label => '$displayNodeLabel - ${direction.label}';

  @override
  bool operator ==(Object other) =>
      other is WorkflowDevelopmentParameterTarget &&
      nodeId == other.nodeId &&
      direction == other.direction;

  @override
  int get hashCode => Object.hash(nodeId, direction);
}

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
  List<WorkflowDevelopmentParameterTarget> parameterTargets = const [],
  List<WorkflowParameterReference> availableParameters = const [],
}) => showAnimatedDialog<List<WorkflowDevelopmentParameter>>(
  context: context,
  transitionProfile: kOpenHandLayoutSafeTransitionProfile,
  barrierDismissible: false,
  dismissOnEscape: false,
  builder: (_) => _WorkflowDevelopmentParameterDialog(
    parameters: parameters,
    onRefresh: onRefresh,
    referencesFor: referencesFor,
    ownerLabelFor: ownerLabelFor,
    parameterTargets: parameterTargets,
    availableParameters: availableParameters,
  ),
);

class _WorkflowDevelopmentParameterDialog extends StatefulWidget {
  const _WorkflowDevelopmentParameterDialog({
    required this.parameters,
    required this.onRefresh,
    required this.referencesFor,
    required this.ownerLabelFor,
    required this.parameterTargets,
    required this.availableParameters,
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
  final List<WorkflowDevelopmentParameterTarget> parameterTargets;
  final List<WorkflowParameterReference> availableParameters;

  @override
  State<_WorkflowDevelopmentParameterDialog> createState() =>
      _WorkflowDevelopmentParameterDialogState();
}

class _WorkflowDevelopmentParameterDialogState
    extends State<_WorkflowDevelopmentParameterDialog> {
  late final List<WorkflowDevelopmentParameter> _initialParameters = List.of(
    widget.parameters,
  );
  late List<WorkflowDevelopmentParameter> _parameters = List.of(
    widget.parameters,
  );
  late final ScrollController _scrollController = ScrollController();
  bool _refreshing = false;
  bool _closeConfirmationOpen = false;
  bool _validationRequested = false;
  bool _listReady = false;

  bool get _isDirty =>
      !_sameDevelopmentParameters(_initialParameters, _parameters);

  @override
  void initState() {
    super.initState();
    unawaited(_waitForInitialLayout());
  }

  Future<void> _waitForInitialLayout() async {
    final binding = WidgetsBinding.instance;
    await binding.endOfFrame;
    await binding.endOfFrame;
    if (mounted) setState(() => _listReady = true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
    final target = await _showCreateParameterDialog(
      context,
      targets: widget.parameterTargets,
    );
    if (!mounted || target == null) return;
    final id = 'manual-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _parameters = <WorkflowDevelopmentParameter>[
        ..._parameters,
        WorkflowDevelopmentParameter(
          id: id,
          field: WorkflowOutputField(id: id),
          source: WorkflowDevelopmentParameterSource.manual,
          ownerNodeId: target.nodeId,
          direction: target.direction,
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

  List<WorkflowParameterReference> _candidatesFor(
    WorkflowDevelopmentParameter parameter,
  ) {
    final usedNames = _parameters
        .where((item) => item.id != parameter.id)
        .map((item) => item.name)
        .where((name) => name.isNotEmpty)
        .toSet();
    return widget.availableParameters
        .where((reference) => !usedNames.contains(reference.name))
        .toList(growable: false);
  }

  String? _nameErrorFor(WorkflowDevelopmentParameter parameter) {
    if (!parameter.isWorkflowDefined && parameter.name.isEmpty) {
      return '请输入参数名称';
    }
    if (!workflowParameterNamePattern.hasMatch(parameter.name)) {
      return '名称只能包含字母、数字和下划线，且不能以数字开头';
    }
    final duplicates = _parameters
        .where((item) => item.name == parameter.name)
        .length;
    if (duplicates > 1) return '参数名称重复';
    return null;
  }

  bool _hasValidationErrors() =>
      _parameters.any((parameter) => _nameErrorFor(parameter) != null);

  void _save() {
    if (_hasValidationErrors()) {
      setState(() => _validationRequested = true);
      return;
    }
    Navigator.of(
      context,
    ).pop(List<WorkflowDevelopmentParameter>.of(_parameters));
  }

  Future<void> _close() async {
    if (!_isDirty || _closeConfirmationOpen) {
      if (!_isDirty) Navigator.of(context).pop();
      return;
    }
    setState(() => _closeConfirmationOpen = true);
    final discard = await showOpenHandConfirmDialog(
      context: context,
      title: '放弃未保存的参数修改？',
      message: '参数列表中的修改尚未保存，关闭后将无法恢复。',
      cancelLabel: '继续编辑',
      confirmLabel: '放弃修改',
      icon: Icon(
        Icons.warning_amber_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      destructive: true,
      barrierDismissible: false,
    );
    if (!mounted) return;
    setState(() => _closeConfirmationOpen = false);
    if (discard) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final listHeight = math.min(
      _developmentParameterListMaxHeight,
      viewport.height * 0.64,
    );
    final actionStyle = IconButton.styleFrom(
      fixedSize: const Size.square(_developmentParameterActionSize),
      padding: EdgeInsets.zero,
      shape: _developmentParameterButtonShape,
      shadowColor: Colors.transparent,
      disabledBackgroundColor: colors.surfaceContainerHighest.withValues(
        alpha: 0.72,
      ),
      disabledForegroundColor: colors.onSurface.withValues(alpha: 0.32),
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
                IconButton.filledTonal(
                  tooltip: '新增参数',
                  onPressed: widget.parameterTargets.isEmpty
                      ? null
                      : _addParameter,
                  style: actionStyle,
                  icon: const Icon(Icons.add_rounded),
                ),
                kOpenHandHGap8,
                IconButton.filledTonal(
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
                IconButton.filledTonal(
                  tooltip: '保存参数列表',
                  onPressed: _isDirty ? _save : null,
                  style: actionStyle,
                  icon: const Icon(Icons.save_rounded),
                ),
                kOpenHandHGap8,
                IconButton.filledTonal(
                  tooltip: '关闭',
                  onPressed: _close,
                  style: actionStyle,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          SizedBox(
            height: listHeight,
            child: _parameters.isEmpty
                ? const _DevelopmentParameterEmptyState()
                : !_listReady
                ? const SizedBox.expand()
                : OpenHandSafeScrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    interactive: true,
                    thickness: 6,
                    child: ListView.separated(
                      controller: _scrollController,
                      primary: false,
                      // 弹窗转场期间避免列表项的独立 layer 脱离后参与布局，
                      // 参数列表高度受限且可见项很少，关闭分层不会造成性能负担。
                      addRepaintBoundaries: false,
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                      itemCount: _parameterGroups.length,
                      separatorBuilder: (_, _) => kOpenHandGap10,
                      itemBuilder: (context, index) {
                        final group = _parameterGroups[index];
                        return _DevelopmentParameterNodeGroup(
                          key: ValueKey<String>(
                            'development-node-${group.key}',
                          ),
                          nodeLabel: group.name,
                          inputParameters: group.parameters
                              .where(
                                (parameter) =>
                                    parameter.direction ==
                                    WorkflowParameterDirection.input,
                              )
                              .toList(growable: false),
                          outputParameters: group.parameters
                              .where(
                                (parameter) =>
                                    parameter.direction ==
                                    WorkflowParameterDirection.output,
                              )
                              .toList(growable: false),
                          referencesFor: widget.referencesFor,
                          onValueChanged: (parameter, value) =>
                              _replace(parameter.copyWith(value: value)),
                          onFieldChanged: (parameter, field) =>
                              _replace(parameter.copyWith(field: field)),
                          onDelete: _delete,
                          candidatesFor: _candidatesFor,
                          nameErrorFor: _validationRequested
                              ? _nameErrorFor
                              : (_) => null,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<
    ({String key, String name, List<WorkflowDevelopmentParameter> parameters})
  >
  get _parameterGroups {
    final grouped = <String, List<WorkflowDevelopmentParameter>>{};
    for (final parameter in _parameters) {
      final key = parameter.ownerNodeId ?? parameter.id;
      grouped.putIfAbsent(key, () => []).add(parameter);
    }
    return grouped.entries
        .map(
          (entry) => (
            key: entry.key,
            name: widget.ownerLabelFor(entry.value.first).trim().isEmpty
                ? '未命名节点'
                : widget.ownerLabelFor(entry.value.first).trim(),
            parameters: entry.value,
          ),
        )
        .toList(growable: false);
  }
}

class _DevelopmentParameterEmptyState extends StatelessWidget {
  const _DevelopmentParameterEmptyState();

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
          ],
        ),
      ),
    );
  }
}

class _DevelopmentParameterNodeGroup extends StatelessWidget {
  const _DevelopmentParameterNodeGroup({
    super.key,
    required this.nodeLabel,
    required this.inputParameters,
    required this.outputParameters,
    required this.referencesFor,
    required this.onValueChanged,
    required this.onFieldChanged,
    required this.onDelete,
    required this.candidatesFor,
    required this.nameErrorFor,
  });

  final String nodeLabel;
  final List<WorkflowDevelopmentParameter> inputParameters;
  final List<WorkflowDevelopmentParameter> outputParameters;
  final List<WorkflowParameterReference> Function(
    WorkflowDevelopmentParameter parameter,
  )
  referencesFor;
  final void Function(WorkflowDevelopmentParameter parameter, String value)
  onValueChanged;
  final void Function(
    WorkflowDevelopmentParameter parameter,
    WorkflowOutputField field,
  )
  onFieldChanged;
  final void Function(WorkflowDevelopmentParameter parameter) onDelete;
  final List<WorkflowParameterReference> Function(
    WorkflowDevelopmentParameter parameter,
  )
  candidatesFor;
  final String? Function(WorkflowDevelopmentParameter parameter) nameErrorFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(kOpenHandRadius10),
                ),
                child: Icon(
                  Icons.account_tree_rounded,
                  size: 18,
                  color: colors.onPrimaryContainer,
                ),
              ),
              kOpenHandHGap10,
              Expanded(
                child: Text(
                  nodeLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${inputParameters.length + outputParameters.length} 个参数',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (inputParameters.isNotEmpty) ...[
            kOpenHandGap12,
            _DevelopmentParameterSection(
              title: '输入参数',
              icon: Icons.input_rounded,
              parameters: inputParameters,
              referencesFor: referencesFor,
              onValueChanged: onValueChanged,
              onFieldChanged: onFieldChanged,
              onDelete: onDelete,
              candidatesFor: candidatesFor,
              nameErrorFor: nameErrorFor,
            ),
          ],
          if (outputParameters.isNotEmpty) ...[
            kOpenHandGap12,
            _DevelopmentParameterSection(
              title: '输出参数',
              icon: Icons.output_rounded,
              parameters: outputParameters,
              referencesFor: referencesFor,
              onValueChanged: onValueChanged,
              onFieldChanged: onFieldChanged,
              onDelete: onDelete,
              candidatesFor: candidatesFor,
              nameErrorFor: nameErrorFor,
            ),
          ],
        ],
      ),
    );
  }
}

class _DevelopmentParameterSection extends StatelessWidget {
  const _DevelopmentParameterSection({
    required this.title,
    required this.icon,
    required this.parameters,
    required this.referencesFor,
    required this.onValueChanged,
    required this.onFieldChanged,
    required this.onDelete,
    required this.candidatesFor,
    required this.nameErrorFor,
  });

  final String title;
  final IconData icon;
  final List<WorkflowDevelopmentParameter> parameters;
  final List<WorkflowParameterReference> Function(
    WorkflowDevelopmentParameter parameter,
  )
  referencesFor;
  final void Function(WorkflowDevelopmentParameter parameter, String value)
  onValueChanged;
  final void Function(
    WorkflowDevelopmentParameter parameter,
    WorkflowOutputField field,
  )
  onFieldChanged;
  final void Function(WorkflowDevelopmentParameter parameter) onDelete;
  final List<WorkflowParameterReference> Function(
    WorkflowDevelopmentParameter parameter,
  )
  candidatesFor;
  final String? Function(WorkflowDevelopmentParameter parameter) nameErrorFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.primary),
              kOpenHandHGap8,
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              kOpenHandHGap6,
              Text(
                '${parameters.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          ...parameters.indexed.map((entry) {
            final parameter = entry.$2;
            return Padding(
              padding: EdgeInsets.only(
                bottom: entry.$1 == parameters.length - 1 ? 0 : 8,
              ),
              child: _DevelopmentParameterItem(
                key: ValueKey<String>('development-parameter-${parameter.id}'),
                parameter: parameter,
                references: referencesFor(parameter),
                onValueChanged: (value) => onValueChanged(parameter, value),
                onFieldChanged: (field) => onFieldChanged(parameter, field),
                onDelete: parameter.canDelete
                    ? () => onDelete(parameter)
                    : null,
                candidates: candidatesFor(parameter),
                nameError: nameErrorFor(parameter),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DevelopmentParameterItem extends StatelessWidget {
  const _DevelopmentParameterItem({
    super.key,
    required this.parameter,
    required this.references,
    required this.onValueChanged,
    required this.onFieldChanged,
    required this.candidates,
    required this.nameError,
    this.onDelete,
  });

  final WorkflowDevelopmentParameter parameter;
  final List<WorkflowParameterReference> references;
  final ValueChanged<String> onValueChanged;
  final ValueChanged<WorkflowOutputField> onFieldChanged;
  final List<WorkflowParameterReference> candidates;
  final String? nameError;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final field = parameter.field;
    final decoration = _developmentParameterInputDecoration(context);
    final readOnlyDecoration = _developmentParameterInputDecoration(
      context,
      enabled: false,
    );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < _developmentParameterCompactWidth;
          final deleteButton = IconButton.filledTonal(
            tooltip: parameter.canDelete ? '删除参数' : '开始节点参数不可删除',
            onPressed: onDelete,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(_developmentParameterFieldHeight),
              padding: EdgeInsets.zero,
              shape: _developmentParameterButtonShape,
              disabledBackgroundColor: colors.surfaceContainerHighest,
              disabledForegroundColor: colors.onSurface.withValues(alpha: 0.32),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
          );
          final nameField = _DevelopmentParameterNameField(
            parameter: parameter,
            candidates: candidates,
            enabled: !parameter.isWorkflowDefined,
            errorText: nameError,
            onChanged: (name) => onFieldChanged(field.copyWith(name: name)),
            onSelected: (reference) => onFieldChanged(
              field.copyWith(
                name: reference.name,
                type: reference.field.type,
                description: reference.field.description,
                required: reference.field.required,
                valueSource: reference.field.valueSource,
              ),
            ),
          );
          final typeField = parameter.isWorkflowDefined
              ? TextFormField(
                  initialValue: field.type.storageValue,
                  enabled: false,
                  decoration: readOnlyDecoration.copyWith(labelText: '类型'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface.withValues(alpha: 0.56),
                  ),
                )
              : AnimatedDropdownButtonFormField<WorkflowOutputType>(
                  initialValue: field.type,
                  isExpanded: true,
                  decoration: decoration.copyWith(labelText: '类型'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: kOpenHandMonospaceFontFamily,
                    fontWeight: FontWeight.w800,
                  ),
                  items: WorkflowOutputType.values
                      .map(
                        (type) => DropdownMenuItem<WorkflowOutputType>(
                          value: type,
                          child: Text(
                            type.storageValue,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (type) {
                    if (type != null) {
                      onFieldChanged(field.copyWith(type: type));
                    }
                  },
                );
          final descriptionField = TextFormField(
            initialValue: field.description,
            enabled: !parameter.isWorkflowDefined,
            onChanged: (description) =>
                onFieldChanged(field.copyWith(description: description)),
            decoration:
                (parameter.isWorkflowDefined ? readOnlyDecoration : decoration)
                    .copyWith(labelText: '参数介绍'),
            style: parameter.isWorkflowDefined
                ? theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.56),
                  )
                : null,
          );
          final requiredField = _DevelopmentParameterMeta(
            label: '必需',
            selected: field.required,
            width: 82,
            enabled: !parameter.isWorkflowDefined,
            onChanged: (selected) =>
                onFieldChanged(field.copyWith(required: selected)),
          );
          final sourceField = _DevelopmentParameterMeta(
            label: field.valueSource == WorkflowValueSource.constant
                ? '常量'
                : '变量',
            selected: field.valueSource == WorkflowValueSource.constant,
            width: 82,
            enabled: !parameter.isWorkflowDefined,
            onChanged: (selected) => onFieldChanged(
              field.copyWith(
                valueSource: selected
                    ? WorkflowValueSource.constant
                    : WorkflowValueSource.variable,
              ),
            ),
          );
          final descriptionRow = SizedBox(
            height: _developmentParameterFieldHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: descriptionField),
                kOpenHandHGap8,
                requiredField,
                kOpenHandHGap8,
                sourceField,
              ],
            ),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                SizedBox(
                  height: nameError == null
                      ? _developmentParameterFieldHeight
                      : null,
                  child: nameField,
                ),
                kOpenHandGap8,
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: _developmentParameterFieldHeight,
                        child: typeField,
                      ),
                    ),
                    kOpenHandHGap8,
                    deleteButton,
                  ],
                ),
                kOpenHandGap8,
                SizedBox(
                  height: _developmentParameterFieldHeight,
                  child: descriptionField,
                ),
                kOpenHandGap8,
                Row(children: [requiredField, kOpenHandHGap8, sourceField]),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: SizedBox(
                        height: nameError == null
                            ? _developmentParameterFieldHeight
                            : null,
                        child: nameField,
                      ),
                    ),
                    kOpenHandHGap8,
                    SizedBox(
                      width: _developmentParameterTypeFieldWidth,
                      height: _developmentParameterFieldHeight,
                      child: typeField,
                    ),
                    kOpenHandHGap8,
                    deleteButton,
                  ],
                ),
                kOpenHandGap8,
                descriptionRow,
              ],
              kOpenHandGap10,
              WorkflowParameterReferenceField(
                key: ValueKey<String>('development-value-${parameter.id}'),
                value: parameter.value,
                references: references,
                maxLines: 4,
                decoration: decoration.copyWith(
                  labelText: '参数值',
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
  const _DevelopmentParameterMeta({
    required this.label,
    required this.selected,
    required this.width,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final double width;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;
    return SizedBox(
      width: width,
      height: _developmentParameterFieldHeight,
      child: OutlinedButton(
        onPressed: enabled ? () => onChanged(!selected) : null,
        style: OutlinedButton.styleFrom(
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: foreground,
          disabledForegroundColor: colors.onSurface.withValues(alpha: 0.38),
          backgroundColor: selected
              ? (enabled
                    ? colors.primaryContainer
                    : colors.surfaceContainerHighest)
              : (enabled
                    ? colors.surfaceContainerLow
                    : colors.surfaceContainerHighest),
          side: BorderSide(
            color: enabled && selected
                ? colors.primary.withValues(alpha: 0.5)
                : colors.outlineVariant.withValues(alpha: enabled ? 1 : 0.6),
          ),
          shape: _developmentParameterButtonShape,
        ),
        child: Text(label),
      ),
    );
  }
}

InputDecoration _developmentParameterInputDecoration(
  BuildContext context, {
  bool enabled = true,
}) {
  final colors = Theme.of(context).colorScheme;
  final radius = BorderRadius.circular(kOpenHandRadius12);
  final enabledBorder = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  final focusedBorder = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: colors.primary, width: 1.6),
  );
  final disabledBorder = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(
      color: colors.outlineVariant.withValues(alpha: 0.52),
    ),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: enabled
        ? colors.surface
        : colors.surfaceContainerHighest.withValues(alpha: 0.72),
    labelStyle: enabled
        ? null
        : TextStyle(
            color: colors.onSurfaceVariant.withValues(alpha: 0.58),
            fontWeight: FontWeight.w600,
          ),
    floatingLabelStyle: enabled
        ? null
        : TextStyle(
            color: colors.onSurfaceVariant.withValues(alpha: 0.58),
            fontWeight: FontWeight.w600,
          ),
    hintStyle: enabled
        ? null
        : TextStyle(color: colors.onSurfaceVariant.withValues(alpha: 0.5)),
    border: enabled ? enabledBorder : disabledBorder,
    enabledBorder: enabled ? enabledBorder : disabledBorder,
    focusedBorder: enabled ? focusedBorder : disabledBorder,
    disabledBorder: disabledBorder,
    errorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: colors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: colors.error, width: 1.6),
    ),
  );
}

class _DevelopmentParameterNameField extends StatelessWidget {
  const _DevelopmentParameterNameField({
    required this.parameter,
    required this.candidates,
    required this.enabled,
    required this.errorText,
    required this.onChanged,
    required this.onSelected,
  });

  final WorkflowDevelopmentParameter parameter;
  final List<WorkflowParameterReference> candidates;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final ValueChanged<WorkflowParameterReference> onSelected;

  @override
  Widget build(BuildContext context) {
    final decoration = _developmentParameterInputDecoration(
      context,
      enabled: enabled,
    ).copyWith(labelText: '参数名称', errorText: errorText);
    if (!enabled) {
      return TextFormField(
        initialValue: parameter.name,
        enabled: false,
        decoration: decoration,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontFamily: kOpenHandMonospaceFontFamily,
          fontWeight: FontWeight.w800,
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.56),
        ),
      );
    }
    return Autocomplete<WorkflowParameterReference>(
      displayStringForOption: (reference) => reference.name,
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        return candidates.where(
          (reference) =>
              query.isEmpty || reference.name.toLowerCase().contains(query),
        );
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        if (controller.text != parameter.name) {
          controller.value = TextEditingValue(
            text: parameter.name,
            selection: TextSelection.collapsed(offset: parameter.name.length),
          );
        }
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          maxLength: 64,
          buildCounter: openHandHiddenTextFieldCounter,
          onChanged: onChanged,
          decoration: decoration,
        );
      },
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(kOpenHandRadius12),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, minWidth: 360),
            child: ListView.builder(
              padding: const EdgeInsets.all(6),
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final reference = options.elementAt(index);
                final theme = Theme.of(context);
                final colors = theme.colorScheme;
                final accent = colors.primary;
                final description = reference.field.description.trim();
                return InkWell(
                  onTap: () => onSelected(reference),
                  borderRadius: BorderRadius.circular(kOpenHandRadius9),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reference.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        if (description.isNotEmpty)
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              height: 1.25,
                            ),
                          ),
                        kOpenHandGap4,
                        Wrap(
                          spacing: 4,
                          runSpacing: 3,
                          children: [
                            _ReferenceTag(label: reference.nodeTitle),
                            _ReferenceTag(
                              label: reference.direction.label,
                              accent: accent,
                            ),
                            _ReferenceTag(
                              label: reference.field.type.storageValue,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ReferenceTag extends StatelessWidget {
  const _ReferenceTag({required this.label, this.accent});

  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = accent ?? colors.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

Future<WorkflowDevelopmentParameterTarget?> _showCreateParameterDialog(
  BuildContext context, {
  required List<WorkflowDevelopmentParameterTarget> targets,
}) => showAnimatedDialog<WorkflowDevelopmentParameterTarget>(
  context: context,
  transitionProfile: kOpenHandLayoutSafeTransitionProfile,
  builder: (_) => _CreateDevelopmentParameterDialog(targets: targets),
);

class _DevelopmentParameterTargetOption extends StatelessWidget {
  const _DevelopmentParameterTargetOption({
    required this.target,
    this.dense = false,
  });

  final WorkflowDevelopmentParameterTarget target;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = workflowParameterDirectionAccent(colors, target.direction);
    final icon = workflowParameterDirectionIcon(target.direction);
    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 8,
        vertical: dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 12 : 13, color: accent),
          if (dense) const SizedBox(width: 3) else kOpenHandHGap4,
          Text(
            target.direction.shortLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: target.label,
      child: Row(
        children: [
          if (!dense) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(kOpenHandRadius7),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, size: 16, color: accent),
            ),
            kOpenHandHGap8,
          ],
          Expanded(
            child: Text(
              target.displayNodeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ),
          kOpenHandHGap8,
          chip,
        ],
      ),
    );
  }
}

class _CreateDevelopmentParameterDialog extends StatefulWidget {
  const _CreateDevelopmentParameterDialog({required this.targets});

  final List<WorkflowDevelopmentParameterTarget> targets;

  @override
  State<_CreateDevelopmentParameterDialog> createState() =>
      _CreateDevelopmentParameterDialogState();
}

class _CreateDevelopmentParameterDialogState
    extends State<_CreateDevelopmentParameterDialog> {
  WorkflowDevelopmentParameterTarget? _target;

  @override
  void initState() {
    super.initState();
    _target = widget.targets.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return buildOpenHandDialog(
      width: 520,
      insetPadding: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '新增参数',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            kOpenHandGap18,
            AnimatedDropdownButtonFormField<WorkflowDevelopmentParameterTarget>(
              initialValue: _target,
              isExpanded: true,
              itemHeight: _developmentParameterTargetItemHeight,
              borderRadius: BorderRadius.circular(kOpenHandRadius14),
              decoration: _developmentParameterInputDecoration(
                context,
              ).copyWith(labelText: '添加到'),
              selectedItemBuilder: (context) => widget.targets
                  .map(
                    (target) => _DevelopmentParameterTargetOption(
                      target: target,
                      dense: true,
                    ),
                  )
                  .toList(growable: false),
              items: widget.targets
                  .map(
                    (target) =>
                        DropdownMenuItem<WorkflowDevelopmentParameterTarget>(
                          value: target,
                          child: _DevelopmentParameterTargetOption(
                            target: target,
                          ),
                        ),
                  )
                  .toList(growable: false),
              onChanged: widget.targets.isEmpty
                  ? null
                  : (target) => setState(() => _target = target),
            ),
            kOpenHandGap18,
            buildOpenHandDialogActionsBar(
              actions: [
                OpenHandDialogActionButton.secondary(
                  label: '取消',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                OpenHandDialogActionButton.primary(
                  label: '确认添加',
                  onPressed: _target == null
                      ? null
                      : () => Navigator.of(context).pop(_target),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

bool _sameDevelopmentParameters(
  List<WorkflowDevelopmentParameter> left,
  List<WorkflowDevelopmentParameter> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final a = left[index];
    final b = right[index];
    if (a.id != b.id ||
        a.ownerNodeId != b.ownerNodeId ||
        a.source != b.source ||
        a.direction != b.direction ||
        a.value != b.value ||
        a.field.name != b.field.name ||
        a.field.description != b.field.description ||
        a.field.type != b.field.type ||
        a.field.required != b.field.required ||
        a.field.value != b.field.value ||
        a.field.valueMode != b.field.valueMode ||
        a.field.defaultValue != b.field.defaultValue ||
        a.field.valueSource != b.field.valueSource) {
      return false;
    }
  }
  return true;
}
