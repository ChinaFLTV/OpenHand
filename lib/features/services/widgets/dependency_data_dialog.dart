import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_trailing_toolbar.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';
import '../model/ai_exposure_models.dart';
import '../services_controller.dart';
import '../services_errors.dart';
import 'dependency_metric_detail_dialog.dart';
import 'postgresql_record_editor.dart';
import 'redis_record_editor.dart';
import 'service_dialog_controls.dart';

const Duration _kTelemetryRefreshInterval = Duration(seconds: 8);
const Duration _kTelemetryRefreshTimeout = Duration(seconds: 20);
const double _kPostgresqlTableFieldWidth = 190;
const double _kRedisSearchFieldWidth = 220;
const double _kRecordCompactBreakpoint = 520;
const double _kSurfaceSectionCompactBreakpoint = 680;
const double _kDependencyRecordListMaxHeight = 460;
const EdgeInsets _kToolbarFieldPadding = EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 11,
);
const ButtonStyle _kToolbarButtonStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(0, 44)),
  padding: WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  ),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: kOpenHandBorderRadius8),
  ),
);
const List<String> _kPostgresqlTables = <String>[
  'hunt_jobs',
  'hunt_results',
  'hunt_job_logs',
  'hunt_scanned_targets',
];
const Map<String, String> _kPostgresqlTableLabels = <String, String>{
  'hunt_jobs': '扫描任务',
  'hunt_results': '扫描结果',
  'hunt_job_logs': '任务日志',
  'hunt_scanned_targets': '增量目标',
};

enum DependencyDataView { postgresql, redis }

Future<void> showAiExposureDependencyDataDialog(
  BuildContext context, {
  DependencyDataView initialView = DependencyDataView.postgresql,
}) => showAnimatedDialog<void>(
  context: context,
  builder: (_) => buildOpenHandDialog(
    maxWidth: kOpenHandDialogWidthExtraWide,
    maxHeight: kOpenHandDialogHeightTall,
    child: ServiceDialogInteractionTheme(
      child: _DependencyDataDialog(initialView: initialView),
    ),
  ),
);

class _DependencyDataDialog extends StatefulWidget {
  const _DependencyDataDialog({required this.initialView});

  final DependencyDataView initialView;

  @override
  State<_DependencyDataDialog> createState() => _DependencyDataDialogState();
}

class _DependencyDataDialogState extends State<_DependencyDataDialog> {
  late DependencyDataView _view = widget.initialView;
  final TextEditingController _redisSearch = TextEditingController();
  final TextEditingController _query = TextEditingController(
    text:
        'SELECT id, name, stage, created_at FROM hunt_jobs ORDER BY created_at DESC',
  );
  Timer? _telemetryTimer;
  String _table = _kPostgresqlTables.first;
  Map<String, Object?> _postgresPage = const <String, Object?>{};
  Map<String, Object?> _redisPage = const <String, Object?>{};
  List<Object?> _queryRows = const <Object?>[];
  final List<int> _redisCursorHistory = <int>[0];
  int _postgresOffset = 0;
  bool _loading = false;
  bool _operating = false;
  bool _queryVisible = false;
  bool _metricDialogOpen = false;

  bool get _busy => _loading || _operating;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refresh(includeData: true),
    );
    _telemetryTimer = startNonOverlappingPeriodicTimer(
      _kTelemetryRefreshInterval,
      (_) async {
        if (!mounted || _operating || _loading) return;
        await context
            .read<ServicesController>()
            .refreshDependencyDataOverview();
      },
      callbackTimeout: _kTelemetryRefreshTimeout,
      onError: (error, stack) =>
          silentLog('dependency_data_dialog', '刷新依赖遥测', error, stack),
    );
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _redisSearch.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _refresh({
    required bool includeData,
    bool forcePluginRescan = false,
  }) async {
    if (_loading || !mounted) return;
    setState(() => _loading = true);
    final controller = context.read<ServicesController>();
    try {
      if (forcePluginRescan) {
        await controller.refreshData(forcePluginRescan: true);
      }
      await controller.refreshDependencyDataOverview();
      if (includeData) {
        if (_view == DependencyDataView.postgresql &&
            controller.dependencyStatus?.postgresql.connected == true) {
          _postgresPage = await controller.loadPostgresqlRows(
            _table,
            offset: _postgresOffset,
          );
        } else if (_view == DependencyDataView.redis &&
            controller.dependencyStatus?.redis.connected == true) {
          _redisPage = await controller.loadRedisRecords(
            cursor: _redisCursorHistory.last,
            search: _redisSearch.text,
          );
        }
      }
    } catch (error, stack) {
      final message = reportServicesFailure(
        'dependency_data_dialog',
        '刷新运行依赖数据',
        error,
        stack,
        fallback: '运行依赖数据刷新失败，请稍后重试。',
      );
      if (mounted) showOpenHandErrorSnack(context, message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeView(DependencyDataView view) async {
    if (_view == view) return;
    setState(() {
      _view = view;
      _queryVisible = false;
    });
    await _refresh(includeData: true);
  }

  @override
  Widget build(BuildContext context) {
    final dependencyStatus = context
        .select<ServicesController, AiExposureDependencyStatus?>(
          (controller) => controller.dependencyStatus,
        );
    final dependencyDataOverview = context
        .select<ServicesController, Map<String, Object?>>(
          (controller) => controller.dependencyDataOverview,
        );
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = openHandTextResolver(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpenHandResponsiveHeaderLayout(
            compactBreakpoint: 720,
            identity: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: kServiceInteractiveBorderRadius,
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    Icons.dns_rounded,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                kOpenHandHGap12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('依赖数据与遥测', style: theme.textTheme.titleLarge),
                      Text(
                        'PostgreSQL · Redis · ${_capturedAt(dependencyDataOverview)}',
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
            ),
            actions: ServiceDialogIconActions(
              children: [
                ServiceDialogHeaderIconButton(
                  tooltip: '刷新插件、数据与遥测',
                  onPressed: _busy
                      ? null
                      : () => _refresh(
                          includeData: true,
                          forcePluginRescan: true,
                        ),
                  icon: _loading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                ServiceDialogHeaderIconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          kOpenHandGap14,
          SegmentedButton<DependencyDataView>(
            segments: const [
              ButtonSegment(
                value: DependencyDataView.postgresql,
                icon: Icon(Icons.storage_rounded),
                label: Text('PostgreSQL'),
              ),
              ButtonSegment(
                value: DependencyDataView.redis,
                icon: Icon(Icons.hub_rounded),
                label: Text('Redis'),
              ),
            ],
            selected: <DependencyDataView>{_view},
            onSelectionChanged: _busy
                ? null
                : (selection) => _changeView(selection.first),
          ),
          kOpenHandGap14,
          Expanded(
            child: AnimatedSwitcher(
              duration: openHandMotionDuration(context, kOpenHandMotion220),
              switchInCurve: kOpenHandSwitchInCurve,
              switchOutCurve: kOpenHandSwitchOutCurve,
              transitionBuilder: (child, animation) {
                final offset = Tween<Offset>(
                  begin: const Offset(0.018, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: SingleChildScrollView(
                key: ValueKey<DependencyDataView>(_view),
                physics: openHandDialogAwareScrollPhysics(context),
                child: _view == DependencyDataView.postgresql
                    ? _buildPostgresql(
                        dependencyStatus,
                        dependencyDataOverview,
                        text,
                      )
                    : _buildRedis(
                        dependencyStatus,
                        dependencyDataOverview,
                        text,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostgresql(
    AiExposureDependencyStatus? dependencyStatus,
    Map<String, Object?> dependencyDataOverview,
    OpenHandLocalizedTextResolver text,
  ) {
    final connected = dependencyStatus?.postgresql.connected == true;
    final overview = _map(dependencyDataOverview['postgresql']);
    final telemetry = _map(overview['telemetry']);
    final tables = _maps(overview['tables']);
    final rows = _maps(_postgresPage['rows']);
    final columns = _maps(_postgresPage['columns']);
    final primaryKeys = _strings(_postgresPage['primaryKeys']);
    final total = _integer(_postgresPage['total']);
    final hitBlocks = _integer(telemetry['blocksHit']);
    final readBlocks = _integer(telemetry['blocksRead']);
    final hitRate = hitBlocks + readBlocks == 0
        ? 0.0
        : hitBlocks / (hitBlocks + readBlocks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TelemetryGrid(
          children: [
            _TelemetryTile(
              icon: Icons.storage_rounded,
              label: '数据库容量',
              value: connected
                  ? formatByteSize(_integer(telemetry['databaseSizeBytes']))
                  : '--',
              detail: '${telemetry['serverVersion'] ?? '未连接'}',
              color: OpenHandStatusColors.success,
              onTap: () =>
                  _showMetricDetail(DependencyMetricKind.postgresqlCapacity),
            ),
            _TelemetryTile(
              icon: Icons.lan_outlined,
              label: '活跃连接',
              value:
                  '${_integer(telemetry['activeConnections'])}/${_integer(telemetry['maxConnections'])}',
              detail:
                  '连接池 ${_integer(overview['poolSize'])} · 空闲 ${_integer(overview['idleConnections'])}',
              color: Theme.of(context).colorScheme.primary,
              onTap: () =>
                  _showMetricDetail(DependencyMetricKind.postgresqlConnections),
            ),
            _TelemetryTile(
              icon: Icons.speed_rounded,
              label: '缓存命中率',
              value: '${(hitRate * 100).toStringAsFixed(1)}%',
              detail: '命中 $hitBlocks · 读取 $readBlocks',
              color: OpenHandStatusColors.info,
              onTap: () =>
                  _showMetricDetail(DependencyMetricKind.postgresqlCache),
            ),
            _TelemetryTile(
              icon: Icons.commit_rounded,
              label: '事务提交',
              value: '${_integer(telemetry['transactionsCommitted'])}',
              detail:
                  '回滚 ${_integer(telemetry['transactionsRolledBack'])} · 死锁 ${_integer(telemetry['deadlocks'])}',
              color: Theme.of(context).colorScheme.tertiary,
              onTap: () => _showMetricDetail(
                DependencyMetricKind.postgresqlTransactions,
              ),
            ),
          ],
        ),
        kOpenHandGap12,
        _DependencyNotice(
          connected: connected,
          message: dependencyStatus?.postgresql.message ?? '未启用',
        ),
        if (connected) ...[
          kOpenHandGap12,
          _SurfaceSection(
            title: '数据表与记录',
            icon: Icons.table_rows_rounded,
            trailing: _SurfaceToolbar(
              fieldWidth: _kPostgresqlTableFieldWidth,
              field: AnimatedDropdownButtonFormField<String>(
                initialValue: _table,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '数据表',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: _kToolbarFieldPadding,
                ),
                items: _kPostgresqlTables
                    .map(
                      (table) => DropdownMenuItem(
                        value: table,
                        child: Text(_kPostgresqlTableLabels[table] ?? table),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _busy
                    ? null
                    : (value) async {
                        if (value == null) return;
                        setState(() {
                          _table = value;
                          _postgresOffset = 0;
                        });
                        await _refresh(includeData: true);
                      },
              ),
              actions: [
                FilledButton.icon(
                  style: _kToolbarButtonStyle,
                  onPressed: _busy
                      ? null
                      : () => setState(() => _queryVisible = !_queryVisible),
                  icon: const Icon(Icons.terminal_rounded, size: 19),
                  label: const Text('只读查询'),
                ),
                FilledButton.icon(
                  style: _kToolbarButtonStyle,
                  onPressed: _busy
                      ? null
                      : () => _editPostgresql(columns: columns),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增记录'),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSize(
                  duration: openHandMotionDuration(context, kOpenHandMotion220),
                  curve: kOpenHandSwitchInCurve,
                  child: !_queryVisible
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _QueryConsole(
                            controller: _query,
                            rows: _queryRows,
                            busy: _busy,
                            onRun: _runQuery,
                          ),
                        ),
                ),
                if (tables.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 8.0;
                      final columns = constraints.maxWidth >= 760
                          ? 4
                          : constraints.maxWidth >= 420
                          ? 2
                          : 1;
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: tables
                            .map(
                              (table) => SizedBox(
                                width: width,
                                child: _MiniMetric(
                                  label:
                                      _kPostgresqlTableLabels['${table['name']}'] ??
                                      '${table['name']}',
                                  value: '${_integer(table['rowCount'])} 条',
                                  helper: formatByteSize(
                                    _integer(table['totalBytes']),
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      );
                    },
                  ),
                if (tables.isNotEmpty) kOpenHandGap12,
                if (rows.isEmpty)
                  const _EmptyState(
                    icon: Icons.inbox_outlined,
                    label: '当前数据表暂无记录',
                  )
                else
                  _DependencyRecordList(
                    children: rows
                        .map(
                          (row) => _DataRecordTile(
                            title: _postgresRowTitle(row, primaryKeys),
                            subtitle: _postgresRowSubtitle(row, primaryKeys),
                            record: row,
                            tags: row.entries
                                .where(
                                  (entry) => !primaryKeys.contains(entry.key),
                                )
                                .take(4)
                                .map(
                                  (entry) =>
                                      '${entry.key}: ${_compactValue(entry.value)}',
                                )
                                .toList(growable: false),
                            onEdit: _busy
                                ? null
                                : () => _editPostgresql(
                                    columns: columns,
                                    row: row,
                                    primaryKeys: primaryKeys,
                                  ),
                            onDelete: _busy
                                ? null
                                : () => _deletePostgresql(row, primaryKeys),
                          ),
                        )
                        .toList(growable: false),
                  ),
                kOpenHandGap8,
                _PaginationBar(
                  summary: '共 $total 条',
                  page: '${_postgresOffset ~/ 50 + 1}',
                  onPrevious: _postgresOffset <= 0 || _busy
                      ? null
                      : () {
                          setState(() => _postgresOffset -= 50);
                          _refresh(includeData: true);
                        },
                  onNext:
                      _postgresOffset + rows.length >= total ||
                          rows.isEmpty ||
                          _busy
                      ? null
                      : () {
                          setState(() => _postgresOffset += 50);
                          _refresh(includeData: true);
                        },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRedis(
    AiExposureDependencyStatus? dependencyStatus,
    Map<String, Object?> dependencyDataOverview,
    OpenHandLocalizedTextResolver text,
  ) {
    final connected = dependencyStatus?.redis.connected == true;
    final overview = _map(dependencyDataOverview['redis']);
    final records = _maps(_redisPage['records']);
    final nextCursor = _integer(_redisPage['nextCursor']);
    final hitRate = _number(overview['hitRate']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TelemetryGrid(
          children: [
            _TelemetryTile(
              icon: Icons.memory_rounded,
              label: '内存占用',
              value: connected
                  ? formatByteSize(_integer(overview['usedMemoryBytes']))
                  : '--',
              detail:
                  '峰值 ${formatByteSize(_integer(overview['peakMemoryBytes']))} · 碎片 ${_number(overview['memoryFragmentationRatio']).toStringAsFixed(2)}',
              color: OpenHandStatusColors.success,
              onTap: () => _showMetricDetail(DependencyMetricKind.redisMemory),
            ),
            _TelemetryTile(
              icon: Icons.key_rounded,
              label: '键空间',
              value: '${_integer(overview['keyCount'])}',
              detail:
                  '过期 ${_integer(overview['expiredKeys'])} · 驱逐 ${_integer(overview['evictedKeys'])}',
              color: Theme.of(context).colorScheme.primary,
              onTap: () =>
                  _showMetricDetail(DependencyMetricKind.redisKeyspace),
            ),
            _TelemetryTile(
              icon: Icons.speed_rounded,
              label: '实时吞吐',
              value: '${_integer(overview['operationsPerSecond'])} ops/s',
              detail: '累计 ${_integer(overview['totalCommands'])} 条命令',
              color: OpenHandStatusColors.info,
              onTap: () =>
                  _showMetricDetail(DependencyMetricKind.redisThroughput),
            ),
            _TelemetryTile(
              icon: Icons.track_changes_rounded,
              label: '缓存命中率',
              value: '${(hitRate * 100).toStringAsFixed(1)}%',
              detail:
                  '命中 ${_integer(overview['keyspaceHits'])} · 未命中 ${_integer(overview['keyspaceMisses'])}',
              color: Theme.of(context).colorScheme.tertiary,
              onTap: () => _showMetricDetail(DependencyMetricKind.redisCache),
            ),
            _TelemetryTile(
              icon: Icons.group_outlined,
              label: '客户端',
              value: '${_integer(overview['connectedClients'])}',
              detail: '阻塞 ${_integer(overview['blockedClients'])}',
              color: Theme.of(context).colorScheme.secondary,
              onTap: () => _showMetricDetail(DependencyMetricKind.redisClients),
            ),
            _TelemetryTile(
              icon: Icons.swap_vert_circle_outlined,
              label: '网络流量',
              value: formatByteSize(
                _integer(overview['networkInputBytes']) +
                    _integer(overview['networkOutputBytes']),
              ),
              detail:
                  '入 ${formatByteSize(_integer(overview['networkInputBytes']))} · 出 ${formatByteSize(_integer(overview['networkOutputBytes']))}',
              color: const Color(0xff0f766e),
              onTap: () => _showMetricDetail(DependencyMetricKind.redisNetwork),
            ),
          ],
        ),
        kOpenHandGap12,
        _DependencyNotice(
          connected: connected,
          message: dependencyStatus?.redis.message ?? '未启用',
        ),
        if (connected) ...[
          kOpenHandGap12,
          _SurfaceSection(
            title: '键值与 TTL',
            icon: Icons.key_rounded,
            trailing: _SurfaceToolbar(
              fieldWidth: _kRedisSearchFieldWidth,
              field: TextField(
                controller: _redisSearch,
                enabled: !_busy,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchRedis(),
                decoration: InputDecoration(
                  hintText: '搜索键',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: _kToolbarFieldPadding,
                  suffixIcon: ServiceDialogCompactIconButton(
                    tooltip: '搜索',
                    onPressed: _busy ? null : _searchRedis,
                    icon: const Icon(Icons.search_rounded, size: 19),
                  ),
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                ),
              ),
              actions: [
                FilledButton.icon(
                  style: _kToolbarButtonStyle,
                  onPressed: _busy ? null : _editRedis,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增键'),
                ),
              ],
            ),
            child: Column(
              children: [
                if (records.isEmpty)
                  const _EmptyState(
                    icon: Icons.key_off_outlined,
                    label: '当前命名空间暂无键',
                  )
                else
                  _DependencyRecordList(
                    children: records
                        .map(
                          (record) => _DataRecordTile(
                            title: '${record['key'] ?? '--'}',
                            subtitle:
                                '${record['type'] ?? 'none'} · ${_ttlText(_integer(record['ttlSeconds']))} · ${formatByteSize(_integer(record['sizeBytes']))}',
                            record: record,
                            tags: [
                              if (record['protected'] == true) '运行数据 · 只读',
                              _compactValue(record['value'], maxChars: 180),
                            ],
                            onEdit: record['protected'] == true || _busy
                                ? null
                                : () => _editRedis(record: record),
                            onDelete: record['protected'] == true || _busy
                                ? null
                                : () {
                                    final key = '${record['key']}';
                                    if (key.isEmpty || key == 'null') return;
                                    _deleteRedis(key);
                                  },
                          ),
                        )
                        .toList(growable: false),
                  ),
                kOpenHandGap8,
                _PaginationBar(
                  summary: '游标 ${_redisCursorHistory.last}',
                  onPrevious: _redisCursorHistory.length <= 1 || _busy
                      ? null
                      : () {
                          setState(() => _redisCursorHistory.removeLast());
                          _refresh(includeData: true);
                        },
                  onNext: nextCursor == 0 || _busy
                      ? null
                      : () {
                          setState(() => _redisCursorHistory.add(nextCursor));
                          _refresh(includeData: true);
                        },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _editPostgresql({
    required List<Map<String, Object?>> columns,
    Map<String, Object?>? row,
    List<String> primaryKeys = const <String>[],
  }) async {
    final values = await showPostgresqlRecordEditor(
      context,
      title: row == null ? '新增 PostgreSQL 记录' : '编辑 PostgreSQL 记录',
      initial: row ?? const <String, Object?>{},
      columns: columns,
      primaryKeys: primaryKeys,
    );
    if (values == null || !mounted) return;
    setState(() => _operating = true);
    try {
      final controller = context.read<ServicesController>();
      if (row == null) {
        await controller.insertPostgresqlRow(_table, values);
      } else {
        final keys = <String, Object?>{
          for (final key in primaryKeys) key: row[key],
        };
        final editable = Map<String, Object?>.of(values)
          ..removeWhere((key, _) => primaryKeys.contains(key));
        await controller.updatePostgresqlRow(
          _table,
          keys: keys,
          values: editable,
        );
      }
      if (mounted) showOpenHandSuccessSnack(context, 'PostgreSQL 记录已保存');
      await _refresh(includeData: true);
    } catch (error, stack) {
      final message = reportServicesFailure(
        'dependency_data_dialog',
        '保存 PostgreSQL 记录',
        error,
        stack,
        fallback: 'PostgreSQL 记录保存失败，请稍后重试。',
      );
      if (mounted) showOpenHandErrorSnack(context, message);
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _deletePostgresql(
    Map<String, Object?> row,
    List<String> primaryKeys,
  ) async {
    final keys = <String, Object?>{
      for (final key in primaryKeys) key: row[key],
    };
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: '删除 PostgreSQL 记录？',
      message: keys.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join(' · '),
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _operating = true);
    try {
      await context.read<ServicesController>().deletePostgresqlRow(
        _table,
        keys,
      );
      if (mounted) showOpenHandSuccessSnack(context, 'PostgreSQL 记录已删除');
      await _refresh(includeData: true);
    } catch (error, stack) {
      final message = reportServicesFailure(
        'dependency_data_dialog',
        '删除 PostgreSQL 记录',
        error,
        stack,
        fallback: 'PostgreSQL 记录删除失败，请稍后重试。',
      );
      if (mounted) showOpenHandErrorSnack(context, message);
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _runQuery() async {
    if (_busy || _query.text.trim().isEmpty) return;
    setState(() => _operating = true);
    try {
      final result = await context.read<ServicesController>().queryPostgresql(
        _query.text,
      );
      if (mounted) {
        final rows = _list(result['rows']);
        setState(() => _queryRows = rows);
        showOpenHandSuccessSnack(context, '查询完成 · ${_queryRows.length} 行');
      }
    } catch (error, stack) {
      final message = reportServicesFailure(
        'dependency_data_dialog',
        '执行 PostgreSQL 查询',
        error,
        stack,
        fallback: 'PostgreSQL 查询失败，请检查查询语句。',
      );
      if (mounted) showOpenHandErrorSnack(context, message);
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _searchRedis() async {
    if (_busy) return;
    _redisCursorHistory
      ..clear()
      ..add(0);
    await _refresh(includeData: true);
  }

  Future<void> _editRedis({Map<String, Object?>? record}) async {
    final result = await showAnimatedDialog<RedisRecordEditorResult>(
      context: context,
      builder: (_) => buildOpenHandDialog(
        maxWidth: kOpenHandDialogWidthCompact,
        maxHeight: kOpenHandDialogHeightTall,
        child: ServiceDialogInteractionTheme(
          child: RedisRecordEditor(record: record),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _operating = true);
    try {
      await context.read<ServicesController>().putRedisRecord(
        key: result.key,
        type: result.type,
        value: result.value,
        ttlSeconds: result.ttlSeconds,
      );
      if (mounted) showOpenHandSuccessSnack(context, 'Redis 键已保存');
      await _refresh(includeData: true);
    } catch (error, stack) {
      final message = reportServicesFailure(
        'dependency_data_dialog',
        '保存 Redis 键',
        error,
        stack,
        fallback: 'Redis 键保存失败，请稍后重试。',
      );
      if (mounted) showOpenHandErrorSnack(context, message);
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _deleteRedis(String key) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: '删除 Redis 键？',
      message: key,
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _operating = true);
    try {
      await context.read<ServicesController>().deleteRedisRecord(key);
      if (mounted) showOpenHandSuccessSnack(context, 'Redis 键已删除');
      await _refresh(includeData: true);
    } catch (error, stack) {
      final message = reportServicesFailure(
        'dependency_data_dialog',
        '删除 Redis 键',
        error,
        stack,
        fallback: 'Redis 键删除失败，请稍后重试。',
      );
      if (mounted) showOpenHandErrorSnack(context, message);
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _showMetricDetail(DependencyMetricKind kind) async {
    if (_metricDialogOpen || !mounted) return;
    _metricDialogOpen = true;
    final overview = context.read<ServicesController>().dependencyDataOverview;
    final postgresql = _map(overview['postgresql']);
    try {
      await showDependencyMetricDetailDialog(
        context,
        kind: kind,
        postgresqlTables: _maps(postgresql['tables']),
        redisRecords: _maps(_redisPage['records']),
        onReload: () => _refresh(includeData: true, forcePluginRescan: true),
      );
    } finally {
      _metricDialogOpen = false;
    }
  }
}

class _TelemetryGrid extends StatelessWidget {
  const _TelemetryGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 840
          ? children.length == 4
                ? 4
                : 3
          : constraints.maxWidth >= 620
          ? children.length == 4
                ? 2
                : 3
          : constraints.maxWidth >= 420
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );
}

class _TelemetryTile extends StatefulWidget {
  const _TelemetryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_TelemetryTile> createState() => _TelemetryTileState();
}

class _TelemetryTileState extends State<_TelemetryTile> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = openHandMotionDuration(context, kOpenHandMotion140);
    final highlighted = _hovered || _focused;
    return Semantics(
      button: true,
      label: '${widget.label}，${widget.value}，打开详情',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _pressed ? 0.975 : 1,
          duration: duration,
          curve: kOpenHandSwitchInCurve,
          child: AnimatedContainer(
            duration: duration,
            curve: kOpenHandSwitchInCurve,
            constraints: const BoxConstraints(minHeight: 112),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: highlighted ? 0.12 : 0.08),
              borderRadius: kServiceInteractiveBorderRadius,
              border: Border.all(
                color: widget.color.withValues(
                  alpha: highlighted ? 0.62 : 0.28,
                ),
                width: _focused ? 1.6 : 1,
              ),
              boxShadow: highlighted
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: kServiceInteractiveBorderRadius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                onHover: (value) => setState(() => _hovered = value),
                onFocusChange: (value) => setState(() => _focused = value),
                onHighlightChanged: (value) => setState(() => _pressed = value),
                borderRadius: kServiceInteractiveBorderRadius,
                overlayColor: WidgetStatePropertyAll(
                  widget.color.withValues(alpha: 0.08),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(widget.icon, size: 18, color: widget.color),
                          kOpenHandHGap8,
                          Expanded(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                          AnimatedSlide(
                            offset: highlighted
                                ? Offset.zero
                                : const Offset(-0.18, 0),
                            duration: duration,
                            curve: kOpenHandSwitchInCurve,
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 19,
                              color: widget.color.withValues(
                                alpha: highlighted ? 0.9 : 0.56,
                              ),
                            ),
                          ),
                        ],
                      ),
                      kOpenHandGap9,
                      Text(
                        widget.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      kOpenHandGap3,
                      Text(
                        widget.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DependencyNotice extends StatelessWidget {
  const _DependencyNotice({required this.connected, required this.message});

  final bool connected;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = connected
        ? OpenHandStatusColors.success
        : OpenHandStatusColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: kServiceInteractiveBorderRadius,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.check_circle_rounded : Icons.link_off_rounded,
            color: color,
          ),
          kOpenHandHGap10,
          Expanded(child: Text(message)),
          Text(
            connected ? '已就绪' : '未连接',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SurfaceSection extends StatelessWidget {
  const _SurfaceSection({
    required this.title,
    required this.icon,
    required this.trailing,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: kServiceInteractiveBorderRadius,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth < _kSurfaceSectionCompactBreakpoint
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(icon),
                          kOpenHandHGap8,
                          Text(title, style: theme.textTheme.titleMedium),
                        ],
                      ),
                      kOpenHandGap10,
                      trailing,
                    ],
                  )
                : Row(
                    children: [
                      Icon(icon),
                      kOpenHandHGap8,
                      Text(title, style: theme.textTheme.titleMedium),
                      kOpenHandHGap16,
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: trailing,
                        ),
                      ),
                    ],
                  ),
          ),
          kOpenHandGap14,
          child,
        ],
      ),
    );
  }
}

class _SurfaceToolbar extends StatelessWidget {
  const _SurfaceToolbar({
    required this.field,
    required this.fieldWidth,
    required this.actions,
  });

  final Widget field;
  final double fieldWidth;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Flexible(
        child: SizedBox(width: fieldWidth, child: field),
      ),
      for (final action in actions) ...[kOpenHandHGap8, action],
    ],
  );
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 150),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: kServiceInteractiveBorderRadius,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text('$value · $helper', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _DependencyRecordList extends StatefulWidget {
  const _DependencyRecordList({required this.children});

  final List<Widget> children;

  @override
  State<_DependencyRecordList> createState() => _DependencyRecordListState();
}

class _DependencyRecordListState extends State<_DependencyRecordList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(
      maxHeight: _kDependencyRecordListMaxHeight,
    ),
    child: Padding(
      padding: const EdgeInsets.only(right: 10),
      child: OpenHandSafeScrollbar(
        controller: _controller,
        thumbVisibility: true,
        interactive: true,
        thickness: 5,
        radius: kOpenHandPillRadius,
        scrollbarOrientation: ScrollbarOrientation.right,
        child: ListView(
          controller: _controller,
          primary: false,
          shrinkWrap: true,
          physics: openHandDialogAwareScrollPhysics(context),
          children: widget.children,
        ),
      ),
    ),
  );
}

class _DataRecordTile extends StatelessWidget {
  const _DataRecordTile({
    required this.title,
    required this.subtitle,
    required this.record,
    required this.tags,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final Map<String, Object?> record;
  final List<String> tags;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final leading = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: kServiceInteractiveBorderRadius,
      ),
      child: Icon(Icons.data_object_rounded, size: 19, color: colors.primary),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        kOpenHandGap2,
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (tags.isNotEmpty) ...[
          kOpenHandGap7,
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags
                .where((tag) => tag.isNotEmpty)
                .map(
                  (tag) => Container(
                    constraints: kOpenHandContentMaxWidth360,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(kOpenHandRadius6),
                    ),
                    child: Text(
                      tag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
    final actions = ServiceDialogIconActions(
      spacing: 4,
      children: [
        ServiceDialogCompactIconButton(
          tooltip: '查看完整数据',
          onPressed: () => showServiceDetailsDialog(
            context,
            title: title,
            subtitle: '数据记录详情',
            icon: Icons.data_object_rounded,
            presentation: ServiceDetailPresentation.record,
            fields: serviceDetailFieldsFromMap(record),
          ),
          icon: const Icon(Icons.arrow_forward_rounded, size: 19),
        ),
        ServiceDialogCompactIconButton(
          tooltip: '编辑',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 19),
        ),
        ServiceDialogCompactIconButton(
          tooltip: '删除',
          onPressed: onDelete,
          foregroundColor: OpenHandStatusColors.error,
          icon: const Icon(Icons.delete_outline_rounded, size: 19),
        ),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: kServiceInteractiveBorderRadius,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              kOpenHandHGap10,
              Expanded(child: details),
            ],
          );
          if (constraints.maxWidth < _kRecordCompactBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                kOpenHandGap4,
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: actions,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              kOpenHandHGap8,
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.summary,
    required this.onPrevious,
    required this.onNext,
    this.page,
  });

  final String summary;
  final String? page;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      ServiceDialogIconActions(
        spacing: 2,
        children: [
          ServiceDialogCompactIconButton(
            tooltip: '上一页',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
          ),
          if (page != null)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 24),
              child: Text(page!, textAlign: TextAlign.center),
            ),
          ServiceDialogCompactIconButton(
            tooltip: '下一页',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded, size: 22),
          ),
        ],
      ),
    ],
  );
}

class _QueryConsole extends StatelessWidget {
  const _QueryConsole({
    required this.controller,
    required this.rows,
    required this.busy,
    required this.onRun,
  });

  final TextEditingController controller;
  final List<Object?> rows;
  final bool busy;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xff0b0e12),
      borderRadius: kServiceInteractiveBorderRadius,
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(
            color: Color(0xffe5e7eb),
            fontFamily: 'monospace',
          ),
          decoration: const InputDecoration(
            labelText: '只读 SQL',
            labelStyle: TextStyle(color: Color(0xff9ca3af)),
            border: OutlineInputBorder(),
          ),
        ),
        kOpenHandGap8,
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            style: _kToolbarButtonStyle,
            onPressed: busy ? null : onRun,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('执行查询'),
          ),
        ),
        if (rows.isNotEmpty) ...[
          kOpenHandGap10,
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(rows),
                style: const TextStyle(
                  color: Color(0xffd1d5db),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Column(
      children: [
        Icon(icon, size: 32, color: Theme.of(context).colorScheme.outline),
        kOpenHandGap8,
        Text(label),
      ],
    ),
  );
}

Map<String, Object?> _map(Object? value) => value is Map
    ? <String, Object?>{
        for (final entry in value.entries) '${entry.key}': entry.value,
      }
    : const <String, Object?>{};

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

List<Map<String, Object?>> _maps(Object? value) =>
    _list(value).map(_map).toList(growable: false);

List<String> _strings(Object? value) =>
    _list(value).map((item) => '$item').toList(growable: false);

int _integer(Object? value) => optionalIntFromValue(value) ?? 0;

double _number(Object? value) => optionalDoubleFromValue(value) ?? 0;

String _capturedAt(Map<String, Object?> overview) {
  final parsed = DateTime.tryParse(
    '${overview['capturedAt'] ?? ''}',
  )?.toLocal();
  if (parsed == null) return '等待遥测';
  return formatHourMinuteSecond(parsed);
}

String _postgresRowTitle(Map<String, Object?> row, List<String> primaryKeys) =>
    primaryKeys.isEmpty
    ? _compactValue(row)
    : primaryKeys.map((key) => '$key=${_compactValue(row[key])}').join(' · ');

String _postgresRowSubtitle(
  Map<String, Object?> row,
  List<String> primaryKeys,
) => row.entries
    .where((entry) => !primaryKeys.contains(entry.key))
    .take(2)
    .map((entry) => '${entry.key}=${_compactValue(entry.value)}')
    .join(' · ');

String _compactValue(Object? value, {int maxChars = 80}) {
  final text = value is Map || value is List
      ? jsonEncode(value)
      : '${value ?? 'null'}';
  return text.length <= maxChars ? text : '${text.substring(0, maxChars)}...';
}

String _ttlText(int seconds) => seconds < 0 ? '永久' : '${seconds}s';
