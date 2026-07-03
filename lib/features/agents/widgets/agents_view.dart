import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/model/cron_config.dart';
import '../../../app/state/settings_controller.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/hover_lift.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/util/localized_text.dart';
import '../../crons/index.dart';
import '../../plugin_service/index.dart';

class AgentsView extends StatefulWidget {
  const AgentsView({
    super.key,
    required this.onOpenPlugins,
    required this.onOpenCrons,
    required this.onOpenSettings,
    required this.onCreateThreadRequested,
  });

  final VoidCallback onOpenPlugins;
  final VoidCallback onOpenCrons;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onCreateThreadRequested;

  @override
  State<AgentsView> createState() => _AgentsViewState();
}

class _AgentsViewState extends State<AgentsView> {
  static const PluginInfo _hermesFallbackPlugin = PluginInfo(
    id: PluginCatalogIds.hermesAgent,
    name: 'Hermes Agent',
    description: 'Hermes Agent 运行时，用于智能体编排、自我学习与技能沉淀',
    status: PluginStatus.notInstalled,
    dependencies: <String>[PluginCatalogIds.nodejs],
  );

  @override
  Widget build(BuildContext context) {
    final isZh = openHandIsChineseLocale(context);
    final pluginController = context.watch<PluginServiceController>();
    final settings = context.watch<SettingsController>();
    final crons = context.watch<CronsController>();
    final plugin =
        pluginController.pluginById(PluginCatalogIds.hermesAgent) ??
        _hermesFallbackPlugin;

    return FeaturePageShell(
      title: _agentText(context, zh: '智能体', en: 'Agents'),
      subtitle: _agentText(
        context,
        zh: '管理基于 Hermes Agent 的本地智能体运行时、线程模板与后台自学习能力。',
        en: 'Manage the local Hermes Agent runtime, thread template, and background self-learning.',
      ),
      actions: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.end,
        children: [
          FilledButton.tonalIcon(
            onPressed: pluginController.isOperating
                ? null
                : () => pluginController.rescan(),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_agentText(context, zh: '刷新状态', en: 'Refresh')),
          ),
          OutlinedButton.icon(
            onPressed: widget.onOpenPlugins,
            icon: const Icon(Icons.power_rounded),
            label: Text(_agentText(context, zh: '插件页管理', en: 'Plugins')),
          ),
        ],
      ),
      successSignal: pluginController.operationSuccessSignal,
      notices: [
        if (pluginController.errorMessage != null &&
            pluginController.plugins.isNotEmpty)
          FeatureStateCard.inline(
            icon: Icons.warning_amber_rounded,
            tone: FeatureStateTone.secondary,
            title: _agentText(
              context,
              zh: '插件状态未完全刷新',
              en: 'Plugin scan warning',
            ),
            body: pluginController.errorMessage!,
          ),
        if (!plugin.isInstalled)
          FeatureStateCard.inline(
            icon: Icons.auto_awesome_outlined,
            tone: FeatureStateTone.secondary,
            title: _agentText(
              context,
              zh: 'Hermes Agent 尚未安装',
              en: 'Hermes Agent is not installed',
            ),
            body: _agentText(
              context,
              zh: '请在插件页安装 Hermes Agent；智能体面板会自动同步运行时状态。',
              en: 'Install Hermes Agent from the Plugins page. This panel will sync the runtime status automatically.',
            ),
          ),
      ],
      body: _buildBody(
        context,
        pluginController: pluginController,
        plugin: plugin,
        settings: settings,
        crons: crons,
        isZh: isZh,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required PluginServiceController pluginController,
    required PluginInfo plugin,
    required SettingsController settings,
    required CronsController crons,
    required bool isZh,
  }) {
    if (pluginController.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pluginController.errorMessage != null &&
        pluginController.plugins.isEmpty) {
      return FeatureStateCard.centered(
        key: const ValueKey<String>('agents-plugin-error'),
        icon: Icons.error_outline_rounded,
        tone: FeatureStateTone.error,
        title: _agentText(context, zh: '智能体状态扫描失败', en: 'Agent scan failed'),
        body: pluginController.errorMessage!,
        action: OpenHandDialogActionButton.primary(
          onPressed: () => pluginController.rescan(),
          label: _agentText(context, zh: '重试', en: 'Retry'),
        ),
      );
    }

    final cron = _selfLearningCron(crons.entries);
    return ListView(
      key: const ValueKey<String>('agents-list'),
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
      cacheExtent: 600,
      children: [
        SettingsAwareAppearOnce(
          key: const ValueKey<String>('agent-hermes-runtime'),
          child: _AgentRuntimeCard(
            plugin: plugin,
            pluginController: pluginController,
            onOpenPlugins: widget.onOpenPlugins,
            onDetails: () => _showPluginDetails(context, plugin),
            onCheckUpdate: () => _checkHermesUpdate(context, pluginController),
          ),
        ),
        const SizedBox(height: 14),
        SettingsAwareAppearOnce(
          key: const ValueKey<String>('agent-hermes-talker'),
          child: _AgentCard(
            icon: Icons.record_voice_over_rounded,
            iconColor: plugin.isInstalled
                ? OpenHandStatusColors.success
                : Theme.of(context).colorScheme.error,
            title: 'Hermes Talker',
            subtitle: _agentText(
              context,
              zh: '面向长期会话、记忆沉淀与技能复用的智能体线程模板。',
              en: 'Agent thread template for long-running dialogue, memory, and reusable skills.',
            ),
            chips: [
              _AgentChipData(
                icon: Icons.account_tree_rounded,
                label: _agentText(context, zh: '线程模板', en: 'Thread template'),
              ),
              _AgentChipData(
                icon: Icons.memory_rounded,
                label: _agentText(context, zh: 'Memory', en: 'Memory'),
              ),
              _AgentChipData(
                icon: Icons.extension_rounded,
                label: _agentText(
                  context,
                  zh: 'Skill Manager',
                  en: 'Skill Manager',
                ),
              ),
              _AgentChipData(
                icon: plugin.isInstalled
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                label: plugin.isInstalled
                    ? _agentText(context, zh: '运行时就绪', en: 'Runtime ready')
                    : _agentText(context, zh: '等待运行时', en: 'Runtime required'),
              ),
            ],
            actions: [
              FilledButton.tonalIcon(
                onPressed: widget.onCreateThreadRequested,
                icon: const Icon(Icons.add_comment_rounded, size: 18),
                label: Text(_agentText(context, zh: '新建线程', en: 'New thread')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SettingsAwareAppearOnce(
          key: const ValueKey<String>('agent-self-learning'),
          child: _AgentCard(
            icon: Icons.sync_rounded,
            iconColor: settings.selfLearningEnabled
                ? OpenHandStatusColors.success
                : Theme.of(context).colorScheme.onSurfaceVariant,
            title: _agentText(context, zh: '后台自学习', en: 'Self-learning'),
            subtitle: _agentText(
              context,
              zh: '系统 Cron 每 5 分钟扫描 Hermes Talker 会话，派发受限子智能体更新记忆与技能。',
              en: 'A system cron scans Hermes Talker sessions every 5 minutes and dispatches restricted sub-agents to update memory and skills.',
            ),
            chips: [
              _AgentChipData(
                icon: settings.selfLearningEnabled
                    ? Icons.toggle_on_rounded
                    : Icons.toggle_off_outlined,
                label: settings.selfLearningEnabled
                    ? _agentText(context, zh: '调度开启', en: 'Scheduler on')
                    : _agentText(context, zh: '调度关闭', en: 'Scheduler off'),
              ),
              _AgentChipData(
                icon: Icons.groups_rounded,
                label: _agentText(
                  context,
                  zh: '并发 ${settings.selfLearningConcurrency}',
                  en: 'Concurrency ${settings.selfLearningConcurrency}',
                ),
              ),
              _AgentChipData(
                icon: Icons.speed_rounded,
                label: '${settings.selfLearningStreamFlushIntervalMs} ms',
              ),
              if (cron != null)
                _AgentChipData(
                  icon: _cronStatusIcon(cron),
                  label: _agentText(
                    context,
                    zh: '${cron.cronExpression} · ${cron.status.label(true)}',
                    en: '${cron.cronExpression} · ${cron.status.label(false)}',
                  ),
                ),
              _AgentChipData(
                icon: settings.showSelfLearningMessages
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                label: settings.showSelfLearningMessages
                    ? _agentText(context, zh: '卡片可见', en: 'Cards visible')
                    : _agentText(context, zh: '卡片隐藏', en: 'Cards hidden'),
              ),
            ],
            actions: [
              OutlinedButton.icon(
                onPressed: widget.onOpenCrons,
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: const Text('Crons'),
              ),
              FilledButton.tonalIcon(
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(_agentText(context, zh: '调整设置', en: 'Settings')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  CronEntry? _selfLearningCron(List<CronEntry> entries) {
    for (final entry in entries) {
      if (entry.id == CronsController.selfLearningSystemEntryId) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _checkHermesUpdate(
    BuildContext context,
    PluginServiceController controller,
  ) async {
    final refreshed = await controller.checkPluginUpdate(
      PluginCatalogIds.hermesAgent,
    );
    if (!context.mounted) return;
    final latest =
        controller.pluginById(PluginCatalogIds.hermesAgent) ?? refreshed;
    final message = latest == null
        ? (controller.errorMessage ??
              _agentText(context, zh: '检查更新失败', en: 'Update check failed'))
        : latest.hasUpdate && latest.latestVersion != null
        ? _agentText(
            context,
            zh: '发现 Hermes Agent 新版本：${latest.latestVersion}',
            en: 'Hermes Agent update available: ${latest.latestVersion}',
          )
        : _agentText(
            context,
            zh: 'Hermes Agent 已是最新状态。',
            en: 'Hermes Agent is up to date.',
          );
    OpenHandSnackBar.flash(context, message, postFrame: true);
  }

  void _showPluginDetails(BuildContext context, PluginInfo plugin) {
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => _AgentPluginDetailsDialog(plugin: plugin),
    );
  }

  static IconData _cronStatusIcon(CronEntry cron) {
    if (!cron.enabled) return Icons.pause_circle_outline_rounded;
    return switch (cron.status) {
      CronJobStatus.running => Icons.play_circle_outline_rounded,
      CronJobStatus.paused => Icons.pause_circle_outline_rounded,
      CronJobStatus.failed ||
      CronJobStatus.error => Icons.error_outline_rounded,
      CronJobStatus.idle => Icons.schedule_rounded,
    };
  }
}

class _AgentRuntimeCard extends StatelessWidget {
  const _AgentRuntimeCard({
    required this.plugin,
    required this.pluginController,
    required this.onOpenPlugins,
    required this.onDetails,
    required this.onCheckUpdate,
  });

  final PluginInfo plugin;
  final PluginServiceController pluginController;
  final VoidCallback onOpenPlugins;
  final VoidCallback onDetails;
  final VoidCallback onCheckUpdate;

  @override
  Widget build(BuildContext context) {
    final checking = pluginController.checkingPluginId == plugin.id;
    final color = _pluginColor(context, plugin);
    return _AgentCard(
      icon: Icons.auto_awesome_rounded,
      iconColor: color,
      title: plugin.name,
      subtitle: plugin.description,
      chips: [
        _AgentChipData(
          icon: _pluginStatusIcon(plugin),
          label: _pluginStatus(context, plugin),
        ),
        const _AgentChipData(
          icon: Icons.inventory_2_outlined,
          label: 'hermes-agent',
          monospace: true,
        ),
        if (plugin.installedVersion?.trim().isNotEmpty ?? false)
          _AgentChipData(
            icon: Icons.tag_rounded,
            label: _agentText(
              context,
              zh: '版本 ${plugin.installedVersion}',
              en: 'Version ${plugin.installedVersion}',
            ),
          ),
        if (plugin.hasUpdate && plugin.latestVersion != null)
          _AgentChipData(
            icon: Icons.new_releases_outlined,
            label: _agentText(
              context,
              zh: '可更新到 ${plugin.latestVersion}',
              en: 'Update ${plugin.latestVersion}',
            ),
          ),
        if (plugin.installPath?.trim().isNotEmpty ?? false)
          _AgentChipData(
            icon: Icons.folder_outlined,
            label: plugin.installPath!,
            monospace: true,
          ),
      ],
      actions: [
        IconButton.filledTonal(
          tooltip: _agentText(context, zh: '详情', en: 'Details'),
          onPressed: onDetails,
          icon: const Icon(Icons.info_outline_rounded, size: 18),
        ),
        IconButton.filledTonal(
          tooltip: _agentText(context, zh: '检查更新', en: 'Check updates'),
          onPressed:
              plugin.isInstalled && !pluginController.isOperating && !checking
              ? onCheckUpdate
              : null,
          icon: checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
        ),
        FilledButton.tonalIcon(
          onPressed: onOpenPlugins,
          icon: const Icon(Icons.power_rounded, size: 18),
          label: Text(_agentText(context, zh: '插件页管理', en: 'Manage')),
        ),
      ],
    );
  }

  static Color _pluginColor(BuildContext context, PluginInfo plugin) {
    return switch (plugin.status) {
      PluginStatus.installed =>
        plugin.enabled
            ? OpenHandStatusColors.success
            : Theme.of(context).colorScheme.onSurfaceVariant,
      PluginStatus.error => Theme.of(context).colorScheme.error,
      PluginStatus.installing ||
      PluginStatus.updating ||
      PluginStatus.uninstalling => OpenHandStatusColors.warning,
      PluginStatus.notInstalled => Theme.of(context).colorScheme.error,
    };
  }

  static IconData _pluginStatusIcon(PluginInfo plugin) {
    return switch (plugin.status) {
      PluginStatus.installed =>
        plugin.enabled ? Icons.check_circle_rounded : Icons.toggle_off_outlined,
      PluginStatus.error => Icons.error_outline_rounded,
      PluginStatus.installing => Icons.download_rounded,
      PluginStatus.updating => Icons.system_update_alt_rounded,
      PluginStatus.uninstalling => Icons.delete_outline_rounded,
      PluginStatus.notInstalled => Icons.download_for_offline_outlined,
    };
  }

  static String _pluginStatus(BuildContext context, PluginInfo plugin) {
    return switch (plugin.status) {
      PluginStatus.installed =>
        plugin.enabled
            ? _agentText(context, zh: '已安装', en: 'Installed')
            : _agentText(context, zh: '已安装 · 已禁用', en: 'Installed · disabled'),
      PluginStatus.notInstalled => _agentText(
        context,
        zh: '未安装',
        en: 'Not installed',
      ),
      PluginStatus.installing => _agentText(
        context,
        zh: '安装中',
        en: 'Installing',
      ),
      PluginStatus.updating => _agentText(context, zh: '更新中', en: 'Updating'),
      PluginStatus.uninstalling => _agentText(
        context,
        zh: '卸载中',
        en: 'Uninstalling',
      ),
      PluginStatus.error => _agentText(context, zh: '异常', en: 'Error'),
    };
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.chips,
    required this.actions,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<_AgentChipData> chips;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return HoverLift(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final header = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          alignment: Alignment.center,
                          child: Icon(icon, color: iconColor, size: 26),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: _AgentStatusDot(color: iconColor),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final actionBar = Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 6,
                  children: actions,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (compact) ...[
                      header,
                      const SizedBox(height: 14),
                      Align(alignment: Alignment.centerLeft, child: actionBar),
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: header),
                          const SizedBox(width: 12),
                          actionBar,
                        ],
                      ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: chips
                            .map((chip) => _AgentStatusChip(data: chip))
                            .toList(growable: false),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentChipData {
  const _AgentChipData({
    required this.icon,
    required this.label,
    this.monospace = false,
  });

  final IconData icon;
  final String label;
  final bool monospace;
}

class _AgentStatusChip extends StatelessWidget {
  const _AgentStatusChip({required this.data});

  final _AgentChipData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.58)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              data.label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: data.monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentStatusDot extends StatelessWidget {
  const _AgentStatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: surface,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _AgentPluginDetailsDialog extends StatelessWidget {
  const _AgentPluginDetailsDialog({required this.plugin});

  final PluginInfo plugin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <MapEntry<String, String>>[
      MapEntry('ID', plugin.id),
      MapEntry(_agentText(context, zh: '名称', en: 'Name'), plugin.name),
      MapEntry(_agentText(context, zh: '状态', en: 'Status'), plugin.status.name),
      if (plugin.installedVersion?.trim().isNotEmpty ?? false)
        MapEntry(
          _agentText(context, zh: '版本', en: 'Version'),
          plugin.installedVersion!,
        ),
      if (plugin.latestVersion?.trim().isNotEmpty ?? false)
        MapEntry(
          _agentText(context, zh: '最新版本', en: 'Latest'),
          plugin.latestVersion!,
        ),
      if (plugin.installPath?.trim().isNotEmpty ?? false)
        MapEntry(
          _agentText(context, zh: '路径', en: 'Path'),
          plugin.installPath!,
        ),
      for (final entry in plugin.metadata.entries)
        if ('${entry.value}'.trim().isNotEmpty)
          MapEntry(entry.key, '${entry.value}'),
    ];
    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 620,
      maxHeight: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.auto_awesome_rounded,
            title: _agentText(
              context,
              zh: 'Hermes Agent 详情',
              en: 'Hermes Agent Details',
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(20),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final row = rows[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.key,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      row.value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: row.key == 'ID' ? 'monospace' : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Align(
              alignment: Alignment.centerRight,
              child: OpenHandDialogActionButton.primary(
                onPressed: () => Navigator.of(context).pop(),
                label: _agentText(context, zh: '关闭', en: 'Close'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _agentText(
  BuildContext context, {
  required String zh,
  required String en,
}) {
  return openHandLocalizedText(context, zh: zh, en: en);
}
