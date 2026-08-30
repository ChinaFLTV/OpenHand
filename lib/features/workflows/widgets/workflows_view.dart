import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../app/support/silent_log.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../model/workflow_definition.dart';
import '../service/workflow_portability_service.dart';
import '../workflows_controller.dart';
import 'workflow_editor_dialog.dart';
import 'workflow_export_progress_dialog.dart';
import 'workflow_minimap.dart';

const XTypeGroup _workflowYamlTypeGroup = XTypeGroup(
  label: 'OpenHand 工作流 YAML',
  extensions: <String>['yaml', 'yml'],
);
const Uuid _workflowUuid = Uuid();
const double _workflowGridSpacing = 14;
const double _workflowTwoColumnMinWidth = 920;

class WorkflowsView extends StatefulWidget {
  const WorkflowsView({super.key});

  @override
  State<WorkflowsView> createState() => _WorkflowsViewState();
}

class _WorkflowsViewState extends State<WorkflowsView> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final snapshot = context
        .select<
          WorkflowsController,
          ({bool loading, String? error, List<WorkflowDefinition> workflows})
        >(
          (controller) => (
            loading: controller.isLoading,
            error: controller.errorMessage,
            workflows: controller.workflows,
          ),
        );
    final controller = context.read<WorkflowsController>();
    return FeaturePageShell(
      title: l10n.workflowsTitle,
      subtitle: l10n.workflowsSubtitle,
      successSignal: controller.saveSuccessSignal,
      actions: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.end,
        children: [
          if (snapshot.error != null)
            FilledButton.tonalIcon(
              onPressed: snapshot.loading ? null : controller.refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.commonRetry),
            ),
          FilledButton.tonalIcon(
            key: const ValueKey<String>('workflow-import-button'),
            onPressed: snapshot.loading || snapshot.error != null || _importing
                ? null
                : () => _importWorkflow(controller),
            icon: _importing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.file_upload_outlined),
            label: const Text('导入工作流'),
          ),
          FilledButton.icon(
            onPressed: snapshot.loading || snapshot.error != null
                ? null
                : () => _openEditor(context, controller),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.workflowsNew),
          ),
        ],
      ),
      notices: [
        if (snapshot.error != null && snapshot.workflows.isNotEmpty)
          FeatureStateCard.inline(
            icon: Icons.error_outline_rounded,
            tone: FeatureStateTone.error,
            title: l10n.settingsPersistenceLoadFailedTitle,
            body: snapshot.error!,
          ),
      ],
      body: snapshot.loading && snapshot.workflows.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : snapshot.error != null && snapshot.workflows.isEmpty
          ? FeatureStateCard.centered(
              icon: Icons.error_outline_rounded,
              tone: FeatureStateTone.error,
              title: l10n.settingsPersistenceLoadFailedTitle,
              body: snapshot.error!,
            )
          : snapshot.workflows.isEmpty
          ? SizedBox.expand(
              child: FeatureStateCard.centered(
                icon: Icons.account_tree_outlined,
                tone: FeatureStateTone.neutral,
                title: l10n.workflowsEmptyTitle,
                body: l10n.workflowsEmptyBody,
              ),
            )
          : SizedBox.expand(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      constraints.maxWidth >= _workflowTwoColumnMinWidth
                      ? 2
                      : 1;
                  final cardWidth =
                      (constraints.maxWidth -
                          _workflowGridSpacing * (columns - 1)) /
                      columns;
                  return SingleChildScrollView(
                    key: const ValueKey<String>('workflows-list'),
                    padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
                    child: Wrap(
                      spacing: _workflowGridSpacing,
                      runSpacing: _workflowGridSpacing,
                      children: [
                        for (final workflow in snapshot.workflows)
                          SizedBox(
                            width: cardWidth,
                            child: AppearOnce(
                              child: RepaintBoundary(
                                child: _WorkflowCard(
                                  workflow: workflow,
                                  onOpen: () => _openEditor(
                                    context,
                                    controller,
                                    workflow: workflow,
                                  ),
                                  onDelete: () => _deleteWorkflow(
                                    context,
                                    controller,
                                    workflow,
                                  ),
                                  onExport: (format) =>
                                      _exportWorkflow(workflow, format),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }

  Future<void> _importWorkflow(WorkflowsController controller) async {
    if (_importing) return;
    setState(() => _importing = true);
    OpenHandDialogSession<void>? loadingDialog;
    try {
      final selected = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[_workflowYamlTypeGroup],
      );
      if (selected == null || !mounted) return;
      final extension = path.extension(selected.path).toLowerCase();
      if (extension != '.yaml' && extension != '.yml') {
        throw const WorkflowPortabilityException('请选择 .yaml 或 .yml 配置文件。');
      }
      loadingDialog = showOpenHandTrackedLoadingDialog(
        context: context,
        message: '正在读取并验证工作流配置…',
      );
      final source = await readBoundedFileString(
        File(selected.path),
        maxBytes: kMaxWorkflowImportBytes,
      );
      final imported = await decodeWorkflowYamlInIsolate(source);
      await loadingDialog.dismiss(logTag: '工作流导入', logAction: '关闭工作流导入加载弹窗');
      loadingDialog = null;
      if (!mounted) return;

      var name = imported.name.trim();
      if (_workflowNameExists(controller, name)) {
        final renamed = await _showImportRenameDialog(
          context,
          controller,
          name,
        );
        if (renamed == null || !mounted) return;
        name = renamed;
      }
      final now = DateTime.now().toUtc();
      final candidate = WorkflowDefinition(
        id: _workflowUuid.v4(),
        name: name,
        createdAt: now,
        updatedAt: now,
        nodes: imported.nodes,
        connections: imported.connections,
      );
      final saved = await controller.save(candidate);
      if (!mounted) return;
      if (!saved) {
        throw WorkflowPortabilityException(
          controller.errorMessage ?? '工作流写入本地数据库失败。',
        );
      }
      showOpenHandSuccessSnack(context, '工作流“$name”已成功导入。');
    } catch (error, stack) {
      silentLog('工作流导入', '导入工作流', error, stack);
      await loadingDialog?.dismiss(
        logTag: '工作流导入',
        logAction: '关闭失败的工作流导入加载弹窗',
      );
      if (mounted) await _showImportErrorDialog(context, error);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _exportWorkflow(
    WorkflowDefinition workflow,
    WorkflowExportFormat format,
  ) async {
    FileSaveLocation? location;
    try {
      location = await getSaveLocation(
        suggestedName: workflowExportFileName(workflow, format),
        acceptedTypeGroups: <XTypeGroup>[
          XTypeGroup(
            label: format.typeLabel,
            extensions: <String>[format.extension],
          ),
        ],
      );
    } catch (error, stack) {
      silentLog('工作流导出', '选择工作流导出位置', error, stack);
      if (mounted) {
        await _showImportErrorDialog(context, error, exporting: true);
      }
      return;
    }
    if (location == null || !mounted) return;
    final outputPath = _ensureExportExtension(location.path, format.extension);
    await showWorkflowExportProgressDialog(
      context: context,
      formatLabel: format.label,
      task: (onProgress) async {
        final artifact = await buildWorkflowExportArtifact(
          workflow,
          format,
          onProgress: onProgress,
        );
        await writeBytesFileAtomically(File(outputPath), artifact.bytes);
        onProgress(1, '文件写入完成。');
        return outputPath;
      },
    );
  }

  bool _workflowNameExists(WorkflowsController controller, String candidate) {
    final normalized = candidate.trim().toLowerCase();
    return controller.workflows.any(
      (workflow) => workflow.name.trim().toLowerCase() == normalized,
    );
  }

  Future<String?> _showImportRenameDialog(
    BuildContext context,
    WorkflowsController controller,
    String initialName,
  ) async {
    final nameController = TextEditingController(text: initialName);
    String? errorText;
    try {
      return await showOpenHandStatefulDialog<String>(
        context: context,
        builder: (dialogContext, setDialogState) => buildOpenHandAlertDialog(
          icon: const Icon(Icons.drive_file_rename_outline_rounded),
          title: const Text('工作流名称已存在'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '请输入一个新的工作流名称。原配置名称已为你保留在输入框中。',
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
                kOpenHandGap16,
                TextField(
                  key: const ValueKey<String>('workflow-import-name-field'),
                  controller: nameController,
                  autofocus: true,
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(120),
                  ],
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: '工作流名称',
                    errorText: errorText,
                    filled: true,
                    border: const OutlineInputBorder(
                      borderRadius: kOpenHandBorderRadius12,
                    ),
                  ),
                  onSubmitted: (_) => _submitImportedName(
                    dialogContext,
                    setDialogState,
                    nameController,
                    controller,
                    (value) => errorText = value,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              label: '取消',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            OpenHandDialogActionButton.primary(
              label: '确认导入',
              onPressed: () => _submitImportedName(
                dialogContext,
                setDialogState,
                nameController,
                controller,
                (value) => errorText = value,
              ),
            ),
          ],
        ),
      );
    } finally {
      nameController.dispose();
    }
  }

  void _submitImportedName(
    BuildContext dialogContext,
    StateSetter setDialogState,
    TextEditingController nameController,
    WorkflowsController controller,
    ValueChanged<String?> setError,
  ) {
    final name = nameController.text.trim();
    final error = name.isEmpty
        ? '工作流名称不能为空。'
        : _workflowNameExists(controller, name)
        ? '该名称仍然存在，请换一个名称。'
        : null;
    if (error != null) {
      setDialogState(() => setError(error));
      return;
    }
    Navigator.of(dialogContext).pop(name);
  }

  Future<void> _showImportErrorDialog(
    BuildContext context,
    Object error, {
    bool exporting = false,
  }) {
    final detail = error is WorkflowPortabilityException
        ? error.message
        : '$error';
    return showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = theme.colorScheme;
        return buildOpenHandAlertDialog(
          icon: Icon(Icons.error_outline_rounded, color: colors.error),
          title: Text(exporting ? '导出工作流失败' : '导入工作流失败'),
          content: buildOpenHandDialogConstrainedContent(
            maxWidth: kOpenHandDialogWidthCompact,
            maxHeight: 560,
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: kOpenHandBorderRadius14,
                ),
                child: SelectableText(
                  detail,
                  style: TextStyle(
                    color: colors.onErrorContainer,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            OpenHandDialogActionButton.secondary(
              icon: Icons.copy_all_outlined,
              label: '复制报错信息',
              onPressed: () => copyOpenHandTextToClipboard(
                context: dialogContext,
                text: detail,
                logTag: '工作流导入导出',
                logAction: exporting ? '复制工作流导出错误' : '复制工作流导入错误',
                successMessage: '报错信息已复制。',
              ),
            ),
            OpenHandDialogActionButton.primary(
              label: '关闭',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WorkflowsController controller, {
    WorkflowDefinition? workflow,
  }) async {
    final result = await showWorkflowEditorDialog(
      context,
      workflow: workflow,
      onRename: workflow == null ? null : controller.save,
    );
    if (result == null || !context.mounted) return;
    final saved = await controller.save(result);
    if (!context.mounted) return;
    if (saved) {
      showOpenHandInfoSnack(context, workflow == null ? '工作流已创建。' : '工作流已更新。');
    } else {
      showOpenHandInfoSnack(context, controller.errorMessage ?? '保存工作流失败。');
    }
  }

  Future<void> _deleteWorkflow(
    BuildContext context,
    WorkflowsController controller,
    WorkflowDefinition workflow,
  ) async {
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: '删除工作流',
      message: '将删除“${workflow.name}”及其全部节点配置。',
      confirmLabel: '删除',
    );
    if (!confirmed || !context.mounted) return;
    final deleted = await controller.delete(workflow.id);
    if (!context.mounted) return;
    showOpenHandInfoSnack(
      context,
      deleted ? '工作流已删除。' : controller.errorMessage ?? '删除工作流失败。',
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({
    required this.workflow,
    required this.onOpen,
    required this.onDelete,
    required this.onExport,
  });

  final WorkflowDefinition workflow;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final ValueChanged<WorkflowExportFormat> onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final actionButtonStyle = _workflowCardActionButtonStyle(theme);
    return Card(
      key: ValueKey<String>('workflow-card-${workflow.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: kOpenHandBorderRadius22,
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(kOpenHandRadius13),
                    ),
                    child: Icon(
                      Icons.account_tree_rounded,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  kOpenHandHGap12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workflow.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        kOpenHandGap3,
                        Text(
                          '${workflow.nodes.length} 个节点 · ${workflow.connections.length} 条连接',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedPopupMenuButton<WorkflowExportFormat>(
                    key: ValueKey<String>('workflow-export-${workflow.id}'),
                    tooltip: '导出工作流',
                    position: PopupMenuPosition.under,
                    style: actionButtonStyle,
                    buttonConstraints: const BoxConstraints.tightFor(
                      width: _workflowCardActionSize,
                      height: _workflowCardActionSize,
                    ),
                    icon: const Icon(Icons.file_download_outlined),
                    onSelected: onExport,
                    itemBuilder: (context) => [
                      for (final format in WorkflowExportFormat.values)
                        PopupMenuItem<WorkflowExportFormat>(
                          key: ValueKey<String>(
                            'workflow-export-option-${format.extension}',
                          ),
                          value: format,
                          child: _WorkflowExportMenuItem(format: format),
                        ),
                    ],
                  ),
                  kOpenHandHGap8,
                  IconButton.filledTonal(
                    key: ValueKey<String>('workflow-open-${workflow.id}'),
                    tooltip: '编辑工作流',
                    style: actionButtonStyle,
                    onPressed: onOpen,
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  kOpenHandHGap8,
                  IconButton.filledTonal(
                    key: ValueKey<String>('workflow-delete-${workflow.id}'),
                    tooltip: '删除工作流',
                    style: actionButtonStyle,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
              kOpenHandGap16,
              SizedBox(
                key: ValueKey<String>('workflow-minimap-${workflow.id}'),
                height: 128,
                child: WorkflowMiniMap(
                  nodes: workflow.nodes,
                  connections: workflow.connections,
                  annotations: workflow.annotations,
                ),
              ),
              kOpenHandGap14,
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 15,
                    color: colors.onSurfaceVariant,
                  ),
                  kOpenHandHGap6,
                  Expanded(
                    child: Text(
                      '更新于 ${_timeText(workflow.updatedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _workflowCardActionSize = 40;
const double _workflowCardActionEnabledAlpha = 0.74;

ButtonStyle _workflowCardActionButtonStyle(ThemeData theme) {
  return IconButton.styleFrom(
    shape: const CircleBorder(),
    padding: EdgeInsets.zero,
    minimumSize: const Size.square(_workflowCardActionSize),
    fixedSize: const Size.square(_workflowCardActionSize),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: _workflowCardActionEnabledAlpha,
    ),
    foregroundColor: theme.colorScheme.onSurfaceVariant,
  );
}

class _WorkflowExportMenuItem extends StatelessWidget {
  const _WorkflowExportMenuItem({required this.format});

  final WorkflowExportFormat format;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = switch (format) {
      WorkflowExportFormat.yaml => Icons.data_object_rounded,
      WorkflowExportFormat.png => Icons.image_outlined,
      WorkflowExportFormat.jpeg => Icons.photo_outlined,
      WorkflowExportFormat.svg => Icons.polyline_rounded,
    };
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: kOpenHandBorderRadius10,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 19, color: colors.onPrimaryContainer),
        ),
        kOpenHandHGap12,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(format.label),
            Text(
              '.${format.extension}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

String _ensureExportExtension(String filePath, String extension) {
  final expected = '.$extension';
  if (path.extension(filePath).toLowerCase() == expected) return filePath;
  return path.setExtension(filePath, expected);
}

String _timeText(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
