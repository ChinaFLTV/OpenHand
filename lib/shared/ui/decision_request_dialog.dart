import 'dart:convert';

import 'package:flutter/material.dart';

import '../util/decision_payload.dart';
import '../util/localized_text.dart';
import 'animated_dialog.dart';
import 'decision_copy.dart';
import 'openhand_dialog_action_button.dart';
import 'openhand_spacing.dart';

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
  late final TextEditingController _question;
  final _criteriaByType = {
    DecisionPayload.typeNoul: TextEditingController(),
    DecisionPayload.typeChoice: TextEditingController(),
    DecisionPayload.typeScore: TextEditingController(),
  };
  String _type = DecisionPayload.typeNoul;
  TextEditingController get _criteria => _criteriaByType[_type]!;
  bool _advanced = false;
  bool _seededDefaultQuestion = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _state = TextEditingController(text: widget.initialText);
    _question = TextEditingController(
      text: DecisionPayload.defaultQuestionForType(_type),
    );
    if (widget.initialText.contains(DecisionPayload.requestLanguage) ||
        widget.initialText.trimLeft().startsWith('{')) {
      try {
        final request = DecisionPayload.request(widget.initialText);
        final questions = request['questions'] as Map;
        final question = questions.length == 1
            ? questions[DecisionPayload.simpleQuestionKey]
            : null;
        final criteria = question is Map ? question['criteria'] : null;
        final simpleCriteria =
            criteria == null ||
            (question is Map &&
                question['type'] == DecisionPayload.typeChoice &&
                criteria is Map &&
                criteria.values.every((value) => value == null)) ||
            (question is Map &&
                question['type'] == DecisionPayload.typeScore &&
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
        _error = 'draft';
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededDefaultQuestion || _advanced) return;
    _seededDefaultQuestion = true;
    final copy = DecisionCopy.of(context);
    if (_question.text.trim().isEmpty ||
        DecisionPayload.isBuiltInQuestion(_question.text)) {
      _question.text = copy.defaultQuestionFor(_type);
    }
  }

  @override
  void dispose() {
    _state.dispose();
    _question.dispose();
    for (final controller in _criteriaByType.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _apply() {
    final copy = DecisionCopy.of(context);
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
    if (_type == DecisionPayload.typeChoice &&
        options.toSet().length != options.length) {
      setState(() => _error = copy.duplicateOptions);
      return;
    }
    final payload = {
      'state': _state.text.trim(),
      'questions': {
        DecisionPayload.simpleQuestionKey: {
          'type': _type,
          'instructions': _question.text.trim(),
          if (_type == DecisionPayload.typeChoice)
            'criteria': {for (final option in options) option: null},
          if (_type == DecisionPayload.typeScore) 'criteria': options,
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
    final copy = DecisionCopy.of(context);
    return buildOpenHandAlertDialog(
      icon: Icon(Icons.fact_check_rounded, color: colors.primary),
      title: Text(copy.dialogTitle),
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
                  borderRadius: kOpenHandBorderRadius16,
                ),
                child: Text(copy.dialogBody),
              ),
              const SizedBox(height: 16),
              if (!_advanced) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in const [
                      DecisionPayload.typeNoul,
                      DecisionPayload.typeChoice,
                      DecisionPayload.typeScore,
                    ])
                      ChoiceChip(
                        label: Text(copy.typeLabel(type)),
                        selected: _type == type,
                        onSelected: (_) {
                          if (_type == type) return;
                          setState(() {
                            _type = type;
                            _question.text = DecisionPayload.questionForType(
                              _type,
                              current: _question.text,
                              localizedDefault: copy.defaultQuestionFor(_type),
                            );
                            _error = null;
                          });
                        },
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
                  labelText: _advanced
                      ? copy.advancedJsonLabel
                      : copy.stateLabel,
                  alignLabelWithHint: true,
                ),
              ),
              if (!_advanced) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _question,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: copy.questionLabel),
                ),
                if (_type != DecisionPayload.typeNoul) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: ValueKey(_type),
                    controller: _criteria,
                    minLines: 3,
                    maxLines: 7,
                    decoration: InputDecoration(
                      labelText: _type == DecisionPayload.typeChoice
                          ? copy.choiceLinesLabel
                          : copy.scoreLinesLabel,
                    ),
                  ),
                ],
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error == 'draft' ? copy.invalidDraft : _error!,
                    style: TextStyle(color: colors.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          label: openHandCancelLabel(context),
          onPressed: () => Navigator.of(context).pop(),
        ),
        OpenHandDialogActionButton.primary(
          label: copy.applyToDraft,
          onPressed: _apply,
        ),
      ],
    );
  }
}
