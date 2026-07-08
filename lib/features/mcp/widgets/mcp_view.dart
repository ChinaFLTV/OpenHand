import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../app/support/url_validation.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/feature_page_shell.dart';
import '../../../shared/ui/feature_state_card.dart';
import '../../../shared/ui/hover_lift.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_inline_notice.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../../../shared/ui/persistence_issue_card.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/localized_text.dart';
import '../../../shared/util/structured_text_format.dart';
import '../../../shared/util/text_clip.dart';
import '../../ai/index.dart' show AiToolRuntimeService;
import '../../instructions/index.dart';
import '../../knowledge_base/index.dart';
import '../../memory/index.dart';
import '../../skills/index.dart';
import '../../thread_template_runtime/index.dart';
import '../data/mcp_store.dart';
import '../mcp_controller.dart';
import '../model/mcp_http_headers.dart';
import '../model/mcp_server.dart';
import '../model/mcp_server_health.dart';
import '../model/mcp_server_ops.dart';
import '../model/mcp_tool.dart';
import '../service/mcp_ops_endpoint.dart';
import '../service/mcp_stdio_process_manager.dart';
import '../service/mcp_tool_discovery_service.dart';
import 'mcp_dialog_utils.dart';
import 'mcp_keyword_index_progress_dialog.dart';
import 'mcp_stdio_dialogs.dart';

enum _McpCardAction { edit, delete, viewHistory, viewDetails }

const int _mcpToolPreviewCollapsedLimit = 8;
const double _mcpToolDebugMenuGap = 8;
const double _mcpToolDebugMenuMinWidth = 240;
const double _mcpToolDebugMenuMaxWidth = 520;
const double _mcpToolDebugMenuMaxHeight = 360;
const double _mcpToolDebugMenuItemInset = 8;
const double _mcpToolDebugMenuItemRadius = 10;
const Duration _mcpForceProbeResetDelay = Duration(milliseconds: 200);
const Duration _mcpToolPreviewExpandDuration = Duration(milliseconds: 220);

Duration _mcpMotionDuration(BuildContext context, Duration duration) {
  return openHandMotionDuration(context, duration);
}

class McpView extends StatefulWidget {
  const McpView({super.key});

  @override
  State<McpView> createState() => _McpViewState();
}

class _McpViewState extends State<McpView> with WidgetsBindingObserver {
  McpController? _mcpController;
  bool _pageActiveSyncScheduled = false;
  bool? _pendingPageActiveState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<McpController>();
    if (!identical(_mcpController, controller)) {
      _mcpController?.setPageActive(false);
      _mcpController = controller;
    }
    _schedulePageActiveStateSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _schedulePageActiveStateSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mcpController?.setPageActive(false);
    super.dispose();
  }

  void _schedulePageActiveStateSync() {
    _pendingPageActiveState = _desiredPageActiveState();
    if (_pageActiveSyncScheduled) {
      return;
    }
    _pageActiveSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageActiveSyncScheduled = false;
      if (!mounted) {
        return;
      }
      final controller = _mcpController;
      final nextPageActiveState = _pendingPageActiveState;
      _pendingPageActiveState = null;
      if (controller == null || nextPageActiveState == null) {
        return;
      }
      controller.setPageActive(nextPageActiveState);
    });
  }

  bool _desiredPageActiveState() {
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    return lifecycleState == null ||
        lifecycleState == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mcpSnapshot = context
        .select<
          McpController,
          ({
            bool isLoading,
            String? errorMessage,
            List<McpServer> servers,
            McpPersistenceIssue? persistenceIssue,
          })
        >((controller) {
          return (
            isLoading: controller.isLoading,
            errorMessage: controller.errorMessage,
            servers: controller.servers,
            persistenceIssue: controller.persistenceIssue,
          );
        });
    final mcpController = context.read<McpController>();
    final mcpEnabled = context.select<SettingsController, bool>(
      (controller) => controller.mcpEnabled,
    );

    final actions = Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      children: [
        FilledButton.tonalIcon(
          onPressed: mcpSnapshot.isLoading
              ? null
              : () => mcpController.refresh(),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.mcpRefresh),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _showMcpOpsDialog(context),
          icon: const Icon(Icons.dns_rounded),
          label: Text(_localizedText(context, zh: 'MCP服务器', en: 'MCP Server')),
        ),
        OutlinedButton.icon(
          onPressed: () => _openDirectory(context),
          icon: const Icon(Icons.folder_open_rounded),
          label: Text(l10n.mcpOpenDirectory),
        ),
        OutlinedButton.icon(
          onPressed: () => _showSnapshotExportMenu(context),
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(
            _localizedText(context, zh: '导出快照', en: 'Export snapshot'),
          ),
        ),
        OutlinedButton.icon(
          onPressed: mcpController.isBuildingKeywordIndex
              ? null
              : () => _buildKeywordIndex(context),
          icon: const Icon(Icons.travel_explore_rounded),
          label: Text(l10n.mcpBuildKeywordIndex),
        ),
        OutlinedButton.icon(
          onPressed: mcpSnapshot.servers.isEmpty
              ? null
              : () => _showProbeDetailsDialog(context),
          icon: const Icon(Icons.radar_rounded),
          label: Text(_localizedText(context, zh: '探测详情', en: 'Probe Details')),
        ),
        FilledButton.icon(
          onPressed: () => _showServerDialog(context),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.mcpNewServer),
        ),
      ],
    );

    return FeaturePageShell(
      title: l10n.mcpPageTitle,
      subtitle: l10n.mcpPageSubtitle,
      actions: actions,
      successSignal: mcpController.saveSuccessSignal,
      notices: [
        if (!mcpEnabled)
          FeatureStateCard.inline(
            icon: Icons.toggle_off_rounded,
            tone: FeatureStateTone.secondary,
            title: l10n.mcpDisabledTitle,
            body: l10n.mcpDisabledBody,
          ),
        if (mcpSnapshot.persistenceIssue != null)
          _McpPersistenceIssueCard(
            issue: mcpSnapshot.persistenceIssue!,
            onDismiss: mcpController.clearPersistenceIssue,
          ),
      ],
      body: _buildBody(
        context,
        isLoading: mcpSnapshot.isLoading,
        errorMessage: mcpSnapshot.errorMessage,
        servers: mcpSnapshot.servers,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required bool isLoading,
    required String? errorMessage,
    required List<McpServer> servers,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.read<McpController>();
    final linkageController = context.watch<TemplateRuntimeLinkageController>();
    final templateCandidates = _templateMcpCandidateEntries(controller);
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null) {
      return FeatureStateCard.centered(
        key: const ValueKey<String>('mcp-error'),
        icon: Icons.error_outline_rounded,
        tone: FeatureStateTone.error,
        title: l10n.mcpLoadFailedTitle,
        body: errorMessage,
        action: OpenHandDialogActionButton.primary(
          onPressed: () => context.read<McpController>().refresh(),
          label: l10n.mcpRefresh,
        ),
      );
    }
    if (servers.isEmpty) {
      return ListView(
        key: const ValueKey<String>('mcp-empty'),
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
        children: [
          for (final entry in templateCandidates) ...[
            _TemplateMcpCandidateCard(
              spec: entry.spec,
              capability: entry.capability,
              linkageController: linkageController,
              onRegister: entry.capability.hasSuggestedServer
                  ? () => _registerTemplateMcpCapability(
                      context,
                      entry.capability,
                    )
                  : null,
            ),
            const SizedBox(height: 14),
          ],
          FeatureStateCard.inline(
            icon: Icons.hub_outlined,
            title: l10n.mcpEmptyTitle,
            body: l10n.mcpEmptyBody,
          ),
        ],
      );
    }

    return ListView(
      key: const ValueKey<String>('mcp-list'),
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
      cacheExtent: 600,
      children: [
        for (final entry in templateCandidates) ...[
          SettingsAwareAppearOnce(
            key: ValueKey<String>(
              'mcp-template-candidate-${entry.spec.templateId}-${entry.capability.id}',
            ),
            child: _TemplateMcpCandidateCard(
              spec: entry.spec,
              capability: entry.capability,
              linkageController: linkageController,
              onRegister: entry.capability.hasSuggestedServer
                  ? () => _registerTemplateMcpCapability(
                      context,
                      entry.capability,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 14),
        ],
        for (final server in servers) ...[
          SettingsAwareAppearOnce(
            key: ValueKey<String>('mcp-server-appear-${server.name}'),
            child: RepaintBoundary(
              child:
                  Selector<
                    McpController,
                    ({McpServerHealth healthStatus, McpToolCatalog toolCatalog})
                  >(
                    key: ValueKey<String>('mcp-server-${server.name}'),
                    selector: (context, controller) => (
                      healthStatus: controller.healthStatusFor(server.name),
                      toolCatalog: controller.toolCatalogFor(server.name),
                    ),
                    builder: (context, cardState, child) {
                      final controller = context.read<McpController>();
                      return _McpServerCard(
                        key: ValueKey<String>('mcp-server-card-${server.name}'),
                        server: server,
                        healthStatus: cardState.healthStatus,
                        toolCatalog: cardState.toolCatalog,
                        onTap: () =>
                            _showServerDialog(context, initialServer: server),
                        onToggleEnabled: (enabled) =>
                            _updateServerEnabled(context, server.name, enabled),
                        onCheckHealth: () =>
                            controller.checkServerHealth(server.name),
                        onRefreshTools: () =>
                            controller.refreshServerTools(server.name),
                        onReconnect: () =>
                            controller.reconnectServer(server.name),
                        onActionSelected: (action) {
                          switch (action) {
                            case _McpCardAction.edit:
                              _showServerDialog(context, initialServer: server);
                            case _McpCardAction.delete:
                              _confirmDeleteServer(context, server);
                            case _McpCardAction.viewHistory:
                              _showHealthHistorySheet(context, server.name);
                            case _McpCardAction.viewDetails:
                              _showServerDetailsSheet(context, server);
                          }
                        },
                      );
                    },
                  ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  Future<void> _registerTemplateMcpCapability(
    BuildContext context,
    TemplateRuntimeMcpCapabilitySpec capability,
  ) async {
    final name = capability.suggestedServerName?.trim();
    final command = capability.suggestedCommand?.trim();
    final url = capability.suggestedUrl?.trim();
    final hasPlaceholder =
        (command?.contains('<') ?? false) ||
        (url?.contains('<') ?? false) ||
        capability.suggestedArgs.any(
          (arg) => arg.contains('<') || arg.contains('>'),
        );
    if (name == null ||
        name.isEmpty ||
        hasPlaceholder ||
        ((command == null || command.isEmpty) &&
            (url == null || url.isEmpty))) {
      _showSnackBar(
        context,
        _localizedText(
          context,
          zh: '该 MCP 需要先按服务说明填写包名或地址。',
          en: 'This MCP needs a concrete package name or URL first.',
        ),
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    final saved = await context.read<McpController>().saveServer(
      McpServer(
        name: name,
        type: url != null && url.isNotEmpty
            ? McpServerType.sse
            : McpServerType.stdio,
        enabled: true,
        url: url ?? '',
        command: command ?? '',
        args: capability.suggestedArgs,
      ),
    );
    if (!context.mounted) return;
    _showSnackBar(
      context,
      saved
          ? _localizedText(
              context,
              zh: '已添加 MCP 服务：$name',
              en: 'MCP added: $name',
              zhHant: '已新增 MCP 服務：$name',
              fr: 'MCP ajouté : $name',
              de: 'MCP hinzugefügt: $name',
              ja: 'MCP を追加しました: $name',
            )
          : _localizedText(
              context,
              zh: 'MCP 服务已存在或名称冲突：$name',
              en: 'MCP exists or name conflicts: $name',
              zhHant: 'MCP 服務已存在或名稱衝突：$name',
              fr: 'Le MCP existe déjà ou le nom est en conflit : $name',
              de: 'MCP existiert bereits oder der Name kollidiert: $name',
              ja: 'MCP は既に存在するか、名前が競合しています: $name',
            ),
      kind: saved ? OpenHandSnackKind.success : OpenHandSnackKind.error,
    );
  }

  Future<void> _openDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<McpController>().openStorageDirectory();
    } catch (error, stack) {
      silentLog('mcp_view', 'open MCP storage directory', error, stack);
      if (!context.mounted) {
        return;
      }
      _showSnackBar(
        context,
        l10n.mcpOperationFailed,
        kind: OpenHandSnackKind.error,
      );
    }
  }

  Future<void> _buildKeywordIndex(BuildContext context) async {
    // 防抖：服务层已有单飞，但 UI 层也防止快速重复点击进 dialog 队列。
    final controller = context.read<McpController>();
    if (controller.isBuildingKeywordIndex) return;
    await showMcpKeywordIndexProgressDialog(context);
  }

  void _showProbeDetailsDialog(BuildContext context) {
    showAnimatedDialog(
      context: context,
      builder: (ctx) => const _McpProbeDetailsDialog(),
    );
  }

  void _showMcpOpsDialog(BuildContext context) {
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => const _McpOpsDialog(),
    );
  }

  Future<void> _showServerDialog(
    BuildContext context, {
    McpServer? initialServer,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.read<McpController>();
    final existingNames = controller.servers
        .where((item) => item.name != initialServer?.name)
        .map((item) => item.name.toLowerCase())
        .toSet();

    final submitted = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _McpServerEditorDialog(
          initialServer: initialServer,
          existingNames: existingNames,
        );
      },
    );

    if (!context.mounted || submitted != true) {
      return;
    }
    _showSnackBar(
      context,
      initialServer == null ? l10n.mcpServerCreated : l10n.mcpServerUpdated,
      kind: OpenHandSnackKind.success,
    );
  }

  Future<void> _confirmDeleteServer(
    BuildContext context,
    McpServer server,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    // 对于 STDIO 类型的 npx/uvx 服务，询问是否同时清理底层包
    bool shouldCleanupDeps = false;
    final isNpxService =
        server.type == McpServerType.stdio && _isPackageManagerCommand(server);
    final npxPackageName = isNpxService ? _extractPackageName(server) : null;

    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: l10n.mcpDeleteConfirmTitle,
      cancelLabel: l10n.commonCancel,
      confirmLabel: l10n.commonDelete,
      destructive: true,
      content: StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${l10n.mcpDeleteConfirmBody}\n\n${server.name}'),
              if (isNpxService && npxPackageName != null) ...[
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: shouldCleanupDeps,
                  onChanged: (value) {
                    setDialogState(() {
                      shouldCleanupDeps = value ?? false;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    l10n.mcpDeleteAlsoUninstallPackage(npxPackageName),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  subtitle: Text(
                    l10n.mcpDeleteAlsoUninstallPackageBody,
                    style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    final deleted = await context.read<McpController>().deleteServer(server);
    if (!context.mounted) {
      return;
    }
    if (!deleted) {
      _showSnackBar(
        context,
        l10n.mcpOperationFailed,
        kind: OpenHandSnackKind.error,
      );
      return;
    }

    // 异步清理底层依赖包（不阻塞 UI）
    if (shouldCleanupDeps && isNpxService && npxPackageName != null) {
      final cleanPkg = npxPackageName.replaceAll(RegExp(r'@[^/]*$'), '');
      _cleanupNpxDependency(context, cleanPkg, server.name);
    }

    _showSnackBar(
      context,
      l10n.mcpServerDeleted,
      kind: OpenHandSnackKind.success,
    );
  }

  /// 异步清理包管理器类型 MCP 服务的底层全局包和隔离缓存。
  Future<void> _cleanupNpxDependency(
    BuildContext context,
    String packageName,
    String serverName,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      // 1. 卸载全局包
      final result = await runTrackedProcessOrFailed(
        'npm',
        ['uninstall', '-g', packageName],
        timeout: const Duration(seconds: 30),
        environment: SystemProxyResolver.instance
            .resolveSubprocessEnvironment(),
      );

      // 2. 清理该服务在隔离缓存中的残留
      final cacheRoot = mcpStdioIsolatedCacheRoot();
      final cacheDir = Directory(cacheRoot);
      if (cacheDir.existsSync()) {
        // 尝试清理与该包名相关的缓存子目录
        try {
          await for (final entity in cacheDir.list()) {
            if (entity is Directory &&
                entity.path.contains(packageName.replaceAll('/', '-'))) {
              await entity.delete(recursive: true);
            }
          }
        } catch (error, stack) {
          silentLog(
            'mcp_view',
            'clear package cache $packageName',
            error,
            stack,
          );
        }
      }

      if (!context.mounted) return;
      if (result.exitCode == 0) {
        _showSnackBar(
          context,
          l10n.mcpDependencyCleanedUp(packageName),
          kind: OpenHandSnackKind.success,
        );
      } else {
        _showSnackBar(
          context,
          l10n.mcpDependencyCleanupFailed(packageName, result.stderr),
          kind: OpenHandSnackKind.error,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(
        context,
        l10n.mcpDependencyCleanupError(packageName, '$e'),
        kind: OpenHandSnackKind.error,
      );
    }
  }

  /// 弹出半屏 ModalBottomSheet 展示该服务的最近 30 条探测历史，用 Selector 监听
  /// controller 的健康表，使得 reconnect / 自动健康检查刷新历史时抽屉内容会自动跟新。
  void _showHealthHistorySheet(BuildContext context, String serverName) {
    showAnimatedModalSheet<void>(
      context: context,
      builder: (sheetContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
            minHeight: 240,
          ),
          child: Selector<McpController, McpServerHealth>(
            selector: (_, controller) => controller.healthStatusFor(serverName),
            builder: (context, health, _) =>
                _McpHealthHistorySheet(serverName: serverName, health: health),
          ),
        );
      },
    );
  }

  /// 服务详情抽屉：基于 healthStatus / toolCatalog 聚合可读统计（成功率、平均耗时、
  /// 最近成功 / 失败时间、Tool 数量），同时展示 server 的关键配置摘要。仅读，不可编辑。
  void _showServerDetailsSheet(BuildContext context, McpServer server) {
    showAnimatedModalSheet<void>(
      context: context,
      builder: (sheetContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.86,
            minHeight: 320,
          ),
          child:
              Selector<
                McpController,
                ({McpServerHealth health, McpToolCatalog catalog})
              >(
                selector: (_, controller) => (
                  health: controller.healthStatusFor(server.name),
                  catalog: controller.toolCatalogFor(server.name),
                ),
                builder: (context, snapshot, _) => _McpServerDetailsSheet(
                  server: server,
                  health: snapshot.health,
                  toolCatalog: snapshot.catalog,
                  onEdit: () {
                    Navigator.of(sheetContext).pop();
                    if (!context.mounted) {
                      return;
                    }
                    _showServerDialog(context, initialServer: server);
                  },
                ),
              ),
        );
      },
    );
  }

  Future<void> _showSnapshotExportMenu(BuildContext context) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final box = context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null) {
      await _exportAllSnapshots(context, _McpHistoryExportFormat.json);
      return;
    }
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final selected = await showAnimatedMenu<_McpHistoryExportFormat>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: _McpHistoryExportFormat.json,
          child: Text(
            _localizedText(
              context,
              zh: '导出快照 (JSON)',
              en: 'Export snapshot (JSON)',
            ),
          ),
        ),
        PopupMenuItem(
          value: _McpHistoryExportFormat.csv,
          child: Text(
            _localizedText(
              context,
              zh: '导出快照 (CSV)',
              en: 'Export snapshot (CSV)',
            ),
          ),
        ),
      ],
    );
    if (selected == null || !context.mounted) {
      return;
    }
    await _exportAllSnapshots(context, selected);
  }

  Future<void> _exportAllSnapshots(
    BuildContext context,
    _McpHistoryExportFormat format,
  ) async {
    final controller = context.read<McpController>();
    final servers = controller.servers;
    final entries = <Map<String, dynamic>>[];
    for (final server in servers) {
      final health = controller.healthStatusFor(server.name);
      final catalog = controller.toolCatalogFor(server.name);
      final probes = health.recentProbes;
      final successCount = probes
          .where((p) => p.status == McpServerHealthStatus.healthy)
          .length;
      entries.add({
        'name': server.name,
        'type': server.type.name,
        'enabled': server.enabled,
        'status': switch (health.status) {
          McpServerHealthStatus.healthy => 'healthy',
          McpServerHealthStatus.unhealthy => 'unhealthy',
          McpServerHealthStatus.checking => 'checking',
          McpServerHealthStatus.idle => 'idle',
        },
        'consecutiveFailures': health.consecutiveFailures,
        'lastSuccessAt': health.lastSuccessAt?.toIso8601String(),
        'latencyMs': health.latencyMs,
        'recentProbes': probes.length,
        'recentSuccesses': successCount,
        'recentFailures': probes.length - successCount,
        'toolCount': catalog.tools.length,
        'toolCatalogError': catalog.errorMessage,
      });
    }

    final String text;
    if (format == _McpHistoryExportFormat.json) {
      text = prettyPrintJson({
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'servers': entries,
      });
    } else {
      final buffer = StringBuffer()
        ..writeln(
          'name,type,enabled,status,consecutive_failures,last_success_at,'
          'latency_ms,recent_probes,recent_successes,recent_failures,tool_count,tool_catalog_error',
        );
      for (final e in entries) {
        buffer.writeln(
          [
            _csvFieldString(e['name']),
            _csvFieldString(e['type']),
            _csvFieldString(e['enabled']),
            _csvFieldString(e['status']),
            _csvFieldString(e['consecutiveFailures']),
            _csvFieldString(e['lastSuccessAt']),
            _csvFieldString(e['latencyMs']),
            _csvFieldString(e['recentProbes']),
            _csvFieldString(e['recentSuccesses']),
            _csvFieldString(e['recentFailures']),
            _csvFieldString(e['toolCount']),
            _csvFieldString(e['toolCatalogError']),
          ].join(','),
        );
      }
      text = buffer.toString();
    }

    final formatLabel = format == _McpHistoryExportFormat.json ? 'JSON' : 'CSV';
    await copyMcpTextToClipboard(
      context: context,
      text: text,
      successMessage: _localizedText(
        context,
        zh: '已将 ${entries.length} 个服务的快照以 $formatLabel 复制到剪贴板',
        en: 'Copied snapshot of ${entries.length} servers as $formatLabel to clipboard',
        zhHant: '已將 ${entries.length} 個服務的快照以 $formatLabel 複製到剪貼簿',
        fr: 'Instantané de ${entries.length} services copié en $formatLabel dans le presse-papiers',
        de: 'Snapshot von ${entries.length} Diensten als $formatLabel in die Zwischenablage kopiert',
        ja: '${entries.length} 個のサービスのスナップショットを $formatLabel としてクリップボードにコピーしました',
      ),
      logAction: 'export server snapshots',
    );
  }

  String _csvFieldString(Object? value) {
    if (value == null) return '';
    final raw = value.toString();
    final needsQuote =
        raw.contains(',') || raw.contains('"') || raw.contains('\n');
    if (!needsQuote) return raw;
    return '"${raw.replaceAll('"', '""')}"';
  }

  Future<void> _updateServerEnabled(
    BuildContext context,
    String name,
    bool enabled,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final saved = await context.read<McpController>().updateServerEnabled(
      name,
      enabled,
    );
    if (!context.mounted || saved) {
      return;
    }
    _showSnackBar(
      context,
      l10n.mcpOperationFailed,
      kind: OpenHandSnackKind.error,
    );
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    OpenHandSnackKind kind = OpenHandSnackKind.info,
  }) {
    OpenHandSnackBar.flash(context, message, kind: kind, postFrame: true);
  }
}

List<
  ({
    TemplateRuntimeDependencySpec spec,
    TemplateRuntimeMcpCapabilitySpec capability,
  })
>
_templateMcpCandidateEntries(McpController controller) {
  final entries =
      <
        ({
          TemplateRuntimeDependencySpec spec,
          TemplateRuntimeMcpCapabilitySpec capability,
        })
      >[];
  for (final spec
      in TemplateRuntimeDependencyRegistry.reverseEngineeringSpecs) {
    for (final capability in spec.mcpCapabilities) {
      final matches = _matchingServersForCapability(controller, capability);
      if (matches.isEmpty) {
        entries.add((spec: spec, capability: capability));
      }
    }
  }
  return List.unmodifiable(entries);
}

class _TemplateMcpCandidateCard extends StatelessWidget {
  const _TemplateMcpCandidateCard({
    required this.spec,
    required this.capability,
    required this.linkageController,
    required this.onRegister,
  });

  final TemplateRuntimeDependencySpec spec;
  final TemplateRuntimeMcpCapabilitySpec capability;
  final TemplateRuntimeLinkageController linkageController;
  final VoidCallback? onRegister;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final latestState = linkageController.latestCapabilityState(
      spec.templateId,
      capability.id,
    );
    final runtimeEnabledCount = linkageController.enabledSessionCount(
      spec.templateId,
      capability.id,
    );
    final ready =
        capability.openHandManaged &&
        latestState?.enabled == true &&
        latestState?.status == 'ready';
    final color = ready
        ? OpenHandStatusColors.success
        : capability.openHandManaged
        ? OpenHandStatusColors.warning
        : cs.error;
    final statusText = capability.openHandManaged
        ? latestState == null
              ? l10n.mcpTemplateSessionManaged
              : latestState.enabled
              ? l10n.mcpTemplateSessionOn(latestState.status)
              : l10n.mcpTemplateSessionOff(latestState.status)
        : l10n.mcpTemplateNotRegistered;
    final hasPlaceholder = capability.suggestedArgs.any(
      (arg) => arg.contains('<') || arg.contains('>'),
    );
    final canRegister = onRegister != null && !hasPlaceholder;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Icon(
                ready
                    ? Icons.check_circle_rounded
                    : capability.openHandManaged
                    ? Icons.motion_photos_auto_rounded
                    : Icons.add_circle_outline_rounded,
                color: color,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
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
                        _localizedText(
                          context,
                          zh: capability.labelZh,
                          en: capability.labelEn,
                          zhHant: capability.labelZhHant,
                          fr: capability.labelFr,
                          de: capability.labelDe,
                          ja: capability.labelJa,
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                      _TemplateMcpStateChip(label: statusText, color: color),
                      _TemplateMcpTinyChip(
                        icon: Icons.account_tree_rounded,
                        label: _localizedText(
                          context,
                          zh: spec.labelZh,
                          en: spec.labelEn,
                          zhHant: spec.labelZhHant,
                          fr: spec.labelFr,
                          de: spec.labelDe,
                          ja: spec.labelJa,
                        ),
                      ),
                      if (runtimeEnabledCount > 0)
                        _TemplateMcpTinyChip(
                          icon: Icons.toggle_on_rounded,
                          label: l10n.mcpTemplateRuntimeEnabledCount(
                            runtimeEnabledCount,
                          ),
                        ),
                      if (capability.packageName != null)
                        _TemplateMcpTinyChip(
                          icon: Icons.inventory_2_outlined,
                          label: capability.packageName!,
                          monospace: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      _localizedText(
                        context,
                        zh: capability.descriptionZh,
                        en: capability.descriptionEn,
                        zhHant: capability.descriptionZhHant,
                        fr: capability.descriptionFr,
                        de: capability.descriptionDe,
                        ja: capability.descriptionJa,
                      ),
                      if (latestState?.message?.trim().isNotEmpty ?? false)
                        latestState!.message!.trim(),
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (capability.suggestedServerName?.trim().isNotEmpty ??
                      false) ...[
                    const SizedBox(height: 10),
                    _TemplateMcpTinyChip(
                      icon: Icons.hub_rounded,
                      label: capability.suggestedServerName!.trim(),
                      monospace: true,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: canRegister ? onRegister : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                canRegister
                    ? _localizedText(context, zh: '注册服务', en: 'Register')
                    : _localizedText(context, zh: '需配置', en: 'Configure'),
              ),
              style: FilledButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateMcpTinyChip extends StatelessWidget {
  const _TemplateMcpTinyChip({
    required this.icon,
    required this.label,
    this.monospace = false,
  });

  final IconData icon;
  final String label;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.44)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateMcpStateChip extends StatelessWidget {
  const _TemplateMcpStateChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

List<McpServer> _matchingServersForCapability(
  McpController controller,
  TemplateRuntimeMcpCapabilitySpec capability,
) {
  return controller.servers
      .where(
        (server) => TemplateRuntimeDependencyRegistry.containsAnyKeyword(
          _mcpServerSearchText(controller, server),
          capability.keywords,
        ),
      )
      .toList(growable: false);
}

String _mcpServerSearchText(McpController controller, McpServer server) {
  return _mcpServerSearchTextForCatalog(
    server,
    controller.toolCatalogFor(server.name),
  );
}

String _mcpServerSearchTextForCatalog(
  McpServer server,
  McpToolCatalog catalog,
) {
  final buffer = StringBuffer()
    ..write(server.name)
    ..write(' ')
    ..write(server.summary)
    ..write(' ')
    ..write(server.type.transportValue);
  for (final tool in catalog.tools) {
    buffer
      ..write(' ')
      ..write(tool.id)
      ..write(' ')
      ..write(tool.name)
      ..write(' ')
      ..write(tool.description);
  }
  return buffer.toString();
}

class _McpServerEditorDialog extends StatefulWidget {
  const _McpServerEditorDialog({
    required this.existingNames,
    this.initialServer,
  });

  final McpServer? initialServer;
  final Set<String> existingNames;

  @override
  State<_McpServerEditorDialog> createState() => _McpServerEditorDialogState();
}

class _McpServerEditorDialogState extends State<_McpServerEditorDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _commandController;
  late final TextEditingController _argsController;
  late final List<_EditableHeaderRow> _headerRows;
  late McpServerType _type;
  late bool _enabled;
  bool _isSaving = false;
  String? _errorMessage;
  String? _headerErrorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialServer?.name ?? '',
    );
    _urlController = TextEditingController(
      text: widget.initialServer?.url ?? '',
    );
    _commandController = TextEditingController(
      text: widget.initialServer?.command ?? '',
    );
    _argsController = TextEditingController(
      text: widget.initialServer == null
          ? ''
          : widget.initialServer!.args.join('\n'),
    );
    _headerRows = _buildInitialHeaderRows(widget.initialServer?.headers);
    _type = widget.initialServer?.type ?? McpServerType.streamableHttp;
    _enabled = widget.initialServer?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    for (final row in _headerRows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final useUrlField =
        _type == McpServerType.streamableHttp || _type == McpServerType.sse;

    return PopScope(
      canPop: !_isSaving,
      child: buildOpenHandResponsiveDialogShell(
        context: context,
        maxWidth: 760,
        maxHeight: 760,
        safeAreaMinimum: kOpenHandDialogDefaultInsetPadding,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initialServer == null
                    ? l10n.mcpDialogCreateTitle
                    : l10n.mcpDialogEditTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          enabled: !_isSaving,
                          decoration: InputDecoration(
                            labelText: l10n.mcpNameField,
                          ),
                          validator: (value) {
                            final name = value?.trim() ?? '';
                            if (name.isEmpty) {
                              return l10n.mcpNameRequired;
                            }
                            if (widget.existingNames.contains(
                              name.toLowerCase(),
                            )) {
                              return l10n.mcpNameDuplicate;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 320,
                          child: DropdownButtonFormField<McpServerType>(
                            initialValue: _type,
                            decoration: InputDecoration(
                              labelText: l10n.mcpTypeField,
                            ),
                            items: McpServerType.values
                                .map(
                                  (item) => DropdownMenuItem<McpServerType>(
                                    value: item,
                                    child: Text(item.label(l10n)),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: _isSaving
                                ? null
                                : (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setState(() {
                                      _type = value;
                                      _headerErrorMessage = null;
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.mcpServerEnabledLabel),
                          subtitle: Text(l10n.mcpServerEnabledBody),
                          value: _enabled,
                          onChanged: _isSaving
                              ? null
                              : (value) {
                                  setState(() {
                                    _enabled = value;
                                  });
                                },
                        ),
                        const SizedBox(height: 16),
                        if (useUrlField) ...[
                          TextFormField(
                            controller: _urlController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: l10n.mcpUrlField,
                            ),
                            validator: (value) {
                              final rawValue = value?.trim() ?? '';
                              if (rawValue.isEmpty) {
                                return l10n.mcpUrlRequired;
                              }
                              if (!isValidHttpUrl(rawValue)) {
                                return l10n.mcpUrlInvalid;
                              }
                              if (context.read<McpController>().isSelfReferencingServer(
                                McpServer(
                                  name: _nameController.text.trim(),
                                  type: _type,
                                  enabled: _enabled,
                                  url: rawValue,
                                ),
                              )) {
                                return _localizedText(
                                  context,
                                  zh: '该地址指向 OpenHand 自身的 MCP 运维入口，无法添加，否则会造成引用循环与工具无限膨胀。',
                                  en: 'This URL points to OpenHand\'s own MCP operations endpoint and cannot be added; it would create a reference cycle and unbounded tool growth.',
                                );
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildHeaderEditor(context),
                        ] else ...[
                          TextFormField(
                            controller: _commandController,
                            enabled: !_isSaving,
                            decoration: InputDecoration(
                              labelText: l10n.mcpCommandField,
                            ),
                            validator: (value) {
                              if ((value?.trim() ?? '').isEmpty) {
                                return l10n.mcpCommandRequired;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _argsController,
                            enabled: !_isSaving,
                            minLines: 4,
                            maxLines: 8,
                            decoration: InputDecoration(
                              labelText: l10n.mcpArgsField,
                              hintText: l10n.mcpArgsHint,
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (_isSaving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OpenHandDialogActionButton.secondary(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    label: l10n.commonCancel,
                  ),
                  const SizedBox(width: 12),
                  OpenHandDialogActionButton.primary(
                    onPressed: _isSaving ? null : _handleSave,
                    label: l10n.commonSave,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final l10n = AppLocalizations.of(context)!;
    final useUrlField =
        _type == McpServerType.streamableHttp || _type == McpServerType.sse;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final headerParseResult = useUrlField
        ? _collectHeadersFromRows()
        : const _HeaderParseResult(headers: <String, String>{});
    if (headerParseResult.errorMessage != null) {
      setState(() {
        _headerErrorMessage = headerParseResult.errorMessage;
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _headerErrorMessage = null;
    });

    final server = McpServer(
      name: _nameController.text.trim(),
      type: _type,
      enabled: _enabled,
      url: _urlController.text.trim(),
      command: _commandController.text.trim(),
      args: splitTrimmedNonEmpty(_argsController.text, separator: '\n'),
      headers: headerParseResult.headers,
    );

    late final bool saved;
    try {
      saved = await context.read<McpController>().saveServer(
        server,
        previousName: widget.initialServer?.name,
      );
    } catch (error, stack) {
      silentLog('mcp_view', 'save MCP server', error, stack);
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.mcpOperationFailed;
      });
      return;
    }

    if (!mounted) {
      return;
    }
    if (!saved) {
      setState(() {
        _isSaving = false;
        _errorMessage = l10n.mcpOperationFailed;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  Widget _buildHeaderEditor(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localizedText(
                      context,
                      zh: '请求 Header',
                      en: 'Request Headers',
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _localizedText(
                      context,
                      zh: '按键值对逐项维护，将随 HTTP / SSE 请求一起发送。',
                      en: 'Manage headers as key-value rows for HTTP / SSE requests.',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              key: const ValueKey<String>('mcpHeaderAddButton'),
              onPressed: _isSaving ? null : _addHeaderRow,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                _localizedText(context, zh: '新增 Header', en: 'Add Header'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          children: _headerRows
              .asMap()
              .entries
              .map((entry) {
                final index = entry.key;
                final row = entry.value;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == _headerRows.length - 1 ? 0 : 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: ValueKey<String>('mcpHeaderNameField-$index'),
                          controller: row.nameController,
                          enabled: !_isSaving,
                          onChanged: (_) => _clearHeaderError(),
                          decoration: InputDecoration(
                            labelText: _localizedText(
                              context,
                              zh: 'Header 名称',
                              en: 'Header Name',
                            ),
                            hintText: _localizedText(
                              context,
                              zh: '例如 Authorization',
                              en: 'e.g. Authorization',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: ValueKey<String>('mcpHeaderValueField-$index'),
                          controller: row.valueController,
                          enabled: !_isSaving,
                          onChanged: (_) => _clearHeaderError(),
                          decoration: InputDecoration(
                            labelText: _localizedText(
                              context,
                              zh: 'Header 值',
                              en: 'Header Value',
                            ),
                            hintText: _localizedText(
                              context,
                              zh: '例如 Bearer token',
                              en: 'e.g. Bearer token',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: IconButton(
                          key: ValueKey<String>('mcpHeaderRemoveButton-$index'),
                          onPressed: _isSaving
                              ? null
                              : () => _removeHeaderRow(index),
                          tooltip: _localizedText(
                            context,
                            zh: '删除 Header',
                            en: 'Remove Header',
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ),
                    ],
                  ),
                );
              })
              .toList(growable: false),
        ),
        if (_headerErrorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _headerErrorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  List<_EditableHeaderRow> _buildInitialHeaderRows(
    Map<String, String>? headers,
  ) {
    final entries = headers?.entries.toList(growable: false) ?? const [];
    if (entries.isEmpty) {
      return <_EditableHeaderRow>[_EditableHeaderRow()];
    }
    return entries
        .map((entry) => _EditableHeaderRow(name: entry.key, value: entry.value))
        .toList();
  }

  void _addHeaderRow() {
    setState(() {
      _headerRows.add(_EditableHeaderRow());
      _headerErrorMessage = null;
    });
  }

  void _removeHeaderRow(int index) {
    setState(() {
      _headerErrorMessage = null;
      if (_headerRows.length == 1) {
        _headerRows.single.clear();
        return;
      }
      final removedRow = _headerRows.removeAt(index);
      removedRow.dispose();
    });
  }

  void _clearHeaderError() {
    if (_headerErrorMessage == null) {
      return;
    }
    setState(() {
      _headerErrorMessage = null;
    });
  }

  _HeaderParseResult _collectHeadersFromRows() {
    final headers = <String, String>{};
    final seenNames = <String>{};
    for (var index = 0; index < _headerRows.length; index++) {
      final row = _headerRows[index];
      final name = row.nameController.text.trim();
      final value = row.valueController.text.trim();
      if (name.isEmpty && value.isEmpty) {
        continue;
      }
      if (name.isEmpty || value.isEmpty) {
        return _HeaderParseResult(
          headers: const <String, String>{},
          errorMessage: _localizedText(
            context,
            zh: '第 ${index + 1} 个 Header 的名称和值都不能为空',
            en: 'Header ${index + 1} must include both name and value',
            zhHant: '第 ${index + 1} 個 Header 的名稱和值都不能為空',
            fr: 'L’en-tête ${index + 1} doit inclure un nom et une valeur',
            de: 'Header ${index + 1} muss sowohl Name als auch Wert enthalten',
            ja: 'ヘッダー ${index + 1} には名前と値の両方が必要です',
          ),
        );
      }
      if (!isValidMcpHttpHeaderName(name)) {
        return _HeaderParseResult(
          headers: const <String, String>{},
          errorMessage: _localizedText(
            context,
            zh: '第 ${index + 1} 个 Header 名称只能使用 ASCII 字母、数字和标准 HTTP 符号',
            en: 'Header ${index + 1} name must use ASCII letters, digits and standard HTTP token symbols',
            zhHant: '第 ${index + 1} 個 Header 名稱只能使用 ASCII 字母、數字和標準 HTTP 符號',
            fr: 'Le nom de l’en-tête ${index + 1} doit utiliser des lettres ASCII, des chiffres et les symboles HTTP standard',
            de: 'Header ${index + 1} muss ASCII-Buchstaben, Ziffern und standardmäßige HTTP-Token-Zeichen verwenden',
            ja: 'ヘッダー ${index + 1} の名前は ASCII 英数字と標準 HTTP 記号のみ使用できます',
          ),
        );
      }
      if (!isValidMcpHttpHeaderValue(value)) {
        return _HeaderParseResult(
          headers: const <String, String>{},
          errorMessage: _localizedText(
            context,
            zh: '第 ${index + 1} 个 Header 值不能包含中文、换行或控制字符；请使用 ASCII / Latin-1 安全值',
            en: 'Header ${index + 1} value cannot contain Chinese characters, line breaks or control characters; use an ASCII / Latin-1 safe value',
            zhHant:
                '第 ${index + 1} 個 Header 值不能包含中文、換行或控制字元；請使用 ASCII / Latin-1 安全值',
            fr: 'La valeur de l’en-tête ${index + 1} ne peut pas contenir de caractères chinois, de retours à la ligne ni de caractères de contrôle ; utilisez une valeur ASCII / Latin-1 sûre',
            de: 'Header ${index + 1} darf keine chinesischen Zeichen, Zeilenumbrüche oder Steuerzeichen enthalten; verwenden Sie einen ASCII-/Latin-1-sicheren Wert',
            ja: 'ヘッダー ${index + 1} の値には中国語、改行、制御文字を含められません。ASCII / Latin-1 で安全な値を使用してください',
          ),
        );
      }
      final normalizedName = name.toLowerCase();
      if (!seenNames.add(normalizedName)) {
        return _HeaderParseResult(
          headers: const <String, String>{},
          errorMessage: _localizedText(
            context,
            zh: '第 ${index + 1} 个 Header 名称重复',
            en: 'Header ${index + 1} uses a duplicate name',
            zhHant: '第 ${index + 1} 個 Header 名稱重複',
            fr: 'L’en-tête ${index + 1} utilise un nom en double',
            de: 'Header ${index + 1} verwendet einen doppelten Namen',
            ja: 'ヘッダー ${index + 1} の名前が重複しています',
          ),
        );
      }
      headers[name] = value;
    }
    return _HeaderParseResult(
      headers: Map<String, String>.unmodifiable(headers),
    );
  }
}

extension on McpServerType {
  String label(AppLocalizations l10n) {
    return switch (this) {
      McpServerType.streamableHttp => l10n.mcpTransportStreamableHttp,
      McpServerType.sse => l10n.mcpTransportSse,
      McpServerType.stdio => l10n.mcpTransportStdio,
    };
  }
}

class _HeaderParseResult {
  const _HeaderParseResult({required this.headers, this.errorMessage});

  final Map<String, String> headers;
  final String? errorMessage;
}

class _EditableHeaderRow {
  _EditableHeaderRow({String name = '', String value = ''})
    : nameController = TextEditingController(text: name),
      valueController = TextEditingController(text: value);

  final TextEditingController nameController;
  final TextEditingController valueController;

  void clear() {
    nameController.clear();
    valueController.clear();
  }

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}

const double _mcpOpsDialogMaxWidth = 1180;
const double _mcpOpsDialogMaxHeight = 860;
const double _mcpOpsOuterRadius = 28;
const double _mcpOpsShellRadius = 20;
const double _mcpOpsPanelRadius = 14;
const double _mcpOpsControlRadius = 12;
const double _mcpOpsGridGap = 16;
const double _mcpOpsTerminalRadius = 12;
const double _mcpOpsMetricWideBreakpoint = 860;
const double _mcpOpsMetricMediumBreakpoint = 560;
const int _mcpOpsExposureInitialLimit = 14;
const int _mcpOpsExposurePageSize = 18;
const Color _mcpOpsTerminalBackground = Color(0xFF0B0D10);

class _McpOpsDialog extends StatefulWidget {
  const _McpOpsDialog();

  @override
  State<_McpOpsDialog> createState() => _McpOpsDialogState();
}

class _McpOpsDialogState extends State<_McpOpsDialog> {
  final Map<McpOpsExposureSurface, int> _exposureLimits =
      <McpOpsExposureSurface, int>{};
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _rpmController;
  late final TextEditingController _thresholdController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _approvalTimeoutController;
  late final TextEditingController _workspaceController;
  late final TextEditingController _authTokenController;
  late final TextEditingController _allowedClientsController;
  late final TextEditingController _allowedIpsController;
  late final TextEditingController _allowedTimeController;
  late final TextEditingController _exposureSearchController;
  late bool _autoStart;
  late bool _requireAuthToken;
  late bool _capturePayload;
  late McpOpsNetworkMode _networkMode;
  late McpOpsInvocationMode _invocationMode;
  late McpOpsWriteMode _writeMode;
  late Set<McpOpsExposureSurface> _surfaces;
  late Set<String> _hiddenItems;
  late Set<String> _hiddenEndpoints;
  bool _saving = false;
  String? _configMessage;

  @override
  void initState() {
    super.initState();
    final config = context.read<McpController>().opsConfig;
    _hostController = TextEditingController(text: config.listenHost);
    _portController = TextEditingController(text: '${config.listenPort}');
    _rpmController = TextEditingController(text: '${config.rpmLimit}');
    _thresholdController = TextEditingController(
      text: '${config.callThreshold}',
    );
    _timeoutController = TextEditingController(text: '${config.timeoutMs}');
    _approvalTimeoutController = TextEditingController(
      text: '${config.approvalTimeoutMs}',
    );
    _workspaceController = TextEditingController(text: config.workspaceRoot);
    _authTokenController = TextEditingController(text: config.authToken);
    _allowedClientsController = TextEditingController(
      text: config.allowedClients.join('\n'),
    );
    _allowedIpsController = TextEditingController(
      text: config.allowedIpCidrs.join('\n'),
    );
    _allowedTimeController = TextEditingController(
      text: config.allowedTimeWindows.join('\n'),
    );
    _exposureSearchController = TextEditingController();
    _autoStart = config.autoStart;
    _requireAuthToken = config.requireAuthToken;
    _capturePayload = config.capturePayload;
    _networkMode = config.networkMode;
    _invocationMode = config.invocationMode;
    _writeMode = config.writeMode;
    _surfaces = Set<McpOpsExposureSurface>.from(config.exposedSurfaces);
    _hiddenItems = Set<String>.from(config.hiddenItemIds);
    _hiddenEndpoints = Set<String>.from(config.hiddenEndpointIds);
  }

  @override
  void dispose() {
    for (final controller in [
      _hostController,
      _portController,
      _rpmController,
      _thresholdController,
      _timeoutController,
      _approvalTimeoutController,
      _workspaceController,
      _authTokenController,
      _allowedClientsController,
      _allowedIpsController,
      _allowedTimeController,
      _exposureSearchController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<McpController>();
    final snapshot = controller.opsSnapshot;
    final config = _buildConfig();
    final endpoint = mcpOpsClientAuthority(snapshot, config);
    final bindEndpoint = mcpOpsBindAuthority(snapshot, config);
    final endpointUri = 'http://$endpoint/mcp';
    final bindEndpointUri = 'http://$bindEndpoint/mcp';
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: _mcpOpsDialogMaxWidth,
      maxHeight: _mcpOpsDialogMaxHeight,
      maxWidthFraction: 0.96,
      maxHeightFraction: 0.94,
      horizontalMargin: 32,
      verticalMargin: 64,
      minAvailableWidth: 340,
      expandToMax: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_mcpOpsOuterRadius),
      ),
      child: DefaultTabController(
        length: 3,
        child: _McpOpsDialogSurface(
          child: _McpOpsConsoleShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _McpOpsConsoleHeader(
                  snapshot: snapshot,
                  endpointUri: endpointUri,
                  bindEndpointUri: bindEndpointUri,
                  config: config,
                  onCopyEndpoint: () => _copyOpsEndpoint(context, endpointUri),
                  onCopyCursorConfig: () =>
                      _copyCursorConfig(context, endpointUri, config),
                  onConnectivityTest: () => _testConnectivity(context),
                  onStart: () => _startServer(context),
                  onRestart: () => _restartServer(context),
                  onStop: () => _stopServer(context),
                  configActionBusy: _saving,
                  configMessage: _configMessage,
                  onResetConfig: () => _resetConfigWithConfirm(context),
                  onSaveConfig: () => _saveConfig(context),
                  onClose: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(height: 12),
                const _McpOpsTabStrip(),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      Builder(
                        builder: (tabContext) =>
                            _tabScroll(tabContext, _buildOpsTab(tabContext)),
                      ),
                      Builder(
                        builder: (tabContext) =>
                            _tabScroll(tabContext, _buildConfigTab(tabContext)),
                      ),
                      Builder(builder: _buildAuditTab),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyOpsEndpoint(
    BuildContext context,
    String endpointUri,
  ) async {
    await copyMcpTextToClipboard(
      context: context,
      text: endpointUri,
      successMessage: _localizedText(
        context,
        zh: 'MCP入口已复制',
        en: 'MCP endpoint copied',
      ),
      logAction: 'copy mcp ops endpoint',
    );
  }

  Future<void> _copyCursorConfig(
    BuildContext context,
    String endpointUri,
    McpOpsConfig config,
  ) async {
    final validationMessage = _opsClientConfigValidationMessage(
      context,
      config,
    );
    if (validationMessage != null) {
      OpenHandSnackBar.flash(
        context,
        validationMessage,
        kind: OpenHandSnackKind.error,
      );
      return;
    }
    final serverConfig = <String, Object?>{'url': endpointUri};
    final token = config.authToken.trim();
    if (config.requireAuthToken && token.isNotEmpty) {
      serverConfig['headers'] = <String, String>{
        'Authorization': 'Bearer $token',
      };
    }
    final content = prettyPrintJson(
      <String, Object?>{
        'mcpServers': <String, Object?>{'openhand': serverConfig},
      },
    );
    await copyMcpTextToClipboard(
      context: context,
      text: content,
      successMessage: _localizedText(
        context,
        zh: 'Cursor MCP配置已复制',
        en: 'Cursor MCP config copied',
      ),
      logAction: 'copy openhand mcp cursor config',
    );
  }

  Widget _buildWorkspaceScopeField(BuildContext context) {
    final browseLabel = _localizedText(
      context,
      zh: '选择目录',
      en: 'Choose Directory',
    );
    final clearLabel = _localizedText(
      context,
      zh: '清除目录',
      en: 'Clear Directory',
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _workspaceController,
      builder: (context, value, _) {
        final hasPath = value.text.trim().isNotEmpty;
        return TextField(
          controller: _workspaceController,
          readOnly: true,
          showCursor: false,
          onTap: _browseWorkspaceRoot,
          decoration: InputDecoration(
            labelText: _localizedText(
              context,
              zh: '可操作文件空间',
              en: 'Workspace Scope',
            ),
            hintText: _localizedText(
              context,
              zh: '通过系统文件浏览器选择目录',
              en: 'Pick a folder with the system file browser',
            ),
            prefixIcon: const Icon(Icons.folder_open_rounded),
            suffixIconConstraints: BoxConstraints(
              minWidth: hasPath ? 92 : 48,
              minHeight: 48,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasPath)
                    Tooltip(
                      message: clearLabel,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _clearWorkspaceRoot,
                      ),
                    ),
                  Tooltip(
                    message: browseLabel,
                    child: IconButton(
                      icon: const Icon(Icons.drive_folder_upload_rounded),
                      onPressed: _browseWorkspaceRoot,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _browseWorkspaceRoot() async {
    final confirmLabel = _localizedText(
      context,
      zh: '选择目录',
      en: 'Choose Directory',
    );
    final failureLabel = _localizedText(
      context,
      zh: '打开系统文件浏览器失败',
      en: 'Failed to open file browser',
    );
    final initialDirectory = OpenHandPaths.normalizeOptionalPath(
      _workspaceController.text,
    );
    try {
      final selectedPath = await getDirectoryPath(
        confirmButtonText: confirmLabel,
        initialDirectory: initialDirectory.isEmpty ? null : initialDirectory,
      );
      if (!mounted) {
        return;
      }
      final normalizedPath = OpenHandPaths.normalizeOptionalPath(selectedPath);
      if (normalizedPath.isEmpty) {
        return;
      }
      setState(() {
        _workspaceController.text = normalizedPath;
        _configMessage = null;
      });
    } catch (error, stack) {
      silentLog('mcp', 'browse workspace scope directory', error, stack);
      if (!mounted) {
        return;
      }
      OpenHandSnackBar.flash(
        context,
        '$failureLabel：$error',
        kind: OpenHandSnackKind.error,
      );
    }
  }

  void _clearWorkspaceRoot() {
    setState(() {
      _workspaceController.clear();
      _configMessage = null;
    });
  }

  String? _opsClientConfigValidationMessage(
    BuildContext context,
    McpOpsConfig config,
  ) {
    if (!config.requireAuthToken) {
      return null;
    }
    final token = config.authToken.trim();
    if (token.isEmpty) {
      return _localizedText(
        context,
        zh: '开启令牌校验后必须填写访问令牌',
        en: 'Access token is required when token auth is enabled',
      );
    }
    if (!isValidMcpHttpHeaderValue('Bearer $token')) {
      return _localizedText(
        context,
        zh: '访问令牌会写入 Cursor Authorization Header，不能包含中文、换行或控制字符；请换成英文、数字或符号组成的安全令牌。',
        en: 'The access token is sent through the Cursor Authorization header, so it cannot contain Chinese characters, line breaks or control characters. Use a token made of English letters, digits or symbols.',
      );
    }
    return null;
  }

  Widget _tabScroll(BuildContext context, Widget child) {
    return SingleChildScrollView(
      physics: openHandDialogAwareScrollPhysics(context),
      child: Padding(padding: const EdgeInsets.only(bottom: 18), child: child),
    );
  }

  Widget _buildOpsTab(BuildContext context) {
    final controller = context.watch<McpController>();
    final snapshot = controller.opsSnapshot;
    final auditEntries = controller.opsAuditEntries;
    final config = _buildConfig();
    final stats = _McpOpsDashboardStats.from(
      snapshot: snapshot,
      auditEntries: auditEntries,
    );
    final endpoint = mcpOpsClientAuthority(snapshot, config);
    final bindEndpoint = mcpOpsBindAuthority(snapshot, config);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _McpOpsHeroPanel(
          snapshot: snapshot,
          endpoint: endpoint,
          bindEndpoint: bindEndpoint,
          config: config,
        ),
        const SizedBox(height: _mcpOpsGridGap),
        _McpOpsMetricGrid(
          children: [
            _McpOpsMetricTile(
              icon: Icons.link_rounded,
              label: _localizedText(context, zh: '当前连接数', en: 'Connections'),
              value: '${snapshot.currentConnections}',
              helper: _localizedText(context, zh: '实时会话', en: 'Live sessions'),
              onTap: () =>
                  _showOpsInsight(context, _McpOpsInsightKind.connections),
            ),
            _McpOpsMetricTile(
              icon: Icons.bolt_rounded,
              label: _localizedText(context, zh: '活跃请求', en: 'Active'),
              value: '${snapshot.activeRequests}',
              helper: _localizedText(context, zh: '执行中', en: 'In flight'),
              onTap: () =>
                  _showOpsInsight(context, _McpOpsInsightKind.activeRequests),
            ),
            _McpOpsMetricTile(
              icon: Icons.call_made_rounded,
              label: _localizedText(context, zh: '请求总数', en: 'Requests'),
              value: '${snapshot.requestTotal}',
              helper: _localizedText(
                context,
                zh: '近窗 ${stats.windowRequestCount}',
                en: 'Window ${stats.windowRequestCount}',
                zhHant: '近窗 ${stats.windowRequestCount}',
                fr: 'Fenêtre ${stats.windowRequestCount}',
                de: 'Fenster ${stats.windowRequestCount}',
                ja: '直近 ${stats.windowRequestCount}',
              ),
              onTap: () =>
                  _showOpsInsight(context, _McpOpsInsightKind.requests),
            ),
            _McpOpsMetricTile(
              icon: Icons.task_alt_rounded,
              label: _localizedText(context, zh: '成功数量', en: 'Succeeded'),
              value: '${stats.successTotal}',
              helper: '${stats.successRateLabel}%',
              color: OpenHandStatusColors.success,
              onTap: () =>
                  _showOpsInsight(context, _McpOpsInsightKind.succeeded),
            ),
            _McpOpsMetricTile(
              icon: Icons.shield_rounded,
              label: _localizedText(context, zh: '拦截数量', en: 'Blocked'),
              value: '${snapshot.blockedTotal}',
              helper: '${stats.blockedRateLabel}%',
              color: OpenHandStatusColors.warning,
              onTap: () => _showOpsInsight(context, _McpOpsInsightKind.blocked),
            ),
            _McpOpsMetricTile(
              icon: Icons.error_outline_rounded,
              label: _localizedText(context, zh: '失败数量', en: 'Failures'),
              value: '${snapshot.failedTotal}',
              helper: '${stats.failedRateLabel}%',
              color: Theme.of(context).colorScheme.error,
              onTap: () =>
                  _showOpsInsight(context, _McpOpsInsightKind.failures),
            ),
            _McpOpsMetricTile(
              icon: Icons.south_west_rounded,
              label: _localizedText(context, zh: '入口流量', en: 'Inbound'),
              value: formatByteSize(snapshot.inboundBytes),
              helper: _localizedText(context, zh: '请求体', en: 'Request bytes'),
              onTap: () => _showOpsInsight(context, _McpOpsInsightKind.inbound),
            ),
            _McpOpsMetricTile(
              icon: Icons.north_east_rounded,
              label: _localizedText(context, zh: '出口流量', en: 'Outbound'),
              value: formatByteSize(snapshot.outboundBytes),
              helper: _localizedText(context, zh: '响应体', en: 'Response bytes'),
              onTap: () =>
                  _showOpsInsight(context, _McpOpsInsightKind.outbound),
            ),
            _McpOpsMetricTile(
              icon: Icons.speed_rounded,
              label: _localizedText(context, zh: '调用耗时', en: 'Latency'),
              value: '${snapshot.avgLatencyMs}ms',
              helper: 'p95 ${snapshot.p95LatencyMs}ms',
              onTap: () => _showOpsInsight(context, _McpOpsInsightKind.latency),
            ),
            _McpOpsMetricTile(
              icon: Icons.schedule_rounded,
              label: _localizedText(context, zh: '允许时间', en: 'Allowed Time'),
              value: config.allowedTimeWindows.join(', '),
              helper: _localizedText(context, zh: '本地时区', en: 'Local time'),
              onTap: () =>
                  _showOpsInsight(context, _McpOpsInsightKind.allowedTime),
            ),
            _McpOpsMetricTile(
              icon: Icons.memory_rounded,
              label: _localizedText(context, zh: '内存占用', en: 'Memory'),
              value: formatByteSize(snapshot.memoryRssBytes),
              helper: _localizedText(context, zh: '当前RSS', en: 'Current RSS'),
              onTap: () => _showOpsInsight(context, _McpOpsInsightKind.memory),
            ),
            _McpOpsMetricTile(
              icon: Icons.hub_rounded,
              label: _localizedText(context, zh: 'MCP数量', en: 'MCP Count'),
              value: '${controller.servers.length}',
              helper: _localizedText(context, zh: '已注册服务', en: 'Registered'),
              onTap: () =>
                  _showOpsInsight(context, _McpOpsInsightKind.mcpCount),
            ),
            _McpOpsMetricTile(
              icon: Icons.change_circle_rounded,
              label: _localizedText(context, zh: '文件变动', en: 'Mutations'),
              value: '${snapshot.fileMutationCount}',
              helper: _localizedText(context, zh: '写工具成功', en: 'Write calls'),
              onTap: () =>
                  _showOpsInsight(context, _McpOpsInsightKind.mutations),
            ),
            _McpOpsMetricTile(
              icon: Icons.inventory_2_rounded,
              label: _localizedText(context, zh: '审计日志', en: 'Audit Logs'),
              value: '${auditEntries.length}',
              helper: _localizedText(context, zh: '滚动保留', en: 'Rolling kept'),
              onTap: () =>
                  _showOpsInsight(context, _McpOpsInsightKind.auditLogs),
            ),
            _McpOpsMetricTile(
              icon: Icons.speed_rounded,
              label: 'RPM',
              value: '${stats.currentRpm}',
              helper: config.rpmLimit <= 0
                  ? _localizedText(context, zh: '不限流', en: 'Unlimited')
                  : '/ ${config.rpmLimit}',
              onTap: () => _showOpsInsight(context, _McpOpsInsightKind.rpm),
            ),
            _McpOpsMetricTile(
              icon: Icons.security_rounded,
              label: _localizedText(context, zh: '访问策略', en: 'Access Policy'),
              value: _networkModeLabel(context, config.networkMode),
              helper: config.requireAuthToken
                  ? _localizedText(context, zh: '令牌校验', en: 'Token auth')
                  : _localizedText(context, zh: '无令牌', en: 'No token'),
              onTap: () =>
                  _showOpsInsight(context, _McpOpsInsightKind.accessPolicy),
            ),
          ],
        ),
        const SizedBox(height: _mcpOpsGridGap),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth.isFinite && constraints.maxWidth < 780;
            final trendPanels = [
              _McpOpsTrendPanel(
                title: _localizedText(context, zh: '请求趋势', en: 'Request Trend'),
                icon: Icons.show_chart_rounded,
                subtitle: _localizedText(
                  context,
                  zh: '最近12分钟 · 成功/失败/拦截',
                  en: 'Last 12 minutes · success/failure/blocked',
                ),
                series: stats.requestTrendSeries(context),
                emptyLabel: _localizedText(
                  context,
                  zh: '等待请求样本',
                  en: 'Waiting for traffic',
                ),
                onTap: () =>
                    _showOpsInsight(context, _McpOpsInsightKind.requestTrend),
              ),
              _McpOpsTrendPanel(
                title: _localizedText(context, zh: '耗时曲线', en: 'Latency Curve'),
                icon: Icons.timeline_rounded,
                subtitle: _localizedText(
                  context,
                  zh: '平均耗时与尾延迟',
                  en: 'Average and tail latency',
                ),
                series: stats.latencyTrendSeries(context),
                valueSuffix: 'ms',
                emptyLabel: _localizedText(
                  context,
                  zh: '暂无耗时样本',
                  en: 'No latency samples',
                ),
                onTap: () =>
                    _showOpsInsight(context, _McpOpsInsightKind.latencyTrend),
              ),
            ];
            if (compact) {
              return Column(
                children: [
                  for (final panel in trendPanels) ...[
                    panel,
                    const SizedBox(height: _mcpOpsGridGap),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < trendPanels.length; i++) ...[
                  Expanded(child: trendPanels[i]),
                  if (i != trendPanels.length - 1)
                    const SizedBox(width: _mcpOpsGridGap),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: _mcpOpsGridGap),
        Builder(
          builder: (context) {
            final panels = [
              _McpOpsDistributionPanel(
                title: _localizedText(context, zh: '状态分布', en: 'Status Mix'),
                icon: Icons.donut_small_rounded,
                values: stats.statusDistribution(context),
                onTap: () =>
                    _showOpsInsight(context, _McpOpsInsightKind.statusMix),
              ),
              _McpOpsDistributionPanel(
                title: _localizedText(context, zh: '请求IP分布', en: 'IP Mix'),
                icon: Icons.public_rounded,
                values: snapshot.ipDistribution,
                onTap: () => _showOpsInsight(context, _McpOpsInsightKind.ipMix),
              ),
              _McpOpsDistributionPanel(
                title: _localizedText(context, zh: '请求客户端分布', en: 'Client Mix'),
                icon: Icons.devices_other_rounded,
                values: snapshot.clientDistribution,
                onTap: () =>
                    _showOpsInsight(context, _McpOpsInsightKind.clientMix),
              ),
              _McpOpsDistributionPanel(
                title: _localizedText(context, zh: '请求分布', en: 'Request Mix'),
                icon: Icons.account_tree_rounded,
                values: snapshot.requestDistribution,
                onTap: () =>
                    _showOpsInsight(context, _McpOpsInsightKind.requestMix),
              ),
              _McpOpsDistributionPanel(
                title: _localizedText(context, zh: '协议分布', en: 'Protocol Mix'),
                icon: Icons.api_rounded,
                values: snapshot.protocolDistribution,
                onTap: () =>
                    _showOpsInsight(context, _McpOpsInsightKind.protocolMix),
              ),
            ];
            return _McpOpsPanelGrid(children: panels);
          },
        ),
        if (controller.opsApprovalRequests.isNotEmpty) ...[
          const SizedBox(height: _mcpOpsGridGap),
          _McpOpsApprovalPanel(requests: controller.opsApprovalRequests),
        ],
      ],
    );
  }

  Widget _buildConfigTab(BuildContext context) {
    final controller = context.read<McpController>();
    final servers = context.select<McpController, List<McpServer>>(
      (controller) => controller.servers,
    );
    final settings = context.watch<SettingsController>();
    final skills = context.watch<SkillsController>().skills;
    final memories = context.watch<MemoryController>().entries;
    final instructions = context.watch<InstructionsController>().entries;
    final knowledgeSources = context.watch<KnowledgeBaseController>().sources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _McpOpsPanel(
          icon: Icons.settings_ethernet_rounded,
          title: _localizedText(context, zh: '监听与访问控制', en: 'Listener'),
          subtitle: _localizedText(
            context,
            zh: '定义服务器对外暴露的网络端点、可操作文件空间与访问凭证。',
            en: 'Define the network endpoint, workspace scope and access credentials this server exposes.',
          ),
          child: Column(
            children: [
              _McpOpsFieldGroup(
                icon: Icons.lan_rounded,
                label: _localizedText(context, zh: '网络绑定', en: 'Binding'),
                hint: _localizedText(
                  context,
                  zh: '监听地址决定谁能连入，端口范围 $mcpOpsMinListenPort–$mcpOpsMaxListenPort。',
                  en: 'Host controls who can connect; port range $mcpOpsMinListenPort–$mcpOpsMaxListenPort.',
                ),
                child: _McpOpsResponsiveFields(
                  children: [
                    TextField(
                      controller: _hostController,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '监听地址',
                          en: 'Listen Host',
                        ),
                        prefixIcon: const Icon(Icons.dns_rounded),
                        helperText: _localizedText(
                          context,
                          zh: '127.0.0.1 仅本机 · 0.0.0.0 允许局域网',
                          en: '127.0.0.1 loopback · 0.0.0.0 LAN',
                        ),
                      ),
                    ),
                    TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '监听端口',
                          en: 'Listen Port',
                        ),
                        prefixIcon: const Icon(Icons.numbers_rounded),
                        helperText: _localizedText(
                          context,
                          zh: '默认 $mcpOpsDefaultListenPort',
                          en: 'Default $mcpOpsDefaultListenPort',
                        ),
                      ),
                    ),
                    _buildWorkspaceScopeField(context),
                  ],
                ),
              ),
              _McpOpsFieldGroup(
                icon: Icons.verified_user_rounded,
                label: _localizedText(context, zh: '安全与留痕', en: 'Security'),
                topGap: 18,
                hint: _localizedText(
                  context,
                  zh: '令牌校验开启后所有请求需携带 Bearer 令牌；记录参数便于审计回溯。',
                  en: 'Token auth requires a Bearer token on every request; payload capture aids audit replay.',
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _authTokenController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '访问令牌',
                          en: 'Access Token',
                        ),
                        prefixIcon: const Icon(Icons.key_rounded),
                        helperText: _localizedText(
                          context,
                          zh: '写入 Authorization Header，仅限英文、数字与符号',
                          en: 'Sent via Authorization header; ASCII letters, digits and symbols only',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _McpOpsSwitchChip(
                          label: _localizedText(
                            context,
                            zh: '跟随应用启动',
                            en: 'Start with app',
                          ),
                          value: _autoStart,
                          onChanged: (value) =>
                              setState(() => _autoStart = value),
                        ),
                        _McpOpsSwitchChip(
                          label: _localizedText(
                            context,
                            zh: '令牌校验',
                            en: 'Token Auth',
                          ),
                          value: _requireAuthToken,
                          onChanged: (value) =>
                              setState(() => _requireAuthToken = value),
                        ),
                        _McpOpsSwitchChip(
                          label: _localizedText(
                            context,
                            zh: '记录参数',
                            en: 'Capture Payload',
                          ),
                          value: _capturePayload,
                          onChanged: (value) =>
                              setState(() => _capturePayload = value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _McpOpsHintText(
                icon: Icons.info_outline_rounded,
                text: _localizedText(
                  context,
                  zh: '自启动默认关闭；仅在这里开启后，OpenHand 启动完成时才会自动启动本 MCP 服务器。',
                  en: 'Autostart is off by default. OpenHand only starts this MCP server during app launch when this switch is enabled.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: _mcpOpsGridGap),
        _McpOpsPanel(
          icon: Icons.rule_rounded,
          title: _localizedText(context, zh: '限流与调用策略', en: 'Policy'),
          subtitle: _localizedText(
            context,
            zh: '控制请求速率、超时、写操作审批与来源白名单，保障服务稳定与安全。',
            en: 'Govern request rate, timeouts, write approvals and source allowlists for stable, safe serving.',
          ),
          child: Column(
            children: [
              _McpOpsFieldGroup(
                icon: Icons.speed_rounded,
                label: _localizedText(context, zh: '速率与超时', en: 'Rate & Timeout'),
                hint: _localizedText(
                  context,
                  zh: '数值填 0 表示不限制；超时与审批等待单位为毫秒。',
                  en: 'Enter 0 to disable a limit; timeout and approval wait are in milliseconds.',
                ),
                child: _McpOpsResponsiveFields(
                  children: [
                    TextField(
                      controller: _rpmController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'RPM',
                        prefixIcon: const Icon(Icons.rate_review_rounded),
                        helperText: _localizedText(
                          context,
                          zh: '每分钟请求上限 · 0 不限流 · 最大 $mcpOpsMaxRpmLimit',
                          en: 'Requests / minute · 0 unlimited · max $mcpOpsMaxRpmLimit',
                        ),
                      ),
                    ),
                    TextField(
                      controller: _thresholdController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '调用次数阈值',
                          en: 'Call Threshold',
                        ),
                        prefixIcon: const Icon(Icons.filter_9_plus_rounded),
                        helperText: _localizedText(
                          context,
                          zh: '累计调用达到后告警 · 0 关闭',
                          en: 'Alert after total calls · 0 off',
                        ),
                      ),
                    ),
                    TextField(
                      controller: _timeoutController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '超时时间(ms)',
                          en: 'Timeout (ms)',
                        ),
                        prefixIcon: const Icon(Icons.timer_outlined),
                        helperText: _localizedText(
                          context,
                          zh: '范围 $mcpOpsMinTimeoutMs–$mcpOpsMaxTimeoutMs',
                          en: 'Range $mcpOpsMinTimeoutMs–$mcpOpsMaxTimeoutMs',
                        ),
                      ),
                    ),
                    TextField(
                      controller: _approvalTimeoutController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '审批等待(ms)',
                          en: 'Approval Wait (ms)',
                        ),
                        prefixIcon: const Icon(Icons.hourglass_top_rounded),
                        helperText: _localizedText(
                          context,
                          zh: '超时未审批则自动拒绝',
                          en: 'Auto-reject when no approval in time',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _McpOpsFieldGroup(
                icon: Icons.tune_rounded,
                label: _localizedText(context, zh: '调用与写入策略', en: 'Execution'),
                topGap: 18,
                hint: _policyModeHint(context),
                child: _McpOpsResponsiveFields(
                  children: [
                    DropdownButtonFormField<McpOpsNetworkMode>(
                      initialValue: _networkMode,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '网络模式',
                          en: 'Network Mode',
                        ),
                        prefixIcon: const Icon(Icons.wifi_tethering_rounded),
                      ),
                      items: [
                        for (final mode in McpOpsNetworkMode.values)
                          DropdownMenuItem(
                            value: mode,
                            child: Text(_networkModeLabel(context, mode)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _networkMode = value);
                      },
                    ),
                    DropdownButtonFormField<McpOpsInvocationMode>(
                      initialValue: _invocationMode,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '调用模式',
                          en: 'Invocation Mode',
                        ),
                        prefixIcon: const Icon(Icons.alt_route_rounded),
                      ),
                      items: [
                        for (final mode in McpOpsInvocationMode.values)
                          DropdownMenuItem(
                            value: mode,
                            child: Text(_invocationModeLabel(context, mode)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _invocationMode = value);
                        }
                      },
                    ),
                    DropdownButtonFormField<McpOpsWriteMode>(
                      initialValue: _writeMode,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '写调用策略',
                          en: 'Write Policy',
                        ),
                        prefixIcon: const Icon(Icons.edit_note_rounded),
                      ),
                      items: [
                        for (final mode in McpOpsWriteMode.values)
                          DropdownMenuItem(
                            value: mode,
                            child: Text(_writeModeLabel(context, mode)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _writeMode = value);
                      },
                    ),
                  ],
                ),
              ),
              _McpOpsFieldGroup(
                icon: Icons.shield_moon_rounded,
                label: _localizedText(context, zh: '访问白名单', en: 'Allowlist'),
                topGap: 18,
                hint: _localizedText(
                  context,
                  zh: '每行一条，留空表示不限制；时间窗支持 HH:MM-HH:MM 本地时区。',
                  en: 'One entry per line; empty means unrestricted. Time window uses HH:MM-HH:MM local time.',
                ),
                child: _McpOpsResponsiveFields(
                  children: [
                    TextField(
                      controller: _allowedClientsController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '允许客户端',
                          en: 'Allowed Clients',
                        ),
                        alignLabelWithHint: true,
                        hintText: 'cursor\nclaude-desktop',
                      ),
                    ),
                    TextField(
                      controller: _allowedIpsController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '允许IP/CIDR',
                          en: 'Allowed IP/CIDR',
                        ),
                        alignLabelWithHint: true,
                        hintText: '127.0.0.1\n192.168.0.0/16',
                      ),
                    ),
                    TextField(
                      controller: _allowedTimeController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: _localizedText(
                          context,
                          zh: '允许时间',
                          en: 'Allowed Time',
                        ),
                        alignLabelWithHint: true,
                        hintText: '00:00-23:59\n09:00-18:00',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: _mcpOpsGridGap),
        Builder(
          builder: (context) {
            final sections = <McpOpsExposureSurface, List<_McpOpsExposureRow>>{
              McpOpsExposureSurface.builtinTools: [
                for (final config in settings.builtinToolConfigs)
                  () {
                    final base = AiToolRuntimeService.builtinToolDefault(
                      config.kind,
                    );
                    final description =
                        config.summary?.trim().isNotEmpty == true
                        ? config.summary!.trim()
                        : (base?.definition.description.trim() ??
                              config.kind.name);
                    final defaultSchema = base?.definition.parameters;
                    return _McpOpsExposureRow(
                      id: config.kind.name,
                      title: config.effectiveName,
                      subtitle: description,
                      endpoints: const ['invoke'],
                      inputSchema: config.schemaOverride?.isNotEmpty == true
                          ? config.schemaOverride
                          : defaultSchema,
                      defaultSchema: defaultSchema,
                      onSchemaSaved: (schema) {
                        // schema == defaultSchema (or null) → clear the override
                        // so the tool falls back to its factory definition.
                        final isDefault =
                            schema == null ||
                            (defaultSchema != null &&
                                _mcpJsonEquals(schema, defaultSchema));
                        return settings.updateBuiltinToolConfig(
                          config.copyWith(
                            schemaOverride: isDefault ? null : schema,
                            clearSchemaOverride: isDefault,
                          ),
                        );
                      },
                    );
                  }(),
              ],
              McpOpsExposureSurface.memory: [
                for (final entry in memories)
                  _McpOpsExposureRow(
                    id: entry.id,
                    title: entry.displayTitle,
                    subtitle: entry.type,
                    endpoints: const ['read'],
                  ),
              ],
              McpOpsExposureSurface.skills: [
                for (final skill in skills)
                  _McpOpsExposureRow(
                    id: skill.name,
                    title: skill.name,
                    subtitle: skill.description,
                    endpoints: const ['manifest'],
                  ),
              ],
              McpOpsExposureSurface.instructions: [
                for (final entry in instructions)
                  _McpOpsExposureRow(
                    id: entry.id,
                    title: entry.name,
                    subtitle: entry.enabled
                        ? entry.description
                        : _localizedText(context, zh: '已停用', en: 'Disabled'),
                    endpoints: const ['read'],
                  ),
              ],
              McpOpsExposureSurface.knowledgeBase: [
                for (final source in knowledgeSources)
                  _McpOpsExposureRow(
                    id: source.id,
                    title: source.title,
                    subtitle: '${source.kind} · ${source.status}',
                    endpoints: const ['metadata'],
                  ),
              ],
              McpOpsExposureSurface.mcpServers: [
                for (final server in servers)
                  _McpOpsExposureRow(
                    id: server.name,
                    title: server.name,
                    subtitle: server.summary,
                    endpoints: controller
                        .toolCatalogFor(server.name)
                        .tools
                        .map((tool) => tool.id)
                        .toList(growable: false),
                    endpointLabels: {
                      for (final tool
                          in controller.toolCatalogFor(server.name).tools)
                        tool.id: tool.name,
                    },
                  ),
              ],
            };
            final enabledSurfaces = sections.keys
                .where(_surfaces.contains)
                .length;
            final totalItems = sections.values.fold<int>(
              0,
              (sum, rows) => sum + rows.length,
            );
            final exposedItems = sections.entries
                .where((entry) => _surfaces.contains(entry.key))
                .fold<int>(
                  0,
                  (sum, entry) =>
                      sum +
                      entry.value
                          .where(
                            (row) => !_hiddenItems.contains(
                              mcpOpsItemKey(entry.key, row.id),
                            ),
                          )
                          .length,
                );
            return _McpOpsPanel(
              icon: Icons.visibility_rounded,
              title: _localizedText(context, zh: 'MCP化暴露范围', en: 'Exposure'),
              subtitle: _localizedText(
                context,
                zh: '精细控制内建工具、记忆、技能、指令、知识库与 MCP 服务对外的可见性。',
                en: 'Fine-tune which builtin tools, memory, skills, instructions, knowledge and MCP servers are exposed.',
              ),
              trailing: _McpOpsExposureQuickActions(
                allEnabled: enabledSurfaces == sections.length,
                onEnableAll: () => setState(
                  () => _surfaces.addAll(sections.keys),
                ),
                onDisableAll: () => setState(_surfaces.clear),
                enableLabel: _localizedText(context, zh: '全部启用', en: 'All on'),
                disableLabel: _localizedText(context, zh: '全部关闭', en: 'All off'),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _exposureSearchController,
                    onChanged: (_) => setState(() {
                      _exposureLimits.clear();
                    }),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      labelText: _localizedText(
                        context,
                        zh: '搜索暴露条目',
                        en: 'Search exposure items',
                      ),
                      hintText: _localizedText(
                        context,
                        zh: '输入服务、工具、技能、记忆或知识库关键字',
                        en: 'Filter by server, tool, skill, memory or knowledge',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _McpOpsExposureSummary(
                    enabledSurfaces: enabledSurfaces,
                    totalSurfaces: sections.length,
                    exposedItems: exposedItems,
                    totalItems: totalItems,
                  ),
                  const SizedBox(height: 12),
                  for (final entry in sections.entries)
                    _exposureSection(context, entry.key, entry.value),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _exposureSection(
    BuildContext context,
    McpOpsExposureSurface surface,
    List<_McpOpsExposureRow> rows,
  ) {
    final enabled = _surfaces.contains(surface);
    final visibleCount = rows
        .where(
          (row) => !_hiddenItems.contains(mcpOpsItemKey(surface, row.id)),
        )
        .length;
    return Column(
      children: [
        _surfaceSwitch(
          context,
          surface,
          badge: '$visibleCount/${rows.length}',
        ),
        AnimatedSize(
          duration: _mcpMotionDuration(
            context,
            const Duration(milliseconds: 240),
          ),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: enabled
              ? _exposureList(context, surface: surface, rows: rows)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildAuditTab(BuildContext context) {
    final entries = context.watch<McpController>().opsAuditEntries;
    if (entries.isEmpty) {
      return SizedBox.expand(
        key: const ValueKey<String>('mcp-ops-audit-empty'),
        child: FeatureStateCard.centered(
          icon: Icons.manage_search_rounded,
          tone: FeatureStateTone.neutral,
          title: _localizedText(context, zh: '暂无调用日志', en: 'No audit logs'),
          body: _localizedText(
            context,
            zh: '外部 MCP 客户端发起调用后，会在这里实时滚动输出审计记录。',
            en: 'External MCP calls will stream into this audit list.',
          ),
        ),
      );
    }
    return ListView.separated(
      physics: openHandDialogAwareScrollPhysics(context),
      itemCount: entries.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _McpOpsAuditSummaryPanel(entries: entries);
        }
        final entry = entries[index - 1];
        return SettingsAwareAppearOnce(
          key: ValueKey<String>('mcp-ops-audit-${entry.id}'),
          child: _McpOpsAuditRow(
            entry: entry,
            onDetails: () => _showAuditDetails(context, entry),
          ),
        );
      },
    );
  }

  Widget _surfaceSwitch(
    BuildContext context,
    McpOpsExposureSurface surface, {
    String? badge,
  }) {
    final enabled = _surfaces.contains(surface);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    void update(bool value) {
      setState(() {
        if (value) {
          _surfaces.add(surface);
        } else {
          _surfaces.remove(surface);
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
          onTap: () => update(!enabled),
          hoverColor: cs.primary.withValues(alpha: 0.05),
          splashColor: cs.primary.withValues(alpha: 0.08),
          highlightColor: cs.primary.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: _mcpMotionDuration(
              context,
              const Duration(milliseconds: 160),
            ),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: enabled
                  ? cs.primary.withValues(alpha: 0.08)
                  : cs.surfaceContainerHigh.withValues(alpha: 0.44),
              borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
              border: Border.all(
                color: enabled
                    ? cs.primary.withValues(alpha: 0.24)
                    : cs.outlineVariant.withValues(alpha: 0.46),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _surfaceIcon(surface),
                  color: enabled ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _surfaceLabel(context, surface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (badge != null && badge.trim().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _McpOpsCountBadge(text: badge, active: enabled),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Switch(value: enabled, onChanged: update),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _exposureList(
    BuildContext context, {
    required McpOpsExposureSurface surface,
    required List<_McpOpsExposureRow> rows,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final query = _exposureSearchController.text.trim().toLowerCase();
    final filteredRows = query.isEmpty
        ? rows
        : rows
              .where(
                (row) =>
                    row.title.toLowerCase().contains(query) ||
                    row.subtitle.toLowerCase().contains(query) ||
                    row.id.toLowerCase().contains(query) ||
                    row.endpoints.any(
                      (endpoint) =>
                          endpoint.toLowerCase().contains(query) ||
                          (row.endpointLabels[endpoint] ?? '')
                              .toLowerCase()
                              .contains(query),
                    ),
              )
              .toList(growable: false);
    if (filteredRows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          rows.isEmpty
              ? _localizedText(context, zh: '暂无可暴露条目', en: 'No exposed items')
              : _localizedText(context, zh: '没有匹配条目', en: 'No matches'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    final limit = math.min(
      _exposureLimits[surface] ?? _mcpOpsExposureInitialLimit,
      filteredRows.length,
    );
    final visibleRows = filteredRows.take(limit).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _localizedText(
                      context,
                      zh: '显示 $limit / ${filteredRows.length}',
                      en: 'Showing $limit / ${filteredRows.length}',
                      zhHant: '顯示 $limit / ${filteredRows.length}',
                      fr: '$limit / ${filteredRows.length} affichés',
                      de: '$limit / ${filteredRows.length} angezeigt',
                      ja: '$limit / ${filteredRows.length} 件を表示',
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (limit < filteredRows.length)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _exposureLimits[surface] = math.min(
                        filteredRows.length,
                        limit + _mcpOpsExposurePageSize,
                      );
                    }),
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    label: Text(
                      _localizedText(context, zh: '加载更多', en: 'Show more'),
                    ),
                  ),
                if (limit > _mcpOpsExposureInitialLimit)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _exposureLimits[surface] = _mcpOpsExposureInitialLimit;
                    }),
                    icon: const Icon(Icons.unfold_less_rounded, size: 18),
                    label: Text(
                      _localizedText(context, zh: '收起', en: 'Collapse'),
                    ),
                  ),
              ],
            ),
          ),
          for (final entry in visibleRows.indexed) ...[
            _McpOpsExposureTile(
              surface: surface,
              row: entry.$2,
              itemVisible: !_hiddenItems.contains(
                mcpOpsItemKey(surface, entry.$2.id),
              ),
              endpointVisible: (endpoint) => !_hiddenEndpoints.contains(
                mcpOpsEndpointKey(surface, '${entry.$2.id}:$endpoint'),
              ),
              onItemChanged: (value) {
                setState(() {
                  final key = mcpOpsItemKey(surface, entry.$2.id);
                  if (value) {
                    _hiddenItems.remove(key);
                  } else {
                    _hiddenItems.add(key);
                  }
                });
              },
              onEndpointChanged: (endpoint, value) {
                setState(() {
                  final key = mcpOpsEndpointKey(
                    surface,
                    '${entry.$2.id}:$endpoint',
                  );
                  if (value) {
                    _hiddenEndpoints.remove(key);
                  } else {
                    _hiddenEndpoints.add(key);
                  }
                });
              },
            ),
            if (entry.$1 != visibleRows.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Future<void> _saveConfig(BuildContext context) async {
    await _persistConfig(context, action: null);
  }

  Future<void> _startServer(BuildContext context) async {
    await _persistConfig(
      context,
      action: () {
        return context.read<McpController>().startMcpOpsServer();
      },
    );
  }

  Future<void> _restartServer(BuildContext context) async {
    await _persistConfig(
      context,
      action: () {
        return context.read<McpController>().restartMcpOpsServer();
      },
    );
  }

  Future<void> _stopServer(BuildContext context) async {
    setState(() => _saving = true);
    final ok = await context.read<McpController>().stopMcpOpsServer();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _configMessage = ok
          ? _localizedText(context, zh: 'MCP服务器已关闭', en: 'MCP server stopped')
          : _localizedText(context, zh: '关闭失败', en: 'Stop failed');
    });
  }

  Future<void> _testConnectivity(BuildContext context) async {
    setState(() => _saving = true);
    final result = await context.read<McpController>().testMcpOpsConnectivity();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _configMessage = result.ok
          ? _localizedText(context, zh: '连通性正常', en: 'Connectivity OK')
          : result.message;
    });
  }

  Future<void> _persistConfig(
    BuildContext context, {
    required Future<bool> Function()? action,
  }) async {
    final config = _buildConfig();
    final validationMessage = _opsClientConfigValidationMessage(
      context,
      config,
    );
    if (validationMessage != null) {
      setState(() {
        _saving = false;
        _configMessage = validationMessage;
      });
      return;
    }
    setState(() => _saving = true);
    final controller = context.read<McpController>();
    final ok = await controller.saveOpsConfig(config);
    var actionOk = true;
    if (ok && action != null) {
      actionOk = await action();
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _configMessage = ok && actionOk
          ? _localizedText(context, zh: '配置已生效', en: 'Configuration applied')
          : _localizedText(context, zh: '配置保存失败', en: 'Configuration failed');
    });
  }

  Future<void> _resetConfigWithConfirm(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = context.read<McpController>();
    final previous = controller.opsConfig;
    final confirmed = await showOpenHandConfirmDialog(
      context: context,
      title: _localizedText(
        context,
        zh: '重置 MCP 服务器配置？',
        en: 'Reset MCP server configuration?',
      ),
      message: _localizedText(
        context,
        zh: '将把监听、访问控制、限流、调用策略、暴露范围全部恢复为默认值。自启动会保持关闭。此操作会立即保存。',
        en: 'Listener, access control, rate limits, invocation policy and exposure scope will return to defaults. Autostart stays off. This will be saved immediately.',
      ),
      cancelLabel: l10n.commonCancel,
      confirmLabel: _localizedText(context, zh: '重置', en: 'Reset'),
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    const defaults = McpOpsConfig();
    setState(() {
      _saving = true;
      _applyConfigToForm(defaults);
      _configMessage = null;
    });
    final ok = await controller.saveOpsConfig(defaults);
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      if (!ok) {
        _applyConfigToForm(previous);
      }
      _configMessage = ok
          ? _localizedText(context, zh: '已恢复默认配置', en: 'Defaults restored')
          : _localizedText(context, zh: '重置失败', en: 'Reset failed');
    });
  }

  void _applyConfigToForm(McpOpsConfig config) {
    _hostController.text = config.listenHost;
    _portController.text = '${config.listenPort}';
    _rpmController.text = '${config.rpmLimit}';
    _thresholdController.text = '${config.callThreshold}';
    _timeoutController.text = '${config.timeoutMs}';
    _approvalTimeoutController.text = '${config.approvalTimeoutMs}';
    _workspaceController.text = config.workspaceRoot;
    _authTokenController.text = config.authToken;
    _allowedClientsController.text = config.allowedClients.join('\n');
    _allowedIpsController.text = config.allowedIpCidrs.join('\n');
    _allowedTimeController.text = config.allowedTimeWindows.join('\n');
    _exposureSearchController.clear();
    _autoStart = config.autoStart;
    _requireAuthToken = config.requireAuthToken;
    _capturePayload = config.capturePayload;
    _networkMode = config.networkMode;
    _invocationMode = config.invocationMode;
    _writeMode = config.writeMode;
    _surfaces = Set<McpOpsExposureSurface>.from(config.exposedSurfaces);
    _hiddenItems = Set<String>.from(config.hiddenItemIds);
    _hiddenEndpoints = Set<String>.from(config.hiddenEndpointIds);
    _exposureLimits.clear();
  }

  String _policyModeHint(BuildContext context) {
    return '${_invocationModeDescription(context, _invocationMode)} · '
        '${_writeModeDescription(context, _writeMode)}';
  }

  McpOpsConfig _buildConfig() {
    final current = context.read<McpController>().opsConfig;
    return current.copyWith(
      autoStart: _autoStart,
      listenHost: _hostController.text.trim(),
      listenPort: nonNegativeIntFromValue(
        _portController.text,
        fallback: current.listenPort,
      ),
      networkMode: _networkMode,
      invocationMode: _invocationMode,
      writeMode: _writeMode,
      requireAuthToken: _requireAuthToken,
      authToken: _authTokenController.text.trim(),
      allowedClients: splitLooseDelimitedValues(_allowedClientsController.text),
      allowedIpCidrs: splitLooseDelimitedValues(_allowedIpsController.text),
      allowedTimeWindows: splitLooseDelimitedValues(
        _allowedTimeController.text,
      ),
      workspaceRoot: _workspaceController.text.trim(),
      rpmLimit: nonNegativeIntFromValue(
        _rpmController.text,
        fallback: current.rpmLimit,
      ),
      callThreshold: nonNegativeIntFromValue(
        _thresholdController.text,
        fallback: current.callThreshold,
      ),
      timeoutMs: nonNegativeIntFromValue(
        _timeoutController.text,
        fallback: current.timeoutMs,
      ),
      approvalTimeoutMs: nonNegativeIntFromValue(
        _approvalTimeoutController.text,
        fallback: current.approvalTimeoutMs,
      ),
      capturePayload: _capturePayload,
      exposedSurfaces: _surfaces,
      hiddenItemIds: _hiddenItems,
      hiddenEndpointIds: _hiddenEndpoints,
    );
  }

  void _showAuditDetails(BuildContext context, McpOpsAuditEntry entry) {
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => _McpOpsAuditDetailDialog(entry: entry),
    );
  }

  /// Opens a structured drill-down for a dashboard card. The dialog reuses the
  /// shared animated shell and watches the controller, so its content stays
  /// live while open. [kind] selects which sections to render.
  void _showOpsInsight(BuildContext context, _McpOpsInsightKind kind) {
    final config = _buildConfig();
    final spec = _mcpOpsInsightSpec(context, kind);
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => _McpOpsInsightDialog(
        icon: spec.icon,
        title: spec.title,
        subtitle: spec.subtitle,
        tone: spec.tone,
        config: config,
        sections: spec.sections,
      ),
    );
  }
}

/// Identifies which drill-down an ops card opens.
enum _McpOpsInsightKind {
  connections,
  activeRequests,
  requests,
  succeeded,
  blocked,
  failures,
  inbound,
  outbound,
  latency,
  allowedTime,
  memory,
  mcpCount,
  mutations,
  auditLogs,
  rpm,
  accessPolicy,
  requestTrend,
  latencyTrend,
  statusMix,
  ipMix,
  clientMix,
  requestMix,
  protocolMix,
}

class _McpOpsInsightSpec {
  const _McpOpsInsightSpec({
    required this.icon,
    required this.title,
    required this.sections,
    this.subtitle = '',
    this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? tone;
  final _McpOpsInsightSections sections;
}

class _McpOpsDialogSurface extends StatelessWidget {
  const _McpOpsDialogSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(_mcpOpsOuterRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.72)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.18),
            blurRadius: 38,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _McpOpsConsoleShell extends StatelessWidget {
  const _McpOpsConsoleShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: _mcpMotionDuration(context, const Duration(milliseconds: 180)),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(_mcpOpsShellRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.74)),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _McpOpsConsoleHeader extends StatelessWidget {
  const _McpOpsConsoleHeader({
    required this.snapshot,
    required this.endpointUri,
    required this.bindEndpointUri,
    required this.config,
    required this.onCopyEndpoint,
    required this.onCopyCursorConfig,
    required this.onConnectivityTest,
    required this.onStart,
    required this.onRestart,
    required this.onStop,
    required this.configActionBusy,
    required this.onResetConfig,
    required this.onSaveConfig,
    required this.onClose,
    this.configMessage,
  });

  final McpOpsRuntimeSnapshot snapshot;
  final String endpointUri;
  final String bindEndpointUri;
  final McpOpsConfig config;
  final VoidCallback onCopyEndpoint;
  final VoidCallback onCopyCursorConfig;
  final VoidCallback onConnectivityTest;
  final VoidCallback onStart;
  final VoidCallback onRestart;
  final VoidCallback onStop;
  final bool configActionBusy;
  final String? configMessage;
  final VoidCallback onResetConfig;
  final VoidCallback onSaveConfig;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final running = snapshot.isRunning;
    final statusColor = running
        ? OpenHandStatusColors.success
        : snapshot.lifecycle == McpOpsLifecycleState.failed
        ? cs.error
        : cs.primary;
    final canStart =
        !configActionBusy &&
        snapshot.lifecycle != McpOpsLifecycleState.running &&
        snapshot.lifecycle != McpOpsLifecycleState.starting &&
        snapshot.lifecycle != McpOpsLifecycleState.restarting;
    final canStop =
        !configActionBusy &&
        (snapshot.lifecycle == McpOpsLifecycleState.running ||
            snapshot.lifecycle == McpOpsLifecycleState.starting ||
            snapshot.lifecycle == McpOpsLifecycleState.restarting);
    final showsBindEndpoint = bindEndpointUri != endpointUri;
    final configMessageText = configMessage?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: statusColor.withValues(alpha: 0.34)),
              ),
              child: Icon(Icons.dns_rounded, color: statusColor, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localizedText(
                      context,
                      zh: 'MCP服务器运维',
                      en: 'MCP Server Operations',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _localizedText(
                      context,
                      zh: 'OpenHand MCP Server · $endpointUri',
                      en: 'OpenHand MCP Server · $endpointUri',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            _McpOpsIconButton(
              icon: Icons.copy_rounded,
              tooltip: _localizedText(context, zh: '复制入口', en: 'Copy endpoint'),
              onPressed: onCopyEndpoint,
            ),
            const SizedBox(width: 8),
            _McpOpsIconButton(
              icon: Icons.integration_instructions_rounded,
              tooltip: _localizedText(
                context,
                zh: '复制 Cursor 配置',
                en: 'Copy Cursor config',
              ),
              onPressed: onCopyCursorConfig,
            ),
            const SizedBox(width: 8),
            _McpOpsIconButton(
              icon: Icons.close_rounded,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onClose,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _McpOpsStatusChip(
              icon: Icons.circle_rounded,
              label: _lifecycleLabel(context, snapshot.lifecycle),
              color: statusColor,
            ),
            _McpOpsStatusChip(
              icon: Icons.link_rounded,
              label: endpointUri,
              color: cs.primary,
              monospace: true,
            ),
            if (showsBindEndpoint)
              _McpOpsStatusChip(
                icon: Icons.settings_ethernet_rounded,
                label: _localizedText(
                  context,
                  zh: '监听 $bindEndpointUri',
                  en: 'Bind $bindEndpointUri',
                ),
                color: cs.onSurfaceVariant,
                monospace: true,
              ),
            _McpOpsStatusChip(
              icon: Icons.speed_rounded,
              label: config.rpmLimit <= 0 ? 'RPM ∞' : 'RPM ${config.rpmLimit}',
              color: cs.tertiary,
              monospace: true,
            ),
            _McpOpsStatusChip(
              icon: config.writeMode == McpOpsWriteMode.fullAccess
                  ? Icons.lock_open_rounded
                  : Icons.verified_user_rounded,
              label: _writeModeLabel(context, config.writeMode),
              color: cs.secondary,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _McpOpsHeaderControls(
          running: running,
          canStart: canStart,
          canStop: canStop,
          busy: configActionBusy,
          onConnectivityTest: onConnectivityTest,
          onStart: onStart,
          onRestart: onRestart,
          onStop: onStop,
          onResetConfig: onResetConfig,
          onSaveConfig: onSaveConfig,
          onClose: onClose,
        ),
        AnimatedSize(
          duration: _mcpMotionDuration(
            context,
            const Duration(milliseconds: 180),
          ),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: configMessageText.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _McpOpsHeaderMessage(text: configMessageText),
                ),
        ),
      ],
    );
  }
}

class _McpOpsHeaderControls extends StatelessWidget {
  const _McpOpsHeaderControls({
    required this.running,
    required this.canStart,
    required this.canStop,
    required this.busy,
    required this.onConnectivityTest,
    required this.onStart,
    required this.onRestart,
    required this.onStop,
    required this.onResetConfig,
    required this.onSaveConfig,
    required this.onClose,
  });

  final bool running;
  final bool canStart;
  final bool canStop;
  final bool busy;
  final VoidCallback onConnectivityTest;
  final VoidCallback onStart;
  final VoidCallback onRestart;
  final VoidCallback onStop;
  final VoidCallback onResetConfig;
  final VoidCallback onSaveConfig;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tabController = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: tabController,
      builder: (context, _) {
        final showConfigActions = tabController.index == 1;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _McpOpsIconButton(
              icon: Icons.radar_rounded,
              tooltip: _localizedText(context, zh: '连通性测试', en: 'Test'),
              onPressed: busy ? null : onConnectivityTest,
            ),
            _McpOpsIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: _localizedText(context, zh: '启动', en: 'Start'),
              onPressed: canStart ? onStart : null,
            ),
            _McpOpsIconButton(
              icon: Icons.restart_alt_rounded,
              tooltip: _localizedText(context, zh: '重启', en: 'Restart'),
              onPressed: running && !busy ? onRestart : null,
            ),
            _McpOpsIconButton(
              icon: Icons.stop_rounded,
              tooltip: _localizedText(context, zh: '关闭', en: 'Stop'),
              onPressed: canStop ? onStop : null,
            ),
            AnimatedSwitcher(
              duration: _mcpMotionDuration(
                context,
                const Duration(milliseconds: 180),
              ),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                return FadeTransition(
                  opacity: curved,
                  child: SizeTransition(
                    axis: Axis.horizontal,
                    axisAlignment: -1,
                    sizeFactor: curved,
                    child: child,
                  ),
                );
              },
              child: showConfigActions
                  ? _McpOpsHeaderConfigActions(
                      key: const ValueKey<String>('mcp-ops-top-config-actions'),
                      busy: busy,
                      onResetConfig: onResetConfig,
                      onSaveConfig: onSaveConfig,
                      onClose: onClose,
                    )
                  : const SizedBox.shrink(
                      key: ValueKey<String>('mcp-ops-top-config-actions-empty'),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _McpOpsHeaderConfigActions extends StatelessWidget {
  const _McpOpsHeaderConfigActions({
    super.key,
    required this.busy,
    required this.onResetConfig,
    required this.onSaveConfig,
    required this.onClose,
  });

  final bool busy;
  final VoidCallback onResetConfig;
  final VoidCallback onSaveConfig;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _McpOpsHeaderActionButton(
          icon: Icons.restart_alt_rounded,
          label: _localizedText(context, zh: '重置', en: 'Reset'),
          onPressed: busy ? null : onResetConfig,
        ),
        _McpOpsHeaderActionButton(
          icon: Icons.close_rounded,
          label: l10n.commonClose,
          onPressed: busy ? null : onClose,
        ),
        _McpOpsHeaderActionButton(
          icon: Icons.save_rounded,
          label: l10n.commonSave,
          primary: true,
          onPressed: busy ? null : onSaveConfig,
        ),
      ],
    );
  }
}

class _McpOpsHeaderActionButton extends StatelessWidget {
  const _McpOpsHeaderActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = onPressed != null;
    final background = primary
        ? cs.primary
        : cs.surfaceContainerHigh.withValues(alpha: 0.82);
    final foreground = primary ? cs.onPrimary : cs.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
          hoverColor: (primary ? cs.onPrimary : cs.primary).withValues(
            alpha: 0.08,
          ),
          splashColor: (primary ? cs.onPrimary : cs.primary).withValues(
            alpha: 0.10,
          ),
          highlightColor: (primary ? cs.onPrimary : cs.primary).withValues(
            alpha: 0.05,
          ),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: _mcpMotionDuration(
              context,
              const Duration(milliseconds: 160),
            ),
            curve: Curves.easeOutCubic,
            height: 44,
            constraints: const BoxConstraints(minWidth: 88, maxWidth: 124),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: enabled
                  ? background
                  : cs.surfaceContainerHighest.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
              border: Border.all(
                color: enabled
                    ? (primary
                          ? cs.primary.withValues(alpha: 0.30)
                          : cs.outlineVariant.withValues(alpha: 0.72))
                    : cs.outlineVariant.withValues(alpha: 0.40),
              ),
              boxShadow: enabled && primary
                  ? <BoxShadow>[
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: enabled
                      ? foreground
                      : cs.onSurfaceVariant.withValues(alpha: 0.42),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: enabled
                          ? foreground
                          : cs.onSurfaceVariant.withValues(alpha: 0.42),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _McpOpsHeaderMessage extends StatelessWidget {
  const _McpOpsHeaderMessage({required this.text, this.tone});

  final String text;

  /// Accent color; defaults to the primary "info" tone when omitted.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = tone ?? cs.primary;
    final isError = tone == cs.error;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              size: 16,
              color: accent,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isError ? accent : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _McpOpsIconButton extends StatelessWidget {
  const _McpOpsIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
          hoverColor: cs.primary.withValues(alpha: 0.08),
          splashColor: cs.primary.withValues(alpha: 0.10),
          highlightColor: cs.primary.withValues(alpha: 0.06),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: _mcpMotionDuration(
              context,
              const Duration(milliseconds: 160),
            ),
            curve: Curves.easeOutCubic,
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled
                  ? cs.surfaceContainerHigh.withValues(alpha: 0.78)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
              border: Border.all(
                color: cs.outlineVariant.withValues(
                  alpha: enabled ? 0.72 : 0.4,
                ),
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: enabled
                  ? cs.onSurfaceVariant
                  : cs.onSurfaceVariant.withValues(alpha: 0.42),
            ),
          ),
        ),
      ),
    );
  }
}

class _McpOpsTabStrip extends StatelessWidget {
  const _McpOpsTabStrip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(_mcpOpsPanelRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.58)),
      ),
      child: TabBar(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        // Inset the selected pill on both sides so neighbouring tabs keep a
        // visible gutter instead of butting together edge-to-edge.
        indicatorPadding: const EdgeInsets.symmetric(horizontal: 5),
        // Clip the ink ripple and press/hover overlay to the indicator's radius
        // so interaction feedback stays pill-shaped instead of a sharp rectangle.
        splashBorderRadius: BorderRadius.circular(_mcpOpsControlRadius),
        overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.pressed)) {
            return cs.primary.withValues(alpha: 0.16);
          }
          if (states.contains(WidgetState.hovered)) {
            return cs.primary.withValues(alpha: 0.08);
          }
          if (states.contains(WidgetState.focused)) {
            return cs.primary.withValues(alpha: 0.10);
          }
          return null;
        }),
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w900,
        ),
        unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        indicator: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
          border: Border.all(color: cs.primary.withValues(alpha: 0.32)),
        ),
        tabs: [
          Tab(
            height: 48,
            child: _McpOpsTabLabel(
              icon: Icons.monitor_heart_rounded,
              label: _localizedText(context, zh: '运维面板', en: 'Ops'),
            ),
          ),
          Tab(
            height: 48,
            child: _McpOpsTabLabel(
              icon: Icons.tune_rounded,
              label: _localizedText(context, zh: '参数配置', en: 'Config'),
            ),
          ),
          Tab(
            height: 48,
            child: _McpOpsTabLabel(
              icon: Icons.manage_search_rounded,
              label: _localizedText(context, zh: '日志审计', en: 'Audit'),
            ),
          ),
        ],
      ),
    );
  }
}

class _McpOpsTabLabel extends StatelessWidget {
  const _McpOpsTabLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 8),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _McpOpsDashboardStats {
  const _McpOpsDashboardStats({
    required this.successTotal,
    required this.blockedTotal,
    required this.failedTotal,
    required this.currentRpm,
    required this.windowRequestCount,
    required this.successRate,
    required this.blockedRate,
    required this.failedRate,
    required this.successBuckets,
    required this.blockedBuckets,
    required this.failedBuckets,
    required this.avgLatencyBuckets,
    required this.p95LatencyBuckets,
    required this.bucketMinutes,
  });

  factory _McpOpsDashboardStats.from({
    required McpOpsRuntimeSnapshot snapshot,
    required List<McpOpsAuditEntry> auditEntries,
  }) {
    // The runtime traffic series is authoritative: it rolls up *every* request
    // (initialize/list/stream/call) per minute, whereas audit entries cover
    // only tool calls and blocks. Charts read from it so trends never sit empty
    // while real traffic flows.
    final series = snapshot.trafficSeries;
    final successBuckets = <double>[];
    final blockedBuckets = <double>[];
    final failedBuckets = <double>[];
    final avgLatencyBuckets = <double>[];
    final p95LatencyBuckets = <double>[];
    final bucketMinutes = <DateTime>[];
    var windowRequestCount = 0;
    for (final sample in series) {
      successBuckets.add(sample.success.toDouble());
      blockedBuckets.add(sample.blocked.toDouble());
      failedBuckets.add(sample.failed.toDouble());
      avgLatencyBuckets.add(sample.avgLatencyMs.toDouble());
      p95LatencyBuckets.add(sample.p95LatencyMs.toDouble());
      bucketMinutes.add(sample.minute);
      windowRequestCount += sample.total;
    }
    final currentRpm = series.isEmpty ? 0 : series.last.total;
    final total = math.max(1, snapshot.requestTotal);
    final blocked = snapshot.blockedTotal;
    final failed = snapshot.failedTotal;
    final success = math.max(0, snapshot.requestTotal - blocked - failed);
    return _McpOpsDashboardStats(
      successTotal: success,
      blockedTotal: blocked,
      failedTotal: failed,
      currentRpm: currentRpm,
      windowRequestCount: windowRequestCount,
      successRate: success / total,
      blockedRate: blocked / total,
      failedRate: failed / total,
      successBuckets: List<double>.unmodifiable(successBuckets),
      blockedBuckets: List<double>.unmodifiable(blockedBuckets),
      failedBuckets: List<double>.unmodifiable(failedBuckets),
      avgLatencyBuckets: List<double>.unmodifiable(avgLatencyBuckets),
      p95LatencyBuckets: List<double>.unmodifiable(p95LatencyBuckets),
      bucketMinutes: List<DateTime>.unmodifiable(bucketMinutes),
    );
  }

  final int successTotal;
  final int blockedTotal;
  final int failedTotal;
  final int currentRpm;
  final int windowRequestCount;
  final double successRate;
  final double blockedRate;
  final double failedRate;
  final List<double> successBuckets;
  final List<double> blockedBuckets;
  final List<double> failedBuckets;
  final List<double> avgLatencyBuckets;
  final List<double> p95LatencyBuckets;
  final List<DateTime> bucketMinutes;

  String get successRateLabel => _percentLabel(successRate);
  String get blockedRateLabel => _percentLabel(blockedRate);
  String get failedRateLabel => _percentLabel(failedRate);

  List<_McpOpsChartSeries> requestTrendSeries(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return <_McpOpsChartSeries>[
      _McpOpsChartSeries(
        label: _localizedText(context, zh: '成功', en: 'Success'),
        values: successBuckets,
        color: OpenHandStatusColors.success,
      ),
      _McpOpsChartSeries(
        label: _localizedText(context, zh: '拦截', en: 'Blocked'),
        values: blockedBuckets,
        color: OpenHandStatusColors.warning,
      ),
      _McpOpsChartSeries(
        label: _localizedText(context, zh: '失败', en: 'Failed'),
        values: failedBuckets,
        color: cs.error,
      ),
    ];
  }

  List<_McpOpsChartSeries> latencyTrendSeries(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return <_McpOpsChartSeries>[
      _McpOpsChartSeries(
        label: _localizedText(context, zh: '平均', en: 'Average'),
        values: avgLatencyBuckets,
        color: cs.primary,
      ),
      _McpOpsChartSeries(
        label: 'p95',
        values: p95LatencyBuckets,
        color: cs.tertiary,
      ),
    ];
  }

  Map<String, int> statusDistribution(BuildContext context) {
    return <String, int>{
      _localizedText(context, zh: '成功', en: 'Success'): successTotal,
      _localizedText(context, zh: '拦截', en: 'Blocked'): blockedTotal,
      _localizedText(context, zh: '失败', en: 'Failed'): failedTotal,
    }..removeWhere((_, value) => value <= 0);
  }

  static String _percentLabel(double value) {
    return (value * 100).clamp(0, 100).toStringAsFixed(1);
  }
}

class _McpOpsChartSeries {
  const _McpOpsChartSeries({
    required this.label,
    required this.values,
    required this.color,
  });

  final String label;
  final List<double> values;
  final Color color;
}

class _McpOpsHeroPanel extends StatelessWidget {
  const _McpOpsHeroPanel({
    required this.snapshot,
    required this.endpoint,
    required this.bindEndpoint,
    required this.config,
  });

  final McpOpsRuntimeSnapshot snapshot;
  final String endpoint;
  final String bindEndpoint;
  final McpOpsConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final running = snapshot.isRunning;
    final tone = running
        ? OpenHandStatusColors.success
        : snapshot.lifecycle == McpOpsLifecycleState.failed
        ? cs.error
        : cs.primary;
    final endpointUri = 'http://$endpoint/mcp';
    final bindEndpointUri = 'http://$bindEndpoint/mcp';
    final showsBindEndpoint = bindEndpoint != endpoint;
    return _McpOpsPanel(
      icon: running ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
      title: _localizedText(context, zh: '服务控制台', en: 'Server Console'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _McpOpsStatusChip(
                icon: running
                    ? Icons.check_circle_rounded
                    : Icons.pause_circle_outline_rounded,
                label: _lifecycleLabel(context, snapshot.lifecycle),
                color: tone,
              ),
              _McpOpsStatusChip(
                icon: Icons.link_rounded,
                label: endpointUri,
                color: cs.primary,
                monospace: true,
              ),
              if (showsBindEndpoint)
                _McpOpsStatusChip(
                  icon: Icons.settings_ethernet_rounded,
                  label: _localizedText(
                    context,
                    zh: '监听 $bindEndpointUri',
                    en: 'Bind $bindEndpointUri',
                  ),
                  color: cs.onSurfaceVariant,
                  monospace: true,
                ),
              _McpOpsStatusChip(
                icon: Icons.schedule_rounded,
                label: _localizedText(
                  context,
                  zh: '运行 ${formatCompactDuration(snapshot.uptime)}',
                  en: 'Uptime ${formatCompactDuration(snapshot.uptime)}',
                  zhHant: '運行 ${formatCompactDuration(snapshot.uptime)}',
                  fr: 'Disponibilité ${formatCompactDuration(snapshot.uptime)}',
                  de: 'Laufzeit ${formatCompactDuration(snapshot.uptime)}',
                  ja: '稼働 ${formatCompactDuration(snapshot.uptime)}',
                ),
                color: cs.tertiary,
              ),
              _McpOpsStatusChip(
                icon: config.writeMode == McpOpsWriteMode.fullAccess
                    ? Icons.lock_open_rounded
                    : Icons.verified_user_rounded,
                label: _writeModeLabel(context, config.writeMode),
                color: cs.secondary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _McpOpsRuntimeTerminal(
            snapshot: snapshot,
            endpointUri: endpointUri,
            bindEndpointUri: bindEndpointUri,
            config: config,
          ),
          if (snapshot.errorMessage?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            Text(
              snapshot.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          if (snapshot.lastConnectivityAt != null) ...[
            const SizedBox(height: 10),
            Text(
              '${formatMonthDayHms(snapshot.lastConnectivityAt!.toLocal())} · ${snapshot.lastConnectivityMessage}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: snapshot.lastConnectivityOk
                    ? OpenHandStatusColors.success
                    : cs.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _McpOpsRuntimeTerminal extends StatelessWidget {
  const _McpOpsRuntimeTerminal({
    required this.snapshot,
    required this.endpointUri,
    required this.bindEndpointUri,
    required this.config,
  });

  final McpOpsRuntimeSnapshot snapshot;
  final String endpointUri;
  final String bindEndpointUri;
  final McpOpsConfig config;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const promptColor = OpenHandStatusColors.success;
    final commandColor = cs.tertiary;
    final textColor = Colors.white.withValues(alpha: 0.90);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _mcpOpsTerminalBackground,
        borderRadius: BorderRadius.circular(_mcpOpsTerminalRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.34)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: DefaultTextStyle(
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            height: 1.45,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _McpOpsConsoleLine(
                prompt: 'OpenHand',
                command: 'mcp-server',
                detail: endpointUri,
                promptColor: promptColor,
                commandColor: commandColor,
              ),
              if (bindEndpointUri != endpointUri)
                _McpOpsConsoleLine(
                  prompt: 'bind',
                  command: bindEndpointUri,
                  detail: 'client endpoint uses loopback for wildcard bind',
                  promptColor: promptColor,
                  commandColor: commandColor,
                ),
              _McpOpsConsoleLine(
                prompt: 'state',
                command: _lifecycleLabel(context, snapshot.lifecycle),
                detail:
                    'uptime=${formatCompactDuration(snapshot.uptime)} active=${snapshot.activeRequests} connections=${snapshot.currentConnections}',
                promptColor: promptColor,
                commandColor: commandColor,
              ),
              _McpOpsConsoleLine(
                prompt: 'traffic',
                command: 'in=${formatByteSize(snapshot.inboundBytes)}',
                detail:
                    'out=${formatByteSize(snapshot.outboundBytes)} avg=${snapshot.avgLatencyMs}ms p95=${snapshot.p95LatencyMs}ms',
                promptColor: promptColor,
                commandColor: commandColor,
              ),
              _McpOpsConsoleLine(
                prompt: 'policy',
                command: _networkModeLabel(context, config.networkMode),
                detail:
                    'write=${_writeModeLabel(context, config.writeMode)} auth=${config.requireAuthToken ? 'token' : 'none'}',
                promptColor: promptColor,
                commandColor: commandColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _McpOpsConsoleLine extends StatelessWidget {
  const _McpOpsConsoleLine({
    required this.prompt,
    required this.command,
    required this.detail,
    required this.promptColor,
    required this.commandColor,
  });

  final String prompt;
  final String command;
  final String detail;
  final Color promptColor;
  final Color commandColor;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '➜ $prompt ',
            style: TextStyle(color: promptColor),
          ),
          TextSpan(
            text: command,
            style: TextStyle(color: commandColor, fontWeight: FontWeight.w900),
          ),
          TextSpan(
            text: detail.trim().isEmpty ? '' : '  $detail',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _McpOpsMetricGrid extends StatelessWidget {
  const _McpOpsMetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = !maxWidth.isFinite
            ? 3
            : maxWidth >= _mcpOpsMetricWideBreakpoint
            ? 4
            : maxWidth >= _mcpOpsMetricMediumBreakpoint
            ? 2
            : 1;
        final width = maxWidth.isFinite
            ? (maxWidth - _mcpOpsGridGap * (columns - 1)) / columns
            : 220.0;
        return Wrap(
          spacing: _mcpOpsGridGap,
          runSpacing: _mcpOpsGridGap,
          children: [
            for (final child in children)
              SizedBox(width: width < 0 ? 0 : width, child: child),
          ],
        );
      },
    );
  }
}

class _McpOpsPanelGrid extends StatelessWidget {
  const _McpOpsPanelGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = !maxWidth.isFinite
            ? 2
            : maxWidth >= 920
            ? 2
            : 1;
        final width = maxWidth.isFinite
            ? (maxWidth - _mcpOpsGridGap * (columns - 1)) / columns
            : 420.0;
        return Wrap(
          spacing: _mcpOpsGridGap,
          runSpacing: _mcpOpsGridGap,
          children: [
            for (final child in children)
              SizedBox(width: width < 0 ? 0 : width, child: child),
          ],
        );
      },
    );
  }
}

class _McpOpsMetricTile extends StatelessWidget {
  const _McpOpsMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? helper;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tone = color ?? cs.primary;
    final duration = openHandMotionDurationMs(context, 180);
    return _McpOpsTappableCard(
      onTap: onTap,
      radius: _mcpOpsPanelRadius,
      tone: tone,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.66),
          borderRadius: BorderRadius.circular(_mcpOpsPanelRadius),
          border: Border.all(color: tone.withValues(alpha: 0.26)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tone.withValues(alpha: 0.22)),
                  ),
                  child: Icon(icon, size: 17, color: tone),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: tone.withValues(alpha: 0.7),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value.trim().isEmpty ? '-' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            if (helper?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(
                helper!.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tone.withValues(alpha: 0.86),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared tap affordance for ops cards: a hover-highlighted, press-scaled
/// wrapper that stays inert (and shows no pointer cursor) when [onTap] is null.
class _McpOpsTappableCard extends StatefulWidget {
  const _McpOpsTappableCard({
    required this.child,
    required this.radius,
    required this.tone,
    this.onTap,
  });

  final Widget child;
  final double radius;
  final Color tone;
  final VoidCallback? onTap;

  @override
  State<_McpOpsTappableCard> createState() => _McpOpsTappableCardState();
}

class _McpOpsTappableCardState extends State<_McpOpsTappableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    final duration = _mcpMotionDuration(
      context,
      const Duration(milliseconds: 120),
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: Stack(
            children: [
              widget.child,
              Positioned.fill(
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: _pressed
                        ? widget.tone.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(widget.radius),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _McpOpsTrendPanel extends StatelessWidget {
  const _McpOpsTrendPanel({
    required this.title,
    required this.icon,
    required this.series,
    required this.emptyLabel,
    this.subtitle = '',
    this.valueSuffix = '',
    this.onTap,
  });

  final String title;
  final IconData icon;
  final List<_McpOpsChartSeries> series;
  final String emptyLabel;
  final String subtitle;
  final String valueSuffix;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxValue = series
        .expand((item) => item.values)
        .fold<double>(0, (max, value) => math.max(max, value));
    return _McpOpsPanel(
      icon: icon,
      title: title,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle.trim().isNotEmpty) ...[
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            height: 156,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _McpOpsSmoothLineChartPainter(
                  series: series,
                  gridColor: cs.outlineVariant.withValues(alpha: 0.46),
                  labelColor: cs.onSurfaceVariant,
                  emptyLabel: maxValue <= 0 ? emptyLabel : '',
                  valueSuffix: valueSuffix,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final item in series)
                _McpOpsLegendPill(label: item.label, color: item.color),
            ],
          ),
        ],
      ),
    );
  }
}

class _McpOpsSmoothLineChartPainter extends CustomPainter {
  const _McpOpsSmoothLineChartPainter({
    required this.series,
    required this.gridColor,
    required this.labelColor,
    required this.emptyLabel,
    required this.valueSuffix,
  });

  final List<_McpOpsChartSeries> series;
  final Color gridColor;
  final Color labelColor;
  final String emptyLabel;
  final String valueSuffix;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final chart = Rect.fromLTWH(8, 8, size.width - 16, size.height - 24);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    for (var i = 0; i < 6; i++) {
      final x = chart.left + chart.width * i / 5;
      canvas.drawLine(Offset(x, chart.top), Offset(x, chart.bottom), gridPaint);
    }

    final allValues = series.expand((item) => item.values).toList();
    final maxValue = allValues.fold<double>(
      0,
      (max, value) => math.max(max, value),
    );
    if (maxValue <= 0) {
      _paintEmpty(canvas, bounds);
      return;
    }
    final normalizedMax = maxValue <= 1 ? 1.0 : maxValue * 1.14;
    for (final item in series) {
      if (item.values.isEmpty) continue;
      final points = <Offset>[];
      final denominator = math.max(1, item.values.length - 1);
      for (var i = 0; i < item.values.length; i++) {
        final x = chart.left + chart.width * i / denominator;
        final ratio = (item.values[i] / normalizedMax).clamp(0.0, 1.0);
        final y = chart.bottom - chart.height * ratio;
        points.add(Offset(x, y));
      }
      if (points.length == 1) {
        points.add(Offset(chart.right, points.first.dy));
      }
      final areaPath = _smoothPath(points)
        ..lineTo(points.last.dx, chart.bottom)
        ..lineTo(points.first.dx, chart.bottom)
        ..close();
      canvas.drawPath(
        areaPath,
        Paint()..color = item.color.withValues(alpha: 0.08),
      );
      canvas.drawPath(
        _smoothPath(points),
        Paint()
          ..color = item.color
          ..strokeWidth = 2.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawCircle(points.last, 3.4, Paint()..color = item.color);
    }
    final maxLabel = valueSuffix.isEmpty
        ? maxValue.round().toString()
        : '${maxValue.round()}$valueSuffix';
    _paintLabel(canvas, maxLabel, Offset(chart.left + 2, chart.top + 2));
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  void _paintEmpty(Canvas canvas, Rect bounds) {
    if (emptyLabel.trim().isEmpty) return;
    final painter = TextPainter(
      text: TextSpan(
        text: emptyLabel,
        style: TextStyle(
          color: labelColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: bounds.width);
    painter.paint(
      canvas,
      Offset(
        bounds.center.dx - painter.width / 2,
        bounds.center.dy - painter.height / 2,
      ),
    );
  }

  void _paintLabel(Canvas canvas, String label, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: labelColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _McpOpsSmoothLineChartPainter oldDelegate) {
    return oldDelegate.series != series ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.emptyLabel != emptyLabel ||
        oldDelegate.valueSuffix != valueSuffix;
  }
}

class _McpOpsLegendPill extends StatelessWidget {
  const _McpOpsLegendPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _McpOpsPanel extends StatelessWidget {
  const _McpOpsPanel({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final subtitleText = subtitle?.trim();
    final panel = AnimatedContainer(
      duration: _mcpMotionDuration(context, const Duration(milliseconds: 180)),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(_mcpOpsPanelRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.62)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.primary.withValues(alpha: 0.18),
                        cs.primary.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Icon(icon, color: cs.primary, size: 19),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitleText != null && subtitleText.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitleText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
                if (trailing == null && onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
    if (onTap == null) return panel;
    return _McpOpsTappableCard(
      onTap: onTap,
      radius: _mcpOpsPanelRadius,
      tone: cs.primary,
      child: panel,
    );
  }
}

class _McpOpsFieldGroup extends StatelessWidget {
  const _McpOpsFieldGroup({
    required this.icon,
    required this.label,
    required this.child,
    this.hint,
    this.topGap = 0,
  });

  final IconData icon;
  final String label;
  final String? hint;
  final Widget child;
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hintText = hint?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (topGap > 0) SizedBox(height: topGap),
        Row(
          children: [
            Icon(icon, size: 16, color: cs.primary),
            const SizedBox(width: 7),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cs.outlineVariant.withValues(alpha: 0.5),
                      cs.outlineVariant.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (hintText != null && hintText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 23),
            child: Text(
              hintText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _McpOpsCountBadge extends StatelessWidget {
  const _McpOpsCountBadge({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tone = active ? cs.primary : cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: active ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: tone,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _McpOpsExposureQuickActions extends StatelessWidget {
  const _McpOpsExposureQuickActions({
    required this.allEnabled,
    required this.onEnableAll,
    required this.onDisableAll,
    required this.enableLabel,
    required this.disableLabel,
  });

  final bool allEnabled;
  final VoidCallback onEnableAll;
  final VoidCallback onDisableAll;
  final String enableLabel;
  final String disableLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _McpOpsTogglePill(
          selected: allEnabled,
          icon: Icons.done_all_rounded,
          label: enableLabel,
          onChanged: (_) => onEnableAll(),
        ),
        const SizedBox(width: 8),
        _McpOpsTogglePill(
          selected: false,
          icon: Icons.remove_done_rounded,
          label: disableLabel,
          onChanged: (_) => onDisableAll(),
        ),
      ],
    );
  }
}

class _McpOpsExposureSummary extends StatelessWidget {
  const _McpOpsExposureSummary({
    required this.enabledSurfaces,
    required this.totalSurfaces,
    required this.exposedItems,
    required this.totalItems,
  });

  final int enabledSurfaces;
  final int totalSurfaces;
  final int exposedItems;
  final int totalItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = totalItems <= 0 ? 0.0 : exposedItems / totalItems;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.1),
            cs.primary.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _localizedText(
                    context,
                    zh: '已启用 $enabledSurfaces / $totalSurfaces 个面 · 暴露 $exposedItems / $totalItems 个条目',
                    en: '$enabledSurfaces / $totalSurfaces surfaces on · $exposedItems / $totalItems items exposed',
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                '${(ratio * 100).round()}%',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: ratio.clamp(0, 1).toDouble()),
              duration: _mcpMotionDuration(
                context,
                const Duration(milliseconds: 420),
              ),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 7,
                color: cs.primary,
                backgroundColor: cs.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _McpOpsDistributionPanel extends StatelessWidget {
  const _McpOpsDistributionPanel({
    required this.title,
    required this.icon,
    required this.values,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Map<String, int> values;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sorted = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList(growable: false);
    final total = values.values.fold<int>(0, (sum, value) => sum + value);
    final palette = _mcpOpsChartPalette(cs);
    return _McpOpsPanel(
      icon: icon,
      title: title,
      onTap: onTap,
      child: top.isEmpty
          ? Text(
              _localizedText(context, zh: '等待请求样本', en: 'Waiting for traffic'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          : Row(
              children: [
                SizedBox(
                  width: 112,
                  height: 112,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _McpOpsDonutChartPainter(
                        values: top.map((entry) => entry.value).toList(),
                        colors: palette,
                        trackColor: cs.surfaceContainerHighest,
                      ),
                      child: Center(
                        child: Text(
                          '$total',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < top.length; i++)
                        _McpOpsDistributionRow(
                          label: top[i].key,
                          value: top[i].value,
                          total: total,
                          color: palette[i % palette.length],
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _McpOpsDonutChartPainter extends CustomPainter {
  const _McpOpsDonutChartPainter({
    required this.values,
    required this.colors,
    required this.trackColor,
  });

  final List<int> values;
  final List<Color> colors;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final stroke = math.max(10.0, math.min(size.shortestSide * 0.16, 18.0));
    final rect =
        Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2,
      false,
      paint..color = trackColor,
    );
    if (total <= 0 || colors.isEmpty) return;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = math.pi * 2 * values[i] / total;
      if (sweep <= 0) continue;
      canvas.drawArc(
        rect,
        start,
        math.max(0.03, sweep - 0.018),
        false,
        paint..color = colors[i % colors.length],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _McpOpsDonutChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.trackColor != trackColor;
  }
}

class _McpOpsDistributionRow extends StatelessWidget {
  const _McpOpsDistributionRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
    this.showPercent = false,
  });

  final String label;
  final int value;
  final int total;
  final Color color;
  final bool showPercent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ratio = total <= 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
              if (showPercent) ...[
                Text(
                  '${(ratio * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                '$value',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              minHeight: 8,
              color: color,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

List<Color> _mcpOpsChartPalette(ColorScheme cs) {
  return <Color>[
    cs.primary,
    cs.tertiary,
    OpenHandStatusColors.success,
    OpenHandStatusColors.warning,
    cs.error,
    cs.secondary,
  ];
}

class _McpOpsResponsiveFields extends StatelessWidget {
  const _McpOpsResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - _mcpOpsGridGap * (columns - 1)) / columns;
        return Wrap(
          spacing: _mcpOpsGridGap,
          runSpacing: _mcpOpsGridGap,
          children: [
            for (final child in children)
              SizedBox(width: width < 0 ? 0 : width, child: child),
          ],
        );
      },
    );
  }
}

class _McpOpsSwitchChip extends StatelessWidget {
  const _McpOpsSwitchChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _McpOpsTogglePill(
      selected: value,
      icon: value ? Icons.check_rounded : Icons.close_rounded,
      label: label,
      onChanged: onChanged,
    );
  }
}

class _McpOpsHintText extends StatelessWidget {
  const _McpOpsHintText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _McpOpsTogglePill extends StatelessWidget {
  const _McpOpsTogglePill({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onChanged,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tone = selected ? cs.primary : cs.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        hoverColor: tone.withValues(alpha: 0.08),
        splashColor: tone.withValues(alpha: 0.08),
        highlightColor: tone.withValues(alpha: 0.05),
        onTap: () => onChanged(!selected),
        child: AnimatedContainer(
          duration: _mcpMotionDuration(
            context,
            const Duration(milliseconds: 160),
          ),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? tone.withValues(alpha: 0.14)
                : cs.surfaceContainerHighest.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? tone.withValues(alpha: 0.32)
                  : cs.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? tone : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _McpOpsExposureRow {
  const _McpOpsExposureRow({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.endpoints,
    this.endpointLabels = const <String, String>{},
    this.inputSchema,
    this.defaultSchema,
    this.onSchemaSaved,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<String> endpoints;
  final Map<String, String> endpointLabels;

  /// 入参 JSON Schema（内建工具携带真实参数定义），供暴露面板结构化预览与编辑。
  final Map<String, Object?>? inputSchema;

  /// 出厂默认 Schema，用于弹窗内「恢复默认」。
  final Map<String, Object?>? defaultSchema;

  /// 持久化回调；为空表示该条目 Schema 只读。返回是否保存成功。
  final Future<bool> Function(Map<String, Object?>? schema)? onSchemaSaved;

  bool get hasInputSchema => inputSchema?.isNotEmpty == true;

  bool get schemaEditable => onSchemaSaved != null;
}

class _McpOpsExposureTile extends StatelessWidget {
  const _McpOpsExposureTile({
    required this.surface,
    required this.row,
    required this.itemVisible,
    required this.endpointVisible,
    required this.onItemChanged,
    required this.onEndpointChanged,
  });

  final McpOpsExposureSurface surface;
  final _McpOpsExposureRow row;
  final bool itemVisible;
  final bool Function(String endpoint) endpointVisible;
  final ValueChanged<bool> onItemChanged;
  final void Function(String endpoint, bool visible) onEndpointChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final showSchemaPill = itemVisible && row.hasInputSchema;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: itemVisible
            ? cs.surfaceContainerHigh.withValues(alpha: 0.52)
            : cs.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
        border: Border.all(
          color: itemVisible
              ? cs.primary.withValues(alpha: 0.20)
              : cs.outlineVariant.withValues(alpha: 0.46),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (row.subtitle.trim().isNotEmpty)
                        Text(
                          row.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                    ],
                  ),
                ),
                Switch(value: itemVisible, onChanged: onItemChanged),
              ],
            ),
            if (itemVisible && row.endpoints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final endpoint in row.endpoints)
                    _McpOpsTogglePill(
                      selected: endpointVisible(endpoint),
                      icon: endpointVisible(endpoint)
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      label: row.endpointLabels[endpoint] ?? endpoint,
                      onChanged: (value) => onEndpointChanged(endpoint, value),
                    ),
                  // Shares _McpOpsTogglePill geometry so its top/bottom edges
                  // line up exactly with the invoke pill beside it.
                  if (showSchemaPill)
                    _McpOpsSchemaPill(
                      editable: row.schemaEditable,
                      onTap: () => _openSchemaDialog(context),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openSchemaDialog(BuildContext context) {
    showAnimatedDialog<void>(
      context: context,
      builder: (_) => _McpOpsSchemaDialog(
        title: row.title,
        subtitle: row.subtitle,
        schema: row.inputSchema!,
        defaultSchema: row.defaultSchema,
        onSaved: row.onSchemaSaved,
      ),
    );
  }
}

/// 暴露面板中「参数 Schema」胶囊按钮，几何尺寸与 [_McpOpsTogglePill] 完全一致，
/// 从而与左侧 invoke 胶囊上下对齐；点击打开结构化 Schema 弹窗。
class _McpOpsSchemaPill extends StatelessWidget {
  const _McpOpsSchemaPill({required this.editable, required this.onTap});

  final bool editable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        hoverColor: cs.primary.withValues(alpha: 0.08),
        splashColor: cs.primary.withValues(alpha: 0.08),
        highlightColor: cs.primary.withValues(alpha: 0.05),
        onTap: onTap,
        child: AnimatedContainer(
          duration: _mcpMotionDuration(
            context,
            const Duration(milliseconds: 160),
          ),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.primary.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.data_object_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 7),
              Text(
                _localizedText(context, zh: '参数 Schema', en: 'Schema'),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                editable ? Icons.edit_rounded : Icons.open_in_full_rounded,
                size: 14,
                color: cs.primary.withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Structured, editable viewer for a builtin tool's input schema. The schema is
/// surfaced as a hierarchical field list (name · type · required · description)
/// with a raw-JSON editor underneath; edits validate before persisting through
/// [onSaved]. Read-only when [onSaved] is null. Reuses the shared ops dialog
/// shell so it inherits the global Q-elastic enter/exit motion.
class _McpOpsSchemaDialog extends StatefulWidget {
  const _McpOpsSchemaDialog({
    required this.title,
    required this.subtitle,
    required this.schema,
    required this.defaultSchema,
    required this.onSaved,
  });

  final String title;
  final String subtitle;
  final Map<String, Object?> schema;
  final Map<String, Object?>? defaultSchema;
  final Future<bool> Function(Map<String, Object?>? schema)? onSaved;

  @override
  State<_McpOpsSchemaDialog> createState() => _McpOpsSchemaDialogState();
}

class _McpOpsSchemaDialogState extends State<_McpOpsSchemaDialog> {
  late final TextEditingController _editorController;
  bool get _editable => widget.onSaved != null;
  bool _rawMode = false;
  bool _saving = false;
  String? _error;
  late String _savedText;

  @override
  void initState() {
    super.initState();
    _savedText = prettyPrintJson(widget.schema);
    _editorController = TextEditingController(text: _savedText);
  }

  @override
  void dispose() {
    _editorController.dispose();
    super.dispose();
  }

  /// Current editor text parsed back into a schema map, or null when invalid.
  Map<String, Object?>? get _parsedSchema =>
      optionalStringKeyedMapFromJsonText(_editorController.text);

  bool get _dirty => _editorController.text.trim() != _savedText.trim();

  bool get _canRestoreDefault {
    final defaultSchema = widget.defaultSchema;
    if (defaultSchema == null) return false;
    final parsed = _parsedSchema;
    return parsed == null || !_mcpJsonEquals(parsed, defaultSchema);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final parsed = _parsedSchema;
    final fields = _schemaFields(parsed ?? widget.schema);
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: 820,
      maxWidthFraction: 0.94,
      maxHeightFraction: 0.92,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_mcpOpsOuterRadius),
      ),
      child: _McpOpsDialogSurface(
        child: _McpOpsConsoleShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHero(context, theme, cs),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  physics: openHandDialogAwareScrollPhysics(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _McpOpsSchemaFieldList(fields: fields),
                      const SizedBox(height: _mcpOpsGridGap),
                      _buildSourcePanel(context, theme, cs),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _McpOpsHeaderMessage(text: _error!, tone: cs.error),
              ],
              buildOpenHandDialogActionsBar(
                actions: _buildActions(context, l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, ThemeData theme, ColorScheme cs) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: cs.primary.withValues(alpha: 0.28)),
          ),
          child: Icon(Icons.data_object_rounded, color: cs.primary, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _editable
                    ? _localizedText(
                        context,
                        zh: '参数 Schema · 可编辑',
                        en: 'Input schema · Editable',
                      )
                    : _localizedText(
                        context,
                        zh: '参数 Schema · 只读',
                        en: 'Input schema · Read-only',
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _buildSourcePanel(BuildContext context, ThemeData theme, ColorScheme cs) {
    return _McpOpsPanel(
      icon: Icons.code_rounded,
      title: _localizedText(context, zh: 'Schema 源码', en: 'Schema Source'),
      subtitle: _editable
          ? _localizedText(
              context,
              zh: '编辑标准 JSON Schema；保存前会自动校验格式。',
              en: 'Edit the JSON Schema; format is validated before saving.',
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editable)
            _McpOpsTogglePill(
              selected: _rawMode,
              icon: _rawMode ? Icons.edit_note_rounded : Icons.visibility_rounded,
              label: _rawMode
                  ? _localizedText(context, zh: '编辑', en: 'Edit')
                  : _localizedText(context, zh: '预览', en: 'Preview'),
              onChanged: (value) => setState(() => _rawMode = value),
            ),
          const SizedBox(width: 8),
          _McpOpsIconButton(
            icon: Icons.copy_rounded,
            tooltip: _localizedText(context, zh: '复制', en: 'Copy'),
            onPressed: () => copyMcpTextToClipboard(
              context: context,
              text: _editorController.text,
              successMessage: _localizedText(
                context,
                zh: '已复制 Schema',
                en: 'Schema copied',
              ),
              logAction: 'copy ops tool schema',
            ),
          ),
        ],
      ),
      child: (!_editable || !_rawMode)
          ? _McpOpsSchemaCodeView(text: _editorController.text)
          : TextField(
              controller: _editorController,
              onChanged: (_) => setState(() => _error = null),
              maxLines: null,
              minLines: 10,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.5,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
    );
  }

  List<Widget> _buildActions(BuildContext context, AppLocalizations l10n) {
    if (!_editable) {
      return [
        OpenHandDialogActionButton.primary(
          onPressed: () => Navigator.of(context).maybePop(),
          label: l10n.commonClose,
        ),
      ];
    }
    return [
      if (widget.defaultSchema != null)
        OpenHandDialogActionButton.secondary(
          icon: Icons.restart_alt_rounded,
          onPressed: _saving || !_canRestoreDefault
              ? null
              : _restoreDefault,
          label: _localizedText(context, zh: '恢复默认', en: 'Default'),
        ),
      OpenHandDialogActionButton.secondary(
        onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
        label: l10n.commonClose,
      ),
      OpenHandDialogActionButton.primary(
        icon: Icons.save_rounded,
        busy: _saving,
        onPressed: _saving || !_dirty ? null : _save,
        label: l10n.commonSave,
      ),
    ];
  }

  void _restoreDefault() {
    final defaultSchema = widget.defaultSchema;
    if (defaultSchema == null) return;
    setState(() {
      _editorController.text = prettyPrintJson(defaultSchema);
      _error = null;
    });
  }

  Future<void> _save() async {
    final parsed = _parsedSchema;
    if (parsed == null) {
      setState(() {
        _error = _localizedText(
          context,
          zh: 'JSON 格式无效，请检查后重试。',
          en: 'Invalid JSON. Please fix and retry.',
        );
      });
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.onSaved!(parsed);
    if (!mounted) return;
    if (ok) {
      OpenHandSnackBar.flash(
        context,
        _localizedText(context, zh: 'Schema 已保存', en: 'Schema saved'),
        kind: OpenHandSnackKind.success,
        postFrame: true,
      );
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _saving = false;
      _error = _localizedText(context, zh: '保存失败，请重试。', en: 'Save failed.');
    });
  }
}

/// Hierarchical, read-first rendering of parsed schema fields. Groups the field
/// name, type badge, required marker and description into structured cards.
class _McpOpsSchemaFieldList extends StatelessWidget {
  const _McpOpsSchemaFieldList({required this.fields});

  final List<_SchemaField> fields;

  @override
  Widget build(BuildContext context) {
    return _McpOpsPanel(
      icon: Icons.account_tree_rounded,
      title: _localizedText(context, zh: '参数结构', en: 'Parameters'),
      subtitle: _localizedText(
        context,
        zh: '按字段名、类型、是否必填与说明分层展示。',
        en: 'Structured by name, type, requirement and description.',
      ),
      trailing: _McpOpsCountBadge(text: '${fields.length}', active: true),
      child: fields.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _localizedText(
                  context,
                  zh: '该工具无入参字段。',
                  en: 'This tool takes no parameters.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              children: [
                for (final field in fields.indexed) ...[
                  if (field.$1 != 0) const SizedBox(height: 10),
                  _McpOpsSchemaFieldCard(field: field.$2),
                ],
              ],
            ),
    );
  }
}

class _McpOpsSchemaFieldCard extends StatelessWidget {
  const _McpOpsSchemaFieldCard({required this.field});

  final _SchemaField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                field.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                ),
              ),
              _McpOpsStatusChip(
                icon: Icons.code_rounded,
                label: field.type,
                color: cs.secondary,
              ),
              if (field.required)
                _McpOpsStatusChip(
                  icon: Icons.priority_high_rounded,
                  label: _localizedText(context, zh: '必填', en: 'Required'),
                  color: cs.error,
                ),
            ],
          ),
          if (field.description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              field.description.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Syntax-neutral, scroll-safe code display for the schema JSON preview.
class _McpOpsSchemaCodeView extends StatelessWidget {
  const _McpOpsSchemaCodeView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: SelectableText(
        text.trim().isEmpty ? '{}' : text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.5,
        ),
      ),
    );
  }
}

/// A single audit log entry rendered as a fully-clickable, structured card:
/// a status accent rail, a stage badge, a title + stage/status header, and a
/// compact metadata strip. Tapping anywhere (or the trailing button) opens the
/// detail dialog.
class _McpOpsAuditRow extends StatelessWidget {
  const _McpOpsAuditRow({required this.entry, required this.onDetails});

  final McpOpsAuditEntry entry;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = _mcpOpsAuditStatusColor(context, entry);
    return HoverLift(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_mcpOpsPanelRadius),
          onTap: onDetails,
          hoverColor: cs.primary.withValues(alpha: 0.04),
          splashColor: cs.primary.withValues(alpha: 0.07),
          highlightColor: cs.primary.withValues(alpha: 0.04),
          child: AnimatedContainer(
            duration: _mcpMotionDuration(
              context,
              const Duration(milliseconds: 180),
            ),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(_mcpOpsPanelRadius),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.62),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_mcpOpsPanelRadius),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: statusColor),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(context, theme, cs, statusColor),
                            const SizedBox(height: 12),
                            _buildMetaStrip(context, cs),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    Color statusColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: statusColor.withValues(alpha: 0.24)),
          ),
          child: Icon(
            _mcpOpsAuditKindIcon(entry.kind),
            size: 19,
            color: statusColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _mcpOpsAuditTitle(context, entry),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_mcpOpsAuditKindLabel(context, entry.kind)} · ${formatMonthDayHms(entry.timestamp.toLocal())}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Keep the status capsule and the open button on one baseline: the
        // IntrinsicHeight + stretch pins the round button to the capsule's
        // exact height, so their top and bottom edges line up precisely.
        IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _McpOpsStatusChip(
                icon: Icons.circle_rounded,
                label: _mcpOpsAuditStatusLabel(context, entry.status),
                color: statusColor,
              ),
              const SizedBox(width: 8),
              AspectRatio(
                aspectRatio: 1,
                child: _McpOpsAuditOpenButton(onTap: onDetails),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetaStrip(BuildContext context, ColorScheme cs) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _McpOpsStatusChip(
          icon: Icons.timer_rounded,
          label: '${entry.durationMs}ms',
          color: cs.primary,
        ),
        _McpOpsStatusChip(
          icon: Icons.token_rounded,
          label: '${entry.totalTokens} tokens',
          color: cs.secondary,
        ),
        _McpOpsStatusChip(
          icon: Icons.swap_vert_rounded,
          label:
              '${formatByteSize(entry.inboundBytes)} / ${formatByteSize(entry.outboundBytes)}',
          color: cs.tertiary,
        ),
        _McpOpsStatusChip(
          icon: Icons.api_rounded,
          label: entry.protocol,
          color: cs.tertiary,
        ),
        _McpOpsStatusChip(
          icon: Icons.devices_rounded,
          label: entry.clientName,
          color: cs.primary,
        ),
        _McpOpsStatusChip(
          icon: Icons.public_rounded,
          label: entry.ipAddress,
          color: cs.secondary,
        ),
      ],
    );
  }
}

/// Circular "open detail" affordance shown at the top-right of an audit card.
/// Sized by an [AspectRatio] against the sibling status capsule so it stays a
/// perfect circle whose top/bottom edges align with the capsule.
class _McpOpsAuditOpenButton extends StatelessWidget {
  const _McpOpsAuditOpenButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: cs.primary.withValues(alpha: 0.10),
        splashColor: cs.primary.withValues(alpha: 0.12),
        highlightColor: cs.primary.withValues(alpha: 0.06),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.58),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: cs.onSurfaceVariant.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

class _McpOpsAuditSummaryPanel extends StatelessWidget {
  const _McpOpsAuditSummaryPanel({required this.entries});

  final List<McpOpsAuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    final total = entries.length;
    final blocked = entries.where((entry) => entry.blocked).length;
    final failed = entries.where((entry) => entry.errored).length;
    final success = math.max(0, total - blocked - failed);
    final avgLatency = total == 0
        ? 0
        : (entries.fold<int>(0, (sum, entry) => sum + entry.durationMs) / total)
              .round();
    final inbound = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.inboundBytes,
    );
    final outbound = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.outboundBytes,
    );
    final successRate = total == 0 ? 0.0 : success / total * 100;
    final stageCounts = <McpOpsAuditKind, int>{};
    for (final entry in entries) {
      stageCounts[entry.kind] = (stageCounts[entry.kind] ?? 0) + 1;
    }
    final stages = stageCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _McpOpsPanel(
      icon: Icons.analytics_rounded,
      title: _localizedText(context, zh: '审计概览', en: 'Audit Overview'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _McpOpsMetricGrid(
            children: [
              _McpOpsMetricTile(
                icon: Icons.receipt_long_rounded,
                label: _localizedText(context, zh: '日志总数', en: 'Total Logs'),
                value: '$total',
                helper: _localizedText(
                  context,
                  zh: '滚动窗口 · 成功率 ${successRate.toStringAsFixed(1)}%',
                  en: 'Rolling · ${successRate.toStringAsFixed(1)}% ok',
                ),
              ),
              _McpOpsMetricTile(
                icon: Icons.task_alt_rounded,
                label: _localizedText(context, zh: '成功', en: 'Success'),
                value: '$success',
                color: OpenHandStatusColors.success,
              ),
              _McpOpsMetricTile(
                icon: Icons.shield_rounded,
                label: _localizedText(context, zh: '拦截', en: 'Blocked'),
                value: '$blocked',
                color: OpenHandStatusColors.warning,
              ),
              _McpOpsMetricTile(
                icon: Icons.error_outline_rounded,
                label: _localizedText(context, zh: '失败', en: 'Failed'),
                value: '$failed',
                color: Theme.of(context).colorScheme.error,
              ),
              _McpOpsMetricTile(
                icon: Icons.timer_rounded,
                label: _localizedText(context, zh: '平均耗时', en: 'Average latency'),
                value: '${avgLatency}ms',
              ),
              _McpOpsMetricTile(
                icon: Icons.swap_vert_rounded,
                label: _localizedText(context, zh: '进出口流量', en: 'Traffic'),
                value:
                    '${formatByteSize(inbound)} / ${formatByteSize(outbound)}',
              ),
            ],
          ),
          if (stages.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              _localizedText(context, zh: '环节分布', en: 'Stage breakdown'),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final stage in stages)
                  _McpOpsStatusChip(
                    icon: _mcpOpsAuditKindIcon(stage.key),
                    label:
                        '${_mcpOpsAuditKindLabel(context, stage.key)} · ${stage.value}',
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _McpOpsAuditDetailDialog extends StatelessWidget {
  const _McpOpsAuditDetailDialog({required this.entry});

  final McpOpsAuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final statusColor = _mcpOpsAuditStatusColor(context, entry);
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: 920,
      maxHeight: 760,
      maxWidthFraction: 0.94,
      maxHeightFraction: 0.92,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_mcpOpsOuterRadius),
      ),
      child: _McpOpsDialogSurface(
        child: _McpOpsConsoleShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHero(context, statusColor),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  physics: openHandDialogAwareScrollPhysics(context),
                  child: Column(
                    children: [
                      _McpOpsDetailSection(
                        icon: Icons.route_rounded,
                        title: _localizedText(
                          context,
                          zh: '调用环节',
                          en: 'Call Stage',
                        ),
                        rows: {
                          _localizedText(context, zh: '环节', en: 'Stage'):
                              _mcpOpsAuditKindLabel(context, entry.kind),
                          _localizedText(context, zh: '工具/方法', en: 'Tool/Method'):
                              _mcpOpsAuditTitle(context, entry),
                          _localizedText(context, zh: '暴露面', en: 'Surface'):
                              entry.surface,
                          _localizedText(context, zh: '接口', en: 'Endpoint'):
                              entry.endpoint,
                          _localizedText(context, zh: '状态', en: 'Status'):
                              _mcpOpsAuditStatusLabel(context, entry.status),
                          _localizedText(context, zh: '日志ID', en: 'Log ID'):
                              entry.id,
                        },
                      ),
                      const SizedBox(height: _mcpOpsGridGap),
                      _McpOpsDetailSection(
                        icon: Icons.speed_rounded,
                        title: _localizedText(
                          context,
                          zh: '性能与流量',
                          en: 'Performance',
                        ),
                        rows: {
                          _localizedText(context, zh: '调用耗时', en: 'Duration'):
                              '${entry.durationMs}ms',
                          _localizedText(context, zh: 'Token数', en: 'Tokens'):
                              '${entry.totalTokens} (${entry.promptTokens} + ${entry.completionTokens})',
                          _localizedText(context, zh: '入口流量', en: 'Inbound'):
                              formatByteSize(entry.inboundBytes),
                          _localizedText(context, zh: '出口流量', en: 'Outbound'):
                              formatByteSize(entry.outboundBytes),
                        },
                      ),
                      const SizedBox(height: _mcpOpsGridGap),
                      _McpOpsDetailSection(
                        icon: Icons.hub_rounded,
                        title: _localizedText(
                          context,
                          zh: '来源与环境',
                          en: 'Peer & Environment',
                        ),
                        rows: {
                          _localizedText(context, zh: '请求时间', en: 'Time'):
                              entry.timestamp.toLocal().toIso8601String(),
                          _localizedText(context, zh: '来源客户端', en: 'Client'):
                              entry.clientName,
                          _localizedText(context, zh: '来源IP', en: 'IP'):
                              entry.ipAddress,
                          _localizedText(context, zh: '协议', en: 'Protocol'):
                              entry.protocol,
                          _localizedText(context, zh: '模型', en: 'Model'):
                              entry.model,
                          ...entry.environment.map(
                            (key, value) => MapEntry(key, '$value'),
                          ),
                        },
                      ),
                      if (entry.errorMessage.trim().isNotEmpty) ...[
                        const SizedBox(height: _mcpOpsGridGap),
                        _McpOpsDetailText(
                          icon: Icons.report_gmailerrorred_rounded,
                          title: _localizedText(
                            context,
                            zh: '错误信息',
                            en: 'Error',
                          ),
                          text: entry.errorMessage,
                          tone: statusColor,
                        ),
                      ],
                      const SizedBox(height: _mcpOpsGridGap),
                      _McpOpsDetailText(
                        icon: Icons.data_object_rounded,
                        title: _localizedText(
                          context,
                          zh: '请求参数',
                          en: 'Parameters',
                        ),
                        text: entry.argumentsPreview,
                      ),
                      const SizedBox(height: _mcpOpsGridGap),
                      _McpOpsDetailText(
                        icon: Icons.http_rounded,
                        title: _localizedText(
                          context,
                          zh: '请求摘要',
                          en: 'Request',
                        ),
                        text: entry.requestSummary,
                      ),
                      const SizedBox(height: _mcpOpsGridGap),
                      _McpOpsDetailText(
                        icon: Icons.subject_rounded,
                        title: _localizedText(
                          context,
                          zh: '响应内容',
                          en: 'Response',
                        ),
                        text: entry.responsePreview,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, Color statusColor) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: statusColor.withValues(alpha: 0.28)),
          ),
          child: Icon(
            _mcpOpsAuditKindIcon(entry.kind),
            color: statusColor,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _mcpOpsAuditTitle(context, entry),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_mcpOpsAuditKindLabel(context, entry.kind)} · ${_mcpOpsAuditStatusLabel(context, entry.status)} · ${formatMonthDayHms(entry.timestamp.toLocal())}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

class _McpOpsDetailSection extends StatelessWidget {
  const _McpOpsDetailSection({
    required this.title,
    required this.rows,
    this.icon = Icons.info_outline_rounded,
  });

  final String title;
  final Map<String, String> rows;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final visibleRows = rows.entries
        .where((row) => row.value.trim().isNotEmpty)
        .toList(growable: false);
    return _McpOpsPanel(
      icon: icon,
      title: title,
      child: Column(
        children: [
          for (final row in visibleRows.indexed)
            Padding(
              padding: EdgeInsets.only(
                bottom: row.$1 == visibleRows.length - 1 ? 0 : 10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 180,
                    child: Text(
                      row.$2.key,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      row.$2.value,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _McpOpsDetailText extends StatelessWidget {
  const _McpOpsDetailText({
    required this.title,
    required this.text,
    this.icon = Icons.notes_rounded,
    this.tone,
  });

  final String title;
  final String text;
  final IconData icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final trimmed = text.trim();
    final accent = tone ?? cs.primary;
    return _McpOpsPanel(
      icon: icon,
      title: title,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(_mcpOpsControlRadius),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
        ),
        child: SelectableText(
          trimmed.isEmpty ? '—' : trimmed,
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.5,
            color: trimmed.isEmpty ? cs.onSurfaceVariant : null,
          ),
        ),
      ),
    );
  }
}

class _McpOpsApprovalPanel extends StatelessWidget {
  const _McpOpsApprovalPanel({required this.requests});

  final List<McpOpsApprovalRequest> requests;

  @override
  Widget build(BuildContext context) {
    return _McpOpsPanel(
      icon: Icons.verified_user_rounded,
      title: _localizedText(context, zh: '写调用审批', en: 'Write Approvals'),
      child: Column(
        children: [
          for (final request in requests)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(request.toolName),
              subtitle: Text(
                '${request.clientName} · ${request.ipAddress} · ${formatMonthDayHms(request.requestedAt.toLocal())}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => context
                        .read<McpController>()
                        .resolveOpsApproval(request.id, approved: false),
                    child: Text(
                      _localizedText(context, zh: '拒绝', en: 'Reject'),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => context
                        .read<McpController>()
                        .resolveOpsApproval(request.id, approved: true),
                    child: Text(_localizedText(context, zh: '放行', en: 'Allow')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _McpOpsStatusChip extends StatelessWidget {
  const _McpOpsStatusChip({
    required this.icon,
    required this.label,
    required this.color,
    this.monospace = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxLabelWidth = math.min(
      460.0,
      math.max(120.0, MediaQuery.sizeOf(context).width * 0.58),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxLabelWidth),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _surfaceLabel(BuildContext context, McpOpsExposureSurface surface) {
  return switch (surface) {
    McpOpsExposureSurface.builtinTools => _localizedText(
      context,
      zh: '内建工具',
      en: 'Builtin Tools',
    ),
    McpOpsExposureSurface.memory => _localizedText(
      context,
      zh: '记忆',
      en: 'Memory',
    ),
    McpOpsExposureSurface.skills => _localizedText(
      context,
      zh: '技能',
      en: 'Skills',
    ),
    McpOpsExposureSurface.instructions => _localizedText(
      context,
      zh: '指令',
      en: 'Instructions',
    ),
    McpOpsExposureSurface.knowledgeBase => _localizedText(
      context,
      zh: '知识库',
      en: 'Knowledge Base',
    ),
    McpOpsExposureSurface.mcpServers => _localizedText(
      context,
      zh: 'MCP服务',
      en: 'MCP Servers',
    ),
  };
}

IconData _surfaceIcon(McpOpsExposureSurface surface) {
  return switch (surface) {
    McpOpsExposureSurface.builtinTools => Icons.build_circle_rounded,
    McpOpsExposureSurface.memory => Icons.psychology_alt_rounded,
    McpOpsExposureSurface.skills => Icons.extension_rounded,
    McpOpsExposureSurface.instructions => Icons.fact_check_rounded,
    McpOpsExposureSurface.knowledgeBase => Icons.library_books_rounded,
    McpOpsExposureSurface.mcpServers => Icons.hub_rounded,
  };
}

String _networkModeLabel(BuildContext context, McpOpsNetworkMode mode) {
  return switch (mode) {
    McpOpsNetworkMode.loopbackOnly => _localizedText(
      context,
      zh: '仅本机',
      en: 'Loopback',
    ),
    McpOpsNetworkMode.lan => _localizedText(context, zh: '局域网', en: 'LAN'),
    McpOpsNetworkMode.custom => _localizedText(
      context,
      zh: '自定义',
      en: 'Custom',
    ),
  };
}

String _invocationModeLabel(BuildContext context, McpOpsInvocationMode mode) {
  return switch (mode) {
    McpOpsInvocationMode.direct => _localizedText(
      context,
      zh: '直接',
      en: 'Direct',
    ),
    McpOpsInvocationMode.queued => _localizedText(
      context,
      zh: '排队',
      en: 'Queued',
    ),
    McpOpsInvocationMode.guarded => _localizedText(
      context,
      zh: '受控',
      en: 'Guarded',
    ),
  };
}

String _writeModeLabel(BuildContext context, McpOpsWriteMode mode) {
  return switch (mode) {
    McpOpsWriteMode.approvalRequired => _localizedText(
      context,
      zh: '默认审批',
      en: 'Approval',
    ),
    McpOpsWriteMode.fullAccess => _localizedText(
      context,
      zh: '完全访问',
      en: 'Full Access',
    ),
    McpOpsWriteMode.readOnly => _localizedText(
      context,
      zh: '只读',
      en: 'Read Only',
    ),
  };
}

String _invocationModeDescription(
  BuildContext context,
  McpOpsInvocationMode mode,
) {
  return switch (mode) {
    McpOpsInvocationMode.direct => _localizedText(
      context,
      zh: '直接执行不排队',
      en: 'Execute directly without queueing',
    ),
    McpOpsInvocationMode.queued => _localizedText(
      context,
      zh: '排队串行执行',
      en: 'Queue and run serially',
    ),
    McpOpsInvocationMode.guarded => _localizedText(
      context,
      zh: '受控执行含审计',
      en: 'Guarded execution with audit',
    ),
  };
}

String _writeModeDescription(BuildContext context, McpOpsWriteMode mode) {
  return switch (mode) {
    McpOpsWriteMode.approvalRequired => _localizedText(
      context,
      zh: '写操作需人工审批',
      en: 'Writes require manual approval',
    ),
    McpOpsWriteMode.fullAccess => _localizedText(
      context,
      zh: '写操作直接放行',
      en: 'Writes allowed directly',
    ),
    McpOpsWriteMode.readOnly => _localizedText(
      context,
      zh: '仅读禁止写操作',
      en: 'Read only, writes blocked',
    ),
  };
}

String _lifecycleLabel(BuildContext context, McpOpsLifecycleState state) {
  return switch (state) {
    McpOpsLifecycleState.stopped => _localizedText(
      context,
      zh: '已关闭',
      en: 'Stopped',
    ),
    McpOpsLifecycleState.starting => _localizedText(
      context,
      zh: '启动中',
      en: 'Starting',
    ),
    McpOpsLifecycleState.running => _localizedText(
      context,
      zh: '运行中',
      en: 'Running',
    ),
    McpOpsLifecycleState.restarting => _localizedText(
      context,
      zh: '重启中',
      en: 'Restarting',
    ),
    McpOpsLifecycleState.stopping => _localizedText(
      context,
      zh: '关闭中',
      en: 'Stopping',
    ),
    McpOpsLifecycleState.failed => _localizedText(
      context,
      zh: '异常',
      en: 'Failed',
    ),
  };
}

String _mcpOpsAuditStatusLabel(BuildContext context, String status) {
  return switch (status.trim().toLowerCase()) {
    'success' => _localizedText(context, zh: '成功', en: 'Success'),
    'blocked' => _localizedText(context, zh: '已拦截', en: 'Blocked'),
    'failed' => _localizedText(context, zh: '失败', en: 'Failed'),
    _ => status,
  };
}

Color _mcpOpsAuditStatusColor(BuildContext context, McpOpsAuditEntry entry) {
  final cs = Theme.of(context).colorScheme;
  if (entry.errored) return cs.error;
  if (entry.blocked) return OpenHandStatusColors.warning;
  return OpenHandStatusColors.success;
}

/// Human label for an audit event's protocol stage ("环节").
String _mcpOpsAuditKindLabel(BuildContext context, McpOpsAuditKind kind) {
  return switch (kind) {
    McpOpsAuditKind.handshake => _localizedText(context, zh: '握手', en: 'Handshake'),
    McpOpsAuditKind.heartbeat => _localizedText(context, zh: '心跳', en: 'Heartbeat'),
    McpOpsAuditKind.discovery => _localizedText(context, zh: '能力发现', en: 'Discovery'),
    McpOpsAuditKind.invocation => _localizedText(context, zh: '工具调用', en: 'Tool Call'),
    McpOpsAuditKind.stream => _localizedText(context, zh: '事件流', en: 'Event Stream'),
    McpOpsAuditKind.session => _localizedText(context, zh: '会话终止', en: 'Session'),
    McpOpsAuditKind.notification => _localizedText(context, zh: '通知', en: 'Notification'),
    McpOpsAuditKind.other => _localizedText(context, zh: '其他', en: 'Other'),
  };
}

IconData _mcpOpsAuditKindIcon(McpOpsAuditKind kind) {
  return switch (kind) {
    McpOpsAuditKind.handshake => Icons.handshake_rounded,
    McpOpsAuditKind.heartbeat => Icons.favorite_rounded,
    McpOpsAuditKind.discovery => Icons.travel_explore_rounded,
    McpOpsAuditKind.invocation => Icons.bolt_rounded,
    McpOpsAuditKind.stream => Icons.stream_rounded,
    McpOpsAuditKind.session => Icons.link_off_rounded,
    McpOpsAuditKind.notification => Icons.notifications_active_rounded,
    McpOpsAuditKind.other => Icons.more_horiz_rounded,
  };
}

/// A short, human title for a log row: the tool/method name, falling back to a
/// stage label so protocol traffic never renders as a blank headline.
String _mcpOpsAuditTitle(BuildContext context, McpOpsAuditEntry entry) {
  final name = entry.toolName.trim();
  if (name.isNotEmpty) return name;
  return _mcpOpsAuditKindLabel(context, entry.kind);
}

class _McpServerCard extends StatefulWidget {
  const _McpServerCard({
    super.key,
    required this.server,
    required this.healthStatus,
    required this.toolCatalog,
    required this.onTap,
    required this.onToggleEnabled,
    required this.onCheckHealth,
    required this.onRefreshTools,
    required this.onReconnect,
    required this.onActionSelected,
  });

  final McpServer server;
  final McpServerHealth healthStatus;
  final McpToolCatalog toolCatalog;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onCheckHealth;
  final VoidCallback onRefreshTools;
  final VoidCallback onReconnect;
  final ValueChanged<_McpCardAction> onActionSelected;

  @override
  State<_McpServerCard> createState() => _McpServerCardState();
}

class _McpServerCardState extends State<_McpServerCard> {
  McpServer get server => widget.server;
  McpServerHealth get healthStatus => widget.healthStatus;
  McpToolCatalog get toolCatalog => widget.toolCatalog;
  VoidCallback get onTap => widget.onTap;
  ValueChanged<bool> get onToggleEnabled => widget.onToggleEnabled;
  VoidCallback get onCheckHealth => widget.onCheckHealth;
  VoidCallback get onRefreshTools => widget.onRefreshTools;
  VoidCallback get onReconnect => widget.onReconnect;
  ValueChanged<_McpCardAction> get onActionSelected => widget.onActionSelected;

  final _toolSearchController = TextEditingController();
  final _toolSearchFocusNode = FocusNode();
  bool _showToolSearch = false;
  String _toolSearchKeyword = '';

  @override
  void dispose() {
    _toolSearchController.dispose();
    _toolSearchFocusNode.dispose();
    super.dispose();
  }

  void _toggleToolSearch() {
    setState(() {
      _showToolSearch = !_showToolSearch;
      if (!_showToolSearch) {
        _toolSearchController.clear();
        _toolSearchKeyword = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final templateSpecs = TemplateRuntimeDependencyRegistry.specsForMcpText(
      _mcpServerSearchTextForCatalog(server, toolCatalog),
    );

    return HoverLift(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
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
                            alignment: Alignment.center,
                            child: Text(
                              server.initials,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: _McpHealthStatusDot(
                              server: server,
                              healthStatus: healthStatus,
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
                              server.name,
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              server.type.label(l10n),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              server.summary,
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
                          // GestureDetector 吞掉按钮区域的点击事件，
                          // 阻止冒泡到父级 InkWell 触发 onTap（编辑弹窗）。
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {},
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                Tooltip(
                                  message: _localizedText(
                                    context,
                                    zh: '健康检测',
                                    en: 'Health Check',
                                  ),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: IconButton.filledTonal(
                                      onPressed: healthStatus.isChecking
                                          ? null
                                          : onCheckHealth,
                                      icon: healthStatus.isChecking
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                              ),
                                            )
                                          : Icon(
                                              _healthStatusActionIcon(
                                                healthStatus,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message: _localizedText(
                                    context,
                                    zh: '刷新 Tool 检测',
                                    en: 'Refresh Tool Scan',
                                  ),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: IconButton.filledTonal(
                                      onPressed: toolCatalog.isLoading
                                          ? null
                                          : onRefreshTools,
                                      icon: toolCatalog.isLoading
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                              ),
                                            )
                                          : const Icon(Icons.refresh_rounded),
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message: _localizedText(
                                    context,
                                    zh: '一键重连：重新拉取 Tools 并立即健康复测',
                                    en: 'Reconnect: re-scan Tools and re-run health check',
                                  ),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: IconButton.filledTonal(
                                      onPressed: onReconnect,
                                      icon: const Icon(Icons.cyclone_rounded),
                                    ),
                                  ),
                                ),
                                // STDIO 专属按钮：运行/停止、日志、详情
                                if (server.type == McpServerType.stdio)
                                  _StdioProcessButtons(server: server),
                                Tooltip(
                                  message: _showToolSearch
                                      ? _localizedText(
                                          context,
                                          zh: '关闭搜索',
                                          en: 'Close search',
                                        )
                                      : _localizedText(
                                          context,
                                          zh: '搜索 Tool',
                                          en: 'Search tools',
                                        ),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: IconButton.filledTonal(
                                      onPressed: _toggleToolSearch,
                                      icon: Icon(
                                        _showToolSearch
                                            ? Icons.search_off_rounded
                                            : Icons.search_rounded,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child:
                                      AnimatedPopupMenuButton<_McpCardAction>(
                                        tooltip: _localizedText(
                                          context,
                                          zh: '更多操作',
                                          en: 'More actions',
                                        ),
                                        onSelected: onActionSelected,
                                        itemBuilder: (context) {
                                          return [
                                            PopupMenuItem<_McpCardAction>(
                                              value: _McpCardAction.viewDetails,
                                              child: Text(
                                                _localizedText(
                                                  context,
                                                  zh: '服务详情',
                                                  en: 'Server details',
                                                ),
                                              ),
                                            ),
                                            PopupMenuItem<_McpCardAction>(
                                              value: _McpCardAction.viewHistory,
                                              child: Text(
                                                _localizedText(
                                                  context,
                                                  zh: '查看探测历史',
                                                  en: 'View probe history',
                                                ),
                                              ),
                                            ),
                                            PopupMenuItem<_McpCardAction>(
                                              value: _McpCardAction.edit,
                                              child: Text(l10n.commonEdit),
                                            ),
                                            PopupMenuItem<_McpCardAction>(
                                              value: _McpCardAction.delete,
                                              child: Text(l10n.commonDelete),
                                            ),
                                          ];
                                        },
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
                        _McpServerToggleChip(
                          enabled: server.enabled,
                          onPressed: () => onToggleEnabled(!server.enabled),
                        ),
                        for (final spec in templateSpecs)
                          _McpStatusChip(
                            icon: Icons.account_tree_rounded,
                            label: _localizedText(
                              context,
                              zh: spec.labelZh,
                              en: spec.labelEn,
                              zhHant: spec.labelZhHant,
                              fr: spec.labelFr,
                              de: spec.labelDe,
                              ja: spec.labelJa,
                            ),
                          ),
                        // STDIO 进程运行状态 chip
                        if (server.type == McpServerType.stdio)
                          AnimatedBuilder(
                            animation: McpStdioProcessManager.instance,
                            builder: (context, _) {
                              final processInfo = McpStdioProcessManager
                                  .instance
                                  .infoFor(server.name);
                              if (processInfo.isStopped &&
                                  processInfo.errorMessage == null) {
                                return const SizedBox.shrink();
                              }
                              final chipIcon = switch (processInfo.state) {
                                StdioProcessState.running =>
                                  Icons.fiber_manual_record,
                                StdioProcessState.starting =>
                                  Icons.hourglass_top_rounded,
                                StdioProcessState.stopping =>
                                  Icons.hourglass_bottom_rounded,
                                StdioProcessState.stopped =>
                                  Icons.error_outline_rounded,
                              };
                              final chipLabel = switch (processInfo.state) {
                                StdioProcessState.running => _localizedText(
                                  context,
                                  zh: '进程运行中 · PID ${processInfo.pid}',
                                  en: 'Running · PID ${processInfo.pid}',
                                  zhHant: '進程運行中 · PID ${processInfo.pid}',
                                  fr: 'Processus en cours · PID ${processInfo.pid}',
                                  de: 'Prozess läuft · PID ${processInfo.pid}',
                                  ja: 'プロセス実行中 · PID ${processInfo.pid}',
                                ),
                                StdioProcessState.starting => _localizedText(
                                  context,
                                  zh: '进程启动中',
                                  en: 'Starting',
                                ),
                                StdioProcessState.stopping => _localizedText(
                                  context,
                                  zh: '进程停止中',
                                  en: 'Stopping',
                                ),
                                StdioProcessState.stopped => _localizedText(
                                  context,
                                  zh: '进程异常退出',
                                  en: 'Process exited',
                                ),
                              };
                              return _McpStatusChip(
                                icon: chipIcon,
                                label: chipLabel,
                              );
                            },
                          ),
                        if (server.headers.isNotEmpty)
                          _McpStatusChip(
                            icon: Icons.badge_outlined,
                            label: _localizedText(
                              context,
                              zh: '${server.headers.length} 个 Header',
                              en: '${server.headers.length} Headers',
                              zhHant: '${server.headers.length} 個 Header',
                              fr: '${server.headers.length} en-têtes',
                              de: '${server.headers.length} Header',
                              ja: '${server.headers.length} 件のヘッダー',
                            ),
                          ),
                        if (healthStatus.isChecking ||
                            healthStatus.lastCheckedAt != null)
                          _McpStatusChip(
                            icon: _healthStatusChipIcon(healthStatus),
                            label: _healthStatusSummary(context, healthStatus),
                          ),
                        if (healthStatus.latencyMs != null &&
                            healthStatus.isHealthy)
                          _McpStatusChip(
                            icon: Icons.speed_rounded,
                            label: _localizedText(
                              context,
                              zh: '${healthStatus.latencyMs} ms',
                              en: '${healthStatus.latencyMs} ms',
                            ),
                          ),
                        if (healthStatus.lastCheckedAt != null &&
                            !healthStatus.isChecking)
                          _McpStatusChip(
                            icon: Icons.history_toggle_off_rounded,
                            label: _formatRelativePast(
                              context,
                              healthStatus.lastCheckedAt!,
                            ),
                          ),
                        if (healthStatus.needsAttention)
                          _McpAttentionChip(
                            consecutiveFailures:
                                healthStatus.consecutiveFailures,
                          ),
                        if (toolCatalog.isLoading)
                          AnimatedBuilder(
                            animation: mcpStdioBootstrapStatus,
                            builder: (context, _) {
                              final liveLine =
                                  server.type == McpServerType.stdio
                                  ? mcpStdioBootstrapStatus.statusOf(
                                      server.name,
                                    )
                                  : null;
                              final tooltipBase =
                                  server.type == McpServerType.stdio
                                  ? _localizedText(
                                      context,
                                      zh:
                                          '首次启动通常较慢：npx / uvx 需要在线拉取 npm / PyPI 包并安装。\n'
                                          '本应用给 stdio MCP 留最长 6 分钟的发现窗口。',
                                      en:
                                          'First launch is usually slow: npx / uvx '
                                          'pulls npm / PyPI packages on demand. '
                                          'OpenHand grants stdio MCP servers up to '
                                          '6 minutes for discovery.',
                                      zhHant:
                                          '首次啟動通常較慢：npx / uvx 需要在線拉取 npm / PyPI 套件並安裝。\n'
                                          '本應用給 stdio MCP 留最長 6 分鐘的發現視窗。',
                                      fr:
                                          'Le premier lancement est souvent lent : npx / uvx télécharge et installe les paquets npm / PyPI à la demande.\n'
                                          'OpenHand accorde jusqu’à 6 minutes aux serveurs stdio MCP pour la découverte.',
                                      de:
                                          'Der erste Start ist oft langsam: npx / uvx lädt npm- / PyPI-Pakete bei Bedarf herunter und installiert sie.\n'
                                          'OpenHand gibt stdio-MCP-Diensten bis zu 6 Minuten für die Erkennung.',
                                      ja:
                                          '初回起動は通常遅めです。npx / uvx が npm / PyPI パッケージを必要時に取得してインストールします。\n'
                                          'OpenHand は stdio MCP サーバーの検出に最大 6 分を確保します。',
                                    )
                                  : _localizedText(
                                      context,
                                      zh: '正在扫描该 MCP 服务暴露的 Tool 列表。',
                                      en:
                                          'Scanning the tool list exposed by this '
                                          'MCP server.',
                                    );
                              final tooltipMsg =
                                  liveLine != null && liveLine.isNotEmpty
                                  ? '$tooltipBase\n\n$liveLine'
                                  : tooltipBase;
                              // 标签：拿到 stderr 行后切到「首启 · 实时进度」，否则保持初始文案。
                              final label = server.type == McpServerType.stdio
                                  ? (liveLine != null && liveLine.isNotEmpty
                                        ? clipMiddleText(liveLine, maxChars: 36)
                                        : _localizedText(
                                            context,
                                            zh: '首启准备中…',
                                            en: 'Bootstrapping…',
                                          ))
                                  : _localizedText(
                                      context,
                                      zh: '扫描 Tool 中',
                                      en: 'Scanning Tools',
                                    );
                              return Tooltip(
                                message: tooltipMsg,
                                child: _McpStatusChip(
                                  icon: Icons.radar_rounded,
                                  label: label,
                                ),
                              );
                            },
                          )
                        else if (toolCatalog.lastScannedAt != null)
                          _McpStatusChip(
                            icon: Icons.build_circle_outlined,
                            label: _localizedText(
                              context,
                              zh: '${toolCatalog.tools.length} 个 Tool',
                              en: '${toolCatalog.tools.length} Tools',
                              zhHant: '${toolCatalog.tools.length} 個 Tool',
                              fr: '${toolCatalog.tools.length} tools',
                              de: '${toolCatalog.tools.length} Tools',
                              ja: '${toolCatalog.tools.length} 件の Tool',
                            ),
                          ),
                        if (toolCatalog.lastScannedAt != null)
                          _McpStatusChip(
                            icon: Icons.schedule_rounded,
                            label: _formatStatusTime(
                              context,
                              toolCatalog.lastScannedAt!,
                            ),
                          ),
                      ],
                    ),
                  ),
                  OpenHandInlineNoticeSlot(
                    child: healthStatus.hasError
                        ? Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: OpenHandInlineNoticeFactory.error(
                              context,
                              healthStatus.errorMessage!,
                            ),
                          )
                        : null,
                  ),
                  OpenHandInlineNoticeSlot(
                    child: toolCatalog.hasError
                        ? Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: OpenHandInlineNoticeFactory.error(
                              context,
                              toolCatalog.errorMessage!,
                            ),
                          )
                        : null,
                  ),
                  OpenHandInlineNoticeSlot(
                    child: toolCatalog.hasWarning
                        ? Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: OpenHandInlineNoticeFactory.warning(
                              context,
                              toolCatalog.warningMessage!,
                            ),
                          )
                        : null,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInBack,
                    transitionBuilder: (child, animation) {
                      return SizeTransition(
                        sizeFactor: animation,
                        axisAlignment: -1.0,
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: _showToolSearch
                        ? Padding(
                            key: const ValueKey('mcp_tool_search_on'),
                            padding: const EdgeInsets.only(top: 14),
                            child: TextField(
                              controller: _toolSearchController,
                              focusNode: _toolSearchFocusNode,
                              autofocus: true,
                              onChanged: (value) {
                                setState(() {
                                  _toolSearchKeyword = value
                                      .trim()
                                      .toLowerCase();
                                });
                              },
                              decoration: InputDecoration(
                                hintText: _localizedText(
                                  context,
                                  zh: '输入关键字过滤 Tool…',
                                  en: 'Type to filter tools…',
                                ),
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon:
                                    _toolSearchController.text.isNotEmpty
                                    ? GestureDetector(
                                        onTap: () {
                                          _toolSearchController.clear();
                                          setState(() {
                                            _toolSearchKeyword = '';
                                          });
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Icon(
                                            Icons.clear_rounded,
                                            size: 20,
                                          ),
                                        ),
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 16,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('mcp_tool_search_off'),
                          ),
                  ),
                  if (toolCatalog.tools.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _McpToolPreview(
                      server: server,
                      toolCatalog: toolCatalog,
                      searchKeyword: _toolSearchKeyword,
                    ),
                  ] else if (!toolCatalog.isLoading &&
                      !toolCatalog.hasError) ...[
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        server.enabled
                            ? _localizedText(
                                context,
                                zh: '暂未发现可用 Tool，可手动刷新重试。',
                                en: 'No tools were discovered yet. Try refreshing this service.',
                              )
                            : _localizedText(
                                context,
                                zh: '服务已禁用，可手动刷新检测 Tool 信息。',
                                en: 'This service is disabled. Refresh manually to inspect its tools.',
                              ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// STDIO 类型 MCP 服务卡片右上角的专属按钮组：运行/停止、日志、详情。
class _StdioProcessButtons extends StatelessWidget {
  const _StdioProcessButtons({required this.server});

  final McpServer server;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: McpStdioProcessManager.instance,
      builder: (context, _) {
        final info = McpStdioProcessManager.instance.infoFor(server.name);
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            // 运行/停止按钮
            Tooltip(
              message: _localizedText(
                context,
                zh: info.isRunning ? '停止服务' : '启动服务',
                en: info.isRunning ? 'Stop service' : 'Start service',
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: IconButton.filledTonal(
                  onPressed: info.isTransitioning
                      ? null
                      : () {
                          if (info.isRunning) {
                            McpStdioProcessManager.instance.stopServer(
                              server.name,
                            );
                          } else {
                            McpStdioProcessManager.instance.startServer(server);
                          }
                        },
                  style: info.isRunning
                      ? IconButton.styleFrom(
                          backgroundColor: const Color(
                            0xFF16A34A,
                          ).withValues(alpha: 0.15),
                          foregroundColor: const Color(0xFF16A34A),
                        )
                      : null,
                  icon: info.isTransitioning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Icon(
                          info.isRunning
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                        ),
                ),
              ),
            ),
            // 日志按钮
            Tooltip(
              message: _localizedText(context, zh: '查看日志', en: 'View logs'),
              child: SizedBox(
                width: 44,
                height: 44,
                child: IconButton.filledTonal(
                  onPressed: () => showStdioLogDialog(context, server),
                  icon: const Icon(Icons.article_outlined),
                ),
              ),
            ),
            // 运行时详情按钮
            Tooltip(
              message: _localizedText(
                context,
                zh: '运行时详情',
                en: 'Runtime details',
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: IconButton.filledTonal(
                  onPressed: () => showStdioDetailsDialog(context, server),
                  icon: const Icon(Icons.analytics_outlined),
                ),
              ),
            ),
            // 依赖管理按钮（npx / uvx 类型）
            if (_isPackageManagerCommand(server))
              Tooltip(
                message: _localizedText(
                  context,
                  zh: '依赖管理',
                  en: 'Dependencies',
                ),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton.filledTonal(
                    onPressed: () => showStdioDepsDialog(context, server),
                    icon: const Icon(Icons.inventory_2_outlined),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _McpStatusChip extends StatelessWidget {
  const _McpStatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 18),
      backgroundColor: colorScheme.surfaceContainerHighest,
      label: Text(label),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      labelStyle: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: colorScheme.onSurface),
    );
  }
}

/// 当某个 MCP 服务连续探测失败 ≥ 3 次时，在卡片顶部胶囊行展示一枚醒目的警告标签，
/// 引导用户去检查配置或网络。配色走 errorContainer，与下方错误提示框遥相呼应。
class _McpAttentionChip extends StatelessWidget {
  const _McpAttentionChip({required this.consecutiveFailures});

  final int consecutiveFailures;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: _localizedText(
        context,
        zh: '已连续 $consecutiveFailures 次探测失败，建议检查 MCP 服务配置或网络可达性。',
        en: '$consecutiveFailures consecutive probe failures. Please check MCP server configuration or connectivity.',
        zhHant: '已連續 $consecutiveFailures 次探測失敗，建議檢查 MCP 服務配置或網路可達性。',
        fr: '$consecutiveFailures échecs de sonde consécutifs. Vérifiez la configuration du service MCP ou la connectivité.',
        de: '$consecutiveFailures Prüfungen in Folge fehlgeschlagen. Prüfen Sie die MCP-Dienstkonfiguration oder die Verbindung.',
        ja: '$consecutiveFailures 回連続でプローブに失敗しました。MCP サービス設定またはネットワーク到達性を確認してください。',
      ),
      child: Chip(
        avatar: Icon(
          Icons.priority_high_rounded,
          size: 18,
          color: colorScheme.onErrorContainer,
        ),
        backgroundColor: colorScheme.errorContainer,
        labelStyle: TextStyle(color: colorScheme.onErrorContainer),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        label: Text(
          _localizedText(
            context,
            zh: '需要处理 · 连续失败 $consecutiveFailures 次',
            en: 'Needs attention · $consecutiveFailures fails',
            zhHant: '需要處理 · 連續失敗 $consecutiveFailures 次',
            fr: 'À traiter · $consecutiveFailures échecs',
            de: 'Aufmerksamkeit nötig · $consecutiveFailures Fehler',
            ja: '対応が必要 · $consecutiveFailures 回失敗',
          ),
        ),
      ),
    );
  }
}

/// 服务详情抽屉：展示服务配置摘要 + 聚合健康统计 + Tool 数量。
/// 数据来源全部为 controller 既有快照，无独立请求。
class _McpServerDetailsSheet extends StatelessWidget {
  const _McpServerDetailsSheet({
    required this.server,
    required this.health,
    required this.toolCatalog,
    this.onEdit,
  });

  final McpServer server;
  final McpServerHealth health;
  final McpToolCatalog toolCatalog;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final probes = health.recentProbes;
    final successCount = probes
        .where((p) => p.status == McpServerHealthStatus.healthy)
        .length;
    final failureCount = probes.length - successCount;
    final successRate = probes.isEmpty
        ? null
        : (successCount / probes.length * 100).round();
    final latencies = <int>[
      for (final p in probes)
        if (p.status == McpServerHealthStatus.healthy && p.latencyMs != null)
          p.latencyMs!,
    ];
    final avgLatency = latencies.isEmpty
        ? null
        : (latencies.reduce((a, b) => a + b) / latencies.length).round();
    final lastFailure = probes.firstWhere(
      (p) => p.status != McpServerHealthStatus.healthy,
      orElse: () => McpHealthProbeRecord(
        status: McpServerHealthStatus.idle,
        timestamp: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ),
    );
    final lastFailureAt = lastFailure.timestamp.millisecondsSinceEpoch == 0
        ? null
        : lastFailure.timestamp;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: ListView(
        shrinkWrap: true,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizedText(context, zh: '服务详情', en: 'Server details'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      server.name,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                Tooltip(
                  message: _localizedText(
                    context,
                    zh: '跳转到编辑',
                    en: 'Edit configuration',
                  ),
                  child: FilledButton.tonalIcon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(_localizedText(context, zh: '编辑', en: 'Edit')),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _DetailsSection(
            title: _localizedText(context, zh: '配置摘要', en: 'Configuration'),
            children: [
              _DetailsRow(
                label: _localizedText(context, zh: '协议类型', en: 'Protocol'),
                value: server.type.label(AppLocalizations.of(context)!),
              ),
              _DetailsRow(
                label: _localizedText(context, zh: '启用状态', en: 'Enabled'),
                value: server.enabled
                    ? _localizedText(context, zh: '已启用', en: 'Yes')
                    : _localizedText(context, zh: '已停用', en: 'No'),
              ),
              _DetailsRow(
                label: _localizedText(context, zh: '入口', en: 'Endpoint'),
                value: server.summary.isEmpty ? '—' : server.summary,
                multiline: true,
              ),
              if (server.headers.isNotEmpty)
                _DetailsRow(
                  label: _localizedText(
                    context,
                    zh: 'Header 数量',
                    en: 'Headers',
                  ),
                  value: '${server.headers.length}',
                ),
            ],
          ),
          const SizedBox(height: 16),
          _DetailsSection(
            title: _localizedText(context, zh: '健康统计', en: 'Health'),
            children: [
              _DetailsRow(
                label: _localizedText(context, zh: '当前状态', en: 'Status'),
                value: switch (health.status) {
                  McpServerHealthStatus.healthy => _localizedText(
                    context,
                    zh: '健康',
                    en: 'Healthy',
                  ),
                  McpServerHealthStatus.unhealthy => _localizedText(
                    context,
                    zh: '不健康',
                    en: 'Unhealthy',
                  ),
                  McpServerHealthStatus.checking => _localizedText(
                    context,
                    zh: '检测中',
                    en: 'Checking',
                  ),
                  McpServerHealthStatus.idle => _localizedText(
                    context,
                    zh: '尚未探测',
                    en: 'Idle',
                  ),
                },
              ),
              _DetailsRow(
                label: _localizedText(context, zh: '最近成功', en: 'Last success'),
                value: health.lastSuccessAt == null
                    ? '—'
                    : _formatRelativePast(context, health.lastSuccessAt!),
              ),
              _DetailsRow(
                label: _localizedText(context, zh: '最近失败', en: 'Last failure'),
                value: lastFailureAt == null
                    ? '—'
                    : _formatRelativePast(context, lastFailureAt),
              ),
              _DetailsRow(
                label: _localizedText(
                  context,
                  zh: '连续失败',
                  en: 'Consecutive fails',
                ),
                value: '${health.consecutiveFailures}',
              ),
              _DetailsRow(
                label: _localizedText(
                  context,
                  zh: '近期成功率',
                  en: 'Recent success rate',
                ),
                value: successRate == null ? '—' : '$successRate%',
              ),
              _DetailsRow(
                label: _localizedText(
                  context,
                  zh: '平均耗时',
                  en: 'Average latency',
                ),
                value: avgLatency == null ? '—' : '$avgLatency ms',
              ),
              _DetailsRow(
                label: _localizedText(context, zh: '记录样本', en: 'Sample size'),
                value:
                    '${probes.length} '
                    '(${_localizedText(context, zh: '成功 $successCount / 失败 $failureCount', en: '$successCount ok / $failureCount fail', zhHant: '成功 $successCount / 失敗 $failureCount', fr: '$successCount ok / $failureCount échec', de: '$successCount ok / $failureCount fehlgeschlagen', ja: '成功 $successCount / 失敗 $failureCount')})',
              ),
            ],
          ),
          if (probes.length >= 2) ...[
            const SizedBox(height: 16),
            _ProbeTrendSection(probes: probes),
          ],
          const SizedBox(height: 16),
          _DetailsSection(
            title: _localizedText(context, zh: '工具目录', en: 'Tool catalog'),
            children: [
              _DetailsRow(
                label: _localizedText(context, zh: '加载状态', en: 'Status'),
                value: toolCatalog.isLoading
                    ? _localizedText(context, zh: '加载中', en: 'Loading')
                    : (toolCatalog.errorMessage != null
                          ? _localizedText(context, zh: '失败', en: 'Failed')
                          : _localizedText(context, zh: '已加载', en: 'Loaded')),
              ),
              _DetailsRow(
                label: _localizedText(context, zh: 'Tool 数量', en: 'Tool count'),
                value: '${toolCatalog.tools.length}',
              ),
              if (toolCatalog.errorMessage != null)
                _DetailsRow(
                  label: _localizedText(context, zh: '最近错误', en: 'Last error'),
                  value: toolCatalog.errorMessage!,
                  multiline: true,
                ),
            ],
          ),
          if (toolCatalog.tools.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ToolListPreview(tools: toolCatalog.tools),
          ],
        ],
      ),
    );
  }
}

class _ProbeTrendSection extends StatelessWidget {
  const _ProbeTrendSection({required this.probes});

  final List<McpHealthProbeRecord> probes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // 绘制顺序：左旧 → 右新；recentProbes 是倒序，因此反转。
    final ordered = probes.reversed.toList();
    final latencyValues = <int?>[
      for (final probe in ordered)
        probe.status == McpServerHealthStatus.healthy ? probe.latencyMs : null,
    ];
    final hasAnyLatency = latencyValues.any((v) => v != null);
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.show_chart_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _localizedText(context, zh: '探测趋势', en: 'Probe trend'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _localizedText(
                  context,
                  zh: '最近 ${ordered.length} 次',
                  en: 'Last ${ordered.length}',
                  zhHant: '最近 ${ordered.length} 次',
                  fr: '${ordered.length} dernières',
                  de: 'Letzte ${ordered.length}',
                  ja: '直近 ${ordered.length} 回',
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: CustomPaint(
              painter: _ProbeTrendPainter(
                ordered: ordered,
                lineColor: colorScheme.primary,
                fillColor: colorScheme.primary.withValues(alpha: 0.16),
                gridColor: colorScheme.outlineVariant,
                healthyColor: colorScheme.primary,
                failedColor: colorScheme.error,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _LegendDot(color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                _localizedText(context, zh: '健康 (耗时)', en: 'Healthy (latency)'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              _LegendDot(color: colorScheme.error),
              const SizedBox(width: 4),
              Text(
                _localizedText(context, zh: '失败', en: 'Failed'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (!hasAnyLatency) ...[
                const SizedBox(width: 12),
                Text(
                  _localizedText(
                    context,
                    zh: '暂无耗时样本',
                    en: 'No latency samples',
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _ProbeTrendPainter extends CustomPainter {
  _ProbeTrendPainter({
    required this.ordered,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.healthyColor,
    required this.failedColor,
  });

  final List<McpHealthProbeRecord> ordered;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color healthyColor;
  final Color failedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (ordered.isEmpty) return;
    const padding = EdgeInsets.fromLTRB(6, 6, 6, 12);
    final chartLeft = padding.left;
    final chartTop = padding.top;
    final chartWidth = size.width - padding.horizontal;
    final chartHeight = size.height - padding.vertical;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    // 基线（失败/无耗时点的 Y）。
    final baselineY = chartTop + chartHeight;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(chartLeft, baselineY),
      Offset(chartLeft + chartWidth, baselineY),
      gridPaint,
    );

    final healthyLatencies = <int>[
      for (final p in ordered)
        if (p.status == McpServerHealthStatus.healthy && p.latencyMs != null)
          p.latencyMs!,
    ];
    final maxLatency = healthyLatencies.isEmpty
        ? 1
        : healthyLatencies.reduce((a, b) => a > b ? a : b);
    final scaleMax = maxLatency <= 0 ? 1 : maxLatency;

    final n = ordered.length;
    final stepX = n > 1 ? chartWidth / (n - 1) : 0.0;

    final points = <Offset?>[];
    for (var i = 0; i < n; i++) {
      final p = ordered[i];
      if (p.status == McpServerHealthStatus.healthy && p.latencyMs != null) {
        final ratio = unitRatio(p.latencyMs!, scaleMax);
        final x = chartLeft + stepX * i;
        final y = baselineY - ratio * chartHeight;
        points.add(Offset(x, y));
      } else {
        points.add(null);
      }
    }

    // Fill area under healthy segments.
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    Path? currentLine;
    Path? currentFill;
    Offset? lineStart;
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      if (point == null) {
        if (currentLine != null) {
          canvas.drawPath(currentLine, linePaint);
          if (currentFill != null && lineStart != null) {
            currentFill.lineTo(points[i - 1]!.dx, baselineY);
            currentFill.lineTo(lineStart.dx, baselineY);
            currentFill.close();
            canvas.drawPath(currentFill, fillPaint);
          }
        }
        currentLine = null;
        currentFill = null;
        lineStart = null;
        continue;
      }
      if (currentLine == null) {
        currentLine = Path()..moveTo(point.dx, point.dy);
        currentFill = Path()..moveTo(point.dx, point.dy);
        lineStart = point;
      } else {
        currentLine.lineTo(point.dx, point.dy);
        currentFill!.lineTo(point.dx, point.dy);
      }
    }
    if (currentLine != null) {
      canvas.drawPath(currentLine, linePaint);
      if (currentFill != null && lineStart != null) {
        // Find last non-null x in the trailing segment.
        Offset? lastPoint;
        for (var i = points.length - 1; i >= 0; i--) {
          if (points[i] != null) {
            lastPoint = points[i];
            break;
          }
        }
        if (lastPoint != null) {
          currentFill.lineTo(lastPoint.dx, baselineY);
          currentFill.lineTo(lineStart.dx, baselineY);
          currentFill.close();
          canvas.drawPath(currentFill, fillPaint);
        }
      }
    }

    // Draw status dots.
    final healthyDotPaint = Paint()..color = healthyColor;
    final failedDotPaint = Paint()..color = failedColor;
    for (var i = 0; i < n; i++) {
      final p = ordered[i];
      final x = chartLeft + stepX * i;
      if (p.status == McpServerHealthStatus.healthy) {
        final point = points[i];
        if (point != null) {
          canvas.drawCircle(point, 2.4, healthyDotPaint);
        }
      } else {
        canvas.drawCircle(Offset(x, baselineY), 2.6, failedDotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ProbeTrendPainter oldDelegate) {
    return oldDelegate.ordered != ordered ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.healthyColor != healthyColor ||
        oldDelegate.failedColor != failedColor;
  }
}

class _ToolListPreview extends StatelessWidget {
  const _ToolListPreview({required this.tools});

  final List<McpTool> tools;

  static const int _previewLimit = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final preview = tools.take(_previewLimit).toList();
    final overflow = tools.length - preview.length;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _localizedText(context, zh: '工具预览', en: 'Tool preview'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _localizedText(
                  context,
                  zh: '${preview.length}/${tools.length}',
                  en: '${preview.length}/${tools.length}',
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...preview.map((tool) => _ToolPreviewTile(tool: tool)),
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _localizedText(
                  context,
                  zh: '另有 $overflow 个工具未在此列出',
                  en: '$overflow more tools not shown here',
                  zhHant: '另有 $overflow 個工具未在此列出',
                  fr: '$overflow autres tools non affichés ici',
                  de: '$overflow weitere Tools hier nicht angezeigt',
                  ja: 'ほかに $overflow 件の Tool はここに表示されていません',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolPreviewTile extends StatefulWidget {
  const _ToolPreviewTile({required this.tool});

  final McpTool tool;

  @override
  State<_ToolPreviewTile> createState() => _ToolPreviewTileState();
}

class _ToolPreviewTileState extends State<_ToolPreviewTile> {
  bool _expanded = false;

  bool get _hasInputSchema => widget.tool.inputSchema.isNotEmpty;
  bool get _hasOutputSchema => widget.tool.hasOutputSchema;
  bool get _canExpand => _hasInputSchema || _hasOutputSchema;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final description = widget.tool.description.trim();
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.handyman_outlined,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                widget.tool.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  description,
                  maxLines: _expanded ? 6 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_canExpand)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: AnimatedRotation(
              turns: _expanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: _canExpand ? () => setState(() => _expanded = !_expanded) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8, left: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_hasInputSchema)
                              _ToolSchemaBlock(
                                title: _localizedText(
                                  context,
                                  zh: '入参 Schema',
                                  en: 'Input schema',
                                ),
                                payload: widget.tool.inputSchema,
                              ),
                            if (_hasOutputSchema) ...[
                              const SizedBox(height: 8),
                              _ToolSchemaBlock(
                                title: _localizedText(
                                  context,
                                  zh: '出参 Schema',
                                  en: 'Output schema',
                                ),
                                payload:
                                    widget.tool.outputSchema ??
                                    const <String, Object?>{},
                              ),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolSchemaBlock extends StatelessWidget {
  const _ToolSchemaBlock({required this.title, required this.payload});

  final String title;
  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    String pretty;
    try {
      pretty = prettyPrintJson(payload);
    } catch (error, stack) {
      silentLog('mcp', 'render tool schema json', error, stack);
      pretty = payload.toString();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              Tooltip(
                message: _localizedText(context, zh: '复制', en: 'Copy'),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  onPressed: () async {
                    await copyMcpTextToClipboard(
                      context: context,
                      text: pretty,
                      successMessage: _localizedText(
                        context,
                        zh: '已复制 Schema',
                        en: 'Schema copied',
                      ),
                      logAction: 'copy tool schema',
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            pretty,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: colorScheme.onSurface,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _DetailsRow extends StatelessWidget {
  const _DetailsRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value,
              maxLines: multiline ? 6 : 2,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// 「最近探测历史」抽屉：渲染最多 30 条 [McpHealthProbeRecord]，按时间倒序，
/// 健康记录显示绿色对勾 + 耗时，失败记录显示红色叹号 + 截断错误信息（点击可查看完整内容）。
class _McpHealthHistorySheet extends StatelessWidget {
  const _McpHealthHistorySheet({
    required this.serverName,
    required this.health,
  });

  final String serverName;
  final McpServerHealth health;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final probes = health.recentProbes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizedText(
                        context,
                        zh: '最近探测历史',
                        en: 'Recent probe history',
                      ),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      serverName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (probes.isNotEmpty)
                AnimatedPopupMenuButton<_McpHistoryExportFormat>(
                  tooltip: _localizedText(
                    context,
                    zh: '复制探测历史',
                    en: 'Copy probe history',
                  ),
                  icon: const Icon(Icons.copy_all_rounded),
                  onSelected: (format) =>
                      _copyHistoryToClipboard(context, format),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _McpHistoryExportFormat.markdown,
                      child: Text(
                        _localizedText(
                          context,
                          zh: '复制为 Markdown',
                          en: 'Copy as Markdown',
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: _McpHistoryExportFormat.json,
                      child: Text(
                        _localizedText(
                          context,
                          zh: '复制为 JSON',
                          en: 'Copy as JSON',
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: _McpHistoryExportFormat.csv,
                      child: Text(
                        _localizedText(
                          context,
                          zh: '复制为 CSV',
                          en: 'Copy as CSV',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (probes.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              alignment: Alignment.center,
              child: Text(
                _localizedText(
                  context,
                  zh: '尚无探测记录，请先发起一次健康检测或一键重连。',
                  en: 'No probes yet. Run a health check or reconnect to populate this list.',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: probes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final probe = probes[index];
                  return _McpHealthProbeTile(probe: probe);
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _copyHistoryToClipboard(
    BuildContext context,
    _McpHistoryExportFormat format,
  ) async {
    final probes = health.recentProbes;
    final text = switch (format) {
      _McpHistoryExportFormat.markdown => _renderHistoryMarkdown(probes),
      _McpHistoryExportFormat.json => _renderHistoryJson(probes),
      _McpHistoryExportFormat.csv => _renderHistoryCsv(probes),
    };
    final formatLabel = switch (format) {
      _McpHistoryExportFormat.markdown => 'Markdown',
      _McpHistoryExportFormat.json => 'JSON',
      _McpHistoryExportFormat.csv => 'CSV',
    };
    await copyMcpTextToClipboard(
      context: context,
      text: text,
      successMessage: _localizedText(
        context,
        zh: '已将最近 ${probes.length} 条探测记录以 $formatLabel 格式复制到剪贴板',
        en: 'Copied ${probes.length} recent probes as $formatLabel to clipboard',
        zhHant: '已將最近 ${probes.length} 條探測記錄以 $formatLabel 格式複製到剪貼簿',
        fr: '${probes.length} sondes récentes copiées en $formatLabel dans le presse-papiers',
        de: '${probes.length} aktuelle Prüfungen als $formatLabel in die Zwischenablage kopiert',
        ja: '直近 ${probes.length} 件のプローブ記録を $formatLabel としてクリップボードにコピーしました',
      ),
      logAction: 'copy probe history',
    );
  }

  String _renderHistoryMarkdown(List<McpHealthProbeRecord> probes) {
    final buffer = StringBuffer()
      ..writeln('# MCP probe history — $serverName')
      ..writeln();
    for (final probe in probes) {
      final isHealthy = probe.status == McpServerHealthStatus.healthy;
      buffer
        ..write('- ')
        ..write(probe.timestamp.toIso8601String())
        ..write(isHealthy ? ' · healthy' : ' · failed');
      if (probe.latencyMs != null) {
        buffer.write(' · ${probe.latencyMs} ms');
      }
      if (probe.errorMessage != null && probe.errorMessage!.trim().isNotEmpty) {
        final firstLine =
            splitTrimmedNonEmpty(
              probe.errorMessage!,
              separator: '\n',
            ).firstOrNull ??
            '';
        if (firstLine.isNotEmpty) {
          buffer.write(' — $firstLine');
        }
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _renderHistoryJson(List<McpHealthProbeRecord> probes) {
    final payload = {
      'server': serverName,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'probes': [
        for (final probe in probes)
          {
            'timestamp': probe.timestamp.toIso8601String(),
            'status': probe.status == McpServerHealthStatus.healthy
                ? 'healthy'
                : 'failed',
            if (probe.latencyMs != null) 'latencyMs': probe.latencyMs,
            if (probe.errorMessage != null &&
                probe.errorMessage!.trim().isNotEmpty)
              'errorMessage': probe.errorMessage!.trim(),
          },
      ],
    };
    return prettyPrintJson(payload);
  }

  String _renderHistoryCsv(List<McpHealthProbeRecord> probes) {
    final buffer = StringBuffer()..writeln('timestamp,status,latency_ms,error');
    for (final probe in probes) {
      final status = probe.status == McpServerHealthStatus.healthy
          ? 'healthy'
          : 'failed';
      final latency = probe.latencyMs?.toString() ?? '';
      final error = probe.errorMessage == null
          ? ''
          : probe.errorMessage!
                .replaceAll('\r', ' ')
                .replaceAll('\n', ' ')
                .trim();
      buffer.writeln(
        '${_csvCell(probe.timestamp.toIso8601String())},${_csvCell(status)},${_csvCell(latency)},${_csvCell(error)}',
      );
    }
    return buffer.toString();
  }

  String _csvCell(String raw) {
    if (raw.isEmpty) {
      return '';
    }
    final needsQuote =
        raw.contains(',') || raw.contains('"') || raw.contains('\n');
    if (!needsQuote) {
      return raw;
    }
    final escaped = raw.replaceAll('"', '""');
    return '"$escaped"';
  }
}

enum _McpHistoryExportFormat { markdown, json, csv }

class _McpHealthProbeTile extends StatelessWidget {
  const _McpHealthProbeTile({required this.probe});

  final McpHealthProbeRecord probe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isHealthy = probe.status == McpServerHealthStatus.healthy;
    final accentColor = isHealthy ? colorScheme.primary : colorScheme.error;
    final accentSurface = isHealthy
        ? colorScheme.primaryContainer
        : colorScheme.errorContainer;
    final accentOnSurface = isHealthy
        ? colorScheme.onPrimaryContainer
        : colorScheme.onErrorContainer;
    final relative = _formatRelativePast(context, probe.timestamp);
    final latencyText = probe.latencyMs != null
        ? _localizedText(
            context,
            zh: '耗时 ${probe.latencyMs} ms',
            en: '${probe.latencyMs} ms',
            zhHant: '耗時 ${probe.latencyMs} ms',
            fr: '${probe.latencyMs} ms',
            de: '${probe.latencyMs} ms',
            ja: '${probe.latencyMs} ms',
          )
        : null;
    final statusText = isHealthy
        ? _localizedText(context, zh: '健康', en: 'Healthy')
        : _localizedText(context, zh: '失败', en: 'Failed');

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accentSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              isHealthy ? Icons.check_rounded : Icons.priority_high_rounded,
              size: 18,
              color: accentOnSurface,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      statusText,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      relative,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (latencyText != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        latencyText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                if (probe.errorMessage != null &&
                    probe.errorMessage!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    probe.errorMessage!.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
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

class _McpAnimatedProgressBar extends StatelessWidget {
  const _McpAnimatedProgressBar({
    required this.value,
    required this.backgroundColor,
  });

  final double value;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: _mcpMotionDuration(context, const Duration(milliseconds: 520)),
      curve: Curves.easeOutBack,
      builder: (context, animatedProgress, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: clampUnitInterval(animatedProgress),
            backgroundColor: backgroundColor,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MCP 探测详情弹窗
// ─────────────────────────────────────────────────────────────────────────────

class _McpProbeDetailsDialog extends StatelessWidget {
  const _McpProbeDetailsDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: 680,
      maxHeight: 620,
      safeAreaMinimum: kOpenHandDialogDefaultInsetPadding,
      child:
          Selector<
            McpController,
            ({
              List<McpServer> servers,
              int autoProbeConcurrency,
              int activeAutoProbeSlots,
              int queuedAutoProbeTasks,
              bool autoToolRefreshInProgress,
              bool autoHealthCheckInProgress,
              DateTime? lastBatchProbeAt,
              DateTime? nextScheduledProbeAt,
            })
          >(
            selector: (_, c) => (
              servers: c.servers,
              autoProbeConcurrency: c.autoProbeConcurrency,
              activeAutoProbeSlots: c.activeAutoProbeSlots,
              queuedAutoProbeTasks: c.queuedAutoProbeTasks,
              autoToolRefreshInProgress: c.isAutoToolRefreshInProgress,
              autoHealthCheckInProgress: c.isAutoHealthCheckInProgress,
              lastBatchProbeAt: c.lastBatchProbeAt,
              nextScheduledProbeAt: c.nextScheduledProbeAt,
            ),
            builder: (context, snap, _) {
              final controller = context.read<McpController>();
              final hasWork =
                  snap.activeAutoProbeSlots > 0 ||
                  snap.queuedAutoProbeTasks > 0 ||
                  snap.autoToolRefreshInProgress ||
                  snap.autoHealthCheckInProgress;
              final progress = unitRatio(
                snap.activeAutoProbeSlots,
                snap.autoProbeConcurrency,
              );

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 标题栏
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      border: Border(
                        bottom: BorderSide(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: hasWork
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            hasWork
                                ? Icons.radar_rounded
                                : Icons.speed_outlined,
                            color: hasWork
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.mcpProbeDetailsTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                hasWork
                                    ? l10n.mcpProbePoolActive
                                    : l10n.mcpProbePoolIdle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 18),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  // 进度条
                  _McpAnimatedProgressBar(
                    value: progress,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                  // 内容
                  Flexible(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // 探测池状态
                        _ProbeSection(
                          title: l10n.mcpProbePoolStatusTitle,
                          icon: Icons.commit_rounded,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _McpStatusChip(
                                  icon: Icons.commit_rounded,
                                  label: l10n.mcpProbeSlots(
                                    snap.activeAutoProbeSlots,
                                    snap.autoProbeConcurrency,
                                  ),
                                ),
                                _McpStatusChip(
                                  icon: Icons.queue_rounded,
                                  label: l10n.mcpProbeQueued(
                                    snap.queuedAutoProbeTasks,
                                  ),
                                ),
                                _McpStatusChip(
                                  icon: Icons.build_circle_outlined,
                                  label: l10n.mcpProbeToolsStatus(
                                    snap.autoToolRefreshInProgress
                                        ? l10n.mcpProbeStateRunning
                                        : l10n.mcpProbeStateIdle,
                                  ),
                                ),
                                _McpStatusChip(
                                  icon: Icons.health_and_safety_outlined,
                                  label: l10n.mcpProbeHealthStatus(
                                    snap.autoHealthCheckInProgress
                                        ? l10n.mcpProbeStateRunning
                                        : l10n.mcpProbeStateIdle,
                                  ),
                                ),
                                if (snap.lastBatchProbeAt != null)
                                  _McpStatusChip(
                                    icon: Icons.history_rounded,
                                    label: l10n.mcpProbeLastRun(
                                      _formatRelativePast(
                                        context,
                                        snap.lastBatchProbeAt!,
                                      ),
                                    ),
                                  ),
                                if (snap.nextScheduledProbeAt != null &&
                                    !hasWork)
                                  _McpStatusChip(
                                    icon: Icons.schedule_rounded,
                                    label: l10n.mcpProbeNextRun(
                                      _formatRelativeFuture(
                                        context,
                                        snap.nextScheduledProbeAt!,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 探测控制
                        _ProbeSection(
                          title: l10n.mcpProbeControlsTitle,
                          icon: Icons.tune_rounded,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: hasWork
                                      ? null
                                      : () {
                                          // 强制触发：先 deactivate 再 activate 以重置状态
                                          controller.setPageActive(false);
                                          Future.delayed(
                                            _mcpForceProbeResetDelay,
                                            () {
                                              if (!context.mounted) return;
                                              controller.setPageActive(true);
                                            },
                                          );
                                        },
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 18,
                                  ),
                                  label: Text(l10n.mcpProbeForceProbe),
                                ),
                                OutlinedButton.icon(
                                  onPressed: !hasWork
                                      ? null
                                      : () {
                                          // 中断：deactivate 停止所有探测
                                          controller.setPageActive(false);
                                        },
                                  icon: const Icon(
                                    Icons.stop_rounded,
                                    size: 18,
                                  ),
                                  label: Text(l10n.mcpProbeStopProbing),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await controller.refresh();
                                    if (!context.mounted) return;
                                    // refresh 完成后重新激活探测
                                    controller.setPageActive(true);
                                  },
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  label: Text(l10n.mcpProbeReloadServers),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 各服务探测状态
                        _ProbeSection(
                          title: l10n.mcpProbeServerStatusTitle(
                            snap.servers.length,
                          ),
                          icon: Icons.dns_outlined,
                          children: [
                            for (final server in snap.servers)
                              _ProbeServerRow(
                                server: server,
                                controller: controller,
                              ),
                            if (snap.servers.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(
                                  l10n.mcpProbeNoServers,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }
}

class _ProbeSection extends StatelessWidget {
  const _ProbeSection({
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
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
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

class _ProbeServerRow extends StatelessWidget {
  const _ProbeServerRow({required this.server, required this.controller});

  final McpServer server;
  final McpController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final health = controller.healthStatusFor(server.name);
    final catalog = controller.toolCatalogFor(server.name);
    final isBusy = health.isChecking || catalog.isLoading;

    final statusColor = switch (health.status) {
      McpServerHealthStatus.healthy => const Color(0xFF16A34A),
      McpServerHealthStatus.unhealthy => colorScheme.error,
      McpServerHealthStatus.checking => OpenHandStatusColors.warning,
      McpServerHealthStatus.idle => colorScheme.onSurfaceVariant,
    };
    final statusLabel = switch (health.status) {
      McpServerHealthStatus.healthy => l10n.mcpProbeHealthHealthy,
      McpServerHealthStatus.unhealthy => l10n.mcpProbeHealthUnhealthy,
      McpServerHealthStatus.checking => l10n.mcpProbeHealthChecking,
      McpServerHealthStatus.idle => l10n.mcpProbeHealthIdle,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // 启用/禁用探测开关
          SizedBox(
            width: 28,
            height: 28,
            child: Tooltip(
              message: server.probeEnabled
                  ? l10n.mcpProbeDisableServerTooltip
                  : l10n.mcpProbeEnableServerTooltip,
              child: IconButton(
                onPressed: () => controller.updateServerProbeEnabled(
                  server.name,
                  !server.probeEnabled,
                ),
                icon: Icon(
                  server.probeEnabled
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  size: 14,
                  color: server.probeEnabled
                      ? const Color(0xFF16A34A)
                      : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: server.probeEnabled
                  ? statusColor
                  : colorScheme.outlineVariant,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              server.name,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: server.probeEnabled
                    ? null
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            server.probeEnabled ? statusLabel : l10n.mcpProbeNoProbe,
            style: theme.textTheme.labelSmall?.copyWith(
              color: server.probeEnabled
                  ? statusColor
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (catalog.tools.isNotEmpty && server.probeEnabled) ...[
            const SizedBox(width: 8),
            Text(
              l10n.mcpProbeToolCount(catalog.tools.length),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(width: 8),
          // 单独触发该服务的探测（禁用态或探测中时不可点击）
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              onPressed: !server.probeEnabled || isBusy
                  ? null
                  : () => controller.reconnectServer(server.name),
              icon: Icon(
                Icons.refresh_rounded,
                size: 14,
                color: !server.probeEnabled || isBusy
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.3)
                    : null,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              tooltip: l10n.mcpProbeThisServer,
            ),
          ),
        ],
      ),
    );
  }
}

/// 失败热点筛选栏：两枚等尺寸动作按钮，窄屏自动换成一行一个。

class _McpServerToggleChip extends StatelessWidget {
  const _McpServerToggleChip({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabledBg = colorScheme.primaryContainer;
    final disabledBg = colorScheme.surfaceContainerHighest;
    final enabledFg = colorScheme.onPrimaryContainer;
    final disabledFg = colorScheme.onSurfaceVariant;
    final enabledBorder = colorScheme.primary.withValues(alpha: 0.28);
    final disabledBorder = colorScheme.outlineVariant;

    return Tooltip(
      message: enabled
          ? _localizedText(context, zh: '点击停用', en: 'Click to Disable')
          : _localizedText(context, zh: '点击启用', en: 'Click to Enable'),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: enabled ? 1.0 : 0.0),
        duration: _mcpMotionDuration(
          context,
          const Duration(milliseconds: 220),
        ),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) {
          final backgroundColor = Color.lerp(disabledBg, enabledBg, t)!;
          final foregroundColor = Color.lerp(disabledFg, enabledFg, t)!;
          final borderColor = Color.lerp(disabledBorder, enabledBorder, t)!;
          return ActionChip(
            avatar: Icon(
              enabled
                  ? Icons.check_circle_outline_rounded
                  : Icons.pause_circle_outline_rounded,
              size: 18,
              color: foregroundColor,
            ),
            label: Text(
              enabled
                  ? AppLocalizations.of(context)!.mcpServerStatusEnabled
                  : AppLocalizations.of(context)!.mcpServerStatusDisabled,
            ),
            onPressed: onPressed,
            backgroundColor: backgroundColor,
            side: BorderSide(color: borderColor),
            shape: const StadiumBorder(),
            labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}

class _McpHealthStatusDot extends StatelessWidget {
  const _McpHealthStatusDot({required this.server, required this.healthStatus});

  final McpServer server;
  final McpServerHealth healthStatus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dotColor = _healthStatusDotColor(
      colorScheme,
      server: server,
      healthStatus: healthStatus,
    );

    return Tooltip(
      message: _healthStatusDotTooltip(context, server, healthStatus),
      child: AnimatedContainer(
        duration: _mcpMotionDuration(
          context,
          const Duration(milliseconds: 180),
        ),
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: dotColor,
          shape: BoxShape.circle,
          border: Border.all(color: colorScheme.surface, width: 3),
          boxShadow: openHandTickerMotionEnabled(context)
              ? [
                  BoxShadow(
                    color: dotColor.withValues(alpha: 0.32),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

class _McpToolPreview extends StatefulWidget {
  const _McpToolPreview({
    required this.server,
    required this.toolCatalog,
    this.searchKeyword = '',
  });

  final McpServer server;
  final McpToolCatalog toolCatalog;
  final String searchKeyword;

  @override
  State<_McpToolPreview> createState() => _McpToolPreviewState();
}

class _McpToolPreviewState extends State<_McpToolPreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyword = widget.searchKeyword;
    final allTools = widget.toolCatalog.tools;
    final filteredTools = keyword.isEmpty
        ? allTools
        : allTools
              .where((t) => t.name.toLowerCase().contains(keyword))
              .toList(growable: false);
    final showAll =
        _expanded || filteredTools.length <= _mcpToolPreviewCollapsedLimit;
    final previewTools = showAll
        ? filteredTools
        : filteredTools
              .take(_mcpToolPreviewCollapsedLimit)
              .toList(growable: false);
    final hiddenToolCount = showAll
        ? 0
        : filteredTools.length - previewTools.length;
    final canExpand = filteredTools.length > _mcpToolPreviewCollapsedLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                keyword.isEmpty
                    ? _localizedText(
                        context,
                        zh: '可用 Tools',
                        en: 'Available Tools',
                      )
                    : _localizedText(
                        context,
                        zh: '匹配 "${widget.searchKeyword}" 的 Tool',
                        en: 'Tools matching "${widget.searchKeyword}"',
                        zhHant: '匹配 "${widget.searchKeyword}" 的 Tool',
                        fr: 'Tools correspondant à "${widget.searchKeyword}"',
                        de: 'Tools passend zu "${widget.searchKeyword}"',
                        ja: '"${widget.searchKeyword}" に一致する Tool',
                      ),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (canExpand)
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: _mcpMotionDuration(
                    context,
                    _mcpToolPreviewExpandDuration,
                  ),
                  curve: Curves.easeOutCubic,
                  child: const Icon(Icons.expand_more_rounded),
                ),
                label: Text(
                  _expanded
                      ? _localizedText(context, zh: '收起', en: 'Collapse')
                      : _localizedText(context, zh: '展开', en: 'Expand'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (filteredTools.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _localizedText(
                context,
                zh: '没有匹配的 Tool',
                en: 'No matching tools',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          AnimatedSize(
            duration: _mcpMotionDuration(
              context,
              _mcpToolPreviewExpandDuration,
            ),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final tool in previewTools)
                    ActionChip(
                      avatar: Icon(
                        tool.hasMetadataWarning
                            ? Icons.warning_amber_rounded
                            : Icons.build_circle_outlined,
                        size: 18,
                      ),
                      label: Text(tool.name),
                      onPressed: () {
                        _showToolDetailsDialog(
                          context,
                          mcpController: context.read<McpController>(),
                          server: widget.server,
                          toolCatalog: widget.toolCatalog,
                          tool: tool,
                        );
                      },
                    ),
                  if (hiddenToolCount > 0)
                    Chip(
                      avatar: const Icon(Icons.more_horiz_rounded),
                      label: Text(
                        _localizedText(
                          context,
                          zh: '还有 $hiddenToolCount 个',
                          en: '+$hiddenToolCount more',
                          zhHant: '還有 $hiddenToolCount 個',
                          fr: '+$hiddenToolCount autres',
                          de: '+$hiddenToolCount weitere',
                          ja: 'ほか $hiddenToolCount 件',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

void _showToolDetailsDialog(
  BuildContext context, {
  required McpController mcpController,
  required McpServer server,
  required McpToolCatalog toolCatalog,
  required McpTool tool,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _McpToolDetailsDialog(
      mcpController: mcpController,
      server: server,
      toolCatalog: toolCatalog,
      tool: tool,
    ),
  );
}

void _showToolDebugDialog(
  BuildContext context, {
  required McpController mcpController,
  required McpServer server,
  required McpToolCatalog toolCatalog,
  McpTool? initialTool,
}) {
  showAnimatedDialog<void>(
    context: context,
    builder: (dialogContext) => _McpToolDebugDialog(
      mcpController: mcpController,
      server: server,
      toolCatalog: toolCatalog,
      initialTool: initialTool,
    ),
  );
}

class _McpToolDetailsDialog extends StatelessWidget {
  const _McpToolDetailsDialog({
    required this.mcpController,
    required this.server,
    required this.toolCatalog,
    required this.tool,
  });

  final McpController mcpController;
  final McpServer server;
  final McpToolCatalog toolCatalog;
  final McpTool tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final inputSchemaMetadata = _displayedSchemaMetadata(
      rawSchema: tool.rawInputSchema,
      normalizedSchema: tool.inputSchema,
      hasRawMetadata: tool.hasRawMetadata,
    );
    final outputSchemaMetadata = _displayedSchemaMetadata(
      rawSchema: tool.rawOutputSchema,
      normalizedSchema: tool.outputSchema,
      hasRawMetadata: tool.hasRawMetadata,
    );
    final inputFields = _schemaFields(inputSchemaMetadata);
    final outputFields = _schemaFields(outputSchemaMetadata);
    final outputDescription = tool.outputDescription?.trim() ?? '';

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: 860,
      maxHeight: 760,
      safeAreaMinimum: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tool.name, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      SelectableText(
                        '${_localizedText(context, zh: 'Tool ID', en: 'Tool ID')}: ${tool.id}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  key: ValueKey<String>('mcpToolDetailsDebugButton-${tool.id}'),
                  tooltip: _localizedText(
                    context,
                    zh: '调试 Tool',
                    en: 'Debug Tool',
                  ),
                  onPressed: () => _showToolDebugDialog(
                    context,
                    mcpController: mcpController,
                    server: server,
                    toolCatalog: toolCatalog,
                    initialTool: tool,
                  ),
                  icon: const Icon(Icons.play_circle_outline_rounded),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (tool.description.trim().isNotEmpty) ...[
                      _ToolDescriptionPanel(description: tool.description),
                      const SizedBox(height: 14),
                    ],
                    if (tool.hasMetadataWarning) ...[
                      OpenHandInlineNoticeFactory.warning(
                        context,
                        tool.metadataWarning!,
                      ),
                      const SizedBox(height: 14),
                    ],
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _ToolMetaTile(
                          label: _localizedText(
                            context,
                            zh: '入參信息',
                            en: 'Input Metadata',
                          ),
                          value: _schemaSummary(
                            context,
                            rawSchema: inputSchemaMetadata,
                            fields: inputFields,
                          ),
                        ),
                        _ToolMetaTile(
                          label: _localizedText(
                            context,
                            zh: '返回信息',
                            en: 'Output Metadata',
                          ),
                          value: _schemaSummary(
                            context,
                            rawSchema: outputSchemaMetadata,
                            fields: outputFields,
                            description: outputDescription,
                          ),
                        ),
                        _ToolMetaTile(
                          label: _localizedText(
                            context,
                            zh: '执行能力',
                            en: 'Execution',
                          ),
                          value: _executionSummary(context, tool),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _ToolSchemaSection(
                      title: _localizedText(
                        context,
                        zh: '入參',
                        en: 'Parameters',
                      ),
                      fields: inputFields,
                      schema: inputSchemaMetadata,
                      emptyLabel: _localizedText(
                        context,
                        zh: '该 Tool 未声明结构化入參字段。',
                        en: 'This tool does not declare structured input fields.',
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (outputDescription.isNotEmpty) ...[
                      _ToolTextSection(
                        title: _localizedText(
                          context,
                          zh: '返回说明',
                          en: 'Return Description',
                        ),
                        body: outputDescription,
                        caption: tool.outputDescriptionIsInferred
                            ? _localizedText(
                                context,
                                zh: '基于 Tool 描述推断',
                                en: 'Derived from the tool description',
                              )
                            : null,
                      ),
                      const SizedBox(height: 20),
                    ],
                    _ToolSchemaSection(
                      title: _localizedText(
                        context,
                        zh: '返回值',
                        en: 'Return Value',
                      ),
                      fields: outputFields,
                      schema: outputSchemaMetadata,
                      emptyLabel: outputSchemaMetadata == null
                          ? outputDescription.isNotEmpty
                                ? _localizedText(
                                    context,
                                    zh: '该 Tool 未声明结构化返回值 Schema。',
                                    en: 'This tool does not declare a structured output schema.',
                                  )
                                : _localizedText(
                                    context,
                                    zh: '该 Tool 未声明返回值 Schema。',
                                    en: 'This tool does not declare an output schema.',
                                  )
                          : _localizedText(
                              context,
                              zh: '返回值 Schema 未提供结构化字段。',
                              en: 'The output schema does not expose structured fields.',
                            ),
                    ),
                    if (tool.hasMetadataWarning && tool.hasRawMetadata) ...[
                      const SizedBox(height: 20),
                      Text(
                        _localizedText(
                          context,
                          zh: '服务端原始元数据',
                          en: 'Raw Server Metadata',
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      _ToolSchemaPanel(schema: tool.rawMetadata),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _McpToolDebugDialog extends StatefulWidget {
  const _McpToolDebugDialog({
    required this.mcpController,
    required this.server,
    required this.toolCatalog,
    this.initialTool,
  });

  final McpController mcpController;
  final McpServer server;
  final McpToolCatalog toolCatalog;
  final McpTool? initialTool;

  @override
  State<_McpToolDebugDialog> createState() => _McpToolDebugDialogState();
}

class _McpToolDebugDialogState extends State<_McpToolDebugDialog> {
  late McpTool? _selectedTool;
  late final TextEditingController _argumentsController;
  late final List<_EditableHeaderRow> _headerRows;
  final GlobalKey _toolMenuAnchorKey = GlobalKey();
  bool _useServerHeaders = true;
  McpToolCallResult? _result;
  String? _errorMessage;
  String? _headerErrorMessage;
  bool _isRunning = false;
  bool _toolMenuOpen = false;

  @override
  void initState() {
    super.initState();
    _selectedTool =
        widget.initialTool ??
        (widget.toolCatalog.tools.isEmpty
            ? null
            : widget.toolCatalog.tools.first);
    _argumentsController = TextEditingController(
      text: _selectedTool == null
          ? '{}'
          : _suggestedArgumentsJson(_selectedTool!),
    );
    _headerRows = _buildInitialHeaderRows(widget.server.headers);
  }

  @override
  void dispose() {
    _argumentsController.dispose();
    for (final row in _headerRows) {
      row.dispose();
    }
    super.dispose();
  }

  List<_EditableHeaderRow> _buildInitialHeaderRows(
    Map<String, String>? headers,
  ) {
    final entries = headers?.entries.toList(growable: false) ?? const [];
    if (entries.isEmpty) {
      return <_EditableHeaderRow>[_EditableHeaderRow()];
    }
    return entries
        .map((entry) => _EditableHeaderRow(name: entry.key, value: entry.value))
        .toList();
  }

  void _addHeaderRow() {
    setState(() {
      _headerRows.add(_EditableHeaderRow());
      _headerErrorMessage = null;
    });
  }

  void _removeHeaderRow(int index) {
    setState(() {
      _headerErrorMessage = null;
      if (_headerRows.length == 1) {
        _headerRows.single.clear();
        return;
      }
      final removedRow = _headerRows.removeAt(index);
      removedRow.dispose();
    });
  }

  void _clearHeaderError() {
    if (_headerErrorMessage == null) {
      return;
    }
    setState(() {
      _headerErrorMessage = null;
    });
  }

  _HeaderParseResult _collectHeadersFromRows() {
    final headers = <String, String>{};
    final seenNames = <String>{};
    for (var index = 0; index < _headerRows.length; index++) {
      final row = _headerRows[index];
      final name = row.nameController.text.trim();
      final value = row.valueController.text.trim();
      if (name.isEmpty && value.isEmpty) {
        continue;
      }
      if (name.isEmpty || value.isEmpty) {
        return _HeaderParseResult(
          headers: const <String, String>{},
          errorMessage: _localizedText(
            context,
            zh: '第 ${index + 1} 个 Header 的名称和值都不能为空',
            en: 'Header ${index + 1} must include both name and value',
            zhHant: '第 ${index + 1} 個 Header 的名稱和值都不能為空',
            fr: 'L’en-tête ${index + 1} doit inclure un nom et une valeur',
            de: 'Header ${index + 1} muss sowohl Name als auch Wert enthalten',
            ja: 'ヘッダー ${index + 1} には名前と値の両方が必要です',
          ),
        );
      }
      final normalizedName = name.toLowerCase();
      if (!seenNames.add(normalizedName)) {
        return _HeaderParseResult(
          headers: const <String, String>{},
          errorMessage: _localizedText(
            context,
            zh: '第 ${index + 1} 个 Header 名称重复',
            en: 'Header ${index + 1} uses a duplicate name',
            zhHant: '第 ${index + 1} 個 Header 名稱重複',
            fr: 'L’en-tête ${index + 1} utilise un nom en double',
            de: 'Header ${index + 1} verwendet einen doppelten Namen',
            ja: 'ヘッダー ${index + 1} の名前が重複しています',
          ),
        );
      }
      headers[name] = value;
    }
    return _HeaderParseResult(
      headers: Map<String, String>.unmodifiable(headers),
    );
  }

  McpTool? _toolForId(String toolId) {
    for (final item in widget.toolCatalog.tools) {
      if (item.id == toolId) {
        return item;
      }
    }
    return null;
  }

  void _applySelectedTool(McpTool tool) {
    _selectedTool = tool;
    _result = null;
    _errorMessage = null;
    _headerErrorMessage = null;
    _argumentsController.text = _suggestedArgumentsJson(tool);
  }

  Future<void> _showToolMenu() async {
    if (_isRunning || _toolMenuOpen || widget.toolCatalog.tools.isEmpty) {
      return;
    }
    final anchorContext = _toolMenuAnchorKey.currentContext;
    final overlayState = Navigator.of(context).overlay;
    if (anchorContext == null || overlayState == null) {
      return;
    }
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
    if (anchorBox == null ||
        overlayBox == null ||
        !anchorBox.attached ||
        !overlayBox.attached) {
      return;
    }

    final anchorOffset = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(
        anchorOffset.dx,
        anchorOffset.dy + anchorBox.size.height + _mcpToolDebugMenuGap,
        anchorBox.size.width,
        0,
      ),
      Offset.zero & overlayBox.size,
    );
    final minWidth = anchorBox.size.width
        .clamp(_mcpToolDebugMenuMinWidth, _mcpToolDebugMenuMaxWidth)
        .toDouble();
    final selectedToolId = _selectedTool?.id;

    setState(() {
      _toolMenuOpen = true;
    });

    String? nextToolId;
    try {
      nextToolId = await showAnimatedMenu<String>(
        context: context,
        position: position,
        initialValue: selectedToolId,
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: _mcpToolDebugMenuMaxWidth,
          maxHeight: _mcpToolDebugMenuMaxHeight,
        ),
        enableBidirectionalScroll: true,
        items: [
          for (final item in widget.toolCatalog.tools)
            PopupMenuItem<String>(
              key: ValueKey<String>('mcpToolDebugMenuItem-${item.id}'),
              value: item.id,
              padding: EdgeInsets.zero,
              child: _McpToolDebugMenuItem(
                label: item.name,
                selected: item.id == selectedToolId,
                hasWarning: item.hasMetadataWarning,
              ),
            ),
        ],
      );
    } finally {
      if (mounted) {
        setState(() {
          _toolMenuOpen = false;
        });
      }
    }

    if (!mounted || nextToolId == null || nextToolId == selectedToolId) {
      return;
    }
    final nextTool = _toolForId(nextToolId);
    if (nextTool == null) {
      return;
    }
    setState(() {
      _applySelectedTool(nextTool);
    });
  }

  Future<void> _runTool() async {
    final tool = _selectedTool;
    if (tool == null || _isRunning) {
      return;
    }

    Map<String, Object?> arguments;
    final rawArguments = _argumentsController.text.trim();
    try {
      if (rawArguments.isEmpty) {
        arguments = const <String, Object?>{};
      } else {
        final decoded = jsonDecode(rawArguments);
        if (decoded is! Map) {
          throw const FormatException('root-not-object');
        }
        arguments = stringKeyedMapFromValue(decoded);
      }
    } catch (_) {
      setState(() {
        _result = null;
        _errorMessage = _localizedText(
          context,
          zh: '参数必须是合法的 JSON 对象。',
          en: 'Arguments must be a valid JSON object.',
        );
      });
      return;
    }

    // 仅对 HTTP/SSE 类型服务处理自定义 headers
    Map<String, String>? customHeaders;
    if (widget.server.type == McpServerType.streamableHttp ||
        widget.server.type == McpServerType.sse) {
      if (!_useServerHeaders) {
        final headerParseResult = _collectHeadersFromRows();
        if (headerParseResult.errorMessage != null) {
          setState(() {
            _headerErrorMessage = headerParseResult.errorMessage;
          });
          return;
        }
        customHeaders = headerParseResult.headers;
      }
    }

    setState(() {
      _isRunning = true;
      _result = null;
      _errorMessage = null;
      _headerErrorMessage = null;
    });

    try {
      final result = await widget.mcpController.callTool(
        serverName: widget.server.name,
        toolName: tool.id,
        arguments: arguments,
        customHeaders: customHeaders,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Widget _buildHeaderConfigSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final headers = widget.server.headers;
    final headersEmpty = headers.isEmpty;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_rounded, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _localizedText(
                      context,
                      zh: '请求 Header 配置',
                      en: 'Request Headers',
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                if (headersEmpty)
                  _McpStatusChip(
                    icon: Icons.info_outline_rounded,
                    label: _localizedText(context, zh: '未配置', en: 'None'),
                  )
                else
                  _McpStatusChip(
                    icon: Icons.layers_outlined,
                    label: _localizedText(
                      context,
                      zh: '${headers.length} 个',
                      en: '${headers.length}',
                      zhHant: '${headers.length} 個',
                      fr: '${headers.length}',
                      de: '${headers.length}',
                      ja: '${headers.length} 件',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _localizedText(
                context,
                zh: '可复用 MCP 服务配置的 Header，或手动配置调试专用 Header。',
                en: 'Reuse server headers or configure custom headers for debugging.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _localizedText(
                      context,
                      zh: '复用服务 Header',
                      en: 'Use server headers',
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Switch(
                  value: _useServerHeaders,
                  onChanged: _isRunning
                      ? null
                      : (value) {
                          setState(() {
                            _useServerHeaders = value;
                            _headerErrorMessage = null;
                          });
                        },
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1.0,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: !_useServerHeaders
                  ? Padding(
                      key: const ValueKey('custom-headers'),
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Divider(height: 1, color: colorScheme.outlineVariant),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _localizedText(
                                    context,
                                    zh: '自定义 Header',
                                    en: 'Custom Headers',
                                  ),
                                  style: theme.textTheme.labelLarge,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _isRunning ? null : _addHeaderRow,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: Text(
                                  _localizedText(context, zh: '新增', en: 'Add'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Column(
                            children: _headerRows
                                .asMap()
                                .entries
                                .map((entry) {
                                  final index = entry.key;
                                  final row = entry.value;
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom: index == _headerRows.length - 1
                                          ? 0
                                          : 10,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: row.nameController,
                                            enabled: !_isRunning,
                                            onChanged: (_) =>
                                                _clearHeaderError(),
                                            decoration: InputDecoration(
                                              isDense: true,
                                              labelText: _localizedText(
                                                context,
                                                zh: '名称',
                                                en: 'Name',
                                              ),
                                              hintText: _localizedText(
                                                context,
                                                zh: 'Authorization',
                                                en: 'Authorization',
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          flex: 2,
                                          child: TextField(
                                            controller: row.valueController,
                                            enabled: !_isRunning,
                                            onChanged: (_) =>
                                                _clearHeaderError(),
                                            decoration: InputDecoration(
                                              isDense: true,
                                              labelText: _localizedText(
                                                context,
                                                zh: '值',
                                                en: 'Value',
                                              ),
                                              hintText: _localizedText(
                                                context,
                                                zh: 'Bearer token',
                                                en: 'Bearer token',
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        IconButton(
                                          onPressed: _isRunning
                                              ? null
                                              : () => _removeHeaderRow(index),
                                          tooltip: _localizedText(
                                            context,
                                            zh: '删除',
                                            en: 'Remove',
                                          ),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                })
                                .toList(growable: false),
                          ),
                          if (_headerErrorMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _headerErrorMessage!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('use-server-headers')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tool = _selectedTool;
    final inputSchemaMetadata = tool == null
        ? null
        : _displayedSchemaMetadata(
            rawSchema: tool.rawInputSchema,
            normalizedSchema: tool.inputSchema,
            hasRawMetadata: tool.hasRawMetadata,
          );
    final inputFields = tool == null
        ? const <_SchemaField>[]
        : _schemaFields(inputSchemaMetadata);

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: 920,
      maxHeight: 820,
      safeAreaMinimum: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _localizedText(
                          context,
                          zh: '调试 MCP Tool',
                          en: 'Debug MCP Tool',
                        ),
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${widget.server.name} · ${widget.server.type.label(AppLocalizations.of(context)!)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (tool == null)
              Expanded(
                child: Center(
                  child: Text(
                    _localizedText(
                      context,
                      zh: '当前服务还没有可调试的 Tool，请先刷新 Tool 列表。',
                      en: 'No tools are available for debugging yet. Refresh the tool list first.',
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey<String>(
                            'mcpToolDebugToolField-${tool.id}',
                          ),
                          onTap: _isRunning ? null : _showToolMenu,
                          borderRadius: BorderRadius.circular(18),
                          child: InputDecorator(
                            key: _toolMenuAnchorKey,
                            isFocused: _toolMenuOpen,
                            isEmpty: tool.name.trim().isEmpty,
                            decoration: InputDecoration(
                              labelText: _localizedText(
                                context,
                                zh: '选择 Tool',
                                en: 'Tool',
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              suffixIcon: Icon(
                                _toolMenuOpen
                                    ? Icons.arrow_drop_up_rounded
                                    : Icons.arrow_drop_down_rounded,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  tool.hasMetadataWarning
                                      ? Icons.warning_amber_rounded
                                      : Icons.build_circle_outlined,
                                  size: 18,
                                  color: tool.hasMetadataWarning
                                      ? colorScheme.error
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tool.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (tool.description.trim().isNotEmpty) ...[
                        _ToolDescriptionPanel(description: tool.description),
                        const SizedBox(height: 14),
                      ],
                      Text(
                        _localizedText(
                          context,
                          zh: '参数 JSON',
                          en: 'Arguments JSON',
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey<String>(
                          'mcpToolDebugArgumentsField',
                        ),
                        controller: _argumentsController,
                        minLines: 8,
                        maxLines: 16,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          hintText: _localizedText(
                            context,
                            zh: '请输入 JSON 对象，例如 {"page": 1}',
                            en: 'Enter a JSON object, for example {"page": 1}',
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (widget.server.type == McpServerType.streamableHttp ||
                          widget.server.type == McpServerType.sse)
                        _buildHeaderConfigSection(context),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OpenHandDialogActionButton.primary(
                            key: const ValueKey<String>(
                              'mcpToolDebugRunButton',
                            ),
                            onPressed: _isRunning ? null : _runTool,
                            icon: Icons.play_arrow_rounded,
                            busy: _isRunning,
                            label: _isRunning
                                ? _localizedText(
                                    context,
                                    zh: '执行中',
                                    en: 'Running',
                                  )
                                : _localizedText(
                                    context,
                                    zh: '执行 Tool',
                                    en: 'Run Tool',
                                  ),
                          ),
                          OpenHandDialogActionButton.secondary(
                            onPressed: _isRunning
                                ? null
                                : () {
                                    setState(() {
                                      _argumentsController.text =
                                          _suggestedArgumentsJson(tool);
                                    });
                                  },
                            icon: Icons.restart_alt_rounded,
                            label: _localizedText(
                              context,
                              zh: '恢复示例参数',
                              en: 'Reset Sample',
                            ),
                          ),
                        ],
                      ),
                      OpenHandInlineNoticeSlot(
                        child: _errorMessage != null
                            ? Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: OpenHandInlineNoticeFactory.error(
                                  context,
                                  _errorMessage!,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _localizedText(
                          context,
                          zh: '参数参考',
                          en: 'Parameter Reference',
                        ),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      if (inputFields.isEmpty)
                        Text(
                          _localizedText(
                            context,
                            zh: '该 Tool 未声明结构化参数字段。',
                            en: 'This tool does not declare structured input fields.',
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        Column(
                          children: inputFields
                              .map(
                                (field) => _ToolSchemaFieldCard(field: field),
                              )
                              .toList(growable: false),
                        ),
                      if (inputSchemaMetadata != null) ...[
                        const SizedBox(height: 12),
                        _ToolSchemaPanel(schema: inputSchemaMetadata),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        _localizedText(context, zh: '执行结果', en: 'Result'),
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      if (_result == null &&
                          _errorMessage == null &&
                          !_isRunning)
                        Text(
                          _localizedText(
                            context,
                            zh: '执行后会在这里展示原始返回结果。',
                            en: 'The raw tool result will appear here after execution.',
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      else if (_result != null) ...[
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _McpStatusChip(
                              icon: _result!.isError
                                  ? Icons.error_outline_rounded
                                  : Icons.check_circle_outline_rounded,
                              label: _result!.isError
                                  ? _localizedText(
                                      context,
                                      zh: '服务端返回错误',
                                      en: 'Server Returned Error',
                                    )
                                  : _localizedText(
                                      context,
                                      zh: '执行成功',
                                      en: 'Succeeded',
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _McpFormattedResultPanel(result: _result!),
                      ] else if (_isRunning)
                        _ToolConsolePanel(
                          content: _localizedText(
                            context,
                            zh: '正在等待 MCP 服务返回结果...',
                            en: 'Waiting for the MCP service to return a result...',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _McpToolDebugMenuItem extends StatelessWidget {
  const _McpToolDebugMenuItem({
    required this.label,
    required this.selected,
    required this.hasWarning,
  });

  final String label;
  final bool selected;
  final bool hasWarning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foregroundColor = selected
        ? colorScheme.primary
        : hasWarning
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _mcpToolDebugMenuItemInset,
        vertical: 4,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.42)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(_mcpToolDebugMenuItemRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : hasWarning
                  ? Icons.warning_amber_rounded
                  : Icons.build_circle_outlined,
              size: 18,
              color: foregroundColor,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              softWrap: false,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected ? colorScheme.onSurface : null,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolMetaTile extends StatelessWidget {
  const _ToolMetaTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _ToolDescriptionPanel extends StatelessWidget {
  const _ToolDescriptionPanel({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final styleSheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(
        color: colorScheme.onSurfaceVariant,
        height: 1.45,
      ),
      listBullet: theme.textTheme.bodyLarge?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      strong: theme.textTheme.bodyLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurface,
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      blockquoteDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: MarkdownBody(
        data: description,
        selectable: true,
        softLineBreak: true,
        styleSheet: styleSheet,
      ),
    );
  }
}

class _ToolTextSection extends StatelessWidget {
  const _ToolTextSection({
    required this.title,
    required this.body,
    this.caption,
  });

  final String title;
  final String body;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        if (caption?.trim().isNotEmpty ?? false) ...[
          const SizedBox(height: 4),
          Text(
            caption!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        _ToolDescriptionPanel(description: body),
      ],
    );
  }
}

class _ToolSchemaSection extends StatelessWidget {
  const _ToolSchemaSection({
    required this.title,
    required this.fields,
    required this.schema,
    required this.emptyLabel,
  });

  final String title;
  final List<_SchemaField> fields;
  final Object? schema;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (fields.isEmpty)
          Text(
            emptyLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Column(
            children: fields
                .map((field) => _ToolSchemaFieldCard(field: field))
                .toList(growable: false),
          ),
        if (schema != null) ...[
          const SizedBox(height: 12),
          _ToolSchemaPanel(schema: schema),
        ],
      ],
    );
  }
}

class _ToolSchemaFieldCard extends StatelessWidget {
  const _ToolSchemaFieldCard({required this.field});

  final _SchemaField field;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SelectableText(
                field.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _McpStatusChip(icon: Icons.code_rounded, label: field.type),
              if (field.required)
                _McpStatusChip(
                  icon: Icons.priority_high_rounded,
                  label: _localizedText(context, zh: '必填', en: 'Required'),
                ),
            ],
          ),
          if (field.description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              field.description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolSchemaPanel extends StatelessWidget {
  const _ToolSchemaPanel({required this.schema});

  final Object? schema;

  @override
  Widget build(BuildContext context) {
    final content = prettyPrintJson(_jsonFriendlyValue(schema));
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontFamily: 'monospace',
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

/// 内容超过该阈值时，将格式化工作转移到后台 isolate 执行，避免阻塞 UI。
const int _kAsyncFormatThreshold = 50 * kBytesPerKiB;

/// 展示内容的最大长度，超出部分截断并标注。
const int _kMaxDisplaySize = 500 * kBytesPerKiB;

/// 超出该大小的原始响应直接放弃格式化，仅展示截断后的原始文本。
const int _kSkipFormatThreshold = 5 * kBytesPerMiB;

/// 从 MCP tool call 结果中提取实际响应文本，剥离 MCP 协议信封
/// (`content` / `type` / `text` 包装层)。
String _extractMcpContentForDisplay(McpToolCallResult result) {
  final raw = result.rawResult;
  if (raw is! Map<String, Object?>) {
    return result.outputText;
  }
  final content = raw['content'];
  if (content is! List || content.isEmpty) {
    return result.outputText;
  }
  final texts = <String>[];
  for (final item in content) {
    if (item is Map<String, Object?>) {
      final type = item['type'];
      if (type == 'text') {
        final text = item['text'];
        if (text is String && text.isNotEmpty) {
          texts.add(text);
        }
      } else if (type == 'image') {
        texts.add('[image: ${item['mimeType'] ?? 'unknown'}]');
      } else if (type == 'resource' || type == 'resource_link') {
        texts.add('[resource: ${item['uri'] ?? 'unknown'}]');
      }
    }
  }
  if (texts.isEmpty) {
    return result.outputText;
  }
  return texts.join('\n');
}

class _McpFormattedResultPanel extends StatefulWidget {
  const _McpFormattedResultPanel({required this.result});

  final McpToolCallResult result;

  @override
  State<_McpFormattedResultPanel> createState() =>
      _McpFormattedResultPanelState();
}

class _McpFormattedResultPanelState extends State<_McpFormattedResultPanel> {
  String? _displayText;
  String? _formatBadge;
  String? _truncationNote;
  bool _isFormatting = false;

  @override
  void initState() {
    super.initState();
    _processResult();
  }

  @override
  void didUpdateWidget(covariant _McpFormattedResultPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result != widget.result) {
      _processResult();
    }
  }

  Future<void> _processResult() async {
    final rawText = _extractMcpContentForDisplay(widget.result);

    // 超大响应直接跳过格式化，截断展示原始文本
    if (rawText.length > _kSkipFormatThreshold) {
      _applyDisplay(
        rawText.substring(0, _kMaxDisplaySize),
        null,
        _kTruncationNote(rawText.length),
      );
      return;
    }

    // 小内容同步格式化，即时展示
    if (rawText.length <= _kAsyncFormatThreshold) {
      final formatted = formatStructuredTextForDisplay(rawText);
      final (display, truncated) = _capDisplay(formatted.text);
      _applyDisplay(
        display,
        _formatBadgeLabel(formatted),
        truncated ? _kTruncationNote(formatted.text.length) : null,
      );
      return;
    }

    // 大内容切到 isolate 格式化，避免卡 UI
    if (!mounted) return;
    setState(() => _isFormatting = true);

    final formattedMap = await Isolate.run(
      () => formatStructuredTextForDisplay(rawText).toMap(),
    );
    if (!mounted) return;

    final formatted = StructuredTextFormatResult.fromMap(formattedMap);
    final (display, truncated) = _capDisplay(formatted.text);
    _applyDisplay(
      display,
      _formatBadgeLabel(formatted),
      truncated ? _kTruncationNote(formatted.text.length) : null,
    );
  }

  void _applyDisplay(String text, String? badge, String? truncation) {
    if (!mounted) return;
    setState(() {
      _displayText = text;
      _formatBadge = badge;
      _truncationNote = truncation;
      _isFormatting = false;
    });
  }

  static (String, bool) _capDisplay(String text) {
    if (text.length <= _kMaxDisplaySize) return (text, false);
    return (text.substring(0, _kMaxDisplaySize), true);
  }

  static String _kTruncationNote(int fullLength) {
    final kb = (fullLength / kBytesPerKiB).toStringAsFixed(1);
    return '（内容已截断，原始大小约 $kb KB）';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_formatBadge != null || _truncationNote != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (_formatBadge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _formatBadge!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  if (_truncationNote != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _truncationNote!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (_isFormatting)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            )
          else if (_displayText != null)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                _displayText!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String? _formatBadgeLabel(StructuredTextFormatResult result) {
  final format = result.format;
  return format == null ? null : structuredTextFormatLabel(format);
}

class _ToolConsolePanel extends StatelessWidget {
  const _ToolConsolePanel({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontFamily: 'monospace',
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _SchemaField {
  const _SchemaField({
    required this.name,
    required this.type,
    required this.description,
    required this.required,
  });

  final String name;
  final String type;
  final String description;
  final bool required;
}

class _McpPersistenceIssueCard extends StatelessWidget {
  const _McpPersistenceIssueCard({
    required this.issue,
    required this.onDismiss,
  });

  final McpPersistenceIssue issue;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final shortPath = OpenHandPaths.shortenHomePath(issue.filePath);
    final (title, body) = switch (issue.kind) {
      McpPersistenceIssueKind.recoveredInvalidFile => (
        l10n.mcpPersistenceRecoveredTitle,
        '${l10n.mcpPersistenceRecoveredBody}\n$shortPath',
      ),
      McpPersistenceIssueKind.sanitizedInvalidContent => (
        l10n.mcpPersistenceSanitizedTitle,
        '${l10n.mcpPersistenceSanitizedBody}\n$shortPath',
      ),
      McpPersistenceIssueKind.saveFailed => (
        l10n.mcpPersistenceSaveFailedTitle,
        '${l10n.mcpPersistenceSaveFailedBody}\n$shortPath',
      ),
    };

    return PersistenceIssueCard(
      title: title,
      body: body,
      dismissLabel: l10n.settingsPersistenceDismiss,
      onDismiss: onDismiss,
    );
  }
}

List<_SchemaField> _schemaFields(Object? schema) {
  final fields = <_SchemaField>[];
  final seenNames = <String>{};

  void addField(_SchemaField field) {
    if (seenNames.add(field.name)) {
      fields.add(field);
    }
  }

  final schemaMap = _asMap(schema);
  if (schemaMap != null) {
    _collectSchemaFields(schemaMap, addField);
  }
  if (fields.isNotEmpty) {
    return fields;
  }
  if (schema is List) {
    for (final item in schema) {
      final field = _descriptorField(item);
      if (field != null) {
        addField(field);
      }
    }
  }
  return fields;
}

void _collectSchemaFields(
  Map<String, Object?> schema,
  void Function(_SchemaField field) addField, {
  String prefix = '',
}) {
  final properties = _asMap(schema['properties']);
  if (properties != null && properties.isNotEmpty) {
    final requiredFields = _requiredFieldNames(schema['required']);
    for (final entry in properties.entries) {
      final propertySchema = entry.value;
      final propertyName = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      addField(
        _SchemaField(
          name: propertyName,
          type: _schemaType(propertySchema),
          description: _schemaDescription(propertySchema),
          required: requiredFields.contains(entry.key),
        ),
      );
    }
  }

  for (final collectionKey in const <String>['fields', 'parameters']) {
    final collection = schema[collectionKey];
    if (collection is! List) {
      continue;
    }
    for (final item in collection) {
      final field = _descriptorField(item, prefix: prefix);
      if (field != null) {
        addField(field);
      }
    }
  }

  for (final keyword in const <String>['oneOf', 'anyOf', 'allOf']) {
    final variants = schema[keyword];
    if (variants is! List) {
      continue;
    }
    for (final variant in variants) {
      final variantMap = _asMap(variant);
      if (variantMap != null) {
        _collectSchemaFields(variantMap, addField, prefix: prefix);
      }
    }
  }

  final items = schema['items'];
  final itemPrefix = prefix.isEmpty ? 'item' : '$prefix.item';
  if (items is List) {
    for (final item in items) {
      final field = _descriptorField(item, prefix: itemPrefix);
      if (field != null) {
        addField(field);
      }
      final itemMap = _asMap(item);
      if (itemMap != null) {
        _collectSchemaFields(itemMap, addField, prefix: itemPrefix);
      }
    }
    return;
  }
  final itemMap = _asMap(items);
  if (itemMap != null) {
    _collectSchemaFields(itemMap, addField, prefix: itemPrefix);
  }
}

Set<String> _requiredFieldNames(Object? rawRequired) {
  final requiredFields = <String>{};
  if (rawRequired is List) {
    for (final item in rawRequired) {
      final name = '$item'.trim();
      if (name.isNotEmpty) {
        requiredFields.add(name);
      }
    }
  }
  return requiredFields;
}

_SchemaField? _descriptorField(Object? value, {String prefix = ''}) {
  final descriptor = _asMap(value);
  if (descriptor == null) {
    return null;
  }
  final fieldName =
      _firstNonEmptyText(descriptor, const <String>[
        'name',
        'key',
        'id',
        'title',
      ]) ??
      '';
  if (fieldName.isEmpty) {
    return null;
  }
  final schema = descriptor.containsKey('schema')
      ? descriptor['schema']
      : descriptor;
  return _SchemaField(
    name: prefix.isEmpty ? fieldName : '$prefix.$fieldName',
    type: _schemaType(schema),
    description:
        _firstNonEmptyText(descriptor, const <String>[
          'description',
          'summary',
          'title',
        ]) ??
        '',
    required: _readBoolFlag(descriptor['required']),
  );
}

String _schemaType(Object? schema) {
  final schemaMap = _asMap(schema);
  if (schemaMap == null) {
    if (schema is List) {
      return 'array';
    }
    if (schema is bool) {
      return 'boolean';
    }
    if (schema is num) {
      return 'number';
    }
    if (schema is String) {
      final text = schema.trim();
      return text.isEmpty ? 'text' : text;
    }
    return 'object';
  }
  final typeValue = schemaMap['type'];
  if (typeValue is String && typeValue.trim().isNotEmpty) {
    return typeValue.trim();
  }
  if (typeValue is List) {
    final values = stringListFromValue(typeValue);
    if (values.isNotEmpty) {
      return values.join(' | ');
    }
  }
  final enumValues = schemaMap['enum'];
  if (enumValues is List && enumValues.isNotEmpty) {
    return 'enum';
  }
  for (final keyword in const <String>['oneOf', 'anyOf', 'allOf']) {
    final variants = schemaMap[keyword];
    if (variants is! List || variants.isEmpty) {
      continue;
    }
    final variantTypes = trimmedNonEmptyStrings(
      variants.map(_schemaType),
    ).toSet().toList(growable: false);
    if (variantTypes.isNotEmpty) {
      return variantTypes.join(' | ');
    }
  }
  if (schemaMap.containsKey('items')) {
    return 'array';
  }
  if (_asMap(schemaMap['properties']) != null) {
    return 'object';
  }
  return 'object';
}

String _schemaDescription(Object? schema) {
  final schemaMap = _asMap(schema);
  if (schemaMap == null) {
    return '';
  }
  return _firstNonEmptyText(schemaMap, const <String>[
        'description',
        'summary',
      ]) ??
      '';
}

String _schemaSummary(
  BuildContext context, {
  required Object? rawSchema,
  required List<_SchemaField> fields,
  String description = '',
}) {
  if (rawSchema == null) {
    if (description.trim().isNotEmpty) {
      return _localizedText(context, zh: '已描述', en: 'Described');
    }
    return _localizedText(context, zh: '未声明', en: 'Unspecified');
  }
  if (fields.isNotEmpty) {
    return _localizedText(
      context,
      zh: '${fields.length} 个字段',
      en: '${fields.length} fields',
      zhHant: '${fields.length} 個欄位',
      fr: '${fields.length} champs',
      de: '${fields.length} Felder',
      ja: '${fields.length} 個のフィールド',
    );
  }
  final type = _schemaType(rawSchema).toLowerCase();
  if (type == 'array') {
    return _localizedText(context, zh: '数组', en: 'Array');
  }
  if (type == 'string' || type == 'text') {
    return _localizedText(context, zh: '文本', en: 'Text');
  }
  if (type == 'number' || type == 'integer') {
    return _localizedText(context, zh: '数字', en: 'Number');
  }
  if (type == 'boolean') {
    return _localizedText(context, zh: '布尔值', en: 'Boolean');
  }
  if (type == 'enum') {
    return _localizedText(context, zh: '枚举', en: 'Enum');
  }
  return _localizedText(context, zh: '原始元数据', en: 'Raw Metadata');
}

String _suggestedArgumentsJson(McpTool tool) {
  final schemaMap = _asMap(tool.inputSchema);
  final properties = schemaMap == null ? null : _asMap(schemaMap['properties']);
  if (properties == null || properties.isEmpty) {
    return '{}';
  }
  final suggested = <String, Object?>{};
  for (final entry in properties.entries) {
    suggested[entry.key] = _schemaExampleValue(entry.value);
  }
  return prettyPrintJson(suggested);
}

Object? _schemaExampleValue(Object? schema) {
  final schemaMap = _asMap(schema);
  if (schemaMap == null) {
    return '';
  }
  final enumValues = schemaMap['enum'];
  if (enumValues is List && enumValues.isNotEmpty) {
    return _jsonFriendlyValue(enumValues.first);
  }
  final type = _schemaType(schemaMap).toLowerCase();
  return switch (type) {
    'boolean' => false,
    'number' || 'integer' => 0,
    'array' => <Object?>[],
    'object' => <String, Object?>{},
    _ => '',
  };
}

String _executionSummary(BuildContext context, McpTool tool) {
  final taskSupport = _readText(tool.execution['taskSupport']);
  if (taskSupport.isEmpty) {
    return _localizedText(context, zh: '默认', en: 'Default');
  }
  return taskSupport;
}

String _formatStatusTime(BuildContext context, DateTime timestamp) {
  final formatted = formatMonthDayHm(timestamp.toLocal());
  return _localizedText(context, zh: formatted, en: formatted);
}

IconData _healthStatusActionIcon(McpServerHealth healthStatus) {
  return switch (healthStatus.status) {
    McpServerHealthStatus.healthy => Icons.health_and_safety_rounded,
    McpServerHealthStatus.unhealthy => Icons.health_and_safety_outlined,
    McpServerHealthStatus.idle ||
    McpServerHealthStatus.checking => Icons.health_and_safety_outlined,
  };
}

IconData _healthStatusChipIcon(McpServerHealth healthStatus) {
  return switch (healthStatus.status) {
    McpServerHealthStatus.healthy => Icons.verified_rounded,
    McpServerHealthStatus.unhealthy => Icons.error_outline_rounded,
    McpServerHealthStatus.idle ||
    McpServerHealthStatus.checking => Icons.health_and_safety_outlined,
  };
}

String _healthStatusSummary(
  BuildContext context,
  McpServerHealth healthStatus,
) {
  if (healthStatus.isChecking) {
    return _localizedText(context, zh: '健康检测中', en: 'Checking Health');
  }
  final checkedAt = healthStatus.lastCheckedAt;
  if (checkedAt == null) {
    return _localizedText(context, zh: '未检测', en: 'Unchecked');
  }
  final statusLabel = healthStatus.isHealthy
      ? _localizedText(context, zh: '健康', en: 'Healthy')
      : _localizedText(context, zh: '异常', en: 'Unhealthy');
  return '$statusLabel · ${_formatStatusTime(context, checkedAt)}';
}

Color _healthStatusDotColor(
  ColorScheme colorScheme, {
  required McpServer server,
  required McpServerHealth healthStatus,
}) {
  if (!server.enabled) {
    return colorScheme.outlineVariant;
  }
  return switch (healthStatus.status) {
    McpServerHealthStatus.healthy => const Color(0xFF56C271),
    McpServerHealthStatus.unhealthy => colorScheme.error,
    McpServerHealthStatus.checking => colorScheme.tertiary,
    McpServerHealthStatus.idle => colorScheme.outline,
  };
}

String _healthStatusDotTooltip(
  BuildContext context,
  McpServer server,
  McpServerHealth healthStatus,
) {
  if (!server.enabled) {
    return _localizedText(context, zh: '服务已禁用', en: 'Service Disabled');
  }
  if (healthStatus.isChecking) {
    return _localizedText(context, zh: '健康检测中', en: 'Checking Health');
  }
  final checkedAt = healthStatus.lastCheckedAt;
  if (checkedAt == null) {
    return _localizedText(context, zh: '尚未检测健康状态', en: 'Health Not Checked');
  }
  final statusLabel = healthStatus.isHealthy
      ? _localizedText(context, zh: '服务健康', en: 'Service Healthy')
      : _localizedText(context, zh: '服务异常', en: 'Service Unhealthy');
  return '$statusLabel · ${_formatStatusTime(context, checkedAt)}';
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return stringKeyedMapFromValue(value);
  }
  return null;
}

/// Deep equality for two JSON-shaped maps via canonical encoding. Used to tell
/// an edited builtin-tool schema apart from its factory default.
bool _mcpJsonEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) return true;
  try {
    return jsonEncode(_jsonFriendlyValue(a)) == jsonEncode(_jsonFriendlyValue(b));
  } catch (_) {
    return false;
  }
}

Object? _jsonFriendlyValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return value.map(_jsonFriendlyValue).toList(growable: false);
  }
  if (value is Map) {
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      normalized['${entry.key}'] = _jsonFriendlyValue(entry.value);
    }
    return normalized;
  }
  return '$value';
}

Object? _displayedSchemaMetadata({
  required Object? rawSchema,
  required Object? normalizedSchema,
  required bool hasRawMetadata,
}) {
  if (rawSchema != null) {
    return rawSchema;
  }
  if (hasRawMetadata) {
    return null;
  }
  return normalizedSchema;
}

bool _readBoolFlag(Object? value) {
  return boolFromValue(value);
}

String? _firstNonEmptyText(Map<String, Object?> source, List<String> keys) {
  for (final key in keys) {
    final value = _readText(source[key]);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

String _readText(Object? value) {
  final text = '$value'.trim();
  if (text == 'null') {
    return '';
  }
  return text;
}

String _localizedText(
  BuildContext context, {
  required String zh,
  required String en,
  String? zhHans,
  String? zhHant,
  String? fr,
  String? de,
  String? ja,
}) {
  final fallback = _mcpLocalizedFallbacks[en];
  return openHandLocalizedText(
    context,
    zh: zh,
    en: en,
    zhHans: zhHans,
    zhHant: zhHant ?? fallback?.zhHant,
    fr: fr ?? fallback?.fr,
    de: de ?? fallback?.de,
    ja: ja ?? fallback?.ja,
  );
}

class _McpLocalizedFallback {
  const _McpLocalizedFallback({
    required this.zhHant,
    required this.fr,
    required this.de,
    required this.ja,
  });

  final String zhHant;
  final String fr;
  final String de;
  final String ja;
}

const Map<String, _McpLocalizedFallback>
_mcpLocalizedFallbacks = <String, _McpLocalizedFallback>{
  'MCP Server Operations': _McpLocalizedFallback(
    zhHant: 'MCP 伺服器運維',
    fr: 'Opérations du serveur MCP',
    de: 'MCP-Serverbetrieb',
    ja: 'MCP サーバー運用',
  ),
  'MCP Server': _McpLocalizedFallback(
    zhHant: 'MCP 伺服器',
    fr: 'Serveur MCP',
    de: 'MCP-Server',
    ja: 'MCP サーバー',
  ),
  'Ops': _McpLocalizedFallback(
    zhHant: '運維面板',
    fr: 'Exploitation',
    de: 'Betrieb',
    ja: '運用',
  ),
  'Config': _McpLocalizedFallback(
    zhHant: '參數配置',
    fr: 'Configuration',
    de: 'Konfiguration',
    ja: '設定',
  ),
  'Audit': _McpLocalizedFallback(
    zhHant: '日誌審計',
    fr: 'Audit',
    de: 'Audit',
    ja: '監査',
  ),
  'No audit logs': _McpLocalizedFallback(
    zhHant: '暫無調用日誌',
    fr: 'Aucun journal d’appel',
    de: 'Keine Aufruflogs',
    ja: '呼び出しログはありません',
  ),
  'External MCP calls will stream into this audit list.': _McpLocalizedFallback(
    zhHant: '外部 MCP 客戶端發起調用後，會在這裡即時滾動輸出審計記錄。',
    fr: 'Les appels MCP externes s’affichent ici en continu.',
    de: 'Externe MCP-Aufrufe erscheinen fortlaufend in dieser Auditliste.',
    ja: '外部 MCP クライアントの呼び出しはここに流れます。',
  ),
  'Details': _McpLocalizedFallback(
    zhHant: '詳情',
    fr: 'Détails',
    de: 'Details',
    ja: '詳細',
  ),
  'Audit Details': _McpLocalizedFallback(
    zhHant: '審計詳情',
    fr: 'Détails d’audit',
    de: 'Auditdetails',
    ja: '監査詳細',
  ),
  'Audit Overview': _McpLocalizedFallback(
    zhHant: '審計概覽',
    fr: 'Vue d’ensemble de l’audit',
    de: 'Auditübersicht',
    ja: '監査概要',
  ),
  'Total Logs': _McpLocalizedFallback(
    zhHant: '日誌總數',
    fr: 'Total des journaux',
    de: 'Logs gesamt',
    ja: 'ログ総数',
  ),
  'Rolling window': _McpLocalizedFallback(
    zhHant: '滾動窗口',
    fr: 'Fenêtre glissante',
    de: 'Rollierendes Fenster',
    ja: 'ローリングウィンドウ',
  ),
  'Environment': _McpLocalizedFallback(
    zhHant: '環境資訊',
    fr: 'Environnement',
    de: 'Umgebung',
    ja: '環境',
  ),
  'Success': _McpLocalizedFallback(
    zhHant: '成功',
    fr: 'Succès',
    de: 'Erfolg',
    ja: '成功',
  ),
  'Failures': _McpLocalizedFallback(
    zhHant: '失敗數量',
    fr: 'Échecs',
    de: 'Fehler',
    ja: '失敗数',
  ),
  'ID': _McpLocalizedFallback(zhHant: '日誌 ID', fr: 'ID', de: 'ID', ja: 'ID'),
  'Surface': _McpLocalizedFallback(
    zhHant: '暴露面',
    fr: 'Surface',
    de: 'Oberfläche',
    ja: '公開面',
  ),
  'Time': _McpLocalizedFallback(
    zhHant: '請求時間',
    fr: 'Heure',
    de: 'Zeit',
    ja: '時刻',
  ),
  'Client': _McpLocalizedFallback(
    zhHant: '來源客戶端',
    fr: 'Client',
    de: 'Client',
    ja: 'クライアント',
  ),
  'Model': _McpLocalizedFallback(
    zhHant: '模型',
    fr: 'Modèle',
    de: 'Modell',
    ja: 'モデル',
  ),
  'Duration': _McpLocalizedFallback(
    zhHant: '調用耗時',
    fr: 'Durée',
    de: 'Dauer',
    ja: '所要時間',
  ),
  'Tokens': _McpLocalizedFallback(
    zhHant: 'Token 數',
    fr: 'Tokens',
    de: 'Tokens',
    ja: 'トークン数',
  ),
  'Traffic': _McpLocalizedFallback(
    zhHant: '進出口流量',
    fr: 'Trafic',
    de: 'Traffic',
    ja: 'トラフィック',
  ),
  'Request': _McpLocalizedFallback(
    zhHant: '請求資訊',
    fr: 'Requête',
    de: 'Anfrage',
    ja: 'リクエスト',
  ),
  'Response': _McpLocalizedFallback(
    zhHant: '響應資訊',
    fr: 'Réponse',
    de: 'Antwort',
    ja: 'レスポンス',
  ),
  'Connections': _McpLocalizedFallback(
    zhHant: '當前連線數',
    fr: 'Connexions',
    de: 'Verbindungen',
    ja: '接続数',
  ),
  'Live sessions': _McpLocalizedFallback(
    zhHant: '即時會話',
    fr: 'Sessions actives',
    de: 'Live-Sitzungen',
    ja: 'ライブセッション',
  ),
  'In flight': _McpLocalizedFallback(
    zhHant: '執行中',
    fr: 'En cours',
    de: 'In Ausführung',
    ja: '処理中',
  ),
  'Inbound': _McpLocalizedFallback(
    zhHant: '入口流量',
    fr: 'Entrant',
    de: 'Eingehend',
    ja: '受信',
  ),
  'Outbound': _McpLocalizedFallback(
    zhHant: '出口流量',
    fr: 'Sortant',
    de: 'Ausgehend',
    ja: '送信',
  ),
  'Request bytes': _McpLocalizedFallback(
    zhHant: '請求體',
    fr: 'Octets de requête',
    de: 'Anfragebytes',
    ja: 'リクエストバイト',
  ),
  'Response bytes': _McpLocalizedFallback(
    zhHant: '響應體',
    fr: 'Octets de réponse',
    de: 'Antwortbytes',
    ja: 'レスポンスバイト',
  ),
  'Latency': _McpLocalizedFallback(
    zhHant: '調用耗時',
    fr: 'Latence',
    de: 'Latenz',
    ja: 'レイテンシ',
  ),
  'Allowed Time': _McpLocalizedFallback(
    zhHant: '允許時間',
    fr: 'Période autorisée',
    de: 'Erlaubte Zeit',
    ja: '許可時間',
  ),
  'Local time': _McpLocalizedFallback(
    zhHant: '本地時區',
    fr: 'Heure locale',
    de: 'Lokale Zeit',
    ja: 'ローカル時刻',
  ),
  'Memory': _McpLocalizedFallback(
    zhHant: '記憶',
    fr: 'Mémoire',
    de: 'Speicher',
    ja: 'メモリ',
  ),
  'Current RSS': _McpLocalizedFallback(
    zhHant: '當前 RSS',
    fr: 'RSS actuel',
    de: 'Aktueller RSS',
    ja: '現在の RSS',
  ),
  'MCP Count': _McpLocalizedFallback(
    zhHant: 'MCP 數量',
    fr: 'Nombre de MCP',
    de: 'MCP-Anzahl',
    ja: 'MCP 数',
  ),
  'Registered': _McpLocalizedFallback(
    zhHant: '已註冊服務',
    fr: 'Enregistrés',
    de: 'Registriert',
    ja: '登録済み',
  ),
  'Mutations': _McpLocalizedFallback(
    zhHant: '檔案變動',
    fr: 'Mutations',
    de: 'Änderungen',
    ja: '変更',
  ),
  'Write calls': _McpLocalizedFallback(
    zhHant: '寫工具成功',
    fr: 'Écritures réussies',
    de: 'Schreibaufrufe',
    ja: '書き込み呼び出し',
  ),
  'Audit Logs': _McpLocalizedFallback(
    zhHant: '審計日誌',
    fr: 'Journaux d’audit',
    de: 'Audit-Logs',
    ja: '監査ログ',
  ),
  'Rolling kept': _McpLocalizedFallback(
    zhHant: '滾動保留',
    fr: 'Conservation glissante',
    de: 'Rollierend behalten',
    ja: 'ローテーション保持',
  ),
  'Unlimited': _McpLocalizedFallback(
    zhHant: '不限流',
    fr: 'Illimité',
    de: 'Unbegrenzt',
    ja: '無制限',
  ),
  'Access Policy': _McpLocalizedFallback(
    zhHant: '訪問策略',
    fr: 'Politique d’accès',
    de: 'Zugriffsrichtlinie',
    ja: 'アクセス方針',
  ),
  'Token auth': _McpLocalizedFallback(
    zhHant: '令牌校驗',
    fr: 'Jeton requis',
    de: 'Tokenprüfung',
    ja: 'トークン認証',
  ),
  'No token': _McpLocalizedFallback(
    zhHant: '無令牌',
    fr: 'Sans jeton',
    de: 'Kein Token',
    ja: 'トークンなし',
  ),
  'Request Trend': _McpLocalizedFallback(
    zhHant: '請求趨勢',
    fr: 'Tendance des requêtes',
    de: 'Anfragetrend',
    ja: 'リクエスト推移',
  ),
  'Latency Curve': _McpLocalizedFallback(
    zhHant: '耗時曲線',
    fr: 'Courbe de latence',
    de: 'Latenzkurve',
    ja: 'レイテンシ曲線',
  ),
  'Last 12 minutes · success/failure/blocked': _McpLocalizedFallback(
    zhHant: '最近12分鐘 · 成功/失敗/攔截',
    fr: '12 dernières minutes · succès/échec/bloqué',
    de: 'Letzte 12 Minuten · Erfolg/Fehler/Blockiert',
    ja: '直近12分 · 成功/失敗/ブロック',
  ),
  'Average and tail latency': _McpLocalizedFallback(
    zhHant: '平均耗時與尾延遲',
    fr: 'Latence moyenne et de queue',
    de: 'Durchschnitts- und Tail-Latenz',
    ja: '平均とテールレイテンシ',
  ),
  'Status Mix': _McpLocalizedFallback(
    zhHant: '狀態分布',
    fr: 'Répartition des états',
    de: 'Statusverteilung',
    ja: 'ステータス分布',
  ),
  'IP Mix': _McpLocalizedFallback(
    zhHant: '請求 IP 分布',
    fr: 'Répartition IP',
    de: 'IP-Verteilung',
    ja: 'IP 分布',
  ),
  'Client Mix': _McpLocalizedFallback(
    zhHant: '請求客戶端分布',
    fr: 'Répartition des clients',
    de: 'Clientverteilung',
    ja: 'クライアント分布',
  ),
  'Request Mix': _McpLocalizedFallback(
    zhHant: '請求分布',
    fr: 'Répartition des requêtes',
    de: 'Anfrageverteilung',
    ja: 'リクエスト分布',
  ),
  'Protocol Mix': _McpLocalizedFallback(
    zhHant: '協議分布',
    fr: 'Répartition des protocoles',
    de: 'Protokollverteilung',
    ja: 'プロトコル分布',
  ),
  'Listener': _McpLocalizedFallback(
    zhHant: '監聽與訪問控制',
    fr: 'Écoute et accès',
    de: 'Listener und Zugriff',
    ja: 'リスナーとアクセス',
  ),
  'Listen Host': _McpLocalizedFallback(
    zhHant: '監聽地址',
    fr: 'Adresse d’écoute',
    de: 'Listen-Adresse',
    ja: 'リッスンホスト',
  ),
  'Listen Port': _McpLocalizedFallback(
    zhHant: '監聽埠',
    fr: 'Port d’écoute',
    de: 'Listen-Port',
    ja: 'リッスンポート',
  ),
  'Workspace Scope': _McpLocalizedFallback(
    zhHant: '可操作檔案空間',
    fr: 'Espace de travail',
    de: 'Arbeitsbereich',
    ja: 'ワークスペース範囲',
  ),
  'Pick a folder with the system file browser': _McpLocalizedFallback(
    zhHant: '透過系統檔案瀏覽器選擇目錄',
    fr: 'Choisir un dossier avec le navigateur système',
    de: 'Ordner über den System-Dateibrowser auswählen',
    ja: 'システムのファイルブラウザーでフォルダーを選択',
  ),
  'Choose Directory': _McpLocalizedFallback(
    zhHant: '選擇目錄',
    fr: 'Choisir un dossier',
    de: 'Verzeichnis auswählen',
    ja: 'ディレクトリを選択',
  ),
  'Clear Directory': _McpLocalizedFallback(
    zhHant: '清除目錄',
    fr: 'Effacer le dossier',
    de: 'Verzeichnis leeren',
    ja: 'ディレクトリをクリア',
  ),
  'Failed to open file browser': _McpLocalizedFallback(
    zhHant: '開啟系統檔案瀏覽器失敗',
    fr: 'Échec de l’ouverture du navigateur de fichiers',
    de: 'Dateibrowser konnte nicht geöffnet werden',
    ja: 'ファイルブラウザーを開けませんでした',
  ),
  'Access Token': _McpLocalizedFallback(
    zhHant: '訪問令牌',
    fr: 'Jeton d’accès',
    de: 'Zugriffstoken',
    ja: 'アクセストークン',
  ),
  'Start with app': _McpLocalizedFallback(
    zhHant: '跟隨應用啟動',
    fr: 'Démarrer avec l’app',
    de: 'Mit App starten',
    ja: 'アプリ起動時に開始',
  ),
  'Autostart is off by default. OpenHand only starts this MCP server during app launch when this switch is enabled.':
      _McpLocalizedFallback(
        zhHant: '自動啟動預設關閉；只有在這裡啟用後，OpenHand 啟動完成時才會自動啟動本 MCP 伺服器。',
        fr: 'Le démarrage auto est désactivé par défaut. OpenHand ne lance ce serveur MCP au démarrage que si ce commutateur est activé.',
        de: 'Autostart ist standardmäßig aus. OpenHand startet diesen MCP-Server beim App-Start nur, wenn dieser Schalter aktiviert ist.',
        ja: '自動起動は既定でオフです。このスイッチを有効にした場合のみ、OpenHand の起動時にこの MCP サーバーを開始します。',
      ),
  'Autostart': _McpLocalizedFallback(
    zhHant: '自動啟動',
    fr: 'Démarrage auto',
    de: 'Autostart',
    ja: '自動起動',
  ),
  'Token Auth': _McpLocalizedFallback(
    zhHant: '令牌校驗',
    fr: 'Auth par jeton',
    de: 'Token-Auth',
    ja: 'トークン認証',
  ),
  'Capture Payload': _McpLocalizedFallback(
    zhHant: '記錄參數',
    fr: 'Capturer les paramètres',
    de: 'Payload erfassen',
    ja: 'ペイロード記録',
  ),
  'Policy': _McpLocalizedFallback(
    zhHant: '限流與調用策略',
    fr: 'Politique',
    de: 'Richtlinie',
    ja: 'ポリシー',
  ),
  'Call Threshold': _McpLocalizedFallback(
    zhHant: '調用次數閾值',
    fr: 'Seuil d’appels',
    de: 'Aufrufschwelle',
    ja: '呼び出ししきい値',
  ),
  'Timeout (ms)': _McpLocalizedFallback(
    zhHant: '超時時間(ms)',
    fr: 'Délai (ms)',
    de: 'Timeout (ms)',
    ja: 'タイムアウト(ms)',
  ),
  'Approval Wait (ms)': _McpLocalizedFallback(
    zhHant: '審批等待(ms)',
    fr: 'Attente approbation (ms)',
    de: 'Freigabe-Wartezeit (ms)',
    ja: '承認待機(ms)',
  ),
  'Network Mode': _McpLocalizedFallback(
    zhHant: '網路模式',
    fr: 'Mode réseau',
    de: 'Netzwerkmodus',
    ja: 'ネットワークモード',
  ),
  'Invocation Mode': _McpLocalizedFallback(
    zhHant: '調用模式',
    fr: 'Mode d’appel',
    de: 'Aufrufmodus',
    ja: '呼び出しモード',
  ),
  'Write Policy': _McpLocalizedFallback(
    zhHant: '寫調用策略',
    fr: 'Politique d’écriture',
    de: 'Schreibrichtlinie',
    ja: '書き込み方針',
  ),
  'Allowed Clients': _McpLocalizedFallback(
    zhHant: '允許客戶端',
    fr: 'Clients autorisés',
    de: 'Erlaubte Clients',
    ja: '許可クライアント',
  ),
  'Allowed IP/CIDR': _McpLocalizedFallback(
    zhHant: '允許 IP/CIDR',
    fr: 'IP/CIDR autorisés',
    de: 'Erlaubte IP/CIDR',
    ja: '許可 IP/CIDR',
  ),
  'Exposure': _McpLocalizedFallback(
    zhHant: 'MCP 化暴露範圍',
    fr: 'Exposition MCP',
    de: 'MCP-Freigabe',
    ja: 'MCP 公開範囲',
  ),
  'Search exposure items': _McpLocalizedFallback(
    zhHant: '搜尋暴露條目',
    fr: 'Rechercher les éléments exposés',
    de: 'Freigaben durchsuchen',
    ja: '公開項目を検索',
  ),
  'Filter by server, tool, skill, memory or knowledge': _McpLocalizedFallback(
    zhHant: '輸入服務、工具、技能、記憶或知識庫關鍵字',
    fr: 'Filtrer par serveur, outil, compétence, mémoire ou connaissance',
    de: 'Nach Server, Tool, Skill, Memory oder Wissen filtern',
    ja: 'サーバー、ツール、スキル、メモリ、知識で絞り込み',
  ),
  'Disabled': _McpLocalizedFallback(
    zhHant: '已停用',
    fr: 'Désactivé',
    de: 'Deaktiviert',
    ja: '無効',
  ),
  'No exposed items': _McpLocalizedFallback(
    zhHant: '暫無可暴露條目',
    fr: 'Aucun élément exposable',
    de: 'Keine freigebbaren Einträge',
    ja: '公開可能な項目はありません',
  ),
  'No matches': _McpLocalizedFallback(
    zhHant: '沒有匹配條目',
    fr: 'Aucun résultat',
    de: 'Keine Treffer',
    ja: '一致なし',
  ),
  'Show more': _McpLocalizedFallback(
    zhHant: '載入更多',
    fr: 'Afficher plus',
    de: 'Mehr anzeigen',
    ja: 'さらに表示',
  ),
  'MCP server stopped': _McpLocalizedFallback(
    zhHant: 'MCP 伺服器已關閉',
    fr: 'Serveur MCP arrêté',
    de: 'MCP-Server gestoppt',
    ja: 'MCP サーバーを停止しました',
  ),
  'Stop failed': _McpLocalizedFallback(
    zhHant: '關閉失敗',
    fr: 'Arrêt échoué',
    de: 'Stop fehlgeschlagen',
    ja: '停止に失敗しました',
  ),
  'Connectivity OK': _McpLocalizedFallback(
    zhHant: '連通性正常',
    fr: 'Connectivité OK',
    de: 'Verbindung OK',
    ja: '接続正常',
  ),
  'Configuration applied': _McpLocalizedFallback(
    zhHant: '配置已生效',
    fr: 'Configuration appliquée',
    de: 'Konfiguration angewendet',
    ja: '設定を適用しました',
  ),
  'Configuration failed': _McpLocalizedFallback(
    zhHant: '配置保存失敗',
    fr: 'Échec de la configuration',
    de: 'Konfiguration fehlgeschlagen',
    ja: '設定に失敗しました',
  ),
  'Reset': _McpLocalizedFallback(
    zhHant: '重置',
    fr: 'Réinitialiser',
    de: 'Zurücksetzen',
    ja: 'リセット',
  ),
  'Reset MCP server configuration?': _McpLocalizedFallback(
    zhHant: '重置 MCP 伺服器配置？',
    fr: 'Réinitialiser la configuration du serveur MCP ?',
    de: 'MCP-Serverkonfiguration zurücksetzen?',
    ja: 'MCP サーバー設定をリセットしますか？',
  ),
  'Listener, access control, rate limits, invocation policy and exposure scope will return to defaults. Autostart stays off. This will be saved immediately.':
      _McpLocalizedFallback(
        zhHant: '監聽、訪問控制、限流、調用策略與暴露範圍都會恢復為預設值。自動啟動會保持關閉。此操作會立即保存。',
        fr: 'L’écoute, le contrôle d’accès, les limites, la stratégie d’appel et le périmètre d’exposition reviendront aux valeurs par défaut. Le démarrage auto reste désactivé. L’enregistrement est immédiat.',
        de: 'Listener, Zugriffskontrolle, Limits, Aufrufrichtlinie und Freigabeumfang werden auf Standardwerte zurückgesetzt. Autostart bleibt aus. Dies wird sofort gespeichert.',
        ja: 'リスナー、アクセス制御、レート制限、呼び出し方針、公開範囲を既定値に戻します。自動起動はオフのままです。この操作はすぐに保存されます。',
      ),
  'Defaults restored': _McpLocalizedFallback(
    zhHant: '已恢復預設配置',
    fr: 'Valeurs par défaut restaurées',
    de: 'Standardwerte wiederhergestellt',
    ja: '既定値を復元しました',
  ),
  'Reset failed': _McpLocalizedFallback(
    zhHant: '重置失敗',
    fr: 'Échec de la réinitialisation',
    de: 'Zurücksetzen fehlgeschlagen',
    ja: 'リセットに失敗しました',
  ),
  'Server Console': _McpLocalizedFallback(
    zhHant: '服務控制台',
    fr: 'Console serveur',
    de: 'Serverkonsole',
    ja: 'サーバーコンソール',
  ),
  'Test': _McpLocalizedFallback(
    zhHant: '連通性測試',
    fr: 'Tester',
    de: 'Testen',
    ja: 'テスト',
  ),
  'Start': _McpLocalizedFallback(
    zhHant: '啟動',
    fr: 'Démarrer',
    de: 'Starten',
    ja: '起動',
  ),
  'Restart': _McpLocalizedFallback(
    zhHant: '重啟',
    fr: 'Redémarrer',
    de: 'Neu starten',
    ja: '再起動',
  ),
  'Stop': _McpLocalizedFallback(
    zhHant: '關閉',
    fr: 'Arrêter',
    de: 'Stoppen',
    ja: '停止',
  ),
  'Average': _McpLocalizedFallback(
    zhHant: '平均',
    fr: 'Moyenne',
    de: 'Durchschnitt',
    ja: '平均',
  ),
  'Waiting for traffic': _McpLocalizedFallback(
    zhHant: '等待請求樣本',
    fr: 'En attente de trafic',
    de: 'Warte auf Traffic',
    ja: 'トラフィック待ち',
  ),
  'Write Approvals': _McpLocalizedFallback(
    zhHant: '寫調用審批',
    fr: 'Approbations d’écriture',
    de: 'Schreibfreigaben',
    ja: '書き込み承認',
  ),
  'Reject': _McpLocalizedFallback(
    zhHant: '拒絕',
    fr: 'Refuser',
    de: 'Ablehnen',
    ja: '拒否',
  ),
  'Allow': _McpLocalizedFallback(
    zhHant: '放行',
    fr: 'Autoriser',
    de: 'Erlauben',
    ja: '許可',
  ),
  'Builtin Tools': _McpLocalizedFallback(
    zhHant: '內建工具',
    fr: 'Outils intégrés',
    de: 'Integrierte Tools',
    ja: '内蔵ツール',
  ),
  'Skills': _McpLocalizedFallback(
    zhHant: '技能',
    fr: 'Compétences',
    de: 'Skills',
    ja: 'スキル',
  ),
  'Instructions': _McpLocalizedFallback(
    zhHant: '指令',
    fr: 'Instructions',
    de: 'Anweisungen',
    ja: '指示',
  ),
  'Knowledge Base': _McpLocalizedFallback(
    zhHant: '知識庫',
    fr: 'Base de connaissances',
    de: 'Wissensdatenbank',
    ja: 'ナレッジベース',
  ),
  'MCP Servers': _McpLocalizedFallback(
    zhHant: 'MCP 服務',
    fr: 'Serveurs MCP',
    de: 'MCP-Server',
    ja: 'MCP サーバー',
  ),
  'Loopback': _McpLocalizedFallback(
    zhHant: '僅本機',
    fr: 'Boucle locale',
    de: 'Loopback',
    ja: 'ローカルのみ',
  ),
  'LAN': _McpLocalizedFallback(zhHant: '區域網', fr: 'LAN', de: 'LAN', ja: 'LAN'),
  'Custom': _McpLocalizedFallback(
    zhHant: '自訂',
    fr: 'Personnalisé',
    de: 'Benutzerdefiniert',
    ja: 'カスタム',
  ),
  'Direct': _McpLocalizedFallback(
    zhHant: '直接',
    fr: 'Direct',
    de: 'Direkt',
    ja: '直接',
  ),
  'Queued': _McpLocalizedFallback(
    zhHant: '排隊',
    fr: 'En file',
    de: 'Warteschlange',
    ja: 'キュー',
  ),
  'Guarded': _McpLocalizedFallback(
    zhHant: '受控',
    fr: 'Contrôlé',
    de: 'Geschützt',
    ja: '保護',
  ),
  'Approval': _McpLocalizedFallback(
    zhHant: '預設審批',
    fr: 'Approbation',
    de: 'Freigabe',
    ja: '承認',
  ),
  'Full Access': _McpLocalizedFallback(
    zhHant: '完全訪問',
    fr: 'Accès complet',
    de: 'Vollzugriff',
    ja: 'フルアクセス',
  ),
  'Read Only': _McpLocalizedFallback(
    zhHant: '只讀',
    fr: 'Lecture seule',
    de: 'Nur Lesen',
    ja: '読み取り専用',
  ),
  'Stopped': _McpLocalizedFallback(
    zhHant: '已關閉',
    fr: 'Arrêté',
    de: 'Gestoppt',
    ja: '停止済み',
  ),
  'Restarting': _McpLocalizedFallback(
    zhHant: '重啟中',
    fr: 'Redémarrage',
    de: 'Neustart läuft',
    ja: '再起動中',
  ),
  'Export snapshot': _McpLocalizedFallback(
    zhHant: '匯出快照',
    fr: 'Exporter l’instantané',
    de: 'Snapshot exportieren',
    ja: 'スナップショットを書き出し',
  ),
  'Probe Details': _McpLocalizedFallback(
    zhHant: '探測詳情',
    fr: 'Détails de la sonde',
    de: 'Prüfdetails',
    ja: 'プローブ詳細',
  ),
  'This MCP needs a concrete package name or URL first.': _McpLocalizedFallback(
    zhHant: '該 MCP 需要先按服務說明填寫套件名稱或地址。',
    fr: 'Ce MCP nécessite d’abord un nom de paquet ou une URL concret.',
    de: 'Für dieses MCP muss zuerst ein konkreter Paketname oder eine URL eingetragen werden.',
    ja: 'この MCP には先に具体的なパッケージ名または URL が必要です。',
  ),
  'Export snapshot (JSON)': _McpLocalizedFallback(
    zhHant: '匯出快照 (JSON)',
    fr: 'Exporter l’instantané (JSON)',
    de: 'Snapshot exportieren (JSON)',
    ja: 'スナップショットを書き出し (JSON)',
  ),
  'Export snapshot (CSV)': _McpLocalizedFallback(
    zhHant: '匯出快照 (CSV)',
    fr: 'Exporter l’instantané (CSV)',
    de: 'Snapshot exportieren (CSV)',
    ja: 'スナップショットを書き出し (CSV)',
  ),
  'Register': _McpLocalizedFallback(
    zhHant: '註冊服務',
    fr: 'Enregistrer',
    de: 'Registrieren',
    ja: '登録',
  ),
  'Configure': _McpLocalizedFallback(
    zhHant: '需配置',
    fr: 'À configurer',
    de: 'Konfigurieren',
    ja: '設定が必要',
  ),
  'Request Headers': _McpLocalizedFallback(
    zhHant: '請求 Header',
    fr: 'En-têtes de requête',
    de: 'Request-Header',
    ja: 'リクエストヘッダー',
  ),
  'Manage headers as key-value rows for HTTP / SSE requests.': _McpLocalizedFallback(
    zhHant: '按鍵值對逐項維護，會隨 HTTP / SSE 請求一起發送。',
    fr: 'Gérez les en-têtes en lignes clé-valeur pour les requêtes HTTP / SSE.',
    de: 'Header als Schlüssel-Wert-Zeilen für HTTP- / SSE-Anfragen verwalten.',
    ja: 'HTTP / SSE リクエストに送るヘッダーをキーと値で管理します。',
  ),
  'Add Header': _McpLocalizedFallback(
    zhHant: '新增 Header',
    fr: 'Ajouter un en-tête',
    de: 'Header hinzufügen',
    ja: 'ヘッダーを追加',
  ),
  'Header Name': _McpLocalizedFallback(
    zhHant: 'Header 名稱',
    fr: 'Nom de l’en-tête',
    de: 'Header-Name',
    ja: 'ヘッダー名',
  ),
  'e.g. Authorization': _McpLocalizedFallback(
    zhHant: '例如 Authorization',
    fr: 'p. ex. Authorization',
    de: 'z. B. Authorization',
    ja: '例: Authorization',
  ),
  'Header Value': _McpLocalizedFallback(
    zhHant: 'Header 值',
    fr: 'Valeur de l’en-tête',
    de: 'Header-Wert',
    ja: 'ヘッダー値',
  ),
  'e.g. Bearer token': _McpLocalizedFallback(
    zhHant: '例如 Bearer token',
    fr: 'p. ex. Bearer token',
    de: 'z. B. Bearer token',
    ja: '例: Bearer token',
  ),
  'Remove Header': _McpLocalizedFallback(
    zhHant: '刪除 Header',
    fr: 'Supprimer l’en-tête',
    de: 'Header entfernen',
    ja: 'ヘッダーを削除',
  ),
  'Health Check': _McpLocalizedFallback(
    zhHant: '健康檢測',
    fr: 'Contrôle de santé',
    de: 'Integritätsprüfung',
    ja: 'ヘルスチェック',
  ),
  'Refresh Tool Scan': _McpLocalizedFallback(
    zhHant: '重新整理 Tool 檢測',
    fr: 'Actualiser l’analyse des tools',
    de: 'Tool-Scan aktualisieren',
    ja: 'Tool スキャンを更新',
  ),
  'Reconnect: re-scan Tools and re-run health check': _McpLocalizedFallback(
    zhHant: '一鍵重連：重新拉取 Tools 並立即健康複測',
    fr: 'Reconnecter : rescanner les tools et relancer le contrôle de santé',
    de: 'Neu verbinden: Tools erneut scannen und Integritätsprüfung wiederholen',
    ja: '再接続: Tools を再スキャンしてヘルスチェックを再実行',
  ),
  'Close search': _McpLocalizedFallback(
    zhHant: '關閉搜尋',
    fr: 'Fermer la recherche',
    de: 'Suche schließen',
    ja: '検索を閉じる',
  ),
  'Search tools': _McpLocalizedFallback(
    zhHant: '搜尋 Tool',
    fr: 'Rechercher des tools',
    de: 'Tools suchen',
    ja: 'Tools を検索',
  ),
  'More actions': _McpLocalizedFallback(
    zhHant: '更多操作',
    fr: 'Plus d’actions',
    de: 'Weitere Aktionen',
    ja: 'その他の操作',
  ),
  'Server details': _McpLocalizedFallback(
    zhHant: '服務詳情',
    fr: 'Détails du service',
    de: 'Dienstdetails',
    ja: 'サービス詳細',
  ),
  'View probe history': _McpLocalizedFallback(
    zhHant: '查看探測歷史',
    fr: 'Voir l’historique des sondes',
    de: 'Prüfverlauf anzeigen',
    ja: 'プローブ履歴を表示',
  ),
  'Starting': _McpLocalizedFallback(
    zhHant: '進程啟動中',
    fr: 'Démarrage',
    de: 'Startet',
    ja: '起動中',
  ),
  'Stopping': _McpLocalizedFallback(
    zhHant: '進程停止中',
    fr: 'Arrêt',
    de: 'Stoppt',
    ja: '停止中',
  ),
  'Process exited': _McpLocalizedFallback(
    zhHant: '進程異常退出',
    fr: 'Processus terminé',
    de: 'Prozess beendet',
    ja: 'プロセスが終了しました',
  ),
  'Scanning the tool list exposed by this MCP server.': _McpLocalizedFallback(
    zhHant: '正在掃描該 MCP 服務暴露的 Tool 列表。',
    fr: 'Analyse de la liste des tools exposés par ce serveur MCP.',
    de: 'Die von diesem MCP-Dienst bereitgestellte Tool-Liste wird gescannt.',
    ja: 'この MCP サービスが公開する Tool 一覧をスキャンしています。',
  ),
  'Bootstrapping…': _McpLocalizedFallback(
    zhHant: '首啟準備中…',
    fr: 'Préparation…',
    de: 'Wird vorbereitet…',
    ja: '初回準備中…',
  ),
  'Scanning Tools': _McpLocalizedFallback(
    zhHant: '掃描 Tool 中',
    fr: 'Analyse des tools',
    de: 'Tools werden gescannt',
    ja: 'Tools をスキャン中',
  ),
  'Type to filter tools…': _McpLocalizedFallback(
    zhHant: '輸入關鍵字過濾 Tool…',
    fr: 'Saisissez pour filtrer les tools…',
    de: 'Zum Filtern der Tools eingeben…',
    ja: 'キーワードで Tool を絞り込み…',
  ),
  'No tools were discovered yet. Try refreshing this service.':
      _McpLocalizedFallback(
        zhHant: '暫未發現可用 Tool，可手動重新整理重試。',
        fr: 'Aucun tool n’a encore été découvert. Essayez d’actualiser ce service.',
        de: 'Noch keine Tools gefunden. Aktualisieren Sie diesen Dienst erneut.',
        ja: '利用可能な Tool はまだ見つかっていません。更新して再試行してください。',
      ),
  'This service is disabled. Refresh manually to inspect its tools.':
      _McpLocalizedFallback(
        zhHant: '服務已禁用，可手動重新整理檢測 Tool 資訊。',
        fr: 'Ce service est désactivé. Actualisez manuellement pour inspecter ses tools.',
        de: 'Dieser Dienst ist deaktiviert. Aktualisieren Sie manuell, um seine Tools zu prüfen.',
        ja: 'このサービスは無効です。手動更新で Tool 情報を確認できます。',
      ),
  'Stop service': _McpLocalizedFallback(
    zhHant: '停止服務',
    fr: 'Arrêter le service',
    de: 'Dienst stoppen',
    ja: 'サービスを停止',
  ),
  'Start service': _McpLocalizedFallback(
    zhHant: '啟動服務',
    fr: 'Démarrer le service',
    de: 'Dienst starten',
    ja: 'サービスを起動',
  ),
  'View logs': _McpLocalizedFallback(
    zhHant: '查看日誌',
    fr: 'Voir les journaux',
    de: 'Logs anzeigen',
    ja: 'ログを表示',
  ),
  'Runtime details': _McpLocalizedFallback(
    zhHant: '執行期詳情',
    fr: 'Détails d’exécution',
    de: 'Laufzeitdetails',
    ja: 'ランタイム詳細',
  ),
  'Dependencies': _McpLocalizedFallback(
    zhHant: '依賴管理',
    fr: 'Dépendances',
    de: 'Abhängigkeiten',
    ja: '依存関係',
  ),
  'Edit configuration': _McpLocalizedFallback(
    zhHant: '跳轉到編輯',
    fr: 'Modifier la configuration',
    de: 'Konfiguration bearbeiten',
    ja: '設定を編集',
  ),
  'Edit': _McpLocalizedFallback(
    zhHant: '編輯',
    fr: 'Modifier',
    de: 'Bearbeiten',
    ja: '編集',
  ),
  'Configuration': _McpLocalizedFallback(
    zhHant: '配置摘要',
    fr: 'Configuration',
    de: 'Konfiguration',
    ja: '設定',
  ),
  'Protocol': _McpLocalizedFallback(
    zhHant: '協議類型',
    fr: 'Protocole',
    de: 'Protokoll',
    ja: 'プロトコル',
  ),
  'Enabled': _McpLocalizedFallback(
    zhHant: '啟用狀態',
    fr: 'Activé',
    de: 'Aktiviert',
    ja: '有効状態',
  ),
  'Yes': _McpLocalizedFallback(zhHant: '已啟用', fr: 'Oui', de: 'Ja', ja: 'はい'),
  'No': _McpLocalizedFallback(zhHant: '已停用', fr: 'Non', de: 'Nein', ja: 'いいえ'),
  'Endpoint': _McpLocalizedFallback(
    zhHant: '入口',
    fr: 'Point d’accès',
    de: 'Endpunkt',
    ja: 'エンドポイント',
  ),
  'Headers': _McpLocalizedFallback(
    zhHant: 'Header 數量',
    fr: 'En-têtes',
    de: 'Header',
    ja: 'ヘッダー',
  ),
  'Health': _McpLocalizedFallback(
    zhHant: '健康統計',
    fr: 'Santé',
    de: 'Integrität',
    ja: 'ヘルス',
  ),
  'Status': _McpLocalizedFallback(
    zhHant: '當前狀態',
    fr: 'État',
    de: 'Status',
    ja: '状態',
  ),
  'Healthy': _McpLocalizedFallback(
    zhHant: '健康',
    fr: 'Sain',
    de: 'Fehlerfrei',
    ja: '正常',
  ),
  'Unhealthy': _McpLocalizedFallback(
    zhHant: '不健康',
    fr: 'Dégradé',
    de: 'Fehlerhaft',
    ja: '異常',
  ),
  'Checking': _McpLocalizedFallback(
    zhHant: '檢測中',
    fr: 'Vérification',
    de: 'Prüfung',
    ja: '確認中',
  ),
  'Idle': _McpLocalizedFallback(
    zhHant: '尚未探測',
    fr: 'Inactif',
    de: 'Inaktiv',
    ja: '未実行',
  ),
  'Last success': _McpLocalizedFallback(
    zhHant: '最近成功',
    fr: 'Dernier succès',
    de: 'Letzter Erfolg',
    ja: '直近の成功',
  ),
  'Last failure': _McpLocalizedFallback(
    zhHant: '最近失敗',
    fr: 'Dernier échec',
    de: 'Letzter Fehler',
    ja: '直近の失敗',
  ),
  'Consecutive fails': _McpLocalizedFallback(
    zhHant: '連續失敗',
    fr: 'Échecs consécutifs',
    de: 'Fehler in Folge',
    ja: '連続失敗',
  ),
  'Recent success rate': _McpLocalizedFallback(
    zhHant: '近期成功率',
    fr: 'Taux de succès récent',
    de: 'Aktuelle Erfolgsrate',
    ja: '直近の成功率',
  ),
  'Average latency': _McpLocalizedFallback(
    zhHant: '平均耗時',
    fr: 'Latence moyenne',
    de: 'Durchschnittslatenz',
    ja: '平均レイテンシ',
  ),
  'Sample size': _McpLocalizedFallback(
    zhHant: '記錄樣本',
    fr: 'Taille d’échantillon',
    de: 'Stichprobengröße',
    ja: 'サンプル数',
  ),
  'Tool catalog': _McpLocalizedFallback(
    zhHant: '工具目錄',
    fr: 'Catalogue des tools',
    de: 'Tool-Katalog',
    ja: 'Tool カタログ',
  ),
  'Loading': _McpLocalizedFallback(
    zhHant: '載入中',
    fr: 'Chargement',
    de: 'Lädt',
    ja: '読み込み中',
  ),
  'Failed': _McpLocalizedFallback(
    zhHant: '失敗',
    fr: 'Échec',
    de: 'Fehlgeschlagen',
    ja: '失敗',
  ),
  'Loaded': _McpLocalizedFallback(
    zhHant: '已載入',
    fr: 'Chargé',
    de: 'Geladen',
    ja: '読み込み済み',
  ),
  'Tool count': _McpLocalizedFallback(
    zhHant: 'Tool 數量',
    fr: 'Nombre de tools',
    de: 'Tool-Anzahl',
    ja: 'Tool 数',
  ),
  'Last error': _McpLocalizedFallback(
    zhHant: '最近錯誤',
    fr: 'Dernière erreur',
    de: 'Letzter Fehler',
    ja: '直近のエラー',
  ),
  'Probe trend': _McpLocalizedFallback(
    zhHant: '探測趨勢',
    fr: 'Tendance des sondes',
    de: 'Prüftrend',
    ja: 'プローブ傾向',
  ),
  'Healthy (latency)': _McpLocalizedFallback(
    zhHant: '健康 (耗時)',
    fr: 'Sain (latence)',
    de: 'Fehlerfrei (Latenz)',
    ja: '正常 (レイテンシ)',
  ),
  'No latency samples': _McpLocalizedFallback(
    zhHant: '暫無耗時樣本',
    fr: 'Aucun échantillon de latence',
    de: 'Keine Latenzproben',
    ja: 'レイテンシサンプルなし',
  ),
  'Tool preview': _McpLocalizedFallback(
    zhHant: '工具預覽',
    fr: 'Aperçu des tools',
    de: 'Tool-Vorschau',
    ja: 'Tool プレビュー',
  ),
  'Input schema': _McpLocalizedFallback(
    zhHant: '入參 Schema',
    fr: 'Schéma d’entrée',
    de: 'Eingabeschema',
    ja: '入力スキーマ',
  ),
  'Output schema': _McpLocalizedFallback(
    zhHant: '出參 Schema',
    fr: 'Schéma de sortie',
    de: 'Ausgabeschema',
    ja: '出力スキーマ',
  ),
  'Copy': _McpLocalizedFallback(
    zhHant: '複製',
    fr: 'Copier',
    de: 'Kopieren',
    ja: 'コピー',
  ),
  'Copy endpoint': _McpLocalizedFallback(
    zhHant: '複製入口',
    fr: 'Copier le point d’accès',
    de: 'Endpunkt kopieren',
    ja: 'エンドポイントをコピー',
  ),
  'Copy Cursor config': _McpLocalizedFallback(
    zhHant: '複製 Cursor 配置',
    fr: 'Copier la configuration Cursor',
    de: 'Cursor-Konfiguration kopieren',
    ja: 'Cursor 設定をコピー',
  ),
  'MCP endpoint copied': _McpLocalizedFallback(
    zhHant: 'MCP 入口已複製',
    fr: 'Point d’accès MCP copié',
    de: 'MCP-Endpunkt kopiert',
    ja: 'MCP エンドポイントをコピーしました',
  ),
  'Cursor MCP config copied': _McpLocalizedFallback(
    zhHant: 'Cursor MCP 配置已複製',
    fr: 'Configuration MCP Cursor copiée',
    de: 'Cursor-MCP-Konfiguration kopiert',
    ja: 'Cursor MCP 設定をコピーしました',
  ),
  'Access token is required when token auth is enabled': _McpLocalizedFallback(
    zhHant: '開啟令牌校驗後必須填寫訪問令牌',
    fr: 'Le jeton d’accès est requis quand l’authentification par jeton est activée',
    de: 'Bei aktivierter Token-Authentifizierung ist ein Zugriffstoken erforderlich',
    ja: 'トークン認証を有効にする場合はアクセストークンが必要です',
  ),
  'The access token is sent through the Cursor Authorization header, so it cannot contain Chinese characters, line breaks or control characters. Use a token made of English letters, digits or symbols.':
      _McpLocalizedFallback(
        zhHant:
            '訪問令牌會寫入 Cursor Authorization Header，不能包含中文、換行或控制字元；請換成英文、數字或符號組成的安全令牌。',
        fr: 'Le jeton est envoyé dans l’en-tête Authorization de Cursor ; il ne peut donc pas contenir de caractères chinois, de retours à la ligne ni de caractères de contrôle. Utilisez un jeton composé de lettres anglaises, de chiffres ou de symboles.',
        de: 'Das Token wird über den Cursor-Authorization-Header gesendet und darf daher keine chinesischen Zeichen, Zeilenumbrüche oder Steuerzeichen enthalten. Verwenden Sie ein Token aus englischen Buchstaben, Ziffern oder Symbolen.',
        ja: 'アクセストークンは Cursor の Authorization ヘッダーで送信されるため、中国語、改行、制御文字は使用できません。英字、数字、記号で構成されたトークンを使用してください。',
      ),
  'Schema copied': _McpLocalizedFallback(
    zhHant: '已複製 Schema',
    fr: 'Schéma copié',
    de: 'Schema kopiert',
    ja: 'スキーマをコピーしました',
  ),
  'Recent probe history': _McpLocalizedFallback(
    zhHant: '最近探測歷史',
    fr: 'Historique récent des sondes',
    de: 'Aktueller Prüfverlauf',
    ja: '直近のプローブ履歴',
  ),
  'Copy probe history': _McpLocalizedFallback(
    zhHant: '複製探測歷史',
    fr: 'Copier l’historique des sondes',
    de: 'Prüfverlauf kopieren',
    ja: 'プローブ履歴をコピー',
  ),
  'Copy as Markdown': _McpLocalizedFallback(
    zhHant: '複製為 Markdown',
    fr: 'Copier en Markdown',
    de: 'Als Markdown kopieren',
    ja: 'Markdown としてコピー',
  ),
  'Copy as JSON': _McpLocalizedFallback(
    zhHant: '複製為 JSON',
    fr: 'Copier en JSON',
    de: 'Als JSON kopieren',
    ja: 'JSON としてコピー',
  ),
  'Copy as CSV': _McpLocalizedFallback(
    zhHant: '複製為 CSV',
    fr: 'Copier en CSV',
    de: 'Als CSV kopieren',
    ja: 'CSV としてコピー',
  ),
  'No probes yet. Run a health check or reconnect to populate this list.':
      _McpLocalizedFallback(
        zhHant: '尚無探測記錄，請先發起一次健康檢測或一鍵重連。',
        fr: 'Aucune sonde pour l’instant. Lancez un contrôle de santé ou reconnectez pour remplir cette liste.',
        de: 'Noch keine Prüfungen. Führen Sie eine Integritätsprüfung aus oder verbinden Sie neu.',
        ja: 'プローブ記録はまだありません。ヘルスチェックまたは再接続を実行してください。',
      ),
  'Click to Disable': _McpLocalizedFallback(
    zhHant: '點擊停用',
    fr: 'Cliquer pour désactiver',
    de: 'Zum Deaktivieren klicken',
    ja: 'クリックして無効化',
  ),
  'Click to Enable': _McpLocalizedFallback(
    zhHant: '點擊啟用',
    fr: 'Cliquer pour activer',
    de: 'Zum Aktivieren klicken',
    ja: 'クリックして有効化',
  ),
  'Available Tools': _McpLocalizedFallback(
    zhHant: '可用 Tools',
    fr: 'Tools disponibles',
    de: 'Verfügbare Tools',
    ja: '利用可能な Tools',
  ),
  'Collapse': _McpLocalizedFallback(
    zhHant: '收起',
    fr: 'Réduire',
    de: 'Einklappen',
    ja: '折りたたむ',
  ),
  'Expand': _McpLocalizedFallback(
    zhHant: '展開',
    fr: 'Développer',
    de: 'Erweitern',
    ja: '展開',
  ),
  'No matching tools': _McpLocalizedFallback(
    zhHant: '沒有匹配的 Tool',
    fr: 'Aucun tool correspondant',
    de: 'Keine passenden Tools',
    ja: '一致する Tool はありません',
  ),
  'Debug Tool': _McpLocalizedFallback(
    zhHant: '調試 Tool',
    fr: 'Déboguer le tool',
    de: 'Tool debuggen',
    ja: 'Tool をデバッグ',
  ),
  'Input Metadata': _McpLocalizedFallback(
    zhHant: '入參資訊',
    fr: 'Métadonnées d’entrée',
    de: 'Eingabemetadaten',
    ja: '入力メタデータ',
  ),
  'Output Metadata': _McpLocalizedFallback(
    zhHant: '返回資訊',
    fr: 'Métadonnées de sortie',
    de: 'Ausgabemetadaten',
    ja: '出力メタデータ',
  ),
  'Execution': _McpLocalizedFallback(
    zhHant: '執行能力',
    fr: 'Exécution',
    de: 'Ausführung',
    ja: '実行',
  ),
  'Parameters': _McpLocalizedFallback(
    zhHant: '入參',
    fr: 'Paramètres',
    de: 'Parameter',
    ja: 'パラメータ',
  ),
  'This tool does not declare structured input fields.': _McpLocalizedFallback(
    zhHant: '該 Tool 未聲明結構化入參欄位。',
    fr: 'Ce tool ne déclare aucun champ d’entrée structuré.',
    de: 'Dieses Tool deklariert keine strukturierten Eingabefelder.',
    ja: 'この Tool は構造化入力フィールドを宣言していません。',
  ),
  'Return Description': _McpLocalizedFallback(
    zhHant: '返回說明',
    fr: 'Description du retour',
    de: 'Rückgabebeschreibung',
    ja: '戻り値の説明',
  ),
  'Derived from the tool description': _McpLocalizedFallback(
    zhHant: '基於 Tool 描述推斷',
    fr: 'Déduit de la description du tool',
    de: 'Aus der Tool-Beschreibung abgeleitet',
    ja: 'Tool の説明から推定',
  ),
  'Return Value': _McpLocalizedFallback(
    zhHant: '返回值',
    fr: 'Valeur de retour',
    de: 'Rückgabewert',
    ja: '戻り値',
  ),
  'This tool does not declare a structured output schema.':
      _McpLocalizedFallback(
        zhHant: '該 Tool 未聲明結構化返回值 Schema。',
        fr: 'Ce tool ne déclare aucun schéma de sortie structuré.',
        de: 'Dieses Tool deklariert kein strukturiertes Ausgabeschema.',
        ja: 'この Tool は構造化出力スキーマを宣言していません。',
      ),
  'This tool does not declare an output schema.': _McpLocalizedFallback(
    zhHant: '該 Tool 未聲明返回值 Schema。',
    fr: 'Ce tool ne déclare aucun schéma de sortie.',
    de: 'Dieses Tool deklariert kein Ausgabeschema.',
    ja: 'この Tool は出力スキーマを宣言していません。',
  ),
  'The output schema does not expose structured fields.': _McpLocalizedFallback(
    zhHant: '返回值 Schema 未提供結構化欄位。',
    fr: 'Le schéma de sortie n’expose aucun champ structuré.',
    de: 'Das Ausgabeschema stellt keine strukturierten Felder bereit.',
    ja: '出力スキーマに構造化フィールドがありません。',
  ),
  'Raw Server Metadata': _McpLocalizedFallback(
    zhHant: '服務端原始元資料',
    fr: 'Métadonnées serveur brutes',
    de: 'Rohe Servermetadaten',
    ja: 'サーバーの生メタデータ',
  ),
  'Arguments must be a valid JSON object.': _McpLocalizedFallback(
    zhHant: '參數必須是合法的 JSON 物件。',
    fr: 'Les arguments doivent être un objet JSON valide.',
    de: 'Argumente müssen ein gültiges JSON-Objekt sein.',
    ja: '引数は有効な JSON オブジェクトである必要があります。',
  ),
  'None': _McpLocalizedFallback(
    zhHant: '未配置',
    fr: 'Aucun',
    de: 'Keine',
    ja: 'なし',
  ),
  'Use server headers': _McpLocalizedFallback(
    zhHant: '複用服務 Header',
    fr: 'Utiliser les en-têtes du service',
    de: 'Dienst-Header verwenden',
    ja: 'サービスヘッダーを使用',
  ),
  'Reuse server headers or configure custom headers for debugging.':
      _McpLocalizedFallback(
        zhHant: '可複用 MCP 服務配置的 Header，或手動配置調試專用 Header。',
        fr: 'Réutilisez les en-têtes du service MCP ou configurez des en-têtes dédiés au débogage.',
        de: 'MCP-Dienst-Header wiederverwenden oder eigene Header für das Debugging konfigurieren.',
        ja: 'MCP サービス設定のヘッダーを再利用するか、デバッグ専用ヘッダーを手動設定します。',
      ),
  'Custom Headers': _McpLocalizedFallback(
    zhHant: '自訂 Header',
    fr: 'En-têtes personnalisés',
    de: 'Benutzerdefinierte Header',
    ja: 'カスタムヘッダー',
  ),
  'Add': _McpLocalizedFallback(
    zhHant: '新增',
    fr: 'Ajouter',
    de: 'Hinzufügen',
    ja: '追加',
  ),
  'Name': _McpLocalizedFallback(zhHant: '名稱', fr: 'Nom', de: 'Name', ja: '名前'),
  'Value': _McpLocalizedFallback(
    zhHant: '值',
    fr: 'Valeur',
    de: 'Wert',
    ja: '値',
  ),
  'Remove': _McpLocalizedFallback(
    zhHant: '刪除',
    fr: 'Supprimer',
    de: 'Entfernen',
    ja: '削除',
  ),
  'Debug MCP Tool': _McpLocalizedFallback(
    zhHant: '調試 MCP Tool',
    fr: 'Déboguer le tool MCP',
    de: 'MCP-Tool debuggen',
    ja: 'MCP Tool をデバッグ',
  ),
  'No tools are available for debugging yet. Refresh the tool list first.':
      _McpLocalizedFallback(
        zhHant: '目前服務還沒有可調試的 Tool，請先重新整理 Tool 列表。',
        fr: 'Aucun tool n’est encore disponible pour le débogage. Actualisez d’abord la liste.',
        de: 'Noch keine Tools zum Debuggen verfügbar. Aktualisieren Sie zuerst die Tool-Liste.',
        ja: 'デバッグ可能な Tool はまだありません。先に Tool 一覧を更新してください。',
      ),
  'Tool': _McpLocalizedFallback(
    zhHant: '選擇 Tool',
    fr: 'Tool',
    de: 'Tool',
    ja: 'Tool',
  ),
  'Arguments JSON': _McpLocalizedFallback(
    zhHant: '參數 JSON',
    fr: 'Arguments JSON',
    de: 'Argumente JSON',
    ja: '引数 JSON',
  ),
  'Enter a JSON object, for example {"page": 1}': _McpLocalizedFallback(
    zhHant: '請輸入 JSON 物件，例如 {"page": 1}',
    fr: 'Saisissez un objet JSON, par exemple {"page": 1}',
    de: 'JSON-Objekt eingeben, z. B. {"page": 1}',
    ja: 'JSON オブジェクトを入力します。例: {"page": 1}',
  ),
  'Running': _McpLocalizedFallback(
    zhHant: '執行中',
    fr: 'Exécution',
    de: 'Läuft',
    ja: '実行中',
  ),
  'Run Tool': _McpLocalizedFallback(
    zhHant: '執行 Tool',
    fr: 'Exécuter le tool',
    de: 'Tool ausführen',
    ja: 'Tool を実行',
  ),
  'Reset Sample': _McpLocalizedFallback(
    zhHant: '恢復範例參數',
    fr: 'Réinitialiser l’exemple',
    de: 'Beispiel zurücksetzen',
    ja: 'サンプルをリセット',
  ),
  'Parameter Reference': _McpLocalizedFallback(
    zhHant: '參數參考',
    fr: 'Référence des paramètres',
    de: 'Parameterreferenz',
    ja: 'パラメータ参照',
  ),
  'Result': _McpLocalizedFallback(
    zhHant: '執行結果',
    fr: 'Résultat',
    de: 'Ergebnis',
    ja: '結果',
  ),
  'The raw tool result will appear here after execution.':
      _McpLocalizedFallback(
        zhHant: '執行後會在這裡展示原始返回結果。',
        fr: 'Le résultat brut du tool s’affichera ici après l’exécution.',
        de: 'Das rohe Tool-Ergebnis wird nach der Ausführung hier angezeigt.',
        ja: '実行後、Tool の生の戻り値がここに表示されます。',
      ),
  'Server Returned Error': _McpLocalizedFallback(
    zhHant: '服務端返回錯誤',
    fr: 'Erreur retournée par le serveur',
    de: 'Server gab einen Fehler zurück',
    ja: 'サーバーがエラーを返しました',
  ),
  'Succeeded': _McpLocalizedFallback(
    zhHant: '執行成功',
    fr: 'Réussi',
    de: 'Erfolgreich',
    ja: '成功',
  ),
  'Waiting for the MCP service to return a result...': _McpLocalizedFallback(
    zhHant: '正在等待 MCP 服務返回結果...',
    fr: 'En attente du résultat du service MCP...',
    de: 'Warten auf ein Ergebnis des MCP-Dienstes...',
    ja: 'MCP サービスの結果を待っています...',
  ),
  'Required': _McpLocalizedFallback(
    zhHant: '必填',
    fr: 'Obligatoire',
    de: 'Erforderlich',
    ja: '必須',
  ),
  'Described': _McpLocalizedFallback(
    zhHant: '已描述',
    fr: 'Décrit',
    de: 'Beschrieben',
    ja: '説明あり',
  ),
  'Unspecified': _McpLocalizedFallback(
    zhHant: '未聲明',
    fr: 'Non spécifié',
    de: 'Nicht angegeben',
    ja: '未指定',
  ),
  'Array': _McpLocalizedFallback(
    zhHant: '陣列',
    fr: 'Tableau',
    de: 'Array',
    ja: '配列',
  ),
  'Text': _McpLocalizedFallback(
    zhHant: '文字',
    fr: 'Texte',
    de: 'Text',
    ja: 'テキスト',
  ),
  'Number': _McpLocalizedFallback(
    zhHant: '數字',
    fr: 'Nombre',
    de: 'Zahl',
    ja: '数値',
  ),
  'Boolean': _McpLocalizedFallback(
    zhHant: '布林值',
    fr: 'Booléen',
    de: 'Boolesch',
    ja: 'ブール値',
  ),
  'Enum': _McpLocalizedFallback(
    zhHant: '枚舉',
    fr: 'Énumération',
    de: 'Enum',
    ja: '列挙',
  ),
  'Raw Metadata': _McpLocalizedFallback(
    zhHant: '原始元資料',
    fr: 'Métadonnées brutes',
    de: 'Rohmetadaten',
    ja: '生メタデータ',
  ),
  'Default': _McpLocalizedFallback(
    zhHant: '預設',
    fr: 'Par défaut',
    de: 'Standard',
    ja: 'デフォルト',
  ),
  'Checking Health': _McpLocalizedFallback(
    zhHant: '健康檢測中',
    fr: 'Contrôle de santé',
    de: 'Integrität wird geprüft',
    ja: 'ヘルス確認中',
  ),
  'Unchecked': _McpLocalizedFallback(
    zhHant: '未檢測',
    fr: 'Non vérifié',
    de: 'Nicht geprüft',
    ja: '未確認',
  ),
  'Service Disabled': _McpLocalizedFallback(
    zhHant: '服務已禁用',
    fr: 'Service désactivé',
    de: 'Dienst deaktiviert',
    ja: 'サービス無効',
  ),
  'Health Not Checked': _McpLocalizedFallback(
    zhHant: '尚未檢測健康狀態',
    fr: 'Santé non vérifiée',
    de: 'Integrität nicht geprüft',
    ja: 'ヘルス未確認',
  ),
  'Service Healthy': _McpLocalizedFallback(
    zhHant: '服務健康',
    fr: 'Service sain',
    de: 'Dienst fehlerfrei',
    ja: 'サービス正常',
  ),
  'Service Unhealthy': _McpLocalizedFallback(
    zhHant: '服務異常',
    fr: 'Service dégradé',
    de: 'Dienst fehlerhaft',
    ja: 'サービス異常',
  ),
};

/// 把 UTC 时间戳渲染成「12 秒前 / 3 分钟前 / 4 小时前」形式。
String _formatRelativePast(BuildContext context, DateTime utc) {
  final diff = DateTime.now().toUtc().difference(utc);
  final l10n = AppLocalizations.of(context)!;
  if (diff.inSeconds < 5) return l10n.mcpRelativeJustNow;
  if (diff.inSeconds < 60) {
    final s = diff.inSeconds;
    return l10n.mcpRelativeSecondsAgo(s);
  }
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return l10n.mcpRelativeMinutesAgo(m);
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return l10n.mcpRelativeHoursAgo(h);
  }
  final d = diff.inDays;
  return l10n.mcpRelativeDaysAgo(d);
}

/// 判断 STDIO MCP 服务是否为 npx 类型。
/// 兼容两种用户输入习惯：
///   1. command="npx", args=["@playwright/mcp"]
///   2. command="npx chrome-devtools-mcp@latest", args=["--autoConnect"]
/// 同时支持绝对路径形式（如 /opt/homebrew/bin/npx）。
bool _isNpxCommand(McpServer server) {
  final cmd = server.command.trim();
  // 精确匹配或路径结尾匹配
  if (cmd == 'npx' || cmd.endsWith('/npx')) return true;
  // 用户把整条命令粘进 command 字段：第一个 token 是 npx
  final firstToken = cmd.split(RegExp(r'\s+')).first;
  return firstToken == 'npx' || firstToken.endsWith('/npx');
}

/// 判断 STDIO MCP 服务是否为 uvx 类型（Python 包管理器）。
bool _isUvxCommand(McpServer server) {
  final cmd = server.command.trim();
  if (cmd == 'uvx' || cmd.endsWith('/uvx')) return true;
  final firstToken = cmd.split(RegExp(r'\s+')).first;
  return firstToken == 'uvx' || firstToken.endsWith('/uvx');
}

/// 判断 STDIO MCP 服务是否为包管理器类型（npx 或 uvx），支持依赖管理功能。
bool _isPackageManagerCommand(McpServer server) {
  return _isNpxCommand(server) || _isUvxCommand(server);
}

/// 从 STDIO MCP 服务配置中提取包名。
/// 兼容两种输入习惯：
///   1. command="npx", args=["@playwright/mcp", "--headless"]  → "@playwright/mcp"
///   2. command="npx chrome-devtools-mcp@latest", args=["--autoConnect"] → "chrome-devtools-mcp@latest"
String? _extractPackageName(McpServer server) {
  final cmd = server.command.trim();
  final tokens = cmd.split(RegExp(r'\s+'));
  // 如果 command 字段包含多个 token，第二个 token 就是包名
  if (tokens.length > 1) return tokens[1];
  // 否则从 args 的第一个非 flag 参数提取
  for (final arg in server.args) {
    final trimmed = arg.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('-')) continue; // 跳过 flag 参数
    return trimmed;
  }
  return null;
}

/// 把未来 UTC 时间戳渲染成「约 12 秒后 / 约 3 分钟后」形式；过期则显示「即将开始」。
String _formatRelativeFuture(BuildContext context, DateTime utc) {
  final diff = utc.difference(DateTime.now().toUtc());
  final l10n = AppLocalizations.of(context)!;
  if (diff.inSeconds <= 0) return l10n.mcpRelativeImminent;
  if (diff.inSeconds < 60) {
    final s = diff.inSeconds;
    return l10n.mcpRelativeInSeconds(s);
  }
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return l10n.mcpRelativeInMinutes(m);
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return l10n.mcpRelativeInHours(h);
  }
  final d = diff.inDays;
  return l10n.mcpRelativeInDays(d);
}

/// Live view of the data every insight dialog renders against. The dialog
/// watches [McpController], so these values refresh in place while it is open.
class _McpOpsInsightData {
  const _McpOpsInsightData({
    required this.snapshot,
    required this.audit,
    required this.config,
    required this.stats,
    required this.servers,
  });

  final McpOpsRuntimeSnapshot snapshot;
  final List<McpOpsAuditEntry> audit;
  final McpOpsConfig config;
  final _McpOpsDashboardStats stats;
  final List<McpServer> servers;
}

typedef _McpOpsInsightSections =
    List<Widget> Function(BuildContext context, _McpOpsInsightData data);

/// Structured drill-down dialog shared by every clickable ops card. Reuses the
/// audit dialog's animated shell so entrance/exit motion follows the global
/// dialog animation setting, and recomputes its body from the live controller.
class _McpOpsInsightDialog extends StatelessWidget {
  const _McpOpsInsightDialog({
    required this.icon,
    required this.title,
    required this.config,
    required this.sections,
    this.subtitle = '',
    this.tone,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final McpOpsConfig config;
  final _McpOpsInsightSections sections;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<McpController>();
    final snapshot = controller.opsSnapshot;
    final audit = controller.opsAuditEntries;
    final data = _McpOpsInsightData(
      snapshot: snapshot,
      audit: audit,
      config: config,
      stats: _McpOpsDashboardStats.from(
        snapshot: snapshot,
        auditEntries: audit,
      ),
      servers: controller.servers,
    );
    final cs = Theme.of(context).colorScheme;
    final accent = tone ?? cs.primary;
    final children = sections(context, data);
    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: 940,
      maxHeight: 800,
      maxWidthFraction: 0.94,
      maxHeightFraction: 0.92,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_mcpOpsOuterRadius),
      ),
      child: _McpOpsDialogSurface(
        child: _McpOpsConsoleShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: accent.withValues(alpha: 0.26)),
                    ),
                    child: Icon(icon, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (subtitle.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: SingleChildScrollView(
                  physics: openHandDialogAwareScrollPhysics(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i != 0) const SizedBox(height: _mcpOpsGridGap),
                        children[i],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Panel wrapping an inline KPI grid — the workhorse for dialog headers.
class _McpOpsStatPanel extends StatelessWidget {
  const _McpOpsStatPanel({
    required this.icon,
    required this.title,
    required this.tiles,
  });

  final IconData icon;
  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return _McpOpsPanel(
      icon: icon,
      title: title,
      child: _McpOpsMetricGrid(children: tiles),
    );
  }
}

/// Full breakdown of a distribution map — every entry ranked with share bars,
/// unlike the dashboard cards which only surface the top five.
class _McpOpsBarPanel extends StatelessWidget {
  const _McpOpsBarPanel({
    required this.icon,
    required this.title,
    required this.values,
  });

  final IconData icon;
  final String title;
  final Map<String, int> values;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sorted = values.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<int>(0, (sum, entry) => sum + entry.value);
    final palette = _mcpOpsChartPalette(cs);
    return _McpOpsPanel(
      icon: icon,
      title: title,
      trailing: sorted.isEmpty
          ? null
          : _McpOpsStatusChip(
              icon: Icons.functions_rounded,
              label: '$total',
              color: cs.primary,
            ),
      child: sorted.isEmpty
          ? _McpOpsInsightEmpty(
              label: _localizedText(
                context,
                zh: '暂无样本数据',
                en: 'No samples yet',
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < sorted.length; i++)
                  _McpOpsDistributionRow(
                    label: sorted[i].key,
                    value: sorted[i].value,
                    total: total,
                    color: palette[i % palette.length],
                    showPercent: true,
                  ),
              ],
            ),
    );
  }
}

/// Trend chart with a per-minute breakdown table, used by the request/latency
/// drill-downs.
class _McpOpsTrendDetailPanel extends StatelessWidget {
  const _McpOpsTrendDetailPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.series,
    required this.minutes,
    required this.columns,
    required this.emptyLabel,
    this.valueSuffix = '',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<_McpOpsChartSeries> series;
  final List<DateTime> minutes;
  final List<String> columns;
  final String emptyLabel;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxValue = series
        .expand((item) => item.values)
        .fold<double>(0, (max, value) => math.max(max, value));
    final rows = <TableRow>[];
    for (var i = minutes.length - 1; i >= 0; i--) {
      final hasData = series.any((s) => i < s.values.length && s.values[i] > 0);
      if (!hasData) continue;
      rows.add(
        TableRow(
          children: [
            _McpOpsTableCell(text: formatHourMinute(minutes[i].toLocal())),
            for (final s in series)
              _McpOpsTableCell(
                text: i < s.values.length
                    ? '${s.values[i].round()}$valueSuffix'
                    : '-',
                color: s.color,
                alignEnd: true,
              ),
          ],
        ),
      );
    }
    return _McpOpsPanel(
      icon: icon,
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 208,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _McpOpsSmoothLineChartPainter(
                  series: series,
                  gridColor: cs.outlineVariant.withValues(alpha: 0.46),
                  labelColor: cs.onSurfaceVariant,
                  emptyLabel: maxValue <= 0 ? emptyLabel : '',
                  valueSuffix: valueSuffix,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final item in series)
                _McpOpsLegendPill(label: item.label, color: item.color),
            ],
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 14),
            Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(1.2),
              },
              children: [
                TableRow(
                  children: [
                    _McpOpsTableCell(
                      text: _localizedText(context, zh: '时间', en: 'Time'),
                      header: true,
                    ),
                    for (final column in columns)
                      _McpOpsTableCell(
                        text: column,
                        header: true,
                        alignEnd: true,
                      ),
                  ],
                ),
                ...rows,
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact list of audit entries filtered to a single lens (blocked, failed,
/// write, …). Shows a status-colored strip per row.
class _McpOpsLogListPanel extends StatelessWidget {
  const _McpOpsLogListPanel({
    required this.icon,
    required this.title,
    required this.entries,
    required this.emptyLabel,
    this.showReason = false,
    this.maxEntries = 30,
  });

  final IconData icon;
  final String title;
  final List<McpOpsAuditEntry> entries;
  final String emptyLabel;
  final bool showReason;
  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final shown = entries.take(maxEntries).toList(growable: false);
    return _McpOpsPanel(
      icon: icon,
      title: title,
      trailing: entries.isEmpty
          ? null
          : _McpOpsStatusChip(
              icon: Icons.list_alt_rounded,
              label: '${entries.length}',
              color: cs.primary,
            ),
      child: shown.isEmpty
          ? _McpOpsInsightEmpty(label: emptyLabel)
          : Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i != 0)
                    Divider(
                      height: 16,
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  _McpOpsLogRow(entry: shown[i], showReason: showReason),
                ],
              ],
            ),
    );
  }
}

class _McpOpsLogRow extends StatelessWidget {
  const _McpOpsLogRow({required this.entry, this.showReason = false});

  final McpOpsAuditEntry entry;
  final bool showReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final statusColor = entry.failed
        ? (entry.status == 'blocked' ? OpenHandStatusColors.warning : cs.error)
        : OpenHandStatusColors.success;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 38,
          margin: const EdgeInsets.only(top: 2, right: 10),
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.toolName.trim().isEmpty
                          ? entry.endpoint
                          : entry.toolName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatMonthDayHms(entry.timestamp.toLocal()),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _McpOpsMiniTag(
                    icon: Icons.public_rounded,
                    label: entry.ipAddress,
                  ),
                  _McpOpsMiniTag(
                    icon: Icons.devices_rounded,
                    label: entry.clientName,
                  ),
                  _McpOpsMiniTag(
                    icon: Icons.timer_rounded,
                    label: '${entry.durationMs}ms',
                  ),
                  if (entry.inboundBytes > 0 || entry.outboundBytes > 0)
                    _McpOpsMiniTag(
                      icon: Icons.swap_vert_rounded,
                      label:
                          '${formatByteSize(entry.inboundBytes)} / ${formatByteSize(entry.outboundBytes)}',
                    ),
                ],
              ),
              if (showReason && entry.errorMessage.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  entry.errorMessage.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _McpOpsMiniTag extends StatelessWidget {
  const _McpOpsMiniTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _McpOpsTableCell extends StatelessWidget {
  const _McpOpsTableCell({
    required this.text,
    this.header = false,
    this.alignEnd = false,
    this.color,
  });

  final String text;
  final bool header;
  final bool alignEnd;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: Text(
        text,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style:
            (header ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
                ?.copyWith(
                  color: color ?? (header ? cs.onSurfaceVariant : null),
                  fontWeight: header ? FontWeight.w800 : FontWeight.w600,
                ),
      ),
    );
  }
}

class _McpOpsInsightEmpty extends StatelessWidget {
  const _McpOpsInsightEmpty({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// Non-tappable metric tile for use inside insight dialogs.
_McpOpsMetricTile _mcpOpsInsightTile(
  IconData icon,
  String label,
  String value, {
  String? helper,
  Color? color,
}) {
  return _McpOpsMetricTile(
    icon: icon,
    label: label,
    value: value,
    helper: helper,
    color: color,
  );
}

/// Resolves the icon/title/tone and section builder for a drill-down [kind].
/// Kept as one dispatcher so every card's dialog shares identical structure.
_McpOpsInsightSpec _mcpOpsInsightSpec(
  BuildContext context,
  _McpOpsInsightKind kind,
) {
  final cs = Theme.of(context).colorScheme;
  const success = OpenHandStatusColors.success;
  const warning = OpenHandStatusColors.warning;

  switch (kind) {
    case _McpOpsInsightKind.connections:
      return _McpOpsInsightSpec(
        icon: Icons.link_rounded,
        title: _localizedText(context, zh: '连接明细', en: 'Connections'),
        subtitle: _localizedText(
          context,
          zh: '实时会话 · 活跃与空闲连接',
          en: 'Live sessions · active and idle',
        ),
        sections: (context, data) {
          final s = data.snapshot;
          return [
            _McpOpsStatPanel(
              icon: Icons.hub_rounded,
              title: _localizedText(context, zh: '连接概览', en: 'Overview'),
              tiles: [
                _mcpOpsInsightTile(
                  Icons.link_rounded,
                  _localizedText(context, zh: '当前连接', en: 'Connections'),
                  '${s.currentConnections}',
                ),
                _mcpOpsInsightTile(
                  Icons.bolt_rounded,
                  _localizedText(context, zh: '活跃请求', en: 'Active'),
                  '${s.activeRequests}',
                  color: cs.primary,
                ),
                _mcpOpsInsightTile(
                  Icons.stream_rounded,
                  _localizedText(context, zh: '空闲流', en: 'Idle streams'),
                  '${s.idleStreams}',
                  helper: _localizedText(context, zh: 'SSE 长连接', en: 'SSE'),
                ),
                _mcpOpsInsightTile(
                  Icons.badge_rounded,
                  _localizedText(context, zh: '会话总数', en: 'Sessions'),
                  '${s.sessionCount}',
                ),
              ],
            ),
            _McpOpsBarPanel(
              icon: Icons.public_rounded,
              title: _localizedText(context, zh: '来源 IP 分布', en: 'IP Mix'),
              values: s.ipDistribution,
            ),
            _McpOpsBarPanel(
              icon: Icons.devices_other_rounded,
              title: _localizedText(context, zh: '客户端分布', en: 'Client Mix'),
              values: s.clientDistribution,
            ),
            _McpOpsLogListPanel(
              icon: Icons.history_rounded,
              title: _localizedText(context, zh: '最近请求', en: 'Recent Requests'),
              entries: data.audit,
              emptyLabel: _localizedText(
                context,
                zh: '暂无请求记录',
                en: 'No requests yet',
              ),
            ),
          ];
        },
      );

    case _McpOpsInsightKind.activeRequests:
      return _McpOpsInsightSpec(
        icon: Icons.bolt_rounded,
        title: _localizedText(context, zh: '活跃请求', en: 'Active Requests'),
        subtitle: _localizedText(
          context,
          zh: '执行中的请求与近窗吞吐',
          en: 'In-flight requests and throughput',
        ),
        sections: (context, data) {
          final s = data.snapshot;
          return [
            _McpOpsStatPanel(
              icon: Icons.speed_rounded,
              title: _localizedText(context, zh: '实时吞吐', en: 'Throughput'),
              tiles: [
                _mcpOpsInsightTile(
                  Icons.bolt_rounded,
                  _localizedText(context, zh: '活跃请求', en: 'Active'),
                  '${s.activeRequests}',
                  color: cs.primary,
                ),
                _mcpOpsInsightTile(
                  Icons.link_rounded,
                  _localizedText(context, zh: '当前连接', en: 'Connections'),
                  '${s.currentConnections}',
                ),
                _mcpOpsInsightTile(
                  Icons.speed_rounded,
                  'RPM',
                  '${data.stats.currentRpm}',
                  helper: data.config.rpmLimit <= 0
                      ? _localizedText(context, zh: '不限流', en: 'Unlimited')
                      : '/ ${data.config.rpmLimit}',
                ),
                _mcpOpsInsightTile(
                  Icons.call_made_rounded,
                  _localizedText(context, zh: '近窗请求', en: 'Window'),
                  '${data.stats.windowRequestCount}',
                ),
              ],
            ),
            _McpOpsBarPanel(
              icon: Icons.account_tree_rounded,
              title: _localizedText(context, zh: '请求方法分布', en: 'Method Mix'),
              values: s.requestDistribution,
            ),
            _McpOpsLogListPanel(
              icon: Icons.history_rounded,
              title: _localizedText(context, zh: '最近调用', en: 'Recent Calls'),
              entries: data.audit,
              emptyLabel: _localizedText(
                context,
                zh: '暂无调用记录',
                en: 'No calls yet',
              ),
            ),
          ];
        },
      );

    case _McpOpsInsightKind.requests:
      return _McpOpsInsightSpec(
        icon: Icons.call_made_rounded,
        title: _localizedText(context, zh: '请求总览', en: 'Requests'),
        subtitle: _localizedText(
          context,
          zh: '累计请求与成功/拦截/失败构成',
          en: 'Totals and success/blocked/failed mix',
        ),
        sections: (context, data) => [
          _McpOpsStatPanel(
            icon: Icons.analytics_rounded,
            title: _localizedText(context, zh: '请求构成', en: 'Composition'),
            tiles: _mcpOpsOutcomeTiles(context, data),
          ),
          _mcpOpsRequestTrendPanel(context, data),
          _McpOpsBarPanel(
            icon: Icons.account_tree_rounded,
            title: _localizedText(context, zh: '请求方法分布', en: 'Method Mix'),
            values: data.snapshot.requestDistribution,
          ),
          _McpOpsLogListPanel(
            icon: Icons.history_rounded,
            title: _localizedText(context, zh: '最近请求', en: 'Recent Requests'),
            entries: data.audit,
            emptyLabel: _localizedText(
              context,
              zh: '暂无请求记录',
              en: 'No requests yet',
            ),
          ),
        ],
      );

    case _McpOpsInsightKind.succeeded:
      return _McpOpsInsightSpec(
        icon: Icons.task_alt_rounded,
        title: _localizedText(context, zh: '成功请求', en: 'Succeeded'),
        tone: success,
        sections: (context, data) => [
          _McpOpsStatPanel(
            icon: Icons.verified_rounded,
            title: _localizedText(context, zh: '成功概览', en: 'Overview'),
            tiles: _mcpOpsOutcomeTiles(context, data),
          ),
          _McpOpsBarPanel(
            icon: Icons.donut_small_rounded,
            title: _localizedText(context, zh: '状态分布', en: 'Status Mix'),
            values: data.stats.statusDistribution(context),
          ),
          _mcpOpsRequestTrendPanel(context, data),
        ],
      );

    case _McpOpsInsightKind.blocked:
      return _McpOpsInsightSpec(
        icon: Icons.shield_rounded,
        title: _localizedText(context, zh: '拦截明细', en: 'Blocked'),
        tone: warning,
        sections: (context, data) {
          final logs = data.audit
              .where((entry) => entry.status == 'blocked')
              .toList(growable: false);
          return [
            _McpOpsStatPanel(
              icon: Icons.gpp_maybe_rounded,
              title: _localizedText(context, zh: '拦截概览', en: 'Overview'),
              tiles: [
                _mcpOpsInsightTile(
                  Icons.shield_rounded,
                  _localizedText(context, zh: '拦截数量', en: 'Blocked'),
                  '${data.snapshot.blockedTotal}',
                  helper: '${data.stats.blockedRateLabel}%',
                  color: warning,
                ),
                _mcpOpsInsightTile(
                  Icons.policy_rounded,
                  _localizedText(context, zh: '访问策略', en: 'Policy'),
                  _networkModeLabel(context, data.config.networkMode),
                ),
                _mcpOpsInsightTile(
                  Icons.speed_rounded,
                  'RPM',
                  data.config.rpmLimit <= 0
                      ? '∞'
                      : '${data.config.rpmLimit}',
                  helper: _localizedText(context, zh: '限流阈值', en: 'Limit'),
                ),
              ],
            ),
            _McpOpsLogListPanel(
              icon: Icons.block_rounded,
              title: _localizedText(context, zh: '拦截记录', en: 'Blocked Log'),
              entries: logs,
              showReason: true,
              emptyLabel: _localizedText(
                context,
                zh: '暂无拦截记录',
                en: 'No blocked requests',
              ),
            ),
          ];
        },
      );

    case _McpOpsInsightKind.failures:
      return _McpOpsInsightSpec(
        icon: Icons.error_outline_rounded,
        title: _localizedText(context, zh: '失败明细', en: 'Failures'),
        tone: cs.error,
        sections: (context, data) {
          final logs = data.audit
              .where((entry) => entry.status == 'failed')
              .toList(growable: false);
          return [
            _McpOpsStatPanel(
              icon: Icons.report_rounded,
              title: _localizedText(context, zh: '失败概览', en: 'Overview'),
              tiles: [
                _mcpOpsInsightTile(
                  Icons.error_outline_rounded,
                  _localizedText(context, zh: '失败数量', en: 'Failures'),
                  '${data.snapshot.failedTotal}',
                  helper: '${data.stats.failedRateLabel}%',
                  color: cs.error,
                ),
                _mcpOpsInsightTile(
                  Icons.task_alt_rounded,
                  _localizedText(context, zh: '成功数量', en: 'Succeeded'),
                  '${data.stats.successTotal}',
                  color: success,
                ),
                _mcpOpsInsightTile(
                  Icons.call_made_rounded,
                  _localizedText(context, zh: '请求总数', en: 'Requests'),
                  '${data.snapshot.requestTotal}',
                ),
              ],
            ),
            _McpOpsLogListPanel(
              icon: Icons.bug_report_rounded,
              title: _localizedText(context, zh: '失败记录', en: 'Failure Log'),
              entries: logs,
              showReason: true,
              emptyLabel: _localizedText(
                context,
                zh: '暂无失败记录',
                en: 'No failures',
              ),
            ),
          ];
        },
      );

    case _McpOpsInsightKind.inbound:
      return _mcpOpsTrafficSpec(context, inbound: true);
    case _McpOpsInsightKind.outbound:
      return _mcpOpsTrafficSpec(context, inbound: false);

    case _McpOpsInsightKind.latency:
    case _McpOpsInsightKind.latencyTrend:
      return _McpOpsInsightSpec(
        icon: Icons.speed_rounded,
        title: _localizedText(context, zh: '耗时分析', en: 'Latency'),
        subtitle: _localizedText(
          context,
          zh: '平均耗时、尾延迟与最慢调用',
          en: 'Average, tail latency and slowest calls',
        ),
        sections: (context, data) {
          final slowest = [...data.audit]
            ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
          return [
            _McpOpsStatPanel(
              icon: Icons.timer_rounded,
              title: _localizedText(context, zh: '耗时概览', en: 'Overview'),
              tiles: [
                _mcpOpsInsightTile(
                  Icons.speed_rounded,
                  _localizedText(context, zh: '平均耗时', en: 'Average'),
                  '${data.snapshot.avgLatencyMs}ms',
                ),
                _mcpOpsInsightTile(
                  Icons.timeline_rounded,
                  'p95',
                  '${data.snapshot.p95LatencyMs}ms',
                  color: cs.tertiary,
                ),
              ],
            ),
            _mcpOpsLatencyTrendPanel(context, data),
            _McpOpsLogListPanel(
              icon: Icons.trending_down_rounded,
              title: _localizedText(context, zh: '最慢调用', en: 'Slowest Calls'),
              entries: slowest
                  .where((entry) => entry.durationMs > 0)
                  .toList(growable: false),
              maxEntries: 12,
              emptyLabel: _localizedText(
                context,
                zh: '暂无耗时样本',
                en: 'No latency samples',
              ),
            ),
          ];
        },
      );

    case _McpOpsInsightKind.allowedTime:
      return _McpOpsInsightSpec(
        icon: Icons.schedule_rounded,
        title: _localizedText(context, zh: '允许时间窗', en: 'Allowed Time'),
        sections: (context, data) => [
          _McpOpsPanel(
            icon: Icons.schedule_rounded,
            title: _localizedText(context, zh: '放行时间段', en: 'Windows'),
            subtitle: _localizedText(
              context,
              zh: '仅在以下本地时段放行外部调用',
              en: 'External calls allowed only within these local windows',
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final window in data.config.allowedTimeWindows)
                  _McpOpsStatusChip(
                    icon: Icons.check_circle_rounded,
                    label: window,
                    color: cs.primary,
                  ),
              ],
            ),
          ),
        ],
      );

    case _McpOpsInsightKind.memory:
      return _McpOpsInsightSpec(
        icon: Icons.memory_rounded,
        title: _localizedText(context, zh: '资源占用', en: 'Resource Usage'),
        sections: (context, data) => [
          _McpOpsStatPanel(
            icon: Icons.memory_rounded,
            title: _localizedText(context, zh: '进程资源', en: 'Process'),
            tiles: [
              _mcpOpsInsightTile(
                Icons.memory_rounded,
                _localizedText(context, zh: '内存占用', en: 'Memory'),
                formatByteSize(data.snapshot.memoryRssBytes),
                helper: _localizedText(context, zh: '当前 RSS', en: 'Current RSS'),
              ),
              _mcpOpsInsightTile(
                Icons.link_rounded,
                _localizedText(context, zh: '当前连接', en: 'Connections'),
                '${data.snapshot.currentConnections}',
              ),
              _mcpOpsInsightTile(
                Icons.swap_vert_rounded,
                _localizedText(context, zh: '进出口流量', en: 'Traffic'),
                '${formatByteSize(data.snapshot.inboundBytes)} / ${formatByteSize(data.snapshot.outboundBytes)}',
              ),
            ],
          ),
        ],
      );

    case _McpOpsInsightKind.mcpCount:
      return _McpOpsInsightSpec(
        icon: Icons.hub_rounded,
        title: _localizedText(context, zh: '已注册 MCP', en: 'Registered MCP'),
        sections: (context, data) => [
          _McpOpsStatPanel(
            icon: Icons.dns_rounded,
            title: _localizedText(context, zh: '服务概览', en: 'Overview'),
            tiles: [
              _mcpOpsInsightTile(
                Icons.hub_rounded,
                _localizedText(context, zh: '注册数量', en: 'Registered'),
                '${data.servers.length}',
              ),
              _mcpOpsInsightTile(
                Icons.toggle_on_rounded,
                _localizedText(context, zh: '已启用', en: 'Enabled'),
                '${data.servers.where((server) => server.enabled).length}',
                color: success,
              ),
            ],
          ),
          _McpOpsPanel(
            icon: Icons.list_alt_rounded,
            title: _localizedText(context, zh: '服务列表', en: 'Server List'),
            child: data.servers.isEmpty
                ? _McpOpsInsightEmpty(
                    label: _localizedText(
                      context,
                      zh: '暂无注册服务',
                      en: 'No servers registered',
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < data.servers.length; i++) ...[
                        if (i != 0)
                          Divider(
                            height: 16,
                            color: cs.outlineVariant.withValues(alpha: 0.4),
                          ),
                        _mcpOpsServerRow(context, data.servers[i]),
                      ],
                    ],
                  ),
          ),
        ],
      );

    case _McpOpsInsightKind.mutations:
      return _McpOpsInsightSpec(
        icon: Icons.change_circle_rounded,
        title: _localizedText(context, zh: '文件变动', en: 'File Mutations'),
        sections: (context, data) {
          final writes = data.audit
              .where(
                (entry) => entry.surface != 'policy' && !entry.failed,
              )
              .toList(growable: false);
          return [
            _McpOpsStatPanel(
              icon: Icons.edit_note_rounded,
              title: _localizedText(context, zh: '写入概览', en: 'Overview'),
              tiles: [
                _mcpOpsInsightTile(
                  Icons.change_circle_rounded,
                  _localizedText(context, zh: '成功写入', en: 'Mutations'),
                  '${data.snapshot.fileMutationCount}',
                ),
              ],
            ),
            _McpOpsLogListPanel(
              icon: Icons.edit_rounded,
              title: _localizedText(context, zh: '写工具调用', en: 'Write Calls'),
              entries: writes,
              emptyLabel: _localizedText(
                context,
                zh: '暂无写入记录',
                en: 'No write calls',
              ),
            ),
          ];
        },
      );

    case _McpOpsInsightKind.auditLogs:
      return _McpOpsInsightSpec(
        icon: Icons.inventory_2_rounded,
        title: _localizedText(context, zh: '审计日志', en: 'Audit Logs'),
        sections: (context, data) => [
          _McpOpsStatPanel(
            icon: Icons.receipt_long_rounded,
            title: _localizedText(context, zh: '日志概览', en: 'Overview'),
            tiles: [
              _mcpOpsInsightTile(
                Icons.inventory_2_rounded,
                _localizedText(context, zh: '日志总数', en: 'Total'),
                '${data.audit.length}',
              ),
              _mcpOpsInsightTile(
                Icons.task_alt_rounded,
                _localizedText(context, zh: '成功', en: 'Success'),
                '${data.audit.where((entry) => !entry.failed).length}',
                color: success,
              ),
              _mcpOpsInsightTile(
                Icons.shield_rounded,
                _localizedText(context, zh: '拦截', en: 'Blocked'),
                '${data.audit.where((entry) => entry.status == 'blocked').length}',
                color: warning,
              ),
              _mcpOpsInsightTile(
                Icons.error_outline_rounded,
                _localizedText(context, zh: '失败', en: 'Failed'),
                '${data.audit.where((entry) => entry.status == 'failed').length}',
                color: cs.error,
              ),
            ],
          ),
          _McpOpsLogListPanel(
            icon: Icons.history_rounded,
            title: _localizedText(context, zh: '最近日志', en: 'Recent Logs'),
            entries: data.audit,
            showReason: true,
            maxEntries: 40,
            emptyLabel: _localizedText(
              context,
              zh: '暂无审计日志',
              en: 'No audit logs',
            ),
          ),
        ],
      );

    case _McpOpsInsightKind.rpm:
      return _McpOpsInsightSpec(
        icon: Icons.speed_rounded,
        title: _localizedText(context, zh: '速率限制', en: 'Rate Limit'),
        sections: (context, data) => [
          _McpOpsStatPanel(
            icon: Icons.speed_rounded,
            title: _localizedText(context, zh: '限流概览', en: 'Overview'),
            tiles: [
              _mcpOpsInsightTile(
                Icons.speed_rounded,
                _localizedText(context, zh: '当前 RPM', en: 'Current RPM'),
                '${data.stats.currentRpm}',
              ),
              _mcpOpsInsightTile(
                Icons.flag_rounded,
                _localizedText(context, zh: '限流阈值', en: 'Limit'),
                data.config.rpmLimit <= 0
                    ? _localizedText(context, zh: '不限流', en: 'Unlimited')
                    : '${data.config.rpmLimit}',
              ),
            ],
          ),
          _mcpOpsRequestTrendPanel(context, data),
        ],
      );

    case _McpOpsInsightKind.accessPolicy:
      return _McpOpsInsightSpec(
        icon: Icons.security_rounded,
        title: _localizedText(context, zh: '访问策略', en: 'Access Policy'),
        sections: (context, data) {
          final config = data.config;
          return [
            _McpOpsStatPanel(
              icon: Icons.verified_user_rounded,
              title: _localizedText(context, zh: '策略概览', en: 'Overview'),
              tiles: [
                _mcpOpsInsightTile(
                  Icons.lan_rounded,
                  _localizedText(context, zh: '网络模式', en: 'Network'),
                  _networkModeLabel(context, config.networkMode),
                ),
                _mcpOpsInsightTile(
                  Icons.edit_rounded,
                  _localizedText(context, zh: '写入策略', en: 'Write'),
                  _writeModeLabel(context, config.writeMode),
                ),
                _mcpOpsInsightTile(
                  Icons.key_rounded,
                  _localizedText(context, zh: '令牌校验', en: 'Token'),
                  config.requireAuthToken
                      ? _localizedText(context, zh: '开启', en: 'On')
                      : _localizedText(context, zh: '关闭', en: 'Off'),
                ),
              ],
            ),
            _McpOpsDetailSection(
              title: _localizedText(context, zh: '策略明细', en: 'Details'),
              rows: {
                _localizedText(context, zh: '调用模式', en: 'Invocation'):
                    _invocationModeLabel(context, config.invocationMode),
                _localizedText(context, zh: '允许客户端', en: 'Clients'):
                    config.allowedClients.isEmpty
                    ? _localizedText(context, zh: '全部', en: 'All')
                    : config.allowedClients.join(', '),
                _localizedText(context, zh: '允许网段', en: 'IP CIDR'):
                    config.allowedIpCidrs.isEmpty
                    ? _localizedText(context, zh: '未限制', en: 'Any')
                    : config.allowedIpCidrs.join(', '),
                _localizedText(context, zh: '工作区', en: 'Workspace'):
                    config.workspaceRoot.trim().isEmpty
                    ? _localizedText(context, zh: '默认', en: 'Default')
                    : config.workspaceRoot,
              },
            ),
          ];
        },
      );

    case _McpOpsInsightKind.requestTrend:
      return _McpOpsInsightSpec(
        icon: Icons.show_chart_rounded,
        title: _localizedText(context, zh: '请求趋势', en: 'Request Trend'),
        subtitle: _localizedText(
          context,
          zh: '最近 12 分钟成功/拦截/失败',
          en: 'Last 12 minutes success/blocked/failed',
        ),
        sections: (context, data) => [
          _mcpOpsRequestTrendPanel(context, data),
          _McpOpsBarPanel(
            icon: Icons.donut_small_rounded,
            title: _localizedText(context, zh: '状态分布', en: 'Status Mix'),
            values: data.stats.statusDistribution(context),
          ),
          _McpOpsBarPanel(
            icon: Icons.account_tree_rounded,
            title: _localizedText(context, zh: '请求方法分布', en: 'Method Mix'),
            values: data.snapshot.requestDistribution,
          ),
        ],
      );

    case _McpOpsInsightKind.statusMix:
      return _McpOpsInsightSpec(
        icon: Icons.donut_small_rounded,
        title: _localizedText(context, zh: '状态分布', en: 'Status Mix'),
        sections: (context, data) => [
          _McpOpsStatPanel(
            icon: Icons.pie_chart_rounded,
            title: _localizedText(context, zh: '状态概览', en: 'Overview'),
            tiles: _mcpOpsOutcomeTiles(context, data),
          ),
          _McpOpsBarPanel(
            icon: Icons.donut_small_rounded,
            title: _localizedText(context, zh: '状态占比', en: 'Status Share'),
            values: data.stats.statusDistribution(context),
          ),
          _mcpOpsRequestTrendPanel(context, data),
        ],
      );

    case _McpOpsInsightKind.ipMix:
      return _mcpOpsDistributionSpec(
        context,
        icon: Icons.public_rounded,
        title: _localizedText(context, zh: '请求 IP 分布', en: 'IP Mix'),
        selector: (data) => data.snapshot.ipDistribution,
      );
    case _McpOpsInsightKind.clientMix:
      return _mcpOpsDistributionSpec(
        context,
        icon: Icons.devices_other_rounded,
        title: _localizedText(context, zh: '客户端分布', en: 'Client Mix'),
        selector: (data) => data.snapshot.clientDistribution,
      );
    case _McpOpsInsightKind.requestMix:
      return _mcpOpsDistributionSpec(
        context,
        icon: Icons.account_tree_rounded,
        title: _localizedText(context, zh: '请求方法分布', en: 'Request Mix'),
        selector: (data) => data.snapshot.requestDistribution,
      );
    case _McpOpsInsightKind.protocolMix:
      return _mcpOpsDistributionSpec(
        context,
        icon: Icons.api_rounded,
        title: _localizedText(context, zh: '协议分布', en: 'Protocol Mix'),
        selector: (data) => data.snapshot.protocolDistribution,
      );
  }
}

/// Shared success/blocked/failed KPI tiles.
List<Widget> _mcpOpsOutcomeTiles(
  BuildContext context,
  _McpOpsInsightData data,
) {
  final cs = Theme.of(context).colorScheme;
  return [
    _mcpOpsInsightTile(
      Icons.call_made_rounded,
      _localizedText(context, zh: '请求总数', en: 'Requests'),
      '${data.snapshot.requestTotal}',
    ),
    _mcpOpsInsightTile(
      Icons.task_alt_rounded,
      _localizedText(context, zh: '成功', en: 'Succeeded'),
      '${data.stats.successTotal}',
      helper: '${data.stats.successRateLabel}%',
      color: OpenHandStatusColors.success,
    ),
    _mcpOpsInsightTile(
      Icons.shield_rounded,
      _localizedText(context, zh: '拦截', en: 'Blocked'),
      '${data.snapshot.blockedTotal}',
      helper: '${data.stats.blockedRateLabel}%',
      color: OpenHandStatusColors.warning,
    ),
    _mcpOpsInsightTile(
      Icons.error_outline_rounded,
      _localizedText(context, zh: '失败', en: 'Failed'),
      '${data.snapshot.failedTotal}',
      helper: '${data.stats.failedRateLabel}%',
      color: cs.error,
    ),
  ];
}

/// Request trend chart + per-minute table.
Widget _mcpOpsRequestTrendPanel(
  BuildContext context,
  _McpOpsInsightData data,
) {
  return _McpOpsTrendDetailPanel(
    icon: Icons.show_chart_rounded,
    title: _localizedText(context, zh: '请求趋势', en: 'Request Trend'),
    subtitle: _localizedText(
      context,
      zh: '最近 12 分钟 · 成功/拦截/失败',
      en: 'Last 12 minutes · success/blocked/failed',
    ),
    series: data.stats.requestTrendSeries(context),
    minutes: data.stats.bucketMinutes,
    columns: [
      _localizedText(context, zh: '成功', en: 'Success'),
      _localizedText(context, zh: '拦截', en: 'Blocked'),
      _localizedText(context, zh: '失败', en: 'Failed'),
    ],
    emptyLabel: _localizedText(context, zh: '等待请求样本', en: 'Waiting for traffic'),
  );
}

/// Latency trend chart + per-minute table.
Widget _mcpOpsLatencyTrendPanel(
  BuildContext context,
  _McpOpsInsightData data,
) {
  return _McpOpsTrendDetailPanel(
    icon: Icons.timeline_rounded,
    title: _localizedText(context, zh: '耗时曲线', en: 'Latency Curve'),
    subtitle: _localizedText(
      context,
      zh: '平均耗时与尾延迟',
      en: 'Average and tail latency',
    ),
    series: data.stats.latencyTrendSeries(context),
    minutes: data.stats.bucketMinutes,
    valueSuffix: 'ms',
    columns: [
      _localizedText(context, zh: '平均', en: 'Average'),
      'p95',
    ],
    emptyLabel: _localizedText(context, zh: '暂无耗时样本', en: 'No latency samples'),
  );
}

/// Inbound/outbound traffic drill-down.
_McpOpsInsightSpec _mcpOpsTrafficSpec(
  BuildContext context, {
  required bool inbound,
}) {
  return _McpOpsInsightSpec(
    icon: inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
    title: inbound
        ? _localizedText(context, zh: '入口流量', en: 'Inbound Traffic')
        : _localizedText(context, zh: '出口流量', en: 'Outbound Traffic'),
    sections: (context, data) {
      final s = data.snapshot;
      final bytes = inbound ? s.inboundBytes : s.outboundBytes;
      final total = math.max(1, s.requestTotal);
      final avg = bytes ~/ total;
      final logs = [...data.audit]..sort(
        (a, b) => (inbound ? b.inboundBytes : b.outboundBytes).compareTo(
          inbound ? a.inboundBytes : a.outboundBytes,
        ),
      );
      return [
        _McpOpsStatPanel(
          icon: Icons.swap_vert_rounded,
          title: _localizedText(context, zh: '流量概览', en: 'Overview'),
          tiles: [
            _mcpOpsInsightTile(
              inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
              inbound
                  ? _localizedText(context, zh: '入口总量', en: 'Inbound')
                  : _localizedText(context, zh: '出口总量', en: 'Outbound'),
              formatByteSize(bytes),
            ),
            _mcpOpsInsightTile(
              Icons.straighten_rounded,
              _localizedText(context, zh: '平均每请求', en: 'Per request'),
              formatByteSize(avg),
            ),
            _mcpOpsInsightTile(
              Icons.call_made_rounded,
              _localizedText(context, zh: '请求总数', en: 'Requests'),
              '${s.requestTotal}',
            ),
          ],
        ),
        _McpOpsLogListPanel(
          icon: Icons.data_usage_rounded,
          title: inbound
              ? _localizedText(context, zh: '入口占用最高', en: 'Top Inbound')
              : _localizedText(context, zh: '出口占用最高', en: 'Top Outbound'),
          entries: logs
              .where(
                (entry) =>
                    (inbound ? entry.inboundBytes : entry.outboundBytes) > 0,
              )
              .toList(growable: false),
          maxEntries: 12,
          emptyLabel: _localizedText(
            context,
            zh: '暂无流量样本',
            en: 'No traffic samples',
          ),
        ),
      ];
    },
  );
}

/// Generic distribution drill-down: full ranked bars + a donut summary.
_McpOpsInsightSpec _mcpOpsDistributionSpec(
  BuildContext context, {
  required IconData icon,
  required String title,
  required Map<String, int> Function(_McpOpsInsightData data) selector,
}) {
  return _McpOpsInsightSpec(
    icon: icon,
    title: title,
    sections: (context, data) => [
      _McpOpsBarPanel(
        icon: icon,
        title: title,
        values: selector(data),
      ),
    ],
  );
}

Widget _mcpOpsServerRow(BuildContext context, McpServer server) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final tone = server.enabled ? OpenHandStatusColors.success : cs.onSurfaceVariant;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 4,
        height: 34,
        margin: const EdgeInsets.only(top: 2, right: 10),
        decoration: BoxDecoration(
          color: tone,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              server.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (server.summary.trim().isNotEmpty)
              Text(
                server.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      _McpOpsStatusChip(
        icon: server.enabled
            ? Icons.check_circle_rounded
            : Icons.pause_circle_rounded,
        label: server.enabled
            ? _localizedText(context, zh: '启用', en: 'Enabled')
            : _localizedText(context, zh: '停用', en: 'Disabled'),
        color: tone,
      ),
    ],
  );
}
