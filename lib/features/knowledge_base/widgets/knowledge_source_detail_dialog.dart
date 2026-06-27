import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
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
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(context).pop(),
              label: isZh ? '关闭' : 'Close',
            ),
          ],
        );
      },
    );
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
                isZh ? '类型' : 'Kind': _localizedKind(source.kind, context),
                isZh ? '状态' : 'Status': _localizedStatus(
                  source.status,
                  context,
                ),
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
            title: isZh ? '分块 (${chunks.length})' : 'Chunks (${chunks.length})',
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

  String _localizedKind(String kind, BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    return switch (kind) {
      'markdown' => isZh ? 'Markdown 文档' : 'Markdown',
      'text' => isZh ? '文本' : 'Text',
      'code' => isZh ? '代码' : 'Code',
      'pdf' => isZh ? 'PDF' : 'PDF',
      'html' => isZh ? '网页 HTML' : 'HTML',
      'docx' => isZh ? 'Word 文档' : 'Word document',
      'spreadsheet' => isZh ? '电子表格' : 'Spreadsheet',
      'presentation' => isZh ? '演示文稿' : 'Presentation',
      'table' => isZh ? '表格数据' : 'Table data',
      'structured' => isZh ? '结构化数据' : 'Structured data',
      'note' => isZh ? '笔记' : 'Note',
      _ => kind.trim().isEmpty ? '-' : kind,
    };
  }

  String _localizedStatus(String status, BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    return switch (status) {
      'indexed' => isZh ? '已索引' : 'Indexed',
      'failed' => isZh ? '失败' : 'Failed',
      'indexing' => isZh ? '索引中' : 'Indexing',
      'pending' => isZh ? '待处理' : 'Pending',
      'cancelled' => isZh ? '已停止' : 'Stopped',
      _ => status.trim().isEmpty ? '-' : status,
    };
  }
}

class _ChunkTile extends StatelessWidget {
  const _ChunkTile({required this.chunk});

  final KnowledgeChunk chunk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
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
                label: isZh
                    ? '${chunk.tokenEstimate} token'
                    : '${chunk.tokenEstimate} tokens',
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
