import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/hover_lift.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/oh_pill.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../knowledge_base_controller.dart';
import '../model/knowledge_source.dart';
import '../service/knowledge_document_parser.dart';
import '../service/knowledge_indexing_control.dart';
import 'knowledge_base_config_dialog.dart';
import 'knowledge_dialog_widgets.dart';
import 'knowledge_import_dialog.dart';
import 'knowledge_indexing_progress_dialog.dart';
import 'knowledge_source_content_dialog.dart';
import 'knowledge_source_detail_dialog.dart';
import 'knowledge_vector_distribution_dialog.dart';
import 'qdrant_admin_dialog.dart';
import 'qdrant_status_dialog.dart';

const double _kKnowledgeToolbarControlHeight = 54;

class KnowledgeBaseView extends StatelessWidget {
  const KnowledgeBaseView({super.key, this.onOpenPlugins});

  final VoidCallback? onOpenPlugins;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KnowledgeBaseController>();
    final settingsController = context.watch<SettingsController>();
    final colorScheme = Theme.of(context).colorScheme;
    final embeddingModel = controller.resolveEmbeddingModel(
      settingsController.aiModels,
    );

    return FeaturePageShell(
      title: openHandKnowledgeBaseLabel(context),
      subtitle: openHandLocalizedText(
        context,
        zh: '本地文档、笔记与 Qdrant 向量检索。',
        zhHant: '本地文件、筆記與 Qdrant 向量檢索。',
        en: 'Local documents, notes, and Qdrant vector retrieval.',
        fr: 'Documents locaux, notes et recherche vectorielle Qdrant.',
        de: 'Lokale Dokumente, Notizen und Qdrant-Vektorsuche.',
        ja: 'ローカルドキュメント、ノート、Qdrant ベクトル検索。',
      ),
      actions: _KnowledgeToolbarActions(
        controller: controller,
        embeddingModel: embeddingModel,
        aiModels: settingsController.aiModels,
        onOpenPlugins: onOpenPlugins,
      ),
      notices: [
        if (controller.error != null)
          FeatureStateCard.inline(
            icon: Icons.error_outline_rounded,
            tone: FeatureStateTone.error,
            title: openHandLocalizedText(
              context,
              zh: '知识库操作失败',
              zhHant: '知識庫操作失敗',
              en: 'Knowledge Base operation failed',
              fr: 'Échec de l’opération',
              de: 'Wissensdatenbank-Aktion fehlgeschlagen',
              ja: 'ナレッジベース操作に失敗しました',
            ),
            body: controller.error!,
            trailing: Tooltip(
              message: openHandDismissLabel(context),
              child: IconButton(
                onPressed: controller.clearError,
                icon: const Icon(Icons.close_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: colorScheme.onErrorContainer,
                  minimumSize: const Size(36, 36),
                  maximumSize: const Size(36, 36),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ),
      ],
      body: _KnowledgeBaseBody(controller: controller),
    );
  }

  static Future<void> _pickAndImportFile(
    BuildContext context, {
    required KnowledgeBaseController controller,
    required AiModelConfig? embeddingModel,
    required List<AiModelConfig> aiModels,
  }) async {
    if (embeddingModel == null) {
      showOpenHandErrorSnack(
        context,
        knowledgeEmbeddingModelMissingMessage(context),
      );
      return;
    }
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: openHandLocalizedText(
            context,
            zh: '知识库文档',
            zhHant: '知識庫文件',
            en: 'Knowledge documents',
            fr: 'Documents de connaissance',
            de: 'Wissensdokumente',
            ja: 'ナレッジドキュメント',
          ),
          extensions: KnowledgeDocumentParserRegistry.supportedExtensions,
        ),
      ],
    );
    if (file == null || !context.mounted) return;
    final cancelToken = KnowledgeIndexingCancelToken();
    final progressController = KnowledgeIndexingProgressController(
      cancelToken: cancelToken,
      initialProgress: KnowledgeIndexingProgress(
        sourceTitle: p.basename(file.path),
      ),
    );
    final source = await runKnowledgeIndexingProgressTask<KnowledgeSource>(
      context: context,
      controller: progressController,
      title: knowledgeIndexingProgressTitle(context),
      subtitle: openHandLocalizedText(
        context,
        zh: '正在准备导入文件。',
        zhHant: '正在準備匯入檔案。',
        en: 'Preparing to import the file.',
        fr: 'Préparation de l’import du fichier.',
        de: 'Dateiimport wird vorbereitet.',
        ja: 'ファイルのインポートを準備しています。',
      ),
      task: () => controller.importFile(
        filePath: file.path,
        embeddingModel: embeddingModel,
        readerModels: aiModels,
        cancelToken: cancelToken,
        onProgress: progressController.updateProgress,
      ),
    );
    if (!context.mounted) return;
    if (cancelToken.isCancelled) {
      showOpenHandInfoSnack(context, knowledgeIndexingStoppedMessage(context));
      return;
    }
    if (source != null) {
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '已导入并建立索引。',
          zhHant: '已匯入並建立索引。',
          en: 'Imported and indexed.',
          fr: 'Importé et indexé.',
          de: 'Importiert und indexiert.',
          ja: 'インポートしてインデックス化しました。',
        ),
      );
    } else {
      showOpenHandErrorSnack(
        context,
        controller.error ??
            openHandLocalizedText(
              context,
              zh: '导入失败。',
              zhHant: '匯入失敗。',
              en: 'Import failed.',
              fr: 'Échec de l’import.',
              de: 'Import fehlgeschlagen.',
              ja: 'インポートに失敗しました。',
            ),
      );
    }
  }

  static void _showReindexNotice(BuildContext context) {
    showOpenHandInfoSnack(
      context,
      openHandLocalizedText(
        context,
        zh: '重建索引入口已保留；可在 Qdrant 管理中检查一致性并删除/重建 collection。',
        zhHant: '重建索引入口已保留；可在 Qdrant 管理中檢查一致性並刪除/重建 collection。',
        en: 'Reindex entry is available; use Qdrant Admin to inspect consistency and rebuild collections.',
        fr: 'L’entrée de réindexation est disponible ; utilisez Qdrant Admin pour vérifier la cohérence et reconstruire les collections.',
        de: 'Der Reindex-Einstieg ist verfügbar; prüfen Sie die Konsistenz in Qdrant Admin und erstellen Sie Collections neu.',
        ja: '再インデックス入口は利用できます。Qdrant Admin で整合性を確認し、collection を再構築できます。',
      ),
    );
  }
}

class _KnowledgeToolbarActions extends StatelessWidget {
  const _KnowledgeToolbarActions({
    required this.controller,
    required this.embeddingModel,
    required this.aiModels,
    this.onOpenPlugins,
  });

  static const double _compactBreakpoint = 560;

  final KnowledgeBaseController controller;
  final AiModelConfig? embeddingModel;
  final List<AiModelConfig> aiModels;
  final VoidCallback? onOpenPlugins;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth.isFinite
            ? constraints.maxWidth < _compactBreakpoint
            : MediaQuery.sizeOf(context).width < 1180;
        return _buildToolbar(context, compact: compact);
      },
    );
  }

  Widget _buildToolbar(BuildContext context, {required bool compact}) {
    final refreshButton = FilledButton.tonalIcon(
      onPressed: controller.loading || controller.busy
          ? null
          : () => controller.initialize(),
      icon: const Icon(Icons.refresh_rounded),
      label: Text(knowledgeRefreshLabel(context)),
    );
    final importButton = FilledButton.icon(
      onPressed: controller.loading || controller.busy
          ? null
          : () => KnowledgeBaseView._pickAndImportFile(
              context,
              controller: controller,
              embeddingModel: embeddingModel,
              aiModels: aiModels,
            ),
      icon: const Icon(Icons.upload_file_rounded),
      label: Text(openHandImportLabel(context)),
    );
    final configButton = FilledButton.tonalIcon(
      onPressed: controller.loading || controller.busy
          ? null
          : () => showKnowledgeBaseConfigDialog(
              context,
              onOpenPlugins: onOpenPlugins,
            ),
      icon: const Icon(Icons.settings_rounded),
      label: Text(
        openHandLocalizedText(
          context,
          zh: '配置',
          zhHant: '設定',
          en: 'Configure',
          fr: 'Configurer',
          de: 'Konfigurieren',
          ja: '設定',
        ),
      ),
    );
    final usageButton = resourceUsageStatisticsButton(
      context,
      onPressed: () => showResourceUsageStatisticsDialog(
        context,
        kind: AiResourceUsageKind.knowledge,
        resourceLabels: <String, String>{
          for (final source in controller.sources) source.id: source.title,
        },
      ),
    );

    if (compact) {
      return FeaturePageToolbar(
        primaryActions: [
          refreshButton,
          importButton,
          configButton,
          usageButton,
        ],
        secondaryActions: [
          FeaturePageToolbarIconButton(
            tooltip: _knowledgeBaseVNewNoteLabel(context),
            icon: Icons.note_add_outlined,
            onPressed: controller.loading || controller.busy
                ? null
                : () => showKnowledgeImportDialog(context),
          ),
          FeaturePageToolbarIconButton(
            tooltip: _knowledgeBaseVVectorMapLabel(context),
            icon: Icons.scatter_plot_rounded,
            onPressed: controller.loading || controller.busy
                ? null
                : () => showKnowledgeVectorDistributionDialog(context),
          ),
          FeaturePageToolbarIconButton(
            tooltip: _knowledgeBaseVReindexLabel(context),
            icon: Icons.manage_search_rounded,
            onPressed: () => KnowledgeBaseView._showReindexNotice(context),
          ),
          FeaturePageToolbarIconButton(
            tooltip: _knowledgeBaseVQdrantOpsLabel(context),
            icon: Icons.monitor_heart_outlined,
            onPressed: controller.loading
                ? null
                : () => showQdrantStatusDialog(context),
          ),
          FeaturePageToolbarIconButton(
            tooltip: knowledgeQdrantAdminLabel(context),
            icon: Icons.storage_outlined,
            onPressed: controller.loading
                ? null
                : () => showQdrantAdminDialog(context),
          ),
        ],
      );
    }

    return FeaturePageToolbar(
      primaryActions: [
        refreshButton,
        OutlinedButton.icon(
          onPressed: controller.loading
              ? null
              : () => showQdrantStatusDialog(context),
          icon: const Icon(Icons.monitor_heart_outlined),
          label: Text(_knowledgeBaseVQdrantOpsLabel(context)),
        ),
        OutlinedButton.icon(
          onPressed: controller.loading
              ? null
              : () => showQdrantAdminDialog(context),
          icon: const Icon(Icons.storage_outlined),
          label: Text(knowledgeQdrantAdminLabel(context)),
        ),
        OutlinedButton.icon(
          onPressed: controller.loading || controller.busy
              ? null
              : () => showKnowledgeVectorDistributionDialog(context),
          icon: const Icon(Icons.scatter_plot_rounded),
          label: Text(_knowledgeBaseVVectorMapLabel(context)),
        ),
      ],
      secondaryActions: [
        OutlinedButton.icon(
          onPressed: () => KnowledgeBaseView._showReindexNotice(context),
          icon: const Icon(Icons.manage_search_rounded),
          label: Text(_knowledgeBaseVReindexLabel(context)),
        ),
        FilledButton.tonalIcon(
          onPressed: controller.loading || controller.busy
              ? null
              : () => showKnowledgeImportDialog(context),
          icon: const Icon(Icons.note_add_outlined),
          label: Text(_knowledgeBaseVNewNoteLabel(context)),
        ),
        importButton,
        configButton,
        usageButton,
      ],
    );
  }
}

class _KnowledgeBaseBody extends StatelessWidget {
  const _KnowledgeBaseBody({required this.controller});

  final KnowledgeBaseController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.sources.isEmpty && controller.query.trim().isEmpty) {
      return SizedBox.expand(
        child: FeatureStateCard.centered(
          icon: Icons.library_books_outlined,
          title: openHandLocalizedText(
            context,
            zh: '知识库为空',
            zhHant: '知識庫為空',
            en: 'Knowledge Base is empty',
            fr: 'La base de connaissances est vide',
            de: 'Wissensdatenbank ist leer',
            ja: 'ナレッジベースは空です',
          ),
          body: openHandLocalizedText(
            context,
            zh: '导入 Markdown、Office、PDF、HTML、CSV、JSON、TOML、YAML、TXT 或代码文件，或新建一条笔记来生成本地向量索引。',
            zhHant:
                '匯入 Markdown、Office、PDF、HTML、CSV、JSON、TOML、YAML、TXT 或程式碼檔案，或新增一條筆記來產生本地向量索引。',
            en: 'Import Markdown, Office, PDF, HTML, CSV, JSON, TOML, YAML, TXT, or code files, or create a note to build the local vector index.',
            fr: 'Importez des fichiers Markdown, Office, PDF, HTML, CSV, JSON, TOML, YAML, TXT ou code, ou créez une note pour bâtir l’index vectoriel local.',
            de: 'Importieren Sie Markdown-, Office-, PDF-, HTML-, CSV-, JSON-, TOML-, YAML-, TXT- oder Codedateien oder erstellen Sie eine Notiz für den lokalen Vektorindex.',
            ja: 'Markdown、Office、PDF、HTML、CSV、JSON、TOML、YAML、TXT、コードファイルをインポートするか、ノートを作成してローカルベクトルインデックスを構築します。',
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: _kKnowledgeToolbarControlHeight,
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: openHandLocalizedText(
                      context,
                      zh: '搜索来源标题或路径',
                      zhHant: '搜尋來源標題或路徑',
                      en: 'Search source title or path',
                      fr: 'Rechercher titre ou chemin',
                      de: 'Quellentitel oder Pfad suchen',
                      ja: 'ソースタイトルまたはパスを検索',
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 17,
                    ),
                  ),
                  onChanged: controller.searchSources,
                ),
              ),
            ),
            kOpenHandHGap12,
            FutureBuilder<
              ({
                int sourceCount,
                int chunkCount,
                int pendingJobs,
                int failedJobs,
              })
            >(
              future: controller.loadStats(),
              builder: (context, snapshot) {
                final stats = snapshot.data;
                return _KbStatStrip(
                  sourceCount: stats?.sourceCount ?? controller.sources.length,
                  chunkCount: stats?.chunkCount ?? 0,
                  pendingJobs: stats?.pendingJobs ?? 0,
                  failedJobs: stats?.failedJobs ?? 0,
                );
              },
            ),
          ],
        ),
        kOpenHandGap16,
        Expanded(
          child: ListView.separated(
            itemCount: controller.sources.length,
            separatorBuilder: (_, _) => kOpenHandGap10,
            itemBuilder: (context, index) {
              final source = controller.sources[index];
              return _KnowledgeSourceCard(source: source);
            },
          ),
        ),
      ],
    );
  }
}

class _KbStatStrip extends StatelessWidget {
  const _KbStatStrip({
    required this.sourceCount,
    required this.chunkCount,
    required this.pendingJobs,
    required this.failedJobs,
  });

  final int sourceCount;
  final int chunkCount;
  final int pendingJobs;
  final int failedJobs;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kKnowledgeToolbarControlHeight,
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _KbStatChip(
              label: openHandLocalizedText(
                context,
                zh: '来源',
                zhHant: '來源',
                en: 'Sources',
                fr: 'Sources',
                de: 'Quellen',
                ja: 'ソース',
              ),
              value: sourceCount,
            ),
            _KbStatChip(
              label: openHandLocalizedText(
                context,
                zh: '分块',
                zhHant: '分塊',
                en: 'Chunks',
                fr: 'Fragments',
                de: 'Chunks',
                ja: 'チャンク',
              ),
              value: chunkCount,
            ),
            _KbStatChip(
              label: knowledgePendingLabel(context),
              value: pendingJobs,
            ),
            _KbStatChip(
              label: knowledgeFailedLabel(context),
              value: failedJobs,
            ),
          ],
        ),
      ),
    );
  }
}

class _KbStatChip extends StatelessWidget {
  const _KbStatChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: _kKnowledgeToolbarControlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: kOpenHandPillBorderRadius,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.data_object_rounded, size: 18),
          kOpenHandHGap8,
          Text(
            '$label $value',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}

enum _KnowledgeCardAction { delete }

class _KnowledgeSourceCard extends StatelessWidget {
  const _KnowledgeSourceCard({required this.source});

  static const double _radius = 28;
  static const double _actionButtonSize = 44;

  final KnowledgeSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = switch (source.status) {
      'indexed' => Colors.green,
      'failed' => colorScheme.error,
      'indexing' => colorScheme.primary,
      'cancelled' => colorScheme.outline,
      _ => colorScheme.onSurfaceVariant,
    };
    return HoverLift(
      child: AnimatedSize(
        duration: openHandMotionDuration(context, kOpenHandMotion320),
        curve: kOpenHandSwitchInCurve,
        alignment: Alignment.topCenter,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(_radius),
            overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.pressed)) {
                return colorScheme.primary.withValues(alpha: 0.10);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return colorScheme.primary.withValues(alpha: 0.06);
              }
              return null;
            }),
            onTap: () => showKnowledgeSourceDetailDialog(context, source.id),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: kOpenHandBorderRadius18,
                            ),
                            child: Icon(
                              knowledgeSourceKindIcon(source.kind),
                              color: colorScheme.onPrimaryContainer,
                              size: 26,
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: _KnowledgeSourceStatusDot(
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                      kOpenHandHGap16,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              source.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            kOpenHandGap6,
                            Text(
                              localizedKnowledgeSourceKind(
                                context,
                                source.kind,
                              ),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            kOpenHandGap6,
                            Text(
                              source.originalPath,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      kOpenHandHGap12,
                      Flexible(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {},
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              alignment: WrapAlignment.end,
                              children: [
                                _KnowledgeCardActionButton(
                                  tooltip: openHandLocalizedText(
                                    context,
                                    zh: '查看内容',
                                    zhHant: '查看內容',
                                    en: 'View content',
                                    fr: 'Voir le contenu',
                                    de: 'Inhalt anzeigen',
                                    ja: '内容を表示',
                                  ),
                                  icon: Icons.article_outlined,
                                  onPressed: () =>
                                      showKnowledgeSourceContentDialog(
                                        context,
                                        source.id,
                                      ),
                                  size: _actionButtonSize,
                                ),
                                _KnowledgeCardActionButton(
                                  tooltip: openHandDetailsLabel(context),
                                  icon: Icons.edit_outlined,
                                  onPressed: () =>
                                      showKnowledgeSourceDetailDialog(
                                        context,
                                        source.id,
                                      ),
                                  size: _actionButtonSize,
                                ),
                                SizedBox(
                                  width: _actionButtonSize,
                                  height: _actionButtonSize,
                                  child:
                                      AnimatedPopupMenuButton<
                                        _KnowledgeCardAction
                                      >(
                                        tooltip: openHandMoreActionsLabel(
                                          context,
                                        ),
                                        onSelected: (action) {
                                          switch (action) {
                                            case _KnowledgeCardAction.delete:
                                              _confirmDelete(context);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem<_KnowledgeCardAction>(
                                            value: _KnowledgeCardAction.delete,
                                            child: Text(
                                              openHandDeleteLabel(context),
                                              style: TextStyle(
                                                color: colorScheme.error,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  kOpenHandGap16,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _SmallPill(
                          icon: Icons.circle,
                          label: localizedKnowledgeSourceStatus(
                            context,
                            source.status,
                          ),
                          color: statusColor,
                        ),
                        _SmallPill(
                          icon: Icons.sd_storage_outlined,
                          label: formatByteSize(source.sizeBytes),
                          color: colorScheme.onSurfaceVariant,
                        ),
                        _SmallPill(
                          icon: Icons.schedule_rounded,
                          label: formatYearMonthDayHm(
                            source.updatedAt.toLocal(),
                          ),
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: openHandLocalizedText(
        context,
        zh: '删除知识库来源？',
        zhHant: '刪除知識庫來源？',
        en: 'Delete knowledge source?',
        fr: 'Supprimer la source ?',
        de: 'Wissensquelle löschen?',
        ja: 'ナレッジソースを削除しますか？',
      ),
      message: openHandLocalizedText(
        context,
        zh: '将删除 SQLite 元数据、chunks，并尝试删除 Qdrant 中该来源的向量。原始文件不会删除。',
        zhHant: '將刪除 SQLite 元資料、chunks，並嘗試刪除 Qdrant 中該來源的向量。原始檔案不會刪除。',
        en: 'This deletes SQLite metadata, chunks, and attempts to remove this source vectors from Qdrant. The original file is kept.',
        fr: 'Supprime les métadonnées SQLite, les chunks et tente de retirer les vecteurs de cette source dans Qdrant. Le fichier original est conservé.',
        de: 'Löscht SQLite-Metadaten und Chunks und versucht, die Vektoren dieser Quelle aus Qdrant zu entfernen. Die Originaldatei bleibt erhalten.',
        ja: 'SQLite メタデータとチャンクを削除し、Qdrant からこのソースのベクトル削除を試みます。元ファイルは削除されません。',
      ),
      confirmLabel: openHandDeleteLabel(context),
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final controller = context.read<KnowledgeBaseController>();
    final deleted = await controller.deleteSource(source);
    if (!context.mounted) return;
    if (deleted) {
      showOpenHandSuccessSnack(
        context,
        openHandLocalizedText(
          context,
          zh: '来源已删除。',
          zhHant: '來源已刪除。',
          en: 'Source deleted.',
          fr: 'Source supprimée.',
          de: 'Quelle gelöscht.',
          ja: 'ソースを削除しました。',
        ),
      );
      return;
    }
    showOpenHandErrorSnack(
      context,
      controller.error ??
          openHandLocalizedText(
            context,
            zh: '来源删除失败。',
            zhHant: '來源刪除失敗。',
            en: 'Failed to delete source.',
            fr: 'Échec de la suppression de la source.',
            de: 'Quelle konnte nicht gelöscht werden.',
            ja: 'ソースの削除に失敗しました。',
          ),
    );
  }
}

class _KnowledgeCardActionButton extends StatelessWidget {
  const _KnowledgeCardActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.size,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton.filledTonal(onPressed: onPressed, icon: Icon(icon)),
      ),
    );
  }
}

class _KnowledgeSourceStatusDot extends StatelessWidget {
  const _KnowledgeSourceStatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final motionEnabled = openHandTickerMotionEnabled(context);
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 3,
        ),
        boxShadow: motionEnabled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.32),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final neutral = color == colorScheme.onSurfaceVariant;
    return Chip(
      avatar: Icon(icon, size: 18, color: neutral ? null : color),
      label: Text(label),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      backgroundColor: neutral
          ? colorScheme.surfaceContainerHighest
          : color.withValues(alpha: 0.10),
      side: neutral
          ? BorderSide(color: colorScheme.outlineVariant)
          : BorderSide(color: color.withValues(alpha: 0.28)),
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        color: neutral ? colorScheme.onSurface : color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// 本文件内复用文案。

String _knowledgeBaseVNewNoteLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '新建笔记',
    zhHant: '新增筆記',
    en: 'New Note',
    fr: 'Nouvelle note',
    de: 'Neue Notiz',
    ja: '新規ノート',
  );
}

String _knowledgeBaseVQdrantOpsLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: 'Qdrant 运维',
    zhHant: 'Qdrant 維運',
    en: 'Qdrant Ops',
    fr: 'Ops Qdrant',
    de: 'Qdrant-Betrieb',
    ja: 'Qdrant 運用',
  );
}

String _knowledgeBaseVReindexLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '重建索引',
    zhHant: '重建索引',
    en: 'Reindex',
    fr: 'Réindexer',
    de: 'Neu indexieren',
    ja: '再インデックス',
  );
}

String _knowledgeBaseVVectorMapLabel(BuildContext context) {
  return openHandLocalizedText(
    context,
    zh: '向量分布',
    zhHant: '向量分布',
    en: 'Vector Map',
    fr: 'Carte vectorielle',
    de: 'Vektorkarte',
    ja: 'ベクトルマップ',
  );
}
