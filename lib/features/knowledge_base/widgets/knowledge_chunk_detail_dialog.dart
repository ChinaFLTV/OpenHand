import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../model/knowledge_chunk.dart';
import '../model/knowledge_source.dart';
import 'knowledge_dialog_widgets.dart';

Future<void> showKnowledgeChunkDetailDialog(
  BuildContext context, {
  required KnowledgeSource source,
  required KnowledgeChunk chunk,
  Map<String, Object?>? retrievalHit,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => KnowledgeChunkDetailDialog(
      source: source,
      chunk: chunk,
      retrievalHit: retrievalHit,
    ),
  );
}

class KnowledgeChunkDetailDialog extends StatelessWidget {
  const KnowledgeChunkDetailDialog({
    super.key,
    required this.source,
    required this.chunk,
    this.retrievalHit,
  });

  final KnowledgeSource source;
  final KnowledgeChunk chunk;
  final Map<String, Object?>? retrievalHit;

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    final metadata = chunk.metadata;
    return buildOpenHandAlertDialog(
      title: Text(isZh ? '分块详情' : 'Chunk Detail'),
      content: buildOpenHandDialogConstrainedContent(
        width: 820,
        maxHeight: MediaQuery.sizeOf(context).height * 0.80,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (retrievalHit != null)
                KnowledgeDialogSection(
                  title: isZh ? '检索命中' : 'Retrieval Hit',
                  icon: Icons.manage_search_rounded,
                  child: KnowledgeDialogKeyValueList(
                    labelWidth: isZh ? 112 : 132,
                    rows: _retrievalRows(retrievalHit!, isZh),
                  ),
                ),
              KnowledgeDialogSection(
                title: isZh ? '基础信息' : 'Overview',
                icon: Icons.article_outlined,
                child: KnowledgeDialogKeyValueList(
                  labelWidth: isZh ? 112 : 132,
                  rows: {
                    isZh ? '分块 ID' : 'Chunk ID': chunk.id,
                    isZh ? '来源 ID' : 'Source ID': source.id,
                    isZh ? '来源标题' : 'Source title': source.title,
                    isZh ? '序号' : 'Index': chunk.chunkIndex,
                    if (_notBlank(chunk.parentChunkId))
                      isZh ? '父分块 ID' : 'Parent chunk ID': chunk.parentChunkId,
                    isZh ? '标题' : 'Title': chunk.title,
                    isZh ? '层级路径' : 'Heading path': chunk.headingPath,
                    isZh ? '内容哈希' : 'Content hash': chunk.contentHash,
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '统计与定位' : 'Stats & Location',
                icon: Icons.data_usage_rounded,
                child: KnowledgeDialogKeyValueList(
                  labelWidth: isZh ? 112 : 132,
                  rows: {
                    isZh ? '字符数' : 'Characters': chunk.charCount,
                    isZh ? '预估 token' : 'Estimated tokens': chunk.tokenEstimate,
                    if (chunk.startOffset != null)
                      isZh ? '起始偏移' : 'Start offset': chunk.startOffset,
                    if (chunk.endOffset != null)
                      isZh ? '结束偏移' : 'End offset': chunk.endOffset,
                    if (chunk.pageNumber != null)
                      isZh ? '页码' : 'Page': chunk.pageNumber,
                    isZh ? '文档时间' : 'Document time': _date(chunk.documentTime),
                    isZh ? '创建时间' : 'Created at': _date(chunk.createdAt),
                    isZh ? '更新时间' : 'Updated at': _date(chunk.updatedAt),
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '标签' : 'Tags',
                icon: Icons.sell_outlined,
                child: chunk.tags.isEmpty
                    ? KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: isZh ? '该分块没有标签。' : 'No tags on this chunk.',
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in chunk.tags)
                            KnowledgeDialogChip(
                              icon: Icons.tag_rounded,
                              label: tag,
                            ),
                        ],
                      ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '元数据' : 'Metadata',
                icon: Icons.account_tree_outlined,
                child: metadata.isEmpty
                    ? KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: isZh
                            ? '该分块没有额外元数据。'
                            : 'No additional metadata.',
                      )
                    : KnowledgeDialogJsonBox(value: metadata, maxHeight: 260),
              ),
              KnowledgeDialogSection(
                title: isZh ? '完整内容' : 'Full Content',
                icon: Icons.notes_rounded,
                margin: EdgeInsets.zero,
                child: KnowledgeDialogTextBox(
                  text: chunk.content,
                  maxHeight: 360,
                  emptyText: isZh ? '分块内容为空。' : 'Chunk content is empty.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () => _copyText(
            context,
            chunk.id,
            isZh ? '已复制分块 ID。' : 'Chunk ID copied.',
          ),
          icon: Icons.fingerprint_rounded,
          label: isZh ? '复制 ID' : 'Copy ID',
        ),
        OpenHandDialogActionButton.secondary(
          onPressed: () => _copyText(
            context,
            chunk.content,
            isZh ? '已复制分块内容。' : 'Chunk content copied.',
          ),
          icon: Icons.copy_all_rounded,
          label: isZh ? '复制内容' : 'Copy Content',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '关闭' : 'Close',
        ),
      ],
    );
  }

  Map<String, Object?> _retrievalRows(Map<String, Object?> hit, bool isZh) {
    return {
      if (_hasValue(hit['score'])) isZh ? '召回分数' : 'Score': hit['score'],
      if (_hasValue(hit['rerank_score']))
        isZh ? '重排分数' : 'Rerank score': hit['rerank_score'],
      if (_hasValue(hit['final_score']))
        isZh ? '最终分数' : 'Final score': hit['final_score'],
      if (_hasValue(hit['time_field']))
        isZh ? '时间字段' : 'Time field': hit['time_field'],
      if (_hasValue(hit['path'])) isZh ? '来源路径' : 'Path': hit['path'],
      if (_hasValue(hit['document_time']))
        isZh ? '文档时间' : 'Document time': hit['document_time'],
      if (_hasValue(hit['updated_at']))
        isZh ? '更新时间' : 'Updated at': hit['updated_at'],
    };
  }

  String _date(DateTime? value) {
    return value == null ? '-' : formatYearMonthDayHms(value.toLocal());
  }

  bool _notBlank(String? value) => value?.trim().isNotEmpty == true;

  bool _hasValue(Object? value) {
    return value != null && '$value'.trim().isNotEmpty;
  }

  Future<void> _copyText(
    BuildContext context,
    String text,
    String message,
  ) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      OpenHandSnackBar.showSuccess(context, message);
    }
  }
}
