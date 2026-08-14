import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_spacing.dart';
import 'service_dialog_controls.dart';

const List<String> _kRedisTypes = <String>[
  'string',
  'json',
  'hash',
  'list',
  'set',
  'zset',
];
const Map<String, String> _kRedisTypeLabels = <String, String>{
  'string': '字符串',
  'json': 'JSON',
  'hash': '哈希',
  'list': '列表',
  'set': '集合',
  'zset': '有序集合',
};
const String _kRedisWritableKeyPrefix = 'openhand:custom:';
const int _kRedisMaxKeyChars = 512;
const int _kRedisMaxCollectionItems = 200;
const double _kRedisMetadataCompactBreakpoint = 420;
const double _kRedisRowCompactBreakpoint = 430;

enum _RedisJsonRootMode { object, array, raw }

enum _RedisJsonValueType { text, number, boolean, nullValue, json }

class RedisRecordEditorResult {
  const RedisRecordEditorResult({
    required this.key,
    required this.type,
    required this.value,
    required this.ttlSeconds,
  });

  final String key;
  final String type;
  final Object? value;
  final int ttlSeconds;
}

class RedisRecordEditor extends StatefulWidget {
  const RedisRecordEditor({super.key, this.record});

  final Map<String, Object?>? record;

  @override
  State<RedisRecordEditor> createState() => _RedisRecordEditorState();
}

class _RedisRecordEditorState extends State<RedisRecordEditor> {
  late final TextEditingController _key;
  late final TextEditingController _ttl;
  late final TextEditingController _stringValue;
  late final TextEditingController _jsonRaw;
  late String _type;
  _RedisJsonRootMode _jsonRootMode = _RedisJsonRootMode.object;
  final List<_RedisJsonValueDraft> _jsonObjectEntries = [];
  final List<_RedisJsonValueDraft> _jsonArrayEntries = [];
  final List<_RedisPairDraft> _hashEntries = [];
  final List<_RedisTextDraft> _listEntries = [];
  final List<_RedisTextDraft> _setEntries = [];
  final List<_RedisPairDraft> _zsetEntries = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final storedValue = widget.record?['value'];
    final storedType = '${widget.record?['type'] ?? 'string'}'.toLowerCase();
    _type = _kRedisTypes.contains(storedType) ? storedType : 'string';
    final initialValue = _type == 'json'
        ? _decodeJsonCollection(storedValue) ?? storedValue
        : storedValue;
    _key = TextEditingController(
      text: '${widget.record?['key'] ?? _kRedisWritableKeyPrefix}',
    );
    _ttl = TextEditingController(
      text: _initialTtl(widget.record?['ttlSeconds']),
    );
    _stringValue = TextEditingController(
      text: _type == 'string' ? '${initialValue ?? ''}' : '',
    );
    _jsonRaw = TextEditingController(text: _initialJsonText(initialValue));
    _initializeDrafts(_type, initialValue);
  }

  @override
  void dispose() {
    _key.dispose();
    _ttl.dispose();
    _stringValue.dispose();
    _jsonRaw.dispose();
    for (final draft in _jsonObjectEntries) {
      draft.dispose();
    }
    for (final draft in _jsonArrayEntries) {
      draft.dispose();
    }
    for (final draft in _hashEntries) {
      draft.dispose();
    }
    for (final draft in _listEntries) {
      draft.dispose();
    }
    for (final draft in _setEntries) {
      draft.dispose();
    }
    for (final draft in _zsetEntries) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.key_rounded),
            kOpenHandHGap10,
            Expanded(
              child: Text(
                widget.record == null ? '新增 Redis 键' : '编辑 Redis 键',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ServiceDialogHeaderIconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        kOpenHandGap16,
        TextField(
          controller: _key,
          readOnly: widget.record != null,
          maxLength: _kRedisMaxKeyChars,
          buildCounter: openHandHiddenTextFieldCounter,
          onChanged: (_) => _clearError(),
          decoration: const InputDecoration(
            labelText: '键',
            border: OutlineInputBorder(),
          ),
        ),
        kOpenHandGap12,
        LayoutBuilder(
          builder: (context, constraints) {
            final typeField = AnimatedDropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              menuMaxHeight: 360,
              decoration: const InputDecoration(
                labelText: '类型',
                border: OutlineInputBorder(),
              ),
              selectedItemBuilder: (context) => [
                for (final type in _kRedisTypes)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(_kRedisTypeLabels[type]!),
                  ),
              ],
              items: [
                for (final type in _kRedisTypes)
                  DropdownMenuItem<String>(
                    value: type,
                    child: Row(
                      children: [
                        Icon(_redisTypeIcon(type), size: 18),
                        kOpenHandHGap9,
                        Text(_kRedisTypeLabels[type]!),
                      ],
                    ),
                  ),
              ],
              onChanged: _changeType,
            );
            final ttlField = TextField(
              controller: _ttl,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              onChanged: (_) => _clearError(),
              decoration: const InputDecoration(
                labelText: 'TTL（秒）',
                border: OutlineInputBorder(),
              ),
            );
            if (constraints.maxWidth < _kRedisMetadataCompactBreakpoint) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [typeField, kOpenHandGap12, ttlField],
              );
            }
            return Row(
              children: [
                Expanded(child: typeField),
                kOpenHandHGap12,
                Expanded(child: ttlField),
              ],
            );
          },
        ),
        kOpenHandGap12,
        Expanded(
          child: OpenHandContentStateSwitcher(
            stateKey: _type,
            animateSize: false,
            child: _buildValueEditor(),
          ),
        ),
        OpenHandDialogErrorText(message: _error, topGap: 8),
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
            OpenHandDialogActionButton.primary(onPressed: _submit, label: '保存'),
          ],
        ),
      ],
    ),
  );

  Widget _buildValueEditor() => switch (_type) {
    'json' => _buildJsonEditor(),
    'hash' => _buildHashEditor(),
    'list' => _buildListEditor(),
    'set' => _buildSetEditor(),
    'zset' => _buildZSetEditor(),
    _ => TextField(
      key: const ValueKey<String>('redis-string-editor'),
      controller: _stringValue,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      onChanged: (_) => _clearError(),
      decoration: const InputDecoration(
        labelText: '字符串值',
        alignLabelWithHint: true,
        border: OutlineInputBorder(),
      ),
    ),
  };

  Widget _buildJsonEditor() => Column(
    key: const ValueKey<String>('redis-json-editor'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<_RedisJsonRootMode>(
        segments: const [
          ButtonSegment(
            value: _RedisJsonRootMode.object,
            icon: Icon(Icons.data_object_rounded),
            label: Text('对象'),
          ),
          ButtonSegment(
            value: _RedisJsonRootMode.array,
            icon: Icon(Icons.data_array_rounded),
            label: Text('数组'),
          ),
          ButtonSegment(
            value: _RedisJsonRootMode.raw,
            icon: Icon(Icons.code_rounded),
            label: Text('源码'),
          ),
        ],
        selected: {_jsonRootMode},
        onSelectionChanged: (selection) => _changeJsonMode(selection.first),
      ),
      kOpenHandGap10,
      Expanded(
        child: OpenHandContentStateSwitcher(
          stateKey: _jsonRootMode.name,
          animateSize: false,
          child: switch (_jsonRootMode) {
            _RedisJsonRootMode.object => _RedisStructuredPanel(
              key: const ValueKey<String>('redis-json-object'),
              icon: Icons.data_object_rounded,
              title: 'JSON 字段',
              count: _jsonObjectEntries.length,
              addTooltip: '添加 JSON 字段',
              onAdd: _jsonObjectEntries.length >= _kRedisMaxCollectionItems
                  ? null
                  : () => setState(() {
                      _jsonObjectEntries.add(_RedisJsonValueDraft.object());
                      _error = null;
                    }),
              emptyLabel: '暂无 JSON 字段',
              itemCount: _jsonObjectEntries.length,
              itemBuilder: (context, index) => _RedisJsonEntryRow(
                key: ObjectKey(_jsonObjectEntries[index]),
                index: index,
                draft: _jsonObjectEntries[index],
                showKey: true,
                onChanged: _clearError,
                onTypeChanged: (type) => setState(() {
                  _jsonObjectEntries[index].type = type;
                  _error = null;
                }),
                onBooleanChanged: (value) => setState(() {
                  _jsonObjectEntries[index].booleanValue = value;
                  _error = null;
                }),
                onRemove: () => _removeJsonEntry(_jsonObjectEntries, index),
              ),
            ),
            _RedisJsonRootMode.array => _RedisStructuredPanel(
              key: const ValueKey<String>('redis-json-array'),
              icon: Icons.data_array_rounded,
              title: 'JSON 元素',
              count: _jsonArrayEntries.length,
              addTooltip: '添加 JSON 元素',
              onAdd: _jsonArrayEntries.length >= _kRedisMaxCollectionItems
                  ? null
                  : () => setState(() {
                      _jsonArrayEntries.add(_RedisJsonValueDraft.array());
                      _error = null;
                    }),
              emptyLabel: '暂无 JSON 元素',
              itemCount: _jsonArrayEntries.length,
              itemBuilder: (context, index) => _RedisJsonEntryRow(
                key: ObjectKey(_jsonArrayEntries[index]),
                index: index,
                draft: _jsonArrayEntries[index],
                showKey: false,
                onChanged: _clearError,
                onTypeChanged: (type) => setState(() {
                  _jsonArrayEntries[index].type = type;
                  _error = null;
                }),
                onBooleanChanged: (value) => setState(() {
                  _jsonArrayEntries[index].booleanValue = value;
                  _error = null;
                }),
                onRemove: () => _removeJsonEntry(_jsonArrayEntries, index),
              ),
            ),
            _RedisJsonRootMode.raw => TextField(
              key: const ValueKey<String>('redis-json-raw'),
              controller: _jsonRaw,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace'),
              onChanged: (_) => _clearError(),
              decoration: const InputDecoration(
                labelText: '原始 JSON',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          },
        ),
      ),
    ],
  );

  Widget _buildHashEditor() => _RedisStructuredPanel(
    key: const ValueKey<String>('redis-hash-editor'),
    icon: Icons.grid_view_rounded,
    title: 'Hash 字段',
    count: _hashEntries.length,
    addTooltip: '添加 Hash 字段',
    onAdd: _hashEntries.length >= _kRedisMaxCollectionItems
        ? null
        : () => setState(() {
            _hashEntries.add(_RedisPairDraft());
            _error = null;
          }),
    emptyLabel: '暂无 Hash 字段',
    itemCount: _hashEntries.length,
    itemBuilder: (context, index) => _RedisPairEntryRow(
      key: ObjectKey(_hashEntries[index]),
      index: index,
      draft: _hashEntries[index],
      firstLabel: '字段',
      secondLabel: '值',
      onChanged: _clearError,
      onRemove: () => _removePairEntry(_hashEntries, index),
    ),
  );

  Widget _buildListEditor() => _RedisStructuredPanel(
    key: const ValueKey<String>('redis-list-editor'),
    icon: Icons.format_list_numbered_rounded,
    title: 'List 元素',
    count: _listEntries.length,
    addTooltip: '添加 List 元素',
    onAdd: _listEntries.length >= _kRedisMaxCollectionItems
        ? null
        : () => setState(() {
            _listEntries.add(_RedisTextDraft());
            _error = null;
          }),
    emptyLabel: '暂无 List 元素',
    itemCount: _listEntries.length,
    itemBuilder: (context, index) => _RedisTextEntryRow(
      key: ObjectKey(_listEntries[index]),
      label: '元素 ${index + 1}',
      controller: _listEntries[index].value,
      onChanged: _clearError,
      onMoveUp: index == 0 ? null : () => _moveListEntry(index, index - 1),
      onMoveDown: index == _listEntries.length - 1
          ? null
          : () => _moveListEntry(index, index + 1),
      onRemove: () => _removeTextEntry(_listEntries, index),
    ),
  );

  Widget _buildSetEditor() => _RedisStructuredPanel(
    key: const ValueKey<String>('redis-set-editor'),
    icon: Icons.hub_outlined,
    title: 'Set 成员',
    count: _setEntries.length,
    addTooltip: '添加 Set 成员',
    onAdd: _setEntries.length >= _kRedisMaxCollectionItems
        ? null
        : () => setState(() {
            _setEntries.add(_RedisTextDraft());
            _error = null;
          }),
    emptyLabel: '暂无 Set 成员',
    itemCount: _setEntries.length,
    itemBuilder: (context, index) => _RedisTextEntryRow(
      key: ObjectKey(_setEntries[index]),
      label: '成员 ${index + 1}',
      controller: _setEntries[index].value,
      onChanged: _clearError,
      onRemove: () => _removeTextEntry(_setEntries, index),
    ),
  );

  Widget _buildZSetEditor() => _RedisStructuredPanel(
    key: const ValueKey<String>('redis-zset-editor'),
    icon: Icons.leaderboard_outlined,
    title: 'ZSet 成员',
    count: _zsetEntries.length,
    addTooltip: '添加 ZSet 成员',
    onAdd: _zsetEntries.length >= _kRedisMaxCollectionItems
        ? null
        : () => setState(() {
            _zsetEntries.add(_RedisPairDraft(second: '0'));
            _error = null;
          }),
    emptyLabel: '暂无 ZSet 成员',
    itemCount: _zsetEntries.length,
    itemBuilder: (context, index) => _RedisPairEntryRow(
      key: ObjectKey(_zsetEntries[index]),
      index: index,
      draft: _zsetEntries[index],
      firstLabel: '成员',
      secondLabel: '分数',
      numericSecond: true,
      onChanged: _clearError,
      onRemove: () => _removePairEntry(_zsetEntries, index),
    ),
  );

  void _initializeDrafts(String type, Object? value) {
    switch (type) {
      case 'json':
        if (value is Map) {
          _jsonRootMode = _RedisJsonRootMode.object;
          for (final entry in value.entries) {
            _jsonObjectEntries.add(
              _RedisJsonValueDraft.fromValue('${entry.key}', entry.value),
            );
          }
        } else if (value is List) {
          _jsonRootMode = _RedisJsonRootMode.array;
          for (final item in value) {
            _jsonArrayEntries.add(_RedisJsonValueDraft.fromValue('', item));
          }
        } else {
          _jsonRootMode = _RedisJsonRootMode.raw;
        }
      case 'hash':
        if (value is Map) {
          for (final entry in value.entries) {
            _hashEntries.add(
              _RedisPairDraft(first: '${entry.key}', second: '${entry.value}'),
            );
          }
        }
      case 'list':
        if (value is List) {
          _listEntries.addAll(value.map((item) => _RedisTextDraft('$item')));
        }
      case 'set':
        if (value is List) {
          _setEntries.addAll(value.map((item) => _RedisTextDraft('$item')));
        }
      case 'zset':
        if (value is List) {
          for (var index = 0; index < value.length; index++) {
            final item = value[index];
            if (item is Map) {
              _zsetEntries.add(
                _RedisPairDraft(
                  first: '${item['member'] ?? ''}',
                  second: '${item['score'] ?? 0}',
                ),
              );
            } else if (index + 1 < value.length) {
              _zsetEntries.add(
                _RedisPairDraft(first: '$item', second: '${value[++index]}'),
              );
            }
          }
        }
    }
    _ensureTypeDraft(type);
  }

  void _changeType(String? type) {
    if (type == null || type == _type) return;
    _ensureTypeDraft(type);
    setState(() {
      _type = type;
      _error = null;
    });
  }

  void _changeJsonMode(_RedisJsonRootMode mode) {
    if (mode == _jsonRootMode) return;
    try {
      if (mode == _RedisJsonRootMode.raw) {
        _jsonRaw.text = const JsonEncoder.withIndent(
          '  ',
        ).convert(_buildJsonValue());
      } else if (_jsonRootMode == _RedisJsonRootMode.raw) {
        final value = jsonDecode(_jsonRaw.text);
        if (mode == _RedisJsonRootMode.object) {
          if (value is! Map) throw const FormatException('JSON 源码根节点必须是对象');
          for (final draft in _jsonObjectEntries) {
            draft.dispose();
          }
          _jsonObjectEntries
            ..clear()
            ..addAll(
              value.entries.map(
                (entry) =>
                    _RedisJsonValueDraft.fromValue('${entry.key}', entry.value),
              ),
            );
        } else {
          if (value is! List) throw const FormatException('JSON 源码根节点必须是数组');
          for (final draft in _jsonArrayEntries) {
            draft.dispose();
          }
          _jsonArrayEntries
            ..clear()
            ..addAll(
              value.map((item) => _RedisJsonValueDraft.fromValue('', item)),
            );
        }
      } else {
        _ensureJsonDraft(mode);
      }
      setState(() {
        _jsonRootMode = mode;
        _error = null;
      });
    } on FormatException catch (error) {
      setState(
        () => _error = error.message.isEmpty ? 'JSON 格式无效' : error.message,
      );
    }
  }

  void _ensureTypeDraft(String type) {
    switch (type) {
      case 'json':
        _ensureJsonDraft(_jsonRootMode);
      case 'hash':
        if (_hashEntries.isEmpty) _hashEntries.add(_RedisPairDraft());
      case 'list':
        if (_listEntries.isEmpty) _listEntries.add(_RedisTextDraft());
      case 'set':
        if (_setEntries.isEmpty) _setEntries.add(_RedisTextDraft());
      case 'zset':
        if (_zsetEntries.isEmpty) {
          _zsetEntries.add(_RedisPairDraft(second: '0'));
        }
    }
  }

  void _ensureJsonDraft(_RedisJsonRootMode mode) {
    if (mode == _RedisJsonRootMode.object && _jsonObjectEntries.isEmpty) {
      _jsonObjectEntries.add(_RedisJsonValueDraft.object());
    } else if (mode == _RedisJsonRootMode.array && _jsonArrayEntries.isEmpty) {
      _jsonArrayEntries.add(_RedisJsonValueDraft.array());
    }
  }

  void _removeJsonEntry(List<_RedisJsonValueDraft> entries, int index) {
    setState(() {
      entries.removeAt(index).dispose();
      _error = null;
    });
  }

  void _removePairEntry(List<_RedisPairDraft> entries, int index) {
    setState(() {
      entries.removeAt(index).dispose();
      _error = null;
    });
  }

  void _removeTextEntry(List<_RedisTextDraft> entries, int index) {
    setState(() {
      entries.removeAt(index).dispose();
      _error = null;
    });
  }

  void _moveListEntry(int from, int to) {
    setState(() {
      final entry = _listEntries.removeAt(from);
      _listEntries.insert(to, entry);
      _error = null;
    });
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  void _submit() {
    try {
      final key = _key.text.trim();
      final ttl = int.tryParse(_ttl.text.trim());
      if (!key.startsWith(_kRedisWritableKeyPrefix) ||
          key.length == _kRedisWritableKeyPrefix.length) {
        throw const FormatException('键必须以 openhand:custom: 开头');
      }
      if (key.length > _kRedisMaxKeyChars || RegExp(r'\s').hasMatch(key)) {
        throw const FormatException('键不能包含空白字符且长度不能超过 512');
      }
      if (ttl == null || (ttl != -1 && ttl <= 0)) {
        throw const FormatException('TTL 必须为正整数或 -1');
      }
      Navigator.of(context).pop(
        RedisRecordEditorResult(
          key: key,
          type: _type,
          value: _buildValue(),
          ttlSeconds: ttl,
        ),
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message.isEmpty ? '数据格式无效' : error.message);
    }
  }

  Object? _buildValue() => switch (_type) {
    'json' => _buildJsonValue(),
    'hash' => _buildHashValue(),
    'list' => _buildTextCollection(_listEntries, 'List 至少需要一个元素'),
    'set' => _buildSetValue(),
    'zset' => _buildZSetValue(),
    _ => _stringValue.text,
  };

  Object? _buildJsonValue() {
    switch (_jsonRootMode) {
      case _RedisJsonRootMode.raw:
        final value = jsonDecode(_jsonRaw.text);
        if (value is! Map && value is! List) {
          throw const FormatException('JSON 源码根节点必须是对象或数组');
        }
        return value;
      case _RedisJsonRootMode.array:
        return [
          for (var index = 0; index < _jsonArrayEntries.length; index++)
            _jsonEntryValue(_jsonArrayEntries[index], index),
        ];
      case _RedisJsonRootMode.object:
        final result = <String, Object?>{};
        for (var index = 0; index < _jsonObjectEntries.length; index++) {
          final draft = _jsonObjectEntries[index];
          final key = draft.key.text.trim();
          if (key.isEmpty) {
            throw FormatException('第 ${index + 1} 个 JSON 字段名不能为空');
          }
          if (result.containsKey(key)) throw FormatException('JSON 字段“$key”重复');
          result[key] = _jsonEntryValue(draft, index);
        }
        return result;
    }
  }

  Object? _jsonEntryValue(_RedisJsonValueDraft draft, int index) {
    final text = draft.value.text.trim();
    return switch (draft.type) {
      _RedisJsonValueType.text => draft.value.text,
      _RedisJsonValueType.number => _parseFiniteNumber(
        text,
        '第 ${index + 1} 个 JSON 值必须是有限数字',
      ),
      _RedisJsonValueType.boolean => draft.booleanValue,
      _RedisJsonValueType.nullValue => null,
      _RedisJsonValueType.json =>
        text.isEmpty
            ? throw FormatException('第 ${index + 1} 个嵌套 JSON 不能为空')
            : jsonDecode(text),
    };
  }

  Map<String, String> _buildHashValue() {
    if (_hashEntries.isEmpty) throw const FormatException('Hash 至少需要一个字段');
    final result = <String, String>{};
    for (var index = 0; index < _hashEntries.length; index++) {
      final draft = _hashEntries[index];
      final field = draft.first.text.trim();
      if (field.isEmpty) throw FormatException('第 ${index + 1} 个 Hash 字段名不能为空');
      if (result.containsKey(field)) throw FormatException('Hash 字段“$field”重复');
      result[field] = draft.second.text;
    }
    return result;
  }

  List<String> _buildTextCollection(
    List<_RedisTextDraft> entries,
    String emptyMessage,
  ) {
    if (entries.isEmpty) throw FormatException(emptyMessage);
    return [for (final entry in entries) entry.value.text];
  }

  List<String> _buildSetValue() {
    final values = _buildTextCollection(_setEntries, 'Set 至少需要一个成员');
    final uniqueValues = <String>{};
    for (var index = 0; index < values.length; index++) {
      if (values[index].isEmpty) {
        throw FormatException('第 ${index + 1} 个 Set 成员不能为空');
      }
      if (!uniqueValues.add(values[index])) {
        throw FormatException('Set 成员“${values[index]}”重复');
      }
    }
    return values;
  }

  List<Map<String, Object>> _buildZSetValue() {
    if (_zsetEntries.isEmpty) throw const FormatException('ZSet 至少需要一个成员');
    final members = <String>{};
    final values = <Map<String, Object>>[];
    for (var index = 0; index < _zsetEntries.length; index++) {
      final draft = _zsetEntries[index];
      final member = draft.first.text;
      if (member.isEmpty) {
        throw FormatException('第 ${index + 1} 个 ZSet 成员不能为空');
      }
      if (!members.add(member)) throw FormatException('ZSet 成员“$member”重复');
      values.add({
        'member': member,
        'score': _parseFiniteNumber(
          draft.second.text.trim(),
          'ZSet 成员“$member”的分数无效',
        ),
      });
    }
    return values;
  }
}

class _RedisStructuredPanel extends StatelessWidget {
  const _RedisStructuredPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.count,
    required this.addTooltip,
    required this.onAdd,
    required this.emptyLabel,
    required this.itemCount,
    required this.itemBuilder,
  });

  final IconData icon;
  final String title;
  final int count;
  final String addTooltip;
  final VoidCallback? onAdd;
  final String emptyLabel;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: colors.primary),
                kOpenHandHGap8,
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$count/$_kRedisMaxCollectionItems',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                kOpenHandHGap4,
                ServiceDialogCompactIconButton(
                  tooltip: addTooltip,
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 20),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: itemCount == 0
                ? Center(
                    child: Text(
                      emptyLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    physics: const ClampingScrollPhysics(),
                    itemCount: itemCount,
                    separatorBuilder: (_, _) => kOpenHandGap10,
                    itemBuilder: itemBuilder,
                  ),
          ),
        ],
      ),
    );
  }
}

class _RedisTextEntryRow extends StatelessWidget {
  const _RedisTextEntryRow({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      textInputAction: TextInputAction.next,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
    final actions = ServiceDialogIconActions(
      spacing: 2,
      children: [
        if (onMoveUp != null || onMoveDown != null) ...[
          ServiceDialogCompactIconButton(
            size: 36,
            tooltip: '上移',
            onPressed: onMoveUp,
            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
          ),
          ServiceDialogCompactIconButton(
            size: 36,
            tooltip: '下移',
            onPressed: onMoveDown,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          ),
        ],
        ServiceDialogCompactIconButton(
          size: 36,
          tooltip: '删除',
          onPressed: onRemove,
          foregroundColor: Theme.of(context).colorScheme.error,
          icon: const Icon(Icons.delete_outline_rounded, size: 19),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _kRedisRowCompactBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              kOpenHandGap4,
              Align(alignment: AlignmentDirectional.centerEnd, child: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: field),
            kOpenHandHGap6,
            actions,
          ],
        );
      },
    );
  }
}

class _RedisPairEntryRow extends StatelessWidget {
  const _RedisPairEntryRow({
    super.key,
    required this.index,
    required this.draft,
    required this.firstLabel,
    required this.secondLabel,
    required this.onChanged,
    required this.onRemove,
    this.numericSecond = false,
  });

  final int index;
  final _RedisPairDraft draft;
  final String firstLabel;
  final String secondLabel;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final bool numericSecond;

  @override
  Widget build(BuildContext context) {
    final first = TextField(
      controller: draft.first,
      textInputAction: TextInputAction.next,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: '$firstLabel ${index + 1}',
        border: const OutlineInputBorder(),
      ),
    );
    final second = TextField(
      controller: draft.second,
      keyboardType: numericSecond
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : null,
      textInputAction: TextInputAction.next,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: secondLabel,
        border: const OutlineInputBorder(),
      ),
    );
    final remove = ServiceDialogCompactIconButton(
      size: 36,
      tooltip: '删除',
      onPressed: onRemove,
      foregroundColor: Theme.of(context).colorScheme.error,
      icon: const Icon(Icons.delete_outline_rounded, size: 19),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _kRedisRowCompactBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              kOpenHandGap10,
              second,
              Align(alignment: AlignmentDirectional.centerEnd, child: remove),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: first),
            kOpenHandHGap10,
            Expanded(child: second),
            kOpenHandHGap4,
            remove,
          ],
        );
      },
    );
  }
}

class _RedisJsonEntryRow extends StatelessWidget {
  const _RedisJsonEntryRow({
    super.key,
    required this.index,
    required this.draft,
    required this.showKey,
    required this.onChanged,
    required this.onTypeChanged,
    required this.onBooleanChanged,
    required this.onRemove,
  });

  final int index;
  final _RedisJsonValueDraft draft;
  final bool showKey;
  final VoidCallback onChanged;
  final ValueChanged<_RedisJsonValueType> onTypeChanged;
  final ValueChanged<bool> onBooleanChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final keyField = TextField(
      controller: draft.key,
      textInputAction: TextInputAction.next,
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: '字段 ${index + 1}',
        border: const OutlineInputBorder(),
      ),
    );
    final typeField = AnimatedDropdownButtonFormField<_RedisJsonValueType>(
      initialValue: draft.type,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '值类型',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final type in _RedisJsonValueType.values)
          DropdownMenuItem(value: type, child: Text(_jsonValueTypeLabel(type))),
      ],
      onChanged: (type) {
        if (type != null) onTypeChanged(type);
      },
    );
    final valueField = switch (draft.type) {
      _RedisJsonValueType.boolean => SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('true')),
          ButtonSegment(value: false, label: Text('false')),
        ],
        selected: {draft.booleanValue},
        onSelectionChanged: (selection) => onBooleanChanged(selection.first),
      ),
      _RedisJsonValueType.nullValue => const InputDecorator(
        decoration: InputDecoration(
          labelText: '值',
          border: OutlineInputBorder(),
        ),
        child: Text('null'),
      ),
      _ => TextField(
        controller: draft.value,
        keyboardType: draft.type == _RedisJsonValueType.number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : null,
        textInputAction: TextInputAction.next,
        style: draft.type == _RedisJsonValueType.json
            ? const TextStyle(fontFamily: 'monospace')
            : null,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          labelText: draft.type == _RedisJsonValueType.json ? '嵌套 JSON' : '值',
          border: const OutlineInputBorder(),
        ),
      ),
    };
    final remove = ServiceDialogCompactIconButton(
      size: 36,
      tooltip: '删除',
      onPressed: onRemove,
      foregroundColor: Theme.of(context).colorScheme.error,
      icon: const Icon(Icons.delete_outline_rounded, size: 19),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _kRedisRowCompactBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showKey) ...[keyField, kOpenHandGap10],
              typeField,
              kOpenHandGap10,
              valueField,
              Align(alignment: AlignmentDirectional.centerEnd, child: remove),
            ],
          );
        }
        return Row(
          children: [
            if (showKey) ...[
              Expanded(flex: 4, child: keyField),
              kOpenHandHGap8,
            ],
            SizedBox(width: 118, child: typeField),
            kOpenHandHGap8,
            Expanded(flex: 5, child: valueField),
            kOpenHandHGap4,
            remove,
          ],
        );
      },
    );
  }
}

class _RedisTextDraft {
  _RedisTextDraft([String value = ''])
    : value = TextEditingController(text: value);

  final TextEditingController value;

  void dispose() => value.dispose();
}

class _RedisPairDraft {
  _RedisPairDraft({String first = '', String second = ''})
    : first = TextEditingController(text: first),
      second = TextEditingController(text: second);

  final TextEditingController first;
  final TextEditingController second;

  void dispose() {
    first.dispose();
    second.dispose();
  }
}

class _RedisJsonValueDraft {
  _RedisJsonValueDraft({
    required String key,
    required String value,
    required this.type,
    this.booleanValue = false,
  }) : key = TextEditingController(text: key),
       value = TextEditingController(text: value);

  factory _RedisJsonValueDraft.object() =>
      _RedisJsonValueDraft(key: '', value: '', type: _RedisJsonValueType.text);

  factory _RedisJsonValueDraft.array() =>
      _RedisJsonValueDraft(key: '', value: '', type: _RedisJsonValueType.text);

  factory _RedisJsonValueDraft.fromValue(String key, Object? value) {
    if (value == null) {
      return _RedisJsonValueDraft(
        key: key,
        value: '',
        type: _RedisJsonValueType.nullValue,
      );
    }
    if (value is bool) {
      return _RedisJsonValueDraft(
        key: key,
        value: '',
        type: _RedisJsonValueType.boolean,
        booleanValue: value,
      );
    }
    if (value is num) {
      return _RedisJsonValueDraft(
        key: key,
        value: '$value',
        type: _RedisJsonValueType.number,
      );
    }
    if (value is Map || value is List) {
      return _RedisJsonValueDraft(
        key: key,
        value: const JsonEncoder.withIndent('  ').convert(value),
        type: _RedisJsonValueType.json,
      );
    }
    return _RedisJsonValueDraft(
      key: key,
      value: '$value',
      type: _RedisJsonValueType.text,
    );
  }

  final TextEditingController key;
  final TextEditingController value;
  _RedisJsonValueType type;
  bool booleanValue;

  void dispose() {
    key.dispose();
    value.dispose();
  }
}

String _initialTtl(Object? value) {
  final ttl = switch (value) {
    int number => number,
    num number when number.isFinite => number.toInt(),
    String text => int.tryParse(text) ?? -1,
    _ => -1,
  };
  return ttl > 0 ? '$ttl' : '-1';
}

Object? _decodeJsonCollection(Object? value) {
  if (value is Map || value is List) return value;
  if (value is! String || value.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(value);
    return decoded is Map || decoded is List ? decoded : null;
  } on FormatException {
    return null;
  }
}

Object? _decodeJsonValue(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

String _initialJsonText(Object? value) {
  if (value == null) return '{}';
  if (value is String) {
    final decoded = _decodeJsonValue(value);
    return decoded == null
        ? value
        : const JsonEncoder.withIndent('  ').convert(decoded);
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}

num _parseFiniteNumber(String value, String errorMessage) {
  final number = num.tryParse(value);
  if (number == null || number is double && !number.isFinite) {
    throw FormatException(errorMessage);
  }
  return number;
}

IconData _redisTypeIcon(String type) => switch (type) {
  'json' => Icons.data_object_rounded,
  'hash' => Icons.grid_view_rounded,
  'list' => Icons.format_list_numbered_rounded,
  'set' => Icons.hub_outlined,
  'zset' => Icons.leaderboard_outlined,
  _ => Icons.text_fields_rounded,
};

String _jsonValueTypeLabel(_RedisJsonValueType type) => switch (type) {
  _RedisJsonValueType.text => '文本',
  _RedisJsonValueType.number => '数字',
  _RedisJsonValueType.boolean => '布尔',
  _RedisJsonValueType.nullValue => '空值',
  _RedisJsonValueType.json => 'JSON',
};
