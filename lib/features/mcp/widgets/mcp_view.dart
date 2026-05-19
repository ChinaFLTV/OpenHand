import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../../app/state/settings_controller.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/url_validation.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/appear_once.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/hover_lift.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../data/mcp_store.dart';
import '../mcp_controller.dart';
import '../model/mcp_server.dart';
import '../model/mcp_server_health.dart';
import '../model/mcp_tool.dart';
import '../service/mcp_stdio_process_manager.dart';
import '../service/mcp_tool_discovery_service.dart';
import 'mcp_keyword_index_progress_dialog.dart';
import 'mcp_stdio_dialogs.dart';

enum _McpCardAction { edit, delete, viewHistory, viewDetails }

const int _mcpToolPreviewCollapsedLimit = 8;
const int _mcpToolPreviewExpandedLimit = 48;

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

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 980;
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
                    OutlinedButton.icon(
                      onPressed: () => _openDirectory(context),
                      icon: const Icon(Icons.folder_open_rounded),
                      label: Text(l10n.mcpOpenDirectory),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showSnapshotExportMenu(context),
                      icon: const Icon(Icons.ios_share_rounded),
                      label: Text(
                        _localizedText(
                          context,
                          zh: '导出快照',
                          en: 'Export snapshot',
                        ),
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
                      label: Text(
                        _localizedText(
                          context,
                          zh: '探测详情',
                          en: 'Probe Details',
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _showServerDialog(context),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(l10n.mcpNewServer),
                    ),
                  ],
                );

                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _McpPageHeader(
                        title: l10n.mcpPageTitle,
                        subtitle: l10n.mcpPageSubtitle,
                      ),
                      const SizedBox(height: 20),
                      actions,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _McpPageHeader(
                        title: l10n.mcpPageTitle,
                        subtitle: l10n.mcpPageSubtitle,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Flexible(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: actions,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            if (!mcpEnabled) ...[
              _McpInfoCard(
                icon: Icons.toggle_off_rounded,
                title: l10n.mcpDisabledTitle,
                body: l10n.mcpDisabledBody,
              ),
              const SizedBox(height: 16),
            ],
            if (mcpSnapshot.persistenceIssue != null) ...[
              _McpPersistenceIssueCard(
                issue: mcpSnapshot.persistenceIssue!,
                onDismiss: mcpController.clearPersistenceIssue,
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                child: _buildBody(
                  context,
                  isLoading: mcpSnapshot.isLoading,
                  errorMessage: mcpSnapshot.errorMessage,
                  servers: mcpSnapshot.servers,
                ),
              ),
            ),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: HighlightPulse(signal: mcpController.saveSuccessSignal),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required bool isLoading,
    required String? errorMessage,
    required List<McpServer> servers,
  }) {
    final l10n = AppLocalizations.of(context)!;
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null) {
      return _McpStateCard(
        key: const ValueKey<String>('mcp-error'),
        icon: Icons.error_outline_rounded,
        title: l10n.mcpLoadFailedTitle,
        body: errorMessage,
        primaryActionLabel: l10n.mcpRefresh,
        onPrimaryAction: () => context.read<McpController>().refresh(),
      );
    }
    if (servers.isEmpty) {
      return _McpStateCard(
        key: const ValueKey<String>('mcp-empty'),
        icon: Icons.hub_outlined,
        title: l10n.mcpEmptyTitle,
        body: l10n.mcpEmptyBody,
      );
    }

    return ListView.separated(
      key: const ValueKey<String>('mcp-list'),
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
      itemCount: servers.length,
      cacheExtent: 600,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final server = servers[index];
        return SettingsAwareAppearOnce(
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
        );
      },
    );
  }

  Future<void> _openDirectory(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await context.read<McpController>().openStorageDirectory();
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, l10n.mcpOperationFailed, kind: _SnackKind.error);
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
      kind: _SnackKind.success,
    );
  }

  Future<void> _confirmDeleteServer(
    BuildContext context,
    McpServer server,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    // 对于 STDIO 类型的 npx/uvx 服务，询问是否同时清理底层包
    bool shouldCleanupDeps = false;
    final isNpxService =
        server.type == McpServerType.stdio && _isPackageManagerCommand(server);
    final npxPackageName = isNpxService ? _extractPackageName(server) : null;

    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(l10n.mcpDeleteConfirmTitle),
              content: Column(
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
                        isZh
                            ? '同时卸载底层包 ($npxPackageName)'
                            : 'Also uninstall package ($npxPackageName)',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      subtitle: Text(
                        isZh
                            ? '将卸载全局包并清理隔离缓存'
                            : 'Will uninstall global package and clean isolated cache',
                        style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                OpenHandDialogActionButton.secondary(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  label: l10n.commonCancel,
                ),
                OpenHandDialogActionButton.destructive(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  label: l10n.commonDelete,
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    final deleted = await context.read<McpController>().deleteServer(server);
    if (!context.mounted) {
      return;
    }
    if (!deleted) {
      _showSnackBar(context, l10n.mcpOperationFailed, kind: _SnackKind.error);
      return;
    }

    // 异步清理底层依赖包（不阻塞 UI）
    if (shouldCleanupDeps && isNpxService && npxPackageName != null) {
      final cleanPkg = npxPackageName.replaceAll(RegExp(r'@[^/]*$'), '');
      _cleanupNpxDependency(context, cleanPkg, server.name);
    }

    _showSnackBar(context, l10n.mcpServerDeleted, kind: _SnackKind.success);
  }

  /// 异步清理包管理器类型 MCP 服务的底层全局包和隔离缓存。
  Future<void> _cleanupNpxDependency(
    BuildContext context,
    String packageName,
    String serverName,
  ) async {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    try {
      // 1. 卸载全局包
      final result = await runTrackedProcessOrFailed('npm', [
        'uninstall',
        '-g',
        packageName,
      ], timeout: const Duration(seconds: 30));

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
        } catch (_) {}
      }

      if (!context.mounted) return;
      if (result.exitCode == 0) {
        _showSnackBar(
          context,
          isZh ? '$packageName 依赖已清理' : '$packageName dependency cleaned up',
          kind: _SnackKind.success,
        );
      } else {
        _showSnackBar(
          context,
          isZh
              ? '$packageName 清理失败：${result.stderr}'
              : '$packageName cleanup failed: ${result.stderr}',
          kind: _SnackKind.error,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(
        context,
        isZh ? '$packageName 清理异常：$e' : '$packageName cleanup error: $e',
        kind: _SnackKind.error,
      );
    }
  }

  /// 弹出半屏 ModalBottomSheet 展示该服务的最近 30 条探测历史，用 Selector 监听
  /// controller 的健康表，使得 reconnect / 自动健康检查刷新历史时抽屉内容会自动跟新。
  void _showHealthHistorySheet(BuildContext context, String serverName) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.78,
              minHeight: 240,
            ),
            child: Selector<McpController, McpServerHealth>(
              selector: (_, controller) =>
                  controller.healthStatusFor(serverName),
              builder: (context, health, _) => _McpHealthHistorySheet(
                serverName: serverName,
                health: health,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 服务详情抽屉：基于 healthStatus / toolCatalog 聚合可读统计（成功率、平均耗时、
  /// 最近成功 / 失败时间、Tool 数量），同时展示 server 的关键配置摘要。仅读，不可编辑。
  void _showServerDetailsSheet(BuildContext context, McpServer server) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
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
    final selected = await showMenu<_McpHistoryExportFormat>(
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
      text = const JsonEncoder.withIndent('  ').convert({
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

    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    final formatLabel = format == _McpHistoryExportFormat.json ? 'JSON' : 'CSV';
    _showSnackBar(
      context,
      _localizedText(
        context,
        zh: '已将 ${entries.length} 个服务的快照以 $formatLabel 复制到剪贴板',
        en: 'Copied snapshot of ${entries.length} servers as $formatLabel to clipboard',
      ),
      kind: _SnackKind.success,
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
    _showSnackBar(context, l10n.mcpOperationFailed, kind: _SnackKind.error);
  }

  void _showSnackBar(
    BuildContext context,
    String message, {
    _SnackKind kind = _SnackKind.info,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      switch (kind) {
        case _SnackKind.success:
          OpenHandSnackBar.show(
            context,
            messenger,
            OpenHandSnackBar.success(context, message),
          );
        case _SnackKind.error:
          OpenHandSnackBar.show(
            context,
            messenger,
            OpenHandSnackBar.error(context, message),
          );
        case _SnackKind.info:
          OpenHandSnackBar.show(
            context,
            messenger,
            SnackBar(content: Text(message)),
          );
      }
    });
  }
}

enum _SnackKind { info, success, error }

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
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
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
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 132,
                      height: 52,
                      child: FilledButton(
                        onPressed: _isSaving ? null : _handleSave,
                        child: Text(l10n.commonSave),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
      args: _argsController.text
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      headers: headerParseResult.headers,
    );

    late final bool saved;
    try {
      saved = await context.read<McpController>().saveServer(
        server,
        previousName: widget.initialServer?.name,
      );
    } catch (_) {
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

class _McpPageHeader extends StatelessWidget {
  const _McpPageHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _McpServerCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

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
                                        ? _truncateMiddle(liveLine)
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
                  if (healthStatus.hasError) ...[
                    const SizedBox(height: 14),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _McpInlineNotice(
                        icon: Icons.health_and_safety_outlined,
                        color: colorScheme.errorContainer,
                        foregroundColor: colorScheme.onErrorContainer,
                        message: healthStatus.errorMessage!,
                      ),
                    ),
                  ],
                  if (toolCatalog.hasError) ...[
                    const SizedBox(height: 14),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _McpInlineNotice(
                        icon: Icons.error_outline_rounded,
                        color: colorScheme.errorContainer,
                        foregroundColor: colorScheme.onErrorContainer,
                        message: toolCatalog.errorMessage!,
                      ),
                    ),
                  ],
                  if (toolCatalog.hasWarning) ...[
                    const SizedBox(height: 14),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: _McpInlineNotice(
                        icon: Icons.warning_amber_rounded,
                        color: colorScheme.tertiaryContainer,
                        foregroundColor: colorScheme.onTertiaryContainer,
                        message: toolCatalog.warningMessage!,
                      ),
                    ),
                  ],
                  if (toolCatalog.tools.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _McpToolPreview(server: server, toolCatalog: toolCatalog),
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
                    '(${_localizedText(context, zh: '成功 $successCount / 失败 $failureCount', en: '$successCount ok / $failureCount fail')})',
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
        final ratio = (p.latencyMs! / scaleMax).clamp(0.0, 1.0);
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
      pretty = const JsonEncoder.withIndent('  ').convert(payload);
    } catch (_) {
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
                    await Clipboard.setData(ClipboardData(text: pretty));
                    if (!context.mounted) return;
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    if (messenger == null) return;
                    OpenHandSnackBar.show(
                      context,
                      messenger,
                      OpenHandSnackBar.success(
                        context,
                        _localizedText(
                          context,
                          zh: '已复制 Schema',
                          en: 'Schema copied',
                        ),
                      ),
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
                PopupMenuButton<_McpHistoryExportFormat>(
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
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    final formatLabel = switch (format) {
      _McpHistoryExportFormat.markdown => 'Markdown',
      _McpHistoryExportFormat.json => 'JSON',
      _McpHistoryExportFormat.csv => 'CSV',
    };
    OpenHandSnackBar.show(
      context,
      messenger,
      OpenHandSnackBar.success(
        context,
        _localizedText(
          context,
          zh: '已将最近 ${probes.length} 条探测记录以 $formatLabel 格式复制到剪贴板',
          en: 'Copied ${probes.length} recent probes as $formatLabel to clipboard',
        ),
      ),
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
        final firstLine = probe.errorMessage!
            .split('\n')
            .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
        if (firstLine.isNotEmpty) {
          buffer.write(' — ${firstLine.trim()}');
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
    return const JsonEncoder.withIndent('  ').convert(payload);
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
    required this.reduceMotion,
  });

  final double value;
  final Color backgroundColor;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, animatedProgress, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: animatedProgress.clamp(0.0, 1.0).toDouble(),
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
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
                final progress = snap.autoProbeConcurrency <= 0
                    ? 0.0
                    : (snap.activeAutoProbeSlots / snap.autoProbeConcurrency)
                          .clamp(0.0, 1.0)
                          .toDouble();

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
                                  isZh ? 'MCP 探测详情' : 'MCP Probe Details',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  hasWork
                                      ? (isZh ? '探测池运行中' : 'Probe pool active')
                                      : (isZh ? '探测池空闲' : 'Probe pool idle'),
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
                      reduceMotion: MediaQuery.disableAnimationsOf(context),
                    ),
                    // 内容
                    Flexible(
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          // 探测池状态
                          _ProbeSection(
                            title: isZh ? '探测池状态' : 'Pool Status',
                            icon: Icons.commit_rounded,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _McpStatusChip(
                                    icon: Icons.commit_rounded,
                                    label: isZh
                                        ? '槽位 ${snap.activeAutoProbeSlots}/${snap.autoProbeConcurrency}'
                                        : 'Slots ${snap.activeAutoProbeSlots}/${snap.autoProbeConcurrency}',
                                  ),
                                  _McpStatusChip(
                                    icon: Icons.queue_rounded,
                                    label: isZh
                                        ? '排队 ${snap.queuedAutoProbeTasks}'
                                        : 'Queued ${snap.queuedAutoProbeTasks}',
                                  ),
                                  _McpStatusChip(
                                    icon: Icons.build_circle_outlined,
                                    label:
                                        'Tools ${snap.autoToolRefreshInProgress ? (isZh ? "运行中" : "running") : (isZh ? "空闲" : "idle")}',
                                  ),
                                  _McpStatusChip(
                                    icon: Icons.health_and_safety_outlined,
                                    label:
                                        '${isZh ? "健康" : "Health"} ${snap.autoHealthCheckInProgress ? (isZh ? "运行中" : "running") : (isZh ? "空闲" : "idle")}',
                                  ),
                                  if (snap.lastBatchProbeAt != null)
                                    _McpStatusChip(
                                      icon: Icons.history_rounded,
                                      label:
                                          '${isZh ? "上次" : "Last"} ${_formatRelativePast(context, snap.lastBatchProbeAt!)}',
                                    ),
                                  if (snap.nextScheduledProbeAt != null &&
                                      !hasWork)
                                    _McpStatusChip(
                                      icon: Icons.schedule_rounded,
                                      label:
                                          '${isZh ? "下次" : "Next"} ${_formatRelativeFuture(context, snap.nextScheduledProbeAt!)}',
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // 探测控制
                          _ProbeSection(
                            title: isZh ? '探测控制' : 'Probe Controls',
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
                                              const Duration(milliseconds: 200),
                                              () {
                                                controller.setPageActive(true);
                                              },
                                            );
                                          },
                                    icon: const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      isZh ? '强制触发探测' : 'Force Probe',
                                    ),
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
                                    label: Text(
                                      isZh ? '中断当前探测' : 'Stop Probing',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await controller.refresh();
                                      // refresh 完成后重新激活探测
                                      controller.setPageActive(true);
                                    },
                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      isZh ? '重载服务列表' : 'Reload Servers',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // 各服务探测状态
                          _ProbeSection(
                            title: isZh
                                ? '服务探测状态 (${snap.servers.length} 个服务)'
                                : 'Server Probe Status (${snap.servers.length} servers)',
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
                                    isZh ? '暂无服务' : 'No servers',
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final health = controller.healthStatusFor(server.name);
    final catalog = controller.toolCatalogFor(server.name);
    final isBusy = health.isChecking || catalog.isLoading;

    final statusColor = switch (health.status) {
      McpServerHealthStatus.healthy => const Color(0xFF16A34A),
      McpServerHealthStatus.unhealthy => colorScheme.error,
      McpServerHealthStatus.checking => const Color(0xFFF59E0B),
      McpServerHealthStatus.idle => colorScheme.onSurfaceVariant,
    };
    final statusLabel = switch (health.status) {
      McpServerHealthStatus.healthy => isZh ? '健康' : 'Healthy',
      McpServerHealthStatus.unhealthy => isZh ? '异常' : 'Unhealthy',
      McpServerHealthStatus.checking => isZh ? '检测中' : 'Checking',
      McpServerHealthStatus.idle => isZh ? '待检测' : 'Idle',
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
                  ? (isZh ? '点击禁用此服务探测' : 'Disable probing')
                  : (isZh ? '点击启用此服务探测' : 'Enable probing'),
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
            server.probeEnabled ? statusLabel : (isZh ? '不探测' : 'No probe'),
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
              '${catalog.tools.length} tools',
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
              tooltip: isZh ? '探测此服务' : 'Probe this server',
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Tooltip(
      message: enabled
          ? _localizedText(context, zh: '点击停用', en: 'Click to Disable')
          : _localizedText(context, zh: '点击启用', en: 'Click to Enable'),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: enabled ? 1.0 : 0.0),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220),
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
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: dotColor,
          shape: BoxShape.circle,
          border: Border.all(color: colorScheme.surface, width: 3),
          boxShadow: [
            BoxShadow(
              color: dotColor.withValues(alpha: 0.32),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _McpToolPreview extends StatefulWidget {
  const _McpToolPreview({required this.server, required this.toolCatalog});

  final McpServer server;
  final McpToolCatalog toolCatalog;

  @override
  State<_McpToolPreview> createState() => _McpToolPreviewState();
}

class _McpToolPreviewState extends State<_McpToolPreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tools = widget.toolCatalog.tools;
    final previewLimit = _expanded
        ? _mcpToolPreviewExpandedLimit
        : _mcpToolPreviewCollapsedLimit;
    final previewTools = tools.take(previewLimit).toList(growable: false);
    final hiddenToolCount = tools.length - previewTools.length;
    final canExpand = tools.length > _mcpToolPreviewCollapsedLimit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _localizedText(context, zh: '可用 Tools', en: 'Available Tools'),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (canExpand)
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
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
        // Wrap chip count animates smoothly when the user expands /
        // collapses the preview, instead of snapping to the new height.
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
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

class _McpInlineNotice extends StatelessWidget {
  const _McpInlineNotice({
    required this.icon,
    required this.color,
    required this.foregroundColor,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final Color foregroundColor;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foregroundColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: foregroundColor),
            ),
          ),
        ],
      ),
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

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 760),
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
                    key: ValueKey<String>(
                      'mcpToolDetailsDebugButton-${tool.id}',
                    ),
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
                        _McpInlineNotice(
                          icon: Icons.warning_amber_rounded,
                          color: colorScheme.tertiaryContainer,
                          foregroundColor: colorScheme.onTertiaryContainer,
                          message: tool.metadataWarning!,
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
  McpToolCallResult? _result;
  String? _errorMessage;
  bool _isRunning = false;

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
  }

  @override
  void dispose() {
    _argumentsController.dispose();
    super.dispose();
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
        arguments = Map<String, Object?>.from(decoded);
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

    setState(() {
      _isRunning = true;
      _result = null;
      _errorMessage = null;
    });

    try {
      final result = await widget.mcpController.callTool(
        serverName: widget.server.name,
        toolName: tool.id,
        arguments: arguments,
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

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 820),
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
                        DropdownButtonFormField<String>(
                          key: ValueKey<String>(
                            'mcpToolDebugToolField-${tool.id}',
                          ),
                          initialValue: tool.id,
                          decoration: InputDecoration(
                            labelText: _localizedText(
                              context,
                              zh: '选择 Tool',
                              en: 'Tool',
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          items: widget.toolCatalog.tools
                              .map(
                                (item) => DropdownMenuItem<String>(
                                  value: item.id,
                                  child: Text(item.name),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            McpTool? nextTool;
                            for (final item in widget.toolCatalog.tools) {
                              if (item.id == value) {
                                nextTool = item;
                                break;
                              }
                            }
                            if (nextTool == null) {
                              return;
                            }
                            setState(() {
                              _selectedTool = nextTool;
                              _result = null;
                              _errorMessage = null;
                              _argumentsController.text =
                                  _suggestedArgumentsJson(nextTool!);
                            });
                          },
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
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              key: const ValueKey<String>(
                                'mcpToolDebugRunButton',
                              ),
                              onPressed: _isRunning ? null : _runTool,
                              icon: _isRunning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                _isRunning
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
                            ),
                            OutlinedButton.icon(
                              onPressed: _isRunning
                                  ? null
                                  : () {
                                      setState(() {
                                        _argumentsController.text =
                                            _suggestedArgumentsJson(tool);
                                      });
                                    },
                              icon: const Icon(Icons.restart_alt_rounded),
                              label: Text(
                                _localizedText(
                                  context,
                                  zh: '恢复示例参数',
                                  en: 'Reset Sample',
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          _McpInlineNotice(
                            icon: Icons.error_outline_rounded,
                            color: colorScheme.errorContainer,
                            foregroundColor: colorScheme.onErrorContainer,
                            message: _errorMessage!,
                          ),
                        ],
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
                          if (_result!.rawResult != null)
                            _ToolSchemaPanel(schema: _result!.rawResult)
                          else
                            _ToolConsolePanel(content: _result!.outputText),
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
    final content = const JsonEncoder.withIndent(
      '  ',
    ).convert(_jsonFriendlyValue(schema));
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

class _McpStateCard extends StatelessWidget {
  const _McpStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(height: 18),
                Text(title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 10),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (primaryActionLabel != null && onPrimaryAction != null) ...[
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onPrimaryAction,
                    child: Text(primaryActionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _McpInfoCard extends StatelessWidget {
  const _McpInfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colorScheme.onSecondaryContainer),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    final colorScheme = Theme.of(context).colorScheme;
    final (title, body) = switch (issue.kind) {
      McpPersistenceIssueKind.recoveredInvalidFile => (
        l10n.mcpPersistenceRecoveredTitle,
        '${l10n.mcpPersistenceRecoveredBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
      McpPersistenceIssueKind.sanitizedInvalidContent => (
        l10n.mcpPersistenceSanitizedTitle,
        '${l10n.mcpPersistenceSanitizedBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
      McpPersistenceIssueKind.saveFailed => (
        l10n.mcpPersistenceSaveFailedTitle,
        '${l10n.mcpPersistenceSaveFailedBody}\n${OpenHandPaths.shortenHomePath(issue.filePath)}',
      ),
    };

    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onDismiss,
              child: Text(
                l10n.settingsPersistenceDismiss,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
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
    final values = typeValue
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
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
    final variantTypes = variants
        .map(_schemaType)
        .where((item) => item.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
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
  return const JsonEncoder.withIndent('  ').convert(suggested);
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

/// 把过长的进度行折成「头…尾」形式，避免 chip label 撑爆容器；
/// 阈值 max 是字符上限（含省略号），优先保留前缀。
String _truncateMiddle(String input, {int max = 36}) {
  if (input.length <= max) return input;
  final keepHead = (max * 0.6).round();
  final keepTail = max - keepHead - 1;
  if (keepTail <= 0) return '${input.substring(0, max - 1)}…';
  return '${input.substring(0, keepHead)}…${input.substring(input.length - keepTail)}';
}

String _formatStatusTime(BuildContext context, DateTime timestamp) {
  final localTime = timestamp.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return _localizedText(
    context,
    zh: '${twoDigits(localTime.month)}-${twoDigits(localTime.day)} ${twoDigits(localTime.hour)}:${twoDigits(localTime.minute)}',
    en: '${twoDigits(localTime.month)}-${twoDigits(localTime.day)} ${twoDigits(localTime.hour)}:${twoDigits(localTime.minute)}',
  );
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
    return Map<String, Object?>.from(value);
  }
  return null;
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
  if (value is bool) {
    return value;
  }
  final text = _readText(value).toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
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
}) {
  final languageCode = Localizations.localeOf(context).languageCode;
  return languageCode.startsWith('zh') ? zh : en;
}

/// 把 UTC 时间戳渲染成「12 秒前 / 3 分钟前 / 4 小时前」形式。
String _formatRelativePast(BuildContext context, DateTime utc) {
  final diff = DateTime.now().toUtc().difference(utc);
  final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
  if (diff.inSeconds < 5) return isZh ? '刚刚' : 'just now';
  if (diff.inSeconds < 60) {
    final s = diff.inSeconds;
    return isZh ? '$s 秒前' : '${s}s ago';
  }
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return isZh ? '$m 分钟前' : '${m}m ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return isZh ? '$h 小时前' : '${h}h ago';
  }
  final d = diff.inDays;
  return isZh ? '$d 天前' : '${d}d ago';
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
  final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
  if (diff.inSeconds <= 0) return isZh ? '即将开始' : 'imminent';
  if (diff.inSeconds < 60) {
    final s = diff.inSeconds;
    return isZh ? '约 $s 秒后' : 'in ${s}s';
  }
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return isZh ? '约 $m 分钟后' : 'in ${m}m';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return isZh ? '约 $h 小时后' : 'in ${h}h';
  }
  final d = diff.inDays;
  return isZh ? '约 $d 天后' : 'in ${d}d';
}
