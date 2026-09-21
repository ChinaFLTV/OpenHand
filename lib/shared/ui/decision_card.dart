import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../util/decision_payload.dart';
import 'decision_copy.dart';
import 'decision_form.dart';
import 'oh_pill.dart';

const double _kDecisionBarHeight = 8;
const double _kDecisionCardOutlineAlpha = 0.72;

/// 展示接口原始决策，不把概率解释为确定事实。
class OpenHandDecisionCard extends StatelessWidget {
  const OpenHandDecisionCard({super.key, required this.data});
  final Map<String, Object?> data;

  static Widget? fromJson(String text) {
    final data = DecisionPayload.tryResult(text);
    if (data == null) return null;
    return OpenHandDecisionCard(data: data);
  }

  @override
  Widget build(BuildContext context) {
    final answers = data['answers'];
    final questions = data['questions'];
    if (answers is! Map || questions is! Map || questions.isEmpty) {
      return const SizedBox.shrink();
    }
    final entries = questions.entries.toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) kOpenHandGap10,
          _DecisionAnswerBlock(
            question: entries[index].value,
            answer: answers[entries[index].key],
          ),
        ],
      ],
    );
  }
}

/// 将决策请求从原始 JSON 围栏还原为结构化卡片。
class OpenHandDecisionRequestCard extends StatelessWidget {
  const OpenHandDecisionRequestCard({super.key, required this.data});
  final Map<String, Object?> data;

  static Widget? fromJson(String text) {
    final data = DecisionPayload.tryRequest(text);
    if (data == null) return null;
    return OpenHandDecisionRequestCard(data: data);
  }

  @override
  Widget build(BuildContext context) {
    final copy = DecisionCopy.of(context);
    final questions = data['questions'];
    final questionEntries = questions is Map
        ? questions.entries.toList(growable: false)
        : const <MapEntry<dynamic, dynamic>>[];
    return _DecisionCardShell(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DecisionField(
            label: copy.stateLabel,
            value: copy.displayValue(data['state']),
          ),
          if (questionEntries.isNotEmpty) ...[
            kOpenHandGap12,
            Text(
              questionEntries.length == 1
                  ? copy.questionLabel
                  : copy.questionsLabel,
              style: openHandDecisionFieldLabelStyle(context),
            ),
            kOpenHandGap8,
            for (var index = 0; index < questionEntries.length; index++) ...[
              if (index > 0) kOpenHandGap12,
              _DecisionRequestQuestion(
                name: '${questionEntries[index].key}',
                question: questionEntries[index].value,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DecisionCardShell extends StatelessWidget {
  const _DecisionCardShell({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: kOpenHandBorderRadius18,
        side: BorderSide(
          color: colors.outlineVariant.withValues(
            alpha: _kDecisionCardOutlineAlpha,
          ),
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
  }
}

class _DecisionAnswerBlock extends StatelessWidget {
  const _DecisionAnswerBlock({required this.question, required this.answer});

  final Object? question;
  final Object? answer;

  @override
  Widget build(BuildContext context) {
    final copy = DecisionCopy.of(context);
    final colors = Theme.of(context).colorScheme;
    final questionMap = question is Map ? question as Map : const {};
    final answerMap = answer is Map ? answer as Map : const {};
    final type = '${answerMap['type'] ?? questionMap['type'] ?? ''}';
    final probabilities = _probabilityEntries(copy, type, answerMap);
    if (probabilities.isEmpty) return const SizedBox.shrink();
    return _DecisionCardShell(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < probabilities.length; index++) ...[
            if (index > 0) kOpenHandGap8,
            _DecisionProbabilityRow(
              label: probabilities[index].key,
              value: probabilities[index].value,
              fill: _barColor(colors, type, probabilities[index].key, copy),
            ),
          ],
        ],
      ),
    );
  }
}

class _DecisionRequestQuestion extends StatelessWidget {
  const _DecisionRequestQuestion({required this.name, required this.question});

  final String name;
  final Object? question;

  @override
  Widget build(BuildContext context) {
    final copy = DecisionCopy.of(context);
    final colors = Theme.of(context).colorScheme;
    final questionMap = question is Map ? question as Map : const {};
    final type = '${questionMap['type'] ?? ''}';
    final criteria = questionMap['criteria'];
    final named = copy.customQuestionName(name, type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _DecisionTypeChip(label: copy.typeLabel(type), type: type),
            if (named.isNotEmpty) ...[
              kOpenHandHGap8,
              Expanded(
                child: Text(
                  named,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ],
        ),
        kOpenHandGap8,
        Text(
          copy.localizedInstructions(type, questionMap['instructions']),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.onSurface,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (criteria != null) ...[
          kOpenHandGap10,
          Text(
            type == DecisionPayload.typeScore
                ? copy.scoreItemLabel
                : type == DecisionPayload.typeChoice
                ? copy.choiceItemLabel
                : copy.criteriaLabel,
            style: openHandDecisionFieldLabelStyle(context),
          ),
          kOpenHandGap6,
          _DecisionCriteriaView(type: type, criteria: criteria),
        ],
      ],
    );
  }
}

class _DecisionCriteriaView extends StatelessWidget {
  const _DecisionCriteriaView({required this.type, required this.criteria});

  final String type;
  final Object criteria;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (criteria is Map) {
      final entries = (criteria as Map).entries.toList(growable: false);
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final entry in entries)
            _DecisionOptionChip(
              label: entry.value == null || '${entry.value}'.trim().isEmpty
                  ? '${entry.key}'
                  : '${entry.key} · ${entry.value}',
              color: openHandDecisionAccent(colors, type),
            ),
        ],
      );
    }
    if (criteria is List) {
      final items = criteria as List;
      return Column(
        children: [
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == items.length - 1 ? 0 : 6,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${index + 1}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${items[index]}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return Text(DecisionCopy.of(context).displayValue(criteria));
  }
}

class _DecisionField extends StatelessWidget {
  const _DecisionField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: openHandDecisionFieldLabelStyle(context)),
        kOpenHandGap6,
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.onSurface,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DecisionProbabilityRow extends StatelessWidget {
  const _DecisionProbabilityRow({
    required this.label,
    required this.value,
    required this.fill,
  });

  final String label;
  final num value;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unit = DecisionPayload.unit(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              DecisionPayload.percentLabel(value),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: fill,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        kOpenHandGap6,
        ClipRRect(
          borderRadius: kOpenHandBorderRadius8,
          child: SizedBox(
            height: _kDecisionBarHeight,
            width: double.infinity,
            child: ColoredBox(
              color: colors.surfaceContainerHighest,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: unit,
                  heightFactor: 1,
                  child: ColoredBox(color: fill),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DecisionTypeChip extends StatelessWidget {
  const _DecisionTypeChip({required this.label, required this.type});

  final String label;
  final String type;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = openHandDecisionAccent(colors, type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DecisionOptionChip extends StatelessWidget {
  const _DecisionOptionChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: kOpenHandBorderRadius12,
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _barColor(
  ColorScheme colors,
  String type,
  String label,
  DecisionCopy copy,
) {
  if (type == DecisionPayload.typeNoul && label == copy.notHeld) {
    return colors.tertiary;
  }
  return openHandDecisionAccent(colors, type);
}

List<MapEntry<String, num>> _probabilityEntries(
  DecisionCopy copy,
  String type,
  Map answer,
) {
  if (type == DecisionPayload.typeNoul && answer['noul'] is num) {
    final held = answer['noul'] as num;
    return [MapEntry(copy.held, held), MapEntry(copy.notHeld, 1 - held)];
  }
  final probabilities = answer['probabilities'];
  final legend = answer['legend'];
  if (probabilities is! Map) return const [];
  return [
    for (final entry in probabilities.entries)
      if (entry.value is num)
        MapEntry(_legendLabel(legend, entry.key), entry.value as num),
  ];
}

String _legendLabel(Object? legend, Object? key) {
  if (legend is Map) {
    final label = '${legend[key] ?? ''}'.trim();
    if (label.isNotEmpty) return label;
  }
  return '$key';
}
