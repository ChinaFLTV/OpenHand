import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../model/workflow_definition.dart';
import '../workflows_controller.dart';
import 'workflow_editor_dialog.dart';

class WorkflowsView extends StatelessWidget {
  const WorkflowsView({super.key});

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
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1180
                    ? 3
                    : constraints.maxWidth >= 760
                    ? 2
                    : 1;
                const gap = 14.0;
                final width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 2, bottom: 20),
                  child: Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: snapshot.workflows
                        .map(
                          (workflow) => SizedBox(
                            width: width,
                            child: AppearOnce(
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
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WorkflowsController controller, {
    WorkflowDefinition? workflow,
  }) async {
    final result = await showWorkflowEditorDialog(context, workflow: workflow);
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
  });

  final WorkflowDefinition workflow;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodeKinds = workflow.nodes.map((node) => node.kind).toSet();
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          theme.colorScheme.primaryContainer,
                          theme.colorScheme.tertiaryContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(kOpenHandRadius13),
                    ),
                    child: Icon(
                      Icons.account_tree_rounded,
                      color: theme.colorScheme.onPrimaryContainer,
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
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '删除工作流',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
              kOpenHandGap16,
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: nodeKinds.isEmpty
                    ? <Widget>[const Chip(label: Text('空工作流'))]
                    : nodeKinds
                          .map(
                            (kind) => Chip(
                              avatar: Icon(_kindIcon(kind), size: 16),
                              label: Text(_kindLabel(kind)),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(growable: false),
              ),
              kOpenHandGap14,
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  kOpenHandHGap6,
                  Expanded(
                    child: Text(
                      '更新于 ${_timeText(workflow.updatedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    '打开画布',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  kOpenHandHGap4,
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 17,
                    color: theme.colorScheme.primary,
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

String _kindLabel(WorkflowNodeKind kind) => switch (kind) {
  WorkflowNodeKind.condition => '条件分支',
  WorkflowNodeKind.loop => '循环',
  WorkflowNodeKind.iteration => '迭代',
  WorkflowNodeKind.llm => 'LLM',
  WorkflowNodeKind.httpRequest => 'HTTP',
};

IconData _kindIcon(WorkflowNodeKind kind) => switch (kind) {
  WorkflowNodeKind.condition => Icons.call_split_rounded,
  WorkflowNodeKind.loop => Icons.loop_rounded,
  WorkflowNodeKind.iteration => Icons.view_week_outlined,
  WorkflowNodeKind.llm => Icons.auto_awesome_rounded,
  WorkflowNodeKind.httpRequest => Icons.language_rounded,
};

String _timeText(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
