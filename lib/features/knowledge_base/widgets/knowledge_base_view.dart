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
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../knowledge_base_controller.dart';
import '../model/knowledge_source.dart';
import '../service/knowledge_document_parser.dart';
import '../service/knowledge_indexing_control.dart';
import 'knowledge_base_config_dialog.dart';
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
    final isZh = openHandIsChineseLocale(context);
    final colorScheme = Theme.of(context).colorScheme;
    final embeddingModel = controller.resolveEmbeddingModel(
      settingsController.aiModels,
    );

    return FeaturePageShell(
      title: isZh ? '知识库' : 'Knowledge Base',
      subtitle: isZh
          ? '本地文档、笔记与 Qdrant 向量检索。'
          : 'Local documents, notes, and Qdrant vector retrieval.',
      actions: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.end,
        children: [
          FilledButton.tonalIcon(
            onPressed: controller.loading || controller.busy
                ? null
                : () => controller.initialize(),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(isZh ? '刷新' : 'Refresh'),
          ),
          OutlinedButton.icon(
            onPressed: () => showQdrantStatusDialog(context),
            icon: const Icon(Icons.monitor_heart_outlined),
            label: Text(isZh ? 'Qdrant 运维' : 'Qdrant Ops'),
          ),
          OutlinedButton.icon(
            onPressed: () => showQdrantAdminDialog(context),
            icon: const Icon(Icons.storage_outlined),
            label: Text(isZh ? 'Qdrant 管理' : 'Qdrant Admin'),
          ),
          OutlinedButton.icon(
            onPressed: controller.loading || controller.busy
                ? null
                : () => showKnowledgeVectorDistributionDialog(context),
            icon: const Icon(Icons.scatter_plot_rounded),
            label: Text(isZh ? '向量分布' : 'Vector Map'),
          ),
          OutlinedButton.icon(
            onPressed: () => _showReindexNotice(context),
            icon: const Icon(Icons.manage_search_rounded),
            label: Text(isZh ? '重建索引' : 'Reindex'),
          ),
          FilledButton.tonalIcon(
            onPressed: controller.busy
                ? null
                : () => showKnowledgeImportDialog(context),
            icon: const Icon(Icons.note_add_outlined),
            label: Text(isZh ? '新建笔记' : 'New Note'),
          ),
          FilledButton.icon(
            onPressed: controller.busy
                ? null
                : () => _pickAndImportFile(
                    context,
                    controller: controller,
                    embeddingModel: embeddingModel,
                    aiModels: settingsController.aiModels,
                  ),
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(isZh ? '导入' : 'Import'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => showKnowledgeBaseConfigDialog(
              context,
              onOpenPlugins: onOpenPlugins,
            ),
            icon: const Icon(Icons.settings_rounded),
            label: Text(isZh ? '配置' : 'Configure'),
          ),
        ],
      ),
      notices: [
        if (controller.error != null)
          FeatureStateCard.inline(
            icon: Icons.error_outline_rounded,
            tone: FeatureStateTone.error,
            title: isZh ? '知识库操作失败' : 'Knowledge Base operation failed',
            body: controller.error!,
            trailing: Tooltip(
              message: isZh ? '关闭' : 'Dismiss',
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
    final isZh = openHandIsChineseLocale(context);
    if (embeddingModel == null) {
      OpenHandSnackBar.showError(
        context,
        isZh ? '请先配置可用的嵌入模型。' : 'Configure an embedding model first.',
      );
      return;
    }
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: isZh ? '知识库文档' : 'Knowledge documents',
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
    KnowledgeSource? source;
    try {
      source = await runKnowledgeIndexingProgressTask<KnowledgeSource>(
        context: context,
        controller: progressController,
        title: isZh ? '构建知识库向量' : 'Building Knowledge Vectors',
        subtitle: isZh ? '正在准备导入文件。' : 'Preparing to import the file.',
        task: () => controller.importFile(
          filePath: file.path,
          embeddingModel: embeddingModel,
          readerModels: aiModels,
          cancelToken: cancelToken,
          onProgress: progressController.updateProgress,
        ),
      );
    } finally {
      progressController.dispose();
    }
    if (!context.mounted) return;
    if (cancelToken.isCancelled) {
      OpenHandSnackBar.showInfo(
        context,
        isZh ? '已停止构建向量。' : 'Vector indexing stopped.',
      );
      return;
    }
    if (source != null) {
      OpenHandSnackBar.showSuccess(
        context,
        isZh ? '已导入并建立索引。' : 'Imported and indexed.',
      );
    } else {
      OpenHandSnackBar.showError(
        context,
        controller.error ?? (isZh ? '导入失败。' : 'Import failed.'),
      );
    }
  }

  static void _showReindexNotice(BuildContext context) {
    OpenHandSnackBar.showInfo(
      context,
      openHandLocalizedText(
        context,
        zh: '重建索引入口已保留；可在 Qdrant 管理中检查一致性并删除/重建 collection。',
        en: 'Reindex entry is available; use Qdrant Admin to inspect consistency and rebuild collections.',
      ),
    );
  }
}

class _KnowledgeBaseBody extends StatelessWidget {
  const _KnowledgeBaseBody({required this.controller});

  final KnowledgeBaseController controller;

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.sources.isEmpty && controller.query.trim().isEmpty) {
      return SizedBox.expand(
        child: FeatureStateCard.centered(
          icon: Icons.library_books_outlined,
          title: isZh ? '知识库为空' : 'Knowledge Base is empty',
          body: isZh
              ? '导入 Markdown、Office、PDF、HTML、CSV、JSON、TOML、YAML、TXT 或代码文件，或新建一条笔记来生成本地向量索引。'
              : 'Import Markdown, Office, PDF, HTML, CSV, JSON, TOML, YAML, TXT, or code files, or create a note to build the local vector index.',
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
                    hintText: isZh
                        ? '搜索来源标题或路径'
                        : 'Search source title or path',
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
            const SizedBox(width: 12),
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
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: controller.sources.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
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
    final isZh = openHandIsChineseLocale(context);
    return SizedBox(
      height: _kKnowledgeToolbarControlHeight,
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _KbStatChip(label: isZh ? '来源' : 'Sources', value: sourceCount),
            _KbStatChip(label: isZh ? '分块' : 'Chunks', value: chunkCount),
            _KbStatChip(label: isZh ? '待处理' : 'Pending', value: pendingJobs),
            _KbStatChip(label: isZh ? '失败' : 'Failed', value: failedJobs),
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
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.data_object_rounded, size: 18),
          const SizedBox(width: 8),
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
    final isZh = openHandIsChineseLocale(context);
    final statusColor = switch (source.status) {
      'indexed' => Colors.green,
      'failed' => colorScheme.error,
      'indexing' => colorScheme.primary,
      'cancelled' => colorScheme.outline,
      _ => colorScheme.onSurfaceVariant,
    };
    return HoverLift(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
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
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              _iconForKind(source.kind),
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
                      const SizedBox(width: 16),
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
                            const SizedBox(height: 6),
                            Text(
                              _localizedKind(source.kind, context),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
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
                      const SizedBox(width: 12),
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
                                  tooltip: isZh ? '查看内容' : 'View content',
                                  icon: Icons.article_outlined,
                                  onPressed: () =>
                                      showKnowledgeSourceContentDialog(
                                        context,
                                        source.id,
                                      ),
                                  size: _actionButtonSize,
                                ),
                                _KnowledgeCardActionButton(
                                  tooltip: isZh ? '详情' : 'Details',
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
                                        tooltip: isZh ? '更多操作' : 'More actions',
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
                                              isZh ? '删除' : 'Delete',
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
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _SmallPill(
                          icon: Icons.circle,
                          label: _localizedStatus(source.status, context),
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
    final isZh = openHandIsChineseLocale(context);
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: isZh ? '删除知识库来源？' : 'Delete knowledge source?',
      message: isZh
          ? '将删除 SQLite 元数据、chunks，并尝试删除 Qdrant 中该来源的向量。原始文件不会删除。'
          : 'This deletes SQLite metadata, chunks, and attempts to remove this source vectors from Qdrant. The original file is kept.',
      confirmLabel: isZh ? '删除' : 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final controller = context.read<KnowledgeBaseController>();
    final deleted = await controller.deleteSource(source);
    if (!context.mounted) return;
    if (deleted) {
      OpenHandSnackBar.showSuccess(
        context,
        isZh ? '来源已删除。' : 'Source deleted.',
      );
      return;
    }
    OpenHandSnackBar.showError(
      context,
      controller.error ?? (isZh ? '来源删除失败。' : 'Failed to delete source.'),
    );
  }

  IconData _iconForKind(String kind) {
    return switch (kind) {
      'markdown' => Icons.notes_rounded,
      'code' => Icons.code_rounded,
      'pdf' => Icons.picture_as_pdf_outlined,
      'html' => Icons.language_rounded,
      'docx' => Icons.article_outlined,
      'spreadsheet' => Icons.table_chart_outlined,
      'presentation' => Icons.slideshow_outlined,
      'table' => Icons.dataset_outlined,
      'structured' => Icons.data_object_rounded,
      _ => Icons.description_outlined,
    };
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
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
        boxShadow: reduceMotion
            ? null
            : [
                BoxShadow(
                  color: color.withValues(alpha: 0.32),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
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
