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
import 'knowledge_dialog_widgets.dart';

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
                ? KnowledgeDialogNotice(
                    icon: Icons.info_outline_rounded,
                    message: isZh ? '来源不存在。' : 'Source not found.',
                  )
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
    final isZh = openHandIsChineseLocale(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeDialogSection(
            title: isZh ? '来源信息' : 'Source',
            icon: Icons.description_outlined,
            child: KnowledgeDialogKeyValueList(
              labelWidth: isZh ? 120 : 128,
              rows: {
                isZh ? '标题' : 'Title': source.title,
                isZh ? '类型' : 'Kind': source.kind,
                isZh ? '状态' : 'Status': source.status,
                isZh ? '原始路径' : 'Original path': source.originalPath,
                isZh ? '存储路径' : 'Stored path': source.storedPath,
                isZh ? '文档时间' : 'Document time': _date(source.documentTime),
                isZh ? '导入时间' : 'Imported at': _date(source.importedAt),
                isZh ? '索引时间' : 'Indexed at': _date(source.indexedAt),
                if (source.errorMessage.trim().isNotEmpty)
                  isZh ? '错误' : 'Error': source.errorMessage,
              },
            ),
          ),
          KnowledgeDialogSection(
            title: isZh
                ? 'Chunks (${chunks.length})'
                : 'Chunks (${chunks.length})',
            icon: Icons.article_outlined,
            margin: EdgeInsets.zero,
            child: chunks.isEmpty
                ? KnowledgeDialogNotice(
                    icon: Icons.info_outline_rounded,
                    message: isZh ? '暂无 chunk。' : 'No chunks yet.',
                  )
                : Column(
                    children: [
                      for (final chunk in chunks) _ChunkTile(chunk: chunk),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _date(DateTime? value) {
    return value == null ? '-' : formatYearMonthDayHms(value.toLocal());
  }
}

class _ChunkTile extends StatelessWidget {
  const _ChunkTile({required this.chunk});

  final KnowledgeChunk chunk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final heading = chunk.headingPath.isEmpty ? chunk.title : chunk.headingPath;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.48),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '#${chunk.chunkIndex}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              KnowledgeDialogChip(
                icon: Icons.numbers_rounded,
                label: '${chunk.tokenEstimate} tokens',
              ),
              KnowledgeDialogChip(
                icon: Icons.fingerprint_rounded,
                label: chunk.id,
              ),
            ],
          ),
          if (heading.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              heading,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            chunk.content,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.36),
          ),
        ],
      ),
    );
  }
}
