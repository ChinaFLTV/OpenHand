import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_ops_charts.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_table_metric_cells.dart';
import '../../../shared/ui/openhand_table_pagination.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/dependency_telemetry.dart';
import '../services_controller.dart';
import '../services_errors.dart';
import 'service_dialog_controls.dart';

const double _kMetricDialogWidth = 1120;
const double _kMetricDialogHeight = 860;
const double _kCompactBreakpoint = 720;
const double _kChartHeight = 224;
const double _kSectionGap = 18;

enum DependencyMetricKind {
  postgresqlCapacity,
  postgresqlConnections,
  postgresqlCache,
  postgresqlTransactions,
  redisMemory,
  redisKeyspace,
  redisThroughput,
  redisCache,
  redisClients,
  redisNetwork,
}

enum _MetricTimeRange { realtime, minutes15, hour1, hours24 }

extension on _MetricTimeRange {
  String get label => switch (this) {
    _MetricTimeRange.realtime => '实时',
    _MetricTimeRange.minutes15 => '15 分钟',
    _MetricTimeRange.hour1 => '1 小时',
    _MetricTimeRange.hours24 => '24 小时',
  };

  Duration get duration => switch (this) {
    _MetricTimeRange.realtime => const Duration(minutes: 5),
    _MetricTimeRange.minutes15 => const Duration(minutes: 15),
    _MetricTimeRange.hour1 => const Duration(hours: 1),
    _MetricTimeRange.hours24 => const Duration(hours: 24),
  };
}

extension on DependencyMetricKind {
  String get title => switch (this) {
    DependencyMetricKind.postgresqlCapacity => 'PostgreSQL 数据库容量',
    DependencyMetricKind.postgresqlConnections => 'PostgreSQL 活跃连接',
    DependencyMetricKind.postgresqlCache => 'PostgreSQL 缓存命中率',
    DependencyMetricKind.postgresqlTransactions => 'PostgreSQL 事务提交',
    DependencyMetricKind.redisMemory => 'Redis 内存占用',
    DependencyMetricKind.redisKeyspace => 'Redis 键空间',
    DependencyMetricKind.redisThroughput => 'Redis 实时吞吐',
    DependencyMetricKind.redisCache => 'Redis 缓存命中率',
    DependencyMetricKind.redisClients => 'Redis 客户端',
    DependencyMetricKind.redisNetwork => 'Redis 网络流量',
  };

  String get subtitle => switch (this) {
    DependencyMetricKind.postgresqlCapacity => '容量构成、增长速度与高占用对象',
    DependencyMetricKind.postgresqlConnections => '会话状态、连接容量与异常连接',
    DependencyMetricKind.postgresqlCache => '数据块与索引缓存的读取效率',
    DependencyMetricKind.postgresqlTransactions => '提交质量、吞吐和事务异常',
    DependencyMetricKind.redisMemory => '内存构成、碎片风险与大 Key',
    DependencyMetricKind.redisKeyspace => '数据类型、TTL 与 Key 生命周期',
    DependencyMetricKind.redisThroughput => '命令速率、耗时和慢命令',
    DependencyMetricKind.redisCache => '请求命中表现与低命中维度',
    DependencyMetricKind.redisClients => '连接状态、来源与异常客户端',
    DependencyMetricKind.redisNetwork => '双向速率、带宽峰值与流量异常',
  };

  IconData get icon => switch (this) {
    DependencyMetricKind.postgresqlCapacity => Icons.storage_rounded,
    DependencyMetricKind.postgresqlConnections => Icons.lan_outlined,
    DependencyMetricKind.postgresqlCache => Icons.speed_rounded,
    DependencyMetricKind.postgresqlTransactions => Icons.commit_rounded,
    DependencyMetricKind.redisMemory => Icons.memory_rounded,
    DependencyMetricKind.redisKeyspace => Icons.key_rounded,
    DependencyMetricKind.redisThroughput => Icons.speed_rounded,
    DependencyMetricKind.redisCache => Icons.track_changes_rounded,
    DependencyMetricKind.redisClients => Icons.group_outlined,
    DependencyMetricKind.redisNetwork => Icons.swap_vert_circle_outlined,
  };

  Color tone(ColorScheme colors) => switch (this) {
    DependencyMetricKind.postgresqlCapacity ||
    DependencyMetricKind.redisMemory => OpenHandStatusColors.success,
    DependencyMetricKind.postgresqlConnections ||
    DependencyMetricKind.redisKeyspace => colors.primary,
    DependencyMetricKind.postgresqlCache => colors.secondary,
    DependencyMetricKind.redisThroughput => OpenHandStatusColors.info,
    DependencyMetricKind.postgresqlTransactions => colors.primary,
    DependencyMetricKind.redisCache => colors.tertiary,
    DependencyMetricKind.redisClients => colors.secondary,
    DependencyMetricKind.redisNetwork => const Color(0xff0f766e),
  };
}

Future<void> showDependencyMetricDetailDialog(
  BuildContext context, {
  required DependencyMetricKind kind,
  required List<Map<String, Object?>> postgresqlTables,
  required List<Map<String, Object?>> redisRecords,
  required Future<void> Function() onReload,
}) => showAnimatedDialog<void>(
  context: context,
  builder: (dialogContext) {
    final colors = Theme.of(dialogContext).colorScheme;
    return buildOpenHandResponsiveDialogShell(
      context: dialogContext,
      maxWidth: _kMetricDialogWidth,
      maxHeight: _kMetricDialogHeight,
      minAvailableWidth: 300,
      minAvailableHeight: 420,
      horizontalMargin: 28,
      verticalMargin: 72,
      expandToMax: true,
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: kOpenHandBorderRadius26,
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.42)),
      ),
      child: ServiceDialogInteractionTheme(
        child: _DependencyMetricDetailDialog(
          kind: kind,
          postgresqlTables: postgresqlTables,
          redisRecords: redisRecords,
          onReload: onReload,
        ),
      ),
    );
  },
);

class _DependencyMetricDetailDialog extends StatefulWidget {
  const _DependencyMetricDetailDialog({
    required this.kind,
    required this.postgresqlTables,
    required this.redisRecords,
    required this.onReload,
  });

  final DependencyMetricKind kind;
  final List<Map<String, Object?>> postgresqlTables;
  final List<Map<String, Object?>> redisRecords;
  final Future<void> Function() onReload;

  @override
  State<_DependencyMetricDetailDialog> createState() =>
      _DependencyMetricDetailDialogState();
}

class _DependencyMetricDetailDialogState
    extends State<_DependencyMetricDetailDialog> {
  _MetricTimeRange _range = _MetricTimeRange.minutes15;
  bool _reloading = false;
  String? _reloadError;

  Future<void> _reload() async {
    if (_reloading) return;
    setState(() {
      _reloading = true;
      _reloadError = null;
    });
    try {
      await widget.onReload();
      if (!mounted) return;
      final controller = context.read<ServicesController>();
      if (controller.dependencyDataOverviewError != null) {
        setState(() => _reloadError = controller.dependencyDataOverviewError);
      }
    } catch (error, stack) {
      final message = reportServicesFailure(
        'dependency_metric_detail_dialog',
        '刷新依赖指标',
        error,
        stack,
        fallback: '依赖指标刷新失败，请稍后重试。',
      );
      if (mounted) setState(() => _reloadError = message);
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = context.select<ServicesController, Map<String, Object?>>(
      (controller) => controller.dependencyDataOverview,
    );
    final overviewError = context.select<ServicesController, String?>(
      (controller) => controller.dependencyDataOverviewError,
    );
    final samples = context
        .read<ServicesController>()
        .dependencyTelemetryHistory
        .where(
          (sample) => !sample.capturedAt.isBefore(
            DateTime.now().subtract(_range.duration),
          ),
        )
        .toList(growable: false);
    final colors = Theme.of(context).colorScheme;
    final tone = widget.kind.tone(colors);
    final error = _reloadError ?? overviewError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricDialogHeader(
          kind: widget.kind,
          tone: tone,
          reloading: _reloading,
          onReload: _reload,
        ),
        _MetricRangeBar(
          selected: _range,
          capturedAt: _capturedAt(overview),
          onChanged: (range) => setState(() => _range = range),
        ),
        SizedBox(
          height: 3,
          child: _reloading
              ? LinearProgressIndicator(
                  color: tone,
                  backgroundColor: tone.withValues(alpha: 0.12),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest.withValues(alpha: 0.72),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: overview.isEmpty
                  ? _MetricLoadState(
                      loading: _reloading,
                      error: error,
                      onReload: _reload,
                    )
                  : SingleChildScrollView(
                      physics: openHandDialogAwareScrollPhysics(context),
                      child: _buildMetricContent(
                        context,
                        overview: overview,
                        samples: samples,
                        tone: tone,
                        error: error,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricContent(
    BuildContext context, {
    required Map<String, Object?> overview,
    required List<DependencyTelemetrySample> samples,
    required Color tone,
    required String? error,
  }) {
    final postgresql = _objectMap(overview['postgresql']);
    final telemetry = _objectMap(postgresql['telemetry']);
    final redis = _objectMap(overview['redis']);
    final warning = error == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _InlineNotice(
              icon: Icons.sync_problem_rounded,
              label: '最近一次刷新失败，当前展示上次成功数据。',
              color: Theme.of(context).colorScheme.error,
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        warning,
        switch (widget.kind) {
          DependencyMetricKind.postgresqlCapacity => _postgresqlCapacity(
            context,
            telemetry: telemetry,
            tables: widget.postgresqlTables.isEmpty
                ? _objectMaps(postgresql['tables'])
                : widget.postgresqlTables,
            samples: samples,
            tone: tone,
          ),
          DependencyMetricKind.postgresqlConnections => _postgresqlConnections(
            context,
            postgresql: postgresql,
            telemetry: telemetry,
            samples: samples,
            tone: tone,
          ),
          DependencyMetricKind.postgresqlCache => _postgresqlCache(
            context,
            telemetry: telemetry,
            samples: samples,
            tone: tone,
          ),
          DependencyMetricKind.postgresqlTransactions =>
            _postgresqlTransactions(
              context,
              telemetry: telemetry,
              samples: samples,
              tone: tone,
            ),
          DependencyMetricKind.redisMemory => _redisMemory(
            context,
            redis: redis,
            records: widget.redisRecords,
            samples: samples,
            tone: tone,
          ),
          DependencyMetricKind.redisKeyspace => _redisKeyspace(
            context,
            redis: redis,
            records: widget.redisRecords,
            samples: samples,
            tone: tone,
          ),
          DependencyMetricKind.redisThroughput => _redisThroughput(
            context,
            redis: redis,
            samples: samples,
            tone: tone,
          ),
          DependencyMetricKind.redisCache => _redisCache(
            context,
            redis: redis,
            samples: samples,
            tone: tone,
          ),
          DependencyMetricKind.redisClients => _redisClients(
            context,
            redis: redis,
            samples: samples,
            tone: tone,
          ),
          DependencyMetricKind.redisNetwork => _redisNetwork(
            context,
            redis: redis,
            samples: samples,
            tone: tone,
          ),
        },
      ],
    );
  }

  Widget _postgresqlCapacity(
    BuildContext context, {
    required Map<String, Object?> telemetry,
    required List<Map<String, Object?>> tables,
    required List<DependencyTelemetrySample> samples,
    required Color tone,
  }) {
    final databaseBytes = _integer(telemetry['databaseSizeBytes']);
    final tableBytes =
        _integerOrNull(telemetry['tableDataBytes']) ??
        tables.fold<int>(0, (sum, table) => sum + _integer(table['dataBytes']));
    final indexBytes =
        _integerOrNull(telemetry['indexBytes']) ??
        tables.fold<int>(
          0,
          (sum, table) =>
              sum +
              (_integerOrNull(table['indexBytes']) ??
                  math.max(
                    0,
                    _integer(table['totalBytes']) -
                        _integer(table['dataBytes']),
                  )),
        );
    final toastBytes = _integer(telemetry['toastBytes']);
    final temporaryBytes = _integer(telemetry['temporaryBytes']);
    final knownBytes = tableBytes + indexBytes + toastBytes + temporaryBytes;
    final otherBytes = math.max(0, databaseBytes - knownBytes);
    final databaseTrend = _sampleValues(
      samples,
      (sample) => _integer(
        _postgresqlTelemetry(sample.overview)['databaseSizeBytes'],
      ).toDouble(),
    );
    final growthPerSecond =
        _seriesRate(samples, (sample) {
          return _integer(
            _postgresqlTelemetry(sample.overview)['databaseSizeBytes'],
          );
        }).lastOrNull ??
        0;
    final capacityLimit = _integer(telemetry['tablespaceCapacityBytes']);
    final remaining = capacityLimit > databaseBytes
        ? capacityLimit - databaseBytes
        : 0;
    final objectRows = <_RankRow>[];
    for (final table in tables) {
      final total = _integer(table['totalBytes']);
      final data = _integer(table['dataBytes']);
      final index =
          _integerOrNull(table['indexBytes']) ?? math.max(0, total - data);
      objectRows.add(
        _RankRow(
          cells: <String>[
            '${table['name'] ?? '--'}',
            '表',
            formatByteSize(data),
            formatByteSize(total),
          ],
          value: total.toDouble(),
        ),
      );
      if (index > 0) {
        objectRows.add(
          _RankRow(
            cells: <String>[
              '${table['name'] ?? '--'}',
              table['indexBytes'] == null ? '索引及 TOAST' : '索引',
              formatByteSize(index),
              '--',
            ],
            value: index.toDouble(),
          ),
        );
      }
    }
    objectRows.sort((left, right) => right.value.compareTo(left.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KpiStrip(
          items: [
            _KpiItem(
              '总容量',
              formatByteSize(databaseBytes),
              Icons.storage_rounded,
            ),
            _KpiItem(
              '表数据',
              formatByteSize(tableBytes),
              Icons.table_rows_rounded,
            ),
            _KpiItem(
              '索引',
              formatByteSize(indexBytes),
              Icons.account_tree_outlined,
            ),
            _KpiItem(
              '临时文件',
              formatByteSize(temporaryBytes),
              Icons.pending_actions_outlined,
            ),
          ],
          tone: tone,
          interactive: false,
          singleRow: true,
        ),
        const SizedBox(height: _kSectionGap),
        _AdaptivePair(
          primaryFlex: 3,
          secondaryFlex: 2,
          primary: _MetricSection(
            title: '容量增长',
            subtitle: '${_range.label} · 数据库总容量',
            icon: Icons.show_chart_rounded,
            child: _InteractiveTrendChart(
              times: _sampleTimes(samples),
              series: [
                OpenHandChartSeries(
                  label: '数据库容量',
                  values: databaseTrend,
                  color: tone,
                ),
              ],
              unit: '容量',
              area: true,
              formatValue: (value) => formatByteSize(value.round()),
            ),
          ),
          secondary: _MetricSection(
            title: '容量构成',
            subtitle: '按存储用途拆分',
            icon: Icons.donut_large_rounded,
            child: _DonutBreakdown(
              values: <_BreakdownItem>[
                _BreakdownItem('表数据', tableBytes, tone),
                _BreakdownItem(
                  '索引',
                  indexBytes,
                  Theme.of(context).colorScheme.primary,
                ),
                _BreakdownItem(
                  'TOAST',
                  toastBytes,
                  Theme.of(context).colorScheme.tertiary,
                ),
                _BreakdownItem(
                  '临时文件',
                  temporaryBytes,
                  OpenHandStatusColors.warning,
                ),
                _BreakdownItem(
                  '其他',
                  otherBytes,
                  Theme.of(context).colorScheme.outline,
                ),
              ],
              centerLabel: formatByteSize(databaseBytes),
            ),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '高占用对象',
          subtitle: '当前接口可见的表与索引，按占用倒序',
          icon: Icons.leaderboard_outlined,
          trailing: _StatusTag(label: '${objectRows.length} 个对象', color: tone),
          child: _RankTable(
            headers: const ['对象名称', '类型', '对象大小', '总占用'],
            rows: objectRows,
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '增长与余量判断',
          subtitle: '根据当前时间范围内的真实容量样本计算',
          icon: Icons.query_stats_rounded,
          child: _OperationalSummary(
            interactive: false,
            items: [
              _SummaryItem(
                '当前增长速度',
                databaseTrend.length < 2
                    ? '等待第二个采样点'
                    : '${formatByteSize(growthPerSecond.round())}/s',
                growthPerSecond > 0 ? OpenHandStatusColors.warning : tone,
              ),
              _SummaryItem(
                '剩余容量',
                capacityLimit <= 0 ? '接口暂未提供表空间上限' : formatByteSize(remaining),
                capacityLimit > 0 && remaining < databaseBytes ~/ 5
                    ? Theme.of(context).colorScheme.error
                    : tone,
              ),
              _SummaryItem(
                '膨胀率',
                telemetry['bloatRatio'] == null
                    ? '接口暂未提供对象膨胀统计'
                    : _percent(_number(telemetry['bloatRatio'])),
                OpenHandStatusColors.info,
              ),
              _SummaryItem(
                '增长最快对象',
                _fastestGrowingTable(samples) ?? '等待对象级历史样本',
                Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _postgresqlConnections(
    BuildContext context, {
    required Map<String, Object?> postgresql,
    required Map<String, Object?> telemetry,
    required List<DependencyTelemetrySample> samples,
    required Color tone,
  }) {
    final states = _stringIntMap(telemetry['connectionStates']);
    final active = _integer(telemetry['activeConnections']);
    final poolSize = _integer(postgresql['poolSize']);
    final idle = _integer(postgresql['idleConnections']);
    final waiting = states['等待'] ?? states['waiting'] ?? 0;
    final blocked = states['阻塞'] ?? states['blocked'] ?? 0;
    final idleInTransaction =
        states['事务中空闲'] ?? states['idle in transaction'] ?? 0;
    final maxConnections = _integer(telemetry['maxConnections']);
    final peak = _sampleValues(
      samples,
      (sample) => _integer(
        _postgresqlTelemetry(sample.overview)['activeConnections'],
      ).toDouble(),
    ).fold<double>(active.toDouble(), math.max);
    final sessions = _objectMaps(telemetry['sessions']);
    final longSessions = sessions
        .where((session) {
          return _integer(session['durationSeconds']) >= 60 ||
              session['blocked'] == true ||
              '${session['waitEvent'] ?? ''}'.isNotEmpty;
        })
        .toList(growable: false);
    final sourceDistribution = _stringIntMap(
      telemetry['connectionsByApplication'],
    );
    if (sourceDistribution.isEmpty && poolSize > 0) {
      sourceDistribution['OpenHand 连接池'] = poolSize;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ConnectionCapacityHero(
          active: active,
          maximum: maxConnections,
          poolSize: poolSize,
          peak: peak.round(),
          tone: tone,
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '连接状态分布',
          subtitle: '突出等待、阻塞与事务中空闲连接',
          icon: Icons.hub_outlined,
          child: _StackedStatusBand(
            values: [
              _BreakdownItem('活跃', active, OpenHandStatusColors.success),
              _BreakdownItem('空闲', idle, tone),
              _BreakdownItem(
                '事务中空闲',
                idleInTransaction,
                OpenHandStatusColors.warning,
              ),
              _BreakdownItem(
                '等待',
                waiting,
                Theme.of(context).colorScheme.tertiary,
              ),
              _BreakdownItem(
                '阻塞',
                blocked,
                Theme.of(context).colorScheme.error,
              ),
            ],
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _AdaptivePair(
          primaryFlex: 2,
          primary: _MetricSection(
            title: '连接变化',
            subtitle: '${_range.label} · 活跃与连接池空闲',
            icon: Icons.stacked_line_chart_rounded,
            child: _InteractiveTrendChart(
              times: _sampleTimes(samples),
              series: [
                OpenHandChartSeries(
                  label: '活跃',
                  values: _sampleValues(
                    samples,
                    (sample) => _integer(
                      _postgresqlTelemetry(
                        sample.overview,
                      )['activeConnections'],
                    ).toDouble(),
                  ),
                  color: OpenHandStatusColors.success,
                ),
                OpenHandChartSeries(
                  label: '空闲',
                  values: _sampleValues(
                    samples,
                    (sample) => _integer(
                      _objectMap(
                        sample.overview['postgresql'],
                      )['idleConnections'],
                    ).toDouble(),
                  ),
                  color: tone,
                ),
                OpenHandChartSeries(
                  label: '阻塞',
                  values: _sampleValues(
                    samples,
                    (sample) => _integer(
                      _postgresqlTelemetry(
                        sample.overview,
                      )['blockedConnections'],
                    ).toDouble(),
                  ),
                  color: Theme.of(context).colorScheme.error,
                ),
              ],
              unit: '个',
              formatValue: (value) => '${value.round()} 个',
            ),
          ),
          secondary: _MetricSection(
            title: '应用来源',
            subtitle: '按 application_name 聚合',
            icon: Icons.apps_rounded,
            child: _HorizontalBars(
              values: sourceDistribution,
              color: tone,
              emptyLabel: '接口暂未提供连接来源',
              valueLabel: (value) => '$value 个',
            ),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '需关注会话',
          subtitle: '长事务、慢会话、等待和阻塞连接',
          icon: Icons.manage_search_rounded,
          trailing: _StatusTag(
            label: longSessions.isEmpty
                ? '当前无异常'
                : '${longSessions.length} 个异常',
            color: longSessions.isEmpty
                ? OpenHandStatusColors.success
                : OpenHandStatusColors.warning,
          ),
          child: _RankTable(
            headers: const ['进程', '用户 / 应用', '状态', '等待 / 时长'],
            emptyLabel: '当前接口未返回异常会话，或暂无异常连接',
            rows: longSessions
                .map(
                  (session) => _RankRow(
                    cells: [
                      '${session['pid'] ?? '--'}',
                      '${session['user'] ?? '--'} / ${session['application'] ?? '--'}',
                      '${session['state'] ?? '--'}',
                      '${session['waitEvent'] ?? '无等待'} / ${_durationText(_integer(session['durationSeconds']))}',
                    ],
                    cellWidgets: [
                      null,
                      null,
                      OpenHandTableStatusBadge(
                        label:
                            '${session['state'] ?? kOpenHandTableMetricEmpty}',
                        color: _sessionStateColor(
                          context,
                          '${session['state'] ?? ''}',
                        ),
                      ),
                      null,
                    ],
                    value: _integer(session['durationSeconds']).toDouble(),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _postgresqlCache(
    BuildContext context, {
    required Map<String, Object?> telemetry,
    required List<DependencyTelemetrySample> samples,
    required Color tone,
  }) {
    final hits = _integer(telemetry['blocksHit']);
    final reads = _integer(telemetry['blocksRead']);
    final blockRate = dependencySafeRatio(hits, hits + reads);
    final indexHits = _integer(telemetry['indexBlocksHit']);
    final indexReads = _integer(telemetry['indexBlocksRead']);
    final indexRate = indexHits + indexReads == 0
        ? null
        : dependencySafeRatio(indexHits, indexHits + indexReads);
    final objects = _objectMaps(telemetry['lowCacheObjects']);
    final sharedBuffers = _integer(telemetry['sharedBuffersBytes']);
    final bufferUsed = _integer(telemetry['sharedBuffersUsedBytes']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _RadialMeter(
                label: '数据块命中率',
                value: blockRate,
                color: tone,
                helper:
                    '命中 ${_compactCount(hits)} · 磁盘读取 ${_compactCount(reads)}',
              ),
            ),
            kOpenHandHGap14,
            Expanded(
              child: _RadialMeter(
                label: '索引命中率',
                value: indexRate ?? 0,
                color: Theme.of(context).colorScheme.tertiary,
                helper: indexRate == null
                    ? '接口暂未提供索引块统计'
                    : '命中 ${_compactCount(indexHits)} · 读取 ${_compactCount(indexReads)}',
                unavailable: indexRate == null,
              ),
            ),
          ],
        ),
        const SizedBox(height: _kSectionGap),
        _AdaptivePair(
          primaryFlex: 3,
          secondaryFlex: 2,
          primary: _MetricSection(
            title: '命中率趋势',
            subtitle: '${_range.label} · 数据块与索引分开观察',
            icon: Icons.multiline_chart_rounded,
            child: _InteractiveTrendChart(
              times: _sampleTimes(samples),
              series: [
                OpenHandChartSeries(
                  label: '数据块',
                  values: _sampleValues(samples, (sample) {
                    final current = _postgresqlTelemetry(sample.overview);
                    final currentHits = _integer(current['blocksHit']);
                    final currentReads = _integer(current['blocksRead']);
                    return dependencySafeRatio(
                          currentHits,
                          currentHits + currentReads,
                        ) *
                        100;
                  }),
                  color: tone,
                ),
                OpenHandChartSeries(
                  label: '索引',
                  values: _sampleValues(samples, (sample) {
                    final current = _postgresqlTelemetry(sample.overview);
                    final currentHits = _integer(current['indexBlocksHit']);
                    final currentReads = _integer(current['indexBlocksRead']);
                    return dependencySafeRatio(
                          currentHits,
                          currentHits + currentReads,
                        ) *
                        100;
                  }),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ],
              unit: '%',
              fixedMaximum: 100,
              formatValue: (value) => '${value.toStringAsFixed(1)}%',
            ),
          ),
          secondary: _MetricSection(
            title: '命中与磁盘读取',
            subtitle: '累计数据块请求构成',
            icon: Icons.compare_arrows_rounded,
            child: _VerticalComparison(
              items: [
                _BreakdownItem('缓存命中', hits, tone),
                _BreakdownItem('磁盘读取', reads, OpenHandStatusColors.warning),
              ],
              valueLabel: _compactCount,
            ),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '共享缓冲区',
          subtitle: '使用率与可用容量',
          icon: Icons.memory_outlined,
          child: sharedBuffers <= 0
              ? const _InlineUnavailable(label: '当前接口暂未提供 shared_buffers 使用明细')
              : _UsageRail(
                  label:
                      '${formatByteSize(bufferUsed)} / ${formatByteSize(sharedBuffers)}',
                  value: dependencySafeRatio(bufferUsed, sharedBuffers),
                  color: tone,
                ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '低命中对象与读取热点',
          subtitle: '按对象命中率升序，优先排查磁盘读取热点',
          icon: Icons.crisis_alert_outlined,
          child: _RankTable(
            headers: const ['对象', '类型', '命中率', '磁盘读取'],
            emptyLabel: '当前接口暂未提供表和索引级缓存统计',
            rows: objects
                .map(
                  (item) => _RankRow(
                    cells: [
                      '${item['name'] ?? '--'}',
                      '${item['type'] ?? '--'}',
                      _percent(_normalizedRatio(item['hitRate'])),
                      _compactCount(_integer(item['blocksRead'])),
                    ],
                    value: 1 - _normalizedRatio(item['hitRate']),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _postgresqlTransactions(
    BuildContext context, {
    required Map<String, Object?> telemetry,
    required List<DependencyTelemetrySample> samples,
    required Color tone,
  }) {
    final commits = _integer(telemetry['transactionsCommitted']);
    final rollbacks = _integer(telemetry['transactionsRolledBack']);
    final deadlocks = _integer(telemetry['deadlocks']);
    final conflicts = _integer(telemetry['conflicts']);
    final commitRates = _seriesRate(
      samples,
      (sample) => _integer(
        _postgresqlTelemetry(sample.overview)['transactionsCommitted'],
      ),
    );
    final rollbackRates = _seriesRate(
      samples,
      (sample) => _integer(
        _postgresqlTelemetry(sample.overview)['transactionsRolledBack'],
      ),
    );
    final peakTps = math.max(
      commitRates.fold<double>(0, math.max),
      rollbackRates.fold<double>(0, math.max),
    );
    final durationBuckets = _stringIntMap(
      telemetry['transactionDurationBuckets'],
    );
    final failures = _objectMaps(telemetry['transactionExceptions']);
    final anomalyRows = _postgresqlTransactionAnomalies(samples);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KpiStrip(
          items: [
            _KpiItem('提交', _compactCount(commits), Icons.task_alt_rounded),
            _KpiItem('回滚', _compactCount(rollbacks), Icons.undo_rounded),
            _KpiItem('死锁', _compactCount(deadlocks), Icons.link_off_rounded),
            _KpiItem(
              '冲突',
              _compactCount(conflicts),
              Icons.warning_amber_rounded,
            ),
            _KpiItem(
              '窗口峰值',
              '${peakTps.toStringAsFixed(1)} TPS',
              Icons.bolt_rounded,
            ),
          ],
          tone: tone,
          interactive: false,
          singleRow: true,
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '提交与回滚速率',
          subtitle: '${_range.label} · 由累计计数器差值换算，计数器重置不计入峰值',
          icon: Icons.swap_calls_rounded,
          trailing: _StatusTag(
            label:
                '提交率 ${_percent(dependencySafeRatio(commits, commits + rollbacks))}',
            color: rollbacks > commits ~/ 20
                ? OpenHandStatusColors.warning
                : OpenHandStatusColors.success,
          ),
          child: _InteractiveTrendChart(
            times: _sampleTimes(samples),
            series: [
              OpenHandChartSeries(
                label: '提交',
                values: commitRates,
                color: OpenHandStatusColors.success,
              ),
              OpenHandChartSeries(
                label: '回滚',
                values: rollbackRates,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
            unit: 'TPS',
            area: true,
            formatValue: (value) => '${value.toStringAsFixed(1)} TPS',
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _AdaptivePair(
          primary: _MetricSection(
            title: '事务耗时区间',
            subtitle: '当前活动事务按耗时分桶',
            icon: Icons.bar_chart_rounded,
            child: _HorizontalBars(
              values: durationBuckets,
              color: tone,
              emptyLabel: '当前接口暂未提供事务耗时分布',
              valueLabel: (value) => '$value 个',
            ),
          ),
          secondary: _MetricSection(
            title: '异常发生时间',
            subtitle: '窗口内回滚与死锁计数变化',
            icon: Icons.history_toggle_off_rounded,
            child: _AnomalyTimeline(
              rows: anomalyRows,
              emptyLabel: samples.length < 2 ? '等待更多遥测样本' : '窗口内未发现新增异常',
            ),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '长事务、失败事务与死锁明细',
          subtitle: '最近异常事务，按发生时间倒序',
          icon: Icons.receipt_long_outlined,
          child: _RankTable(
            headers: const ['时间', '类型', '会话 / 用户', '耗时 / 原因'],
            emptyLabel: '当前接口暂未返回事务异常明细',
            rows: failures
                .map(
                  (item) => _RankRow(
                    cells: [
                      _dateTimeText(item['occurredAt']),
                      '${item['type'] ?? '--'}',
                      '${item['session'] ?? item['user'] ?? '--'}',
                      '${item['durationMs'] == null ? '--' : '${_integer(item['durationMs'])} ms'} / ${item['reason'] ?? '--'}',
                    ],
                    value: _integer(item['durationMs']).toDouble(),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _redisMemory(
    BuildContext context, {
    required Map<String, Object?> redis,
    required List<Map<String, Object?>> records,
    required List<DependencyTelemetrySample> samples,
    required Color tone,
  }) {
    final used = _integer(redis['usedMemoryBytes']);
    final rss = _integer(redis['usedMemoryRssBytes']);
    final peak = _integer(redis['peakMemoryBytes']);
    final dataset = _integerOrNull(redis['datasetMemoryBytes']) ?? used;
    final overhead = _integer(redis['overheadMemoryBytes']);
    final maxMemory = _integer(redis['maxMemoryBytes']);
    final fragmentation = _number(redis['memoryFragmentationRatio']);
    final evicted = _integer(redis['evictedKeys']);
    final usedTrend = _sampleValues(
      samples,
      (sample) => _integer(
        _redisOverview(sample.overview)['usedMemoryBytes'],
      ).toDouble(),
    );
    final rssTrend = _sampleValues(
      samples,
      (sample) => _integer(
        _redisOverview(sample.overview)['usedMemoryRssBytes'],
      ).toDouble(),
    );
    final growthRate = _lastValue(
      _seriesRate(
        samples,
        (sample) =>
            _integer(_redisOverview(sample.overview)['usedMemoryBytes']),
      ),
    );
    final remaining = maxMemory > used ? maxMemory - used : 0;
    final secondsToLimit = growthRate > 0 && remaining > 0
        ? remaining / growthRate
        : 0;
    final risk = maxMemory > 0
        ? dependencySafeRatio(used, maxMemory)
        : fragmentation >= 1.5
        ? 0.72
        : fragmentation >= 1.2
        ? 0.48
        : 0.22;
    final sortedRecords = [...records]
      ..sort(
        (left, right) =>
            _integer(right['sizeBytes']).compareTo(_integer(left['sizeBytes'])),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MemoryRiskHero(
          used: used,
          maximum: maxMemory,
          fragmentation: fragmentation,
          risk: risk,
          tone: tone,
        ),
        const SizedBox(height: _kSectionGap),
        _AdaptivePair(
          primaryFlex: 3,
          secondaryFlex: 2,
          primary: _MetricSection(
            title: '内存趋势',
            subtitle: '${_range.label} · 已使用内存与 RSS',
            icon: Icons.area_chart_rounded,
            child: _InteractiveTrendChart(
              times: _sampleTimes(samples),
              series: [
                OpenHandChartSeries(
                  label: '已使用',
                  values: usedTrend,
                  color: tone,
                ),
                OpenHandChartSeries(
                  label: 'RSS',
                  values: rssTrend,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ],
              unit: '容量',
              area: true,
              formatValue: (value) => formatByteSize(value.round()),
            ),
          ),
          secondary: _MetricSection(
            title: '内存构成',
            subtitle: '数据集、开销与未归类占用',
            icon: Icons.pie_chart_outline_rounded,
            child: _DonutBreakdown(
              values: [
                _BreakdownItem('数据集', math.min(dataset, used), tone),
                _BreakdownItem(
                  '运行开销',
                  math.min(overhead, math.max(0, used - dataset)),
                  Theme.of(context).colorScheme.primary,
                ),
                _BreakdownItem(
                  '未归类',
                  math.max(0, used - dataset - overhead),
                  Theme.of(context).colorScheme.outline,
                ),
              ],
              centerLabel: formatByteSize(used),
            ),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _KpiStrip(
          items: [
            _KpiItem(
              'RSS',
              rss <= 0 ? '暂未接入' : formatByteSize(rss),
              Icons.memory_outlined,
            ),
            _KpiItem('峰值内存', formatByteSize(peak), Icons.flag_outlined),
            _KpiItem('数据集内存', formatByteSize(dataset), Icons.dataset_outlined),
            _KpiItem(
              '碎片率',
              fragmentation.toStringAsFixed(2),
              Icons.grid_view_rounded,
            ),
            _KpiItem(
              '累计淘汰',
              _compactCount(evicted),
              Icons.delete_sweep_outlined,
            ),
          ],
          tone: tone,
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '大 Key 排行',
          subtitle: '当前已加载 Key 样本，按序列化大小倒序',
          icon: Icons.vertical_align_top_rounded,
          trailing: _StatusTag(label: '${records.length} 个样本', color: tone),
          child: _RankTable(
            headers: const ['Key', '类型', '占用', 'TTL'],
            emptyLabel: '当前命名空间暂无 Key',
            rows: sortedRecords
                .map(
                  (record) => _RankRow(
                    cells: [
                      '${record['key'] ?? '--'}',
                      '${record['type'] ?? '--'}',
                      formatByteSize(_integer(record['sizeBytes'])),
                      _ttlText(_integer(record['ttlSeconds'])),
                    ],
                    value: _integer(record['sizeBytes']).toDouble(),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '上限趋势预测',
          subtitle: '只使用当前窗口内相邻真实采样点的增长速度',
          icon: Icons.trending_up_rounded,
          child: _OperationalSummary(
            items: [
              _SummaryItem(
                '内存上限使用率',
                maxMemory <= 0 ? '未设置 maxmemory' : _percent(risk),
                risk >= 0.85
                    ? Theme.of(context).colorScheme.error
                    : risk >= 0.7
                    ? OpenHandStatusColors.warning
                    : OpenHandStatusColors.success,
              ),
              _SummaryItem(
                '窗口增长速度',
                samples.length < 2
                    ? '等待第二个采样点'
                    : '${formatByteSize(growthRate.round())}/s',
                growthRate > 0 ? OpenHandStatusColors.warning : tone,
              ),
              _SummaryItem(
                '预计达到上限',
                maxMemory <= 0
                    ? '未设置内存上限'
                    : secondsToLimit <= 0
                    ? '当前趋势不会达到上限'
                    : _durationText(secondsToLimit.round()),
                secondsToLimit > 0 && secondsToLimit < 3600
                    ? Theme.of(context).colorScheme.error
                    : tone,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _redisKeyspace(
    BuildContext context, {
    required Map<String, Object?> redis,
    required List<Map<String, Object?>> records,
    required List<DependencyTelemetrySample> samples,
    required Color tone,
  }) {
    final keyCount = _integer(redis['keyCount']);
    final expired = _integer(redis['expiredKeys']);
    final evicted = _integer(redis['evictedKeys']);
    final expiringInSample = records
        .where((record) => _integer(record['ttlSeconds']) > 0)
        .length;
    final persistentInSample = records
        .where((record) => _integer(record['ttlSeconds']) < 0)
        .length;
    final types = <String, int>{};
    for (final record in records) {
      final type = '${record['type'] ?? '未知'}';
      types[type] = (types[type] ?? 0) + 1;
    }
    final ttlBuckets = <String, int>{
      '即将过期 < 1 分钟': 0,
      '1 分钟 - 1 小时': 0,
      '1 - 24 小时': 0,
      '大于 24 小时': 0,
      '永久': 0,
    };
    for (final record in records) {
      final ttl = _integer(record['ttlSeconds']);
      final bucket = ttl < 0
          ? '永久'
          : ttl < Duration.secondsPerMinute
          ? '即将过期 < 1 分钟'
          : ttl < Duration.secondsPerHour
          ? '1 分钟 - 1 小时'
          : ttl < Duration.secondsPerDay
          ? '1 - 24 小时'
          : '大于 24 小时';
      ttlBuckets[bucket] = ttlBuckets[bucket]! + 1;
    }
    final keyspaces = _objectMaps(redis['keyspaces']);
    final displayKeyspaces = keyspaces.isEmpty
        ? <Map<String, Object?>>[
            <String, Object?>{
              'database': 'db0',
              'keys': keyCount,
              'expires': expiringInSample,
              'averageTtlMs': null,
            },
          ]
        : keyspaces;
    final sortedBySize = [...records]
      ..sort(
        (left, right) =>
            _integer(right['sizeBytes']).compareTo(_integer(left['sizeBytes'])),
      );
    final expiringSoon =
        records
            .where((record) {
              final ttl = _integer(record['ttlSeconds']);
              return ttl >= 0 && ttl <= 3600;
            })
            .toList(growable: false)
          ..sort(
            (left, right) => _integer(
              left['ttlSeconds'],
            ).compareTo(_integer(right['ttlSeconds'])),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _KpiStrip(
          items: [
            _KpiItem('Key 总量', _compactCount(keyCount), Icons.key_rounded),
            _KpiItem('样本中过期 Key', '$expiringInSample', Icons.timer_outlined),
            _KpiItem(
              '样本中永久 Key',
              '$persistentInSample',
              Icons.all_inclusive_rounded,
            ),
            _KpiItem(
              '累计已过期',
              _compactCount(expired),
              Icons.event_busy_outlined,
            ),
            _KpiItem(
              '累计已淘汰',
              _compactCount(evicted),
              Icons.delete_sweep_outlined,
            ),
          ],
          tone: tone,
          interactive: false,
          singleRow: true,
        ),
        const SizedBox(height: _kSectionGap),
        _AdaptivePair(
          primaryFlex: 2,
          secondaryFlex: 3,
          primary: _MetricSection(
            title: 'Key 类型分布',
            subtitle: '基于当前已加载 Key 样本',
            icon: Icons.pie_chart_rounded,
            child: _DonutBreakdown(
              values: _breakdownFromMap(context, types),
              centerLabel: '${records.length} 个样本',
              rawCount: true,
            ),
          ),
          secondary: _MetricSection(
            title: 'Key 数量增长',
            subtitle: '${_range.label} · 全实例 Key 总量',
            icon: Icons.show_chart_rounded,
            child: _InteractiveTrendChart(
              times: _sampleTimes(samples),
              series: [
                OpenHandChartSeries(
                  label: 'Key 总量',
                  values: _sampleValues(
                    samples,
                    (sample) => _integer(
                      _redisOverview(sample.overview)['keyCount'],
                    ).toDouble(),
                  ),
                  color: tone,
                ),
              ],
              unit: '个',
              formatValue: (value) => '${_compactCount(value.round())} 个',
            ),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: 'TTL 区间热力分布',
          subtitle: '颜色深度表示当前样本中的 Key 数量',
          icon: Icons.grid_on_rounded,
          child: _TtlHeatmap(values: ttlBuckets, color: tone),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '数据库分布',
          subtitle: '各数据库 Key 数量、过期比例与平均 TTL',
          icon: Icons.dns_outlined,
          child: _RankTable(
            headers: const ['数据库', 'Key 数量', '过期比例', '平均 TTL'],
            rows: displayKeyspaces
                .map((database) {
                  final keys = _integer(database['keys']);
                  final expires = _integer(database['expires']);
                  final averageTtl = _integerOrNull(database['averageTtlMs']);
                  return _RankRow(
                    cells: [
                      '${database['database'] ?? database['name'] ?? '--'}',
                      _compactCount(keys),
                      _percent(dependencySafeRatio(expires, keys)),
                      averageTtl == null
                          ? '接口暂未提供'
                          : _durationText((averageTtl / 1000).round()),
                    ],
                    value: keys.toDouble(),
                  );
                })
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _AdaptivePair(
          primary: _MetricSection(
            title: '大 Key',
            subtitle: '当前样本按占用倒序',
            icon: Icons.vertical_align_top_rounded,
            child: _CompactRecordList(
              records: sortedBySize,
              trailing: (record) =>
                  formatByteSize(_integer(record['sizeBytes'])),
              emptyLabel: '暂无 Key 样本',
            ),
          ),
          secondary: _MetricSection(
            title: '即将过期 Key',
            subtitle: '未来 1 小时内到期',
            icon: Icons.hourglass_bottom_rounded,
            child: _CompactRecordList(
              records: expiringSoon,
              trailing: (record) => _ttlText(_integer(record['ttlSeconds'])),
              emptyLabel: '当前样本无即将过期 Key',
            ),
          ),
        ),
      ],
    );
  }

  Widget _redisThroughput(
    BuildContext context, {
    required Map<String, Object?> redis,
    required List<DependencyTelemetrySample> samples,
    required Color tone,
  }) {
    final ops = _integer(redis['operationsPerSecond']);
    final totalCommands = _integer(redis['totalCommands']);
    final measuredRates = _seriesRate(
      samples,
      (sample) => _integer(_redisOverview(sample.overview)['totalCommands']),
    );
    final directOps = _sampleValues(
      samples,
      (sample) => _integer(
        _redisOverview(sample.overview)['operationsPerSecond'],
      ).toDouble(),
    );
    final peak = [
      ...directOps,
      ...measuredRates,
    ].fold<double>(ops.toDouble(), math.max);
    final commandStats = _objectMaps(redis['commandStats']);
    commandStats.sort(
      (left, right) =>
          _integer(right['calls']).compareTo(_integer(left['calls'])),
    );
    final commandMix = _stringIntMap(redis['commandCategories']);
    final slowCommands = _objectMaps(redis['slowCommands']);
    final averageLatency = _number(redis['averageCommandLatencyMs']);
    final p95 = _number(redis['p95CommandLatencyMs']);
    final p99 = _number(redis['p99CommandLatencyMs']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ThroughputHero(
          currentOps: ops,
          peakOps: peak,
          totalCommands: totalCommands,
          averageLatency: averageLatency,
          tone: tone,
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: 'OPS 实时曲线',
          subtitle: '${_range.label} · INFO 即时值与累计命令差值',
          icon: Icons.monitor_heart_outlined,
          child: _InteractiveTrendChart(
            times: _sampleTimes(samples),
            series: [
              OpenHandChartSeries(
                label: '即时 OPS',
                values: directOps,
                color: tone,
              ),
              OpenHandChartSeries(
                label: '计数器换算',
                values: measuredRates,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ],
            unit: 'ops/s',
            area: true,
            formatValue: (value) => '${value.toStringAsFixed(1)} ops/s',
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _AdaptivePair(
          primary: _MetricSection(
            title: '命令类型占比',
            subtitle: '读、写与管理命令',
            icon: Icons.category_outlined,
            child: commandMix.isEmpty
                ? const _InlineUnavailable(label: '当前接口暂未提供命令分类统计')
                : _DonutBreakdown(
                    values: _breakdownFromMap(context, commandMix),
                    centerLabel: _compactCount(
                      commandMix.values.fold<int>(
                        0,
                        (sum, value) => sum + value,
                      ),
                    ),
                    rawCount: true,
                  ),
          ),
          secondary: _MetricSection(
            title: '延迟分位数',
            subtitle: '命令执行耗时',
            icon: Icons.timer_outlined,
            child: _LatencyDistribution(
              average: averageLatency,
              p95: p95,
              p99: p99,
            ),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '热门命令排行',
          subtitle: '调用量、平均耗时与总耗时',
          icon: Icons.leaderboard_rounded,
          child: _RankTable(
            headers: const ['命令', '调用量', '平均耗时', '总耗时'],
            emptyLabel: '当前接口暂未提供 commandstats',
            rows: commandStats
                .map(
                  (command) => _RankRow(
                    cells: [
                      '${command['command'] ?? command['name'] ?? '--'}',
                      _compactCount(_integer(command['calls'])),
                      '${_number(command['microsecondsPerCall']).toStringAsFixed(2)} μs',
                      '${(_number(command['microseconds']) / 1000).toStringAsFixed(1)} ms',
                    ],
                    value: _integer(command['calls']).toDouble(),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '最近慢命令',
          subtitle: '命令、耗时、客户端与发生时间',
          icon: Icons.slow_motion_video_rounded,
          child: _RankTable(
            headers: const ['时间', '命令', '耗时', '客户端'],
            emptyLabel: '当前接口暂未提供 SLOWLOG 数据',
            rows: slowCommands
                .map(
                  (command) => _RankRow(
                    cells: [
                      _dateTimeText(command['occurredAt']),
                      '${command['command'] ?? '--'}',
                      openHandTableMetricDuration(
                        _number(command['durationMs']),
                      ),
                      '${command['client'] ?? '--'}',
                    ],
                    cellWidgets: [
                      null,
                      null,
                      OpenHandDurationMetricCell(
                        durationMs: _number(command['durationMs']),
                      ),
                      null,
                    ],
                    value: _number(command['durationMs']),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _redisCache(
    BuildContext context, {
    required Map<String, Object?> redis,
    required List<DependencyTelemetrySample> samples,
    required Color tone,
  }) {
    final hits = _integer(redis['keyspaceHits']);
    final misses = _integer(redis['keyspaceMisses']);
    final hitRate = dependencySafeRatio(hits, hits + misses);
    final hitRates = _sampleValues(samples, (sample) {
      final current = _redisOverview(sample.overview);
      final currentHits = _integer(current['keyspaceHits']);
      final currentMisses = _integer(current['keyspaceMisses']);
      return dependencySafeRatio(currentHits, currentHits + currentMisses) *
          100;
    });
    final hitRequestRates = _seriesRate(
      samples,
      (sample) => _integer(_redisOverview(sample.overview)['keyspaceHits']),
    );
    final missRequestRates = _seriesRate(
      samples,
      (sample) => _integer(_redisOverview(sample.overview)['keyspaceMisses']),
    );
    final dimensions = _objectMaps(redis['cacheHitDimensions']);
    dimensions.sort(
      (left, right) => _normalizedRatio(
        left['hitRate'],
      ).compareTo(_normalizedRatio(right['hitRate'])),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RedisHitGauge(rate: hitRate, hits: hits, misses: misses, tone: tone),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '请求命中率变化',
          subtitle: '${_range.label} · Redis Key 请求维度',
          icon: Icons.trending_up_rounded,
          child: _InteractiveTrendChart(
            times: _sampleTimes(samples),
            series: [
              OpenHandChartSeries(label: '命中率', values: hitRates, color: tone),
            ],
            unit: '%',
            formatValue: (value) => '${value.toStringAsFixed(1)}%',
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '命中与未命中速率',
          subtitle: '累计请求计数器按采样间隔换算',
          icon: Icons.compare_arrows_rounded,
          child: _InteractiveTrendChart(
            times: _sampleTimes(samples),
            series: [
              OpenHandChartSeries(
                label: '命中',
                values: hitRequestRates,
                color: OpenHandStatusColors.success,
              ),
              OpenHandChartSeries(
                label: '未命中',
                values: missRequestRates,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
            unit: '请求/s',
            formatValue: (value) => '${value.toStringAsFixed(1)} 请求/s',
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '低命中命令与业务维度',
          subtitle: '聚焦 Redis 命令与 Key 类型，不使用数据库块指标',
          icon: Icons.filter_alt_outlined,
          child: _RankTable(
            headers: const ['维度', '请求量', '命中率', '未命中'],
            emptyLabel: '当前接口暂未提供命令或业务维度命中统计',
            rows: dimensions
                .map(
                  (dimension) => _RankRow(
                    cells: [
                      '${dimension['name'] ?? dimension['command'] ?? '--'}',
                      _compactCount(_integer(dimension['requests'])),
                      _percent(_normalizedRatio(dimension['hitRate'])),
                      _compactCount(_integer(dimension['misses'])),
                    ],
                    value: 1 - _normalizedRatio(dimension['hitRate']),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _redisClients(
    BuildContext context, {
    required Map<String, Object?> redis,
    required List<DependencyTelemetrySample> samples,
    required Color tone,
  }) {
    final connected = _integer(redis['connectedClients']);
    final blocked = _integer(redis['blockedClients']);
    final maxClients = _integer(redis['maxClients']);
    final rejected = _integer(redis['rejectedConnections']);
    final clients = _objectMaps(redis['clients']);
    final sources = <String, int>{};
    final ageBuckets = <String, int>{
      '< 1 分钟': 0,
      '1 - 10 分钟': 0,
      '10 - 60 分钟': 0,
      '> 1 小时': 0,
    };
    for (final client in clients) {
      final source = '${client['application'] ?? client['address'] ?? '未知来源'}';
      sources[source] = (sources[source] ?? 0) + 1;
      final age = _integer(client['ageSeconds']);
      final bucket = age < 60
          ? '< 1 分钟'
          : age < 600
          ? '1 - 10 分钟'
          : age < 3600
          ? '10 - 60 分钟'
          : '> 1 小时';
      ageBuckets[bucket] = ageBuckets[bucket]! + 1;
    }
    final abnormalClients = clients
        .where((client) {
          return client['blocked'] == true ||
              _integer(client['idleSeconds']) >= 600 ||
              _integer(client['commands']) >= 10000;
        })
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClientStatusHeader(
          connected: connected,
          blocked: blocked,
          maximum: maxClients,
          rejected: rejected,
          tone: tone,
        ),
        const SizedBox(height: _kSectionGap),
        _AdaptivePair(
          primary: _MetricSection(
            title: '客户端状态',
            subtitle: '正常与阻塞连接分布',
            icon: Icons.donut_small_rounded,
            child: _DonutBreakdown(
              values: [
                _BreakdownItem(
                  '正常',
                  math.max(0, connected - blocked),
                  OpenHandStatusColors.success,
                ),
                _BreakdownItem(
                  '阻塞',
                  blocked,
                  Theme.of(context).colorScheme.error,
                ),
              ],
              centerLabel: '$connected 个',
              rawCount: true,
            ),
          ),
          secondary: _MetricSection(
            title: '连接持续时间',
            subtitle: '当前客户端按连接年龄分桶',
            icon: Icons.timelapse_rounded,
            child: clients.isEmpty
                ? const _InlineUnavailable(label: '当前接口暂未提供 CLIENT LIST')
                : _HorizontalBars(
                    values: ageBuckets,
                    color: tone,
                    emptyLabel: '暂无客户端年龄数据',
                    valueLabel: (value) => '$value 个',
                  ),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '连接数量趋势',
          subtitle: '${_range.label} · 已连接与阻塞客户端',
          icon: Icons.stacked_line_chart_rounded,
          child: _InteractiveTrendChart(
            times: _sampleTimes(samples),
            series: [
              OpenHandChartSeries(
                label: '已连接',
                values: _sampleValues(
                  samples,
                  (sample) => _integer(
                    _redisOverview(sample.overview)['connectedClients'],
                  ).toDouble(),
                ),
                color: tone,
              ),
              OpenHandChartSeries(
                label: '阻塞',
                values: _sampleValues(
                  samples,
                  (sample) => _integer(
                    _redisOverview(sample.overview)['blockedClients'],
                  ).toDouble(),
                ),
                color: Theme.of(context).colorScheme.error,
              ),
            ],
            unit: '个',
            formatValue: (value) => '${value.round()} 个',
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _AdaptivePair(
          primaryFlex: 2,
          secondaryFlex: 3,
          primary: _MetricSection(
            title: '连接来源排行',
            subtitle: '按应用或地址聚合',
            icon: Icons.public_rounded,
            child: _HorizontalBars(
              values: sources,
              color: tone,
              emptyLabel: '当前接口暂未提供客户端来源',
              valueLabel: (value) => '$value 个',
            ),
          ),
          secondary: _MetricSection(
            title: '异常客户端',
            subtitle: '阻塞、长时间空闲或高频连接',
            icon: Icons.person_search_outlined,
            child: _RankTable(
              headers: const ['地址 / 名称', '数据库 / 订阅', '最近命令', '空闲时长'],
              emptyLabel: clients.isEmpty ? '当前接口暂未提供 CLIENT LIST' : '当前无异常客户端',
              rows: abnormalClients
                  .map(
                    (client) => _RankRow(
                      cells: [
                        '${client['address'] ?? '--'} / ${client['name'] ?? '--'}',
                        '${client['database'] ?? '--'} / ${client['subscriptions'] ?? 0}',
                        '${client['lastCommand'] ?? '--'}',
                        _durationText(_integer(client['idleSeconds'])),
                      ],
                      value: _integer(client['idleSeconds']).toDouble(),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }

  Widget _redisNetwork(
    BuildContext context, {
    required Map<String, Object?> redis,
    required List<DependencyTelemetrySample> samples,
    required Color tone,
  }) {
    final totalInput = _integer(redis['networkInputBytes']);
    final totalOutput = _integer(redis['networkOutputBytes']);
    final inputRates = _seriesRate(
      samples,
      (sample) =>
          _integer(_redisOverview(sample.overview)['networkInputBytes']),
    );
    final outputRates = _seriesRate(
      samples,
      (sample) =>
          _integer(_redisOverview(sample.overview)['networkOutputBytes']),
    );
    final currentInput =
        _numberOrNull(redis['networkInputBytesPerSecond']) ??
        _lastValue(inputRates);
    final currentOutput =
        _numberOrNull(redis['networkOutputBytesPerSecond']) ??
        _lastValue(outputRates);
    final peak = math.max(
      inputRates.fold<double>(0, math.max),
      outputRates.fold<double>(0, math.max),
    );
    final totalRates = inputRates.length + outputRates.length;
    final average = totalRates == 0
        ? 0.0
        : (inputRates.fold<double>(0, (sum, value) => sum + value) +
                  outputRates.fold<double>(0, (sum, value) => sum + value)) /
              totalRates;
    final anomalies = _networkAnomalies(samples, inputRates, outputRates);
    final sources = _objectMaps(redis['networkSources']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NetworkDirectionHeader(
          inputRate: currentInput,
          outputRate: currentOutput,
          totalInput: totalInput,
          totalOutput: totalOutput,
          tone: tone,
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '双向网络速率',
          subtitle: '${_range.label} · 累计字节计数器按采样间隔换算',
          icon: Icons.multiline_chart_rounded,
          trailing: _StatusTag(
            label: '峰值 ${formatByteSize(peak.round())}/s',
            color: peak > average * 2 && average > 0
                ? OpenHandStatusColors.warning
                : tone,
          ),
          child: _InteractiveTrendChart(
            times: _sampleTimes(samples),
            series: [
              OpenHandChartSeries(label: '输入', values: inputRates, color: tone),
              OpenHandChartSeries(
                label: '输出',
                values: outputRates,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ],
            unit: 'B/s',
            area: true,
            formatValue: (value) => '${formatByteSize(value.round())}/s',
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _AdaptivePair(
          primary: _MetricSection(
            title: '累计流量构成',
            subtitle: '输入与输出占比',
            icon: Icons.donut_large_rounded,
            child: _DonutBreakdown(
              values: [
                _BreakdownItem('输入', totalInput, tone),
                _BreakdownItem(
                  '输出',
                  totalOutput,
                  Theme.of(context).colorScheme.tertiary,
                ),
              ],
              centerLabel: formatByteSize(totalInput + totalOutput),
            ),
          ),
          secondary: _MetricSection(
            title: '带宽判断',
            subtitle: '窗口峰值、平均值与连接吞吐',
            icon: Icons.network_check_rounded,
            child: _OperationalSummary(
              items: [
                _SummaryItem('峰值带宽', '${formatByteSize(peak.round())}/s', tone),
                _SummaryItem(
                  '平均带宽',
                  '${formatByteSize(average.round())}/s',
                  tone,
                ),
                _SummaryItem(
                  '单连接吞吐',
                  _integer(redis['connectedClients']) <= 0
                      ? '--'
                      : '${formatByteSize(((currentInput + currentOutput) / _integer(redis['connectedClients'])).round())}/s',
                  OpenHandStatusColors.info,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '异常与突增时间点',
          subtitle: '速率超过窗口平均值两倍时标记',
          icon: Icons.warning_amber_rounded,
          child: _AnomalyTimeline(
            rows: anomalies,
            emptyLabel: samples.length < 3 ? '等待更多遥测样本' : '窗口内未发现明显流量突增',
          ),
        ),
        const SizedBox(height: _kSectionGap),
        _MetricSection(
          title: '主要流量来源',
          subtitle: '按客户端累计流量倒序',
          icon: Icons.account_tree_outlined,
          child: _RankTable(
            headers: const ['客户端', '输入', '输出', '总流量'],
            emptyLabel: '当前接口暂未提供客户端级流量统计',
            rows: sources
                .map((source) {
                  final input = _integer(source['inputBytes']);
                  final output = _integer(source['outputBytes']);
                  return _RankRow(
                    cells: [
                      '${source['client'] ?? source['address'] ?? '--'}',
                      formatByteSize(input),
                      formatByteSize(output),
                      formatByteSize(input + output),
                    ],
                    value: (input + output).toDouble(),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _MetricDialogHeader extends StatelessWidget {
  const _MetricDialogHeader({
    required this.kind,
    required this.tone,
    required this.reloading,
    required this.onReload,
  });

  final DependencyMetricKind kind;
  final Color tone;
  final bool reloading;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 18, 18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = ServiceDialogRefreshCloseActions(
            refreshTooltip: '重新加载指标',
            refreshing: reloading,
            onRefresh: reloading ? null : onReload,
          );
          final identity = Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: kOpenHandBorderRadius14,
                  border: Border.all(color: tone.withValues(alpha: 0.28)),
                ),
                child: Icon(kind.icon, color: tone, size: 24),
              ),
              kOpenHandHGap14,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            kind.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        kOpenHandHGap10,
                        _StatusTag(label: '遥测详情', color: tone),
                      ],
                    ),
                    kOpenHandGap4,
                    Text(
                      kind.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                kOpenHandGap12,
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _MetricRangeBar extends StatelessWidget {
  const _MetricRangeBar({
    required this.selected,
    required this.capturedAt,
    required this.onChanged,
  });

  final _MetricTimeRange selected;
  final String capturedAt;
  final ValueChanged<_MetricTimeRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final range = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_MetricTimeRange>(
            segments: [
              for (final value in _MetricTimeRange.values)
                ButtonSegment(value: value, label: Text(value.label)),
            ],
            selected: <_MetricTimeRange>{selected},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kOpenHandRadius10),
                ),
              ),
            ),
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        );
        final stamp = Text(
          '采样时间 $capturedAt',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        );
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.34),
              ),
            ),
          ),
          child: constraints.maxWidth < 620
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    range,
                    kOpenHandGap8,
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: stamp,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: range),
                    kOpenHandHGap12,
                    Flexible(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: stamp,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _MetricLoadState extends StatelessWidget {
  const _MetricLoadState({
    required this.loading,
    required this.error,
    required this.onReload,
  });

  final bool loading;
  final String? error;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator()
            else
              Icon(
                error == null
                    ? Icons.query_stats_rounded
                    : Icons.cloud_off_rounded,
                size: 42,
                color: error == null ? colors.onSurfaceVariant : colors.error,
              ),
            kOpenHandGap12,
            Text(
              loading
                  ? '正在加载遥测数据'
                  : error == null
                  ? '暂无可展示的遥测数据'
                  : '指标请求失败',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!loading) ...[
              kOpenHandGap6,
              Text(
                error ?? '服务连接后将在此展示监控详情。',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              kOpenHandGap14,
              FilledButton.icon(
                onPressed: onReload,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新加载'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricSection extends StatelessWidget {
  const _MetricSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow.withValues(alpha: 0.78),
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 15, 17, 17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(kOpenHandRadius9),
                  ),
                  child: Icon(icon, size: 18, color: colors.primary),
                ),
                kOpenHandHGap10,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      kOpenHandGap2,
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[kOpenHandHGap10, trailing!],
              ],
            ),
            kOpenHandGap15,
            child,
          ],
        ),
      ),
    );
  }
}

class _AdaptivePair extends StatelessWidget {
  const _AdaptivePair({
    required this.primary,
    required this.secondary,
    this.primaryFlex = 1,
    this.secondaryFlex = 1,
  });

  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final int secondaryFlex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < _kCompactBreakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            primary,
            const SizedBox(height: _kSectionGap),
            secondary,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: primaryFlex, child: primary),
          kOpenHandWidth22,
          Expanded(flex: secondaryFlex, child: secondary),
        ],
      );
    },
  );
}

class _KpiItem {
  const _KpiItem(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({
    required this.items,
    required this.tone,
    this.interactive = true,
    this.singleRow = false,
  });

  final List<_KpiItem> items;
  final Color tone;
  final bool interactive;
  final bool singleRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (items.isEmpty) return const SizedBox.shrink();
        const stripInset = 12.0;
        final canFitSingleRow =
            constraints.maxWidth - stripInset >=
            items.length * 132 + (items.length - 1) * 10;
        final columns = singleRow && canFitSingleRow
            ? items.length
            : constraints.maxWidth < 480
            ? 2
            : constraints.maxWidth < 820
            ? math.min(3, items.length)
            : math.min(5, items.length);
        const gap = 10.0;
        final minimumCardWidth = constraints.maxWidth < 480 ? 104.0 : 132.0;
        final width = (singleRow && canFitSingleRow)
            ? (constraints.maxWidth - stripInset - gap * (columns - 1)) /
                  columns
            : math.max(
                minimumCardWidth,
                (constraints.maxWidth - stripInset - gap * (columns - 1)) /
                    columns,
              );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.34),
            borderRadius: kOpenHandBorderRadius14,
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final item in items)
                  SizedBox(
                    width: width,
                    child: ServiceInteractiveSurface(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      tooltip: interactive ? '查看指标详情' : null,
                      onTap: interactive
                          ? () => showServiceDetailsDialog(
                              context,
                              title: item.label,
                              subtitle: '依赖服务指标',
                              icon: item.icon,
                              accentColor: tone,
                              presentation: ServiceDetailPresentation.metric,
                              fields: [
                                ServiceDetailField(
                                  label: '指标',
                                  value: item.label,
                                ),
                                ServiceDetailField(
                                  label: '当前值',
                                  value: item.value,
                                ),
                              ],
                            )
                          : null,
                      showDetailsIcon: interactive,
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: tone.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                kOpenHandRadius9,
                              ),
                            ),
                            child: Icon(item.icon, size: 17, color: tone),
                          ),
                          kOpenHandHGap9,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                kOpenHandGap3,
                                Text(
                                  item.value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(kOpenHandRadius10),
      border: Border.all(color: color.withValues(alpha: 0.24)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        kOpenHandHGap8,
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

class _InlineUnavailable extends StatelessWidget {
  const _InlineUnavailable({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: SizedBox(
        height: 116,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.data_array_rounded, color: colors.outline, size: 30),
              kOpenHandGap8,
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: kOpenHandPillBorderRadius,
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        kOpenHandHGap6,
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _ConnectionCapacityHero extends StatelessWidget {
  const _ConnectionCapacityHero({
    required this.active,
    required this.maximum,
    required this.poolSize,
    required this.peak,
    required this.tone,
  });

  final int active;
  final int maximum;
  final int poolSize;
  final int peak;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ratio = dependencySafeRatio(active, maximum);
    final riskColor = ratio >= 0.85
        ? colors.error
        : ratio >= 0.7
        ? OpenHandStatusColors.warning
        : tone;
    final riskLabel = maximum <= 0
        ? '未设置上限'
        : ratio >= 0.85
        ? '高占用'
        : ratio >= 0.7
        ? '需关注'
        : '运行良好';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          riskColor.withValues(alpha: 0.08),
          colors.surfaceContainerHigh,
        ),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: riskColor.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final header = Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.account_tree_rounded,
                    size: 18,
                    color: riskColor,
                  ),
                ),
                kOpenHandHGap10,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '连接容量',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '活动连接 / 最大连接数',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                kOpenHandHGap12,
                _StatusTag(label: riskLabel, color: riskColor),
              ],
            );
            final usage = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '$active / ${maximum <= 0 ? '--' : maximum}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                kOpenHandGap12,
                ClipRRect(
                  borderRadius: kOpenHandPillBorderRadius,
                  child: ServiceAnimatedProgressBar(
                    minHeight: 8,
                    value: ratio.clamp(0.0, 1.0),
                    color: riskColor,
                    backgroundColor: colors.surfaceContainerHighest,
                  ),
                ),
              ],
            );
            final facts = Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                for (final fact in [
                  _HeroFact(label: '连接池', value: '$poolSize'),
                  _HeroFact(label: '窗口峰值', value: '$peak'),
                  _HeroFact(
                    label: '剩余容量',
                    value: maximum <= 0
                        ? '--'
                        : '${math.max(0, maximum - active)}',
                  ),
                  _HeroFact(label: '使用率', value: _percent(ratio)),
                ])
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.58),
                      borderRadius: BorderRadius.circular(kOpenHandRadius10),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.42),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      child: fact,
                    ),
                  ),
              ],
            );
            final body = constraints.maxWidth < 620
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [usage, kOpenHandGap16, facts],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: usage),
                      kOpenHandHGap24,
                      Expanded(flex: 3, child: facts),
                    ],
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, kOpenHandGap18, body],
            );
          },
        ),
      ),
    );
  }
}

class _MemoryRiskHero extends StatelessWidget {
  const _MemoryRiskHero({
    required this.used,
    required this.maximum,
    required this.fragmentation,
    required this.risk,
    required this.tone,
  });

  final int used;
  final int maximum;
  final double fragmentation;
  final double risk;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final riskColor = risk >= 0.85
        ? colors.error
        : risk >= 0.7
        ? OpenHandStatusColors.warning
        : tone;
    final riskLabel = risk >= 0.85
        ? '高风险'
        : risk >= 0.7
        ? '需关注'
        : '健康';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: riskColor.withValues(alpha: 0.28)),
        color: Color.alphaBlend(
          riskColor.withValues(alpha: 0.07),
          colors.surfaceContainerHigh,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.memory_rounded, color: riskColor),
                  kOpenHandHGap8,
                  Text('内存风险', style: theme.textTheme.titleMedium),
                  kOpenHandHGap8,
                  _StatusTag(label: riskLabel, color: riskColor),
                ],
              ),
              kOpenHandGap8,
              Text(
                formatByteSize(used),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                maximum > 0
                    ? '上限 ${formatByteSize(maximum)} · ${_percent(dependencySafeRatio(used, maximum))}'
                    : '未设置 maxmemory · 以碎片率评估当前风险',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          );
          final facts = Wrap(
            spacing: 22,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              _HeroFact(label: '碎片率', value: fragmentation.toStringAsFixed(2)),
              _HeroFact(
                label: '剩余上限',
                value: maximum <= 0
                    ? '--'
                    : formatByteSize(math.max(0, maximum - used)),
              ),
              _HeroFact(label: '风险指数', value: _percent(risk)),
            ],
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, kOpenHandGap14, facts],
            );
          }
          return Row(
            children: [
              Expanded(flex: 3, child: title),
              kOpenHandHGap20,
              Expanded(flex: 2, child: facts),
            ],
          );
        },
      ),
    );
  }
}

class _ThroughputHero extends StatelessWidget {
  const _ThroughputHero({
    required this.currentOps,
    required this.peakOps,
    required this.totalCommands,
    required this.averageLatency,
    required this.tone,
  });

  final int currentOps;
  final double peakOps;
  final int totalCommands;
  final double averageLatency;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final current = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tone.withValues(alpha: 0.1),
          colors.surfaceContainerHigh,
        ),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前吞吐', style: theme.textTheme.labelMedium),
          kOpenHandGap5,
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '$currentOps ops/s',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    final facts = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Wrap(
        spacing: 22,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        children: [
          _HeroFact(
            label: '窗口峰值',
            value: '${peakOps.toStringAsFixed(1)} ops/s',
          ),
          _HeroFact(label: '累计命令', value: _compactCount(totalCommands)),
          _HeroFact(
            label: '平均耗时',
            value: averageLatency <= 0
                ? '暂未接入'
                : '${averageLatency.toStringAsFixed(2)} ms',
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(children: [current, kOpenHandGap10, facts]);
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 2, child: current),
              kOpenHandHGap10,
              Expanded(flex: 3, child: facts),
            ],
          ),
        );
      },
    );
  }
}

class _ClientStatusHeader extends StatelessWidget {
  const _ClientStatusHeader({
    required this.connected,
    required this.blocked,
    required this.maximum,
    required this.rejected,
    required this.tone,
  });

  final int connected;
  final int blocked;
  final int maximum;
  final int rejected;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return _KpiStrip(
      tone: tone,
      items: [
        _KpiItem('已连接', '$connected', Icons.group_rounded),
        _KpiItem('阻塞', '$blocked', Icons.pause_circle_outline_rounded),
        _KpiItem(
          '最大客户端数',
          maximum <= 0 ? '暂未接入' : '$maximum',
          Icons.groups_2_outlined,
        ),
        _KpiItem('拒绝连接', _compactCount(rejected), Icons.block_rounded),
        _KpiItem(
          '容量使用率',
          maximum <= 0
              ? '--'
              : _percent(dependencySafeRatio(connected, maximum)),
          Icons.data_usage_rounded,
        ),
      ],
      interactive: false,
      singleRow: true,
    );
  }
}

class _NetworkDirectionHeader extends StatelessWidget {
  const _NetworkDirectionHeader({
    required this.inputRate,
    required this.outputRate,
    required this.totalInput,
    required this.totalOutput,
    required this.tone,
  });

  final double inputRate;
  final double outputRate;
  final int totalInput;
  final int totalOutput;
  final Color tone;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cards = [
        _DirectionMetric(
          icon: Icons.south_west_rounded,
          label: '当前输入',
          rate: inputRate,
          total: totalInput,
          color: tone,
        ),
        _DirectionMetric(
          icon: Icons.north_east_rounded,
          label: '当前输出',
          rate: outputRate,
          total: totalOutput,
          color: Theme.of(context).colorScheme.tertiary,
        ),
      ];
      if (constraints.maxWidth < 520) {
        return Column(children: [cards.first, kOpenHandGap10, cards.last]);
      }
      return Row(
        children: [
          Expanded(child: cards.first),
          kOpenHandHGap12,
          Expanded(child: cards.last),
        ],
      );
    },
  );
}

class _DirectionMetric extends StatelessWidget {
  const _DirectionMetric({
    required this.icon,
    required this.label,
    required this.rate,
    required this.total,
    required this.color,
  });

  final IconData icon;
  final String label;
  final double rate;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.08),
          Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
        borderRadius: kOpenHandBorderRadius16,
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          kOpenHandHGap12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                Text(
                  '${formatByteSize(rate.round())}/s',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '累计 ${formatByteSize(total)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroFact extends StatelessWidget {
  const _HeroFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 190),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          kOpenHandGap3,
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownItem {
  const _BreakdownItem(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;
}

class _DonutBreakdown extends StatelessWidget {
  const _DonutBreakdown({
    required this.values,
    required this.centerLabel,
    this.rawCount = false,
  });
  final List<_BreakdownItem> values;
  final String centerLabel;
  final bool rawCount;

  @override
  Widget build(BuildContext context) {
    final visible = values
        .where((item) => item.value > 0)
        .toList(growable: false);
    final total = visible.fold<int>(0, (sum, item) => sum + item.value);
    return OpenHandOperationalDonutChart(
      segments: visible
          .map(
            (item) => OpenHandChartSegment(
              label: item.label,
              value: item.value,
              color: item.color,
              valueLabel: rawCount
                  ? _compactCount(item.value)
                  : formatByteSize(item.value),
            ),
          )
          .toList(growable: false),
      trackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      centerLabel: centerLabel,
      onSelectionChanged: null,
      onSegmentTap: (selection) {
        if (selection.index < 0 || selection.index >= visible.length) return;
        final item = visible[selection.index];
        showServiceDetailsDialog(
          context,
          title: item.label,
          subtitle: '构成明细',
          icon: Icons.donut_small_rounded,
          accentColor: item.color,
          presentation: ServiceDetailPresentation.composition,
          data: visible
              .map(
                (entry) => ServiceDetailDatum(
                  label: entry.label,
                  value: entry.value.toDouble(),
                  valueLabel: rawCount
                      ? _compactCount(entry.value)
                      : formatByteSize(entry.value),
                  color: entry.color,
                  highlighted: identical(entry, item),
                ),
              )
              .toList(growable: false),
          fields: [
            ServiceDetailField(
              label: '当前值',
              value: rawCount
                  ? _compactCount(item.value)
                  : formatByteSize(item.value),
            ),
            ServiceDetailField(
              label: '占比',
              value: _percent(dependencySafeRatio(item.value, total)),
            ),
            ServiceDetailField(label: '总量', value: '$total'),
          ],
        );
      },
    );
  }
}

class _HorizontalBars extends StatelessWidget {
  const _HorizontalBars({
    required this.values,
    required this.color,
    required this.emptyLabel,
    required this.valueLabel,
  });
  final Map<String, int> values;
  final Color color;
  final String emptyLabel;
  final String Function(int value) valueLabel;

  @override
  Widget build(BuildContext context) {
    final sorted = values.entries.where((item) => item.value > 0).toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    if (sorted.isEmpty) return _InlineUnavailable(label: emptyLabel);
    return OpenHandOperationalComparisonBars(
      segments: sorted
          .take(10)
          .map(
            (item) => OpenHandChartSegment(
              label: item.key,
              value: item.value,
              color: color,
              valueLabel: valueLabel(item.value),
            ),
          )
          .toList(growable: false),
      orientation: OpenHandComparisonBarOrientation.horizontal,
      emptyLabel: emptyLabel,
      onSegmentTap: (selected) {
        final item = sorted
            .where((entry) => entry.key == selected.label)
            .firstOrNull;
        if (item == null) return;
        showServiceDetailsDialog(
          context,
          title: item.key,
          subtitle: '排行明细',
          icon: Icons.bar_chart_rounded,
          accentColor: color,
          presentation: ServiceDetailPresentation.ranking,
          data: sorted
              .map(
                (entry) => ServiceDetailDatum(
                  label: entry.key,
                  value: entry.value.toDouble(),
                  valueLabel: valueLabel(entry.value),
                  color: color,
                  highlighted: entry.key == item.key,
                ),
              )
              .toList(growable: false),
          fields: [
            ServiceDetailField(label: '项目', value: item.key),
            ServiceDetailField(label: '当前值', value: valueLabel(item.value)),
            ServiceDetailField(label: '原始值', value: '${item.value}'),
          ],
        );
      },
    );
  }
}

class _RankRow {
  const _RankRow({required this.cells, required this.value, this.cellWidgets});

  final List<String> cells;
  final double value;
  final List<Widget?>? cellWidgets;
}

class _RankTable extends StatelessWidget {
  const _RankTable({
    required this.headers,
    required this.rows,
    this.emptyLabel = '暂无数据',
  });
  final List<String> headers;
  final List<_RankRow> rows;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return _InlineUnavailable(label: emptyLabel);
    return OpenHandOperationalRankTable(
      headers: headers,
      emptyLabel: emptyLabel,
      rows: rows
          .map(
            (row) => OpenHandOperationalRankRow(
              cells: row.cells,
              value: row.value,
              cellWidgets: row.cellWidgets,
            ),
          )
          .toList(growable: false),
      onRowTap: (row) => showServiceDetailsDialog(
        context,
        title: row.cells.isEmpty ? '排行记录' : row.cells.first,
        subtitle: '完整排行数据',
        icon: Icons.table_rows_rounded,
        presentation: ServiceDetailPresentation.record,
        fields: [
          for (var i = 0; i < headers.length; i++)
            ServiceDetailField(
              label: headers[i],
              value: i < row.cells.length ? row.cells[i] : '--',
            ),
        ],
      ),
    );
  }
}

class _StackedStatusBand extends StatelessWidget {
  const _StackedStatusBand({required this.values});
  final List<_BreakdownItem> values;

  @override
  Widget build(BuildContext context) {
    final total = values.fold<int>(
      0,
      (sum, item) => sum + math.max(0, item.value),
    );
    return OpenHandOperationalStatusBand(
      segments: values
          .map(
            (item) => OpenHandChartSegment(
              label: item.label,
              value: item.value,
              color: item.color,
            ),
          )
          .toList(growable: false),
      emptyLabel: '暂无连接状态数据',
      valueLabel: (item) =>
          '${item.safeValue.round()} · ${_percent(dependencySafeRatio(item.safeValue, total))}',
    );
  }
}

class _VerticalComparison extends StatelessWidget {
  const _VerticalComparison({required this.items, required this.valueLabel});
  final List<_BreakdownItem> items;
  final String Function(int value) valueLabel;

  @override
  Widget build(BuildContext context) => OpenHandOperationalComparisonBars(
    segments: items
        .map(
          (item) => OpenHandChartSegment(
            label: item.label,
            value: item.value,
            color: item.color,
            valueLabel: valueLabel(item.value),
          ),
        )
        .toList(growable: false),
    orientation: OpenHandComparisonBarOrientation.vertical,
    emptyLabel: '暂无对比数据',
  );
}

class _UsageRail extends StatelessWidget {
  const _UsageRail({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              _percent(value),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        kOpenHandGap8,
        ClipRRect(
          borderRadius: kOpenHandPillBorderRadius,
          child: ServiceAnimatedProgressBar(
            minHeight: 11,
            value: value.clamp(0.0, 1.0),
            color: color,
            backgroundColor: colors.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _SummaryItem {
  const _SummaryItem(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;
}

class _OperationalSummary extends StatelessWidget {
  const _OperationalSummary({required this.items, this.interactive = true});

  final List<_SummaryItem> items;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              border: index == items.length - 1
                  ? null
                  : Border(
                      bottom: BorderSide(
                        color: colors.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
            ),
            child: ServiceInteractiveSurface(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              tooltip: interactive ? '查看运行摘要详情' : null,
              onTap: interactive
                  ? () => showServiceDetailsDialog(
                      context,
                      title: items[index].label,
                      subtitle: '运行摘要',
                      icon: Icons.analytics_outlined,
                      accentColor: items[index].color,
                      presentation: ServiceDetailPresentation.metric,
                      fields: [
                        ServiceDetailField(
                          label: '项目',
                          value: items[index].label,
                        ),
                        ServiceDetailField(
                          label: '当前值',
                          value: items[index].value,
                        ),
                      ],
                    )
                  : null,
              showDetailsIcon: interactive,
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 24,
                    decoration: BoxDecoration(
                      color: items[index].color,
                      borderRadius: BorderRadius.circular(kOpenHandRadius2),
                    ),
                  ),
                  kOpenHandHGap10,
                  Expanded(
                    child: Text(
                      items[index].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                  kOpenHandHGap12,
                  Flexible(
                    child: Text(
                      items[index].value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AnomalyRow {
  const _AnomalyRow({
    required this.time,
    required this.title,
    required this.detail,
    required this.color,
  });

  final String time;
  final String title;
  final String detail;
  final Color color;
}

class _AnomalyTimeline extends StatelessWidget {
  const _AnomalyTimeline({required this.rows, required this.emptyLabel});

  final List<_AnomalyRow> rows;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return _InlineUnavailable(label: emptyLabel);
    return OpenHandClientPager<_AnomalyRow>(
      items: rows,
      builder: (context, shown) {
        final colors = Theme.of(context).colorScheme;
        return Column(
          children: [
            for (var index = 0; index < shown.length; index++)
              ServiceInteractiveSurface(
                padding: EdgeInsets.zero,
                tooltip: '查看异常详情',
                onTap: () => showServiceDetailsDialog(
                  context,
                  title: shown[index].title,
                  subtitle: '异常时间线',
                  icon: Icons.warning_amber_rounded,
                  accentColor: OpenHandStatusColors.warning,
                  presentation: ServiceDetailPresentation.timeline,
                  data: shown
                      .map(
                        (row) => ServiceDetailDatum(
                          label: row.title,
                          value: 1,
                          valueLabel: row.time,
                          helper: row.detail,
                          color: OpenHandStatusColors.warning,
                          highlighted: identical(row, shown[index]),
                        ),
                      )
                      .toList(growable: false),
                  fields: [
                    ServiceDetailField(label: '时间', value: shown[index].time),
                    ServiceDetailField(label: '标题', value: shown[index].title),
                    ServiceDetailField(label: '说明', value: shown[index].detail),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        shown[index].time,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: shown[index].color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        if (index != shown.length - 1)
                          Container(
                            width: 1,
                            height: 42,
                            color: colors.outlineVariant,
                          ),
                      ],
                    ),
                    kOpenHandHGap10,
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shown[index].title,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              shown[index].detail,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

Map<String, Object?> _redisRecordMetadata(Map<String, Object?> record) {
  const allowed = <String>{
    'key',
    'type',
    'sizeBytes',
    'ttlSeconds',
    'length',
    'encoding',
    'database',
    'idleSeconds',
    'frequency',
  };
  return <String, Object?>{
    for (final entry in record.entries)
      if (allowed.contains(entry.key)) entry.key: entry.value,
    'valueExposure': '已隐藏原始值，仅展示运维元数据',
  };
}

class _CompactRecordList extends StatelessWidget {
  const _CompactRecordList({
    required this.records,
    required this.trailing,
    required this.emptyLabel,
  });

  final List<Map<String, Object?>> records;
  final String Function(Map<String, Object?> record) trailing;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return _InlineUnavailable(label: emptyLabel);
    return OpenHandClientPager<Map<String, Object?>>(
      items: records,
      builder: (context, shown) {
        final colors = Theme.of(context).colorScheme;
        return Column(
          children: [
            for (var index = 0; index < shown.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                onTap: () => showServiceDetailsDialog(
                  context,
                  title: '${shown[index]['key'] ?? '--'}',
                  subtitle: 'Redis Key 详情',
                  icon: Icons.key_rounded,
                  presentation: ServiceDetailPresentation.record,
                  fields: serviceDetailFieldsFromMap(
                    _redisRecordMetadata(shown[index]),
                  ),
                ),
                title: Text(
                  '${shown[index]['key'] ?? '--'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${shown[index]['type'] ?? '--'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      trailing(shown[index]),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    kOpenHandHGap4,
                    const Icon(Icons.chevron_right_rounded, size: 19),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TtlHeatmap extends StatelessWidget {
  const _TtlHeatmap({required this.values, required this.color});
  final Map<String, int> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final total = values.values.fold<int>(0, (sum, count) => sum + count);
    return OpenHandOperationalHeatmap(
      segments: [
        for (final item in values.entries)
          OpenHandChartSegment(
            label: item.key,
            value: item.value,
            color: color,
            valueLabel: '${item.value} 个 Key',
            tooltip: OpenHandChartTooltip(
              title: item.key,
              subtitle: '当前已加载 Key 样本中的 TTL 区间',
              badge: item.value <= 0 ? '空闲' : '${item.value} 个 Key',
              badgeColor: color,
              summary: item.value <= 0
                  ? '这个 TTL 区间当前没有 Key。浅色格表示空闲，不是过期事故。'
                  : '这个区间有 ${item.value} 个 Key，占已加载样本 ${total <= 0 ? '0%' : '${((item.value / total) * 100).toStringAsFixed(1)}%'}。颜色越深表示该过期策略下的 Key 越多。',
              metrics: [
                OpenHandChartTooltipMetric(
                  label: 'Key 数量',
                  value: '${item.value}',
                  icon: Icons.key_rounded,
                  color: color,
                ),
                OpenHandChartTooltipMetric(
                  label: '样本占比',
                  value: total <= 0
                      ? '—'
                      : '${((item.value / total) * 100).toStringAsFixed(1)}%',
                  hint: '共 $total 个已加载 Key',
                  icon: Icons.pie_chart_rounded,
                  color: color,
                ),
                OpenHandChartTooltipMetric(
                  label: '区间含义',
                  value: _ttlBucketMeaning(item.key),
                  icon: Icons.schedule_rounded,
                  color: color,
                ),
              ],
              notes: [
                _ttlBucketAdvice(item.key),
                '此图统计的是当前样本里的过期时间分布，不是 Redis 实例的健康状态。',
              ],
            ),
          ),
      ],
      color: color,
      emptyLabel: '暂无 TTL 数据',
    );
  }
}

String _ttlBucketMeaning(String bucket) {
  return switch (bucket) {
    '即将过期 < 1 分钟' => '剩余 TTL 不足 1 分钟，很快会从缓存消失',
    '1 分钟 - 1 小时' => '短期缓存，适合会话、验证码和热点缓冲',
    '1 - 24 小时' => '日内缓存，适合列表页和配置快照',
    '大于 24 小时' => '长 TTL，适合相对稳定的字典或物化结果',
    '永久' => '未设置过期时间，会一直占用内存直到被淘汰或手动删除',
    _ => '按剩余 TTL 划分的样本桶',
  };
}

String _ttlBucketAdvice(String bucket) {
  return switch (bucket) {
    '即将过期 < 1 分钟' => '若这一桶突然变深，说明大量 Key 会在一分钟内集体过期，可能带来击穿。',
    '1 分钟 - 1 小时' => '常见的短缓存带。深度上升通常只是业务高峰，不一定是风险。',
    '1 - 24 小时' => '中等寿命缓存。可结合内存占用判断是否需要缩短 TTL。',
    '大于 24 小时' => '长寿命 Key 变多时，要留意内存被旧数据长期占用。',
    '永久' => '永久 Key 不会自动释放。占比过高时，应核对是否遗漏了过期策略。',
    _ => '颜色深度只表示该区间的 Key 数量。',
  };
}

class _RadialMeter extends StatelessWidget {
  const _RadialMeter({
    required this.label,
    required this.value,
    required this.color,
    required this.helper,
    this.unavailable = false,
  });
  final String label;
  final double value;
  final Color color;
  final String helper;
  final bool unavailable;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gaugeSize = constraints.maxWidth.isFinite
          ? math.min(136.0, constraints.maxWidth)
          : 136.0;
      return Center(
        child: OpenHandOperationalMeter(
          label: label,
          value: value,
          color: color,
          helper: helper,
          unavailable: unavailable,
          valueLabel: unavailable ? '--' : _percent(value),
          semicircular: false,
          gaugeSize: gaugeSize,
        ),
      );
    },
  );
}

class _RedisHitGauge extends StatelessWidget {
  const _RedisHitGauge({
    required this.rate,
    required this.hits,
    required this.misses,
    required this.tone,
  });
  final double rate;
  final int hits;
  final int misses;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = rate < 0.7
        ? colors.error
        : rate < 0.9
        ? OpenHandStatusColors.warning
        : tone;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gaugeSize = constraints.maxWidth.isFinite
            ? math.min(220.0, constraints.maxWidth)
            : 220.0;
        final gauge = OpenHandOperationalMeter(
          label: '当前命中率',
          value: rate,
          color: status,
          valueLabel: _percent(rate),
          semicircular: false,
          gaugeSize: gaugeSize,
        );
        final facts = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GaugeFact(label: '累计命中', value: _compactCount(hits), color: tone),
            kOpenHandGap8,
            _GaugeFact(
              label: '累计未命中',
              value: _compactCount(misses),
              color: colors.error,
            ),
            kOpenHandGap8,
            _GaugeFact(
              label: '总请求',
              value: _compactCount(hits + misses),
              color: colors.primary,
            ),
          ],
        );
        return constraints.maxWidth < 600
            ? Column(children: [gauge, kOpenHandGap10, facts])
            : Row(
                children: [
                  Expanded(child: gauge),
                  kOpenHandHGap24,
                  Expanded(child: facts),
                ],
              );
      },
    );
  }
}

class _GaugeFact extends StatelessWidget {
  const _GaugeFact({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      kOpenHandHGap8,
      Expanded(child: Text(label)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}

class _LatencyDistribution extends StatelessWidget {
  const _LatencyDistribution({
    required this.average,
    required this.p95,
    required this.p99,
  });
  final double average;
  final double p95;
  final double p99;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return OpenHandOperationalLatencyRange(
      segments: [
        OpenHandChartSegment(
          label: '平均',
          value: average,
          color: colors.primary,
        ),
        OpenHandChartSegment(label: 'p95', value: p95, color: colors.primary),
        OpenHandChartSegment(label: 'p99', value: p99, color: colors.error),
      ],
      emptyLabel: '当前接口暂未提供命令延迟分位数',
    );
  }
}

class _InteractiveTrendChart extends StatelessWidget {
  const _InteractiveTrendChart({
    required this.times,
    required this.series,
    required this.unit,
    required this.formatValue,
    this.area = false,
    this.fixedMaximum,
  });
  final List<DateTime> times;
  final List<OpenHandChartSeries> series;
  final String unit;
  final String Function(double value) formatValue;
  final bool area;
  final double? fixedMaximum;

  @override
  Widget build(BuildContext context) {
    final count = series.fold<int>(
      times.length,
      (value, item) => math.min(value, item.values.length),
    );
    if (count < 2) {
      return const SizedBox(
        height: _kChartHeight,
        child: _InlineUnavailable(label: '等待更多趋势采样点'),
      );
    }
    final visibleTimes = times.take(count).toList(growable: false);
    return OpenHandZoomableOperationalTrendChart(
      series: series
          .map(
            (item) => OpenHandChartSeries(
              label: item.label,
              values: item.values.take(count).toList(growable: false),
              color: item.color,
            ),
          )
          .toList(growable: false),
      xLabels: visibleTimes.map(_clockText).toList(growable: false),
      sampleTimes: visibleTimes,
      valueSuffix: unit,
      formatValue: formatValue,
      area: area,
      fixedMaximum: fixedMaximum,
      emptyLabel: '等待更多趋势采样点',
      semanticLabel:
          '$unit 趋势，从 ${_clockText(visibleTimes.first)} 到 ${_clockText(visibleTimes.last)}，支持双指缩放',
      onSelectionChanged: null,
    );
  }
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return const <String, Object?>{};
}

List<Map<String, Object?>> _objectMaps(Object? value) {
  if (value is! Iterable) return <Map<String, Object?>>[];
  return value.map(_objectMap).where((item) => item.isNotEmpty).toList();
}

int _integer(Object? value) => switch (value) {
  int number => number,
  num number when number.isFinite => number.round(),
  String text => int.tryParse(text.trim()) ?? 0,
  _ => 0,
};

int? _integerOrNull(Object? value) {
  if (value == null) return null;
  return switch (value) {
    int number => number,
    num number when number.isFinite => number.round(),
    String text => int.tryParse(text.trim()),
    _ => null,
  };
}

double _number(Object? value) => switch (value) {
  num number when number.isFinite => number.toDouble(),
  String text => _finiteParsedNumber(text),
  _ => 0,
};

double? _numberOrNull(Object? value) {
  if (value == null) return null;
  return switch (value) {
    num number when number.isFinite => number.toDouble(),
    String text => _parsedFiniteNumberOrNull(text),
    _ => null,
  };
}

double _normalizedRatio(Object? value) {
  final ratio = _number(value);
  if (!ratio.isFinite || ratio <= 0) return 0;
  if (ratio <= 1) return ratio.clamp(0.0, 1.0).toDouble();
  return (ratio / 100).clamp(0.0, 1.0).toDouble();
}

double _finiteParsedNumber(String value) {
  final parsed = double.tryParse(value.trim());
  return parsed != null && parsed.isFinite ? parsed : 0;
}

double? _parsedFiniteNumberOrNull(String value) {
  final parsed = double.tryParse(value.trim());
  return parsed != null && parsed.isFinite ? parsed : null;
}

Map<String, int> _stringIntMap(Object? value) {
  final source = _objectMap(value);
  return <String, int>{
    for (final entry in source.entries) entry.key: _integer(entry.value),
  };
}

Map<String, Object?> _postgresqlTelemetry(Map<String, Object?> overview) =>
    _objectMap(_objectMap(overview['postgresql'])['telemetry']);

Map<String, Object?> _redisOverview(Map<String, Object?> overview) =>
    _objectMap(overview['redis']);

List<DateTime> _sampleTimes(List<DependencyTelemetrySample> samples) =>
    samples.map((sample) => sample.capturedAt).toList(growable: false);

List<double> _sampleValues(
  List<DependencyTelemetrySample> samples,
  double Function(DependencyTelemetrySample sample) valueOf,
) => samples
    .map((sample) {
      final value = valueOf(sample);
      return value.isFinite && value >= 0 ? value : 0.0;
    })
    .toList(growable: false);

List<double> _seriesRate(
  List<DependencyTelemetrySample> samples,
  int Function(DependencyTelemetrySample sample) valueOf,
) {
  if (samples.isEmpty) return const <double>[];
  final rates = <double>[0];
  for (var index = 1; index < samples.length; index++) {
    final previous = valueOf(samples[index - 1]).toDouble();
    final current = valueOf(samples[index]).toDouble();
    final seconds =
        samples[index].capturedAt
            .difference(samples[index - 1].capturedAt)
            .inMilliseconds /
        Duration.millisecondsPerSecond;
    rates.add(
      previous.isFinite &&
              current.isFinite &&
              seconds > 0 &&
              current >= previous
          ? (current - previous) / seconds
          : 0,
    );
  }
  return rates;
}

double _lastValue(List<double> values) => values.isEmpty ? 0 : values.last;

String _capturedAt(Map<String, Object?> overview) {
  final parsed = DateTime.tryParse(
    '${overview['capturedAt'] ?? ''}',
  )?.toLocal();
  return parsed == null ? '--' : _dateTime(parsed);
}

String _dateTimeText(Object? value) {
  final parsed = DateTime.tryParse('${value ?? ''}')?.toLocal();
  return parsed == null ? '--' : _dateTime(parsed);
}

String _dateTime(DateTime value) => formatListDateTime(value);

String _clockText(DateTime value) => formatHourMinuteSecond(value);

String _percent(double value) {
  final safe = value.isFinite ? value.clamp(0.0, 1.0) : 0;
  return '${(safe * 100).toStringAsFixed(1)}%';
}

String _compactCount(int value) => formatCompactCount(value);

Color _sessionStateColor(BuildContext context, String raw) {
  final colors = Theme.of(context).colorScheme;
  final value = raw.trim().toLowerCase();
  if (value.contains('active')) return OpenHandStatusColors.success;
  if (value.contains('idle in transaction')) {
    return OpenHandStatusColors.warning;
  }
  if (value.contains('abort') || value.contains('disabled')) {
    return OpenHandStatusColors.error;
  }
  return colors.onSurfaceVariant;
}

String _durationText(int seconds) {
  if (seconds < 0) return '永久';
  if (seconds < Duration.secondsPerMinute) return '$seconds 秒';
  if (seconds < Duration.secondsPerHour) {
    return '${(seconds / Duration.secondsPerMinute).toStringAsFixed(1)} 分钟';
  }
  if (seconds < Duration.secondsPerDay) {
    return '${(seconds / Duration.secondsPerHour).toStringAsFixed(1)} 小时';
  }
  return '${(seconds / Duration.secondsPerDay).toStringAsFixed(1)} 天';
}

String _ttlText(int ttlSeconds) {
  if (ttlSeconds < 0) return '永久';
  if (ttlSeconds == 0) return '已过期';
  return _durationText(ttlSeconds);
}

String? _fastestGrowingTable(List<DependencyTelemetrySample> samples) {
  if (samples.length < 2) return null;
  final first = _objectMaps(
    _objectMap(samples.first.overview['postgresql'])['tables'],
  );
  final last = _objectMaps(
    _objectMap(samples.last.overview['postgresql'])['tables'],
  );
  if (first.isEmpty || last.isEmpty) return null;
  final initial = <String, int>{
    for (final table in first)
      '${table['name'] ?? ''}': _integer(table['totalBytes']),
  };
  String? name;
  var growth = 0;
  for (final table in last) {
    final tableName = '${table['name'] ?? ''}';
    final delta = _integer(table['totalBytes']) - (initial[tableName] ?? 0);
    if (delta > growth) {
      name = tableName;
      growth = delta;
    }
  }
  return name == null ? null : '$name · +${formatByteSize(growth)}';
}

List<_AnomalyRow> _postgresqlTransactionAnomalies(
  List<DependencyTelemetrySample> samples,
) {
  final rows = <_AnomalyRow>[];
  for (var index = 1; index < samples.length; index++) {
    final previous = _postgresqlTelemetry(samples[index - 1].overview);
    final current = _postgresqlTelemetry(samples[index].overview);
    final rollbackDelta = _counterDelta(
      _integer(previous['transactionsRolledBack']),
      _integer(current['transactionsRolledBack']),
    );
    final deadlockDelta = _counterDelta(
      _integer(previous['deadlocks']),
      _integer(current['deadlocks']),
    );
    if (deadlockDelta > 0) {
      rows.add(
        _AnomalyRow(
          time: _clockText(samples[index].capturedAt),
          title: '新增 $deadlockDelta 次死锁',
          detail: '检查互相等待的锁顺序与长事务。',
          color: OpenHandStatusColors.error,
        ),
      );
    } else if (rollbackDelta > 0) {
      rows.add(
        _AnomalyRow(
          time: _clockText(samples[index].capturedAt),
          title: '新增 $rollbackDelta 次回滚',
          detail: '结合应用日志定位失败事务。',
          color: OpenHandStatusColors.warning,
        ),
      );
    }
  }
  return rows.reversed.toList(growable: false);
}

int _counterDelta(int previous, int current) =>
    current >= previous ? current - previous : 0;

List<_AnomalyRow> _networkAnomalies(
  List<DependencyTelemetrySample> samples,
  List<double> inputRates,
  List<double> outputRates,
) {
  if (samples.length < 3 ||
      inputRates.length != samples.length ||
      outputRates.length != samples.length) {
    return const <_AnomalyRow>[];
  }
  final inputAverage =
      inputRates.skip(1).fold<double>(0, (sum, value) => sum + value) /
      math.max(1, inputRates.length - 1);
  final outputAverage =
      outputRates.skip(1).fold<double>(0, (sum, value) => sum + value) /
      math.max(1, outputRates.length - 1);
  final rows = <_AnomalyRow>[];
  for (var index = 1; index < samples.length; index++) {
    final inputSpike =
        inputAverage > 0 && inputRates[index] >= inputAverage * 2;
    final outputSpike =
        outputAverage > 0 && outputRates[index] >= outputAverage * 2;
    if (!inputSpike && !outputSpike) continue;
    rows.add(
      _AnomalyRow(
        time: _clockText(samples[index].capturedAt),
        title: inputSpike && outputSpike
            ? '双向流量突增'
            : inputSpike
            ? '输入流量突增'
            : '输出流量突增',
        detail:
            '输入 ${formatByteSize(inputRates[index].round())}/s · 输出 ${formatByteSize(outputRates[index].round())}/s',
        color: OpenHandStatusColors.warning,
      ),
    );
  }
  return rows.reversed.toList(growable: false);
}

List<_BreakdownItem> _breakdownFromMap(
  BuildContext context,
  Map<String, int> values,
) {
  final colors = Theme.of(context).colorScheme;
  final palette = <Color>[
    colors.primary,
    colors.tertiary,
    OpenHandStatusColors.success,
    OpenHandStatusColors.warning,
    colors.secondary,
    OpenHandStatusColors.info,
  ];
  final sorted = values.entries.toList()
    ..sort((left, right) {
      final byValue = right.value.compareTo(left.value);
      return byValue != 0 ? byValue : left.key.compareTo(right.key);
    });
  const visibleCategoryLimit = 5;
  final visible = sorted.take(visibleCategoryLimit).toList(growable: false);
  final other = sorted
      .skip(visibleCategoryLimit)
      .fold<int>(0, (sum, entry) => sum + entry.value);
  Color stableColor(String key) {
    final hash = key.codeUnits.fold<int>(0, (value, unit) => value * 31 + unit);
    // abs() 在 int.minValue 时仍返回负数，取无符号模避免负索引。
    final index = hash.abs() % palette.length;
    return palette[index < 0 ? index + palette.length : index];
  }

  return <_BreakdownItem>[
    for (final entry in visible)
      _BreakdownItem(entry.key, entry.value, stableColor(entry.key)),
    if (other > 0) _BreakdownItem('其他', other, colors.outline),
  ];
}
