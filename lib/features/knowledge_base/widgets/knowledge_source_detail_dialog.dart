import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';
import '../model/knowledge_chunk.dart';
import '../model/knowledge_source.dart';

Future<void> showKnowledgeSourceDetailDialog(
  BuildContext context,
  String sourceId,
) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => KnowledgeSourceDetailDialog(sourceId: sourceId),
  );
}

class KnowledgeSourceDetailDialog extends StatelessWidget {
  const KnowledgeSourceDetailDialog({super.key, required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<KnowledgeBaseController>();
    final isZh = openHandIsChineseLocale(context);
    return FutureBuilder<(KnowledgeSource?, List<KnowledgeChunk>)>(
      future: () async {
        final source = await controller.loadSource(sourceId);
        final chunks = await controller.loadChunksForSource(sourceId);
        return (source, chunks);
      }(),
      builder: (context, snapshot) {
        final source = snapshot.data?.$1;
        final chunks = snapshot.data?.$2 ?? const <KnowledgeChunk>[];
        return buildOpenHandAlertDialog(
          title: Text(isZh ? '知识库来源详情' : 'Knowledge Source Detail'),
          content: buildOpenHandDialogConstrainedContent(
            width: 760,
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
            child: snapshot.connectionState != ConnectionState.done
                ? const SizedBox(
                    height: 240,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : source == null
                ? Text(isZh ? '来源不存在。' : 'Source not found.')
                : _SourceDetailBody(source: source, chunks: chunks),
          ),
          actions: [
            if (source != null)
              OpenHandDialogActionButton.secondary(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: source.originalPath)),
                icon: Icons.copy_rounded,
                label: isZh ? '复制路径' : 'Copy Path',
              ),
            if (source != null)
              OpenHandDialogActionButton.destructive(
                onPressed: () => _confirmDelete(context, source),
                icon: Icons.delete_outline_rounded,
                label: isZh ? '删除' : 'Delete',
              ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(context).pop(),
              label: isZh ? '关闭' : 'Close',
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    KnowledgeSource source,
  ) async {
    final isZh = openHandIsChineseLocale(context);
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '删除知识库来源？' : 'Delete knowledge source?',
      message: isZh
          ? '将删除 SQLite 元数据、chunks，并尝试删除 Qdrant 中该来源的向量。原始文件不会删除。'
          : 'This deletes SQLite metadata, chunks, and attempts to remove this source vectors from Qdrant. The original file is kept.',
      confirmLabel: isZh ? '删除' : 'Delete',
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<KnowledgeBaseController>().deleteSource(source);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    OpenHandSnackBar.showSuccess(context, isZh ? '来源已删除。' : 'Source deleted.');
  }
}

class _SourceDetailBody extends StatelessWidget {
  const _SourceDetailBody({required this.source, required this.chunks});

  final KnowledgeSource source;
  final List<KnowledgeChunk> chunks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kv(context, 'Title', source.title),
          _kv(context, 'Kind', source.kind),
          _kv(context, 'Status', source.status),
          _kv(context, 'Original path', source.originalPath),
          _kv(context, 'Stored path', source.storedPath),
          _kv(context, 'Document time', _date(source.documentTime)),
          _kv(context, 'Imported at', _date(source.importedAt)),
          _kv(context, 'Indexed at', _date(source.indexedAt)),
          if (source.errorMessage.trim().isNotEmpty)
            _kv(context, 'Error', source.errorMessage),
          const SizedBox(height: 16),
          Text(
            'Chunks ${chunks.length}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final chunk in chunks)
            Card(
              color: colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${chunk.chunkIndex} · ${chunk.headingPath.isEmpty ? chunk.title : chunk.headingPath}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      chunk.content,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${chunk.tokenEstimate} tokens · ${chunk.id}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value.trim().isEmpty ? '-' : value)),
        ],
      ),
    );
  }

  String _date(DateTime? value) {
    return value == null ? '-' : formatYearMonthDayHms(value.toLocal());
  }
}
