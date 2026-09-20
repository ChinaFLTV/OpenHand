import 'package:flutter/material.dart';
import 'package:openhand/shared/ui/openhand_spacing.dart';

import '../util/decision_payload.dart';
import 'animated_expandable.dart';
import 'decision_copy.dart';
import 'oh_pill.dart';

const double _kDecisionBarHeight = 8;
const int _kDecisionAutoExpandLimit = 3;

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
    final copy = DecisionCopy.of(context);
    final answers = data['answers'];
    final questions = data['questions'];
    if (answers is! Map || questions is! Map || questions.isEmpty) {
      return _DecisionChrome(
        icon: Icons.insights_rounded,
        kicker: copy.fenceResult,
        title: copy.resultHeadline(
          data['model'] ?? DecisionPayload.modelFallback,
        ),
        subtitle: copy.resultSubtitle,
        children: const [],
      );
    }
    final entries = questions.entries.toList(growable: false);
    return _DecisionChrome(
      icon: Icons.insights_rounded,
      kicker: copy.fenceResult,
      title: copy.resultHeadline(
        data['model'] ?? DecisionPayload.modelFallback,
      ),
      subtitle: copy.resultSubtitle,
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) kOpenHandGap10,
          _DecisionAnswerBlock(
            name: '${entries[index].key}',
            question: entries[index].value,
            answer: answers[entries[index].key],
            expanded: entries.length <= _kDecisionAutoExpandLimit,
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
    final leadingType = questionEntries.length == 1
        ? (questionEntries.first.value is Map
              ? '${(questionEntries.first.value as Map)['type']}'
              : '')
        : '';
    return _DecisionChrome(
      icon: Icons.fact_check_rounded,
      kicker: copy.fenceRequest,
      title: copy.requestTitle,
      subtitle: copy.requestSubtitle,
      trailing: leadingType.isEmpty ? null : copy.typeLabel(leadingType),
      accentType: leadingType,
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
            style: _fieldLabelStyle(context),
          ),
          kOpenHandGap8,
          for (var index = 0; index < questionEntries.length; index++) ...[
            if (index > 0) kOpenHandGap8,
            _DecisionRequestQuestion(
              name: '${questionEntries[index].key}',
              question: questionEntries[index].value,
            ),
          ],
        ],
      ],
    );
  }
}

class _DecisionChrome extends StatelessWidget {
  const _DecisionChrome({
    required this.icon,
    required this.kicker,
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
    this.accentType = '',
  });

  final IconData icon;
  final String kicker;
  final String title;
  final String subtitle;
  final String? trailing;
  final String accentType;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = _decisionAccent(colors, accentType);
    final iconFill = switch (accentType) {
      DecisionPayload.typeChoice => colors.tertiaryContainer,
      DecisionPayload.typeScore => colors.secondaryContainer,
      _ => colors.primaryContainer,
    };
    final iconColor = switch (accentType) {
      DecisionPayload.typeChoice => colors.onTertiaryContainer,
      DecisionPayload.typeScore => colors.onSecondaryContainer,
      _ => colors.onPrimaryContainer,
    };
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: kOpenHandBorderRadius18,
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: ClipRRect(
          borderRadius: kOpenHandBorderRadius18,
          child: Stack(
            children: [
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: kOpenHandAccentBarWidth,
                child: ColoredBox(color: accent),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: iconFill,
                            borderRadius: kOpenHandBorderRadius12,
                          ),
                          child: Icon(icon, size: 20, color: iconColor),
                        ),
                        kOpenHandHGap10,
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kicker,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              kOpenHandGap4,
                              Text(
                                title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                              ),
                              kOpenHandGap4,
                              Text(
                                subtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (trailing != null) ...[
                          kOpenHandHGap8,
                          _DecisionTypeChip(label: trailing!, type: accentType),
                        ],
                      ],
                    ),
                    if (children.isNotEmpty) ...[kOpenHandGap14, ...children],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecisionAnswerBlock extends StatelessWidget {
  const _DecisionAnswerBlock({
    required this.name,
    required this.question,
    required this.answer,
    required this.expanded,
  });

  final String name;
  final Object? question;
  final Object? answer;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final copy = DecisionCopy.of(context);
    final colors = Theme.of(context).colorScheme;
    final questionMap = question is Map ? question as Map : const {};
    final answerMap = answer is Map ? answer as Map : const {};
    final type = '${answerMap['type'] ?? questionMap['type'] ?? ''}';
    final accent = _decisionAccent(colors, type);
    final result = switch (type) {
      DecisionPayload.typeNoul when answerMap['noul'] is num =>
        copy.heldProbability(answerMap['noul'] as num),
      DecisionPayload.typeChoice => copy.choiceResult(answerMap['choice']),
      DecisionPayload.typeScore => copy.scoreResult(answerMap['score']),
      _ => copy.typeLabel(type),
    };
    final probabilities = _probabilityEntries(copy, type, answerMap);
    final instructions = copy.displayValue(questionMap['instructions']);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: OpenHandExpansionTile(
        initiallyExpanded: expanded,
        suppressHoverOverlay: true,
        circularToggle: true,
        tilePadding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Text(
          result,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: accent,
            height: 1.3,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${copy.questionName(name)} · $instructions',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        trailing: _DecisionTypeChip(label: copy.typeLabel(type), type: type),
        children: [
          if (answerMap['confidence'] is num)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DecisionMetricPill(
                label: copy.confidenceLine(answerMap['confidence'] as num),
                color: accent,
              ),
            ),
          for (final entry in probabilities)
            _DecisionProbabilityRow(
              label: entry.key,
              value: entry.value,
              fill: _barColor(colors, type, entry.key, copy),
            ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  copy.questionName(name),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                  ),
                ),
              ),
              _DecisionTypeChip(label: copy.typeLabel(type), type: type),
            ],
          ),
          kOpenHandGap8,
          Text(
            copy.displayValue(questionMap['instructions']),
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
              style: _fieldLabelStyle(context),
            ),
            kOpenHandGap6,
            _DecisionCriteriaView(type: type, criteria: criteria),
          ],
        ],
      ),
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
              color: _decisionAccent(colors, type),
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
        Text(label, style: _fieldLabelStyle(context)),
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
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
      ),
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
    final accent = _decisionAccent(colors, type);
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

class _DecisionMetricPill extends StatelessWidget {
  const _DecisionMetricPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: kOpenHandPillBorderRadius,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

Color _decisionAccent(ColorScheme colors, String type) => switch (type) {
  DecisionPayload.typeChoice => colors.tertiary,
  DecisionPayload.typeScore => colors.secondary,
  _ => colors.primary,
};

Color _barColor(
  ColorScheme colors,
  String type,
  String label,
  DecisionCopy copy,
) {
  if (type == DecisionPayload.typeNoul && label == copy.notHeld) {
    return colors.tertiary;
  }
  return _decisionAccent(colors, type);
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

TextStyle? _fieldLabelStyle(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return Theme.of(context).textTheme.labelSmall?.copyWith(
    color: colors.onSurfaceVariant,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
  );
}
