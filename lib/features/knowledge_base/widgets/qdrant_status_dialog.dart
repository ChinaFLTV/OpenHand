import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/timer_safety.dart';
import '../knowledge_base_controller.dart';
import '../service/qdrant_monitoring_service.dart';
import 'knowledge_dialog_widgets.dart';

const int _qdrantTrendSampleCap = 48;
const int _qdrantMinRefreshSeconds = 3;
const int _qdrantMaxRefreshSeconds = 60;
const double _qdrantOpsDialogWidth = 980;
const double _qdrantOpsChartHeight = 172;
const Duration _qdrantRefreshTimeout = Duration(seconds: 30);

Future<void> showQdrantStatusDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => const QdrantStatusDialog(),
  );
}

class QdrantStatusDialog extends StatefulWidget {
  const QdrantStatusDialog({super.key});

  @override
  State<QdrantStatusDialog> createState() => _QdrantStatusDialogState();
}

class _QdrantStatusDialogState extends State<QdrantStatusDialog> {
  final TextEditingController _pointIds = TextEditingController();
  final TextEditingController _sourceId = TextEditingController();
  final TextEditingController _tag = TextEditingController();
  final TextEditingController _limit = TextEditingController(text: '20');
  final TextEditingController _rawVector = TextEditingController();

  Timer? _refreshTimer;
  QdrantMonitoringSnapshot? _snapshot;
  List<Map<String, Object?>> _collections = const <Map<String, Object?>>[];
  final List<_QdrantMetricSample> _samples = <_QdrantMetricSample>[];
  Map<String, Object?>? _operationResult;
  String? _error;
  bool _refreshInFlight = false;
  bool _refreshing = false;
  bool _operating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
      _startRefreshTimer();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pointIds.dispose();
    _sourceId.dispose();
    _tag.dispose();
    _limit.dispose();
    _rawVector.dispose();
    super.dispose();
  }

  void _startRefreshTimer() {
    final settings = context.read<KnowledgeBaseController>().settings;
    final seconds = settings.qdrantMetricsRefreshSeconds.clamp(
      _qdrantMinRefreshSeconds,
      _qdrantMaxRefreshSeconds,
    );
    _refreshTimer?.cancel();
    _refreshTimer = startNonOverlappingPeriodicTimer(
      Duration(seconds: seconds),
      (_) async {
        if (!_refreshInFlight && !_operating) {
          await _refresh(silent: true);
        }
      },
      min: const Duration(seconds: _qdrantMinRefreshSeconds),
      max: const Duration(seconds: _qdrantMaxRefreshSeconds),
    );
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshInFlight) {
      return;
    }
    _refreshInFlight = true;
    if (!silent) {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    }
    try {
      final controller = context.read<KnowledgeBaseController>();
      final results = await Future.wait<Object?>([
        controller.loadMonitoringSnapshot(),
        controller.listQdrantCollections(),
      ]).timeout(_qdrantRefreshTimeout);
      final snapshot = results[0] as QdrantMonitoringSnapshot;
      final collections = results[1] as List<Map<String, Object?>>;
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _collections = collections;
        _samples.add(_QdrantMetricSample.fromSnapshot(snapshot));
        if (_samples.length > _qdrantTrendSampleCap) {
          _samples.removeRange(0, _samples.length - _qdrantTrendSampleCap);
        }
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      _refreshInFlight = false;
      if (mounted && !silent) {
        setState(() => _refreshing = false);
      }
    }
  }

  List<String> _parseIds() {
    return splitLooseDelimitedValues(
      _pointIds.text,
    ).toSet().toList(growable: false);
  }

  List<double>? _parseVector(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    final values = splitLooseDelimitedValues(_rawVector.text);
    if (values.isEmpty) {
      OpenHandSnackBar.showError(
        context,
        isZh ? '请先输入 raw vector。' : 'Enter a raw vector first.',
      );
      return null;
    }
    final vector = <double>[];
    for (final value in values) {
      final parsed = double.tryParse(value);
      if (parsed == null || parsed.isNaN || !parsed.isFinite) {
        OpenHandSnackBar.showError(
          context,
          isZh ? '原始向量包含无效数值：$value' : 'Invalid vector number: $value',
        );
        return null;
      }
      vector.add(parsed);
    }
    final dimensions = context
        .read<KnowledgeBaseController>()
        .settings
        .dimensions;
    if (dimensions > 0 && vector.length != dimensions) {
      OpenHandSnackBar.showError(
        context,
        isZh
            ? '原始向量维度为 ${vector.length}，当前配置要求 $dimensions。'
            : 'Raw vector has ${vector.length} dimensions; current settings require $dimensions.',
      );
      return null;
    }
    return vector;
  }

  int _limitValue() {
    return clampedIntFromText(_limit.text, fallback: 20, min: 1, max: 200);
  }

  Map<String, Object?>? _filter() {
    final must = <Map<String, Object?>>[];
    final sourceId = _sourceId.text.trim();
    final tag = _tag.text.trim();
    if (sourceId.isNotEmpty) {
      must.add(<String, Object?>{
        'key': 'source_id',
        'match': <String, Object?>{'value': sourceId},
      });
    }
    if (tag.isNotEmpty) {
      must.add(<String, Object?>{
        'key': 'tags',
        'match': <String, Object?>{'value': tag},
      });
    }
    return must.isEmpty ? null : <String, Object?>{'must': must};
  }

  Future<void> _runOperation(
    Future<Map<String, Object?>> Function(KnowledgeBaseController controller)
    action,
  ) async {
    setState(() {
      _operating = true;
      _error = null;
    });
    try {
      final result = await action(context.read<KnowledgeBaseController>());
      if (!mounted) return;
      setState(() => _operationResult = result);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _loadPointIds() async {
    final isZh = openHandIsChineseLocale(context);
    final ids = _parseIds();
    if (ids.isEmpty) {
      OpenHandSnackBar.showError(
        context,
        isZh ? '请先输入 point/chunk id。' : 'Enter point/chunk IDs first.',
      );
      return;
    }
    await _runOperation((controller) => controller.loadQdrantPointsByIds(ids));
  }

  Future<void> _scrollPoints() async {
    await _runOperation(
      (controller) => controller.scrollQdrantPoints(
        limit: _limitValue(),
        filter: _filter(),
      ),
    );
  }

  Future<void> _searchVector() async {
    final vector = _parseVector(context);
    if (vector == null) return;
    await _runOperation(
      (controller) => controller.searchQdrantRawVector(
        vector: vector,
        limit: _limitValue(),
        filter: _filter(),
      ),
    );
  }

  Future<void> _createPayloadIndexes() async {
    await _runOperation(
      (controller) => controller.createDefaultQdrantPayloadIndexes(),
    );
    if (!mounted) return;
    OpenHandSnackBar.showSuccess(
      context,
      openHandLocalizedText(
        context,
        zh: '常用 Payload 索引已提交创建/重建。',
        en: 'Default payload index creation submitted.',
      ),
    );
    await _refresh(silent: true);
  }

  Future<void> _deletePoints() async {
    final controller = context.read<KnowledgeBaseController>();
    final isZh = openHandIsChineseLocale(context);
    if (!controller.settings.enableDangerousAdminOperations) {
      OpenHandSnackBar.showError(
        context,
        isZh
            ? '请先在知识库配置中启用危险管理操作。'
            : 'Enable dangerous admin operations in Knowledge Base settings first.',
      );
      return;
    }
    final ids = _parseIds();
    if (ids.isEmpty) {
      OpenHandSnackBar.showError(
        context,
        isZh ? '请先输入要删除的向量点 ID。' : 'Enter point IDs to delete first.',
      );
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '删除 Qdrant 向量点？' : 'Delete Qdrant points?',
      message: isZh
          ? '将从当前集合删除 ${ids.length} 个向量点。此操作不可撤销。'
          : 'This deletes ${ids.length} points from the current collection. This cannot be undone.',
      confirmLabel: isZh ? '删除向量点' : 'Delete points',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _operating = true;
      _error = null;
    });
    try {
      await controller.deleteQdrantPoints(ids);
      if (!mounted) return;
      OpenHandSnackBar.showSuccess(
        context,
        isZh ? '向量点已删除。' : 'Points deleted.',
      );
      await _refresh(silent: true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _loadCollectionInfo(String collection) async {
    await _runOperation(
      (controller) => controller.loadQdrantCollectionInfo(collection),
    );
  }

  Future<void> _deleteCollection(String collection) async {
    final controller = context.read<KnowledgeBaseController>();
    final isZh = openHandIsChineseLocale(context);
    if (!controller.settings.enableDangerousAdminOperations) {
      OpenHandSnackBar.showError(
        context,
        isZh
            ? '请先在知识库配置中启用危险管理操作。'
            : 'Enable dangerous admin operations in Knowledge Base settings first.',
      );
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '删除 Qdrant 集合？' : 'Delete Qdrant collection?',
      message: isZh
          ? '将删除集合 "$collection" 及其中所有向量点。此操作不可撤销。'
          : 'This deletes collection "$collection" and all points in it. This cannot be undone.',
      confirmLabel: isZh ? '删除集合' : 'Delete collection',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _operating = true;
      _error = null;
    });
    try {
      await controller.deleteQdrantCollection(collection);
      if (!mounted) return;
      OpenHandSnackBar.showSuccess(
        context,
        isZh ? '集合已删除。' : 'Collection deleted.',
      );
      await _refresh(silent: true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _copyDiagnostics() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'collected_at': snapshot.collectedAt.toIso8601String(),
          'sections': snapshot.sections,
          'raw': snapshot.raw,
          'collections': _collections,
          'history': [for (final sample in _samples) sample.toJson()],
        }),
      ),
    );
    if (mounted) {
      OpenHandSnackBar.showSuccess(
        context,
        openHandLocalizedText(
          context,
          zh: '诊断信息已复制。',
          en: 'Diagnostics copied.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    final height = math.min(MediaQuery.sizeOf(context).height * 0.82, 760.0);
    return buildOpenHandAlertDialog(
      title: Text(isZh ? 'Qdrant 运维' : 'Qdrant Operations'),
      content: buildOpenHandDialogConstrainedContent(
        width: _qdrantOpsDialogWidth,
        height: height,
        child: DefaultTabController(
          length: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: KnowledgeDialogNotice(
                    icon: Icons.error_outline_rounded,
                    error: true,
                    message: _error!,
                  ),
                ),
              _QdrantOpsHeader(
                snapshot: _snapshot,
                refreshing: _refreshing,
                isZh: isZh,
              ),
              const SizedBox(height: 10),
              TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: isZh ? '总览监控' : 'Overview'),
                  Tab(text: isZh ? '集合管理' : 'Collections'),
                  Tab(text: isZh ? '向量点查询' : 'Points'),
                  Tab(text: isZh ? '诊断日志' : 'Diagnostics'),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  children: [
                    _OverviewTab(
                      snapshot: _snapshot,
                      samples: _samples,
                      isZh: isZh,
                    ),
                    _CollectionsTab(
                      collections: _collections,
                      busy: _operating,
                      isZh: isZh,
                      onInfo: _loadCollectionInfo,
                      onDelete: _deleteCollection,
                    ),
                    _PointsTab(
                      pointIds: _pointIds,
                      sourceId: _sourceId,
                      tag: _tag,
                      limit: _limit,
                      rawVector: _rawVector,
                      busy: _operating,
                      result: _operationResult,
                      isZh: isZh,
                      onLoadIds: _loadPointIds,
                      onScroll: _scrollPoints,
                      onSearchVector: _searchVector,
                      onCreatePayloadIndexes: _createPayloadIndexes,
                      onDeletePoints: _deletePoints,
                    ),
                    _DiagnosticsTab(
                      snapshot: _snapshot,
                      operationResult: _operationResult,
                      isZh: isZh,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: _refreshing ? null : _refresh,
          icon: Icons.refresh_rounded,
          busy: _refreshing,
          label: isZh ? '刷新' : 'Refresh',
        ),
        OpenHandDialogActionButton.secondary(
          onPressed: _snapshot == null ? null : _copyDiagnostics,
          icon: Icons.copy_rounded,
          label: isZh ? '复制诊断' : 'Copy diagnostics',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _operating ? null : () => Navigator.of(context).pop(),
          label: isZh ? '关闭' : 'Close',
        ),
      ],
    );
  }
}

class _QdrantOpsHeader extends StatelessWidget {
  const _QdrantOpsHeader({
    required this.snapshot,
    required this.refreshing,
    required this.isZh,
  });

  final QdrantMonitoringSnapshot? snapshot;
  final bool refreshing;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final overview = snapshot?.sections['overview'];
    final status =
        '${overview?['service_status'] ?? (refreshing ? 'loading' : 'unknown')}';
    final statusColor = status == 'healthy'
        ? colorScheme.primary
        : status == 'loading'
        ? colorScheme.tertiary
        : colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.monitor_heart_outlined, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isZh ? '本地向量数据库实时状态' : 'Local vector database status',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${overview?['rest_endpoint'] ?? '-'} · ${overview?['current_collection'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _StatusPill(
            icon: Icons.circle,
            label: '${_localizedMetricValue(isZh, status)}',
            color: statusColor,
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.snapshot,
    required this.samples,
    required this.isZh,
  });

  final QdrantMonitoringSnapshot? snapshot;
  final List<_QdrantMetricSample> samples;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final api = snapshot!.sections['qdrant_api'] ?? const {};
    final storage = snapshot!.sections['storage_optimizer'] ?? const {};
    final openhand = snapshot!.sections['openhand_knowledge'] ?? const {};
    return SingleChildScrollView(
      physics: openHandDialogAwareScrollPhysics(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricCard(
                icon: Icons.dataset_outlined,
                label: isZh ? '集合' : 'Collections',
                value: '${api['collections_total'] ?? 0}',
              ),
              _MetricCard(
                icon: Icons.scatter_plot_outlined,
                label: isZh ? '向量点' : 'Points',
                value: '${api['points_total'] ?? 0}',
              ),
              _MetricCard(
                icon: Icons.polyline_outlined,
                label: isZh ? '已索引向量' : 'Indexed vectors',
                value: '${api['indexed_vectors_total'] ?? 0}',
              ),
              _MetricCard(
                icon: Icons.segment_outlined,
                label: isZh ? '分块' : 'Chunks',
                value: '${openhand['chunk_count'] ?? 0}',
              ),
              _MetricCard(
                icon: Icons.pending_actions_outlined,
                label: isZh ? '待处理任务' : 'Pending jobs',
                value: '${openhand['pending_embedding_jobs'] ?? 0}',
              ),
              _MetricCard(
                icon: Icons.storage_outlined,
                label: isZh ? 'WAL 容量' : 'WAL capacity',
                value: '${storage['wal_capacity_mb'] ?? '-'}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          KnowledgeDialogSection(
            title: isZh ? '平滑趋势' : 'Smooth Trend',
            icon: Icons.show_chart_rounded,
            child: _QdrantTrendChart(samples: samples, isZh: isZh),
          ),
          for (final section in snapshot!.sections.entries)
            _StatusSection(
              title: section.key,
              values: section.value,
              isZh: isZh,
            ),
        ],
      ),
    );
  }
}

class _CollectionsTab extends StatelessWidget {
  const _CollectionsTab({
    required this.collections,
    required this.busy,
    required this.isZh,
    required this.onInfo,
    required this.onDelete,
  });

  final List<Map<String, Object?>> collections;
  final bool busy;
  final bool isZh;
  final ValueChanged<String> onInfo;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    if (collections.isEmpty) {
      return Center(
        child: KnowledgeDialogNotice(
          icon: Icons.info_outline_rounded,
          message: isZh
              ? '没有集合，或当前 Qdrant 服务不可用。'
              : 'No collection found, or Qdrant is unavailable.',
        ),
      );
    }
    return ListView.separated(
      physics: openHandDialogAwareScrollPhysics(context),
      itemCount: collections.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = collections[index];
        final name = '${item['name'] ?? ''}';
        return _CollectionTile(
          item: item,
          busy: busy || name.isEmpty,
          isZh: isZh,
          onInfo: () => onInfo(name),
          onDelete: () => onDelete(name),
        );
      },
    );
  }
}

class _PointsTab extends StatelessWidget {
  const _PointsTab({
    required this.pointIds,
    required this.sourceId,
    required this.tag,
    required this.limit,
    required this.rawVector,
    required this.busy,
    required this.result,
    required this.isZh,
    required this.onLoadIds,
    required this.onScroll,
    required this.onSearchVector,
    required this.onCreatePayloadIndexes,
    required this.onDeletePoints,
  });

  final TextEditingController pointIds;
  final TextEditingController sourceId;
  final TextEditingController tag;
  final TextEditingController limit;
  final TextEditingController rawVector;
  final bool busy;
  final Map<String, Object?>? result;
  final bool isZh;
  final VoidCallback onLoadIds;
  final VoidCallback onScroll;
  final VoidCallback onSearchVector;
  final VoidCallback onCreatePayloadIndexes;
  final VoidCallback onDeletePoints;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: openHandDialogAwareScrollPhysics(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeDialogSection(
            title: isZh ? '向量点查询 / 搜索 / 滚动读取' : 'Points / Search / Scroll',
            icon: Icons.manage_search_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _OpsTextField(
                      controller: pointIds,
                      width: 300,
                      label: isZh ? '向量点/分块 ID（空格或逗号分隔）' : 'Point / chunk IDs',
                    ),
                    _OpsTextField(
                      controller: sourceId,
                      width: 210,
                      label: isZh ? '来源 ID 过滤' : 'Source ID filter',
                    ),
                    _OpsTextField(
                      controller: tag,
                      width: 170,
                      label: isZh ? '标签过滤' : 'Tag filter',
                    ),
                    _OpsTextField(
                      controller: limit,
                      width: 120,
                      label: isZh ? '数量上限' : 'Limit',
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: rawVector,
                  minLines: 3,
                  maxLines: 6,
                  decoration: knowledgeDialogInputDecoration(
                    context,
                    isZh
                        ? '原始向量（逗号或空格分隔，维度必须匹配当前配置）'
                        : 'Raw vector (comma or space separated, must match dimensions)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onLoadIds,
                      icon: const Icon(Icons.search_rounded),
                      label: Text(isZh ? '按 ID 查询' : 'Query IDs'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onScroll,
                      icon: const Icon(Icons.list_alt_rounded),
                      label: Text(isZh ? '滚动读取 / 过滤' : 'Scroll / Filter'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onSearchVector,
                      icon: const Icon(Icons.polyline_outlined),
                      label: Text(isZh ? '原始向量搜索' : 'Raw Vector Search'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onCreatePayloadIndexes,
                      icon: const Icon(Icons.manage_search_rounded),
                      label: Text(
                        isZh ? '重建 Payload 索引' : 'Rebuild payload indexes',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: busy ? null : onDeletePoints,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(isZh ? '删除 Points' : 'Delete Points'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (result != null)
            KnowledgeDialogSection(
              title: isZh ? '操作结果' : 'Operation Result',
              icon: Icons.data_object_rounded,
              margin: EdgeInsets.zero,
              child: KnowledgeDialogJsonBox(value: result, maxHeight: 420),
            ),
        ],
      ),
    );
  }
}

class _DiagnosticsTab extends StatelessWidget {
  const _DiagnosticsTab({
    required this.snapshot,
    required this.operationResult,
    required this.isZh,
  });

  final QdrantMonitoringSnapshot? snapshot;
  final Map<String, Object?>? operationResult;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KnowledgeBaseController>();
    return SingleChildScrollView(
      physics: openHandDialogAwareScrollPhysics(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeDialogSection(
            title: isZh ? '原始诊断 JSON' : 'Raw Diagnostics JSON',
            icon: Icons.data_object_rounded,
            child: snapshot == null
                ? KnowledgeDialogNotice(
                    icon: Icons.info_outline_rounded,
                    message: isZh ? '暂无诊断数据。' : 'No diagnostics yet.',
                  )
                : KnowledgeDialogJsonBox(
                    value: <String, Object?>{
                      'collected_at': snapshot!.collectedAt.toIso8601String(),
                      'sections': snapshot!.sections,
                      'raw': snapshot!.raw,
                    },
                    maxHeight: 360,
                  ),
          ),
          if (operationResult != null)
            KnowledgeDialogSection(
              title: isZh ? '最近操作结果' : 'Latest Operation Result',
              icon: Icons.receipt_long_outlined,
              child: KnowledgeDialogJsonBox(
                value: operationResult,
                maxHeight: 300,
              ),
            ),
          KnowledgeDialogSection(
            title: isZh ? '操作日志' : 'Operation Log',
            icon: Icons.history_rounded,
            margin: EdgeInsets.zero,
            child: controller.qdrantAdminLogs.isEmpty
                ? KnowledgeDialogNotice(
                    icon: Icons.history_toggle_off_rounded,
                    message: isZh ? '暂无操作。' : 'No operations yet.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final log in controller.qdrantAdminLogs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${formatYearMonthDayHms(log.createdAt.toLocal())} · '
                            '${log.action} · ${log.detail}',
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: 176,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
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

class _QdrantTrendChart extends StatelessWidget {
  const _QdrantTrendChart({required this.samples, required this.isZh});

  final List<_QdrantMetricSample> samples;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (samples.length < 2) {
      return SizedBox(
        height: _qdrantOpsChartHeight,
        child: Center(
          child: Text(
            isZh ? '等待更多采样后展示趋势。' : 'Collecting samples for trend view.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => SizedBox(
            height: _qdrantOpsChartHeight,
            child: CustomPaint(
              painter: _QdrantTrendPainter(
                samples: samples,
                progress: value,
                primary: colorScheme.primary,
                tertiary: colorScheme.tertiary,
                error: colorScheme.error,
                grid: colorScheme.outlineVariant,
                foreground: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _StatusPill(
              icon: Icons.show_chart_rounded,
              label: isZh ? '向量点' : 'points',
              color: colorScheme.primary,
            ),
            _StatusPill(
              icon: Icons.show_chart_rounded,
              label: isZh ? '分块' : 'chunks',
              color: colorScheme.tertiary,
            ),
            _StatusPill(
              icon: Icons.show_chart_rounded,
              label: isZh ? '待处理/失败' : 'pending/failed',
              color: colorScheme.error,
            ),
          ],
        ),
      ],
    );
  }
}

class _QdrantTrendPainter extends CustomPainter {
  const _QdrantTrendPainter({
    required this.samples,
    required this.progress,
    required this.primary,
    required this.tertiary,
    required this.error,
    required this.grid,
    required this.foreground,
  });

  final List<_QdrantMetricSample> samples;
  final double progress;
  final Color primary;
  final Color tertiary;
  final Color error;
  final Color grid;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final background = Paint()
      ..color = grid.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = grid.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas.drawRRect(rounded, background);
    canvas.drawRRect(rounded, border);

    final chartRect = rect.deflate(16);
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.42)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = chartRect.top + chartRect.height * i / 4;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
    }

    final maxValue = math.max(
      1,
      samples
          .expand(
            (sample) => <int>[
              sample.points,
              sample.chunks,
              sample.pending + sample.failed,
            ],
          )
          .reduce(math.max),
    );
    _drawSeries(
      canvas,
      chartRect,
      maxValue,
      samples.map((sample) => sample.points).toList(growable: false),
      primary,
    );
    _drawSeries(
      canvas,
      chartRect,
      maxValue,
      samples.map((sample) => sample.chunks).toList(growable: false),
      tertiary,
    );
    _drawSeries(
      canvas,
      chartRect,
      maxValue,
      samples
          .map((sample) => sample.pending + sample.failed)
          .toList(growable: false),
      error,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: '${samples.length} pts',
        style: TextStyle(color: foreground, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(chartRect.right - textPainter.width, chartRect.top),
    );
  }

  void _drawSeries(
    Canvas canvas,
    Rect rect,
    int maxValue,
    List<int> values,
    Color color,
  ) {
    if (values.length < 2) return;
    final visibleCount = math.max(2, (values.length * progress).ceil());
    final shown = values.take(visibleCount).toList(growable: false);
    final step = shown.length == 1 ? 0 : rect.width / (shown.length - 1);
    Offset pointAt(int index) {
      final x = rect.left + step * index;
      final y = rect.bottom - rect.height * (shown[index] / maxValue);
      return Offset(x, y);
    }

    final path = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var index = 1; index < shown.length; index++) {
      final previous = pointAt(index - 1);
      final current = pointAt(index);
      final midX = (previous.dx + current.dx) / 2;
      path.cubicTo(midX, previous.dy, midX, current.dy, current.dx, current.dy);
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _QdrantTrendPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.progress != progress ||
        oldDelegate.primary != primary ||
        oldDelegate.tertiary != tertiary ||
        oldDelegate.error != error ||
        oldDelegate.grid != grid;
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.title,
    required this.values,
    required this.isZh,
  });

  final String title;
  final Map<String, Object?> values;
  final bool isZh;

  @override
  Widget build(BuildContext context) {
    return KnowledgeDialogSection(
      title: _localizedSectionTitle(isZh, title),
      icon: _iconForSection(title),
      child: KnowledgeDialogKeyValueList(
        rows: {
          for (final entry in values.entries)
            _localizedMetricLabel(isZh, entry.key): _localizedMetricValue(
              isZh,
              entry.value,
            ),
        },
        labelWidth: isZh ? 190 : 220,
      ),
    );
  }

  IconData _iconForSection(String value) {
    return switch (value) {
      'overview' => Icons.dashboard_customize_outlined,
      'docker_container' => Icons.developer_board_outlined,
      'qdrant_api' => Icons.storage_outlined,
      'collection_config' => Icons.tune_rounded,
      'storage_optimizer' => Icons.speed_rounded,
      'telemetry' => Icons.sensors_outlined,
      'openhand_knowledge' => Icons.library_books_outlined,
      _ => Icons.monitor_heart_outlined,
    };
  }
}

String _localizedSectionTitle(bool isZh, String value) {
  return switch (value) {
    'overview' => isZh ? '总览' : 'Overview',
    'docker_container' => isZh ? 'Docker / 容器指标' : 'Docker / Container',
    'qdrant_api' => isZh ? 'Qdrant API 指标' : 'Qdrant API Metrics',
    'collection_config' => isZh ? '集合配置' : 'Collection Config',
    'storage_optimizer' => isZh ? '存储 / 优化器' : 'Storage / Optimizer',
    'telemetry' => isZh ? '遥测数据' : 'Telemetry',
    'openhand_knowledge' => isZh ? 'OpenHand 知识库指标' : 'OpenHand Knowledge',
    _ => value,
  };
}

String _localizedMetricLabel(bool isZh, String value) {
  return switch (value) {
    'service_status' => isZh ? '服务状态' : 'Service status',
    'rest_endpoint' => 'REST endpoint',
    'grpc_endpoint' => 'gRPC endpoint',
    'qdrant_version' => isZh ? 'Qdrant 版本' : 'Qdrant version',
    'current_collection' => isZh ? '当前集合' : 'Current collection',
    'collection_status' => isZh ? '集合状态' : 'Collection status',
    'optimizer_status' => isZh ? '优化器状态' : 'Optimizer status',
    'last_health_check_at' => isZh ? '最近健康检查时间' : 'Last health check',
    'docker_daemon' => isZh ? 'Docker 守护进程' : 'Docker daemon',
    'container_cpu' => isZh ? '容器 CPU' : 'Container CPU',
    'container_memory' => isZh ? '容器内存' : 'Container memory',
    'network_io' => isZh ? '网络收发' : 'Network I/O',
    'block_io' => isZh ? '块设备 I/O' : 'Block I/O',
    'restart_count' => isZh ? '重启次数' : 'Restart count',
    'latest_log_summary' => isZh ? '最近日志摘要' : 'Latest log summary',
    'collections_total' => isZh ? '集合总数' : 'Collections total',
    'points_total' => isZh ? '向量点总数' : 'Points total',
    'vectors_total' => isZh ? '向量总数' : 'Vectors total',
    'indexed_vectors_total' => isZh ? '已索引向量总数' : 'Indexed vectors total',
    'segments_total' => isZh ? '分段数' : 'Segments',
    'payload_schema_fields' =>
      isZh ? 'Payload schema 字段数' : 'Payload schema fields',
    'payload_schema_names' =>
      isZh ? 'Payload schema 字段' : 'Payload schema names',
    'vector_size' => isZh ? '向量维度' : 'Vector size',
    'distance' => isZh ? '距离度量' : 'Distance',
    'single_node_mode' => isZh ? '单机模式' : 'Single-node mode',
    'payload_index_status' => isZh ? 'Payload 索引状态' : 'Payload index status',
    'cluster_status' => isZh ? '集群状态' : 'Cluster status',
    'hnsw_m' => 'HNSW M',
    'hnsw_ef_construct' => 'HNSW ef_construct',
    'hnsw_full_scan_threshold' =>
      isZh ? 'HNSW 全扫描阈值' : 'HNSW full scan threshold',
    'hnsw_max_indexing_threads' =>
      isZh ? 'HNSW 最大索引线程' : 'HNSW max indexing threads',
    'on_disk_payload' => isZh ? 'Payload 磁盘存储' : 'On-disk payload',
    'shard_number' => isZh ? '分片数' : 'Shard number',
    'replication_factor' => isZh ? '副本因子' : 'Replication factor',
    'write_consistency_factor' => isZh ? '写一致性因子' : 'Write consistency factor',
    'read_fan_out_factor' => isZh ? '读取扇出因子' : 'Read fan-out factor',
    'optimizer_deleted_threshold' =>
      isZh ? '优化器删除阈值' : 'Optimizer deleted threshold',
    'optimizer_vacuum_min_vector_number' =>
      isZh ? 'Vacuum 最小向量数' : 'Vacuum min vector number',
    'optimizer_default_segment_number' =>
      isZh ? '默认分段数' : 'Default segment number',
    'optimizer_max_segment_size' => isZh ? '最大分段大小' : 'Max segment size',
    'optimizer_indexing_threshold' => isZh ? '索引阈值' : 'Indexing threshold',
    'optimizer_flush_interval_sec' =>
      isZh ? '刷盘间隔秒数' : 'Flush interval seconds',
    'wal_capacity_mb' => isZh ? 'WAL 容量 MB' : 'WAL capacity MB',
    'wal_segments_ahead' => isZh ? 'WAL 预留段' : 'WAL segments ahead',
    'quantization' => isZh ? '量化配置' : 'Quantization',
    'strict_mode' => isZh ? '严格模式' : 'Strict mode',
    'telemetry_status' => isZh ? '遥测状态' : 'Telemetry status',
    'app_version' => isZh ? '应用版本' : 'App version',
    'app_name' => isZh ? '应用名称' : 'App name',
    'telemetry_collections' => isZh ? '集合遥测' : 'Collections telemetry',
    'telemetry_requests' => isZh ? '请求遥测' : 'Requests telemetry',
    'source_count' => isZh ? '来源数' : 'Sources',
    'chunk_count' => isZh ? '分块数' : 'Chunks',
    'pending_embedding_jobs' => isZh ? '待处理嵌入任务' : 'Pending embedding jobs',
    'failed_embedding_jobs' => isZh ? '失败嵌入任务' : 'Failed embedding jobs',
    'embedding_model' => isZh ? '当前嵌入模型' : 'Current embedding model',
    'embedding_dimensions' => isZh ? '当前向量维度' : 'Current dimensions',
    'retrieval_top_n' => isZh ? '召回 TopN' : 'Retrieval topN',
    'retrieval_top_k' => isZh ? '最终 TopK' : 'Final topK',
    'min_similarity' => isZh ? '最低相似度' : 'Minimum similarity',
    'prompt_chunk_budget' => isZh ? 'Prompt 分块预算' : 'Prompt chunk budget',
    'prompt_token_budget' => isZh ? 'Prompt token 预算' : 'Prompt token budget',
    _ => value,
  };
}

Object? _localizedMetricValue(bool isZh, Object? value) {
  final text = '$value';
  return switch (text) {
    'true' => isZh ? '是' : 'Yes',
    'false' => isZh ? '否' : 'No',
    'healthy' => isZh ? '健康' : 'Healthy',
    'unknown' => isZh ? '未知' : 'Unknown',
    'loading' => isZh ? '加载中' : 'Loading',
    'available' => isZh ? '可用' : 'Available',
    'unavailable' => isZh ? '不可用' : 'Unavailable',
    'plugin_service_scan' => isZh ? '由插件服务扫描' : 'Scanned by plugin service',
    'plugin_runtime_metric' => isZh ? '由插件运行时提供' : 'Provided by plugin runtime',
    'plugin_details_logs' => isZh ? '可在插件详情查看' : 'Available in plugin details',
    'local_single_node_or_unavailable' =>
      isZh ? '本地单机 / 不可用' : 'Local single-node / unavailable',
    'cluster_info_available' => isZh ? '已返回集群信息' : 'Cluster info returned',
    'payload_schema_configured' =>
      isZh ? '已配置 payload schema' : 'Payload schema configured',
    'payload_schema_missing' =>
      isZh ? '未发现 payload schema' : 'No payload schema found',
    _ => value,
  };
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({
    required this.item,
    required this.busy,
    required this.isZh,
    required this.onInfo,
    required this.onDelete,
  });

  final Map<String, Object?> item;
  final bool busy;
  final bool isZh;
  final VoidCallback onInfo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final name = '${item['name'] ?? ''}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.dataset_outlined, size: 20, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  name.isEmpty ? '-' : name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  jsonEncode(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isZh ? '查看配置' : 'View config',
            onPressed: busy ? null : onInfo,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          IconButton(
            tooltip: isZh ? '删除' : 'Delete',
            onPressed: busy ? null : onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _OpsTextField extends StatelessWidget {
  const _OpsTextField({
    required this.controller,
    required this.width,
    required this.label,
    this.keyboardType,
  });

  final TextEditingController controller;
  final double width;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 56,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: knowledgeDialogInputDecoration(context, label),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _QdrantMetricSample {
  const _QdrantMetricSample({
    required this.createdAt,
    required this.collections,
    required this.points,
    required this.indexedVectors,
    required this.chunks,
    required this.pending,
    required this.failed,
  });

  factory _QdrantMetricSample.fromSnapshot(QdrantMonitoringSnapshot snapshot) {
    final api = snapshot.sections['qdrant_api'] ?? const {};
    final openhand = snapshot.sections['openhand_knowledge'] ?? const {};
    return _QdrantMetricSample(
      createdAt: snapshot.collectedAt,
      collections: _intValue(api['collections_total']),
      points: _intValue(api['points_total']),
      indexedVectors: _intValue(api['indexed_vectors_total']),
      chunks: _intValue(openhand['chunk_count']),
      pending: _intValue(openhand['pending_embedding_jobs']),
      failed: _intValue(openhand['failed_embedding_jobs']),
    );
  }

  final DateTime createdAt;
  final int collections;
  final int points;
  final int indexedVectors;
  final int chunks;
  final int pending;
  final int failed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'created_at': createdAt.toIso8601String(),
      'collections': collections,
      'points': points,
      'indexed_vectors': indexedVectors,
      'chunks': chunks,
      'pending': pending,
      'failed': failed,
    };
  }

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}
