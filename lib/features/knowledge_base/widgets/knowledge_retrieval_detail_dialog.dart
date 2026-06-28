import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';
import '../model/knowledge_chunk.dart';
import '../model/knowledge_message_metadata.dart';
import '../model/knowledge_source.dart';
import '../model/knowledge_vector_distribution.dart';
import 'knowledge_chunk_detail_dialog.dart';
import 'knowledge_dialog_widgets.dart';
import 'knowledge_vector_distribution_view.dart';

Future<void> showKnowledgeRetrievalDetailDialog(
  BuildContext context,
  Map<String, Object?> metadata,
) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => KnowledgeRetrievalDetailDialog(metadata: metadata),
  );
}

Future<void> _showKnowledgeRetrievalHitDetailDialog(
  BuildContext context,
  Map<String, Object?> hit,
) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _KnowledgeRetrievalHitDetailDialog(hit: hit),
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
    final results = stringKeyedMapListFromValue(kb['results']);
    final prompt = KnowledgeMessageMetadata.promptAppendContent(metadata);
    final rerank = stringKeyedMapFromValue(kb['rerank']);
    final distribution = KnowledgeMessageMetadata.vectorDistribution(metadata);
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
                  rows: _localizedRows(
                    stringKeyedMapFromValue(kb['embedding']),
                    isZh,
                  ),
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '检索参数' : 'Retrieval Parameters',
                icon: Icons.manage_search_rounded,
                child: KnowledgeDialogKeyValueList(
                  rows: _localizedRows(
                    stringKeyedMapFromValue(kb['retrieval']),
                    isZh,
                  ),
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? 'Prompt 追加' : 'Prompt Append',
                icon: Icons.post_add_outlined,
                child: KnowledgeDialogKeyValueList(
                  rows: _localizedRows(
                    stringKeyedMapFromValue(kb['prompt_append']),
                    isZh,
                  ),
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '重排序' : 'Rerank',
                subtitle: isZh
                    ? '展示召回后如何打分、排序、保留与舍弃分块。'
                    : 'Shows how recalled chunks were scored, reordered, kept, or discarded.',
                icon: Icons.swap_vert_rounded,
                child: rerank.isEmpty
                    ? KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: isZh
                            ? '本次消息没有记录重排序细节。'
                            : 'No rerank details were recorded for this message.',
                      )
                    : KnowledgeDialogKeyValueList(
                        rows: _localizedRows(rerank, isZh),
                      ),
              ),
              if (distribution != null)
                _KnowledgeRetrievalVectorSpaceSection(
                  distribution: distribution,
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
      'mode' => '模式',
      'strategy' => '策略',
      'candidate_count' => '候选数',
      'rerank_input_count' => '重排输入数',
      'rerank_output_count' => '重排输出数',
      'kept_count' => '保留数',
      'discarded_count' => '舍弃数',
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
    final documentTimeLabel = _formatKnowledgeDateTime(hit['document_time']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showKnowledgeRetrievalHitDetailDialog(context, hit),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.48),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.trim().isEmpty ? (isZh ? '知识库命中' : 'KB hit') : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                        label:
                            '${isZh ? '重排' : 'rerank'} ${hit['rerank_score']}',
                      ),
                    if (hit['token_estimate'] != null)
                      KnowledgeDialogChip(
                        icon: Icons.data_usage_rounded,
                        label: isZh
                            ? '${hit['token_estimate']} token'
                            : '${hit['token_estimate']} tokens',
                      ),
                    if (documentTimeLabel.isNotEmpty)
                      KnowledgeDialogChip(
                        icon: Icons.event_rounded,
                        label: documentTimeLabel,
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
          ),
        ),
      ),
    );
  }
}

class _KnowledgeRetrievalHitDetailDialog extends StatefulWidget {
  const _KnowledgeRetrievalHitDetailDialog({required this.hit});

  final Map<String, Object?> hit;

  @override
  State<_KnowledgeRetrievalHitDetailDialog> createState() =>
      _KnowledgeRetrievalHitDetailDialogState();
}

class _KnowledgeRetrievalHitDetailDialogState
    extends State<_KnowledgeRetrievalHitDetailDialog> {
  late final Future<_ResolvedKnowledgeHit> _future = _resolve();

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    return FutureBuilder<_ResolvedKnowledgeHit>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return buildOpenHandAlertDialog(
            title: Text(isZh ? '命中分块详情' : 'Hit Chunk Detail'),
            content: buildOpenHandDialogConstrainedContent(
              width: 520,
              maxHeight: MediaQuery.sizeOf(context).height * 0.64,
              child: const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            actions: [
              OpenHandDialogActionButton.primary(
                onPressed: () => Navigator.of(context).pop(),
                label: isZh ? '关闭' : 'Close',
              ),
            ],
          );
        }
        final resolved = snapshot.data ?? const _ResolvedKnowledgeHit();
        if (resolved.source != null && resolved.chunk != null) {
          return KnowledgeChunkDetailDialog(
            source: resolved.source!,
            chunk: resolved.chunk!,
            retrievalHit: widget.hit,
          );
        }
        return _KnowledgeRetrievalHitFallbackDialog(hit: widget.hit);
      },
    );
  }

  Future<_ResolvedKnowledgeHit> _resolve() async {
    final sourceId = _text(widget.hit['source_id']);
    final chunkId = _text(widget.hit['chunk_id']);
    if (sourceId.isEmpty || chunkId.isEmpty) {
      return const _ResolvedKnowledgeHit();
    }
    final controller = context.read<KnowledgeBaseController>();
    final source = await controller.loadSource(sourceId);
    if (source == null) {
      return const _ResolvedKnowledgeHit();
    }
    final chunks = await controller.loadChunksForSource(sourceId);
    for (final chunk in chunks) {
      if (chunk.id == chunkId) {
        return _ResolvedKnowledgeHit(source: source, chunk: chunk);
      }
    }
    return _ResolvedKnowledgeHit(source: source);
  }
}

class _KnowledgeRetrievalVectorSpaceSection extends StatefulWidget {
  const _KnowledgeRetrievalVectorSpaceSection({required this.distribution});

  final KnowledgeVectorDistribution distribution;

  @override
  State<_KnowledgeRetrievalVectorSpaceSection> createState() =>
      _KnowledgeRetrievalVectorSpaceSectionState();
}

class _KnowledgeRetrievalVectorSpaceSectionState
    extends State<_KnowledgeRetrievalVectorSpaceSection> {
  bool _showCorpus = false;
  bool _loadingCorpus = false;
  KnowledgeVectorDistribution? _corpusDistribution;
  Object? _corpusError;

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    final visibleDistribution = _showCorpus && _corpusDistribution != null
        ? _mergeCorpusDistribution(
            corpus: _corpusDistribution!,
            retrieval: widget.distribution,
          )
        : widget.distribution;
    final corpusCount = _corpusDistribution?.points.length ?? 0;
    return KnowledgeDialogSection(
      title: isZh ? '向量空间' : 'Vector Space',
      subtitle: _showCorpus
          ? (isZh
                ? '天蓝色为全量采样，橙色为当前命中结果，红色为查询向量。'
                : 'Sky blue points are corpus samples; orange points are matched chunks; red is the query vector.')
          : (isZh
                ? '红色为查询向量，橙色为当前命中结果。'
                : 'Red is the query vector; orange points are matched chunks.'),
      icon: Icons.scatter_plot_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _toggleCorpusOverlay,
              icon: Icon(
                _showCorpus
                    ? Icons.visibility_off_outlined
                    : Icons.blur_on_rounded,
              ),
              label: Text(
                _showCorpus
                    ? (isZh ? '隐藏全量' : 'Hide Corpus')
                    : (isZh ? '叠加全量' : 'Overlay Corpus'),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _buildCorpusStatus(context, isZh, corpusCount),
          ),
          const SizedBox(height: 10),
          KnowledgeVectorDistributionView(
            distribution: visibleDistribution,
            height: 380,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCorpusStatus(BuildContext context, bool isZh, int corpusCount) {
    if (_loadingCorpus && _showCorpus) {
      return Padding(
        key: const ValueKey('corpus-loading'),
        padding: const EdgeInsets.only(top: 10),
        child: KnowledgeDialogNotice(
          icon: Icons.hourglass_top_rounded,
          message: isZh
              ? '正在按需采样并叠加全量向量。'
              : 'Sampling and overlaying corpus vectors on demand.',
        ),
      );
    }
    if (_showCorpus && _corpusError != null) {
      return Padding(
        key: const ValueKey('corpus-error'),
        padding: const EdgeInsets.only(top: 10),
        child: KnowledgeDialogNotice(
          icon: Icons.error_outline_rounded,
          message:
              '${isZh ? '全量向量加载失败：' : 'Failed to load corpus vectors: '}${_corpusError!}',
          tone: KnowledgeDialogNoticeTone.error,
        ),
      );
    }
    if (_showCorpus && _corpusDistribution != null) {
      final sampled = _corpusDistribution!.hasMore;
      return Padding(
        key: const ValueKey('corpus-ready'),
        padding: const EdgeInsets.only(top: 10),
        child: KnowledgeDialogNotice(
          icon: sampled
              ? Icons.filter_center_focus_rounded
              : Icons.done_rounded,
          message: sampled
              ? (isZh
                    ? '已叠加 $corpusCount 个全量采样点；数据量较大时会采样展示以保持流畅。'
                    : 'Overlaying $corpusCount sampled corpus points; large collections are sampled to keep the view responsive.')
              : (isZh
                    ? '已叠加 $corpusCount 个全量向量点。'
                    : 'Overlaying $corpusCount corpus points.'),
        ),
      );
    }
    return const SizedBox.shrink(key: ValueKey('corpus-empty-status'));
  }

  void _toggleCorpusOverlay() {
    if (_showCorpus) {
      setState(() => _showCorpus = false);
      return;
    }
    setState(() {
      _showCorpus = true;
      _corpusError = null;
    });
    _loadCorpusDistribution();
  }

  Future<void> _loadCorpusDistribution() async {
    if (_corpusDistribution != null || _loadingCorpus) return;
    setState(() => _loadingCorpus = true);
    try {
      final distribution = await context
          .read<KnowledgeBaseController>()
          .loadVectorDistribution();
      if (!mounted) return;
      setState(() {
        _corpusDistribution = distribution;
        _loadingCorpus = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _corpusError = error;
        _loadingCorpus = false;
      });
    }
  }

  KnowledgeVectorDistribution _mergeCorpusDistribution({
    required KnowledgeVectorDistribution corpus,
    required KnowledgeVectorDistribution retrieval,
  }) {
    final highlightedIds = retrieval.points
        .where((point) => point.kind != KnowledgeVectorPointKind.corpus)
        .map((point) => point.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    final points = <KnowledgeVectorDistributionPoint>[
      for (final point in corpus.points)
        if (!highlightedIds.contains(point.id)) point,
      ...retrieval.points,
    ];
    return retrieval.copyWith(
      points: points,
      originalDimensions: retrieval.originalDimensions > 0
          ? retrieval.originalDimensions
          : corpus.originalDimensions,
      sampledCount: points.length,
      hasMore: corpus.hasMore,
      durationMs: corpus.durationMs,
      generatedAt: corpus.generatedAt ?? retrieval.generatedAt,
    );
  }
}

class _KnowledgeRetrievalHitFallbackDialog extends StatelessWidget {
  const _KnowledgeRetrievalHitFallbackDialog({required this.hit});

  final Map<String, Object?> hit;

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    final chunkId = _text(hit['chunk_id']);
    final preview = _text(hit['preview']);
    final title = _hasValue(hit['title']) ? hit['title'] : hit['source_title'];
    final tags = _stringList(hit['tags']);
    return buildOpenHandAlertDialog(
      title: Text(isZh ? '命中分块详情' : 'Hit Chunk Detail'),
      content: buildOpenHandDialogConstrainedContent(
        width: 820,
        maxHeight: MediaQuery.sizeOf(context).height * 0.80,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KnowledgeDialogNotice(
                icon: Icons.info_outline_rounded,
                message: isZh
                    ? '未能从本地知识库恢复完整 chunk，下面展示消息元数据中保留的命中信息。'
                    : 'The full chunk could not be restored locally. Showing hit metadata saved with this message.',
                tone: KnowledgeDialogNoticeTone.warning,
              ),
              const SizedBox(height: 12),
              KnowledgeDialogSection(
                title: isZh ? '基础信息' : 'Overview',
                icon: Icons.article_outlined,
                child: KnowledgeDialogKeyValueList(
                  labelWidth: isZh ? 112 : 132,
                  rows: {
                    isZh ? '分块 ID' : 'Chunk ID': chunkId,
                    isZh ? '来源 ID' : 'Source ID': hit['source_id'],
                    isZh ? '标题' : 'Title': title,
                    isZh ? '路径' : 'Path': hit['path'],
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '检索数据' : 'Retrieval Data',
                icon: Icons.manage_search_rounded,
                child: KnowledgeDialogKeyValueList(
                  labelWidth: isZh ? 112 : 132,
                  rows: {
                    if (_hasValue(hit['score']))
                      isZh ? '召回分数' : 'Score': hit['score'],
                    if (_hasValue(hit['rerank_score']))
                      isZh ? '重排分数' : 'Rerank score': hit['rerank_score'],
                    if (_hasValue(hit['final_score']))
                      isZh ? '最终分数' : 'Final score': hit['final_score'],
                    if (_hasValue(hit['token_estimate']))
                      isZh ? '预估 token' : 'Estimated tokens':
                          hit['token_estimate'],
                    if (_hasValue(hit['time_field']))
                      isZh ? '时间字段' : 'Time field': hit['time_field'],
                    if (_hasValue(hit['document_time']))
                      isZh ? '文档时间' : 'Document time': _formatKnowledgeDateTime(
                        hit['document_time'],
                      ),
                    if (_hasValue(hit['updated_at']))
                      isZh ? '更新时间' : 'Updated at': _formatKnowledgeDateTime(
                        hit['updated_at'],
                      ),
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '标签' : 'Tags',
                icon: Icons.sell_outlined,
                child: tags.isEmpty
                    ? KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: isZh
                            ? '消息元数据中没有标签。'
                            : 'No tags in message metadata.',
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in tags)
                            KnowledgeDialogChip(
                              icon: Icons.tag_rounded,
                              label: tag,
                            ),
                        ],
                      ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '命中预览' : 'Hit Preview',
                icon: Icons.notes_rounded,
                child: KnowledgeDialogTextBox(
                  text: preview,
                  emptyText: isZh
                      ? '消息元数据中没有命中预览。'
                      : 'No hit preview in message metadata.',
                ),
              ),
              KnowledgeDialogSection(
                title: isZh ? '原始命中元数据' : 'Raw Hit Metadata',
                icon: Icons.account_tree_outlined,
                margin: EdgeInsets.zero,
                child: KnowledgeDialogJsonBox(value: hit, maxHeight: 260),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (chunkId.isNotEmpty)
          OpenHandDialogActionButton.secondary(
            onPressed: () => _copyText(
              context,
              chunkId,
              isZh ? '已复制分块 ID。' : 'Chunk ID copied.',
            ),
            icon: Icons.fingerprint_rounded,
            label: isZh ? '复制 ID' : 'Copy ID',
          ),
        OpenHandDialogActionButton.secondary(
          onPressed: preview.isEmpty
              ? null
              : () => _copyText(
                  context,
                  preview,
                  isZh ? '已复制命中预览。' : 'Hit preview copied.',
                ),
          icon: Icons.copy_all_rounded,
          label: isZh ? '复制预览' : 'Copy Preview',
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: isZh ? '关闭' : 'Close',
        ),
      ],
    );
  }
}

class _ResolvedKnowledgeHit {
  const _ResolvedKnowledgeHit({this.source, this.chunk});

  final KnowledgeSource? source;
  final KnowledgeChunk? chunk;
}

String _text(Object? value) => value == null ? '' : '$value'.trim();

bool _hasValue(Object? value) {
  final text = _text(value);
  return text.isNotEmpty && text != 'null';
}

String _formatKnowledgeDateTime(Object? value) {
  final parsed = _dateTimeFromValue(value);
  if (parsed == null) return _hasValue(value) ? _text(value) : '';
  return formatYearMonthDayHms(parsed.toLocal());
}

DateTime? _dateTimeFromValue(Object? value) {
  if (value is DateTime) return value;
  if (value is num && value.isFinite) {
    final raw = value.toInt();
    if (raw <= 0) return null;
    final milliseconds = raw > 1000000000000 ? raw : raw * 1000;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }
  final text = _text(value);
  if (text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text);
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) return const <String>[];
  return value
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
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
