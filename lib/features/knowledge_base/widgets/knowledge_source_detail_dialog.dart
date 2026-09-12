import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_form_fields.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../knowledge_base_controller.dart';
import '../knowledge_base_errors.dart';
import '../model/knowledge_chunk.dart';
import '../model/knowledge_source.dart';
import 'knowledge_chunk_detail_dialog.dart';
import 'knowledge_dialog_widgets.dart';

Future<void> showKnowledgeSourceDetailDialog(
  BuildContext context,
  String sourceId,
) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _KnowledgeSourceDetailDialog(sourceId: sourceId),
  );
}

class _KnowledgeSourceDetailDialog extends StatelessWidget {
  const _KnowledgeSourceDetailDialog({required this.sourceId});

  final String sourceId;

  Future<(KnowledgeSource?, List<KnowledgeChunk>)> _load(
    KnowledgeBaseController controller,
  ) async {
    try {
      final source = await controller.loadSource(sourceId);
      final chunks = await controller.loadChunksForSource(sourceId);
      return (source, chunks);
    } catch (error, stack) {
      silentLog('knowledge_source_detail_dialog', '加载知识源详情', error, stack);
      Error.throwWithStackTrace(error, stack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<KnowledgeBaseController>();
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<(KnowledgeSource?, List<KnowledgeChunk>)>(
      future: _load(controller),
      builder: (context, snapshot) {
        final source = snapshot.data?.$1;
        final chunks = snapshot.data?.$2 ?? const <KnowledgeChunk>[];
        final loading = snapshot.connectionState != ConnectionState.done;
        return OpenHandEditorDialogScaffold(
          title: openHandLocalizedText(
            context,
            zh: '知识库来源详情',
            zhHant: '知識庫來源詳情',
            en: 'Knowledge Source Detail',
            fr: 'Détail de la source',
            de: 'Wissensquellendetail',
            ja: 'ナレッジソース詳細',
          ),
          subtitle: source?.title,
          icon: Icons.description_outlined,
          iconColor: source == null
              ? colorScheme.primary
              : knowledgeSourceKindAccent(source.kind, colorScheme),
          busy: loading,
          actions: [
            if (source != null)
              OpenHandDialogActionButton.secondary(
                onPressed: () async {
                  await copyOpenHandTextToClipboard(
                    logTag: 'knowledge_base',
                    context: context,
                    text: source.originalPath,
                    successMessage: knowledgePathCopiedMessage(context),
                    logAction: '复制知识源详情路径',
                  );
                },
                icon: Icons.copy_rounded,
                label: knowledgeCopyPathLabel(context),
              ),
            OpenHandDialogActionButton.primary(
              onPressed: () => Navigator.of(context).pop(),
              label: openHandCloseLabel(context),
            ),
          ],
          body: loading
              ? OpenHandTintedPanel(
                  accent: colorScheme.primary,
                  child: const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              : snapshot.hasError
              ? KnowledgeDialogNotice(
                  icon: Icons.error_outline_rounded,
                  message: knowledgeBaseFailureMessage(
                    snapshot.error!,
                    fallback: '加载知识源详情失败，请稍后重试。',
                  ),
                  tone: KnowledgeDialogNoticeTone.error,
                )
              : source == null
              ? KnowledgeDialogNotice(
                  icon: Icons.info_outline_rounded,
                  message: knowledgeSourceMissingMessage(context),
                )
              : _SourceDetailBody(source: source, chunks: chunks),
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
    final colorScheme = Theme.of(context).colorScheme;
    final kindAccent = knowledgeSourceKindAccent(source.kind, colorScheme);
    final statusColor = switch (source.status.trim().toLowerCase()) {
      'indexed' => OpenHandStatusColors.success,
      'failed' => OpenHandStatusColors.error,
      'indexing' => OpenHandStatusColors.warning,
      'pending' => OpenHandStatusColors.caution,
      _ => colorScheme.onSurfaceVariant,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KnowledgeDialogSection(
          title: openHandLocalizedText(
            context,
            zh: '来源信息',
            zhHant: '來源資訊',
            en: 'Source',
            fr: 'Source',
            de: 'Quelle',
            ja: 'ソース',
          ),
          icon: Icons.description_outlined,
          accent: kindAccent,
          trailing: OhPill(
            icon: Icons.check_circle_rounded,
            label: localizedKnowledgeSourceStatus(context, source.status),
            foregroundColor: statusColor,
          ),
          child: KnowledgeDialogKeyValueList(
            labelWidth: openHandIsChineseLocale(context) ? 120 : 128,
            rows: {
              knowledgeTitleLabel(context): source.title,
              openHandLocalizedText(
                context,
                zh: '类型',
                zhHant: '類型',
                en: 'Kind',
                fr: 'Type',
                de: 'Art',
                ja: '種類',
              ): localizedKnowledgeSourceKind(
                context,
                source.kind,
              ),
              knowledgeStatusLabel(context): localizedKnowledgeSourceStatus(
                context,
                source.status,
              ),
              openHandLocalizedText(
                context,
                zh: '原始路径',
                zhHant: '原始路徑',
                en: 'Original path',
                fr: 'Chemin d’origine',
                de: 'Ursprungspfad',
                ja: '元のパス',
              ): source.originalPath,
              openHandLocalizedText(
                context,
                zh: '存储路径',
                zhHant: '儲存路徑',
                en: 'Stored path',
                fr: 'Chemin stocké',
                de: 'Gespeicherter Pfad',
                ja: '保存パス',
              ): source.storedPath,
              knowledgeDocumentTimeLabel(context): _date(source.documentTime),
              openHandLocalizedText(
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
              openHandLocalizedText(
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
                knowledgeErrorLabel(context): source.errorMessage,
            },
          ),
        ),
        KnowledgeDialogSection(
          title: openHandLocalizedText(
            context,
            zh: '分块 (${chunks.length})',
            zhHant: '分塊 (${chunks.length})',
            en: 'Chunks (${chunks.length})',
            fr: 'Fragments (${chunks.length})',
            de: 'Abschnitte (${chunks.length})',
            ja: 'チャンク (${chunks.length})',
          ),
          icon: Icons.article_outlined,
          accent: colorScheme.tertiary,
          margin: EdgeInsets.zero,
          child: chunks.isEmpty
              ? KnowledgeDialogNotice(
                  icon: Icons.info_outline_rounded,
                  message: openHandLocalizedText(
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
    );
  }

  String _date(DateTime? value) {
    if (value == null) return '-';
    return formatYearMonthDayHmsLocal(value);
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
    final accent = colorScheme.tertiary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Color.alphaBlend(
          accent.withValues(alpha: 0.08),
          colorScheme.surfaceContainerLow,
        ),
        borderRadius: kOpenHandBorderRadius16,
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
              borderRadius: kOpenHandBorderRadius16,
              border: Border.all(color: accent.withValues(alpha: 0.22)),
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
                      label: openHandLocalizedText(
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
                  kOpenHandGap8,
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
                kOpenHandGap8,
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
