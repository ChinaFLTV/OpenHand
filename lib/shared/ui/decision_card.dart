import 'dart:convert';

import 'package:flutter/material.dart';

import '../util/decision_payload.dart';
import 'animated_expandable.dart';

/// 展示接口原始决策，不把概率解释为确定事实。
class OpenHandDecisionCard extends StatelessWidget {
  const OpenHandDecisionCard({super.key, required this.data});
  final Map<String, Object?> data;

  static Widget? fromJson(String text) {
    if (text.length > DecisionPayload.maxCharacters) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final questions = decoded['questions'];
      if (questions is! Map ||
          questions.isEmpty ||
          questions.length > DecisionPayload.maxQuestions) {
        return null;
      }
      final data = DecisionPayload.result(
        Map<String, Object?>.from(decoded),
        Map<String, Object?>.from(questions),
      );
      return OpenHandDecisionCard(data: data);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final answers = data['answers'] as Map;
    final questions = data['questions'] as Map;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            colors.primaryContainer.withValues(alpha: .65),
            colors.tertiaryContainer.withValues(alpha: .4),
          ],
        ),
        border: Border.all(color: colors.primary.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_tree_rounded, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '决策结果 · ${data['model'] ?? 'Jev'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('按问题查看答案与概率分布。'),
          for (final entry in questions.entries) ...[
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final answer = answers[entry.key] as Map;
                final question = entry.value as Map;
                final type = answer['type'];
                final result = type == 'noul'
                    ? '成立概率 ${((answer['noul'] as num) * 100).toStringAsFixed(1)}%'
                    : type == 'choice'
                    ? '选择：${answer['choice']}'
                    : '评分：${answer['score']}';
                final probabilities = type == 'noul'
                    ? {'成立': answer['noul'], '不成立': 1 - (answer['noul'] as num)}
                    : answer['probabilities'] as Map;
                return OpenHandExpansionTile(
                  initiallyExpanded: questions.length <= 3,
                  title: Text(
                    result,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                  subtitle: Text('${entry.key} · ${question['instructions']}'),
                  children: [
                    if (answer['confidence'] is num)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '置信度 ${((answer['confidence'] as num) * 100).toStringAsFixed(1)}%',
                        ),
                      ),
                    for (final probability in probabilities.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${(answer['legend'] is Map ? (answer['legend'] as Map)[probability.key] : null) ?? probability.key} · ${((probability.value as num) * 100).toStringAsFixed(1)}%',
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: (probability.value as num).toDouble(),
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
