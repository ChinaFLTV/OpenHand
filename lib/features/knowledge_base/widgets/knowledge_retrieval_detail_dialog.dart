import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_spacing.dart';
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
    builder: (_) => _KnowledgeRetrievalDetailDialog(metadata: metadata),
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

class _KnowledgeRetrievalDetailDialog extends StatelessWidget {
  const _KnowledgeRetrievalDetailDialog({required this.metadata});

  final Map<String, Object?> metadata;

  @override
  Widget build(BuildContext context) {
    final kb =
        KnowledgeMessageMetadata.fromMessageMetadata(metadata) ??
        const <String, Object?>{};
    final results = stringKeyedMapListFromValue(kb['results']);
    final rerank = stringKeyedMapFromValue(kb['rerank']);
    final distribution = KnowledgeMessageMetadata.vectorDistribution(metadata);
    return buildOpenHandAlertDialog(
      title: Text(
        openHandLocalizedText(
          context,
          zh: '引用知识库详情',
          zhHant: '引用知識庫詳情',
          en: 'Knowledge Base References',
          fr: 'Références de la base de connaissances',
          de: 'Wissensdatenbank-Referenzen',
          ja: 'ナレッジベース参照',
        ),
      ),
      content: buildOpenHandDialogConstrainedContent(
        width: 820,
        maxHeight: MediaQuery.sizeOf(context).height * 0.80,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KnowledgeDialogSection(
                title: openHandLocalizedText(
                  context,
                  zh: '总览',
                  zhHant: '總覽',
                  en: 'Overview',
                  fr: 'Vue d’ensemble',
                  de: 'Übersicht',
                  ja: '概要',
                ),
                icon: Icons.fact_check_outlined,
                child: KnowledgeDialogKeyValueList(
                  rows: {
                    knowledgeStatusLabel(context): kb['status'],
                    knowledgeQueryLabel(context): kb['query'],
                    knowledgeErrorLabel(context): kb['error'],
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: openHandLocalizedText(
                  context,
                  zh: '嵌入',
                  zhHant: '嵌入',
                  en: 'Embedding',
                  fr: 'Embedding',
                  de: 'Embedding',
                  ja: '埋め込み',
                ),
                icon: Icons.hub_outlined,
                child: KnowledgeDialogKeyValueList(
                  rows: _localizedRows(
                    context,
                    stringKeyedMapFromValue(kb['embedding']),
                  ),
                ),
              ),
              KnowledgeDialogSection(
                title: openHandLocalizedText(
                  context,
                  zh: '检索参数',
                  zhHant: '檢索參數',
                  en: 'Retrieval Parameters',
                  fr: 'Paramètres de recherche',
                  de: 'Abrufparameter',
                  ja: '検索パラメータ',
                ),
                icon: Icons.manage_search_rounded,
                child: KnowledgeDialogKeyValueList(
                  rows: _localizedRows(
                    context,
                    stringKeyedMapFromValue(kb['retrieval']),
                  ),
                ),
              ),
              KnowledgeDialogSection(
                title: openHandLocalizedText(
                  context,
                  zh: 'Prompt 追加',
                  zhHant: 'Prompt 追加',
                  en: 'Prompt Append',
                  fr: 'Ajout au prompt',
                  de: 'Prompt-Anhang',
                  ja: 'Prompt 追加',
                ),
                icon: Icons.post_add_outlined,
                child: KnowledgeDialogKeyValueList(
                  rows: _localizedRows(
                    context,
                    stringKeyedMapFromValue(kb['prompt_append']),
                  ),
                ),
              ),
              KnowledgeDialogSection(
                title: openHandLocalizedText(
                  context,
                  zh: '重排序',
                  zhHant: '重排序',
                  en: 'Rerank',
                  fr: 'Reclassement',
                  de: 'Reranking',
                  ja: '再ランク',
                ),
                subtitle: openHandLocalizedText(
                  context,
                  zh: '展示召回后如何打分、排序、保留与舍弃分块。',
                  zhHant: '展示召回後如何打分、排序、保留與捨棄分塊。',
                  en: 'Shows how recalled chunks were scored, reordered, kept, or discarded.',
                  fr: 'Affiche comment les fragments rappelés ont été notés, réordonnés, conservés ou ignorés.',
                  de: 'Zeigt, wie abgerufene Abschnitte bewertet, neu sortiert, behalten oder verworfen wurden.',
                  ja: '取得したチャンクのスコア付け、並べ替え、保持、破棄を表示します。',
                ),
                icon: Icons.swap_vert_rounded,
                child: rerank.isEmpty
                    ? KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: openHandLocalizedText(
                          context,
                          zh: '本次消息没有记录重排序细节。',
                          zhHant: '本次訊息沒有記錄重排序細節。',
                          en: 'No rerank details were recorded for this message.',
                          fr: 'Aucun détail de reclassement n’a été enregistré pour ce message.',
                          de: 'Für diese Nachricht wurden keine Reranking-Details aufgezeichnet.',
                          ja: 'このメッセージには再ランクの詳細が記録されていません。',
                        ),
                      )
                    : KnowledgeDialogKeyValueList(
                        rows: _localizedRows(context, rerank),
                      ),
              ),
              if (distribution != null)
                _KnowledgeRetrievalVectorSpaceSection(
                  distribution: distribution,
                ),
              KnowledgeDialogSection(
                title: openHandLocalizedText(
                  context,
                  zh: '命中分块 (${results.length})',
                  zhHant: '命中分塊 (${results.length})',
                  en: 'Hit chunks (${results.length})',
                  fr: 'Fragments trouvés (${results.length})',
                  de: 'Trefferabschnitte (${results.length})',
                  ja: 'ヒットチャンク (${results.length})',
                ),
                icon: Icons.article_outlined,
                child: results.isEmpty
                    ? KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: openHandLocalizedText(
                          context,
                          zh: '没有命中 chunk。',
                          zhHant: '沒有命中 chunk。',
                          en: 'No hit chunks.',
                          fr: 'Aucun fragment trouvé.',
                          de: 'Keine Trefferabschnitte.',
                          ja: 'ヒットしたチャンクはありません。',
                        ),
                      )
                    : Column(
                        children: [
                          for (final hit in results) _HitTile(hit: hit),
                        ],
                      ),
              ),
              KnowledgeDialogSection(
                title: openHandLocalizedText(
                  context,
                  zh: '实际追加给模型的上下文',
                  zhHant: '實際追加給模型的上下文',
                  en: 'Actual appended context',
                  fr: 'Contexte réellement ajouté',
                  de: 'Tatsächlich angehängter Kontext',
                  ja: '実際にモデルへ追加されたコンテキスト',
                ),
                icon: Icons.notes_rounded,
                margin: EdgeInsets.zero,
                child: _KnowledgePromptAppendContextBox(metadata: kb),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OpenHandDialogActionButton.secondary(
          onPressed: () async {
            await copyOpenHandTextToClipboard(
              logTag: 'knowledge_base',
              context: context,
              text: prettyPrintJson(kb),
              successMessage: openHandLocalizedText(
                context,
                zh: '已复制知识库元数据。',
                zhHant: '已複製知識庫元資料。',
                en: 'Knowledge metadata copied.',
                fr: 'Métadonnées copiées.',
                de: 'Wissensdatenbank-Metadaten kopiert.',
                ja: 'ナレッジベースのメタデータをコピーしました。',
              ),
              logAction: '复制检索元数据',
            );
          },
          icon: Icons.copy_rounded,
          label: openHandLocalizedText(
            context,
            zh: '复制元数据',
            zhHant: '複製元資料',
            en: 'Copy metadata',
            fr: 'Copier les métadonnées',
            de: 'Metadaten kopieren',
            ja: 'メタデータをコピー',
          ),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: openHandCloseLabel(context),
        ),
      ],
    );
  }

  Map<String, Object?> _localizedRows(
    BuildContext context,
    Map<String, Object?> rows,
  ) {
    return <String, Object?>{
      for (final entry in rows.entries)
        _metadataLabel(context, entry.key): entry.value,
    };
  }

  String _metadataLabel(BuildContext context, String key) {
    return switch (key) {
      'provider_config_id' => openHandLocalizedText(
        context,
        zh: 'Provider 配置',
        zhHant: 'Provider 配置',
        en: 'Provider config',
        fr: 'Configuration fournisseur',
        de: 'Provider-Konfiguration',
        ja: 'プロバイダー設定',
      ),
      'model_id' => openHandModelIdLabel(context),
      'dimensions' => openHandLocalizedText(
        context,
        zh: '向量维度',
        zhHant: '向量維度',
        en: 'Dimensions',
        fr: 'Dimensions',
        de: 'Dimensionen',
        ja: '次元数',
      ),
      'duration_ms' => openHandLocalizedText(
        context,
        zh: '耗时毫秒',
        zhHant: '耗時毫秒',
        en: 'Duration (ms)',
        fr: 'Durée (ms)',
        de: 'Dauer (ms)',
        ja: '所要時間 (ms)',
      ),
      'top_n' => openHandLocalizedText(
        context,
        zh: '召回 topN',
        zhHant: '召回 topN',
        en: 'Recall topN',
        fr: 'Rappel topN',
        de: 'Abruf topN',
        ja: '取得 topN',
      ),
      'top_k' => openHandLocalizedText(
        context,
        zh: '最终 topK',
        zhHant: '最終 topK',
        en: 'Final topK',
        fr: 'TopK final',
        de: 'Finales topK',
        ja: '最終 topK',
      ),
      'min_similarity' => openHandLocalizedText(
        context,
        zh: '最低相似度',
        zhHant: '最低相似度',
        en: 'Minimum similarity',
        fr: 'Similarité minimale',
        de: 'Minimale Ähnlichkeit',
        ja: '最小類似度',
      ),
      'filters' => openHandLocalizedText(
        context,
        zh: '过滤条件',
        zhHant: '篩選條件',
        en: 'Filters',
        fr: 'Filtres',
        de: 'Filter',
        ja: 'フィルター',
      ),
      'chunk_count' => openHandLocalizedText(
        context,
        zh: '追加分块数',
        zhHant: '追加分塊數',
        en: 'Appended chunks',
        fr: 'Fragments ajoutés',
        de: 'Angehängte Abschnitte',
        ja: '追加チャンク数',
      ),
      'token_estimate' => knowledgeEstimatedTokensLabel(context),
      'content_hash' => knowledgeContentHashLabel(context),
      'mode' => openHandModeLabel(context),
      'strategy' => openHandLocalizedText(
        context,
        zh: '策略',
        zhHant: '策略',
        en: 'Strategy',
        fr: 'Stratégie',
        de: 'Strategie',
        ja: '戦略',
      ),
      'candidate_count' => openHandLocalizedText(
        context,
        zh: '候选数',
        zhHant: '候選數',
        en: 'Candidates',
        fr: 'Candidats',
        de: 'Kandidaten',
        ja: '候補数',
      ),
      'rerank_input_count' => openHandLocalizedText(
        context,
        zh: '重排输入数',
        zhHant: '重排輸入數',
        en: 'Rerank input',
        fr: 'Entrées à reclasser',
        de: 'Reranking-Eingaben',
        ja: '再ランク入力数',
      ),
      'rerank_output_count' => openHandLocalizedText(
        context,
        zh: '重排输出数',
        zhHant: '重排輸出數',
        en: 'Rerank output',
        fr: 'Sorties reclassées',
        de: 'Reranking-Ausgaben',
        ja: '再ランク出力数',
      ),
      'kept_count' => openHandLocalizedText(
        context,
        zh: '保留数',
        zhHant: '保留數',
        en: 'Kept',
        fr: 'Conservés',
        de: 'Behalten',
        ja: '保持数',
      ),
      'discarded_count' => openHandLocalizedText(
        context,
        zh: '舍弃数',
        zhHant: '捨棄數',
        en: 'Discarded',
        fr: 'Ignorés',
        de: 'Verworfen',
        ja: '破棄数',
      ),
      _ => key,
    };
  }
}

class _KnowledgePromptAppendContextBox extends StatefulWidget {
  const _KnowledgePromptAppendContextBox({required this.metadata});

  final Map<String, Object?> metadata;

  @override
  State<_KnowledgePromptAppendContextBox> createState() =>
      _KnowledgePromptAppendContextBoxState();
}

class _KnowledgePromptAppendContextBoxState
    extends State<_KnowledgePromptAppendContextBox> {
  late String _fallback;
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _startResolve();
  }

  @override
  void didUpdateWidget(_KnowledgePromptAppendContextBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.metadata, widget.metadata)) {
      _startResolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final text = (snapshot.data ?? _fallback).trim();
        if (loading && text.isEmpty) {
          return KnowledgeDialogNotice(
            icon: Icons.hourglass_top_rounded,
            message: openHandLocalizedText(
              context,
              zh: '正在恢复本次追加给模型的知识库上下文。',
              zhHant: '正在恢復本次追加給模型的知識庫上下文。',
              en: 'Restoring the Knowledge Base context appended to the model.',
              fr: 'Restauration du contexte de la base de connaissances ajouté au modèle.',
              de: 'Der an das Modell angehängte Wissensdatenbank-Kontext wird wiederhergestellt.',
              ja: 'モデルに追加されたナレッジベースのコンテキストを復元しています。',
            ),
          );
        }
        return AnimatedSwitcher(
          duration: openHandMotionDuration(context, kOpenHandMotion180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KnowledgeDialogTextBox(
            key: ValueKey<String>(
              '${loading ? 'loading' : 'ready'}:${text.hashCode}',
            ),
            text: text,
            maxHeight: 300,
            emptyText: openHandLocalizedText(
              context,
              zh: '没有记录实际上下文；可打开命中分块查看详情。',
              zhHant: '沒有記錄實際上下文；可開啟命中分塊查看詳情。',
              en: 'No appended context was recorded. Open a hit chunk for details.',
              fr: 'Aucun contexte ajouté n’a été enregistré. Ouvrez un fragment trouvé pour les détails.',
              de: 'Es wurde kein angehängter Kontext aufgezeichnet. Öffnen Sie einen Trefferabschnitt für Details.',
              ja: '追加コンテキストは記録されていません。ヒットチャンクを開いて詳細を確認してください。',
            ),
          ),
        );
      },
    );
  }

  void _startResolve() {
    _fallback = KnowledgeMessageMetadata.promptAppendContent(widget.metadata);
    _future = _resolvePromptContext();
  }

  Future<String> _resolvePromptContext() async {
    final direct = KnowledgeMessageMetadata.rawPromptAppendContent(
      widget.metadata,
    );
    if (direct.isNotEmpty) return direct;
    final results = stringKeyedMapListFromValue(widget.metadata['results']);
    if (results.isEmpty) return _fallback;

    KnowledgeBaseController controller;
    try {
      controller = context.read<KnowledgeBaseController>();
    } catch (_) {
      return _fallback;
    }

    final sourceCache = <String, KnowledgeSource?>{};
    final chunkCache = <String, List<KnowledgeChunk>>{};
    final hydrated = <Map<String, Object?>>[];
    for (final hit in results) {
      final next = Map<String, Object?>.from(hit);
      final sourceId = _text(hit['source_id']);
      final chunkId = _text(hit['chunk_id']);
      if (sourceId.isNotEmpty) {
        if (!sourceCache.containsKey(sourceId)) {
          sourceCache[sourceId] = await controller.loadSource(sourceId);
        }
        final source = sourceCache[sourceId];
        if (source != null) {
          _putIfEmpty(next, 'source_title', source.title);
          _putIfEmpty(next, 'path', source.originalPath);
        }
      }
      if (_text(next['content']).isEmpty &&
          sourceId.isNotEmpty &&
          chunkId.isNotEmpty) {
        chunkCache[sourceId] ??= await controller.loadChunksForSource(sourceId);
        final chunk = _findChunk(chunkCache[sourceId]!, chunkId);
        if (chunk != null) {
          next['content'] = chunk.content;
          next['content_truncated'] = false;
          next['content_status'] = 'complete';
          _putIfEmpty(next, 'chunk_title', chunk.title);
          _putIfEmpty(next, 'heading_path', chunk.headingPath);
          _putIfEmpty(next, 'token_estimate', chunk.tokenEstimate);
          _putIfEmpty(
            next,
            'document_time',
            chunk.documentTime?.toUtc().toIso8601String(),
          );
        }
      }
      hydrated.add(next);
    }
    final resolved = KnowledgeMessageMetadata.promptAppendContentFromResults(
      hydrated,
      query: _text(widget.metadata['query']),
    ).trim();
    return resolved.isNotEmpty ? resolved : _fallback;
  }

  KnowledgeChunk? _findChunk(List<KnowledgeChunk> chunks, String chunkId) {
    for (final chunk in chunks) {
      if (chunk.id == chunkId) return chunk;
    }
    return null;
  }

  void _putIfEmpty(Map<String, Object?> target, String key, Object? value) {
    if (value == null || _text(value).isEmpty || _hasValue(target[key])) return;
    target[key] = value;
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit});

  final Map<String, Object?> hit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title =
        '${hit['title'] ?? hit['source_title'] ?? hit['chunk_id'] ?? ''}';
    final path = '${hit['path'] ?? ''}'.trim();
    final preview = '${hit['preview'] ?? ''}'.trim();
    final documentTimeLabel = _formatKnowledgeDateTime(hit['document_time']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.76),
        borderRadius: kOpenHandBorderRadius12,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showKnowledgeRetrievalHitDetailDialog(context, hit),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: kOpenHandBorderRadius12,
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.48),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.trim().isEmpty
                      ? openHandLocalizedText(
                          context,
                          zh: '知识库命中',
                          zhHant: '知識庫命中',
                          en: 'KB hit',
                          fr: 'Résultat KB',
                          de: 'KB-Treffer',
                          ja: 'KB ヒット',
                        )
                      : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                if (path.isNotEmpty) ...[
                  kOpenHandGap6,
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
                kOpenHandGap8,
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    KnowledgeDialogChip(
                      icon: Icons.trending_up_rounded,
                      label:
                          '${openHandLocalizedText(context, zh: '分数', zhHant: '分數', en: 'score', fr: 'score', de: 'Score', ja: 'スコア')} ${hit['score'] ?? '-'}',
                    ),
                    if (hit['rerank_score'] != null)
                      KnowledgeDialogChip(
                        icon: Icons.filter_alt_rounded,
                        label:
                            '${openHandLocalizedText(context, zh: '重排', zhHant: '重排', en: 'rerank', fr: 'rerank', de: 'Rerank', ja: '再ランク')} ${hit['rerank_score']}',
                      ),
                    if (hit['token_estimate'] != null)
                      KnowledgeDialogChip(
                        icon: Icons.data_usage_rounded,
                        label:
                            '${hit['token_estimate']} ${openHandLocalizedText(context, zh: 'token', zhHant: 'token', en: 'tokens', fr: 'tokens', de: 'Tokens', ja: 'トークン')}',
                      ),
                    if (documentTimeLabel.isNotEmpty)
                      KnowledgeDialogChip(
                        icon: Icons.event_rounded,
                        label: documentTimeLabel,
                      ),
                  ],
                ),
                if (preview.isNotEmpty) ...[
                  kOpenHandGap8,
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
    return FutureBuilder<_ResolvedKnowledgeHit>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return buildOpenHandAlertDialog(
            title: Text(_knowledgeRetriHitChunkDetailLabel(context)),
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
                label: openHandCloseLabel(context),
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
    final visibleDistribution = _showCorpus && _corpusDistribution != null
        ? _mergeCorpusDistribution(
            corpus: _corpusDistribution!,
            retrieval: widget.distribution,
          )
        : widget.distribution;
    final corpusCount = _corpusDistribution?.points.length ?? 0;
    return KnowledgeDialogSection(
      title: openHandLocalizedText(
        context,
        zh: '向量空间',
        zhHant: '向量空間',
        en: 'Vector Space',
        fr: 'Espace vectoriel',
        de: 'Vektorraum',
        ja: 'ベクトル空間',
      ),
      subtitle: _showCorpus
          ? openHandLocalizedText(
              context,
              zh: '天蓝色为全量采样，橙色为当前命中结果，红色为查询向量。',
              zhHant: '天藍色為全量採樣，橙色為目前命中結果，紅色為查詢向量。',
              en: 'Sky blue points are corpus samples; orange points are matched chunks; red is the query vector.',
              fr: 'Les points bleu ciel sont des échantillons du corpus ; les points orange sont les fragments trouvés ; le rouge est le vecteur de requête.',
              de: 'Hellblaue Punkte sind Korpus-Stichproben, orange Punkte sind Trefferabschnitte, Rot ist der Abfragevektor.',
              ja: '水色はコーパスのサンプル、オレンジはヒット結果、赤はクエリベクトルです。',
            )
          : openHandLocalizedText(
              context,
              zh: '红色为查询向量，橙色为当前命中结果。',
              zhHant: '紅色為查詢向量，橙色為目前命中結果。',
              en: 'Red is the query vector; orange points are matched chunks.',
              fr: 'Le rouge est le vecteur de requête ; les points orange sont les fragments trouvés.',
              de: 'Rot ist der Abfragevektor, orange Punkte sind Trefferabschnitte.',
              ja: '赤はクエリベクトル、オレンジは現在のヒット結果です。',
            ),
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
                    ? openHandLocalizedText(
                        context,
                        zh: '隐藏全量',
                        zhHant: '隱藏全量',
                        en: 'Hide Corpus',
                        fr: 'Masquer le corpus',
                        de: 'Korpus ausblenden',
                        ja: 'コーパスを非表示',
                      )
                    : openHandLocalizedText(
                        context,
                        zh: '叠加全量',
                        zhHant: '疊加全量',
                        en: 'Overlay Corpus',
                        fr: 'Superposer le corpus',
                        de: 'Korpus überlagern',
                        ja: 'コーパスを重ねる',
                      ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: openHandMotionDuration(context, kOpenHandMotion220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _buildCorpusStatus(context, corpusCount),
          ),
          kOpenHandGap10,
          KnowledgeVectorDistributionView(
            distribution: visibleDistribution,
            height: 380,
            compact: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCorpusStatus(BuildContext context, int corpusCount) {
    if (_loadingCorpus && _showCorpus) {
      return Padding(
        key: const ValueKey('corpus-loading'),
        padding: const EdgeInsets.only(top: 10),
        child: KnowledgeDialogNotice(
          icon: Icons.hourglass_top_rounded,
          message: openHandLocalizedText(
            context,
            zh: '正在按需采样并叠加全量向量。',
            zhHant: '正在按需取樣並疊加全量向量。',
            en: 'Sampling and overlaying corpus vectors on demand.',
            fr: 'Échantillonnage et superposition des vecteurs du corpus.',
            de: 'Korpusvektoren werden bei Bedarf abgetastet und überlagert.',
            ja: '必要に応じてコーパスベクトルをサンプリングして重ねています。',
          ),
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
              '${openHandLocalizedText(context, zh: '全量向量加载失败：', zhHant: '全量向量載入失敗：', en: 'Failed to load corpus vectors: ', fr: 'Échec du chargement des vecteurs du corpus : ', de: 'Korpusvektoren konnten nicht geladen werden: ', ja: 'コーパスベクトルの読み込みに失敗しました: ')}${_corpusError!}',
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
              ? openHandLocalizedText(
                  context,
                  zh: '已叠加 $corpusCount 个全量采样点；数据量较大时会采样展示以保持流畅。',
                  zhHant: '已疊加 $corpusCount 個全量取樣點；資料量較大時會取樣展示以保持流暢。',
                  en: 'Overlaying $corpusCount sampled corpus points; large collections are sampled to keep the view responsive.',
                  fr: '$corpusCount points échantillonnés du corpus sont superposés ; les grands ensembles sont échantillonnés pour rester fluides.',
                  de: '$corpusCount Korpus-Stichprobenpunkte werden überlagert; große Sammlungen werden für eine flüssige Ansicht abgetastet.',
                  ja: '$corpusCount 個のコーパスサンプル点を重ねています。大きなコレクションは表示を滑らかに保つためサンプリングされます。',
                )
              : openHandLocalizedText(
                  context,
                  zh: '已叠加 $corpusCount 个全量向量点。',
                  zhHant: '已疊加 $corpusCount 個全量向量點。',
                  en: 'Overlaying $corpusCount corpus points.',
                  fr: '$corpusCount points du corpus sont superposés.',
                  de: '$corpusCount Korpuspunkte werden überlagert.',
                  ja: '$corpusCount 個のコーパスポイントを重ねています。',
                ),
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
    final highlightedIds = stringListFromValue(
      retrieval.points
          .where((point) => point.kind != KnowledgeVectorPointKind.corpus)
          .map((point) => point.id)
          .toList(growable: false),
    ).toSet();
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
    final tags = stringListFromValue(hit['tags']);
    return buildOpenHandAlertDialog(
      title: Text(_knowledgeRetriHitChunkDetailLabel(context)),
      content: buildOpenHandDialogConstrainedContent(
        width: 820,
        maxHeight: MediaQuery.sizeOf(context).height * 0.80,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KnowledgeDialogNotice(
                icon: Icons.info_outline_rounded,
                message: openHandLocalizedText(
                  context,
                  zh: '未能从本地知识库恢复完整 chunk，下面展示消息元数据中保留的命中信息。',
                  zhHant: '未能從本地知識庫恢復完整 chunk，下面展示訊息元資料中保留的命中資訊。',
                  en: 'The full chunk could not be restored locally. Showing hit metadata saved with this message.',
                  fr: 'Le chunk complet n’a pas pu être restauré localement. Les métadonnées conservées avec ce message sont affichées.',
                  de: 'Der vollständige Chunk konnte lokal nicht wiederhergestellt werden. Angezeigt werden die in dieser Nachricht gespeicherten Treffer-Metadaten.',
                  ja: 'ローカルのナレッジベースから完全なチャンクを復元できませんでした。このメッセージに保存されたヒット情報を表示します。',
                ),
                tone: KnowledgeDialogNoticeTone.warning,
              ),
              kOpenHandGap12,
              KnowledgeDialogSection(
                title: knowledgeOverviewLabel(context),
                icon: Icons.article_outlined,
                child: KnowledgeDialogKeyValueList(
                  labelWidth: knowledgeDetailLabelWidth(isZh),
                  rows: {
                    knowledgeChunkIdLabel(context): chunkId,
                    knowledgeSourceIdLabel(context): hit['source_id'],
                    knowledgeTitleLabel(context): title,
                    openHandPathLabel(context): hit['path'],
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: openHandLocalizedText(
                  context,
                  zh: '检索数据',
                  zhHant: '檢索資料',
                  en: 'Retrieval Data',
                  fr: 'Données de recherche',
                  de: 'Abrufdaten',
                  ja: '検索データ',
                ),
                icon: Icons.manage_search_rounded,
                child: KnowledgeDialogKeyValueList(
                  labelWidth: knowledgeDetailLabelWidth(isZh),
                  rows: {
                    if (_hasValue(hit['score']))
                      knowledgeRecallScoreLabel(context): hit['score'],
                    if (_hasValue(hit['rerank_score']))
                      knowledgeRerankScoreLabel(context): hit['rerank_score'],
                    if (_hasValue(hit['final_score']))
                      knowledgeFinalScoreLabel(context): hit['final_score'],
                    if (_hasValue(hit['token_estimate']))
                      knowledgeEstimatedTokensLabel(context):
                          hit['token_estimate'],
                    if (_hasValue(hit['time_field']))
                      knowledgeTimeFieldLabel(context): hit['time_field'],
                    if (_hasValue(hit['document_time']))
                      knowledgeDocumentTimeLabel(context):
                          _formatKnowledgeDateTime(hit['document_time']),
                    if (_hasValue(hit['updated_at']))
                      knowledgeUpdatedAtLabel(context):
                          _formatKnowledgeDateTime(hit['updated_at']),
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: knowledgeTagsLabel(context),
                icon: Icons.sell_outlined,
                child: tags.isEmpty
                    ? KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: openHandLocalizedText(
                          context,
                          zh: '消息元数据中没有标签。',
                          zhHant: '訊息元資料中沒有標籤。',
                          en: 'No tags in message metadata.',
                          fr: 'Aucune étiquette dans les métadonnées.',
                          de: 'Keine Tags in den Nachrichten-Metadaten.',
                          ja: 'メッセージのメタデータにタグはありません。',
                        ),
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
                title: openHandLocalizedText(
                  context,
                  zh: '命中预览',
                  zhHant: '命中預覽',
                  en: 'Hit Preview',
                  fr: 'Aperçu du résultat',
                  de: 'Treffervorschau',
                  ja: 'ヒットプレビュー',
                ),
                icon: Icons.notes_rounded,
                child: KnowledgeDialogTextBox(
                  text: preview,
                  emptyText: openHandLocalizedText(
                    context,
                    zh: '消息元数据中没有命中预览。',
                    zhHant: '訊息元資料中沒有命中預覽。',
                    en: 'No hit preview in message metadata.',
                    fr: 'Aucun aperçu du résultat dans les métadonnées.',
                    de: 'Keine Treffervorschau in den Nachrichten-Metadaten.',
                    ja: 'メッセージのメタデータにヒットプレビューはありません。',
                  ),
                ),
              ),
              KnowledgeDialogSection(
                title: openHandLocalizedText(
                  context,
                  zh: '原始命中元数据',
                  zhHant: '原始命中元資料',
                  en: 'Raw Hit Metadata',
                  fr: 'Métadonnées brutes du résultat',
                  de: 'Rohe Treffer-Metadaten',
                  ja: '生ヒットメタデータ',
                ),
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
              knowledgeChunkIdCopiedMessage(context),
            ),
            icon: Icons.fingerprint_rounded,
            label: knowledgeCopyIdLabel(context),
          ),
        OpenHandDialogActionButton.secondary(
          onPressed: preview.isEmpty
              ? null
              : () => _copyText(
                  context,
                  preview,
                  openHandLocalizedText(
                    context,
                    zh: '已复制命中预览。',
                    zhHant: '已複製命中預覽。',
                    en: 'Hit preview copied.',
                    fr: 'Aperçu du résultat copié.',
                    de: 'Treffervorschau kopiert.',
                    ja: 'ヒットプレビューをコピーしました。',
                  ),
                ),
          icon: Icons.copy_all_rounded,
          label: openHandLocalizedText(
            context,
            zh: '复制预览',
            zhHant: '複製預覽',
            en: 'Copy Preview',
            fr: 'Copier l’aperçu',
            de: 'Vorschau kopieren',
            ja: 'プレビューをコピー',
          ),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: openHandCloseLabel(context),
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
  final parsed = dateTimeFromValue(
    value,
    numericTimestampMode: DateTimeNumericTimestampMode.secondsOrMilliseconds,
    requirePositiveTimestamp: true,
  );
  if (parsed == null) return _hasValue(value) ? _text(value) : '';
  return formatYearMonthDayHmsLocal(parsed);
}

Future<void> _copyText(
  BuildContext context,
  String text,
  String message,
) async {
  await copyOpenHandTextToClipboard(
    logTag: 'knowledge_base',
    context: context,
    text: text,
    successMessage: message,
    logAction: '复制检索详情文本',
  );
}

// 本文件内复用文案。

String _knowledgeRetriHitChunkDetailLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '命中分块详情',
    zhHant: '命中分塊詳情',
    en: 'Hit Chunk Detail',
    fr: 'Détail du fragment trouvé',
    de: 'Trefferabschnitt-Details',
    ja: 'ヒットチャンク詳細',
  );
}
