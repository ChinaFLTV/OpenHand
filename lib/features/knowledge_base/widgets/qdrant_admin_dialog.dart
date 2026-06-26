import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';

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
      confirmLabel: isZh ? '删除 collection' : 'Delete collection',
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
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isZh ? 'Collections' : 'Collections',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      FutureBuilder<List<Map<String, Object?>>>(
                        future: _collectionsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final collections =
                              snapshot.data ?? const <Map<String, Object?>>[];
                          if (collections.isEmpty) {
                            return Text(
                              isZh
                                  ? '没有 collection 或 Qdrant 不可用。'
                                  : 'No collection found or Qdrant unavailable.',
                            );
                          }
                          return Column(
                            children: [
                              for (final item in collections)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.dataset_outlined),
                                  title: Text('${item['name'] ?? ''}'),
                                  subtitle: Text(jsonEncode(item)),
                                  trailing: Wrap(
                                    spacing: 8,
                                    children: [
                                      IconButton(
                                        tooltip: isZh ? '查看配置' : 'View config',
                                        onPressed: _busy
                                            ? null
                                            : () => _loadInfo(
                                                '${item['name'] ?? ''}',
                                              ),
                                        icon: const Icon(
                                          Icons.info_outline_rounded,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: isZh ? '删除' : 'Delete',
                                        onPressed: _busy
                                            ? null
                                            : () => _deleteCollection(
                                                '${item['name'] ?? ''}',
                                              ),
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isZh
                            ? 'Points / Search / Scroll'
                            : 'Points / Search / Scroll',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isZh
                            ? '当前 collection：${controller.settings.effectiveCollectionName}'
                            : 'Current collection: ${controller.settings.effectiveCollectionName}',
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _scroll,
                          icon: const Icon(Icons.list_alt_rounded),
                          label: Text(
                            isZh
                                ? 'Scroll 前 20 个 points'
                                : 'Scroll first 20 points',
                          ),
                        ),
                      ),
                      if (_scrollResult case final scrollResult?) ...[
                        const SizedBox(height: 10),
                        _JsonBox(value: scrollResult),
                      ],
                    ],
                  ),
                ),
              ),
              if (_collectionInfo case final collectionInfo?)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          isZh
                              ? 'Collection schema/config'
                              : 'Collection schema/config',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        _JsonBox(value: collectionInfo),
                      ],
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isZh ? '操作日志' : 'Operation Log',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      if (controller.qdrantAdminLogs.isEmpty)
                        Text(isZh ? '暂无操作。' : 'No operations yet.')
                      else
                        for (final log in controller.qdrantAdminLogs)
                          Text(
                            '${formatYearMonthDayHms(log.createdAt.toLocal())} · ${log.action} · ${log.detail}',
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(isZh ? '刷新' : 'Refresh'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(isZh ? '关闭' : 'Close'),
        ),
      ],
    );
  }
}

class _JsonBox extends StatelessWidget {
  const _JsonBox({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    final text = const JsonEncoder.withIndent('  ').convert(value);
    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
