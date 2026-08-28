import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/support/silent_log.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_inline_empty_state.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/timer_safety.dart';
import '../knowledge_base_controller.dart';
import '../knowledge_base_errors.dart';
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
  bool _refreshPending = false;
  Future<void>? _refreshTask;
  bool _refreshing = false;
  bool _operating = false;
  AppLocalizations get _l10n => AppLocalizations.of(context)!;

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
    _refreshPending = false;
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
        if (_refreshTask == null && !_operating) {
          await _refresh(silent: true);
        }
      },
      min: const Duration(seconds: _qdrantMinRefreshSeconds),
      max: const Duration(seconds: _qdrantMaxRefreshSeconds),
    );
  }

  Future<void> _refresh({bool silent = false}) {
    if (!mounted) return Future<void>.value();
    _refreshPending = true;
    if (!silent && !_refreshing) {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    }
    final activeTask = _refreshTask;
    if (activeTask != null) return activeTask;
    late final Future<void> task;
    task = _drainRefreshRequests().whenComplete(() {
      if (!identical(_refreshTask, task)) return;
      _refreshTask = null;
      if (mounted && _refreshing) {
        setState(() => _refreshing = false);
      }
    });
    _refreshTask = task;
    return task;
  }

  Future<void> _drainRefreshRequests() async {
    while (mounted && _refreshPending) {
      _refreshPending = false;
      try {
        final controller = context.read<KnowledgeBaseController>();
        QdrantMonitoringSnapshot? snapshot;
        List<Map<String, Object?>>? collections;
        await Future.wait<void>(<Future<void>>[
          controller.loadMonitoringSnapshot().then((value) => snapshot = value),
          controller.listQdrantCollections().then(
            (value) => collections = value,
          ),
        ]).timeout(_qdrantRefreshTimeout);
        if (!mounted) return;
        if (_refreshPending) continue;
        final loadedSnapshot = snapshot;
        final loadedCollections = collections;
        if (loadedSnapshot == null || loadedCollections == null) {
          setState(() => _error = _l10n.qdrantStatusRefreshIncomplete);
          continue;
        }
        setState(() {
          _snapshot = loadedSnapshot;
          _collections = loadedCollections;
          _samples.add(_QdrantMetricSample.fromSnapshot(loadedSnapshot));
          if (_samples.length > _qdrantTrendSampleCap) {
            _samples.removeRange(0, _samples.length - _qdrantTrendSampleCap);
          }
          _error = null;
        });
      } catch (error, stack) {
        if (!mounted) return;
        if (_refreshPending) continue;
        silentLog('qdrant_status_dialog', '刷新 Qdrant 状态', error, stack);
        setState(
          () => _error = knowledgeBaseFailureMessage(
            error,
            fallback: '刷新 Qdrant 状态失败，请稍后重试。',
          ),
        );
      }
    }
  }

  List<String> _parseIds() {
    return splitLooseDelimitedValues(
      _pointIds.text,
    ).toSet().toList(growable: false);
  }

  List<double>? _parseVector(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final values = splitLooseDelimitedValues(_rawVector.text);
    if (values.isEmpty) {
      showOpenHandErrorSnack(context, l10n.qdrantStatusRawVectorEmpty);
      return null;
    }
    final vector = <double>[];
    for (final value in values) {
      final parsed = optionalDoubleFromValue(value);
      if (parsed == null) {
        showOpenHandErrorSnack(
          context,
          l10n.qdrantStatusRawVectorInvalid(value),
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
      showOpenHandErrorSnack(
        context,
        l10n.qdrantStatusRawVectorDimensionMismatch(vector.length, dimensions),
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

  Future<bool> _runOperation(
    String operationName,
    Future<Map<String, Object?>> Function(KnowledgeBaseController controller)
    operation,
  ) async {
    setState(() {
      _operating = true;
      _error = null;
    });
    try {
      final result = await operation(context.read<KnowledgeBaseController>());
      if (!mounted) return false;
      setState(() => _operationResult = result);
      return true;
    } catch (error, stack) {
      silentLog('qdrant_status_dialog', operationName, error, stack);
      if (mounted) {
        setState(
          () => _error = knowledgeBaseFailureMessage(
            error,
            fallback: '$operationName失败，请稍后重试。',
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _loadPointIds() async {
    final ids = _parseIds();
    if (ids.isEmpty) {
      showOpenHandErrorSnack(context, _l10n.qdrantStatusPointIdsEmpty);
      return;
    }
    await _runOperation(
      '查询 Qdrant Points',
      (controller) => controller.loadQdrantPointsByIds(ids),
    );
  }

  Future<void> _scrollPoints() async {
    await _runOperation(
      '滚动读取 Qdrant Points',
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
      '搜索 Qdrant 向量',
      (controller) => controller.searchQdrantRawVector(
        vector: vector,
        limit: _limitValue(),
        filter: _filter(),
      ),
    );
  }

  Future<void> _createPayloadIndexes() async {
    final succeeded = await _runOperation(
      '重建 Qdrant Payload 索引',
      (controller) => controller.createDefaultQdrantPayloadIndexes(),
    );
    if (!succeeded || !mounted) return;
    showOpenHandSuccessSnack(
      context,
      _l10n.qdrantStatusPayloadIndexesSubmitted,
    );
    await _refresh(silent: true);
  }

  Future<void> _deletePoints() async {
    final controller = context.read<KnowledgeBaseController>();
    final l10n = _l10n;
    if (!controller.settings.enableDangerousAdminOperations) {
      showOpenHandErrorSnack(context, l10n.qdrantStatusDangerousOpsDisabled);
      return;
    }
    final ids = _parseIds();
    if (ids.isEmpty) {
      showOpenHandErrorSnack(context, l10n.qdrantStatusDeletePointIdsEmpty);
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.qdrantStatusDeletePointsTitle,
      message: l10n.qdrantStatusDeletePointsMessage(ids.length),
      confirmLabel: l10n.qdrantStatusDeletePointsConfirm,
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
      showOpenHandSuccessSnack(context, l10n.qdrantStatusPointsDeleted);
      await _refresh(silent: true);
    } catch (error, stack) {
      silentLog('qdrant_status_dialog', '删除 Qdrant Points', error, stack);
      if (mounted) {
        setState(
          () => _error = knowledgeBaseFailureMessage(
            error,
            fallback: '删除 Qdrant Points 失败，请稍后重试。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _loadCollectionInfo(String collection) async {
    await _runOperation(
      '读取 Qdrant Collection',
      (controller) => controller.loadQdrantCollectionInfo(collection),
    );
  }

  Future<void> _deleteCollection(String collection) async {
    final controller = context.read<KnowledgeBaseController>();
    final l10n = _l10n;
    if (!controller.settings.enableDangerousAdminOperations) {
      showOpenHandErrorSnack(context, l10n.qdrantStatusDangerousOpsDisabled);
      return;
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.qdrantStatusDeleteCollectionTitle,
      message: l10n.qdrantStatusDeleteCollectionMessage(collection),
      confirmLabel: l10n.qdrantStatusDeleteCollectionConfirm,
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
      showOpenHandSuccessSnack(context, l10n.qdrantStatusCollectionDeleted);
      await _refresh(silent: true);
    } catch (error, stack) {
      silentLog('qdrant_status_dialog', '删除 Qdrant Collection', error, stack);
      if (mounted) {
        setState(
          () => _error = knowledgeBaseFailureMessage(
            error,
            fallback: '删除 Qdrant Collection 失败，请稍后重试。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _copyDiagnostics() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    await copyOpenHandTextToClipboard(
      logTag: 'knowledge_base',
      context: context,
      text: prettyPrintJson(<String, Object?>{
        'collected_at': snapshot.collectedAt.toIso8601String(),
        'sections': snapshot.sections,
        'raw': snapshot.raw,
        'collections': _collections,
        'history': [for (final sample in _samples) sample.toJson()],
      }),
      successMessage: _l10n.qdrantStatusDiagnosticsCopied,
      logAction: '复制 Qdrant 诊断信息',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controllerUnavailable = context.select<KnowledgeBaseController, bool>(
      (controller) => controller.loading || controller.busy,
    );
    final operationBusy = _operating || controllerUnavailable;
    final height = math.min(MediaQuery.sizeOf(context).height * 0.82, 760.0);
    final dialog = buildOpenHandAlertDialog(
      title: Text(l10n.qdrantStatusTitle),
      content: buildOpenHandDialogConstrainedContent(
        width: _qdrantOpsDialogWidth,
        height: height,
        child: DefaultTabController(
          length: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KnowledgeDialogErrorNotice(message: _error, bottomSpacing: 10),
              _QdrantOpsHeader(
                snapshot: _snapshot,
                refreshing: _refreshing,
                l10n: l10n,
              ),
              kOpenHandGap10,
              TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: l10n.qdrantStatusTabOverview),
                  Tab(text: l10n.qdrantStatusTabCollections),
                  Tab(text: l10n.qdrantStatusTabPoints),
                  Tab(text: l10n.qdrantStatusTabDiagnostics),
                ],
              ),
              kOpenHandGap10,
              Expanded(
                child: TabBarView(
                  children: [
                    _OverviewTab(
                      snapshot: _snapshot,
                      samples: _samples,
                      l10n: l10n,
                    ),
                    _CollectionsTab(
                      collections: _collections,
                      busy: operationBusy,
                      l10n: l10n,
                      onInfo: _loadCollectionInfo,
                      onDelete: _deleteCollection,
                    ),
                    _PointsTab(
                      pointIds: _pointIds,
                      sourceId: _sourceId,
                      tag: _tag,
                      limit: _limit,
                      rawVector: _rawVector,
                      busy: operationBusy,
                      result: _operationResult,
                      l10n: l10n,
                      onLoadIds: _loadPointIds,
                      onScroll: _scrollPoints,
                      onSearchVector: _searchVector,
                      onCreatePayloadIndexes: _createPayloadIndexes,
                      onDeletePoints: _deletePoints,
                    ),
                    _DiagnosticsTab(
                      snapshot: _snapshot,
                      operationResult: _operationResult,
                      l10n: l10n,
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
          label: l10n.qdrantStatusRefresh,
        ),
        OpenHandDialogActionButton.secondary(
          onPressed: _snapshot == null ? null : _copyDiagnostics,
          icon: Icons.copy_rounded,
          label: l10n.qdrantStatusCopyDiagnostics,
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _operating ? null : () => Navigator.of(context).pop(),
          label: l10n.commonClose,
        ),
      ],
    );
    return PopScope(canPop: !_operating, child: dialog);
  }
}

class _QdrantOpsHeader extends StatelessWidget {
  const _QdrantOpsHeader({
    required this.snapshot,
    required this.refreshing,
    required this.l10n,
  });

  final QdrantMonitoringSnapshot? snapshot;
  final bool refreshing;
  final AppLocalizations l10n;

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
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(kOpenHandRadius11),
            ),
            child: Icon(Icons.monitor_heart_outlined, color: statusColor),
          ),
          kOpenHandHGap12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.qdrantStatusHeaderTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                kOpenHandGap2,
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
          kOpenHandHGap12,
          _StatusPill(
            icon: Icons.circle,
            label: '${_localizedMetricValue(l10n, status)}',
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
    required this.l10n,
  });

  final QdrantMonitoringSnapshot? snapshot;
  final List<_QdrantMetricSample> samples;
  final AppLocalizations l10n;

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
                label: l10n.qdrantStatusMetricCollections,
                value: '${api['collections_total'] ?? 0}',
              ),
              _MetricCard(
                icon: Icons.scatter_plot_outlined,
                label: l10n.qdrantStatusMetricPoints,
                value: '${api['points_total'] ?? 0}',
              ),
              _MetricCard(
                icon: Icons.polyline_outlined,
                label: l10n.qdrantStatusMetricIndexedVectors,
                value: '${api['indexed_vectors_total'] ?? 0}',
              ),
              _MetricCard(
                icon: Icons.segment_outlined,
                label: l10n.qdrantStatusMetricChunks,
                value: '${openhand['chunk_count'] ?? 0}',
              ),
              _MetricCard(
                icon: Icons.pending_actions_outlined,
                label: l10n.qdrantStatusMetricPendingJobs,
                value: '${openhand['pending_embedding_jobs'] ?? 0}',
              ),
              _MetricCard(
                icon: Icons.storage_outlined,
                label: l10n.qdrantStatusMetricWalCapacity,
                value: '${storage['wal_capacity_mb'] ?? '-'}',
              ),
            ],
          ),
          kOpenHandGap12,
          KnowledgeDialogSection(
            title: l10n.qdrantStatusSmoothTrend,
            icon: Icons.show_chart_rounded,
            child: _QdrantTrendChart(samples: samples, l10n: l10n),
          ),
          for (final section in snapshot!.sections.entries)
            _StatusSection(
              title: section.key,
              values: section.value,
              l10n: l10n,
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
    required this.l10n,
    required this.onInfo,
    required this.onDelete,
  });

  final List<Map<String, Object?>> collections;
  final bool busy;
  final AppLocalizations l10n;
  final ValueChanged<String> onInfo;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    if (collections.isEmpty) {
      return Center(
        child: KnowledgeDialogNotice(
          icon: Icons.info_outline_rounded,
          message: l10n.qdrantStatusNoCollections,
        ),
      );
    }
    return ListView.separated(
      physics: openHandDialogAwareScrollPhysics(context),
      itemCount: collections.length,
      separatorBuilder: (_, _) => kOpenHandGap8,
      itemBuilder: (context, index) {
        final item = collections[index];
        final name = '${item['name'] ?? ''}';
        return KnowledgeCollectionTile(
          item: item,
          busy: busy || name.isEmpty,
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
    required this.l10n,
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
  final AppLocalizations l10n;
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
            title: l10n.qdrantStatusPointsSectionTitle,
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
                      label: l10n.qdrantStatusPointIdsLabel,
                    ),
                    _OpsTextField(
                      controller: sourceId,
                      width: 210,
                      label: l10n.qdrantStatusSourceFilterLabel,
                    ),
                    _OpsTextField(
                      controller: tag,
                      width: 170,
                      label: l10n.qdrantStatusTagFilterLabel,
                    ),
                    _OpsTextField(
                      controller: limit,
                      width: 120,
                      label: l10n.qdrantStatusLimitLabel,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
                kOpenHandGap10,
                TextField(
                  controller: rawVector,
                  minLines: 3,
                  maxLines: 6,
                  decoration: knowledgeDialogInputDecoration(
                    context,
                    l10n.qdrantStatusRawVectorLabel,
                    alignLabelWithHint: true,
                  ),
                ),
                kOpenHandGap12,
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onLoadIds,
                      icon: const Icon(Icons.search_rounded),
                      label: Text(l10n.qdrantStatusQueryIds),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onScroll,
                      icon: const Icon(Icons.list_alt_rounded),
                      label: Text(l10n.qdrantStatusScrollFilter),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onSearchVector,
                      icon: const Icon(Icons.polyline_outlined),
                      label: Text(l10n.qdrantStatusRawVectorSearch),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onCreatePayloadIndexes,
                      icon: const Icon(Icons.manage_search_rounded),
                      label: Text(l10n.qdrantStatusRebuildPayloadIndexes),
                    ),
                    FilledButton.icon(
                      onPressed: busy ? null : onDeletePoints,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(l10n.qdrantStatusDeletePoints),
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
              title: l10n.qdrantStatusOperationResult,
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
    required this.l10n,
  });

  final QdrantMonitoringSnapshot? snapshot;
  final Map<String, Object?>? operationResult;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KnowledgeBaseController>();
    return SingleChildScrollView(
      physics: openHandDialogAwareScrollPhysics(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeDialogSection(
            title: l10n.qdrantStatusRawDiagnosticsJson,
            icon: Icons.data_object_rounded,
            child: snapshot == null
                ? KnowledgeDialogNotice(
                    icon: Icons.info_outline_rounded,
                    message: l10n.qdrantStatusNoDiagnostics,
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
              title: l10n.qdrantStatusLatestOperationResult,
              icon: Icons.receipt_long_outlined,
              child: KnowledgeDialogJsonBox(
                value: operationResult,
                maxHeight: 300,
              ),
            ),
          KnowledgeDialogSection(
            title: l10n.qdrantStatusOperationLog,
            icon: Icons.history_rounded,
            margin: EdgeInsets.zero,
            child: controller.qdrantAdminLogs.isEmpty
                ? KnowledgeDialogNotice(
                    icon: Icons.history_toggle_off_rounded,
                    message: l10n.qdrantStatusNoOperations,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final log in controller.qdrantAdminLogs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${formatYearMonthDayHmsLocal(log.createdAt)} · '
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
        borderRadius: kOpenHandBorderRadius14,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.62),
              borderRadius: kOpenHandBorderRadius10,
            ),
            child: Icon(icon, size: 18, color: colorScheme.onPrimaryContainer),
          ),
          kOpenHandHGap10,
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
                kOpenHandGap2,
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
  const _QdrantTrendChart({required this.samples, required this.l10n});

  final List<_QdrantMetricSample> samples;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (samples.length < 2) {
      return SizedBox(
        height: _qdrantOpsChartHeight,
        child: OpenHandInlineEmptyState(
          message: l10n.qdrantStatusCollectingSamples,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: openHandMotionDuration(context, kOpenHandMotion420),
          curve: kOpenHandSwitchInCurve,
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
                sampleCountLabel: l10n.qdrantStatusTrendSampleCount(
                  samples.length,
                ),
              ),
            ),
          ),
        ),
        kOpenHandGap8,
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            _StatusPill(
              icon: Icons.show_chart_rounded,
              label: l10n.qdrantStatusTrendPoints,
              color: colorScheme.primary,
            ),
            _StatusPill(
              icon: Icons.show_chart_rounded,
              label: l10n.qdrantStatusTrendChunks,
              color: colorScheme.tertiary,
            ),
            _StatusPill(
              icon: Icons.show_chart_rounded,
              label: l10n.qdrantStatusTrendPendingFailed,
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
    required this.sampleCountLabel,
  });

  final List<_QdrantMetricSample> samples;
  final double progress;
  final Color primary;
  final Color tertiary;
  final Color error;
  final Color grid;
  final Color foreground;
  final String sampleCountLabel;

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
    final rounded = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(kOpenHandRadius14),
    );
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
        text: sampleCountLabel,
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
        oldDelegate.grid != grid ||
        oldDelegate.sampleCountLabel != sampleCountLabel;
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.title,
    required this.values,
    required this.l10n,
  });

  final String title;
  final Map<String, Object?> values;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return KnowledgeDialogSection(
      title: _localizedSectionTitle(l10n, title),
      icon: _iconForSection(title),
      child: KnowledgeDialogKeyValueList(
        rows: {
          for (final entry in values.entries)
            _localizedMetricLabel(l10n, entry.key): _localizedMetricValue(
              l10n,
              entry.value,
            ),
        },
        labelWidth: l10n.localeName.startsWith('zh') ? 190 : 220,
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

String _localizedSectionTitle(AppLocalizations l10n, String value) {
  return switch (value) {
    'overview' => l10n.qdrantSectionOverview,
    'docker_container' => l10n.qdrantSectionDockerContainer,
    'qdrant_api' => l10n.qdrantSectionApiMetrics,
    'collection_config' => l10n.qdrantSectionCollectionConfig,
    'storage_optimizer' => l10n.qdrantSectionStorageOptimizer,
    'telemetry' => l10n.qdrantSectionTelemetry,
    'openhand_knowledge' => l10n.qdrantSectionOpenHandKnowledge,
    _ => value,
  };
}

String _localizedMetricLabel(AppLocalizations l10n, String value) {
  return switch (value) {
    'service_status' => l10n.qdrantMetricServiceStatus,
    'rest_endpoint' => l10n.qdrantMetricRestEndpoint,
    'grpc_endpoint' => l10n.qdrantMetricGrpcEndpoint,
    'qdrant_version' => l10n.qdrantMetricQdrantVersion,
    'current_collection' => l10n.qdrantMetricCurrentCollection,
    'collection_status' => l10n.qdrantMetricCollectionStatus,
    'optimizer_status' => l10n.qdrantMetricOptimizerStatus,
    'last_health_check_at' => l10n.qdrantMetricLastHealthCheck,
    'docker_daemon' => l10n.qdrantMetricDockerDaemon,
    'container_cpu' => l10n.qdrantMetricContainerCpu,
    'container_memory' => l10n.qdrantMetricContainerMemory,
    'network_io' => l10n.qdrantMetricNetworkIo,
    'block_io' => l10n.qdrantMetricBlockIo,
    'restart_count' => l10n.qdrantMetricRestartCount,
    'latest_log_summary' => l10n.qdrantMetricLatestLogSummary,
    'collections_total' => l10n.qdrantMetricCollectionsTotal,
    'points_total' => l10n.qdrantMetricPointsTotal,
    'vectors_total' => l10n.qdrantMetricVectorsTotal,
    'indexed_vectors_total' => l10n.qdrantMetricIndexedVectorsTotal,
    'segments_total' => l10n.qdrantMetricSegmentsTotal,
    'payload_schema_fields' => l10n.qdrantMetricPayloadSchemaFields,
    'payload_schema_names' => l10n.qdrantMetricPayloadSchemaNames,
    'vector_size' => l10n.qdrantMetricVectorSize,
    'distance' => l10n.qdrantMetricDistance,
    'single_node_mode' => l10n.qdrantMetricSingleNodeMode,
    'payload_index_status' => l10n.qdrantMetricPayloadIndexStatus,
    'cluster_status' => l10n.qdrantMetricClusterStatus,
    'hnsw_m' => l10n.qdrantMetricHnswM,
    'hnsw_ef_construct' => l10n.qdrantMetricHnswEfConstruct,
    'hnsw_full_scan_threshold' => l10n.qdrantMetricHnswFullScanThreshold,
    'hnsw_max_indexing_threads' => l10n.qdrantMetricHnswMaxIndexingThreads,
    'on_disk_payload' => l10n.qdrantMetricOnDiskPayload,
    'shard_number' => l10n.qdrantMetricShardNumber,
    'replication_factor' => l10n.qdrantMetricReplicationFactor,
    'write_consistency_factor' => l10n.qdrantMetricWriteConsistencyFactor,
    'read_fan_out_factor' => l10n.qdrantMetricReadFanOutFactor,
    'optimizer_deleted_threshold' => l10n.qdrantMetricOptimizerDeletedThreshold,
    'optimizer_vacuum_min_vector_number' =>
      l10n.qdrantMetricOptimizerVacuumMinVectorNumber,
    'optimizer_default_segment_number' =>
      l10n.qdrantMetricOptimizerDefaultSegmentNumber,
    'optimizer_max_segment_size' => l10n.qdrantMetricOptimizerMaxSegmentSize,
    'optimizer_indexing_threshold' =>
      l10n.qdrantMetricOptimizerIndexingThreshold,
    'optimizer_flush_interval_sec' =>
      l10n.qdrantMetricOptimizerFlushIntervalSeconds,
    'wal_capacity_mb' => l10n.qdrantMetricWalCapacityMb,
    'wal_segments_ahead' => l10n.qdrantMetricWalSegmentsAhead,
    'quantization' => l10n.qdrantMetricQuantization,
    'strict_mode' => l10n.qdrantMetricStrictMode,
    'telemetry_status' => l10n.qdrantMetricTelemetryStatus,
    'app_version' => l10n.qdrantMetricAppVersion,
    'app_name' => l10n.qdrantMetricAppName,
    'telemetry_collections' => l10n.qdrantMetricTelemetryCollections,
    'telemetry_requests' => l10n.qdrantMetricTelemetryRequests,
    'source_count' => l10n.qdrantMetricSourceCount,
    'chunk_count' => l10n.qdrantMetricChunkCount,
    'pending_embedding_jobs' => l10n.qdrantMetricPendingEmbeddingJobs,
    'failed_embedding_jobs' => l10n.qdrantMetricFailedEmbeddingJobs,
    'embedding_model' => l10n.qdrantMetricEmbeddingModel,
    'embedding_dimensions' => l10n.qdrantMetricEmbeddingDimensions,
    'retrieval_top_n' => l10n.qdrantMetricRetrievalTopN,
    'retrieval_top_k' => l10n.qdrantMetricRetrievalTopK,
    'min_similarity' => l10n.qdrantMetricMinSimilarity,
    'prompt_chunk_budget' => l10n.qdrantMetricPromptChunkBudget,
    'prompt_token_budget' => l10n.qdrantMetricPromptTokenBudget,
    _ => value,
  };
}

Object? _localizedMetricValue(AppLocalizations l10n, Object? value) {
  final text = '$value';
  return switch (text) {
    'true' => l10n.qdrantValueYes,
    'false' => l10n.qdrantValueNo,
    'healthy' => l10n.qdrantValueHealthy,
    'unknown' => l10n.qdrantValueUnknown,
    'loading' => l10n.qdrantValueLoading,
    'available' => l10n.qdrantValueAvailable,
    'unavailable' => l10n.qdrantValueUnavailable,
    'plugin_service_scan' => l10n.qdrantValuePluginServiceScan,
    'plugin_runtime_metric' => l10n.qdrantValuePluginRuntimeMetric,
    'plugin_details_logs' => l10n.qdrantValuePluginDetailsLogs,
    'local_single_node_or_unavailable' =>
      l10n.qdrantValueLocalSingleNodeOrUnavailable,
    'cluster_info_available' => l10n.qdrantValueClusterInfoAvailable,
    'payload_schema_configured' => l10n.qdrantValuePayloadSchemaConfigured,
    'payload_schema_missing' => l10n.qdrantValuePayloadSchemaMissing,
    _ => value,
  };
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
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          kOpenHandHGap5,
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
    return nonNegativeIntFromValue(value, fallback: 0);
  }
}
