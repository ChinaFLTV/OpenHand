import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_json_tree.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_metric_cells.dart';
import '../../../shared/ui/openhand_table_pagination.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/text_clip.dart';
import '../ai_session_controller.dart';
import '../service/runtime/ai_tool_usage_promotion_store.dart';

const double _kUsageListMaxHeight = 420;

enum _MetricTone { neutral, success, error, info, accent }

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
  return FilledButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.insights_rounded),
    label: Text(resourceUsageStatisticsLabel(context)),
  );
}

String resourceUsageStatisticsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '使用统计',
    zhHant: '使用統計',
    en: 'Usage',
    fr: 'Utilisation',
    de: 'Nutzung',
    ja: '使用状況',
  );
}

String resourceUsageKindLabel(BuildContext context, AiResourceUsageKind kind) {
  return switch (kind) {
    AiResourceUsageKind.tool => openHandToolLabel(context),
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
    AiResourceUsageKind.knowledge => openHandKnowledgeLabel(context),
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
    AiResourceUsageKind.workflow => openHandLocalizedText(
      context,
      zh: '工作流',
      zhHant: '工作流',
      en: 'Workflow',
      fr: 'Workflow',
      de: 'Workflow',
      ja: 'ワークフロー',
    ),
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
    return buildOpenHandDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: kOpenHandBorderRadius30,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      maxWidth: kOpenHandDialogWidthPanel,
      maxHeight: maxHeight,
      child: ValueListenableBuilder<int>(
        valueListenable: widget.store.changes,
        builder: (context, _, _) {
          final snapshot = widget.store.snapshot(
            kind: widget.kind,
            preferredSessionId: widget.preferredSessionId,
          );
          return Column(
            children: [
              _buildHeader(context, kindLabel, snapshot.generatedAt),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
                  physics: openHandDialogAwareScrollPhysics(context),
                  child: _buildBody(context, snapshot),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String kindLabel,
    DateTime generatedAt,
  ) {
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
                borderRadius: BorderRadius.circular(kOpenHandRadius18),
              ),
              child: Icon(
                Icons.query_stats_rounded,
                color: colorScheme.onPrimaryContainer,
                size: 28,
              ),
            ),
            kOpenHandHGap16,
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
                  kOpenHandGap5,
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          openHandLocalizedText(
                            context,
                            zh: '细粒度调用、状态、耗时与会话洞察',
                            zhHant: '細粒度呼叫、狀態、耗時與會話洞察',
                            en: 'Live calls, outcomes, latency, and sessions',
                            fr: 'Appels, états, latence et sessions en direct',
                            de: 'Live-Aufrufe, Status, Latenz und Sitzungen',
                            ja: '呼び出し・状態・所要時間・セッション',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      kOpenHandHGap10,
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: kOpenHandPillBorderRadius,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            kOpenHandHGap5,
                            Text(
                              formatYearMonthDayHmsLocal(generatedAt),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
          rangeHints: <AiResourceUsagePeriod, String>{
            for (final period in AiResourceUsagePeriod.values)
              period: snapshot.level(period).bucketKey,
          },
        ),
        kOpenHandGap18,
        _SummaryGrid(
          level: level,
          topLabel: top == null ? '—' : _labelFor(top.key),
        ),
        kOpenHandGap18,
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
                zh: '当前窗口调用构成',
                zhHant: '目前視窗呼叫構成',
                en: 'Current window composition',
                fr: 'Composition de la fenêtre',
                de: 'Zusammensetzung des Fensters',
                ja: '現在の集計範囲の構成',
              ),
              child: _UsageDistribution(
                entries: ranked,
                labels: widget.resourceLabels,
              ),
            );
            if (!wide) {
              return Column(children: [trend, kOpenHandGap16, distribution]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: trend),
                kOpenHandHGap16,
                Expanded(flex: 4, child: distribution),
              ],
            );
          },
        ),
        kOpenHandGap18,
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
        kOpenHandGap18,
        _AnalyticsPanel(
          title: openHandLocalizedText(
            context,
            zh: '资源与子资源明细',
            zhHant: '資源與子資源明細',
            en: 'Resource details',
            fr: 'Détails des ressources',
            de: 'Ressourcendetails',
            ja: 'リソース詳細',
          ),
          subtitle: openHandLocalizedText(
            context,
            zh: widget.kind == AiResourceUsageKind.mcp
                ? '按 MCP 服务展开实际调用的 Tool'
                : '成功率、耗时、会话与子动作明细',
            zhHant: widget.kind == AiResourceUsageKind.mcp
                ? '依 MCP 服務展開實際呼叫的 Tool'
                : '成功率、耗時、會話與子動作明細',
            en: widget.kind == AiResourceUsageKind.mcp
                ? 'MCP servers and their invoked tools'
                : 'Success, latency, sessions, and sub-actions',
            fr: 'Succès, latence, sessions et sous-actions',
            de: 'Erfolg, Latenz, Sitzungen und Unteraktionen',
            ja: '成功率、所要時間、セッション、サブ操作',
          ),
          child: _ResourceDetails(
            resources: level.resources,
            labels: widget.resourceLabels,
          ),
        ),
        kOpenHandGap18,
        _AnalyticsPanel(
          title: openHandLocalizedText(
            context,
            zh: '调用记录',
            zhHant: '呼叫記錄',
            en: 'Call records',
            fr: 'Enregistrements des appels',
            de: 'Aufrufprotokoll',
            ja: '呼び出し記録',
          ),
          subtitle: openHandLocalizedText(
            context,
            zh: '实时更新 · 参数与结果已脱敏并限制长度',
            zhHant: '即時更新 · 參數與結果已脫敏並限制長度',
            en: 'Live · arguments and results are redacted and bounded',
            fr: 'Temps réel · contenu protégé et limité',
            de: 'Live · Inhalte geschützt und begrenzt',
            ja: 'リアルタイム · 内容はマスク・制限済み',
          ),
          child: _RecentUsageEvents(
            events: level.recentEvents,
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
  const _PeriodSelector({
    required this.selected,
    required this.onSelected,
    required this.rangeHints,
  });

  final AiResourceUsagePeriod selected;
  final ValueChanged<AiResourceUsagePeriod> onSelected;
  final Map<AiResourceUsagePeriod, String> rangeHints;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final period in AiResourceUsagePeriod.values)
          Tooltip(
            message: (rangeHints[period]?.trim().isEmpty ?? true)
                ? _periodLabel(context, period)
                : rangeHints[period]!.trim(),
            child: ChoiceChip(
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
          ),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.level, required this.topLabel});

  final AiResourceUsageLevelSnapshot level;
  final String topLabel;

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
        value: '${level.totalCount}',
      ),
      _SummaryCard(
        icon: Icons.check_circle_outline_rounded,
        label: openHandLocalizedText(
          context,
          zh: '成功调用',
          zhHant: '成功呼叫',
          en: 'Succeeded',
          fr: 'Réussis',
          de: 'Erfolgreich',
          ja: '成功',
        ),
        value: '${level.successCount}',
      ),
      _SummaryCard(
        icon: Icons.error_outline_rounded,
        label: openHandLocalizedText(
          context,
          zh: '失败调用',
          zhHant: '失敗呼叫',
          en: 'Failed',
          fr: 'Échoués',
          de: 'Fehlgeschlagen',
          ja: '失敗',
        ),
        value: '${level.failureCount}',
      ),
      _SummaryCard(
        icon: Icons.timer_outlined,
        label: openHandLocalizedText(
          context,
          zh: '平均耗时',
          zhHant: '平均耗時',
          en: 'Average latency',
          fr: 'Latence moyenne',
          de: 'Mittlere Latenz',
          ja: '平均所要時間',
        ),
        value: _formatAverageDuration(
          level.averageDurationMs,
          level.durationSampleCount,
        ),
      ),
      _SummaryCard(
        icon: Icons.forum_outlined,
        label: openHandLocalizedText(
          context,
          zh: '活跃会话',
          zhHant: '活躍會話',
          en: 'Active sessions',
          fr: 'Sessions actives',
          de: 'Aktive Sitzungen',
          ja: 'アクティブセッション',
        ),
        value: '${level.sessionCount}',
      ),
      _SummaryCard(
        icon: Icons.workspace_premium_outlined,
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
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 3
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
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 112,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(kOpenHandRadius14),
            ),
            child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 22),
          ),
          kOpenHandWidth13,
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
                kOpenHandGap5,
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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
        borderRadius: BorderRadius.circular(kOpenHandRadius22),
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
          kOpenHandGap3,
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          kOpenHandGap18,
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
    final colors = Theme.of(context).colorScheme;
    return OpenHandZoomableOperationalTrendChart(
      series: <OpenHandChartSeries>[
        OpenHandChartSeries(
          label: openHandLocalizedText(
            context,
            zh: '调用总量',
            zhHant: '呼叫總量',
            en: 'Total calls',
            fr: 'Total des appels',
            de: 'Aufrufe gesamt',
            ja: '総呼び出し数',
          ),
          values: points
              .map((point) => point.totalCount.toDouble())
              .toList(growable: false),
          color: colors.primary,
          aggregation: OpenHandTrendAggregation.sum,
        ),
      ],
      xLabels: points.map((point) => point.bucketKey).toList(growable: false),
      valueSuffix: '',
      height: 232,
      area: true,
      showLegend: false,
      initialVisibleItemCount: math.min(16, points.length),
      showZoomToolbar: false,
      formatValue: (value) => value.round().toString(),
      tooltipLabelBuilder: (selection) {
        final point = points[selection.pointIndex];
        return '${_shortBucket(point.bucketKey)}  ·  '
            '${openHandLocalizedText(context, zh: '调用', en: 'Calls')} ${point.totalCount}  ·  '
            '${openHandLocalizedText(context, zh: '成功', en: 'Success')} ${point.successCount}  ·  '
            '${openHandLocalizedText(context, zh: '失败', en: 'Failed')} ${point.failureCount}';
      },
      semanticLabel: openHandLocalizedText(
        context,
        zh: '调用趋势图',
        zhHant: '呼叫趨勢圖',
        en: 'Call trend chart',
        fr: 'Graphique de tendance des appels',
        de: 'Aufruftrenddiagramm',
        ja: '呼び出し推移グラフ',
      ),
      onSelectionChanged: null,
    );
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
        kOpenHandGap14,
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
                    borderRadius: BorderRadius.circular(kOpenHandRadius3),
                  ),
                ),
                kOpenHandHGap8,
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
                    borderRadius: BorderRadius.circular(kOpenHandRadius3),
                  ),
                ),
                kOpenHandHGap8,
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
          zh: '当前窗口尚无调用记录',
          zhHant: '目前視窗尚無呼叫記錄',
          en: 'No calls in this window',
          fr: 'Aucun appel sur cette période',
          de: 'Keine Aufrufe in diesem Zeitraum',
          ja: 'この集計範囲の記録はありません',
        ),
      );
    }
    final visible = entries;
    final maxValue = math.max(1, visible.isEmpty ? 1 : visible.first.value);
    final colorScheme = Theme.of(context).colorScheme;
    return OpenHandClientPager<MapEntry<String, int>>(
      items: visible,
      builder: (context, pageItems) => _BoundedAnalyticsList(
        child: Column(
          children: [
            for (var index = 0; index < pageItems.length; index++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(
                        '${index + 1}'.padLeft(2, '0'),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            labels[pageItems[index].key] ??
                                pageItems[index].key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if ((labels[pageItems[index].key] ?? '').isNotEmpty)
                            Text(
                              pageItems[index].key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    kOpenHandHGap14,
                    Expanded(
                      flex: 5,
                      child: ClipRRect(
                        borderRadius: kOpenHandPillBorderRadius,
                        child: LinearProgressIndicator(
                          value: unitRatio(pageItems[index].value, maxValue),
                          minHeight: 9,
                          color: colorScheme.primary,
                          backgroundColor: colorScheme.surfaceContainerHigh,
                        ),
                      ),
                    ),
                    kOpenHandHGap14,
                    SizedBox(
                      width: 64,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${pageItems[index].value}',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                            TextSpan(
                              text: ' ${_callUnitLabel(context)}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (index != pageItems.length - 1)
                Divider(height: 1, color: colorScheme.outlineVariant),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResourceDetails extends StatelessWidget {
  const _ResourceDetails({required this.resources, required this.labels});

  final List<AiResourceUsageResourceSnapshot> resources;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) {
      return _EmptyAnalytics(
        icon: Icons.account_tree_outlined,
        label: openHandLocalizedText(
          context,
          zh: '当前窗口暂无资源明细',
          zhHant: '目前視窗暫無資源明細',
          en: 'No resource details in this window',
          fr: 'Aucun détail pour cette période',
          de: 'Keine Details für diesen Zeitraum',
          ja: 'この集計範囲の詳細はありません',
        ),
      );
    }
    return OpenHandClientPager<AiResourceUsageResourceSnapshot>(
      items: resources,
      builder: (context, visible) => _BoundedAnalyticsList(
        child: Column(
          children: [
            for (var index = 0; index < visible.length; index++) ...[
              _ResourceDetailCard(
                resource: visible[index],
                label: labels[visible[index].resourceId],
              ),
              if (index != visible.length - 1) kOpenHandGap10,
            ],
          ],
        ),
      ),
    );
  }
}

class _ResourceDetailCard extends StatelessWidget {
  const _ResourceDetailCard({required this.resource, this.label});

  final AiResourceUsageResourceSnapshot resource;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayLabel = label?.trim().isNotEmpty == true
        ? label!.trim()
        : resource.resourceId;
    final children = resource.subResources;
    final rateText = resource.successRate == null
        ? kOpenHandTableMetricEmpty
        : '${(resource.successRate! * 100).toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(kOpenHandRadius12),
                ),
                child: Icon(
                  children.isEmpty
                      ? Icons.extension_outlined
                      : Icons.hub_outlined,
                  size: 20,
                  color: colors.onPrimaryContainer,
                ),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (displayLabel != resource.resourceId)
                      Text(
                        resource.resourceId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFamily: kOpenHandMonospaceFontFamily,
                        ),
                      ),
                  ],
                ),
              ),
              _TotalBadge(total: resource.totalCount),
            ],
          ),
          kOpenHandGap12,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricPill(
                icon: Icons.check_rounded,
                label: _metricSuccessLabel(context),
                value: '${resource.successCount}',
                tone: _MetricTone.success,
              ),
              _MetricPill(
                icon: Icons.percent_rounded,
                label: _metricRateLabel(context),
                value: rateText,
                tone: _MetricTone.accent,
              ),
              _MetricPill(
                icon: Icons.close_rounded,
                label: _metricFailureLabel(context),
                value: '${resource.failureCount}',
                tone: resource.failureCount > 0
                    ? _MetricTone.error
                    : _MetricTone.neutral,
              ),
              _MetricPill(
                icon: Icons.timer_outlined,
                label: _metricLatencyLabel(context),
                value: _formatAverageDuration(
                  resource.averageDurationMs,
                  resource.durationSampleCount,
                ),
                tone: _MetricTone.info,
              ),
              _MetricPill(
                icon: Icons.forum_outlined,
                label: _metricSessionLabel(context),
                value: '${resource.sessionCount}',
              ),
              if (resource.lastCalledAt != null)
                _MetricPill(
                  icon: Icons.schedule_rounded,
                  label: _metricLastLabel(context),
                  value: formatYearMonthDayHms(
                    resource.lastCalledAt!.toLocal(),
                  ),
                ),
            ],
          ),
          if (children.isNotEmpty) ...[
            kOpenHandGap13,
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(kOpenHandRadius14),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    _SubResourceRow(resource: children[index]),
                    if (index != children.length - 1)
                      Divider(height: 14, color: colors.outlineVariant),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubResourceRow extends StatelessWidget {
  const _SubResourceRow({required this.resource});

  final AiResourceUsageResourceSnapshot resource;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayLabel = _subResourceDisplayLabel(context, resource.resourceId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 17,
                color: colors.primary,
              ),
              kOpenHandHGap8,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (displayLabel != resource.resourceId)
                      Text(
                        resource.resourceId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFamily: kOpenHandMonospaceFontFamily,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          kOpenHandGap8,
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetricPill(
                label: _metricSuccessLabel(context),
                value: '${resource.successCount}',
                tone: _MetricTone.success,
                compact: true,
              ),
              _MetricPill(
                label: _metricFailureLabel(context),
                value: '${resource.failureCount}',
                tone: resource.failureCount > 0
                    ? _MetricTone.error
                    : _MetricTone.neutral,
                compact: true,
              ),
              _MetricPill(
                label: _metricLatencyLabel(context),
                value: _formatAverageDuration(
                  resource.averageDurationMs,
                  resource.durationSampleCount,
                ),
                tone: _MetricTone.info,
                compact: true,
              ),
              _MetricPill(
                label: _metricTotalLabel(context),
                value: '${resource.totalCount}',
                tone: _MetricTone.accent,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalBadge extends StatelessWidget {
  const _TotalBadge({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(kOpenHandRadius14),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _metricTotalLabel(context),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$total',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                TextSpan(
                  text: ' ${_callUnitLabel(context)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onPrimaryContainer.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    this.icon,
    this.tone = _MetricTone.neutral,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final _MetricTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (Color foreground, Color background) = switch (tone) {
      _MetricTone.success => (
        colors.onPrimaryContainer,
        colors.primaryContainer,
      ),
      _MetricTone.error => (colors.onErrorContainer, colors.errorContainer),
      _MetricTone.info => (
        colors.onSecondaryContainer,
        colors.secondaryContainer,
      ),
      _MetricTone.accent => (
        colors.onTertiaryContainer,
        colors.tertiaryContainer,
      ),
      _MetricTone.neutral => (
        colors.onSurfaceVariant,
        colors.surfaceContainerHigh,
      ),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 12 : 14, color: foreground),
            SizedBox(width: compact ? 4 : 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
              fontSize: compact ? 10 : null,
            ),
          ),
          SizedBox(width: compact ? 5 : 6),
          Text(
            value,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 11 : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentUsageEvents extends StatefulWidget {
  const _RecentUsageEvents({required this.events, required this.labels});

  final List<AiResourceUsageEvent> events;
  final Map<String, String> labels;

  @override
  State<_RecentUsageEvents> createState() => _RecentUsageEventsState();
}

class _RecentUsageEventsState extends State<_RecentUsageEvents> {
  int _page = 1;
  int _pageSize = kOpenHandTableDefaultPageSize;

  @override
  Widget build(BuildContext context) {
    final events = widget.events;
    if (events.isEmpty) {
      return _EmptyAnalytics(
        icon: Icons.history_rounded,
        label: openHandLocalizedText(
          context,
          zh: '当前窗口暂无详细调用记录',
          zhHant: '目前視窗暫無詳細呼叫記錄',
          en: 'No detailed calls in this window',
          fr: 'Aucun appel détaillé sur cette période',
          de: 'Keine detaillierten Aufrufe',
          ja: 'この集計範囲の詳細な記録はありません',
        ),
      );
    }
    final window = OpenHandPageWindow.normalize(
      page: _page,
      pageSize: _pageSize,
      total: events.length,
    );
    if (window.page != _page || window.pageSize != _pageSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _page = window.page;
            _pageSize = window.pageSize;
          });
        }
      });
    }
    final pageEvents = window.slice(events);
    return Column(
      children: [
        _BoundedAnalyticsList(
          key: ValueKey<(int, int)>((window.page, window.pageSize)),
          child: Column(
            children: [
              for (var index = 0; index < pageEvents.length; index++) ...[
                _UsageEventCard(
                  key: ValueKey<String>(pageEvents[index].eventId),
                  event: pageEvents[index],
                  labels: widget.labels,
                ),
                if (index != pageEvents.length - 1) kOpenHandGap9,
              ],
            ],
          ),
        ),
        if (events.length > 1) ...[
          kOpenHandGap12,
          OpenHandTablePagination(
            total: events.length,
            page: window.page,
            pageSize: window.pageSize,
            bar: true,
            onPageChanged: (page) => setState(() => _page = page),
            onPageSizeChanged: (size) => setState(() {
              _pageSize = size;
              _page = 1;
            }),
          ),
        ],
      ],
    );
  }
}

class _BoundedAnalyticsList extends StatefulWidget {
  const _BoundedAnalyticsList({super.key, required this.child});

  final Widget child;

  @override
  State<_BoundedAnalyticsList> createState() => _BoundedAnalyticsListState();
}

class _BoundedAnalyticsListState extends State<_BoundedAnalyticsList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = math.min(
      _kUsageListMaxHeight,
      MediaQuery.sizeOf(context).height * 0.48,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: OpenHandSafeScrollbar(
        controller: _controller,
        thumbVisibility: false,
        thickness: 5,
        radius: kOpenHandPillRadius,
        child: SingleChildScrollView(
          controller: _controller,
          primary: false,
          physics: openHandDialogAwareScrollPhysics(context),
          padding: const EdgeInsets.only(right: 8),
          child: widget.child,
        ),
      ),
    );
  }
}

class _UsageEventCard extends StatelessWidget {
  const _UsageEventCard({super.key, required this.event, required this.labels});

  final AiResourceUsageEvent event;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = openHandTableMetricRequestStatusColor(
      colors,
      event.status,
    );
    final resourceLabel = () {
      final mapped = labels[event.resourceId]?.trim() ?? '';
      return mapped.isEmpty ? event.resourceId : mapped;
    }();
    final subLabel = event.subResourceId.isEmpty
        ? ''
        : _subResourceDisplayLabel(context, event.subResourceId);
    final showResourceId = resourceLabel != event.resourceId;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(kOpenHandRadius17),
        border: Border.all(
          color: event.succeeded
              ? colors.outlineVariant
              : colors.error.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: event.succeeded
                      ? colors.primaryContainer
                      : colors.errorContainer,
                  borderRadius: BorderRadius.circular(kOpenHandRadius12),
                ),
                child: Icon(
                  event.succeeded
                      ? Icons.bolt_rounded
                      : Icons.error_outline_rounded,
                  size: 18,
                  color: event.succeeded
                      ? colors.onPrimaryContainer
                      : colors.onErrorContainer,
                ),
              ),
              kOpenHandHGap12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resourceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subLabel.isNotEmpty || showResourceId) ...[
                      kOpenHandGap3,
                      Text(
                        [
                          if (subLabel.isNotEmpty) subLabel,
                          if (showResourceId)
                            _shortIdentifier(event.resourceId),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              kOpenHandHGap9,
              OpenHandTableStatusBadge(
                label: _statusLabel(context, event.status),
                color: statusColor,
              ),
            ],
          ),
          kOpenHandGap11,
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetricPill(
                icon: Icons.schedule_rounded,
                label: _metricLastLabel(context),
                value: formatYearMonthDayHmsLocal(event.occurredAt),
                tone: _MetricTone.info,
                compact: true,
              ),
              _MetricPill(
                icon: Icons.timer_outlined,
                label: _metricLatencyLabel(context),
                value: _formatEventDuration(event.durationMs, event.source),
                tone: _MetricTone.accent,
                compact: true,
              ),
              _MetricPill(
                icon: Icons.forum_outlined,
                label: _metricSessionLabel(context),
                value: _shortIdentifier(event.sessionId),
                compact: true,
              ),
              if (event.source.isNotEmpty)
                _MetricPill(
                  icon: Icons.route_outlined,
                  label: _metricSourceLabel(context),
                  value: _usageSourceDisplayLabel(context, event.source),
                  tone: _MetricTone.success,
                  compact: true,
                ),
            ],
          ),
          if (event.argumentsSummary.trim().isNotEmpty)
            _UsageEventPayload(
              label: openHandLocalizedText(
                context,
                zh: '参数',
                zhHant: '參數',
                en: 'Arguments',
                fr: 'Arguments',
                de: 'Argumente',
                ja: '引数',
              ),
              value: event.argumentsSummary,
            ),
          if (event.errorSummary.trim().isNotEmpty)
            _UsageEventPayload(
              label: openHandErrorLabel(context),
              value: event.errorSummary,
              error: true,
            )
          else if (event.resultSummary.trim().isNotEmpty)
            _UsageEventPayload(
              label: openHandLocalizedText(
                context,
                zh: '结果',
                zhHant: '結果',
                en: 'Result',
                fr: 'Résultat',
                de: 'Ergebnis',
                ja: '結果',
              ),
              value: event.resultSummary,
            ),
          if (_hasUsageMetadata(event.metadataJson))
            _UsageEventPayload(
              label: openHandLocalizedText(
                context,
                zh: '元数据',
                zhHant: '元資料',
                en: 'Metadata',
                fr: 'Métadonnées',
                de: 'Metadaten',
                ja: 'メタデータ',
              ),
              value: event.metadataJson,
            ),
        ],
      ),
    );
  }
}

class _UsageEventPayload extends StatelessWidget {
  const _UsageEventPayload({
    required this.label,
    required this.value,
    this.error = false,
  });

  final String label;
  final String value;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: OpenHandJsonTreeView(
        text: value,
        label: label,
        error: error,
        logTag: 'resource_usage',
      ),
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
            kOpenHandGap10,
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
    AiResourceUsagePeriod.session => openHandSessionLabel(context),
    AiResourceUsagePeriod.day => openHandRecentUsageWindowLabel(
      context,
      OpenHandRecentUsageWindow.day,
    ),
    AiResourceUsagePeriod.week => openHandRecentUsageWindowLabel(
      context,
      OpenHandRecentUsageWindow.week,
    ),
    AiResourceUsagePeriod.month => openHandRecentUsageWindowLabel(
      context,
      OpenHandRecentUsageWindow.month,
    ),
    AiResourceUsagePeriod.quarter => openHandRecentUsageWindowLabel(
      context,
      OpenHandRecentUsageWindow.quarter,
    ),
    AiResourceUsagePeriod.year => openHandRecentUsageWindowLabel(
      context,
      OpenHandRecentUsageWindow.year,
    ),
  };
}

String _periodDescription(BuildContext context, AiResourceUsagePeriod period) {
  final label = _periodLabel(context, period);
  return openHandLocalizedText(
    context,
    zh: '$label的调用总量变化',
    zhHant: '$label的呼叫總量變化',
    en: 'Call volume · $label',
    fr: 'Volume d’appels · $label',
    de: 'Aufrufvolumen · $label',
    ja: '$labelの呼び出し数',
  );
}

bool _hasUsageMetadata(String value) {
  final trimmed = value.trim();
  return trimmed.isNotEmpty && trimmed != '{}' && trimmed != '[]';
}

String _shortBucket(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '—';
  if (trimmed.contains('~') || trimmed.length <= 14) return trimmed;
  final start = safeUtf16SuffixStart(trimmed, trimmed.length - 12);
  return '…${trimmed.substring(start)}';
}

String _shortIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 16) return trimmed;
  final start = safeUtf16SuffixStart(trimmed, trimmed.length - 14);
  return '…${trimmed.substring(start)}';
}

String _formatAverageDuration(num milliseconds, int sampleCount) {
  if (sampleCount <= 0 || !milliseconds.isFinite || milliseconds < 0) {
    return kOpenHandTableMetricEmpty;
  }
  return openHandTableMetricDuration(milliseconds);
}

String _formatEventDuration(int milliseconds, String source) {
  if (milliseconds <= 0 && source.trim().toLowerCase() == 'prompt') {
    return kOpenHandTableMetricEmpty;
  }
  return openHandTableMetricDuration(milliseconds);
}

String _metricSourceLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '来源',
    zhHant: '來源',
    en: 'Source',
    fr: 'Source',
    de: 'Quelle',
    ja: 'ソース',
  );
}

String _usageSourceDisplayLabel(BuildContext context, String source) {
  return switch (source.trim().toLowerCase()) {
    'prompt' => openHandLocalizedText(
      context,
      zh: '提示注入',
      zhHant: '提示注入',
      en: 'Prompt',
      fr: 'Prompt',
      de: 'Prompt',
      ja: 'プロンプト',
    ),
    _ => source.trim().isEmpty ? kOpenHandTableMetricEmpty : source.trim(),
  };
}

String _callUnitLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '次',
    zhHant: '次',
    en: 'x',
    fr: 'x',
    de: 'x',
    ja: '回',
  );
}

String _metricTotalLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '合计',
    zhHant: '合計',
    en: 'Total',
    fr: 'Total',
    de: 'Summe',
    ja: '合計',
  );
}

String _metricSuccessLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '成功',
    zhHant: '成功',
    en: 'OK',
    fr: 'OK',
    de: 'OK',
    ja: '成功',
  );
}

String _metricFailureLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '失败',
    zhHant: '失敗',
    en: 'Fail',
    fr: 'Échec',
    de: 'Fehler',
    ja: '失敗',
  );
}

String _metricRateLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '成功率',
    zhHant: '成功率',
    en: 'Rate',
    fr: 'Taux',
    de: 'Rate',
    ja: '成功率',
  );
}

String _metricLatencyLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '耗时',
    zhHant: '耗時',
    en: 'Latency',
    fr: 'Latence',
    de: 'Latenz',
    ja: '所要時間',
  );
}

String _metricSessionLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '会话',
    zhHant: '會話',
    en: 'Sessions',
    fr: 'Sessions',
    de: 'Sitzungen',
    ja: 'セッション',
  );
}

String _metricLastLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '最近',
    zhHant: '最近',
    en: 'Last',
    fr: 'Dernier',
    de: 'Zuletzt',
    ja: '最新',
  );
}

String _subResourceDisplayLabel(BuildContext context, String resourceId) {
  return switch (resourceId) {
    'prompt_context' => openHandLocalizedText(
      context,
      zh: '提示词注入',
      zhHant: '提示詞注入',
      en: 'Prompt context',
      fr: 'Contexte prompt',
      de: 'Prompt-Kontext',
      ja: 'プロンプト注入',
    ),
    'prompt_selection' => openHandLocalizedText(
      context,
      zh: '技能选择',
      zhHant: '技能選擇',
      en: 'Skill selection',
      fr: 'Sélection de skill',
      de: 'Skill-Auswahl',
      ja: 'スキル選択',
    ),
    _ => resourceId,
  };
}

String _statusLabel(BuildContext context, String status) {
  if (status == 'success') {
    return openHandLocalizedText(
      context,
      zh: '成功',
      zhHant: '成功',
      en: 'Success',
      fr: 'Réussi',
      de: 'Erfolgreich',
      ja: '成功',
    );
  }
  return switch (status) {
    'cancelled' => openHandCancelledLabel(context),
    'timed_out' => openHandTimedOutLabel(context),
    'denied' || 'rejected' => openHandLocalizedText(
      context,
      zh: '已拒绝',
      zhHant: '已拒絕',
      en: 'Denied',
      fr: 'Refusé',
      de: 'Abgelehnt',
      ja: '拒否',
    ),
    _ => openHandLocalizedText(
      context,
      zh: '失败',
      zhHant: '失敗',
      en: 'Failed',
      fr: 'Échoué',
      de: 'Fehlgeschlagen',
      ja: '失敗',
    ),
  };
}
