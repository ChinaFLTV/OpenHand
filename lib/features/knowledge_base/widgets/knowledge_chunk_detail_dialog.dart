import 'package:flutter/material.dart';

import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
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
      title: Text(
        openHandLocalizedText(
          context,
          zh: '分块详情',
          zhHant: '分塊詳情',
          en: 'Chunk Detail',
          fr: 'Détail du fragment',
          de: 'Abschnittsdetails',
          ja: 'チャンク詳細',
        ),
      ),
      content: buildOpenHandDialogConstrainedContent(
        width: 820,
        maxHeight: MediaQuery.sizeOf(context).height * 0.80,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (retrievalHit != null)
                KnowledgeDialogSection(
                  title: openHandLocalizedText(
                    context,
                    zh: '检索命中',
                    zhHant: '檢索命中',
                    en: 'Retrieval Hit',
                    fr: 'Résultat de recherche',
                    de: 'Suchtreffer',
                    ja: '検索ヒット',
                  ),
                  icon: Icons.manage_search_rounded,
                  child: KnowledgeDialogKeyValueList(
                    labelWidth: knowledgeDetailLabelWidth(isZh),
                    rows: _retrievalRows(context, retrievalHit!),
                  ),
                ),
              KnowledgeDialogSection(
                title: knowledgeOverviewLabel(context),
                icon: Icons.article_outlined,
                child: KnowledgeDialogKeyValueList(
                  labelWidth: knowledgeDetailLabelWidth(isZh),
                  rows: {
                    knowledgeChunkIdLabel(context): chunk.id,
                    knowledgeSourceIdLabel(context): source.id,
                    openHandLocalizedText(
                      context,
                      zh: '来源标题',
                      zhHant: '來源標題',
                      en: 'Source title',
                      fr: 'Titre de la source',
                      de: 'Quellentitel',
                      ja: 'ソースタイトル',
                    ): source.title,
                    openHandLocalizedText(
                      context,
                      zh: '序号',
                      zhHant: '序號',
                      en: 'Index',
                      fr: 'Index',
                      de: 'Index',
                      ja: 'インデックス',
                    ): chunk.chunkIndex,
                    if (_notBlank(chunk.parentChunkId))
                      openHandLocalizedText(
                        context,
                        zh: '父分块 ID',
                        zhHant: '父分塊 ID',
                        en: 'Parent chunk ID',
                        fr: 'ID du fragment parent',
                        de: 'Übergeordnete Abschnitts-ID',
                        ja: '親チャンク ID',
                      ): chunk.parentChunkId,
                    knowledgeTitleLabel(context): chunk.title,
                    openHandLocalizedText(
                      context,
                      zh: '层级路径',
                      zhHant: '標題路徑',
                      en: 'Heading path',
                      fr: 'Chemin des titres',
                      de: 'Überschriftenpfad',
                      ja: '見出しパス',
                    ): chunk.headingPath,
                    knowledgeContentHashLabel(context): chunk.contentHash,
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: openHandLocalizedText(
                  context,
                  zh: '统计与定位',
                  zhHant: '統計與位置',
                  en: 'Stats & Location',
                  fr: 'Statistiques et emplacement',
                  de: 'Statistik und Position',
                  ja: '統計と位置',
                ),
                icon: Icons.data_usage_rounded,
                child: KnowledgeDialogKeyValueList(
                  labelWidth: knowledgeDetailLabelWidth(isZh),
                  rows: {
                    openHandLocalizedText(
                      context,
                      zh: '字符数',
                      zhHant: '字元數',
                      en: 'Characters',
                      fr: 'Caractères',
                      de: 'Zeichen',
                      ja: '文字数',
                    ): chunk.charCount,
                    knowledgeEstimatedTokensLabel(context): chunk.tokenEstimate,
                    if (chunk.startOffset != null)
                      openHandLocalizedText(
                        context,
                        zh: '起始偏移',
                        zhHant: '起始偏移',
                        en: 'Start offset',
                        fr: 'Décalage début',
                        de: 'Startposition',
                        ja: '開始オフセット',
                      ): chunk.startOffset,
                    if (chunk.endOffset != null)
                      openHandLocalizedText(
                        context,
                        zh: '结束偏移',
                        zhHant: '結束偏移',
                        en: 'End offset',
                        fr: 'Décalage fin',
                        de: 'Endposition',
                        ja: '終了オフセット',
                      ): chunk.endOffset,
                    if (chunk.pageNumber != null)
                      openHandLocalizedText(
                        context,
                        zh: '页码',
                        zhHant: '頁碼',
                        en: 'Page',
                        fr: 'Page',
                        de: 'Seite',
                        ja: 'ページ',
                      ): chunk.pageNumber,
                    knowledgeDocumentTimeLabel(context): _date(
                      chunk.documentTime,
                    ),
                    openHandLocalizedText(
                      context,
                      zh: '创建时间',
                      zhHant: '建立時間',
                      en: 'Created at',
                      fr: 'Créé le',
                      de: 'Erstellt am',
                      ja: '作成日時',
                    ): _date(
                      chunk.createdAt,
                    ),
                    knowledgeUpdatedAtLabel(context): _date(chunk.updatedAt),
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: knowledgeTagsLabel(context),
                icon: Icons.sell_outlined,
                child: chunk.tags.isEmpty
                    ? KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: openHandLocalizedText(
                          context,
                          zh: '该分块没有标签。',
                          zhHant: '此分塊沒有標籤。',
                          en: 'No tags on this chunk.',
                          fr: 'Aucune étiquette pour ce fragment.',
                          de: 'Dieser Abschnitt hat keine Tags.',
                          ja: 'このチャンクにはタグがありません。',
                        ),
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
                title: openHandLocalizedText(
                  context,
                  zh: '元数据',
                  zhHant: '元資料',
                  en: 'Metadata',
                  fr: 'Métadonnées',
                  de: 'Metadaten',
                  ja: 'メタデータ',
                ),
                icon: Icons.account_tree_outlined,
                child: metadata.isEmpty
                    ? KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: openHandLocalizedText(
                          context,
                          zh: '该分块没有额外元数据。',
                          zhHant: '此分塊沒有額外元資料。',
                          en: 'No additional metadata.',
                          fr: 'Aucune métadonnée supplémentaire.',
                          de: 'Keine zusätzlichen Metadaten.',
                          ja: '追加メタデータはありません。',
                        ),
                      )
                    : KnowledgeDialogJsonBox(value: metadata, maxHeight: 260),
              ),
              KnowledgeDialogSection(
                title: openHandLocalizedText(
                  context,
                  zh: '完整内容',
                  zhHant: '完整內容',
                  en: 'Full Content',
                  fr: 'Contenu complet',
                  de: 'Vollständiger Inhalt',
                  ja: '全文',
                ),
                icon: Icons.notes_rounded,
                margin: EdgeInsets.zero,
                child: KnowledgeDialogTextBox(
                  text: chunk.content,
                  maxHeight: 360,
                  emptyText: openHandLocalizedText(
                    context,
                    zh: '分块内容为空。',
                    zhHant: '分塊內容為空。',
                    en: 'Chunk content is empty.',
                    fr: 'Le contenu du fragment est vide.',
                    de: 'Abschnittsinhalt ist leer.',
                    ja: 'チャンク内容は空です。',
                  ),
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
            knowledgeChunkIdCopiedMessage(context),
          ),
          icon: Icons.fingerprint_rounded,
          label: knowledgeCopyIdLabel(context),
        ),
        OpenHandDialogActionButton.secondary(
          onPressed: () => _copyText(
            context,
            chunk.content,
            openHandLocalizedText(
              context,
              zh: '已复制分块内容。',
              zhHant: '已複製分塊內容。',
              en: 'Chunk content copied.',
              fr: 'Contenu du fragment copié.',
              de: 'Abschnittsinhalt kopiert.',
              ja: 'チャンク内容をコピーしました。',
            ),
          ),
          icon: Icons.copy_all_rounded,
          label: knowledgeCopyContentLabel(context),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: openHandCloseLabel(context),
        ),
      ],
    );
  }

  Map<String, Object?> _retrievalRows(
    BuildContext context,
    Map<String, Object?> hit,
  ) {
    return {
      if (_hasValue(hit['score']))
        knowledgeRecallScoreLabel(context): hit['score'],
      if (_hasValue(hit['rerank_score']))
        knowledgeRerankScoreLabel(context): hit['rerank_score'],
      if (_hasValue(hit['final_score']))
        knowledgeFinalScoreLabel(context): hit['final_score'],
      if (_hasValue(hit['time_field']))
        knowledgeTimeFieldLabel(context): hit['time_field'],
      if (_hasValue(hit['path']))
        openHandLocalizedText(
          context,
          zh: '来源路径',
          zhHant: '來源路徑',
          en: 'Path',
          fr: 'Chemin',
          de: 'Pfad',
          ja: 'パス',
        ): hit['path'],
      if (_hasValue(hit['document_time']))
        knowledgeDocumentTimeLabel(context): hit['document_time'],
      if (_hasValue(hit['updated_at']))
        knowledgeUpdatedAtLabel(context): hit['updated_at'],
    };
  }

  String _date(DateTime? value) {
    return value == null ? '-' : formatYearMonthDayHmsLocal(value);
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
    await copyOpenHandTextToClipboard(
      logTag: 'knowledge_base',
      context: context,
      text: text,
      successMessage: message,
      logAction: '复制分块详情文本',
    );
  }
}
