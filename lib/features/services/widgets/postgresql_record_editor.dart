import 'package:flutter/material.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import 'service_dialog_controls.dart';

const int _kPostgresqlJsonMaxEntries = 200;
const int _kPostgresqlJsonMaxDepth = 4;

const Map<String, String> _kPostgresqlColumnLabels = <String, String>{
  'id': '记录 ID',
  'job_id': '任务 ID',
  'name': '名称',
  'url': '地址',
  'source': '来源',
  'host': '主机',
  'product': '产品',
  'category': '分类',
  'stage': '阶段',
  'level': '日志级别',
  'credential_state': '凭据状态',
  'masked_credential': '脱敏凭据',
  'request_json': '请求内容',
  'progress_json': '进度信息',
  'evidence_json': '证据内容',
  'metadata': '元数据',
  'balance_summary': '余额摘要',
  'message': '消息',
  'error_message': '错误信息',
  'stack_summary': '堆栈摘要',
  'created_at': '创建时间',
  'finished_at': '完成时间',
  'last_scanned_at': '最近扫描时间',
};

const Map<String, List<String>> _kPostgresqlSelectOptions =
    <String, List<String>>{
      'stage': <String>[
        'pending',
        'queued',
        'running',
        'scanning',
        'completed',
        'failed',
      ],
      'level': <String>['debug', 'info', 'warn', 'error'],
      'credential_state': <String>[
        'unknown',
        'none',
        'valid',
        'invalid',
        'expired',
      ],
    };

Future<Map<String, Object?>?> showPostgresqlRecordEditor(
  BuildContext context, {
  required String title,
  required Map<String, Object?> initial,
  required List<Map<String, Object?>> columns,
  List<String> primaryKeys = const <String>[],
}) => showAnimatedDialog<Map<String, Object?>>(
  context: context,
  builder: (_) => buildOpenHandDialog(
    maxWidth: kOpenHandDialogWidthWide,
    maxHeight: kOpenHandDialogHeightTall,
    child: ServiceDialogInteractionTheme(
      child: _PostgresqlRecordEditor(
        title: title,
        initial: initial,
        columns: columns,
        primaryKeys: primaryKeys,
      ),
    ),
  ),
);

class _PostgresqlRecordEditor extends StatefulWidget {
  const _PostgresqlRecordEditor({
    required this.title,
    required this.initial,
    required this.columns,
    required this.primaryKeys,
  });

  final String title;
  final Map<String, Object?> initial;
  final List<Map<String, Object?>> columns;
  final List<String> primaryKeys;

  @override
  State<_PostgresqlRecordEditor> createState() =>
      _PostgresqlRecordEditorState();
}

class _PostgresqlRecordEditorState extends State<_PostgresqlRecordEditor> {
  late final List<_PostgresqlColumnSpec> _columns;
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};
  final Map<String, _PostgresqlBooleanValue> _booleanValues =
      <String, _PostgresqlBooleanValue>{};
  final Map<String, String?> _selectValues = <String, String?>{};
  final Map<String, Object?> _jsonValues = <String, Object?>{};
  final Map<String, String> _fieldErrors = <String, String>{};
  final ScrollController _scrollController = ScrollController();
  String? _error;

  bool get _editing => widget.initial.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _columns = _buildColumnSpecs();
    for (final column in _columns) {
      final value = widget.initial[column.name];
      if (column.isJson) {
        _jsonValues[column.name] = _copyJsonValue(value);
      } else if (column.isBoolean) {
        _booleanValues[column.name] = switch (value) {
          true => _PostgresqlBooleanValue.yes,
          false => _PostgresqlBooleanValue.no,
          _ => _PostgresqlBooleanValue.unset,
        };
      } else if (column.selectOptions.isNotEmpty) {
        final text = value == null ? '' : '$value';
        _selectValues[column.name] = text.isEmpty ? null : text;
      } else {
        _textControllers[column.name] = TextEditingController(
          text: _scalarText(value),
        );
      }
    }
  }

  List<_PostgresqlColumnSpec> _buildColumnSpecs() {
    final result = <_PostgresqlColumnSpec>[];
    final seen = <String>{};
    for (final column in widget.columns) {
      final name = '${column['name'] ?? ''}'.trim();
      if (name.isEmpty || !seen.add(name)) continue;
      result.add(
        _PostgresqlColumnSpec(
          name: name,
          dataType: '${column['dataType'] ?? 'text'}',
          nullable: column['nullable'] == true,
          defaultValue: column['defaultValue'],
          primaryKey: widget.primaryKeys.contains(name),
        ),
      );
    }
    for (final name in widget.initial.keys) {
      if (name.trim().isEmpty || !seen.add(name)) continue;
      result.add(
        _PostgresqlColumnSpec(
          name: name,
          dataType: 'text',
          nullable: true,
          primaryKey: widget.primaryKeys.contains(name),
        ),
      );
    }
    return result;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(kOpenHandRadius12),
                ),
                child: Icon(Icons.table_view_rounded, color: colors.primary),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    kOpenHandGap3,
                    Text(
                      _editing ? '按字段修改记录，主键仅用于定位' : '按字段填写记录，留空项将使用数据库默认值',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              ServiceDialogHeaderIconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          kOpenHandGap14,
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(kOpenHandRadius12),
              border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                  kOpenHandHGap8,
                  Expanded(
                    child: Text(
                      '结构化表单会按 PostgreSQL 字段类型校验文本、数字、布尔值和 JSONB，减少格式错误。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          kOpenHandGap14,
          Expanded(
            child: OpenHandSafeScrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              interactive: true,
              thickness: 5,
              radius: kOpenHandPillRadius,
              scrollbarOrientation: ScrollbarOrientation.right,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: openHandDialogAwareScrollPhysics(context),
                padding: const EdgeInsets.only(right: 12),
                child: _buildSections(context),
              ),
            ),
          ),
          OpenHandVerticalRevealSwitcher(
            presentKey: ValueKey<String>('postgres-editor-error-$_error'),
            child: _error == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
          ),
          kOpenHandGap14,
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(context).maybePop(),
                label: '取消',
              ),
              OpenHandDialogActionButton.primary(
                onPressed: _submit,
                label: _editing ? '保存修改' : '新增记录',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSections(BuildContext context) {
    final groups = <String, List<_PostgresqlColumnSpec>>{};
    for (final column in _columns) {
      groups
          .putIfAbsent(_groupLabel(column), () => <_PostgresqlColumnSpec>[])
          .add(column);
    }
    const order = <String>['基础信息', '状态与结果', '结构化内容', '时间信息', '其他字段'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final label in order)
          if (groups[label]?.isNotEmpty == true) ...[
            _PostgresqlFormSection(
              title: label,
              icon: _groupIcon(label),
              children: groups[label]!,
              fieldBuilder: _buildField,
            ),
            kOpenHandGap12,
          ],
      ],
    );
  }

  Widget _buildField(BuildContext context, _PostgresqlColumnSpec column) {
    final colors = Theme.of(context).colorScheme;
    final readOnly = column.primaryKey && _editing;
    final content = column.isJson
        ? _buildJsonField(context, column, readOnly)
        : column.isBoolean
        ? _buildBooleanField(context, column, readOnly)
        : column.selectOptions.isNotEmpty
        ? _buildSelectField(context, column, readOnly)
        : _buildTextField(context, column, readOnly);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: content),
    );
  }

  Widget _buildFieldTitle(
    BuildContext context,
    _PostgresqlColumnSpec column, {
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _columnLabel(column.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                column.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        if (column.primaryKey)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(Icons.key_rounded, size: 15, color: colors.primary),
          ),
        if (trailing != null) ...[kOpenHandHGap8, trailing],
      ],
    );
  }

  Widget _buildTextField(
    BuildContext context,
    _PostgresqlColumnSpec column,
    bool readOnly,
  ) {
    final controller = _textControllers[column.name]!;
    final longText = column.isLongText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldTitle(
          context,
          column,
          trailing: _TypeBadge(label: column.dataType),
        ),
        kOpenHandGap8,
        TextField(
          controller: controller,
          readOnly: readOnly,
          minLines: longText ? 2 : 1,
          maxLines: longText ? 4 : 1,
          keyboardType: column.isNumber
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : TextInputType.text,
          onChanged: (_) => _clearFieldError(column.name),
          decoration: InputDecoration(
            hintText: readOnly ? '编辑时不可修改' : '请输入${_columnLabel(column.name)}',
            helperText: _helperText(column),
            errorText: _fieldErrors[column.name],
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectField(
    BuildContext context,
    _PostgresqlColumnSpec column,
    bool readOnly,
  ) {
    final options = <String>[...column.selectOptions];
    final current = _selectValues[column.name];
    if (current != null && !options.contains(current)) options.add(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldTitle(
          context,
          column,
          trailing: _TypeBadge(label: column.dataType),
        ),
        kOpenHandGap8,
        AnimatedDropdownButtonFormField<String>(
          initialValue: _selectValues[column.name],
          isExpanded: true,
          decoration: InputDecoration(
            hintText: '请选择${_columnLabel(column.name)}',
            helperText: _helperText(column),
            errorText: _fieldErrors[column.name],
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final option in options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: readOnly
              ? null
              : (value) {
                  setState(() => _selectValues[column.name] = value);
                  _clearFieldError(column.name);
                },
        ),
      ],
    );
  }

  Widget _buildBooleanField(
    BuildContext context,
    _PostgresqlColumnSpec column,
    bool readOnly,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldTitle(
          context,
          column,
          trailing: _TypeBadge(label: column.dataType),
        ),
        kOpenHandGap8,
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(kOpenHandRadius10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SegmentedButton<_PostgresqlBooleanValue>(
              segments: const [
                ButtonSegment(
                  value: _PostgresqlBooleanValue.unset,
                  label: Text('未设置'),
                ),
                ButtonSegment(
                  value: _PostgresqlBooleanValue.yes,
                  label: Text('是'),
                ),
                ButtonSegment(
                  value: _PostgresqlBooleanValue.no,
                  label: Text('否'),
                ),
              ],
              selected: {_booleanValues[column.name]!},
              onSelectionChanged: readOnly
                  ? null
                  : (selection) {
                      setState(
                        () => _booleanValues[column.name] = selection.first,
                      );
                      _clearFieldError(column.name);
                    },
            ),
          ),
        ),
        if (_helperText(column) != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              _helperText(column)!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _buildJsonField(
    BuildContext context,
    _PostgresqlColumnSpec column,
    bool readOnly,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final value = _jsonValues[column.name];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldTitle(
          context,
          column,
          trailing: _TypeBadge(label: column.dataType),
        ),
        kOpenHandGap8,
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.24),
            borderRadius: BorderRadius.circular(kOpenHandRadius10),
            border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
            child: Row(
              children: [
                Icon(
                  Icons.data_object_rounded,
                  size: 20,
                  color: colors.primary,
                ),
                kOpenHandHGap8,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _jsonSummary(value),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '使用结构化字段编辑器维护 JSONB 内容',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: readOnly ? null : () => _editJson(column.name),
                  icon: const Icon(Icons.tune_rounded, size: 17),
                  label: Text(readOnly ? '只读' : '编辑结构'),
                ),
              ],
            ),
          ),
        ),
        if (_fieldErrors[column.name] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              _fieldErrors[column.name]!,
              style: TextStyle(color: colors.error),
            ),
          ),
      ],
    );
  }

  Future<void> _editJson(String name) async {
    final result = await _showPostgresqlJsonEditor(
      context,
      initial: _jsonValues[name],
    );
    if (result == null || !mounted) return;
    setState(() => _jsonValues[name] = _copyJsonValue(result.value));
    _clearFieldError(name);
  }

  void _clearFieldError(String name) {
    if (_fieldErrors.containsKey(name) || _error != null) {
      setState(() {
        _fieldErrors.remove(name);
        _error = null;
      });
    }
  }

  void _submit() {
    final errors = <String, String>{};
    final values = <String, Object?>{};
    for (final column in _columns) {
      final name = column.name;
      if (column.isJson) {
        final value = _jsonValues[name];
        if (value == null) {
          if (column.nullable) {
            values[name] = null;
          } else if (!(_editing == false && column.hasDefault)) {
            errors[name] = '该字段不能为空';
          }
        } else {
          values[name] = _copyJsonValue(value);
        }
        continue;
      }
      if (column.isBoolean) {
        switch (_booleanValues[name]) {
          case _PostgresqlBooleanValue.yes:
            values[name] = true;
          case _PostgresqlBooleanValue.no:
            values[name] = false;
          case _PostgresqlBooleanValue.unset:
          case null:
            if (column.nullable) {
              values[name] = null;
            } else if (!(_editing == false && column.hasDefault)) {
              errors[name] = '请选择是或否';
            }
        }
        continue;
      }
      final text = column.selectOptions.isNotEmpty
          ? (_selectValues[name] ?? '').trim()
          : _textControllers[name]!.text.trim();
      if (text.isEmpty) {
        if (column.nullable) {
          values[name] = null;
        } else if (!(_editing == false && column.hasDefault)) {
          errors[name] = '该字段不能为空';
        }
        continue;
      }
      if (column.isNumber) {
        final parsed = _parseNumber(text, column.dataType);
        if (parsed == null) {
          errors[name] = '请输入有效的${column.isInteger ? '整数' : '数字'}';
          continue;
        }
        values[name] = parsed;
      } else {
        values[name] = text;
      }
    }
    if (errors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(errors);
        _error = '请完善标记字段后再保存';
      });
      return;
    }
    Navigator.of(context).pop(values);
  }

  String? _helperText(_PostgresqlColumnSpec column) {
    if (column.primaryKey && _editing) return '主键用于定位记录，编辑时不可修改';
    if (column.hasDefault && !_editing) return '留空将使用数据库默认值';
    if (column.nullable) return '可留空，保存后写入 NULL';
    if (column.isDateTime) return '建议使用 ISO 8601 格式，例如 2026-08-09T12:30:00Z';
    return null;
  }
}

class _PostgresqlFormSection extends StatelessWidget {
  const _PostgresqlFormSection({
    required this.title,
    required this.icon,
    required this.children,
    required this.fieldBuilder,
  });

  final String title;
  final IconData icon;
  final List<_PostgresqlColumnSpec> children;
  final Widget Function(BuildContext, _PostgresqlColumnSpec) fieldBuilder;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(kOpenHandRadius14),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: Theme.of(context).colorScheme.primary,
              ),
              kOpenHandHGap8,
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              kOpenHandHGap8,
              Text(
                '${children.length} 项',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          kOpenHandGap10,
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 2 : 1;
              const gap = 10.0;
              final width = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - gap) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final child in children)
                    SizedBox(width: width, child: fieldBuilder(context, child)),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: kOpenHandPillBorderRadius,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    ),
  );
}

class _PostgresqlColumnSpec {
  const _PostgresqlColumnSpec({
    required this.name,
    required this.dataType,
    required this.nullable,
    required this.primaryKey,
    this.defaultValue,
  });

  final String name;
  final String dataType;
  final bool nullable;
  final bool primaryKey;
  final Object? defaultValue;

  bool get isJson => dataType.toLowerCase().contains('json');
  bool get isBoolean {
    final type = dataType.toLowerCase();
    return type == 'boolean' || type == 'bool';
  }

  bool get isDateTime {
    final type = dataType.toLowerCase();
    return type.contains('timestamp') ||
        type == 'date' ||
        type.contains('time');
  }

  bool get isInteger {
    final type = dataType.toLowerCase();
    // 排除 interval（含 "int" 子串但不是整数类型）。
    return (type.contains('int') && type != 'interval') ||
        type.contains('serial');
  }

  bool get isNumber {
    final type = dataType.toLowerCase();
    return isInteger ||
        type.contains('numeric') ||
        type.contains('decimal') ||
        type.contains('real') ||
        type.contains('double') ||
        type == 'money';
  }

  bool get isLongText {
    final nameLower = name.toLowerCase();
    return nameLower.contains('message') ||
        nameLower.contains('summary') ||
        nameLower.contains('description') ||
        nameLower.contains('trace');
  }

  bool get hasDefault => defaultValue != null;

  List<String> get selectOptions {
    final options = _kPostgresqlSelectOptions[name];
    if (options == null) return const <String>[];
    return List<String>.unmodifiable(options);
  }
}

enum _PostgresqlBooleanValue { unset, yes, no }

String _columnLabel(String name) => _kPostgresqlColumnLabels[name] ?? name;

String _groupLabel(_PostgresqlColumnSpec column) {
  if (column.isJson) return '结构化内容';
  if (column.isDateTime) return '时间信息';
  if (column.primaryKey ||
      const <String>{
        'name',
        'job_id',
        'url',
        'source',
        'host',
        'product',
      }.contains(column.name)) {
    return '基础信息';
  }
  if (const <String>{
    'stage',
    'level',
    'category',
    'credential_state',
    'error_message',
  }.contains(column.name)) {
    return '状态与结果';
  }
  return '其他字段';
}

IconData _groupIcon(String label) => switch (label) {
  '基础信息' => Icons.badge_outlined,
  '状态与结果' => Icons.flag_outlined,
  '结构化内容' => Icons.account_tree_outlined,
  '时间信息' => Icons.schedule_outlined,
  _ => Icons.tune_rounded,
};

String _scalarText(Object? value) => value == null ? '' : '$value';

Object? _parseNumber(String value, String dataType) {
  final type = dataType.toLowerCase();
  if (type.contains('int') || type.contains('serial')) {
    return int.tryParse(value);
  }
  final parsed = double.tryParse(value);
  return parsed == null || !parsed.isFinite ? null : parsed;
}

Object? _copyJsonValue(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        '${entry.key}': _copyJsonValue(entry.value),
    };
  }
  if (value is List) return [for (final item in value) _copyJsonValue(item)];
  return value;
}

String _jsonSummary(Object? value) {
  if (value is Map) return '对象 · ${value.length} 个字段';
  if (value is List) return '数组 · ${value.length} 个元素';
  if (value == null) return '未设置';
  if (value is bool) return value ? '布尔值 · 是' : '布尔值 · 否';
  if (value is num) return '数字 · $value';
  return '文本值 · ${'$value'.length} 个字符';
}

class _PostgresqlJsonFieldResult {
  const _PostgresqlJsonFieldResult(this.value);

  final Object? value;
}

Future<_PostgresqlJsonFieldResult?> _showPostgresqlJsonEditor(
  BuildContext context, {
  required Object? initial,
  int depth = 0,
}) => showAnimatedDialog<_PostgresqlJsonFieldResult>(
  context: context,
  builder: (_) => buildOpenHandDialog(
    maxWidth: kOpenHandDialogWidthWide,
    maxHeight: kOpenHandDialogHeightTall,
    child: ServiceDialogInteractionTheme(
      child: _PostgresqlJsonEditor(initial: initial, depth: depth),
    ),
  ),
);

class _PostgresqlJsonEditor extends StatefulWidget {
  const _PostgresqlJsonEditor({required this.initial, required this.depth});

  final Object? initial;
  final int depth;

  @override
  State<_PostgresqlJsonEditor> createState() => _PostgresqlJsonEditorState();
}

class _PostgresqlJsonEditorState extends State<_PostgresqlJsonEditor> {
  late _PostgresqlJsonRootMode _mode;
  final List<_PostgresqlJsonDraft> _drafts = <_PostgresqlJsonDraft>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize(widget.initial);
  }

  void _initialize(Object? value) {
    _disposeDrafts();
    if (value is Map) {
      _mode = _PostgresqlJsonRootMode.object;
      for (final entry in value.entries) {
        _drafts.add(
          _PostgresqlJsonDraft.fromValue('${entry.key}', entry.value),
        );
      }
    } else if (value is List) {
      _mode = _PostgresqlJsonRootMode.array;
      for (final item in value) {
        _drafts.add(_PostgresqlJsonDraft.fromValue('', item));
      }
    } else {
      _mode = _PostgresqlJsonRootMode.value;
      _drafts.add(_PostgresqlJsonDraft.fromValue('', value));
    }
  }

  @override
  void dispose() {
    _disposeDrafts();
    super.dispose();
  }

  void _disposeDrafts() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    _drafts.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = widget.depth == 0 ? '编辑 JSONB 结构' : '编辑嵌套 JSON';
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(kOpenHandRadius12),
                ),
                child: Icon(Icons.data_object_rounded, color: colors.primary),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ServiceDialogHeaderIconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          kOpenHandGap14,
          SegmentedButton<_PostgresqlJsonRootMode>(
            segments: const [
              ButtonSegment(
                value: _PostgresqlJsonRootMode.object,
                icon: Icon(Icons.data_object_rounded),
                label: Text('对象'),
              ),
              ButtonSegment(
                value: _PostgresqlJsonRootMode.array,
                icon: Icon(Icons.data_array_rounded),
                label: Text('数组'),
              ),
              ButtonSegment(
                value: _PostgresqlJsonRootMode.value,
                icon: Icon(Icons.text_fields_rounded),
                label: Text('单值'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) => _changeMode(selection.first),
          ),
          kOpenHandGap12,
          Expanded(child: _buildDraftList(context)),
          OpenHandVerticalRevealSwitcher(
            presentKey: ValueKey<String>('postgres-json-error-$_error'),
            child: _error == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
          ),
          kOpenHandGap14,
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              OpenHandDialogActionButton.secondary(
                onPressed: () => Navigator.of(context).maybePop(),
                label: '取消',
              ),
              OpenHandDialogActionButton.primary(
                onPressed: _submit,
                label: '应用结构',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDraftList(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isValue = _mode == _PostgresqlJsonRootMode.value;
    final title = switch (_mode) {
      _PostgresqlJsonRootMode.object => '对象字段',
      _PostgresqlJsonRootMode.array => '数组元素',
      _PostgresqlJsonRootMode.value => 'JSON 单值',
    };
    final list = ListView.separated(
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      physics: openHandDialogAwareScrollPhysics(context),
      itemCount: _drafts.length,
      itemBuilder: (context, index) => _buildDraftRow(
        context,
        _drafts[index],
        index,
        showKey: _mode == _PostgresqlJsonRootMode.object,
      ),
      separatorBuilder: (_, _) => kOpenHandGap8,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.account_tree_outlined, size: 18, color: colors.primary),
            kOpenHandHGap8,
            Expanded(
              child: Text(
                '$title · ${_drafts.length} 项',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (!isValue)
              IconButton(
                tooltip: _drafts.length >= _kPostgresqlJsonMaxEntries
                    ? '已达到字段数量上限'
                    : '添加${_mode == _PostgresqlJsonRootMode.object ? '字段' : '元素'}',
                onPressed: _drafts.length >= _kPostgresqlJsonMaxEntries
                    ? null
                    : _addDraft,
                icon: const Icon(Icons.add_rounded),
              ),
          ],
        ),
        kOpenHandGap8,
        Expanded(
          child: _drafts.isEmpty
              ? Center(
                  child: Text(
                    '暂无内容，点击右上角添加${_mode == _PostgresqlJsonRootMode.object ? '字段' : '元素'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : list,
        ),
      ],
    );
  }

  Widget _buildDraftRow(
    BuildContext context,
    _PostgresqlJsonDraft draft,
    int index, {
    required bool showKey,
  }) {
    final colors = Theme.of(context).colorScheme;
    final typeField = AnimatedDropdownButtonFormField<_PostgresqlJsonValueType>(
      initialValue: draft.type,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '类型',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final type in _PostgresqlJsonValueType.values)
          DropdownMenuItem(value: type, child: Text(_jsonTypeLabel(type))),
      ],
      onChanged: (type) {
        if (type == null) return;
        setState(() {
          draft.changeType(type);
          _error = null;
        });
      },
    );
    final valueField = _buildJsonValueField(context, draft, index);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final controls = constraints.maxWidth < 560
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [typeField, kOpenHandGap8, valueField],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 132, child: typeField),
                      kOpenHandHGap8,
                      Expanded(child: valueField),
                    ],
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showKey) ...[
                  TextField(
                    controller: draft.key,
                    onChanged: (_) => setState(() => _error = null),
                    decoration: const InputDecoration(
                      labelText: '字段名',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  kOpenHandGap8,
                ],
                controls,
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    tooltip: '移除${showKey ? '字段' : '元素'}',
                    onPressed: () => setState(() {
                      _drafts.removeAt(index).dispose();
                      _error = null;
                    }),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: colors.error,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildJsonValueField(
    BuildContext context,
    _PostgresqlJsonDraft draft,
    int index,
  ) {
    final colors = Theme.of(context).colorScheme;
    switch (draft.type) {
      case _PostgresqlJsonValueType.boolean:
        return AnimatedDropdownButtonFormField<bool>(
          initialValue: draft.booleanValue,
          decoration: const InputDecoration(
            labelText: '布尔值',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: true, child: Text('是 · true')),
            DropdownMenuItem(value: false, child: Text('否 · false')),
          ],
          onChanged: (value) => setState(() {
            draft.booleanValue = value == true;
            _error = null;
          }),
        );
      case _PostgresqlJsonValueType.nullValue:
        return InputDecorator(
          decoration: const InputDecoration(
            labelText: '值',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          child: Text(
            '保存为 null',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        );
      case _PostgresqlJsonValueType.object:
      case _PostgresqlJsonValueType.array:
        final canEdit = widget.depth < _kPostgresqlJsonMaxDepth;
        return OutlinedButton.icon(
          onPressed: canEdit ? () => _editNested(draft) : null,
          icon: Icon(
            draft.type == _PostgresqlJsonValueType.object
                ? Icons.data_object_rounded
                : Icons.data_array_rounded,
          ),
          label: Text(
            canEdit
                ? '${_jsonSummary(draft.complexValue)} · 编辑结构'
                : '嵌套层级已达到上限',
            overflow: TextOverflow.ellipsis,
          ),
        );
      case _PostgresqlJsonValueType.text:
      case _PostgresqlJsonValueType.number:
        return TextField(
          controller: draft.value,
          keyboardType: draft.type == _PostgresqlJsonValueType.number
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : TextInputType.text,
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(
            labelText: draft.type == _PostgresqlJsonValueType.number
                ? '数字'
                : '文本',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        );
    }
  }

  Future<void> _editNested(_PostgresqlJsonDraft draft) async {
    final result = await _showPostgresqlJsonEditor(
      context,
      initial: draft.complexValue,
      depth: widget.depth + 1,
    );
    if (result == null || !mounted) return;
    setState(() {
      draft.complexValue = _copyJsonValue(result.value);
      _error = null;
    });
  }

  void _addDraft() {
    if (_drafts.length >= _kPostgresqlJsonMaxEntries) return;
    setState(() {
      _drafts.add(_PostgresqlJsonDraft.empty());
      _error = null;
    });
  }

  void _changeMode(_PostgresqlJsonRootMode mode) {
    if (mode == _mode) return;
    final current = _tryBuildValue();
    setState(() {
      _disposeDrafts();
      _mode = mode;
      if (mode == _PostgresqlJsonRootMode.value) {
        _drafts.add(_PostgresqlJsonDraft.fromValue('', current));
      } else if (mode == _PostgresqlJsonRootMode.object) {
        // 从 Map 或 List 转换为对象模式：Map 直接展开，List 转为索引键。
        if (current is Map) {
          for (final entry in current.entries) {
            _drafts.add(
              _PostgresqlJsonDraft.fromValue('${entry.key}', entry.value),
            );
          }
        } else if (current is List) {
          for (var index = 0; index < current.length; index++) {
            _drafts.add(
              _PostgresqlJsonDraft.fromValue('$index', current[index]),
            );
          }
        }
      } else if (mode == _PostgresqlJsonRootMode.array) {
        // 从 Map 或 List 转换为数组模式：List 直接展开，Map 取值列表。
        if (current is List) {
          for (final item in current) {
            _drafts.add(_PostgresqlJsonDraft.fromValue('', item));
          }
        } else if (current is Map) {
          for (final entry in current.entries) {
            _drafts.add(_PostgresqlJsonDraft.fromValue('', entry.value));
          }
        }
      }
      _error = null;
    });
  }

  Object? _tryBuildValue() {
    try {
      return _buildValue();
    } on FormatException {
      return null;
    }
  }

  Object? _buildValue() {
    if (_mode == _PostgresqlJsonRootMode.value) {
      return _drafts.isEmpty ? null : _draftValue(_drafts.first, 1);
    }
    if (_mode == _PostgresqlJsonRootMode.array) {
      return [
        for (var index = 0; index < _drafts.length; index++)
          _draftValue(_drafts[index], index + 1),
      ];
    }
    final result = <String, Object?>{};
    for (var index = 0; index < _drafts.length; index++) {
      final draft = _drafts[index];
      final key = draft.key.text.trim();
      if (key.isEmpty) throw FormatException('第 ${index + 1} 个字段名不能为空');
      if (result.containsKey(key)) throw FormatException('字段“$key”重复');
      result[key] = _draftValue(draft, index + 1);
    }
    return result;
  }

  Object? _draftValue(_PostgresqlJsonDraft draft, int index) {
    final text = draft.value.text.trim();
    return switch (draft.type) {
      _PostgresqlJsonValueType.text => draft.value.text,
      _PostgresqlJsonValueType.number => _parseJsonNumber(text, index),
      _PostgresqlJsonValueType.boolean => draft.booleanValue,
      _PostgresqlJsonValueType.nullValue => null,
      _PostgresqlJsonValueType.object ||
      _PostgresqlJsonValueType.array => _copyJsonValue(draft.complexValue),
    };
  }

  void _submit() {
    try {
      final value = _buildValue();
      Navigator.of(context).pop(_PostgresqlJsonFieldResult(value));
    } on FormatException catch (error) {
      setState(
        () => _error = error.message.isEmpty ? 'JSON 结构无效' : error.message,
      );
    }
  }
}

enum _PostgresqlJsonRootMode { object, array, value }

enum _PostgresqlJsonValueType {
  text,
  number,
  boolean,
  nullValue,
  object,
  array,
}

class _PostgresqlJsonDraft {
  _PostgresqlJsonDraft({
    required String key,
    required String value,
    required this.type,
    this.booleanValue = false,
    this.complexValue,
  }) : key = TextEditingController(text: key),
       value = TextEditingController(text: value);

  factory _PostgresqlJsonDraft.empty() => _PostgresqlJsonDraft(
    key: '',
    value: '',
    type: _PostgresqlJsonValueType.text,
  );

  factory _PostgresqlJsonDraft.fromValue(String key, Object? value) {
    if (value is Map) {
      return _PostgresqlJsonDraft(
        key: key,
        value: '',
        type: _PostgresqlJsonValueType.object,
        complexValue: _copyJsonValue(value),
      );
    }
    if (value is List) {
      return _PostgresqlJsonDraft(
        key: key,
        value: '',
        type: _PostgresqlJsonValueType.array,
        complexValue: _copyJsonValue(value),
      );
    }
    if (value == null) {
      return _PostgresqlJsonDraft(
        key: key,
        value: '',
        type: _PostgresqlJsonValueType.nullValue,
      );
    }
    if (value is bool) {
      return _PostgresqlJsonDraft(
        key: key,
        value: '',
        type: _PostgresqlJsonValueType.boolean,
        booleanValue: value,
      );
    }
    if (value is num) {
      return _PostgresqlJsonDraft(
        key: key,
        value: '$value',
        type: _PostgresqlJsonValueType.number,
      );
    }
    return _PostgresqlJsonDraft(
      key: key,
      value: '$value',
      type: _PostgresqlJsonValueType.text,
    );
  }

  final TextEditingController key;
  final TextEditingController value;
  _PostgresqlJsonValueType type;
  bool booleanValue;
  Object? complexValue;

  void changeType(_PostgresqlJsonValueType next) {
    type = next;
    if (next == _PostgresqlJsonValueType.object) {
      complexValue = <String, Object?>{};
    }
    if (next == _PostgresqlJsonValueType.array) complexValue = <Object?>[];
    if (next == _PostgresqlJsonValueType.boolean) booleanValue = false;
    if (next == _PostgresqlJsonValueType.nullValue) value.clear();
  }

  void dispose() {
    key.dispose();
    value.dispose();
  }
}

String _jsonTypeLabel(_PostgresqlJsonValueType type) => switch (type) {
  _PostgresqlJsonValueType.text => '文本',
  _PostgresqlJsonValueType.number => '数字',
  _PostgresqlJsonValueType.boolean => '布尔',
  _PostgresqlJsonValueType.nullValue => '空值',
  _PostgresqlJsonValueType.object => '对象',
  _PostgresqlJsonValueType.array => '数组',
};

Object _parseJsonNumber(String value, int index) {
  final parsed = num.tryParse(value);
  if (parsed == null || !parsed.isFinite) {
    throw FormatException('第 $index 个值必须是有限数字');
  }
  return parsed;
}
