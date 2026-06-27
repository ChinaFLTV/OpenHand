import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';
import '../model/knowledge_message_metadata.dart';
import 'knowledge_dialog_widgets.dart';

Future<void> showKnowledgeRetrievalDetailDialog(
  BuildContext context,
  Map<String, Object?> metadata,
) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => KnowledgeRetrievalDetailDialog(metadata: metadata),
  );
}

class KnowledgeRetrievalDetailDialog extends StatelessWidget {
  const KnowledgeRetrievalDetailDialog({super.key, required this.metadata});

  final Map<String, Object?> metadata;

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    final kb =
        KnowledgeMessageMetadata.fromMessageMetadata(metadata) ??
        const <String, Object?>{};
    final results = _listOfMaps(kb['results']);
    final prompt = KnowledgeMessageMetadata.promptAppendContent(metadata);
    return buildOpenHandAlertDialog(
      title: Text(isZh ? '引用知识库详情' : 'Knowledge Base References'),
      content: buildOpenHandDialogConstrainedContent(
        width: 820,
        maxHeight: MediaQuery.sizeOf(context).height * 0.80,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KnowledgeDialogSection(
                title: isZh ? '总览' : 'Overview',
                icon: Icons.fact_check_outlined,
                child: KnowledgeDialogKeyValueList(
                  rows: {
                    isZh ? '状态' : 'Status': kb['status'],
                    isZh ? '查询' : 'Query': kb['query'],
                    isZh ? '错误' : 'Error': kb['error'],
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '嵌入' : 'Embedding',
                icon: Icons.hub_outlined,
                child: KnowledgeDialogKeyValueList(
                  rows: _localizedRows(_map(kb['embedding']), isZh),
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '检索参数' : 'Retrieval Parameters',
                icon: Icons.manage_search_rounded,
                child: KnowledgeDialogKeyValueList(
                  rows: _localizedRows(_map(kb['retrieval']), isZh),
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? 'Prompt 追加' : 'Prompt Append',
                icon: Icons.post_add_outlined,
                child: KnowledgeDialogKeyValueList(
                  rows: _localizedRows(_map(kb['prompt_append']), isZh),
                ),
              ),
              KnowledgeDialogSection(
                title: isZh
                    ? '命中分块 (${results.length})'
                    : 'Hit chunks (${results.length})',
                icon: Icons.article_outlined,
                child: results.isEmpty
                    ? KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: isZh ? '没有命中 chunk。' : 'No hit chunks.',
                      )
                    : Column(
                        children: [
                          for (final hit in results) _HitTile(hit: hit),
                        ],
                      ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '实际追加给模型的上下文' : 'Actual appended context',
                icon: Icons.notes_rounded,
                margin: EdgeInsets.zero,
                child: KnowledgeDialogTextBox(text: prompt, maxHeight: 300),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text: const JsonEncoder.withIndent('  ').convert(kb),
              ),
            );
            if (context.mounted) {
              OpenHandSnackBar.showSuccess(
                context,
                isZh ? '已复制知识库元数据。' : 'Knowledge metadata copied.',
              );
            }
          },
          icon: Icons.copy_rounded,
          label: isZh ? '复制元数据' : 'Copy metadata',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '关闭' : 'Close',
        ),
      ],
    );
  }

  Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    return const <String, Object?>{};
  }

  List<Map<String, Object?>> _listOfMaps(Object? value) {
    if (value is! List) return const <Map<String, Object?>>[];
    return value
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  Map<String, Object?> _localizedRows(Map<String, Object?> rows, bool isZh) {
    if (!isZh) return rows;
    return <String, Object?>{
      for (final entry in rows.entries) _metadataLabel(entry.key): entry.value,
    };
  }

  String _metadataLabel(String key) {
    return switch (key) {
      'provider_config_id' => 'Provider 配置',
      'model_id' => '模型 ID',
      'dimensions' => '向量维度',
      'duration_ms' => '耗时毫秒',
      'top_n' => '召回 topN',
      'top_k' => '最终 topK',
      'min_similarity' => '最低相似度',
      'filters' => '过滤条件',
      'chunk_count' => '追加分块数',
      'token_estimate' => '预估 token',
      'content_hash' => '内容哈希',
      _ => key,
    };
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});

  final Map<String, Object?> hit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    final title =
        '${hit['title'] ?? hit['source_title'] ?? hit['chunk_id'] ?? ''}';
    final path = '${hit['path'] ?? ''}'.trim();
    final preview = '${hit['preview'] ?? ''}'.trim();
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
          SelectableText(
            title.trim().isEmpty ? (isZh ? '知识库命中' : 'KB hit') : title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          if (path.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.25,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              KnowledgeDialogChip(
                icon: Icons.trending_up_rounded,
                label: '${isZh ? '分数' : 'score'} ${hit['score'] ?? '-'}',
              ),
              if (hit['rerank_score'] != null)
                KnowledgeDialogChip(
                  icon: Icons.filter_alt_rounded,
                  label: '${isZh ? '重排' : 'rerank'} ${hit['rerank_score']}',
                ),
              if (hit['token_estimate'] != null)
                KnowledgeDialogChip(
                  icon: Icons.data_usage_rounded,
                  label: isZh
                      ? '${hit['token_estimate']} token'
                      : '${hit['token_estimate']} tokens',
                ),
              if ('${hit['document_time'] ?? ''}'.trim().isNotEmpty)
                KnowledgeDialogChip(
                  icon: Icons.event_rounded,
                  label: '${hit['document_time']}',
                ),
            ],
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              preview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.36),
            ),
          ],
        ],
      ),
    );
  }
}
