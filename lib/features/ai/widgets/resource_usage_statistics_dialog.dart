import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/util/localized_text.dart';
import '../ai_session_controller.dart';
import '../service/runtime/ai_tool_usage_promotion_store.dart';

Future<void> showResourceUsageStatisticsDialog(
  BuildContext context, {
  required AiResourceUsageKind kind,
  Map<String, String> resourceLabels = const <String, String>{},
}) async {
  final controller = context.read<AiSessionController>();
  final store = controller.toolUsagePromotionStore;
  await store.initialize();
  if (!context.mounted) return;
  await showAnimatedDialog<void>(
    context: context,
    builder: (_) => _ResourceUsageStatisticsDialog(
      store: store,
      kind: kind,
      preferredSessionId: controller.currentSession?.id,
      resourceLabels: resourceLabels,
    ),
  );
}

Widget resourceUsageStatisticsButton(
  BuildContext context, {
  required VoidCallback onPressed,
}) {
  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.insights_rounded),
    label: Text(
      openHandLocalizedText(
        context,
        zh: '使用统计',
        zhHant: '使用統計',
        en: 'Usage',
        fr: 'Utilisation',
        de: 'Nutzung',
        ja: '使用状況',
      ),
    ),
  );
}

String resourceUsageKindLabel(BuildContext context, AiResourceUsageKind kind) {
  return switch (kind) {
    AiResourceUsageKind.tool => openHandLocalizedText(
      context,
      zh: '工具',
      zhHant: '工具',
      en: 'Tool',
      fr: 'Outil',
      de: 'Werkzeug',
      ja: 'ツール',
    ),
    AiResourceUsageKind.skill => openHandLocalizedText(
      context,
      zh: '技能',
      zhHant: '技能',
      en: 'Skill',
      fr: 'Compétence',
      de: 'Skill',
      ja: 'スキル',
    ),
    AiResourceUsageKind.hook => 'Hook',
    AiResourceUsageKind.knowledge => openHandLocalizedText(
      context,
      zh: '知识库',
      zhHant: '知識庫',
      en: 'Knowledge',
      fr: 'Connaissance',
      de: 'Wissen',
      ja: 'ナレッジ',
    ),
    AiResourceUsageKind.agent => openHandLocalizedText(
      context,
      zh: '智能体',
      zhHant: '智能體',
      en: 'Agent',
      fr: 'Agent',
      de: 'Agent',
      ja: 'エージェント',
    ),
    AiResourceUsageKind.memory => openHandLocalizedText(
      context,
      zh: '记忆',
      zhHant: '記憶',
      en: 'Memory',
      fr: 'Mémoire',
      de: 'Erinnerung',
      ja: 'メモリ',
    ),
    AiResourceUsageKind.mcp => 'MCP',
  };
}

class _ResourceUsageStatisticsDialog extends StatefulWidget {
  const _ResourceUsageStatisticsDialog({
    required this.store,
    required this.kind,
    required this.preferredSessionId,
    required this.resourceLabels,
  });

  final AiToolUsagePromotionStore store;
  final AiResourceUsageKind kind;
  final String? preferredSessionId;
  final Map<String, String> resourceLabels;

  @override
  State<_ResourceUsageStatisticsDialog> createState() =>
      _ResourceUsageStatisticsDialogState();
}

class _ResourceUsageStatisticsDialogState
    extends State<_ResourceUsageStatisticsDialog> {
  AiResourceUsagePeriod _period = AiResourceUsagePeriod.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaSize = MediaQuery.sizeOf(context);
    final maxHeight = math.min(840.0, mediaSize.height * 0.9);
    final kindLabel = resourceUsageKindLabel(context, widget.kind);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 1120, maxHeight: maxHeight),
        child: Material(
          color: colorScheme.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: widget.store.changes,
            builder: (context, _, _) {
              final snapshot = widget.store.snapshot(
                kind: widget.kind,
                preferredSessionId: widget.preferredSessionId,
              );
              return Column(
                children: [
                  _buildHeader(context, kindLabel),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
                      child: _buildBody(context, snapshot),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String kindLabel) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 18, 20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.query_stats_rounded,
                color: colorScheme.onPrimaryContainer,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '$kindLabel使用统计',
                      zhHant: '$kindLabel使用統計',
                      en: '$kindLabel Usage Analytics',
                      fr: 'Analyse d’utilisation · $kindLabel',
                      de: '$kindLabel-Nutzungsanalyse',
                      ja: '$kindLabel 使用状況',
                    ),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '从会话到年度，洞察调用结构、占比与变化趋势',
                      zhHant: '從會話到年度，洞察呼叫結構、占比與變化趨勢',
                      en: 'Explore call mix, share, and trends from session to year',
                      fr: 'Structure, part et tendance de la session à l’année',
                      de: 'Aufrufmix, Anteile und Trends von Sitzung bis Jahr',
                      ja: 'セッションから年次までの構成・比率・推移',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AiResourceUsageSnapshot snapshot) {
    final level = snapshot.level(_period);
    final ranked = level.counts.entries.toList(growable: false);
    final top = ranked.isEmpty ? null : ranked.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PeriodSelector(
          selected: _period,
          onSelected: (period) => setState(() => _period = period),
        ),
        const SizedBox(height: 18),
        _SummaryGrid(
          totalCount: level.totalCount,
          resourceCount: level.resourceCount,
          topLabel: top == null ? '—' : _labelFor(top.key),
          topShare: top == null || level.totalCount <= 0
              ? 0
              : top.value / level.totalCount,
          bucketLabel: _shortBucket(level.bucketKey),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            final trend = _AnalyticsPanel(
              title: openHandLocalizedText(
                context,
                zh: '调用趋势',
                zhHant: '呼叫趨勢',
                en: 'Call trend',
                fr: 'Tendance',
                de: 'Aufruftrend',
                ja: '呼び出し推移',
              ),
              subtitle: _periodDescription(context, _period),
              child: _TrendChart(points: level.trend),
            );
            final distribution = _AnalyticsPanel(
              title: openHandLocalizedText(
                context,
                zh: '资源占比',
                zhHant: '資源占比',
                en: 'Resource share',
                fr: 'Répartition',
                de: 'Ressourcenanteil',
                ja: 'リソース比率',
              ),
              subtitle: openHandLocalizedText(
                context,
                zh: '当前周期调用构成',
                zhHant: '目前週期呼叫構成',
                en: 'Current bucket composition',
                fr: 'Composition actuelle',
                de: 'Aktuelle Zusammensetzung',
                ja: '現在期間の構成',
              ),
              child: _UsageDistribution(
                entries: ranked,
                labels: widget.resourceLabels,
              ),
            );
            if (!wide) {
              return Column(
                children: [trend, const SizedBox(height: 16), distribution],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: trend),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: distribution),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _AnalyticsPanel(
          title: openHandLocalizedText(
            context,
            zh: '资源调用映射',
            zhHant: '資源呼叫映射',
            en: 'Resource call map',
            fr: 'Carte des appels',
            de: 'Ressourcen-Aufrufkarte',
            ja: 'リソース呼び出しマップ',
          ),
          subtitle: level.bucketKey.isEmpty
              ? '—'
              : '${_periodLabel(context, _period)} · ${level.bucketKey}',
          child: _ResourceRanking(
            entries: ranked,
            labels: widget.resourceLabels,
          ),
        ),
      ],
    );
  }

  String _labelFor(String id) {
    final label = widget.resourceLabels[id]?.trim() ?? '';
    return label.isEmpty ? id : label;
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.selected, required this.onSelected});

  final AiResourceUsagePeriod selected;
  final ValueChanged<AiResourceUsagePeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final period in AiResourceUsagePeriod.values)
          ChoiceChip(
            selected: selected == period,
            onSelected: (_) => onSelected(period),
            avatar: Icon(_periodIcon(period), size: 17),
            label: Text(_periodLabel(context, period)),
            showCheckmark: false,
            selectedColor: colorScheme.primaryContainer,
            side: BorderSide(
              color: selected == period
                  ? colorScheme.primary.withValues(alpha: 0.36)
                  : colorScheme.outlineVariant,
            ),
          ),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.totalCount,
    required this.resourceCount,
    required this.topLabel,
    required this.topShare,
    required this.bucketLabel,
  });

  final int totalCount;
  final int resourceCount;
  final String topLabel;
  final double topShare;
  final String bucketLabel;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _SummaryCard(
        icon: Icons.bolt_rounded,
        label: openHandLocalizedText(
          context,
          zh: '调用总量',
          zhHant: '呼叫總量',
          en: 'Total calls',
          fr: 'Total des appels',
          de: 'Aufrufe gesamt',
          ja: '総呼び出し数',
        ),
        value: '$totalCount',
      ),
      _SummaryCard(
        icon: Icons.hub_rounded,
        label: openHandLocalizedText(
          context,
          zh: '活跃资源',
          zhHant: '活躍資源',
          en: 'Active resources',
          fr: 'Ressources actives',
          de: 'Aktive Ressourcen',
          ja: 'アクティブ',
        ),
        value: '$resourceCount',
      ),
      _SummaryCard(
        icon: Icons.workspace_premium_rounded,
        label: openHandLocalizedText(
          context,
          zh: '首位资源',
          zhHant: '首位資源',
          en: 'Top resource',
          fr: 'Première ressource',
          de: 'Top-Ressource',
          ja: 'トップ',
        ),
        value: topLabel,
        detail: '${(topShare * 100).toStringAsFixed(1)}%',
      ),
      _SummaryCard(
        icon: Icons.calendar_today_rounded,
        label: openHandLocalizedText(
          context,
          zh: '当前周期',
          zhHant: '目前週期',
          en: 'Current bucket',
          fr: 'Période actuelle',
          de: 'Aktueller Zeitraum',
          ja: '現在期間',
        ),
        value: bucketLabel,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 4
            : width >= 520
            ? 2
            : 1;
        final itemWidth = (width - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 112,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsPanel extends StatelessWidget {
  const _AnalyticsPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});

  final List<AiResourceUsageTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty || points.every((point) => point.totalCount == 0)) {
      return _EmptyAnalytics(
        icon: Icons.show_chart_rounded,
        label: openHandLocalizedText(
          context,
          zh: '暂无趋势数据',
          zhHant: '暫無趨勢資料',
          en: 'No trend data yet',
          fr: 'Aucune tendance',
          de: 'Noch keine Trenddaten',
          ja: '推移データはありません',
        ),
      );
    }
    final visible = points.length <= 16
        ? points
        : points.sublist(points.length - 16);
    return SizedBox(
      height: 232,
      child: CustomPaint(
        painter: _TrendPainter(
          points: visible,
          colorScheme: Theme.of(context).colorScheme,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_shortBucket(visible.first.bucketKey)),
                Text(_shortBucket(visible.last.bucketKey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.points, required this.colorScheme});

  final List<AiResourceUsageTrendPoint> points;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    const top = 12.0;
    const bottom = 30.0;
    final width = math.max(1.0, size.width - left * 2);
    final height = math.max(1.0, size.height - top - bottom);
    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.58)
      ..strokeWidth = 1;
    for (var row = 0; row <= 4; row++) {
      final y = top + height * row / 4;
      canvas.drawLine(Offset(left, y), Offset(left + width, y), gridPaint);
    }
    final maxValue = points.fold<int>(
      1,
      (current, point) => math.max(current, point.totalCount),
    );
    final line = Path();
    final area = Path();
    final offsets = <Offset>[];
    for (var index = 0; index < points.length; index++) {
      final x = points.length == 1
          ? left + width / 2
          : left + width * index / (points.length - 1);
      final y = top + height * (1 - points[index].totalCount / maxValue);
      final point = Offset(x, y);
      offsets.add(point);
      if (index == 0) {
        line.moveTo(x, y);
        area
          ..moveTo(x, top + height)
          ..lineTo(x, y);
      } else {
        line.lineTo(x, y);
        area.lineTo(x, y);
      }
    }
    area
      ..lineTo(offsets.last.dx, top + height)
      ..close();
    canvas.drawPath(
      area,
      Paint()..color = colorScheme.primaryContainer.withValues(alpha: 0.48),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = colorScheme.primary
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    final pointPaint = Paint()..color = colorScheme.primary;
    for (final point in offsets) {
      canvas.drawCircle(point, 3.5, pointPaint);
      canvas.drawCircle(
        point,
        2,
        Paint()..color = colorScheme.surfaceContainerLowest,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.colorScheme != colorScheme;
  }
}

class _UsageDistribution extends StatelessWidget {
  const _UsageDistribution({required this.entries, required this.labels});

  final List<MapEntry<String, int>> entries;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _EmptyAnalytics(
        icon: Icons.donut_large_rounded,
        label: openHandLocalizedText(
          context,
          zh: '暂无占比数据',
          zhHant: '暫無占比資料',
          en: 'No distribution yet',
          fr: 'Aucune répartition',
          de: 'Noch keine Verteilung',
          ja: '比率データはありません',
        ),
      );
    }
    final visible = entries.take(5).toList(growable: false);
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final visibleTotal = visible.fold<int>(
      0,
      (sum, entry) => sum + entry.value,
    );
    final otherCount = math.max(0, total - visibleTotal);
    final colors = _chartColors(Theme.of(context).colorScheme);
    return Column(
      children: [
        SizedBox(
          width: 174,
          height: 174,
          child: CustomPaint(
            painter: _DonutPainter(
              values: <int>[
                ...visible.map((entry) => entry.value),
                if (otherCount > 0) otherCount,
              ],
              colors: colors,
              trackColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    openHandLocalizedText(
                      context,
                      zh: '次调用',
                      zhHant: '次呼叫',
                      en: 'calls',
                      fr: 'appels',
                      de: 'Aufrufe',
                      ja: '回',
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < visible.length; index++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: colors[index % colors.length],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labels[visible[index].key] ?? visible[index].key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  '${(visible[index].value * 100 / total).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (otherCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: colors[visible.length % colors.length],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    openHandLocalizedText(
                      context,
                      zh: '其他资源',
                      zhHant: '其他資源',
                      en: 'Other resources',
                      fr: 'Autres ressources',
                      de: 'Weitere Ressourcen',
                      ja: 'その他のリソース',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  '${(otherCount * 100 / total).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.values,
    required this.colors,
    required this.trackColor,
  });

  final List<int> values;
  final List<Color> colors;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 17
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, paint..color = trackColor);
    final total = values.fold<int>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    const gap = 0.035;
    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = math.pi * 2 * values[index] / total;
      final visibleSweep = math.max(0.0, sweep - gap);
      canvas.drawArc(
        rect,
        start + gap / 2,
        visibleSweep,
        false,
        paint..color = colors[index % colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.trackColor != trackColor;
  }
}

class _ResourceRanking extends StatelessWidget {
  const _ResourceRanking({required this.entries, required this.labels});

  final List<MapEntry<String, int>> entries;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _EmptyAnalytics(
        icon: Icons.data_usage_rounded,
        label: openHandLocalizedText(
          context,
          zh: '当前周期尚无调用记录',
          zhHant: '目前週期尚無呼叫記錄',
          en: 'No calls in this bucket',
          fr: 'Aucun appel sur cette période',
          de: 'Keine Aufrufe in diesem Zeitraum',
          ja: 'この期間の記録はありません',
        ),
      );
    }
    final visible = entries.take(20).toList(growable: false);
    final maxValue = math.max(1, visible.first.value);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var index = 0; index < visible.length; index++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    '${index + 1}'.padLeft(2, '0'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        labels[visible[index].key] ?? visible[index].key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if ((labels[visible[index].key] ?? '').isNotEmpty)
                        Text(
                          visible[index].key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: visible[index].value / maxValue,
                      minHeight: 9,
                      color: colorScheme.primary,
                      backgroundColor: colorScheme.surfaceContainerHigh,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${visible[index].value}',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (index != visible.length - 1)
            Divider(height: 1, color: colorScheme.outlineVariant),
        ],
        if (entries.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              openHandLocalizedText(
                context,
                zh: '另有 ${entries.length - visible.length} 项低频资源',
                zhHant: '另有 ${entries.length - visible.length} 項低頻資源',
                en: '${entries.length - visible.length} more low-frequency resources',
                fr: '${entries.length - visible.length} autres ressources peu fréquentes',
                de: '${entries.length - visible.length} weitere seltene Ressourcen',
                ja: '低頻度リソースが他に ${entries.length - visible.length} 件あります',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyAnalytics extends StatelessWidget {
  const _EmptyAnalytics({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 214,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: colorScheme.outline),
            const SizedBox(height: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Color> _chartColors(ColorScheme colors) => <Color>[
  colors.primary,
  colors.tertiary,
  colors.secondary,
  colors.error,
  colors.primary.withValues(alpha: 0.58),
  colors.onSurfaceVariant.withValues(alpha: 0.62),
];

IconData _periodIcon(AiResourceUsagePeriod period) => switch (period) {
  AiResourceUsagePeriod.session => Icons.forum_outlined,
  AiResourceUsagePeriod.day => Icons.today_outlined,
  AiResourceUsagePeriod.week => Icons.date_range_outlined,
  AiResourceUsagePeriod.month => Icons.calendar_month_outlined,
  AiResourceUsagePeriod.quarter => Icons.view_timeline_outlined,
  AiResourceUsagePeriod.year => Icons.event_note_outlined,
};

String _periodLabel(BuildContext context, AiResourceUsagePeriod period) {
  return switch (period) {
    AiResourceUsagePeriod.session => openHandLocalizedText(
      context,
      zh: '会话',
      zhHant: '會話',
      en: 'Session',
      fr: 'Session',
      de: 'Sitzung',
      ja: 'セッション',
    ),
    AiResourceUsagePeriod.day => openHandLocalizedText(
      context,
      zh: '天',
      zhHant: '天',
      en: 'Day',
      fr: 'Jour',
      de: 'Tag',
      ja: '日',
    ),
    AiResourceUsagePeriod.week => openHandLocalizedText(
      context,
      zh: '周',
      zhHant: '週',
      en: 'Week',
      fr: 'Semaine',
      de: 'Woche',
      ja: '週',
    ),
    AiResourceUsagePeriod.month => openHandLocalizedText(
      context,
      zh: '月',
      zhHant: '月',
      en: 'Month',
      fr: 'Mois',
      de: 'Monat',
      ja: '月',
    ),
    AiResourceUsagePeriod.quarter => openHandLocalizedText(
      context,
      zh: '季度',
      zhHant: '季度',
      en: 'Quarter',
      fr: 'Trimestre',
      de: 'Quartal',
      ja: '四半期',
    ),
    AiResourceUsagePeriod.year => openHandLocalizedText(
      context,
      zh: '年',
      zhHant: '年',
      en: 'Year',
      fr: 'Année',
      de: 'Jahr',
      ja: '年',
    ),
  };
}

String _periodDescription(BuildContext context, AiResourceUsagePeriod period) {
  final label = _periodLabel(context, period);
  return openHandLocalizedText(
    context,
    zh: '$label级调用总量变化',
    zhHant: '$label級呼叫總量變化',
    en: '$label-level call volume',
    fr: 'Volume d’appels · $label',
    de: 'Aufrufvolumen · $label',
    ja: '$label単位の呼び出し数',
  );
}

String _shortBucket(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '—';
  if (trimmed.length <= 14) return trimmed;
  return '…${trimmed.substring(trimmed.length - 12)}';
}
