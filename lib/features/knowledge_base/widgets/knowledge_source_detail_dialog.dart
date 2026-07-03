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
import 'knowledge_chunk_detail_dialog.dart';
import 'knowledge_dialog_widgets.dart';

String _kbDetailText(
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
          title: Text(
            _kbDetailText(
              context,
              zh: '知识库来源详情',
              zhHant: '知識庫來源詳情',
              en: 'Knowledge Source Detail',
              fr: 'Détail de la source',
              de: 'Wissensquellendetail',
              ja: 'ナレッジソース詳細',
            ),
          ),
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
                    message: _kbDetailText(
                      context,
                      zh: '来源不存在。',
                      zhHant: '來源不存在。',
                      en: 'Source not found.',
                      fr: 'Source introuvable.',
                      de: 'Quelle nicht gefunden.',
                      ja: 'ソースが見つかりません。',
                    ),
                  )
                : _SourceDetailBody(source: source, chunks: chunks),
          ),
          actions: [
            if (source != null)
              OpenHandDialogActionButton.secondary(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: source.originalPath)),
                icon: Icons.copy_rounded,
                label: _kbDetailText(
                  context,
                  zh: '复制路径',
                  zhHant: '複製路徑',
                  en: 'Copy Path',
                  fr: 'Copier le chemin',
                  de: 'Pfad kopieren',
                  ja: 'パスをコピー',
                ),
              ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(context).pop(),
              label: _kbDetailText(
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KnowledgeDialogSection(
            title: _kbDetailText(
              context,
              zh: '来源信息',
              zhHant: '來源資訊',
              en: 'Source',
              fr: 'Source',
              de: 'Quelle',
              ja: 'ソース',
            ),
            icon: Icons.description_outlined,
            child: KnowledgeDialogKeyValueList(
              labelWidth: openHandIsChineseLocale(context) ? 120 : 128,
              rows: {
                _kbDetailText(
                  context,
                  zh: '标题',
                  zhHant: '標題',
                  en: 'Title',
                  fr: 'Titre',
                  de: 'Titel',
                  ja: 'タイトル',
                ): source.title,
                _kbDetailText(
                  context,
                  zh: '类型',
                  zhHant: '類型',
                  en: 'Kind',
                  fr: 'Type',
                  de: 'Art',
                  ja: '種類',
                ): _localizedKind(
                  source.kind,
                  context,
                ),
                _kbDetailText(
                  context,
                  zh: '状态',
                  zhHant: '狀態',
                  en: 'Status',
                  fr: 'État',
                  de: 'Status',
                  ja: '状態',
                ): _localizedStatus(
                  source.status,
                  context,
                ),
                _kbDetailText(
                  context,
                  zh: '原始路径',
                  zhHant: '原始路徑',
                  en: 'Original path',
                  fr: 'Chemin d’origine',
                  de: 'Ursprungspfad',
                  ja: '元のパス',
                ): source.originalPath,
                _kbDetailText(
                  context,
                  zh: '存储路径',
                  zhHant: '儲存路徑',
                  en: 'Stored path',
                  fr: 'Chemin stocké',
                  de: 'Gespeicherter Pfad',
                  ja: '保存パス',
                ): source.storedPath,
                _kbDetailText(
                  context,
                  zh: '文档时间',
                  zhHant: '文件時間',
                  en: 'Document time',
                  fr: 'Date du document',
                  de: 'Dokumentzeit',
                  ja: 'ドキュメント日時',
                ): _date(
                  source.documentTime,
                ),
                _kbDetailText(
                  context,
                  zh: '导入时间',
                  zhHant: '匯入時間',
                  en: 'Imported at',
                  fr: 'Importé le',
                  de: 'Importiert am',
                  ja: 'インポート日時',
                ): _date(
                  source.importedAt,
                ),
                _kbDetailText(
                  context,
                  zh: '索引时间',
                  zhHant: '索引時間',
                  en: 'Indexed at',
                  fr: 'Indexé le',
                  de: 'Indexiert am',
                  ja: 'インデックス日時',
                ): _date(
                  source.indexedAt,
                ),
                if (source.errorMessage.trim().isNotEmpty)
                  _kbDetailText(
                    context,
                    zh: '错误',
                    zhHant: '錯誤',
                    en: 'Error',
                    fr: 'Erreur',
                    de: 'Fehler',
                    ja: 'エラー',
                  ): source.errorMessage,
              },
            ),
          ),
          KnowledgeDialogSection(
            title: _kbDetailText(
              context,
              zh: '分块 (${chunks.length})',
              zhHant: '分塊 (${chunks.length})',
              en: 'Chunks (${chunks.length})',
              fr: 'Fragments (${chunks.length})',
              de: 'Abschnitte (${chunks.length})',
              ja: 'チャンク (${chunks.length})',
            ),
            icon: Icons.article_outlined,
            margin: EdgeInsets.zero,
            child: chunks.isEmpty
                ? KnowledgeDialogNotice(
                    icon: Icons.info_outline_rounded,
                    message: _kbDetailText(
                      context,
                      zh: '暂无 chunk。',
                      zhHant: '暫無 chunk。',
                      en: 'No chunks yet.',
                      fr: 'Aucun fragment pour le moment.',
                      de: 'Noch keine Abschnitte.',
                      ja: 'チャンクはまだありません。',
                    ),
                  )
                : Column(
                    children: [
                      for (final chunk in chunks)
                        _ChunkTile(source: source, chunk: chunk),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _localizedKind(String kind, BuildContext context) {
    return switch (kind) {
      'markdown' => _kbDetailText(
        context,
        zh: 'Markdown 文档',
        zhHant: 'Markdown 文件',
        en: 'Markdown',
        fr: 'Markdown',
        de: 'Markdown',
        ja: 'Markdown',
      ),
      'text' => _kbDetailText(
        context,
        zh: '文本',
        zhHant: '文字',
        en: 'Text',
        fr: 'Texte',
        de: 'Text',
        ja: 'テキスト',
      ),
      'code' => _kbDetailText(
        context,
        zh: '代码',
        zhHant: '程式碼',
        en: 'Code',
        fr: 'Code',
        de: 'Code',
        ja: 'コード',
      ),
      'pdf' => 'PDF',
      'html' => _kbDetailText(
        context,
        zh: '网页 HTML',
        zhHant: '網頁 HTML',
        en: 'HTML',
        fr: 'HTML',
        de: 'HTML',
        ja: 'HTML',
      ),
      'docx' => _kbDetailText(
        context,
        zh: 'Word 文档',
        zhHant: 'Word 文件',
        en: 'Word document',
        fr: 'Document Word',
        de: 'Word-Dokument',
        ja: 'Word ドキュメント',
      ),
      'spreadsheet' => _kbDetailText(
        context,
        zh: '电子表格',
        zhHant: '試算表',
        en: 'Spreadsheet',
        fr: 'Feuille de calcul',
        de: 'Tabelle',
        ja: 'スプレッドシート',
      ),
      'presentation' => _kbDetailText(
        context,
        zh: '演示文稿',
        zhHant: '簡報',
        en: 'Presentation',
        fr: 'Présentation',
        de: 'Präsentation',
        ja: 'プレゼンテーション',
      ),
      'table' => _kbDetailText(
        context,
        zh: '表格数据',
        zhHant: '表格資料',
        en: 'Table data',
        fr: 'Données tabulaires',
        de: 'Tabellendaten',
        ja: '表データ',
      ),
      'structured' => _kbDetailText(
        context,
        zh: '结构化数据',
        zhHant: '結構化資料',
        en: 'Structured data',
        fr: 'Données structurées',
        de: 'Strukturierte Daten',
        ja: '構造化データ',
      ),
      'note' => _kbDetailText(
        context,
        zh: '笔记',
        zhHant: '筆記',
        en: 'Note',
        fr: 'Note',
        de: 'Notiz',
        ja: 'ノート',
      ),
      _ => kind.trim().isEmpty ? '-' : kind,
    };
  }

  String _localizedStatus(String status, BuildContext context) {
    return switch (status) {
      'indexed' => _kbDetailText(
        context,
        zh: '已索引',
        zhHant: '已索引',
        en: 'Indexed',
        fr: 'Indexé',
        de: 'Indexiert',
        ja: 'インデックス済み',
      ),
      'failed' => _kbDetailText(
        context,
        zh: '失败',
        zhHant: '失敗',
        en: 'Failed',
        fr: 'Échec',
        de: 'Fehlgeschlagen',
        ja: '失敗',
      ),
      'indexing' => _kbDetailText(
        context,
        zh: '索引中',
        zhHant: '索引中',
        en: 'Indexing',
        fr: 'Indexation',
        de: 'Wird indexiert',
        ja: 'インデックス中',
      ),
      'pending' => _kbDetailText(
        context,
        zh: '待处理',
        zhHant: '待處理',
        en: 'Pending',
        fr: 'En attente',
        de: 'Ausstehend',
        ja: '保留中',
      ),
      'cancelled' => _kbDetailText(
        context,
        zh: '已停止',
        zhHant: '已停止',
        en: 'Stopped',
        fr: 'Arrêté',
        de: 'Gestoppt',
        ja: '停止済み',
      ),
      _ => status.trim().isEmpty ? '-' : status,
    };
  }

  String _date(DateTime? value) {
    if (value == null) return '-';
    return formatYearMonthDayHms(value.toLocal());
  }
}

class _ChunkTile extends StatelessWidget {
  const _ChunkTile({required this.source, required this.chunk});

  final KnowledgeSource source;
  final KnowledgeChunk chunk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final heading = chunk.headingPath.isEmpty ? chunk.title : chunk.headingPath;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showKnowledgeChunkDetailDialog(
            context,
            source: source,
            chunk: chunk,
          ),
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
                      label: _kbDetailText(
                        context,
                        zh: '${chunk.tokenEstimate} token',
                        zhHant: '${chunk.tokenEstimate} token',
                        en: '${chunk.tokenEstimate} tokens',
                        fr: '${chunk.tokenEstimate} tokens',
                        de: '${chunk.tokenEstimate} Token',
                        ja: '${chunk.tokenEstimate} token',
                      ),
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
          ),
        ),
      ),
    );
  }
}
