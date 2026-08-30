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
          : ListView.separated(
              key: const ValueKey<String>('workflows-list'),
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
              itemCount: snapshot.workflows.length,
              separatorBuilder: (_, _) => kOpenHandGap14,
              itemBuilder: (context, index) {
                final workflow = snapshot.workflows[index];
                return AppearOnce(
                  child: RepaintBoundary(
                    child: _WorkflowCard(
                      workflow: workflow,
                      onOpen: () =>
                          _openEditor(context, controller, workflow: workflow),
                      onDelete: () =>
                          _deleteWorkflow(context, controller, workflow),
                    ),
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
    final colors = theme.colorScheme;
    final nodeKinds = workflow.nodes.map((node) => node.kind).toSet();
    final actionButtonStyle = IconButton.styleFrom(shape: const CircleBorder());
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
                  IconButton.filledTonal(
                    key: ValueKey<String>('workflow-open-${workflow.id}'),
                    tooltip: '打开画布',
                    style: actionButtonStyle,
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_rounded),
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

String _kindLabel(WorkflowNodeKind kind) => switch (kind) {
  WorkflowNodeKind.start => '开始',
  WorkflowNodeKind.condition => '条件分支',
  WorkflowNodeKind.loop => '循环',
  WorkflowNodeKind.iteration => '迭代',
  WorkflowNodeKind.parameterAssignment => '参数赋值',
  WorkflowNodeKind.listOperation => '列表操作',
  WorkflowNodeKind.codeExecution => '代码执行',
  WorkflowNodeKind.humanIntervention => '人工介入',
  WorkflowNodeKind.loopExit => '退出循环',
  WorkflowNodeKind.llm => 'LLM',
  WorkflowNodeKind.httpRequest => 'HTTP',
  WorkflowNodeKind.end => '结束',
};

IconData _kindIcon(WorkflowNodeKind kind) => switch (kind) {
  WorkflowNodeKind.start => Icons.play_arrow_rounded,
  WorkflowNodeKind.condition => Icons.call_split_rounded,
  WorkflowNodeKind.loop => Icons.loop_rounded,
  WorkflowNodeKind.iteration => Icons.view_week_outlined,
  WorkflowNodeKind.parameterAssignment => Icons.assignment_turned_in_outlined,
  WorkflowNodeKind.listOperation => Icons.filter_list_rounded,
  WorkflowNodeKind.codeExecution => Icons.code_rounded,
  WorkflowNodeKind.humanIntervention => Icons.front_hand_outlined,
  WorkflowNodeKind.loopExit => Icons.exit_to_app_rounded,
  WorkflowNodeKind.llm => Icons.auto_awesome_rounded,
  WorkflowNodeKind.httpRequest => Icons.language_rounded,
  WorkflowNodeKind.end => Icons.stop_rounded,
};

String _timeText(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
