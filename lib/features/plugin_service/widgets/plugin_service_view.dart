import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/buffered_console_log.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_busy_indicators.dart';
import '../../../shared/ui/openhand_console_log_panel.dart';
import '../../../shared/ui/openhand_inline_notice.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/ui/runtime_log_dialog.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/user_failure_message.dart';
import '../../ai/index.dart' show AiPromptTemplatePolicies;
import '../../mcp/index.dart';
import '../../thread_template_runtime/index.dart';
import '../model/plugin_info.dart';
import '../plugin_service_controller.dart';
import '../service/plugin_toolchain_shell.dart';

enum _PluginServiceAction { install, update, uninstall }

/// 工具链版本探测（`--version`），命令应当秒回。
const Duration _kToolchainVersionProbeTimeout = Duration(seconds: 5);

/// 工具链包列举，需要读本地安装树。
const Duration _kToolchainListTimeout = Duration(seconds: 10);

/// 日志追加后贴底动画的时长。
const Duration _kLogFollowDuration = kOpenHandMotion200;

const String _playwrightMcpPackage = '@playwright/mcp';
const String _playwrightMcpServerName = 'Playwright MCP';
const String _pluginIconAssetDirectory = 'assets/icons/plugins';
const String _pluginFallbackIconAsset =
    '$_pluginIconAssetDirectory/blutter.svg';
const double _kPluginIconSize = 21;

String _pluginIconAssetPath(String pluginId) {
  return switch (pluginId) {
    PluginCatalogIds.nodejs => '$_pluginIconAssetDirectory/nodejs.svg',
    PluginCatalogIds.playwright => '$_pluginIconAssetDirectory/playwright.svg',
    PluginCatalogIds.python => '$_pluginIconAssetDirectory/python.svg',
    PluginCatalogIds.java => '$_pluginIconAssetDirectory/java.svg',
    PluginCatalogIds.apktool => '$_pluginIconAssetDirectory/apktool.svg',
    PluginCatalogIds.docker => '$_pluginIconAssetDirectory/docker.svg',
    PluginCatalogIds.qdrant => '$_pluginIconAssetDirectory/qdrant.svg',
    PluginCatalogIds.postgresql => '$_pluginIconAssetDirectory/postgresql.svg',
    PluginCatalogIds.redis => '$_pluginIconAssetDirectory/redis.svg',
    PluginCatalogIds.dingtalkWorkspaceCli =>
      '$_pluginIconAssetDirectory/dingtalk-workspace-cli.svg',
    PluginCatalogIds.googleChrome =>
      '$_pluginIconAssetDirectory/google-chrome.svg',
    _ => _pluginFallbackIconAsset,
  };
}

bool _isPlaywrightMcpServer(McpServer server) {
  return server.name == _playwrightMcpServerName ||
      server.command == 'npx' && server.args.contains(_playwrightMcpPackage);
}

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
    PluginCatalogIds.python => l10n.pluginServiceDescriptionPython,
    PluginCatalogIds.pip => l10n.pluginServiceDescriptionPip,
    PluginCatalogIds.java => l10n.pluginServiceDescriptionJava,
    PluginCatalogIds.frida => l10n.pluginServiceDescriptionFrida,
    PluginCatalogIds.mitmproxy => l10n.pluginServiceDescriptionMitmproxy,
    PluginCatalogIds.apktool => l10n.pluginServiceDescriptionApktool,
    PluginCatalogIds.jadx => l10n.pluginServiceDescriptionJadx,
    PluginCatalogIds.radare2 => l10n.pluginServiceDescriptionRadare2,
    PluginCatalogIds.blutter => l10n.pluginServiceDescriptionBlutter,
    PluginCatalogIds.doldrums => l10n.pluginServiceDescriptionDoldrums,
    PluginCatalogIds.anythingAnalyzer =>
      l10n.pluginServiceDescriptionAnythingAnalyzer,
    PluginCatalogIds.docker => l10n.pluginServiceDescriptionDocker,
    PluginCatalogIds.qdrant => l10n.pluginServiceDescriptionQdrant,
    PluginCatalogIds.postgresql => l10n.pluginServiceDescriptionPostgresql,
    PluginCatalogIds.redis => l10n.pluginServiceDescriptionRedis,
    PluginCatalogIds.dingtalkWorkspaceCli =>
      l10n.pluginServiceDescriptionDingtalkWorkspaceCli,
    PluginCatalogIds.googleChrome => l10n.pluginServiceDescriptionGoogleChrome,
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
    'installation_target' => l10n.pluginServiceDetailInstallationTarget,
    'application_path' => l10n.pluginServiceDetailApplicationPath,
    'installation_method' => l10n.pluginServiceDetailInstallMethod,
    'target_os' => l10n.pluginServiceDetailTargetOs,
    'supported_platforms' => l10n.pluginServiceDetailSupportedPlatforms,
    'package_name' => l10n.pluginServiceDetailPackageName,
    'binary_name' => l10n.pluginServiceDetailBinaryName,
    'repository' => l10n.pluginServiceDetailRepository,
    'documentation' => l10n.pluginServiceDetailDocumentation,
    'install_command' => l10n.pluginServiceDetailInstallCommand,
    'upgrade_command' => l10n.pluginServiceDetailUpgradeCommand,
    'uninstall_command' => l10n.pluginServiceDetailUninstallCommand,
    'executable_path' => l10n.pluginServiceDetailExecutablePath,
    'cache_directory' => l10n.pluginServiceDetailCacheDirectory,
    'npm_global_root' => l10n.pluginServiceDetailNpmGlobalRoot,
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
    'external_service' => l10n.pluginServiceDetailExternalService,
    'service_running' => l10n.pluginServiceDetailServiceRunning,
    'endpoint' => l10n.pluginServiceDetailEndpoint,
    'runtime_managed' => l10n.pluginServiceDetailOpenHandManaged,
    'release_channel' => l10n.pluginServiceDetailReleaseChannel,
    'version_source' => l10n.pluginServiceDetailVersionSource,
    'version_api' => l10n.pluginServiceDetailVersionApi,
    'browser_kind' => l10n.pluginServiceDetailBrowserKind,
    'cdp_transport' => l10n.pluginServiceDetailCdpTransport,
    'cdp_endpoint' => l10n.pluginServiceDetailCdpEndpoint,
    'profile_strategy' => l10n.pluginServiceDetailProfileStrategy,
    'capture_scope' => l10n.pluginServiceDetailCaptureScope,
    'credential_policy' => l10n.pluginServiceDetailCredentialPolicy,
    'session_cleanup' => l10n.pluginServiceDetailSessionCleanup,
    'update_policy' => l10n.pluginServiceDetailUpdatePolicy,
    'uninstall_policy' => l10n.pluginServiceDetailUninstallPolicy,
    'official_site' => l10n.pluginServiceDetailOfficialSite,
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

String _pluginUpdateCheckSummary(BuildContext context, PluginInfo plugin) {
  final l10n = AppLocalizations.of(context)!;
  if (!plugin.supportsUpdateCheck) return l10n.qdrantValueNo;
  final error = '${plugin.metadata['update_check_error'] ?? ''}'.trim();
  if (error.isNotEmpty) return error;
  final latest = plugin.latestVersion?.trim();
  if (latest == null || latest.isEmpty) {
    return openHandLocalizedText(
      context,
      zh: '尚未获取上游版本',
      zhHant: '尚未取得上游版本',
      en: 'Upstream version not retrieved',
      fr: 'Version amont non récupérée',
      de: 'Upstream-Version nicht abgerufen',
      ja: '上流バージョンを取得していません',
    );
  }
  return plugin.hasUpdate
      ? l10n.pluginServiceNewVersionAvailable(latest)
      : l10n.pluginServiceNoUpdatesAvailable;
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
          onPressed: controller.isBusy ? null : controller.rescan,
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
            kOpenHandGap16,
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
          kOpenHandGap12,
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
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
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
        borderRadius: BorderRadius.circular(kOpenHandRadius8),
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

// 插件卡片

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
    final pluginIconAsset = _pluginIconAssetPath(plugin.id);

    return Card(
      key: ValueKey<String>('plugin-card-${plugin.id}'),
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
                            borderRadius: BorderRadius.circular(
                              kOpenHandRadius18,
                            ),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: _kPluginIconSize,
                              height: _kPluginIconSize,
                              child: SvgPicture.asset(
                                pluginIconAsset,
                                colorFilter: ColorFilter.mode(
                                  theme.colorScheme.onPrimaryContainer,
                                  BlendMode.srcIn,
                                ),
                                semanticsLabel: plugin.name,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: _StatusDot(color: stateColor),
                        ),
                      ],
                    ),
                    kOpenHandHGap14,
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
                          kOpenHandGap6,
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
                    children: [title, kOpenHandGap14, actions],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    kOpenHandHGap16,
                    actions,
                  ],
                );
              },
            ),
            if (plugin.isInstalled) ...[
              kOpenHandGap14,
              _PluginMetaRow(plugin: plugin),
            ],
            if (plugin.dependencies.isNotEmpty) ...[
              kOpenHandGap10,
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
                            fontFamily: kOpenHandMonospaceFontFamily,
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
    final isBusy = plugin.isBusy || controller.isBusy;
    final hasMcp = plugin.id == PluginCatalogIds.playwright;
    final managedRuntime = plugin.metadata['runtime_managed'] == true;

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
        if (plugin.isInstalled &&
            plugin.id != PluginCatalogIds.aiJungler &&
            plugin.supportsUpdateCheck)
          IconButton.filledTonal(
            tooltip: l10n.pluginServiceCheckUpdates,
            onPressed: isBusy ? null : () => _checkUpdate(context),
            icon: OpenHandBusyStatusIcon(
              busy: isCheckingUpdate,
              icon: Icons.refresh_rounded,
              strokeWidth: 2.2,
            ),
          ),
        // MCP 服务（仅 Playwright）
        if (hasMcp && plugin.isInstalled)
          IconButton.filledTonal(
            tooltip: l10n.pluginServiceMcpService,
            onPressed: isBusy ? null : () => _showMcpActions(context),
            icon: const Icon(Icons.hub_outlined, size: 18),
          ),
        // 启用/禁用
        if (plugin.isInstalled &&
            plugin.id != PluginCatalogIds.aiJungler &&
            plugin.supportsInstall)
          IconButton.filledTonal(
            tooltip: plugin.enabled
                ? l10n.pluginServiceActionDisable
                : l10n.pluginServiceActionEnable,
            onPressed: isBusy
                ? null
                : managedRuntime
                ? () => _toggleManagedRuntime(context)
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
        if (plugin.status == PluginStatus.notInstalled &&
            plugin.supportsInstall)
          IconButton.filled(
            tooltip: l10n.pluginServiceActionInstall,
            onPressed: isBusy ? null : () => _doInstall(context),
            icon: const Icon(Icons.download_rounded, size: 18),
          ),
        // 更新
        if (plugin.isInstalled && plugin.hasUpdate && plugin.supportsInstall)
          IconButton.filledTonal(
            tooltip: l10n.pluginServiceActionUpdate,
            onPressed: isBusy ? null : () => _doUpdate(context),
            icon: const Icon(Icons.system_update_alt_rounded, size: 18),
          ),
        // 运行日志：放在卸载按钮左侧，未安装插件也保留入口用于查看诊断信息。
        IconButton.filledTonal(
          tooltip: openHandLocalizedText(
            context,
            zh: '查看运行日志',
            zhHant: '查看運行日誌',
            en: 'View runtime logs',
            fr: 'Voir les journaux d’exécution',
            de: 'Laufzeitprotokolle anzeigen',
            ja: '実行ログを表示',
          ),
          onPressed: () => _showPluginLogs(context),
          icon: const Icon(Icons.article_outlined, size: 18),
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
        if (plugin.isBusy && !plugin.isInstalled)
          const OpenHandBusyStatusIcon(
            busy: true,
            icon: null,
            size: 24,
            strokeWidth: 2.5,
          ),
      ],
    );
  }

  Future<void> _doInstall(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    for (final depId in plugin.dependencies) {
      final dep = controller.pluginById(depId);
      if (dep == null || !dep.isInstalled) {
        flashOpenHandSnack(
          context,
          l10n.pluginServiceInstallDependencyRequired(dep?.name ?? depId),
          kind: OpenHandSnackKind.error,
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
    final progress = _showOperationDialog(
      context,
      _PluginServiceAction.install.label(l10n),
      plugin.name,
    );
    final success = await controller.installPlugin(plugin.id);
    await progress.dismiss(logTag: 'plugin_service_view', logAction: '关闭安装对话框');
    if (!context.mounted) return;
    flashOpenHandSnack(
      context,
      success
          ? l10n.pluginServiceInstallSuccess(plugin.name)
          : l10n.pluginServiceInstallFailure(plugin.name),
      kind: success ? OpenHandSnackKind.success : OpenHandSnackKind.error,
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
    final progress = _showOperationDialog(
      context,
      _PluginServiceAction.update.label(l10n),
      plugin.name,
    );
    final success = await controller.updatePlugin(plugin.id);
    await progress.dismiss(logTag: 'plugin_service_view', logAction: '关闭更新对话框');
    if (!context.mounted) return;
    flashOpenHandSnack(
      context,
      success
          ? l10n.pluginServiceUpdateSuccess(plugin.name)
          : l10n.pluginServiceUpdateFailure(plugin.name),
      kind: success ? OpenHandSnackKind.success : OpenHandSnackKind.error,
    );
  }

  Future<void> _toggleManagedRuntime(BuildContext context) async {
    final action = plugin.enabled
        ? openHandLocalizedText(context, zh: '停止', en: 'Stop')
        : openHandLocalizedText(context, zh: '启动', en: 'Start');
    final progress = _showOperationDialog(context, action, plugin.name);
    final success = await controller.toggleManagedRuntime(
      plugin.id,
      enabled: !plugin.enabled,
    );
    await progress.dismiss(
      logTag: 'plugin_service_view',
      logAction: '关闭服务状态对话框',
    );
    if (!context.mounted) return;
    flashOpenHandSnack(
      context,
      success ? '$action ${plugin.name}成功' : '$action ${plugin.name}失败',
      kind: success ? OpenHandSnackKind.success : OpenHandSnackKind.error,
    );
  }

  Future<void> _checkUpdate(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final refreshed = await controller.checkPluginUpdate(plugin.id);
    if (!context.mounted) return;
    if (refreshed == null) {
      flashOpenHandSnack(
        context,
        controller.errorMessage ?? l10n.pluginServiceCheckUpdateFailed,
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    final checkedPlugin = controller.pluginById(plugin.id) ?? refreshed;
    final hasUpdate =
        checkedPlugin.hasUpdate && checkedPlugin.latestVersion != null;
    flashOpenHandSnack(
      context,
      hasUpdate
          ? l10n.pluginServiceNewVersionAvailable(checkedPlugin.latestVersion!)
          : l10n.pluginServiceNoUpdatesAvailable,
      kind: hasUpdate ? OpenHandSnackKind.success : OpenHandSnackKind.info,
    );
  }

  Future<void> _doUninstall(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    for (final dependentId in plugin.dependents) {
      final dependent = controller.pluginById(dependentId);
      if (dependent != null && dependent.isInstalled) {
        flashOpenHandSnack(
          context,
          l10n.pluginServiceUninstallBlocked(dependent.name, plugin.name),
          kind: OpenHandSnackKind.error,
        );
        return;
      }
    }
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.pluginServiceUninstallConfirmTitle(plugin.name),
      message: plugin.id == PluginCatalogIds.googleChrome
          ? openHandLocalizedText(
              context,
              zh: '将卸载本机 Google Chrome 应用，但保留 Chrome 用户资料。macOS 会将应用移至废纸篓，Windows 与 Linux 将调用系统卸载能力。',
              zhHant:
                  '將解除安裝本機 Google Chrome 應用程式，但保留 Chrome 使用者資料。macOS 會將應用程式移至垃圾桶，Windows 與 Linux 將呼叫系統解除安裝能力。',
              en: 'Google Chrome will be uninstalled while its user profile is kept. macOS moves the app to Trash; Windows and Linux use the system uninstaller.',
              fr: 'Google Chrome sera désinstallé, mais son profil utilisateur sera conservé. macOS place l’application dans la corbeille ; Windows et Linux utilisent le programme de désinstallation système.',
              de: 'Google Chrome wird deinstalliert, das Benutzerprofil bleibt erhalten. macOS verschiebt die App in den Papierkorb; Windows und Linux verwenden die System-Deinstallation.',
              ja: 'Google Chrome をアンインストールしますが、ユーザープロファイルは保持します。macOS ではゴミ箱へ移動し、Windows と Linux ではシステムのアンインストーラーを使用します。',
            )
          : l10n.pluginServiceUninstallConfirmMessage(plugin.name),
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.pluginServiceActionUninstall,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final progress = _showOperationDialog(
      context,
      _PluginServiceAction.uninstall.label(l10n),
      plugin.name,
    );
    final success = await controller.uninstallPlugin(plugin.id);
    await progress.dismiss(logTag: 'plugin_service_view', logAction: '关闭卸载对话框');
    if (!context.mounted) return;
    flashOpenHandSnack(
      context,
      success
          ? l10n.pluginServiceUninstallSuccess(plugin.name)
          : l10n.pluginServiceUninstallFailure(plugin.name),
      kind: success ? OpenHandSnackKind.success : OpenHandSnackKind.error,
    );
  }

  /// 长时插件操作的不可关闭进度弹窗；结束时仅移除自身路由。
  OpenHandDialogSession<void> _showOperationDialog(
    BuildContext context,
    String action,
    String pluginName,
  ) {
    return showTrackedAnimatedDialog<void>(
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

  void _showPluginLogs(BuildContext context) {
    final title = openHandLocalizedText(
      context,
      zh: '${plugin.name} 运行日志',
      zhHant: '${plugin.name} 運行日誌',
      en: '${plugin.name} runtime logs',
      fr: 'Journaux d’exécution de ${plugin.name}',
      de: '${plugin.name}-Laufzeitprotokolle',
      ja: '${plugin.name} の実行ログ',
    );
    showOpenHandRuntimeLogDialog(
      context: context,
      title: title,
      listenable: controller,
      logs: () {
        final logs = controller.logsForPlugin(plugin.id);
        final current = controller.pluginById(plugin.id) ?? plugin;
        if (!current.isInstalled) {
          return <String>[
            '[ERROR] ${current.name} 尚未安装，暂无核心组件运行日志。',
            '[ERROR] 请先安装并启用该插件后再查看运行状态。',
            ...logs,
          ];
        }
        if (!current.enabled) {
          return <String>['[WARN] ${current.name} 当前已禁用，运行时不会产生新的日志。', ...logs];
        }
        if (logs.isNotEmpty) return logs;
        return <String>['[INFO] ${current.name} 当前没有可用的运行日志。'];
      },
      revision: () =>
          controller.pluginLogRevision(plugin.id) +
          controller.operationLogRevision,
      clearLogs: () => controller.clearPluginLogs(plugin.id),
      fileNamePrefix: 'openhand-plugin-${plugin.id}',
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

// 操作进度弹窗（终端风格）

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
  int _lastLogRevision = 0;
  bool _updateScheduled = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: kOpenHandMotion1200,
    );
    _lastLogRevision = widget.controller.operationLogRevision;
    widget.controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (!mounted || _updateScheduled) return;
    _updateScheduled = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (!mounted) return;
      final revision = widget.controller.operationLogRevision;
      if (revision == _lastLogRevision) return;
      _lastLogRevision = revision;
      _scrollGuard.followToBottom(
        _scrollController,
        animated: true,
        animationDuration: openHandMotionDuration(context, kOpenHandMotion200),
      );
    });
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
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightCompact,
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
                fontFamily: kOpenHandMonospaceFontFamily,
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
            child: OpenHandConsoleLogPanel(
              lineCount: logs.length,
              lineAt: (index) => logs[index],
              controller: _scrollController,
              onNotification: _scrollGuard.handleNotification,
              padding: const EdgeInsets.all(12),
              borderRadius: BorderRadius.zero,
              lineSpacing: 2,
              emptyPlaceholder: Text(
                l10n.pluginServiceWaitingForOutput,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: OpenHandConsolePalette.muted,
                  fontFamily: kOpenHandMonospaceFontFamily,
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
                kOpenHandHGap6,
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
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(isOperating ? Icons.close : Icons.done, size: 16),
                  label: Text(l10n.commonClose),
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

// 插件元信息行

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
              kOpenHandHGap4,
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
              kOpenHandHGap4,
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
              kOpenHandHGap4,
              Text(plugin.installPath!, style: metaStyle),
            ],
          ),
      ],
    );
  }
}

// 依赖关系行

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
        kOpenHandHGap6,
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

// 状态指示点

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

// 状态卡片（加载失败等全屏提示）

// 插件详情弹窗

class _PluginDetailDialog extends StatefulWidget {
  const _PluginDetailDialog({required this.plugin});

  final PluginInfo plugin;

  @override
  State<_PluginDetailDialog> createState() => _PluginDetailDialogState();
}

class _PluginDetailDialogState extends State<_PluginDetailDialog> {
  Map<String, Object?> _envInfo = {};
  Map<String, Object?> _fileSystemInfo = {};
  Map<String, Object?> _capabilityInfo = {};
  bool _loading = true;

  static const _fileSystemKeys = <String>{
    'installation_target',
    'application_path',
    'executable_path',
    'data_directory',
    'cache_directory',
    'npm_global_root',
    'docker_root_dir',
  };
  static const _internalMetadataKeys = <String>{
    'image_version',
    'image_manifest_digest',
    'local_image_digest',
    'remote_image_digest',
    'remote_platform_image_digest',
    'image_update_available',
    'update_check_error',
  };
  static const _chromeCapabilityKeys = <String>{
    'release_channel',
    'version_source',
    'version_api',
    'browser_kind',
    'cdp_transport',
    'cdp_endpoint',
    'profile_strategy',
    'capture_scope',
    'credential_policy',
    'session_cleanup',
    'update_policy',
    'uninstall_policy',
    'official_site',
    'documentation',
    'supported_platforms',
    'target_os',
  };

  @override
  void initState() {
    super.initState();
    _loadEnvInfo();
  }

  Future<void> _loadEnvInfo() async {
    final info = <String, Object?>{};
    final fileSystemInfo = <String, Object?>{};
    final capabilityInfo = <String, Object?>{};
    try {
      info['OS'] =
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      info['architecture'] = pluginDesktopTargetLabel().split(' ').last;
      info['Dart'] = Platform.version.split(' ').first;
      info['PID'] = '$pid';
      info['processors'] = Platform.numberOfProcessors;
      final installPath = widget.plugin.installPath;
      final metadata = widget.plugin.metadata;
      final installationTarget = metadata['installation_target'];
      if (installationTarget != null &&
          '$installationTarget'.trim().isNotEmpty) {
        fileSystemInfo['installation_target'] = installationTarget;
      }
      final executablePath =
          metadata['executable_path'] ??
          (widget.plugin.id == PluginCatalogIds.qdrant ? null : installPath);
      if (executablePath != null &&
          '$executablePath'.trim().isNotEmpty &&
          executablePath != installationTarget) {
        fileSystemInfo['executable_path'] = executablePath;
      }
      // 获取额外运行时信息
      if (widget.plugin.id == PluginCatalogIds.nodejs &&
          widget.plugin.isInstalled) {
        try {
          final npmResult = await runPluginToolchainCommandOrFailed(
            'npm',
            const <String>['--version'],
            timeout: _kToolchainVersionProbeTimeout,
          );
          if (npmResult.exitCode == 0) {
            info['npm'] = npmResult.stdout.toString().trim();
          }
          final npxResult = await runPluginToolchainCommandOrFailed(
            'npx',
            const <String>['--version'],
            timeout: _kToolchainVersionProbeTimeout,
          );
          if (npxResult.exitCode == 0) {
            info['npx'] = npxResult.stdout.toString().trim();
          }
        } catch (error, stack) {
          silentLog('plugin_service_view', '加载 Node 环境信息', error, stack);
        }
      }
      if (widget.plugin.id == PluginCatalogIds.python &&
          widget.plugin.isInstalled) {
        try {
          final pythonExecutable = widget.plugin.installPath ?? 'python3';
          final pythonResult = await runTrackedProcessOrFailed(
            pythonExecutable,
            ['--version'],
            timeout: _kToolchainVersionProbeTimeout,
          );
          if (pythonResult.exitCode == 0) {
            info['python'] = '${pythonResult.stdout}${pythonResult.stderr}'
                .trim();
          }
        } catch (error, stack) {
          silentLog('plugin_service_view', '加载 Python 环境信息', error, stack);
        }
      }
      if (widget.plugin.id == PluginCatalogIds.pip &&
          widget.plugin.isInstalled) {
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
          silentLog('plugin_service_view', '加载 pip 环境信息', error, stack);
        }
      }
      for (final entry in metadata.entries) {
        final key = entry.key.trim();
        if (key.isEmpty || _internalMetadataKeys.contains(key)) continue;
        final value = entry.value;
        if (value == null) continue;
        final text = value is Iterable
            ? value.map((item) => '$item').join(', ')
            : '$value';
        if (text.trim().isNotEmpty) {
          if (widget.plugin.id == PluginCatalogIds.googleChrome &&
              _chromeCapabilityKeys.contains(key)) {
            capabilityInfo[key] = value;
          } else if (_fileSystemKeys.contains(key)) {
            fileSystemInfo[key] = value;
          } else {
            info[key] = value;
          }
        }
      }
    } catch (error, stack) {
      silentLog('plugin_service_view', '加载环境信息', error, stack);
    }
    if (mounted) {
      setState(() {
        _envInfo = info;
        _fileSystemInfo = fileSystemInfo;
        _capabilityInfo = capabilityInfo;
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
      maxWidth: plugin.id == PluginCatalogIds.googleChrome
          ? kOpenHandDialogWidthWide
          : kOpenHandDialogWidthStandard,
      maxHeight: kOpenHandDialogHeightStandard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.info_outline_rounded,
            title: l10n.pluginServiceDetailTitle(plugin.name),
            subtitle: plugin.installedVersion == null
                ? plugin.status.label(l10n)
                : '${plugin.status.label(l10n)} · v${plugin.installedVersion}',
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          // 内容
          Flexible(
            child: AnimatedSwitcher(
              duration: openHandMotionDuration(context, kOpenHandMotion220),
              switchInCurve: kOpenHandSwitchInCurve,
              switchOutCurve: kOpenHandSwitchOutCurve,
              child: _loading
                  ? const Center(
                      key: ValueKey('plugin_detail_loading'),
                      child: CircularProgressIndicator(),
                    )
                  : SelectionArea(
                      key: const ValueKey('plugin_detail_content'),
                      child: ListView(
                        padding: const EdgeInsets.all(24),
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
                                value: _localizedPluginDescription(
                                  l10n,
                                  plugin,
                                ),
                              ),
                              _DetailRow(
                                label: l10n.pluginServiceDetailStatus,
                                value: plugin.status.label(l10n),
                              ),
                              if (plugin.installedVersion != null)
                                _DetailRow(
                                  label: l10n.pluginServiceDetailCurrentVersion,
                                  value: plugin.installedVersion!,
                                ),
                              if (plugin.latestVersion != null)
                                _DetailRow(
                                  label: l10n.pluginServiceDetailLatestVersion,
                                  value: plugin.latestVersion!,
                                ),
                              _DetailRow(
                                label: l10n.pluginServiceCheckUpdates,
                                value: _pluginUpdateCheckSummary(
                                  context,
                                  plugin,
                                ),
                              ),
                              _DetailRow(
                                label: l10n.pluginServiceActionUninstall,
                                value: plugin.supportsUninstall
                                    ? l10n.qdrantValueYes
                                    : l10n.qdrantValueNo,
                              ),
                            ],
                          ),
                          if (_capabilityInfo.isNotEmpty) ...[
                            kOpenHandGap18,
                            _DetailSection(
                              title:
                                  l10n.pluginServiceDetailRuntimeCapabilities,
                              icon: Icons.developer_mode_rounded,
                              children: [
                                for (final entry in _capabilityInfo.entries)
                                  _DetailRow(
                                    label: _localizedDetailLabel(
                                      l10n,
                                      entry.key,
                                    ),
                                    value: _localizedDetailValue(
                                      l10n,
                                      entry.value,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          kOpenHandGap18,
                          // 环境信息
                          _DetailSection(
                            title: l10n.pluginServiceDetailEnvironment,
                            icon: Icons.computer_rounded,
                            children: [
                              for (final entry in _envInfo.entries)
                                _DetailRow(
                                  label: _localizedDetailLabel(l10n, entry.key),
                                  value: _localizedDetailValue(
                                    l10n,
                                    entry.value,
                                  ),
                                ),
                            ],
                          ),
                          if (_fileSystemInfo.isNotEmpty) ...[
                            kOpenHandGap18,
                            _DetailSection(
                              title: l10n.pluginServiceDetailFileSystem,
                              icon: Icons.folder_open_rounded,
                              children: [
                                for (final entry in _fileSystemInfo.entries)
                                  _DetailRow(
                                    label: _localizedDetailLabel(
                                      l10n,
                                      entry.key,
                                    ),
                                    value: _localizedDetailValue(
                                      l10n,
                                      entry.value,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          kOpenHandGap18,
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
                            kOpenHandGap18,
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
                          if (plugin.id == PluginCatalogIds.playwright) ...[
                            kOpenHandGap18,
                            _DetailSection(
                              title: 'MCP',
                              icon: Icons.hub_rounded,
                              children: [
                                _DetailRow(
                                  label: l10n.pluginServiceMcpPackage,
                                  value: _playwrightMcpPackage,
                                ),
                                _DetailRow(
                                  label: l10n.pluginServiceDetailDescription,
                                  value:
                                      l10n.pluginServiceMcpBrowserDescription,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
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
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(kOpenHandRadius16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(kOpenHandRadius11),
                ),
                child: Icon(icon, size: 18, color: colors.onPrimaryContainer),
              ),
              kOpenHandHGap10,
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          kOpenHandGap12,
          Divider(
            height: 1,
            color: colors.outlineVariant.withValues(alpha: 0.7),
          ),
          kOpenHandGap9,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ],
      ),
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
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.4,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: labelStyle),
                    kOpenHandGap3,
                    Text(value, style: valueStyle),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 132, child: Text(label, style: labelStyle)),
                    kOpenHandHGap12,
                    Expanded(child: Text(value, style: valueStyle)),
                  ],
                ),
        );
      },
    );
  }
}

class _PluginMcpDialog extends StatefulWidget {
  const _PluginMcpDialog({required this.plugin, required this.controller});

  final PluginInfo plugin;
  final PluginServiceController controller;

  @override
  State<_PluginMcpDialog> createState() => _PluginMcpDialogState();
}

class _PluginMcpDialogState extends State<_PluginMcpDialog>
    with BufferedConsoleLogHost<_PluginMcpDialog> {
  @override
  String get consoleLogTag => 'plugin_service_view';

  @override
  Duration get consoleFollowDuration => _kLogFollowDuration;

  bool _checking = true;
  bool _mcpInstalled = false;
  String? _mcpVersion;
  bool _operating = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    unawaited(_checkMcpStatus());
  }

  Future<bool> _checkMcpStatus() async {
    setState(() => _checking = true);
    var succeeded = true;
    try {
      if (widget.plugin.id == PluginCatalogIds.playwright) {
        // 同时检查 npm 全局包状态 和 MCP 控制器中的服务注册状态。
        // 只有两者都满足才视为「已安装」——用户在 MCP 板块删除服务卡片后，
        // 即使 npm 包仍在全局，也应视为「未注册」状态。
        bool npmInstalled = false;
        String? npmVersion;
        try {
          final listResult = await runPluginToolchainCommandOrFailed(
            'npm',
            const <String>['list', '-g', _playwrightMcpPackage, '--depth=0'],
            timeout: _kToolchainListTimeout,
          );
          npmInstalled =
              listResult.exitCode == 0 &&
              listResult.stdout.toString().contains(_playwrightMcpPackage);
          if (npmInstalled) {
            final match = RegExp(
              '$_playwrightMcpPackage@([\\d.]+)',
            ).firstMatch(listResult.stdout.toString());
            npmVersion = match?.group(1);
          }
        } catch (error, stack) {
          succeeded = false;
          silentLog(
            'plugin_service_view',
            '检查 Playwright MCP npm 包',
            error,
            stack,
          );
        }

        // 检查 MCP 控制器中是否注册了 Playwright MCP 服务
        bool mcpRegistered = false;
        if (mounted) {
          try {
            final mcpController = context.read<McpController>();
            mcpRegistered = mcpController.servers.any(_isPlaywrightMcpServer);
          } catch (error, stack) {
            succeeded = false;
            silentLog(
              'plugin_service_view',
              '检查 Playwright MCP 注册表',
              error,
              stack,
            );
          }
        }

        _mcpInstalled = npmInstalled && mcpRegistered;
        _mcpVersion = npmVersion;
      }
    } catch (error, stack) {
      succeeded = false;
      silentLog('plugin_service_view', '检查 Playwright MCP', error, stack);
    }
    if (mounted) setState(() => _checking = false);
    return succeeded && mounted;
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
      resetConsoleLog();
    });
    appendConsoleLine('> npm ${args.join(' ')}');
    appendConsoleLine('');
    try {
      final result = await runPluginToolchainCommandWithLineLogging(
        'npm',
        args,
        timeout: const Duration(minutes: 3),
        tag: 'plugin_service_view',
        onStdoutLine: appendConsoleLine,
        onStderrLine: appendConsoleLine,
        onTimeout: () =>
            appendConsoleLine(l10n.pluginServiceMcpOperationTimeout),
      );
      final exitCode = result.exitCode;
      if (exitCode == 0) {
        // npm 操作成功后先同步 MCP 配置，再复检最终状态，避免短暂误报未安装。
        final synced = mounted && await _syncMcpController(action);
        if (!mounted) return;
        if (!synced) {
          const message = 'MCP 服务配置同步失败';
          appendConsoleLine(message);
          _error = message;
        } else {
          final checked = await _checkMcpStatus();
          if (!mounted) return;
          final shouldBeInstalled = action != _PluginServiceAction.uninstall;
          if (!checked || _mcpInstalled != shouldBeInstalled) {
            final message = l10n.pluginServiceMcpVerificationFailed;
            appendConsoleLine(message);
            _error = message;
          }
        }
        if (_error == null) {
          appendConsoleLine('');
          appendConsoleLine(
            l10n.pluginServiceMcpOperationCompleted(actionLabel, exitCode),
          );
        }
      } else {
        appendConsoleLine('');
        final message = l10n.pluginServiceMcpOperationFailed(
          actionLabel,
          exitCode,
        );
        appendConsoleLine(message);
        _error = message;
      }
    } catch (error, stack) {
      silentLog('plugin_service_view', '执行 Playwright MCP 操作', error, stack);
      if (!mounted) return;
      appendConsoleLine('');
      final message = l10n.pluginServiceMcpOperationError(
        userFailureMessage(
          error,
          fallback: openHandLocalizedText(
            context,
            zh: 'MCP 操作失败，请稍后重试。',
            zhHant: 'MCP 操作失敗，請稍後重試。',
            en: 'The MCP operation failed. Please try again later.',
            fr: 'L’opération MCP a échoué. Réessayez plus tard.',
            de: 'Der MCP-Vorgang ist fehlgeschlagen. Bitte später erneut versuchen.',
            ja: 'MCP 操作に失敗しました。しばらくしてから再試行してください。',
          ),
        ),
      );
      appendConsoleLine(message);
      _error = message;
    }
    if (mounted) setState(() => _operating = false);
  }

  Future<bool> _syncMcpController(_PluginServiceAction action) async {
    try {
      if (!mounted) return false;
      final mcpController = context.read<McpController>();
      const mcpName = _playwrightMcpServerName;
      if (action == _PluginServiceAction.install ||
          action == _PluginServiceAction.update) {
        // 注册/更新 MCP 服务到 MCP 板块
        final existing = mcpController.servers
            .where(_isPlaywrightMcpServer)
            .firstOrNull;
        final server =
            existing?.copyWith(
              type: McpServerType.stdio,
              enabled: true,
              command: 'npx',
              args: const <String>[_playwrightMcpPackage],
            ) ??
            const McpServer(
              name: mcpName,
              type: McpServerType.stdio,
              enabled: true,
              command: 'npx',
              args: <String>[_playwrightMcpPackage],
              visibleTemplateIds: <String>{
                AiPromptTemplatePolicies.webReverseExpertTemplateId,
              },
            );
        return await mcpController.saveServer(
          server,
          previousName: existing?.name ?? mcpName,
        );
      } else if (action == _PluginServiceAction.uninstall) {
        // 从 MCP 板块移除
        final existing = mcpController.servers
            .where(_isPlaywrightMcpServer)
            .toList();
        var succeeded = true;
        for (final s in existing) {
          succeeded = await mcpController.deleteServer(s) && succeeded;
        }
        return succeeded;
      }
      return false;
    } catch (error, stack) {
      silentLog('plugin_service_view', '同步 MCP 服务操作', error, stack);
      return false;
    }
  }

  Future<void> _installOrUpdateMcp(_PluginServiceAction action) {
    return _runMcpOperation(action, <String>[
      'install',
      '-g',
      '$_playwrightMcpPackage@latest',
    ]);
  }

  Future<void> _installMcp() =>
      _installOrUpdateMcp(_PluginServiceAction.install);

  Future<void> _updateMcp() => _installOrUpdateMcp(_PluginServiceAction.update);

  Future<void> _uninstallMcp() => _runMcpOperation(
    _PluginServiceAction.uninstall,
    ['uninstall', '-g', _playwrightMcpPackage],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return buildOpenHandToolDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightCompact,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildOpenHandToolDialogHeader(
            context: context,
            icon: Icons.hub_rounded,
            title: '${widget.plugin.name} MCP',
            subtitle: _playwrightMcpPackage,
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          // 状态 + 操作按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: OpenHandContentStateSwitcher(
              stateKey: _checking ? 'checking' : 'ready',
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
                        kOpenHandHGap8,
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
                          kOpenHandHGap6,
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
          ),
          OpenHandInlineErrorText(message: _error),
          if (logLines.isNotEmpty || _operating)
            Flexible(
              child: OpenHandConsoleLogPanel(
                lineCount: logLines.length,
                lineAt: (index) => logLines[index],
                controller: logScrollController,
                onNotification: logScrollGuard.handleNotification,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                emptyPlaceholder: const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
