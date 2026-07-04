import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_inline_notice.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../ai/index.dart' show AiPromptTemplatePolicies;
import '../../mcp/index.dart';
import '../../thread_template_runtime/index.dart';
import '../model/plugin_info.dart';
import '../plugin_service_controller.dart';

void _showPluginSnackBar(BuildContext context, SnackBar snackBar) {
  OpenHandSnackBar.showInContext(context, snackBar);
}

enum _PluginServiceAction { install, update, uninstall }

extension _PluginServiceActionL10n on _PluginServiceAction {
  String label(AppLocalizations l10n) {
    return switch (this) {
      _PluginServiceAction.install => l10n.pluginServiceActionInstall,
      _PluginServiceAction.update => l10n.pluginServiceActionUpdate,
      _PluginServiceAction.uninstall => l10n.pluginServiceActionUninstall,
    };
  }
}

extension _PluginStatusL10n on PluginStatus {
  String label(AppLocalizations l10n) {
    return switch (this) {
      PluginStatus.installed => l10n.pluginServiceStatusInstalled,
      PluginStatus.notInstalled => l10n.pluginServiceStatusNotInstalled,
      PluginStatus.installing => l10n.pluginServiceStatusInstalling,
      PluginStatus.updating => l10n.pluginServiceStatusUpdating,
      PluginStatus.uninstalling => l10n.pluginServiceStatusUninstalling,
      PluginStatus.error => l10n.pluginServiceStatusError,
    };
  }
}

String _localizedPluginDescription(AppLocalizations l10n, PluginInfo plugin) {
  return switch (plugin.id) {
    PluginCatalogIds.nodejs => l10n.pluginServiceDescriptionNodejs,
    PluginCatalogIds.playwright => l10n.pluginServiceDescriptionPlaywright,
    PluginCatalogIds.hermesAgent => l10n.pluginServiceDescriptionHermesAgent,
    'python' => l10n.pluginServiceDescriptionPython,
    'pip' => l10n.pluginServiceDescriptionPip,
    'java' => l10n.pluginServiceDescriptionJava,
    'frida' => l10n.pluginServiceDescriptionFrida,
    'mitmproxy' => l10n.pluginServiceDescriptionMitmproxy,
    'apktool' => l10n.pluginServiceDescriptionApktool,
    'jadx' => l10n.pluginServiceDescriptionJadx,
    'radare2' => l10n.pluginServiceDescriptionRadare2,
    'blutter' => l10n.pluginServiceDescriptionBlutter,
    'doldrums' => l10n.pluginServiceDescriptionDoldrums,
    'anything_analyzer' => l10n.pluginServiceDescriptionAnythingAnalyzer,
    'docker' => l10n.pluginServiceDescriptionDocker,
    'qdrant' => l10n.pluginServiceDescriptionQdrant,
    _ => plugin.description,
  };
}

String _localizedTemplateDependencyLabel(
  AppLocalizations l10n,
  TemplateRuntimeDependencySpec spec,
) {
  return switch (spec.templateId) {
    AiPromptTemplatePolicies.webReverseExpertTemplateId =>
      l10n.pluginServiceTemplateWebReverseExpert,
    AiPromptTemplatePolicies.androidReverseExpertTemplateId =>
      l10n.pluginServiceTemplateAndroidReverseExpert,
    AiPromptTemplatePolicies.hermesTalkerTemplateId =>
      l10n.pluginServiceTemplateHermesTalker,
    _ => spec.labelEn,
  };
}

String _localizedDetailLabel(AppLocalizations l10n, String key) {
  return switch (key) {
    'processors' => l10n.pluginServiceDetailProcessors,
    'install_path' => l10n.pluginServiceDetailInstallPath,
    'current_version' => l10n.pluginServiceDetailCurrentVersion,
    'latest_version' => l10n.pluginServiceDetailLatestVersion,
    'bound_python' => l10n.pluginServiceDetailBoundPython,
    'desktop_app_detected' => l10n.pluginServiceDetailDesktopAppDetected,
    'daemon_running' => l10n.pluginServiceDetailDaemonRunning,
    'cli_available' => l10n.pluginServiceDetailCliAvailable,
    'context' => l10n.pluginServiceDetailDockerContext,
    'server_version' => l10n.pluginServiceDetailServerVersion,
    'docker_os' => l10n.pluginServiceDetailDockerOs,
    'docker_root_dir' => l10n.pluginServiceDetailDockerRootDir,
    'daemon_name' => l10n.pluginServiceDetailDaemonName,
    'os_type' => l10n.pluginServiceDetailOsType,
    'architecture' => l10n.pluginServiceDetailArchitecture,
    'compose_version' => l10n.pluginServiceDetailComposeVersion,
    'docker_daemon_running' => l10n.pluginServiceDetailDockerDaemonRunning,
    'openhand_managed' => l10n.pluginServiceDetailOpenHandManaged,
    'container_id' => l10n.pluginServiceDetailContainerId,
    'container_name' => l10n.pluginServiceDetailContainerName,
    'container_status' => l10n.pluginServiceDetailContainerStatus,
    'running' => l10n.pluginServiceDetailRunning,
    'started_at' => l10n.pluginServiceDetailStartedAt,
    'finished_at' => l10n.pluginServiceDetailFinishedAt,
    'restart_count' => l10n.pluginServiceDetailRestartCount,
    'exit_code' => l10n.pluginServiceDetailExitCode,
    'image' => l10n.pluginServiceDetailImage,
    'image_id' => l10n.pluginServiceDetailImageId,
    'ports' => l10n.pluginServiceDetailPorts,
    'restart_policy' => l10n.pluginServiceDetailRestartPolicy,
    'rest_endpoint' => l10n.pluginServiceDetailRestEndpoint,
    'grpc_endpoint' => l10n.pluginServiceDetailGrpcEndpoint,
    'data_directory' => l10n.pluginServiceDetailDataDirectory,
    'health_response' => l10n.pluginServiceDetailHealthResponse,
    'health_title' => l10n.pluginServiceDetailHealthTitle,
    'collection_count' => l10n.pluginServiceDetailCollectionCount,
    _ => key,
  };
}

String _localizedDetailValue(AppLocalizations l10n, Object? value) {
  if (value is bool) {
    return value ? l10n.qdrantValueYes : l10n.qdrantValueNo;
  }
  if (value is Iterable) {
    return value.map((item) => '$item').join(', ');
  }
  return '$value';
}

class PluginServiceView extends StatefulWidget {
  const PluginServiceView({super.key});

  @override
  State<PluginServiceView> createState() => _PluginServiceViewState();
}

class _PluginServiceViewState extends State<PluginServiceView> {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PluginServiceController>();
    final l10n = AppLocalizations.of(context)!;

    final actions = Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      children: [
        FilledButton.tonalIcon(
          onPressed: controller.isOperating ? null : controller.rescan,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.pluginServiceRescan),
        ),
      ],
    );

    return FeaturePageShell(
      title: l10n.pluginServiceTitle,
      subtitle: l10n.pluginServiceSubtitle,
      actions: actions,
      successSignal: controller.operationSuccessSignal,
      body: _buildBody(context, controller),
      notices: [
        if (controller.errorMessage != null && controller.plugins.isNotEmpty)
          OpenHandInlineNoticeFactory.error(
            context,
            controller.errorMessage!,
            copyText: controller.errorMessage,
            onDismiss: controller.clearError,
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, PluginServiceController controller) {
    final l10n = AppLocalizations.of(context)!;
    if (controller.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              l10n.pluginServiceScanning,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (controller.errorMessage != null && controller.plugins.isEmpty) {
      return FeatureStateCard.centered(
        icon: Icons.error_outline_rounded,
        tone: FeatureStateTone.error,
        title: l10n.pluginServiceScanFailed,
        body: controller.errorMessage!,
        action: TextButton.icon(
          onPressed: controller.rescan,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(l10n.commonRetry),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
      children: [
        for (final plugin in controller.plugins) ...[
          _PluginCard(plugin: plugin, controller: controller),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PluginStatusBadge extends StatelessWidget {
  const _PluginStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PluginTemplateBadge extends StatelessWidget {
  const _PluginTemplateBadge({required this.spec});

  final TemplateRuntimeDependencySpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _localizedTemplateDependencyLabel(l10n, spec),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 插件卡片
// ─────────────────────────────────────────────────────────────────────────────

class _PluginCard extends StatelessWidget {
  const _PluginCard({required this.plugin, required this.controller});

  final PluginInfo plugin;
  final PluginServiceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final stateColor = switch (plugin.status) {
      PluginStatus.installed => OpenHandStatusColors.success,
      PluginStatus.error => theme.colorScheme.error,
      PluginStatus.installing ||
      PluginStatus.updating ||
      PluginStatus.uninstalling => OpenHandStatusColors.warning,
      PluginStatus.notInstalled => theme.colorScheme.onSurfaceVariant,
    };
    final statusLabel = plugin.status.label(l10n);
    final pluginIcon = switch (plugin.id) {
      'nodejs' => Icons.javascript_rounded,
      'python' => Icons.code_rounded,
      'pip' => Icons.inventory_2_rounded,
      'playwright' => Icons.theaters_rounded,
      PluginCatalogIds.hermesAgent => Icons.auto_awesome_rounded,
      'java' => Icons.coffee_rounded,
      'frida' => Icons.bug_report_rounded,
      'mitmproxy' => Icons.lan_rounded,
      'apktool' => Icons.archive_rounded,
      'jadx' => Icons.data_object_rounded,
      'docker' => Icons.view_in_ar_rounded,
      'qdrant' => Icons.hub_rounded,
      _ => Icons.extension_rounded,
    };

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 600;
                final title = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            pluginIcon,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: _StatusDot(color: stateColor),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                plugin.name,
                                style: theme.textTheme.titleLarge,
                              ),
                              _PluginStatusBadge(
                                label: statusLabel,
                                color: stateColor,
                              ),
                              for (final spec
                                  in TemplateRuntimeDependencyRegistry.specsForPlugin(
                                    plugin.id,
                                  ))
                                _PluginTemplateBadge(spec: spec),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _localizedPluginDescription(l10n, plugin),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final actions = _buildActions(context);
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 14), actions],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 16),
                    actions,
                  ],
                );
              },
            ),
            if (plugin.isInstalled) ...[
              const SizedBox(height: 14),
              _PluginMetaRow(plugin: plugin),
            ],
            if (plugin.dependencies.isNotEmpty) ...[
              const SizedBox(height: 10),
              _DependencyRow(plugin: plugin, controller: controller),
            ],
            OpenHandInlineNoticeSlot(
              child:
                  plugin.status == PluginStatus.error &&
                      plugin.errorMessage != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: OpenHandInlineNoticeFactory.error(
                          context,
                          plugin.errorMessage!,
                          copyText: plugin.errorMessage,
                          onDismiss: () =>
                              controller.clearPluginError(plugin.id),
                          messageStyle: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isCheckingUpdate = controller.checkingPluginId == plugin.id;
    final isBusy = plugin.isBusy || controller.isOperating || isCheckingUpdate;
    final hasMcp = plugin.id == 'playwright';

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        // 详情
        IconButton.filledTonal(
          tooltip: l10n.commonDetails,
          onPressed: () => _showDetailDialog(context),
          icon: const Icon(Icons.info_outline_rounded, size: 18),
        ),
        // 检查更新
        if (plugin.isInstalled)
          IconButton.filledTonal(
            tooltip: l10n.pluginServiceCheckUpdates,
            onPressed: isBusy ? null : () => _checkUpdate(context),
            icon: isCheckingUpdate
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.refresh_rounded, size: 18),
          ),
        // MCP 服务（仅 Playwright）
        if (hasMcp && plugin.isInstalled)
          IconButton.filledTonal(
            tooltip: l10n.pluginServiceMcpService,
            onPressed: isBusy ? null : () => _showMcpActions(context),
            icon: const Icon(Icons.hub_outlined, size: 18),
          ),
        // 启用/禁用
        if (plugin.isInstalled)
          IconButton.filledTonal(
            tooltip: plugin.enabled
                ? l10n.pluginServiceActionDisable
                : l10n.pluginServiceActionEnable,
            onPressed: isBusy
                ? null
                : () => controller.toggleEnabled(
                    plugin.id,
                    enabled: !plugin.enabled,
                  ),
            icon: Icon(
              plugin.enabled
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_outlined,
              size: 20,
              color: plugin.enabled ? OpenHandStatusColors.success : null,
            ),
          ),
        // 安装
        if (plugin.status == PluginStatus.notInstalled)
          IconButton.filled(
            tooltip: l10n.pluginServiceActionInstall,
            onPressed: isBusy ? null : () => _doInstall(context),
            icon: const Icon(Icons.download_rounded, size: 18),
          ),
        // 更新
        if (plugin.isInstalled && plugin.hasUpdate)
          IconButton.filledTonal(
            tooltip: l10n.pluginServiceActionUpdate,
            onPressed: isBusy ? null : () => _doUpdate(context),
            icon: const Icon(Icons.system_update_alt_rounded, size: 18),
          ),
        // 卸载
        if (plugin.isInstalled && plugin.supportsUninstall)
          IconButton.filledTonal(
            tooltip: l10n.pluginServiceActionUninstall,
            onPressed: isBusy ? null : () => _doUninstall(context),
            style: IconButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        // 操作中
        if (plugin.isBusy &&
            !plugin.isInstalled &&
            plugin.status != PluginStatus.notInstalled)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
      ],
    );
  }

  Future<void> _doInstall(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    for (final depId in plugin.dependencies) {
      final dep = controller.pluginById(depId);
      if (dep == null || !dep.isInstalled) {
        _showPluginSnackBar(
          context,
          SnackBar(
            content: Text(
              l10n.pluginServiceInstallDependencyRequired(dep?.name ?? depId),
            ),
          ),
        );
        return;
      }
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.pluginServiceInstallConfirmTitle(plugin.name),
      message: l10n.pluginServiceInstallConfirmMessage(plugin.name),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.pluginServiceActionInstall,
    );
    if (!confirmed || !context.mounted) return;
    _showOperationDialog(
      context,
      _PluginServiceAction.install.label(l10n),
      plugin.name,
    );
    final success = await controller.installPlugin(plugin.id);
    if (!context.mounted) return;
    // 弹窗可能已被用户强制关闭，安全 pop
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (error, stack) {
      silentLog('plugin_service_view', 'dismiss install dialog', error, stack);
    }
    _showPluginSnackBar(
      context,
      SnackBar(
        content: Text(
          success
              ? l10n.pluginServiceInstallSuccess(plugin.name)
              : l10n.pluginServiceInstallFailure(plugin.name),
        ),
      ),
    );
  }

  Future<void> _doUpdate(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.pluginServiceUpdateConfirmTitle(plugin.name),
      message: l10n.pluginServiceUpdateConfirmMessage(
        plugin.name,
        plugin.installedVersion ?? '-',
        plugin.latestVersion ?? '-',
      ),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.pluginServiceActionUpdate,
    );
    if (!confirmed || !context.mounted) return;
    _showOperationDialog(
      context,
      _PluginServiceAction.update.label(l10n),
      plugin.name,
    );
    final success = await controller.updatePlugin(plugin.id);
    if (!context.mounted) return;
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (error, stack) {
      silentLog('plugin_service_view', 'dismiss update dialog', error, stack);
    }
    _showPluginSnackBar(
      context,
      SnackBar(
        content: Text(
          success
              ? l10n.pluginServiceUpdateSuccess(plugin.name)
              : l10n.pluginServiceUpdateFailure(plugin.name),
        ),
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final refreshed = await controller.checkPluginUpdate(plugin.id);
    if (!context.mounted) return;
    if (refreshed == null) {
      _showPluginSnackBar(
        context,
        SnackBar(
          content: Text(
            controller.errorMessage ?? l10n.pluginServiceCheckUpdateFailed,
          ),
        ),
      );
      return;
    }
    final checkedPlugin = controller.pluginById(plugin.id) ?? refreshed;
    _showPluginSnackBar(
      context,
      SnackBar(
        content: Text(
          checkedPlugin.hasUpdate && checkedPlugin.latestVersion != null
              ? l10n.pluginServiceNewVersionAvailable(
                  checkedPlugin.latestVersion!,
                )
              : l10n.pluginServiceNoUpdatesAvailable,
        ),
      ),
    );
  }

  Future<void> _doUninstall(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    for (final dependentId in plugin.dependents) {
      final dependent = controller.pluginById(dependentId);
      if (dependent != null && dependent.isInstalled) {
        _showPluginSnackBar(
          context,
          SnackBar(
            content: Text(
              l10n.pluginServiceUninstallBlocked(dependent.name, plugin.name),
            ),
          ),
        );
        return;
      }
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.pluginServiceUninstallConfirmTitle(plugin.name),
      message: l10n.pluginServiceUninstallConfirmMessage(plugin.name),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.pluginServiceActionUninstall,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    _showOperationDialog(
      context,
      _PluginServiceAction.uninstall.label(l10n),
      plugin.name,
    );
    final success = await controller.uninstallPlugin(plugin.id);
    if (!context.mounted) return;
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (error, stack) {
      silentLog(
        'plugin_service_view',
        'dismiss uninstall dialog',
        error,
        stack,
      );
    }
    _showPluginSnackBar(
      context,
      SnackBar(
        content: Text(
          success
              ? l10n.pluginServiceUninstallSuccess(plugin.name)
              : l10n.pluginServiceUninstallFailure(plugin.name),
        ),
      ),
    );
  }

  void _showOperationDialog(
    BuildContext context,
    String action,
    String pluginName,
  ) {
    showAnimatedDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PluginOperationProgressDialog(
        action: action,
        pluginName: pluginName,
        controller: controller,
      ),
    );
  }

  void _showDetailDialog(BuildContext context) {
    showAnimatedDialog(
      context: context,
      builder: (ctx) => _PluginDetailDialog(plugin: plugin),
    );
  }

  void _showMcpActions(BuildContext context) {
    showAnimatedDialog(
      context: context,
      builder: (ctx) =>
          _PluginMcpDialog(plugin: plugin, controller: controller),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 操作进度弹窗（终端风格）
// ─────────────────────────────────────────────────────────────────────────────

class _PluginOperationProgressDialog extends StatefulWidget {
  const _PluginOperationProgressDialog({
    required this.action,
    required this.pluginName,
    required this.controller,
  });

  final String action;
  final String pluginName;
  final PluginServiceController controller;

  @override
  State<_PluginOperationProgressDialog> createState() =>
      _PluginOperationProgressDialogState();
}

class _PluginOperationProgressDialogState
    extends State<_PluginOperationProgressDialog>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  late final AnimationController _pulseController;
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    widget.controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    setState(() {});
    final logs = widget.controller.operationLogs;
    if (logs.length > _lastLogCount) {
      _lastLogCount = logs.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollGuard.followToBottom(
          _scrollController,
          animated: true,
          animationDuration: openHandMotionDuration(
            context,
            const Duration(milliseconds: 200),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final logs = widget.controller.operationLogs;
    final isOperating = widget.controller.isOperating;
    final pulseEnabled = isOperating && openHandTickerMotionEnabled(context);
    _syncPulseController(pulseEnabled);

    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 560,
      maxHeight: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: isOperating
                ? Icons.terminal_rounded
                : Icons.check_circle_rounded,
            title: l10n.pluginServiceOperationTitle(
              widget.action,
              widget.pluginName,
            ),
            iconColor: isOperating
                ? theme.colorScheme.primary
                : OpenHandStatusColors.success,
            iconWidget: isOperating
                ? _buildHeaderIcon(theme, pulseEnabled)
                : null,
            showCloseButton: false,
            actions: [
              if (isOperating)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: pulseEnabled ? null : 1,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          // 环境信息
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            child: DefaultTextStyle(
              style: theme.textTheme.bodySmall!.copyWith(
                fontFamily: 'monospace',
                fontSize: 10.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text('${l10n.pluginServiceRuntimePid}: $pid'),
                  Text(
                    '${l10n.pluginServiceRuntimeOs}: ${Platform.operatingSystem}',
                  ),
                  Text(
                    '${l10n.pluginServiceRuntimeArch}: ${Platform.version.split(' ').last}',
                  ),
                  Text(l10n.pluginServiceLogLineCount(logs.length)),
                ],
              ),
            ),
          ),
          // 进度条
          if (isOperating)
            LinearProgressIndicator(
              minHeight: 3,
              value: pulseEnabled ? null : 1,
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            )
          else
            Container(height: 3, color: OpenHandStatusColors.success),
          // 终端输出区域
          Flexible(
            child: Container(
              color: const Color(0xFF1E1E1E),
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        l10n.pluginServiceWaitingForOutput,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF808080),
                          fontFamily: 'monospace',
                        ),
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: _scrollGuard.handleNotification,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final line = logs[index];
                          final isError =
                              line.startsWith('✗') ||
                              line.toLowerCase().startsWith('error');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              line,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.5,
                                color: isError
                                    ? const Color(0xFFFF6B6B)
                                    : const Color(0xFFD4D4D4),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
          // 底部状态栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isOperating
                      ? Icons.hourglass_top_rounded
                      : Icons.done_all_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isOperating
                        ? l10n.pluginServiceExecuting
                        : l10n.pluginServiceCompleted,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    if (isOperating) {
                      widget.controller.forceCancel();
                    }
                    Navigator.of(context).pop();
                  },
                  icon: Icon(isOperating ? Icons.close : Icons.done, size: 16),
                  label: Text(
                    isOperating
                        ? l10n.pluginServiceForceClose
                        : l10n.commonClose,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _syncPulseController(bool enabled) {
    if (enabled) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
      return;
    }
    _pulseController.stop();
  }

  Widget _buildHeaderIcon(ThemeData theme, bool pulseEnabled) {
    final icon = Icon(
      Icons.terminal_rounded,
      size: 20,
      color: theme.colorScheme.primary,
    );
    if (!pulseEnabled) return icon;
    return FadeTransition(
      opacity: _pulseController.drive(Tween<double>(begin: 0.4, end: 1.0)),
      child: icon,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 插件元信息行
// ─────────────────────────────────────────────────────────────────────────────

class _PluginMetaRow extends StatelessWidget {
  const _PluginMetaRow({required this.plugin});

  final PluginInfo plugin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Wrap(
      spacing: 20,
      runSpacing: 6,
      children: [
        if (plugin.installedVersion != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tag,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${l10n.pluginServiceVersion}: ${plugin.installedVersion}',
                style: metaStyle,
              ),
            ],
          ),
        if (plugin.latestVersion != null && plugin.hasUpdate)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.new_releases_outlined,
                size: 14,
                color: OpenHandStatusColors.warning,
              ),
              const SizedBox(width: 4),
              Text(
                '${l10n.pluginServiceUpdateAvailable}: ${plugin.latestVersion}',
                style: metaStyle?.copyWith(color: OpenHandStatusColors.warning),
              ),
            ],
          ),
        if (plugin.installPath != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(plugin.installPath!, style: metaStyle),
            ],
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 依赖关系行
// ─────────────────────────────────────────────────────────────────────────────

class _DependencyRow extends StatelessWidget {
  const _DependencyRow({required this.plugin, required this.controller});

  final PluginInfo plugin;
  final PluginServiceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Icon(
          Icons.account_tree_outlined,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          '${l10n.pluginServiceDependsOn}: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        ...plugin.dependencies.map((depId) {
          final dep = controller.pluginById(depId);
          final installed = dep?.isInstalled ?? false;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              avatar: Icon(
                installed ? Icons.check_circle : Icons.cancel,
                size: 14,
                color: installed
                    ? OpenHandStatusColors.success
                    : theme.colorScheme.error,
              ),
              label: Text(
                dep?.name ?? depId,
                style: theme.textTheme.labelSmall,
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 状态指示点
// ─────────────────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

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

// ─────────────────────────────────────────────────────────────────────────────
// 状态卡片（加载失败等全屏提示）
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// 插件详情弹窗
// ─────────────────────────────────────────────────────────────────────────────

class _PluginDetailDialog extends StatefulWidget {
  const _PluginDetailDialog({required this.plugin});

  final PluginInfo plugin;

  @override
  State<_PluginDetailDialog> createState() => _PluginDetailDialogState();
}

class _PluginDetailDialogState extends State<_PluginDetailDialog> {
  Map<String, Object?> _envInfo = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEnvInfo();
  }

  Future<void> _loadEnvInfo() async {
    final info = <String, Object?>{};
    try {
      info['OS'] =
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      info['Arch'] = Platform.version.split(' ').last;
      info['Dart'] = Platform.version.split(' ').first;
      info['PID'] = '$pid';
      info['processors'] = Platform.numberOfProcessors;
      final installPath = widget.plugin.installPath;
      if (installPath != null) {
        info['install_path'] = installPath;
      }
      final installedVersion = widget.plugin.installedVersion;
      if (installedVersion != null) {
        info['current_version'] = installedVersion;
      }
      final latestVersion = widget.plugin.latestVersion;
      if (latestVersion != null) {
        info['latest_version'] = latestVersion;
      }
      // 获取额外运行时信息
      if (widget.plugin.id == 'nodejs' && widget.plugin.isInstalled) {
        try {
          final npmResult = await runTrackedProcessOrFailed('npm', [
            '--version',
          ], timeout: const Duration(seconds: 5));
          if (npmResult.exitCode == 0) {
            info['npm'] = npmResult.stdout.toString().trim();
          }
          final npxResult = await runTrackedProcessOrFailed('npx', [
            '--version',
          ], timeout: const Duration(seconds: 5));
          if (npxResult.exitCode == 0) {
            info['npx'] = npxResult.stdout.toString().trim();
          }
        } catch (error, stack) {
          silentLog('plugin_service_view', 'load node env info', error, stack);
        }
      }
      if (widget.plugin.id == 'python' && widget.plugin.isInstalled) {
        try {
          final pythonExecutable = widget.plugin.installPath ?? 'python3';
          final pythonResult = await runTrackedProcessOrFailed(
            pythonExecutable,
            ['--version'],
            timeout: const Duration(seconds: 5),
          );
          if (pythonResult.exitCode == 0) {
            info['python'] = '${pythonResult.stdout}${pythonResult.stderr}'
                .trim();
          }
        } catch (error, stack) {
          silentLog(
            'plugin_service_view',
            'load python env info',
            error,
            stack,
          );
        }
      }
      if (widget.plugin.id == 'pip' && widget.plugin.isInstalled) {
        try {
          final pythonExecutable = widget.plugin.installPath ?? 'python3';
          final pipResult = await runTrackedProcessOrFailed(pythonExecutable, [
            '-m',
            'pip',
            '--version',
          ], timeout: const Duration(seconds: 8));
          if (pipResult.exitCode == 0) {
            info['pip'] = '${pipResult.stdout}${pipResult.stderr}'.trim();
          }
          info['bound_python'] = pythonExecutable;
        } catch (error, stack) {
          silentLog('plugin_service_view', 'load pip env info', error, stack);
        }
      }
      if (widget.plugin.id == 'playwright' && widget.plugin.isInstalled) {
        try {
          final result = await runTrackedProcessOrFailed('npx', [
            'playwright',
            '--version',
          ], timeout: const Duration(seconds: 10));
          if (result.exitCode == 0) {
            info['Playwright CLI'] = result.stdout.toString().trim();
          }
        } catch (error, stack) {
          silentLog(
            'plugin_service_view',
            'load playwright env info',
            error,
            stack,
          );
        }
      }
      for (final entry in widget.plugin.metadata.entries) {
        final key = entry.key.trim();
        if (key.isEmpty) continue;
        final value = entry.value;
        if (value == null) continue;
        final text = value is Iterable
            ? value.map((item) => '$item').join(', ')
            : '$value';
        if (text.trim().isNotEmpty) {
          info[key] = value;
        }
      }
    } catch (error, stack) {
      silentLog('plugin_service_view', 'load env info', error, stack);
    }
    if (mounted) {
      setState(() {
        _envInfo = info;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final plugin = widget.plugin;

    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 480,
      maxHeight: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.info_outline_rounded,
            title: l10n.pluginServiceDetailTitle(plugin.name),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          // 内容
          Flexible(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // 基本信息
                      _DetailSection(
                        title: l10n.pluginServiceDetailBasicInfo,
                        icon: Icons.extension_rounded,
                        children: [
                          _DetailRow(
                            label: l10n.pluginServiceDetailName,
                            value: plugin.name,
                          ),
                          _DetailRow(label: 'ID', value: plugin.id),
                          _DetailRow(
                            label: l10n.pluginServiceDetailDescription,
                            value: _localizedPluginDescription(l10n, plugin),
                          ),
                          _DetailRow(
                            label: l10n.pluginServiceDetailStatus,
                            value: plugin.status.label(l10n),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 环境信息
                      _DetailSection(
                        title: l10n.pluginServiceDetailEnvironment,
                        icon: Icons.computer_rounded,
                        children: [
                          for (final entry in _envInfo.entries)
                            _DetailRow(
                              label: _localizedDetailLabel(l10n, entry.key),
                              value: _localizedDetailValue(l10n, entry.value),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 依赖关系
                      _DetailSection(
                        title: l10n.pluginServiceDetailDependencies,
                        icon: Icons.account_tree_rounded,
                        children: [
                          _DetailRow(
                            label: l10n.pluginServiceDependsOn,
                            value: plugin.dependencies.isEmpty
                                ? l10n.pluginServiceNone
                                : plugin.dependencies.join(', '),
                          ),
                          _DetailRow(
                            label: l10n.pluginServiceRequiredBy,
                            value: plugin.dependents.isEmpty
                                ? l10n.pluginServiceNone
                                : plugin.dependents.join(', '),
                          ),
                        ],
                      ),
                      if (TemplateRuntimeDependencyRegistry.specsForPlugin(
                        plugin.id,
                      ).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _DetailSection(
                          title: l10n.pluginServiceThreadTemplates,
                          icon: Icons.dashboard_customize_rounded,
                          children: [
                            _DetailRow(
                              label: l10n.pluginServiceTemplates,
                              value:
                                  TemplateRuntimeDependencyRegistry.specsForPlugin(
                                        plugin.id,
                                      )
                                      .map(
                                        (spec) =>
                                            _localizedTemplateDependencyLabel(
                                              l10n,
                                              spec,
                                            ),
                                      )
                                      .join(', '),
                            ),
                          ],
                        ),
                      ],
                      if (plugin.id == 'playwright') ...[
                        const SizedBox(height: 16),
                        _DetailSection(
                          title: 'MCP',
                          icon: Icons.hub_rounded,
                          children: [
                            _DetailRow(
                              label: l10n.pluginServiceMcpPackage,
                              value: '@playwright/mcp',
                            ),
                            _DetailRow(
                              label: l10n.pluginServiceDetailDescription,
                              value: l10n.pluginServiceMcpBrowserDescription,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 插件 MCP 服务弹窗
// ─────────────────────────────────────────────────────────────────────────────

class _PluginMcpDialog extends StatefulWidget {
  const _PluginMcpDialog({required this.plugin, required this.controller});

  final PluginInfo plugin;
  final PluginServiceController controller;

  @override
  State<_PluginMcpDialog> createState() => _PluginMcpDialogState();
}

class _PluginMcpDialogState extends State<_PluginMcpDialog> {
  bool _checking = true;
  bool _mcpInstalled = false;
  String? _mcpVersion;
  bool _operating = false;
  String? _error;
  final List<String> _logs = [];
  final ScrollController _logScroll = ScrollController();
  final AutoFollowScrollGuard _logGuard = AutoFollowScrollGuard();

  @override
  void initState() {
    super.initState();
    _checkMcpStatus();
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  void _addLog(String line) {
    _logs.add(line);
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _logGuard.followToBottom(
          _logScroll,
          animated: true,
          animationDuration: const Duration(milliseconds: 200),
        );
      });
    }
  }

  Future<void> _checkMcpStatus() async {
    setState(() => _checking = true);
    try {
      if (widget.plugin.id == 'playwright') {
        // 同时检查 npm 全局包状态 和 MCP 控制器中的服务注册状态。
        // 只有两者都满足才视为「已安装」——用户在 MCP 板块删除服务卡片后，
        // 即使 npm 包仍在全局，也应视为「未注册」状态。
        bool npmInstalled = false;
        String? npmVersion;
        try {
          final listResult = await runTrackedProcessOrFailed(
            'npm',
            ['list', '-g', '@playwright/mcp', '--depth=0'],
            timeout: const Duration(seconds: 10),
            environment: SystemProxyResolver.instance
                .resolveSubprocessEnvironment(),
          );
          npmInstalled =
              listResult.exitCode == 0 &&
              listResult.stdout.toString().contains('@playwright/mcp');
          if (npmInstalled) {
            final match = RegExp(
              r'@playwright/mcp@([\d.]+)',
            ).firstMatch(listResult.stdout.toString());
            npmVersion = match?.group(1);
          }
        } catch (error, stack) {
          silentLog(
            'plugin_service_view',
            'check playwright mcp npm',
            error,
            stack,
          );
        }

        // 检查 MCP 控制器中是否注册了 Playwright MCP 服务
        bool mcpRegistered = false;
        if (mounted) {
          try {
            final mcpController = context.read<McpController>();
            mcpRegistered = mcpController.servers.any(
              (s) =>
                  s.name == 'Playwright MCP' ||
                  s.command == 'npx' && s.args.contains('@playwright/mcp'),
            );
          } catch (error, stack) {
            silentLog(
              'plugin_service_view',
              'check playwright mcp registry',
              error,
              stack,
            );
          }
        }

        _mcpInstalled = npmInstalled && mcpRegistered;
        _mcpVersion = npmVersion;
      }
    } catch (error, stack) {
      silentLog('plugin_service_view', 'check playwright mcp', error, stack);
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _runMcpOperation(
    _PluginServiceAction action,
    List<String> args,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final actionLabel = action.label(l10n);
    setState(() {
      _operating = true;
      _error = null;
      _logs.clear();
    });
    _addLog('> npm ${args.join(' ')}');
    _addLog('');
    try {
      final result = await runTrackedProcessWithLineLogging(
        'npm',
        args,
        environment: SystemProxyResolver.instance
            .resolveSubprocessEnvironment(),
        timeout: const Duration(minutes: 3),
        tag: 'plugin_service_view',
        onStdoutLine: _addLog,
        onStderrLine: _addLog,
        onTimeout: () => _addLog(l10n.pluginServiceMcpOperationTimeout),
      );
      final exitCode = result.exitCode;
      if (exitCode == 0) {
        _addLog('');
        _addLog(l10n.pluginServiceMcpOperationCompleted(actionLabel, exitCode));
        await _checkMcpStatus();
        // 同步到 MCP 板块
        if (mounted) _syncMcpController(action);
      } else {
        _addLog('');
        final message = l10n.pluginServiceMcpOperationFailed(
          actionLabel,
          exitCode,
        );
        _addLog(message);
        _error = message;
      }
    } catch (e) {
      _addLog('');
      final message = l10n.pluginServiceMcpOperationError('$e');
      _addLog(message);
      _error = message;
    }
    if (mounted) setState(() => _operating = false);
  }

  void _syncMcpController(_PluginServiceAction action) {
    try {
      final mcpController = context.read<McpController>();
      const mcpName = 'Playwright MCP';
      if (action == _PluginServiceAction.install ||
          action == _PluginServiceAction.update) {
        // 注册/更新 MCP 服务到 MCP 板块
        const server = McpServer(
          name: mcpName,
          type: McpServerType.stdio,
          enabled: true,
          command: 'npx',
          args: ['@playwright/mcp'],
        );
        mcpController.saveServer(server, previousName: mcpName);
      } else if (action == _PluginServiceAction.uninstall) {
        // 从 MCP 板块移除
        final existing = mcpController.servers
            .where((s) => s.name == mcpName)
            .toList();
        for (final s in existing) {
          mcpController.deleteServer(s);
        }
      }
    } catch (error, stack) {
      silentLog('plugin_service_view', 'sync MCP service action', error, stack);
    }
  }

  Future<void> _installMcp() => _runMcpOperation(_PluginServiceAction.install, [
    'install',
    '-g',
    '@playwright/mcp',
  ]);

  Future<void> _updateMcp() => _runMcpOperation(_PluginServiceAction.update, [
    'update',
    '-g',
    '@playwright/mcp',
  ]);

  Future<void> _uninstallMcp() => _runMcpOperation(
    _PluginServiceAction.uninstall,
    ['uninstall', '-g', '@playwright/mcp'],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: 520,
      maxHeight: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.hub_rounded,
            title: '${widget.plugin.name} MCP',
            subtitle: '@playwright/mcp',
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          // 状态 + 操作按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: _checking
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      Icon(
                        _mcpInstalled ? Icons.check_circle : Icons.cancel,
                        size: 18,
                        color: _mcpInstalled
                            ? OpenHandStatusColors.success
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _mcpInstalled
                            ? _mcpVersion != null
                                  ? l10n.pluginServiceMcpInstalledVersion(
                                      _mcpVersion!,
                                    )
                                  : l10n.pluginServiceStatusInstalled
                            : l10n.pluginServiceStatusNotInstalled,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (!_mcpInstalled)
                        IconButton.filled(
                          tooltip: l10n.pluginServiceActionInstall,
                          onPressed: _operating ? null : _installMcp,
                          icon: const Icon(Icons.download_rounded, size: 18),
                        )
                      else ...[
                        IconButton.filledTonal(
                          tooltip: l10n.pluginServiceActionUpdate,
                          onPressed: _operating ? null : _updateMcp,
                          icon: const Icon(
                            Icons.system_update_alt_rounded,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          tooltip: l10n.pluginServiceActionUninstall,
                          onPressed: _operating ? null : _uninstallMcp,
                          style: IconButton.styleFrom(
                            foregroundColor: theme.colorScheme.error,
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          // 终端输出区域
          if (_logs.isNotEmpty || _operating)
            Flexible(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _logs.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: _logGuard.handleNotification,
                        child: ListView.builder(
                          controller: _logScroll,
                          padding: const EdgeInsets.all(10),
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            final line = _logs[index];
                            final isErr =
                                line.startsWith('✗') ||
                                line.toLowerCase().startsWith('error');
                            final isSuccess = line.startsWith('✓');
                            final isFail = line.startsWith('✗');
                            return Text(
                              line,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.5,
                                color: isErr || isFail
                                    ? const Color(0xFFFF6B6B)
                                    : isSuccess
                                    ? const Color(0xFF4ADE80)
                                    : const Color(0xFFD4D4D4),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
