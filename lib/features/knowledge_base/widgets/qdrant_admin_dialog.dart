import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';
import 'knowledge_dialog_widgets.dart';

Future<void> showQdrantAdminDialog(BuildContext context) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => const QdrantAdminDialog(),
  );
}

class QdrantAdminDialog extends StatefulWidget {
  const QdrantAdminDialog({super.key});

  @override
  State<QdrantAdminDialog> createState() => _QdrantAdminDialogState();
}

class _QdrantAdminDialogState extends State<QdrantAdminDialog> {
  late Future<List<Map<String, Object?>>> _collectionsFuture;
  Map<String, Object?>? _collectionInfo;
  Map<String, Object?>? _scrollResult;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _collectionsFuture = context
        .read<KnowledgeBaseController>()
        .listQdrantCollections();
  }

  void _refresh() {
    setState(() {
      _error = null;
      _collectionsFuture = context
          .read<KnowledgeBaseController>()
          .listQdrantCollections();
    });
  }

  Future<void> _loadInfo(String collection) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await context
          .read<KnowledgeBaseController>()
          .loadQdrantCollectionInfo(collection);
      if (mounted) setState(() => _collectionInfo = info);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scroll() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context
          .read<KnowledgeBaseController>()
          .scrollQdrantPoints();
      if (mounted) setState(() => _scrollResult = result);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      title: isZh ? '删除 Qdrant collection？' : 'Delete Qdrant collection?',
      message: isZh
          ? '将删除 collection "$collection" 及其中所有 points。此操作不可撤销。'
          : 'This deletes collection "$collection" and all points in it. This cannot be undone.',
      confirmLabel: isZh ? '删除 Collection' : 'Delete collection',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await controller.deleteQdrantCollection(collection);
      if (!mounted) return;
      OpenHandSnackBar.showSuccess(
        context,
        isZh ? 'Collection 已删除。' : 'Collection deleted.',
      );
      _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KnowledgeBaseController>();
    final isZh = openHandIsChineseLocale(context);
    return buildOpenHandAlertDialog(
      title: Text(isZh ? 'Qdrant 管理' : 'Qdrant Admin'),
      content: buildOpenHandDialogConstrainedContent(
        width: 880,
        maxHeight: MediaQuery.sizeOf(context).height * 0.80,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: KnowledgeDialogNotice(
                    icon: Icons.error_outline_rounded,
                    error: true,
                    message: _error!,
                  ),
                ),
              KnowledgeDialogSection(
                title: isZh ? 'Collections 列表' : 'Collections',
                icon: Icons.dataset_outlined,
                child: FutureBuilder<List<Map<String, Object?>>>(
                  future: _collectionsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const SizedBox(
                        height: 92,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final collections =
                        snapshot.data ?? const <Map<String, Object?>>[];
                    if (collections.isEmpty) {
                      return KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: isZh
                            ? '没有 collection 或 Qdrant 不可用。'
                            : 'No collection found or Qdrant unavailable.',
                      );
                    }
                    return Column(
                      children: [
                        for (final item in collections)
                          _CollectionTile(
                            item: item,
                            busy: _busy,
                            isZh: isZh,
                            onInfo: () => _loadInfo('${item['name'] ?? ''}'),
                            onDelete: () =>
                                _deleteCollection('${item['name'] ?? ''}'),
                          ),
                      ],
                    );
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? 'Points / 搜索 / 滚动读取' : 'Points / Search / Scroll',
                icon: Icons.manage_search_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KnowledgeDialogKeyValueList(
                      rows: {
                        isZh ? '当前 collection' : 'Current collection':
                            controller.settings.effectiveCollectionName,
                      },
                      labelWidth: isZh ? 150 : 170,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _scroll,
                      icon: const Icon(Icons.list_alt_rounded),
                      label: Text(
                        isZh ? '滚动读取前 20 个 points' : 'Scroll first 20 points',
                      ),
                    ),
                    if (_scrollResult case final scrollResult?) ...[
                      const SizedBox(height: 12),
                      KnowledgeDialogJsonBox(value: scrollResult),
                    ],
                  ],
                ),
              ),
              if (_collectionInfo case final collectionInfo?)
                KnowledgeDialogSection(
                  title: isZh
                      ? 'Collection 结构 / 配置'
                      : 'Collection schema / config',
                  icon: Icons.schema_outlined,
                  child: KnowledgeDialogJsonBox(value: collectionInfo),
                ),
              KnowledgeDialogSection(
                title: isZh ? '操作日志' : 'Operation Log',
                icon: Icons.receipt_long_outlined,
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
                                '${formatYearMonthDayHms(log.createdAt.toLocal())} · ${log.action} · ${log.detail}',
                              ),
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
          onPressed: _refresh,
          icon: Icons.refresh_rounded,
          label: isZh ? '刷新' : 'Refresh',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          label: isZh ? '关闭' : 'Close',
        ),
      ],
    );
  }
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
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
          const SizedBox(width: 8),
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
