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

String _kbChunkText(
  BuildContext context, {
  required String zh,
  required String en,
  String? zhHans,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  return openHandLocalizedText(
    context,
    zh: zh,
    en: en,
    zhHans: zhHans,
    zhHant: zhHant,
    fr: fr,
    de: de,
    ja: ja,
  );
}

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
        _kbChunkText(
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
                  title: _kbChunkText(
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
                    labelWidth: isZh ? 112 : 132,
                    rows: _retrievalRows(context, retrievalHit!),
                  ),
                ),
              KnowledgeDialogSection(
                title: _kbChunkText(
                  context,
                  zh: '基础信息',
                  zhHant: '基本資訊',
                  en: 'Overview',
                  fr: 'Vue d’ensemble',
                  de: 'Übersicht',
                  ja: '概要',
                ),
                icon: Icons.article_outlined,
                child: KnowledgeDialogKeyValueList(
                  labelWidth: isZh ? 112 : 132,
                  rows: {
                    _kbChunkText(
                      context,
                      zh: '分块 ID',
                      zhHant: '分塊 ID',
                      en: 'Chunk ID',
                      fr: 'ID du fragment',
                      de: 'Abschnitts-ID',
                      ja: 'チャンク ID',
                    ): chunk.id,
                    _kbChunkText(
                      context,
                      zh: '来源 ID',
                      zhHant: '來源 ID',
                      en: 'Source ID',
                      fr: 'ID de la source',
                      de: 'Quellen-ID',
                      ja: 'ソース ID',
                    ): source.id,
                    _kbChunkText(
                      context,
                      zh: '来源标题',
                      zhHant: '來源標題',
                      en: 'Source title',
                      fr: 'Titre de la source',
                      de: 'Quellentitel',
                      ja: 'ソースタイトル',
                    ): source.title,
                    _kbChunkText(
                      context,
                      zh: '序号',
                      zhHant: '序號',
                      en: 'Index',
                      fr: 'Index',
                      de: 'Index',
                      ja: 'インデックス',
                    ): chunk.chunkIndex,
                    if (_notBlank(chunk.parentChunkId))
                      _kbChunkText(
                        context,
                        zh: '父分块 ID',
                        zhHant: '父分塊 ID',
                        en: 'Parent chunk ID',
                        fr: 'ID du fragment parent',
                        de: 'Übergeordnete Abschnitts-ID',
                        ja: '親チャンク ID',
                      ): chunk.parentChunkId,
                    _kbChunkText(
                      context,
                      zh: '标题',
                      zhHant: '標題',
                      en: 'Title',
                      fr: 'Titre',
                      de: 'Titel',
                      ja: 'タイトル',
                    ): chunk.title,
                    _kbChunkText(
                      context,
                      zh: '层级路径',
                      zhHant: '標題路徑',
                      en: 'Heading path',
                      fr: 'Chemin des titres',
                      de: 'Überschriftenpfad',
                      ja: '見出しパス',
                    ): chunk.headingPath,
                    _kbChunkText(
                      context,
                      zh: '内容哈希',
                      zhHant: '內容雜湊',
                      en: 'Content hash',
                      fr: 'Hash du contenu',
                      de: 'Inhalts-Hash',
                      ja: 'コンテンツハッシュ',
                    ): chunk.contentHash,
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: _kbChunkText(
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
                  labelWidth: isZh ? 112 : 132,
                  rows: {
                    _kbChunkText(
                      context,
                      zh: '字符数',
                      zhHant: '字元數',
                      en: 'Characters',
                      fr: 'Caractères',
                      de: 'Zeichen',
                      ja: '文字数',
                    ): chunk.charCount,
                    _kbChunkText(
                      context,
                      zh: '预估 token',
                      zhHant: '預估 token',
                      en: 'Estimated tokens',
                      fr: 'Tokens estimés',
                      de: 'Geschätzte Tokens',
                      ja: '推定トークン',
                    ): chunk.tokenEstimate,
                    if (chunk.startOffset != null)
                      _kbChunkText(
                        context,
                        zh: '起始偏移',
                        zhHant: '起始偏移',
                        en: 'Start offset',
                        fr: 'Décalage début',
                        de: 'Startposition',
                        ja: '開始オフセット',
                      ): chunk.startOffset,
                    if (chunk.endOffset != null)
                      _kbChunkText(
                        context,
                        zh: '结束偏移',
                        zhHant: '結束偏移',
                        en: 'End offset',
                        fr: 'Décalage fin',
                        de: 'Endposition',
                        ja: '終了オフセット',
                      ): chunk.endOffset,
                    if (chunk.pageNumber != null)
                      _kbChunkText(
                        context,
                        zh: '页码',
                        zhHant: '頁碼',
                        en: 'Page',
                        fr: 'Page',
                        de: 'Seite',
                        ja: 'ページ',
                      ): chunk.pageNumber,
                    _kbChunkText(
                      context,
                      zh: '文档时间',
                      zhHant: '文件時間',
                      en: 'Document time',
                      fr: 'Date du document',
                      de: 'Dokumentzeit',
                      ja: 'ドキュメント日時',
                    ): _date(
                      chunk.documentTime,
                    ),
                    _kbChunkText(
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
                    _kbChunkText(
                      context,
                      zh: '更新时间',
                      zhHant: '更新時間',
                      en: 'Updated at',
                      fr: 'Mis à jour le',
                      de: 'Aktualisiert am',
                      ja: '更新日時',
                    ): _date(
                      chunk.updatedAt,
                    ),
                  },
                ),
              ),
              KnowledgeDialogSection(
                title: _kbChunkText(
                  context,
                  zh: '标签',
                  zhHant: '標籤',
                  en: 'Tags',
                  fr: 'Étiquettes',
                  de: 'Tags',
                  ja: 'タグ',
                ),
                icon: Icons.sell_outlined,
                child: chunk.tags.isEmpty
                    ? KnowledgeDialogNotice(
                        icon: Icons.info_outline_rounded,
                        message: _kbChunkText(
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
                title: _kbChunkText(
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
                        message: _kbChunkText(
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
                title: _kbChunkText(
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
                  emptyText: _kbChunkText(
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
            _kbChunkText(
              context,
              zh: '已复制分块 ID。',
              zhHant: '已複製分塊 ID。',
              en: 'Chunk ID copied.',
              fr: 'ID du fragment copié.',
              de: 'Abschnitts-ID kopiert.',
              ja: 'チャンク ID をコピーしました。',
            ),
          ),
          icon: Icons.fingerprint_rounded,
          label: _kbChunkText(
            context,
            zh: '复制 ID',
            zhHant: '複製 ID',
            en: 'Copy ID',
            fr: 'Copier l’ID',
            de: 'ID kopieren',
            ja: 'ID をコピー',
          ),
        ),
        OpenHandDialogActionButton.secondary(
          onPressed: () => _copyText(
            context,
            chunk.content,
            _kbChunkText(
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
          label: _kbChunkText(
            context,
            zh: '复制内容',
            zhHant: '複製內容',
            en: 'Copy Content',
            fr: 'Copier le contenu',
            de: 'Inhalt kopieren',
            ja: '内容をコピー',
          ),
        ),
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).pop(),
          label: _kbChunkText(
            context,
            zh: '关闭',
            zhHant: '關閉',
            en: 'Close',
            fr: 'Fermer',
            de: 'Schließen',
            ja: '閉じる',
          ),
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
        _kbChunkText(
          context,
          zh: '召回分数',
          zhHant: '召回分數',
          en: 'Score',
          fr: 'Score',
          de: 'Score',
          ja: 'スコア',
        ): hit['score'],
      if (_hasValue(hit['rerank_score']))
        _kbChunkText(
          context,
          zh: '重排分数',
          zhHant: '重排分數',
          en: 'Rerank score',
          fr: 'Score de reclassement',
          de: 'Rerank-Score',
          ja: '再ランクスコア',
        ): hit['rerank_score'],
      if (_hasValue(hit['final_score']))
        _kbChunkText(
          context,
          zh: '最终分数',
          zhHant: '最終分數',
          en: 'Final score',
          fr: 'Score final',
          de: 'Endscore',
          ja: '最終スコア',
        ): hit['final_score'],
      if (_hasValue(hit['time_field']))
        _kbChunkText(
          context,
          zh: '时间字段',
          zhHant: '時間欄位',
          en: 'Time field',
          fr: 'Champ temporel',
          de: 'Zeitfeld',
          ja: '時間フィールド',
        ): hit['time_field'],
      if (_hasValue(hit['path']))
        _kbChunkText(
          context,
          zh: '来源路径',
          zhHant: '來源路徑',
          en: 'Path',
          fr: 'Chemin',
          de: 'Pfad',
          ja: 'パス',
        ): hit['path'],
      if (_hasValue(hit['document_time']))
        _kbChunkText(
          context,
          zh: '文档时间',
          zhHant: '文件時間',
          en: 'Document time',
          fr: 'Date du document',
          de: 'Dokumentzeit',
          ja: 'ドキュメント日時',
        ): hit['document_time'],
      if (_hasValue(hit['updated_at']))
        _kbChunkText(
          context,
          zh: '更新时间',
          zhHant: '更新時間',
          en: 'Updated at',
          fr: 'Mis à jour le',
          de: 'Aktualisiert am',
          ja: '更新日時',
        ): hit['updated_at'],
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
