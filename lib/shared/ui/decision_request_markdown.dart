import 'dart:convert';

import '../util/decision_payload.dart';
import 'decision_copy.dart';

final _requestFence = RegExp(
  r'^```openhand-decision-request[ \t]*\r?\n([\s\S]*?)^```[ \t]*(?:\r?\n|$)',
  multiLine: true,
);
final _markdownPunctuation = RegExp(r'[\\`*_{}\[\]()<>#+.!|~\-]');

String _literal(String text) => text
    .replaceAllMapped(_markdownPunctuation, (match) => '\\${match[0]}')
    .replaceAll('\r\n', '\n')
    .replaceAll('\n', '  \n');

String _value(Object? value) => value is String
    ? _literal(value)
    : '```json\n${const JsonEncoder.withIndent('  ').convert(value).replaceAll('`', r'\u0060')}\n```';

/// 仅转换明确标记且有效的请求；原文由消息层保留，损坏内容不静默丢弃。
String? decisionRequestToMarkdown(String source, DecisionCopy copy) {
  if (source.length > DecisionPayload.maxCharacters ||
      !source.contains(DecisionPayload.requestLanguage)) {
    return null;
  }
  final matches = _requestFence.allMatches(source).toList();
  if (matches.isEmpty) return null;
  final output = StringBuffer();
  var end = 0;
  for (final match in matches) {
    if (!match[1]!.trimLeft().startsWith('{')) return null;
    final request = DecisionPayload.tryRequest(match[1]!);
    if (request == null) return null;
    output.writeln(_literal(source.substring(end, match.start)));
    output.writeln(
      '### ${copy.requestTitle}\n\n**${copy.stateLabel}**\n\n${_value(request['state'])}\n',
    );
    final questions = request['questions'] as Map;
    for (final entry in questions.entries) {
      final question = entry.value as Map;
      final type = question['type'] as String;
      output.writeln(
        '#### ${_literal(entry.key as String)} · ${copy.typeLabel(type)}\n\n${_value(question['instructions'])}\n',
      );
      final criteria = question['criteria'];
      if (criteria == null) continue;
      final label = type == DecisionPayload.typeScore
          ? copy.scoreItemLabel
          : type == DecisionPayload.typeChoice
          ? copy.choiceItemLabel
          : copy.criteriaLabel;
      output.writeln('**$label**\n');
      final items = criteria is Map
          ? criteria.entries.toList()
          : (criteria as List).asMap().entries.toList();
      for (var index = 0; index < items.length; index++) {
        final entry = items[index];
        final value = criteria is Map
            ? '${_literal('${entry.key}')}${entry.value == null
                  ? ''
                  : entry.value is String
                  ? '：${_value(entry.value)}'
                  : '\n\n${_value(entry.value)}'}'
            : _value(entry.value);
        output.writeln('${index + 1}. ${value.replaceAll('\n', '\n   ')}');
      }
      output.writeln();
    }
    end = match.end;
  }
  output.write(_literal(source.substring(end)));
  return output.toString().trim();
}
