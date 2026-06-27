import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/localized_text.dart';
import '../../ai/index.dart';
import '../../plugin_service/index.dart';
import '../knowledge_base_controller.dart';
import '../model/knowledge_source.dart';
import '../service/knowledge_document_parser.dart';
import 'knowledge_base_config_dialog.dart';
import 'knowledge_import_dialog.dart';
import 'knowledge_source_detail_dialog.dart';
import 'qdrant_admin_dialog.dart';
import 'qdrant_status_dialog.dart';

class KnowledgeBaseView extends StatelessWidget {
  const KnowledgeBaseView({super.key, this.onOpenPlugins});

  final VoidCallback? onOpenPlugins;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<KnowledgeBaseController>();
    final pluginController = context.watch<PluginServiceController>();
    final settingsController = context.watch<SettingsController>();
    final isZh = openHandIsChineseLocale(context);
    final colorScheme = Theme.of(context).colorScheme;
    final dependencies = controller.dependencies(pluginController);
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
      body: _KnowledgeBaseBody(
        controller: controller,
        embeddingModel: embeddingModel,
        dependenciesReady: dependencies.ready,
        onOpenPlugins: onOpenPlugins,
      ),
    );
  }

  static Future<void> _pickAndImportFile(
    BuildContext context, {
    required KnowledgeBaseController controller,
    required AiModelConfig? embeddingModel,
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
    final source = await controller.importFile(
      filePath: file.path,
      embeddingModel: embeddingModel,
    );
    if (!context.mounted) return;
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
  const _KnowledgeBaseBody({
    required this.controller,
    required this.embeddingModel,
    required this.dependenciesReady,
    required this.onOpenPlugins,
  });

  final KnowledgeBaseController controller;
  final AiModelConfig? embeddingModel;
  final bool dependenciesReady;
  final VoidCallback? onOpenPlugins;

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
          action: embeddingModel != null && dependenciesReady
              ? FilledButton.icon(
                  onPressed: () => showKnowledgeImportDialog(context),
                  icon: const Icon(Icons.note_add_outlined),
                  label: Text(isZh ? '新建笔记' : 'New Note'),
                )
              : null,
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: isZh ? '搜索来源标题或路径' : 'Search source title or path',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: controller.searchSources,
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
    return Wrap(
      spacing: 8,
      children: [
        _KbStatChip(label: isZh ? '来源' : 'Sources', value: sourceCount),
        _KbStatChip(label: isZh ? '分块' : 'Chunks', value: chunkCount),
        _KbStatChip(label: isZh ? '待处理' : 'Pending', value: pendingJobs),
        _KbStatChip(label: isZh ? '失败' : 'Failed', value: failedJobs),
      ],
    );
  }
}

class _KbStatChip extends StatelessWidget {
  const _KbStatChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Chip(
      avatar: const Icon(Icons.data_object_rounded, size: 16),
      label: Text('$label $value'),
      visualDensity: VisualDensity.compact,
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide(color: colorScheme.outlineVariant),
    );
  }
}

class _KnowledgeSourceCard extends StatelessWidget {
  const _KnowledgeSourceCard({required this.source});

  final KnowledgeSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = switch (source.status) {
      'indexed' => Colors.green,
      'failed' => colorScheme.error,
      'indexing' => colorScheme.primary,
      _ => colorScheme.onSurfaceVariant,
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showKnowledgeSourceDetailDialog(context, source.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconForKind(source.kind),
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      source.originalPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
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
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
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

  String _localizedStatus(String status, BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    return switch (status) {
      'indexed' => isZh ? '已索引' : 'Indexed',
      'failed' => isZh ? '失败' : 'Failed',
      'indexing' => isZh ? '索引中' : 'Indexing',
      'pending' => isZh ? '待处理' : 'Pending',
      _ => status.trim().isEmpty ? '-' : status,
    };
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
