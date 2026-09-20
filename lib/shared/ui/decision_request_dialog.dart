import 'dart:convert';

import 'package:flutter/material.dart';

import '../util/decision_payload.dart';
import 'animated_dialog.dart';
import 'openhand_dialog_action_button.dart';

Future<String?> showDecisionRequestDialog(
  BuildContext context,
  String initialText,
) => showAnimatedDialog<String>(
  context: context,
  builder: (_) => _DecisionRequestDialog(initialText: initialText),
);

class _DecisionRequestDialog extends StatefulWidget {
  const _DecisionRequestDialog({required this.initialText});
  final String initialText;
  @override
  State<_DecisionRequestDialog> createState() => _DecisionRequestDialogState();
}

class _DecisionRequestDialogState extends State<_DecisionRequestDialog> {
  late final TextEditingController _state;
  final _question = TextEditingController(
    text: DecisionPayload.defaultQuestion,
  );
  final _criteria = TextEditingController();
  String _type = 'noul';
  bool _advanced = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _state = TextEditingController(text: widget.initialText);
    if (widget.initialText.contains(DecisionPayload.requestLanguage) ||
        widget.initialText.trimLeft().startsWith('{')) {
      try {
        final request = DecisionPayload.request(widget.initialText);
        final questions = request['questions'] as Map;
        final question = questions.length == 1 ? questions['决策'] : null;
        final criteria = question is Map ? question['criteria'] : null;
        final simpleCriteria =
            criteria == null ||
            (question is Map &&
                question['type'] == 'choice' &&
                criteria is Map &&
                criteria.values.every((value) => value == null)) ||
            (question is Map &&
                question['type'] == 'score' &&
                criteria is List &&
                criteria.every((value) => value is String));
        if (question is Map &&
            request['state'] is String &&
            question['instructions'] is String &&
            simpleCriteria) {
          _state.text = request['state'] as String;
          _type = question['type'] as String;
          _question.text = question['instructions'] as String;
          _criteria.text = criteria is Map
              ? criteria.keys.join('\n')
              : criteria is List
              ? criteria.join('\n')
              : '';
        } else {
          _advanced = true;
          _state.text = const JsonEncoder.withIndent('  ').convert(request);
        }
      } on FormatException {
        _advanced = true;
        _error = '现有决策草稿格式不完整，请修正配置。';
      }
    }
  }

  @override
  void dispose() {
    _state.dispose();
    _question.dispose();
    _criteria.dispose();
    super.dispose();
  }

  void _apply() {
    if (_advanced) {
      try {
        final request = DecisionPayload.request(_state.text);
        Navigator.of(
          context,
        ).pop(DecisionPayload.encode(DecisionPayload.requestLanguage, request));
      } on FormatException catch (error) {
        setState(() => _error = error.message);
      }
      return;
    }
    final options = _criteria.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (_type == 'choice' && options.toSet().length != options.length) {
      setState(() => _error = '候选项不能重复。');
      return;
    }
    final payload = {
      'state': _state.text.trim(),
      'questions': {
        '决策': {
          'type': _type,
          'instructions': _question.text.trim(),
          if (_type == 'choice')
            'criteria': {for (final option in options) option: null},
          if (_type == 'score') 'criteria': options,
        },
      },
    };
    final encoded = DecisionPayload.encode(
      DecisionPayload.requestLanguage,
      payload,
    );
    try {
      DecisionPayload.request(encoded);
      Navigator.of(context).pop(encoded);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return buildOpenHandAlertDialog(
      icon: Icon(Icons.account_tree_rounded, color: colors.primary),
      title: const Text('配置结构化决策'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '先提供待评估内容，再定义要选择、评分或判断的问题。配置会写入草稿，点击发送后才调用模型。',
                ),
              ),
              const SizedBox(height: 16),
              if (!_advanced) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const {
                      'noul': '判断',
                      'choice': '选择',
                      'score': '评分',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _type == entry.key,
                        onSelected: (_) => setState(() => _type = entry.key),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _state,
                minLines: 3,
                maxLines: _advanced ? 16 : 7,
                maxLength: DecisionPayload.maxCharacters,
                decoration: InputDecoration(
                  labelText: _advanced ? '完整决策配置（JSON）' : '待评估内容',
                  alignLabelWithHint: true,
                ),
              ),
              if (!_advanced) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _question,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '需要模型回答的问题'),
                ),
                if (_type != 'noul') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _criteria,
                    minLines: 3,
                    maxLines: 7,
                    decoration: InputDecoration(
                      labelText: _type == 'choice'
                          ? '候选项，每行一个'
                          : '评分等级，从低到高每行一个（2—10 级）',
                    ),
                  ),
                ],
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: colors.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(),
        ),
        OpenHandDialogActionButton.primary(label: '应用到草稿', onPressed: _apply),
      ],
    );
  }
}
