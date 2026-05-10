import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/highlight_pulse.dart';
import '../../shared/widgets/micro_press_feedback.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import '../../shared/widgets/openhand_snack_bar.dart';
import 'model/plugin_info.dart';
import 'plugin_service_controller.dart';

void _showPluginSnackBar(BuildContext context, SnackBar snackBar) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  OpenHandSnackBar.show(context, messenger, snackBar);
}

class PluginServiceView extends StatefulWidget {
  const PluginServiceView({super.key});

  @override
  State<PluginServiceView> createState() => _PluginServiceViewState();
}

class _PluginServiceViewState extends State<PluginServiceView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<PluginServiceController>();
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');

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
                      onPressed: controller.isOperating
                          ? null
                          : controller.rescan,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(isZh ? '重新扫描' : 'Rescan'),
                    ),
                  ],
                );
                final header = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isZh ? '插件' : 'Plugins',
                      style: theme.textTheme.displaySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isZh
                          ? '管理可选插件的安装、更新与卸载。插件为 OpenHand 提供额外的运行时能力。'
                          : 'Manage optional plugin installation, updates, and removal.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header,
                      const SizedBox(height: 20),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
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
            Expanded(child: _buildBody(context, controller)),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: HighlightPulse(signal: controller.operationSuccessSignal),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, PluginServiceController controller) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    if (controller.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              isZh ? '正在扫描本机插件环境…' : 'Scanning local plugin environment…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (controller.errorMessage != null && controller.plugins.isEmpty) {
      return _PluginStateCard(
        icon: Icons.error_outline_rounded,
        title: isZh ? '插件扫描失败' : 'Plugin scan failed',
        body: controller.errorMessage!,
        action: TextButton.icon(
          onPressed: controller.rescan,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(isZh ? '重试' : 'Retry'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
      children: [
        if (controller.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ErrorBanner(
              message: controller.errorMessage!,
              onDismiss: controller.clearError,
            ),
          ),
        for (final plugin in controller.plugins) ...[
          _PluginCard(plugin: plugin, controller: controller),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 错误横幅
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
          ),
        ],
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final stateColor = switch (plugin.status) {
      PluginStatus.installed => const Color(0xFF16A34A),
      PluginStatus.error => theme.colorScheme.error,
      PluginStatus.installing ||
      PluginStatus.updating ||
      PluginStatus.uninstalling => const Color(0xFFF59E0B),
      PluginStatus.notInstalled => theme.colorScheme.onSurfaceVariant,
    };
    final statusLabel = switch (plugin.status) {
      PluginStatus.installed => isZh ? '已安装' : 'Installed',
      PluginStatus.notInstalled => isZh ? '未安装' : 'Not Installed',
      PluginStatus.installing => isZh ? '安装中…' : 'Installing…',
      PluginStatus.updating => isZh ? '更新中…' : 'Updating…',
      PluginStatus.uninstalling => isZh ? '卸载中…' : 'Uninstalling…',
      PluginStatus.error => isZh ? '错误' : 'Error',
    };
    final pluginIcon = switch (plugin.id) {
      'nodejs' => Icons.javascript_rounded,
      'playwright' => Icons.theaters_rounded,
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
                          Row(
                            children: [
                              Text(
                                plugin.name,
                                style: theme.textTheme.titleLarge,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: stateColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: stateColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            plugin.description,
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
            if (plugin.status == PluginStatus.error &&
                plugin.errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                plugin.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final isBusy = plugin.isBusy || controller.isOperating;
    final hasMcp = plugin.id == 'playwright'; // Playwright 有官方 MCP 服务

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        // 详情按钮
        IconButton.filledTonal(
          tooltip: isZh ? '详情' : 'Details',
          onPressed: () => _showDetailDialog(context),
          icon: const Icon(Icons.info_outline_rounded, size: 18),
        ),
        // MCP 服务按钮（仅 Playwright）
        if (hasMcp && plugin.isInstalled)
          IconButton.filledTonal(
            tooltip: isZh ? 'MCP 服务' : 'MCP Service',
            onPressed: isBusy ? null : () => _showMcpActions(context),
            icon: const Icon(Icons.hub_outlined, size: 18),
          ),
        // 安装/更新/卸载按钮
        if (plugin.status == PluginStatus.notInstalled)
          MicroPressFeedback(
            child: FilledButton.icon(
              onPressed: isBusy ? null : () => _doInstall(context),
              icon: const Icon(Icons.download_rounded),
              label: Text(isZh ? '安装' : 'Install'),
            ),
          )
        else if (plugin.isInstalled) ...[
          if (plugin.hasUpdate)
            MicroPressFeedback(
              child: FilledButton.tonalIcon(
                onPressed: isBusy ? null : () => _doUpdate(context),
                icon: const Icon(Icons.system_update_alt_rounded, size: 18),
                label: Text(isZh ? '更新' : 'Update'),
              ),
            ),
          MicroPressFeedback(
            child: OutlinedButton.icon(
              onPressed: isBusy ? null : () => _doUninstall(context),
              icon: Icon(Icons.delete_outline_rounded,
                  size: 18, color: Theme.of(context).colorScheme.error),
              label: Text(
                isZh ? '卸载' : 'Uninstall',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ] else
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
      ],
    );
  }

  Future<void> _doInstall(BuildContext context) async {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    for (final depId in plugin.dependencies) {
      final dep = controller.pluginById(depId);
      if (dep == null || !dep.isInstalled) {
        _showPluginSnackBar(context, SnackBar(
          content: Text(isZh
              ? '需要先安装 ${dep?.name ?? depId}'
              : '${dep?.name ?? depId} must be installed first'),
        ));
        return;
      }
    }
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isZh ? '安装 ${plugin.name}？' : 'Install ${plugin.name}?'),
        content: Text(isZh
            ? '将在本机安装 ${plugin.name}，可能需要下载依赖文件。'
            : 'This will install ${plugin.name}. Dependencies may be downloaded.'),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: isZh ? '取消' : 'Cancel',
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: isZh ? '安装' : 'Install',
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    _showOperationDialog(context, isZh ? '安装' : 'Install', plugin.name);
    final success = await controller.installPlugin(plugin.id);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    _showPluginSnackBar(context, SnackBar(
      content: Text(success
          ? (isZh ? '${plugin.name} 安装成功' : '${plugin.name} installed')
          : (isZh ? '${plugin.name} 安装失败' : '${plugin.name} install failed')),
    ));
  }

  Future<void> _doUpdate(BuildContext context) async {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isZh ? '更新 ${plugin.name}？' : 'Update ${plugin.name}?'),
        content: Text(isZh
            ? '将 ${plugin.name} 从 ${plugin.installedVersion} 更新到 ${plugin.latestVersion}。'
            : 'Update ${plugin.name} from ${plugin.installedVersion} to ${plugin.latestVersion}.'),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: isZh ? '取消' : 'Cancel',
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: isZh ? '更新' : 'Update',
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    _showOperationDialog(context, isZh ? '更新' : 'Update', plugin.name);
    final success = await controller.updatePlugin(plugin.id);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    _showPluginSnackBar(context, SnackBar(
      content: Text(success
          ? (isZh ? '${plugin.name} 更新成功' : '${plugin.name} updated')
          : (isZh ? '${plugin.name} 更新失败' : '${plugin.name} update failed')),
    ));
  }

  Future<void> _doUninstall(BuildContext context) async {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    for (final other in controller.plugins) {
      if (other.id == plugin.id) continue;
      if (other.isInstalled && other.dependencies.contains(plugin.id)) {
        _showPluginSnackBar(context, SnackBar(
          content: Text(isZh
              ? '${other.name} 依赖 ${plugin.name}，请先卸载 ${other.name}'
              : '${other.name} depends on ${plugin.name}. Uninstall it first.'),
        ));
        return;
      }
    }
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isZh ? '卸载 ${plugin.name}？' : 'Uninstall ${plugin.name}?'),
        content: Text(isZh
            ? '将从本机卸载 ${plugin.name}，此操作不可撤销。'
            : 'This will remove ${plugin.name}. This cannot be undone.'),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(ctx).pop(false),
            label: isZh ? '取消' : 'Cancel',
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(ctx).pop(true),
            label: isZh ? '卸载' : 'Uninstall',
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    _showOperationDialog(context, isZh ? '卸载' : 'Uninstall', plugin.name);
    final success = await controller.uninstallPlugin(plugin.id);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    _showPluginSnackBar(context, SnackBar(
      content: Text(success
          ? (isZh ? '${plugin.name} 已卸载' : '${plugin.name} uninstalled')
          : (isZh ? '${plugin.name} 卸载失败' : '${plugin.name} uninstall failed')),
    ));
  }

  void _showOperationDialog(BuildContext context, String action, String pluginName) {
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    showAnimatedDialog(
      context: context,
      builder: (ctx) => _PluginDetailDialog(plugin: plugin, isZh: isZh),
    );
  }

  void _showMcpActions(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    showAnimatedDialog(
      context: context,
      builder: (ctx) => _PluginMcpDialog(
        plugin: plugin,
        controller: controller,
        isZh: isZh,
      ),
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
  late final AnimationController _pulseController;
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    widget.controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    setState(() {});
    final logs = widget.controller.operationLogs;
    if (logs.length > _lastLogCount) {
      _lastLogCount = logs.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final logs = widget.controller.operationLogs;
    final isOperating = widget.controller.isOperating;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (isOperating)
                    FadeTransition(
                      opacity: _pulseController.drive(
                        Tween(begin: 0.4, end: 1.0),
                      ),
                      child: Icon(
                        Icons.terminal_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  else
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: Color(0xFF16A34A),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.action} ${widget.pluginName}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isOperating)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            // 环境信息
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
                    Text('PID: $pid'),
                    Text('OS: ${Platform.operatingSystem}'),
                    Text('Arch: ${Platform.version.split(' ').last}'),
                    Text(isZh ? '日志: ${logs.length} 行' : 'Logs: ${logs.length} lines'),
                  ],
                ),
              ),
            ),
            // 进度条
            if (isOperating)
              LinearProgressIndicator(
                minHeight: 3,
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              )
            else
              Container(
                height: 3,
                color: const Color(0xFF16A34A),
              ),
            // 终端输出区域
            Flexible(
              child: Container(
                color: const Color(0xFF1E1E1E),
                child: logs.isEmpty
                    ? Center(
                        child: Text(
                          isZh ? '等待输出…' : 'Waiting for output…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF808080),
                            fontFamily: 'monospace',
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final line = logs[index];
                          final isError = line.startsWith('[stderr]');
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
            // 底部状态栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isOperating ? Icons.hourglass_top_rounded : Icons.done_all_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isOperating
                        ? (isZh ? '正在执行…' : 'Executing…')
                        : (isZh ? '操作完成' : 'Completed'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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

// ─────────────────────────────────────────────────────────────────────────────
// 插件元信息行
// ─────────────────────────────────────────────────────────────────────────────

class _PluginMetaRow extends StatelessWidget {
  const _PluginMetaRow({required this.plugin});

  final PluginInfo plugin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
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
              Icon(Icons.tag, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '${isZh ? "版本" : "Version"}: ${plugin.installedVersion}',
                style: metaStyle,
              ),
            ],
          ),
        if (plugin.latestVersion != null && plugin.hasUpdate)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.new_releases_outlined,
                  size: 14, color: Color(0xFFF59E0B)),
              const SizedBox(width: 4),
              Text(
                '${isZh ? "可更新到" : "Update available"}: ${plugin.latestVersion}',
                style: metaStyle?.copyWith(color: const Color(0xFFF59E0B)),
              ),
            ],
          ),
        if (plugin.installPath != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_outlined,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
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
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    return Row(
      children: [
        Icon(Icons.account_tree_outlined,
            size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          isZh ? '依赖: ' : 'Depends on: ',
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
                color: installed ? const Color(0xFF16A34A) : theme.colorScheme.error,
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
          BoxShadow(color: Color(0x1A000000), blurRadius: 2, offset: Offset(0, 1)),
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

class _PluginStateCard extends StatelessWidget {
  const _PluginStateCard({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (action != null) ...[
                  const SizedBox(height: 16),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 插件详情弹窗
// ─────────────────────────────────────────────────────────────────────────────

class _PluginDetailDialog extends StatefulWidget {
  const _PluginDetailDialog({required this.plugin, required this.isZh});

  final PluginInfo plugin;
  final bool isZh;

  @override
  State<_PluginDetailDialog> createState() => _PluginDetailDialogState();
}

class _PluginDetailDialogState extends State<_PluginDetailDialog> {
  Map<String, String> _envInfo = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEnvInfo();
  }

  Future<void> _loadEnvInfo() async {
    final info = <String, String>{};
    try {
      info['OS'] = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      info['Arch'] = Platform.version.split(' ').last;
      info['Dart'] = Platform.version.split(' ').first;
      info['PID'] = '$pid';
      info[widget.isZh ? '处理器数' : 'Processors'] = '${Platform.numberOfProcessors}';
      if (widget.plugin.installPath != null) {
        info[widget.isZh ? '安装路径' : 'Install Path'] = widget.plugin.installPath!;
      }
      if (widget.plugin.installedVersion != null) {
        info[widget.isZh ? '当前版本' : 'Version'] = widget.plugin.installedVersion!;
      }
      if (widget.plugin.latestVersion != null) {
        info[widget.isZh ? '最新版本' : 'Latest'] = widget.plugin.latestVersion!;
      }
      // 获取额外运行时信息
      if (widget.plugin.id == 'nodejs' && widget.plugin.isInstalled) {
        try {
          final npmResult = await Process.run('npm', ['--version'])
              .timeout(const Duration(seconds: 5));
          if (npmResult.exitCode == 0) {
            info['npm'] = npmResult.stdout.toString().trim();
          }
          final npxResult = await Process.run('npx', ['--version'])
              .timeout(const Duration(seconds: 5));
          if (npxResult.exitCode == 0) {
            info['npx'] = npxResult.stdout.toString().trim();
          }
        } catch (_) {}
      }
      if (widget.plugin.id == 'playwright' && widget.plugin.isInstalled) {
        try {
          final result = await Process.run('npx', ['playwright', '--version'])
              .timeout(const Duration(seconds: 10));
          if (result.exitCode == 0) {
            info['Playwright CLI'] = result.stdout.toString().trim();
          }
        } catch (_) {}
      }
    } catch (_) {}
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
    final isZh = widget.isZh;
    final plugin = widget.plugin;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${plugin.name} ${isZh ? "详情" : "Details"}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
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
            // 内容
            Flexible(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // 基本信息
                        _DetailSection(
                          title: isZh ? '基本信息' : 'Basic Info',
                          icon: Icons.extension_rounded,
                          children: [
                            _DetailRow(label: isZh ? '名称' : 'Name', value: plugin.name),
                            _DetailRow(label: 'ID', value: plugin.id),
                            _DetailRow(label: isZh ? '描述' : 'Description', value: plugin.description),
                            _DetailRow(
                              label: isZh ? '状态' : 'Status',
                              value: plugin.status.name,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 环境信息
                        _DetailSection(
                          title: isZh ? '环境信息' : 'Environment',
                          icon: Icons.computer_rounded,
                          children: [
                            for (final entry in _envInfo.entries)
                              _DetailRow(label: entry.key, value: entry.value),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 依赖关系
                        _DetailSection(
                          title: isZh ? '依赖关系' : 'Dependencies',
                          icon: Icons.account_tree_rounded,
                          children: [
                            _DetailRow(
                              label: isZh ? '依赖' : 'Depends on',
                              value: plugin.dependencies.isEmpty
                                  ? (isZh ? '无' : 'None')
                                  : plugin.dependencies.join(', '),
                            ),
                            _DetailRow(
                              label: isZh ? '被依赖' : 'Required by',
                              value: plugin.dependents.isEmpty
                                  ? (isZh ? '无' : 'None')
                                  : plugin.dependents.join(', '),
                            ),
                          ],
                        ),
                        if (plugin.id == 'playwright') ...[
                          const SizedBox(height: 16),
                          _DetailSection(
                            title: 'MCP',
                            icon: Icons.hub_rounded,
                            children: [
                              _DetailRow(
                                label: isZh ? 'MCP 包' : 'MCP Package',
                                value: '@playwright/mcp',
                              ),
                              _DetailRow(
                                label: isZh ? '说明' : 'Description',
                                value: isZh
                                    ? '提供浏览器自动化能力的 MCP 服务'
                                    : 'MCP server for browser automation',
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
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
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
  const _PluginMcpDialog({
    required this.plugin,
    required this.controller,
    required this.isZh,
  });

  final PluginInfo plugin;
  final PluginServiceController controller;
  final bool isZh;

  @override
  State<_PluginMcpDialog> createState() => _PluginMcpDialogState();
}

class _PluginMcpDialogState extends State<_PluginMcpDialog> {
  bool _checking = true;
  bool _mcpInstalled = false;
  String? _mcpVersion;
  bool _operating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkMcpStatus();
  }

  Future<void> _checkMcpStatus() async {
    setState(() => _checking = true);
    try {
      if (widget.plugin.id == 'playwright') {
        final result = await Process.run(
          'npx', ['@playwright/mcp', '--version'],
        ).timeout(const Duration(seconds: 15));
        if (result.exitCode == 0) {
          _mcpInstalled = true;
          _mcpVersion = result.stdout.toString().trim();
        } else {
          // 尝试检查是否已安装但版本命令不同
          final listResult = await Process.run(
            'npm', ['list', '-g', '@playwright/mcp', '--depth=0'],
          ).timeout(const Duration(seconds: 10));
          _mcpInstalled = listResult.exitCode == 0 &&
              listResult.stdout.toString().contains('@playwright/mcp');
          if (_mcpInstalled) {
            final match = RegExp(r'@playwright/mcp@([\d.]+)')
                .firstMatch(listResult.stdout.toString());
            _mcpVersion = match?.group(1);
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _installMcp() async {
    setState(() { _operating = true; _error = null; });
    try {
      final result = await Process.run(
        'npm', ['install', '-g', '@playwright/mcp'],
      ).timeout(const Duration(minutes: 3));
      if (result.exitCode == 0) {
        await _checkMcpStatus();
      } else {
        _error = result.stderr.toString().trim();
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _operating = false);
  }

  Future<void> _updateMcp() async {
    setState(() { _operating = true; _error = null; });
    try {
      final result = await Process.run(
        'npm', ['update', '-g', '@playwright/mcp'],
      ).timeout(const Duration(minutes: 3));
      if (result.exitCode == 0) {
        await _checkMcpStatus();
      } else {
        _error = result.stderr.toString().trim();
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _operating = false);
  }

  Future<void> _uninstallMcp() async {
    setState(() { _operating = true; _error = null; });
    try {
      final result = await Process.run(
        'npm', ['uninstall', '-g', '@playwright/mcp'],
      ).timeout(const Duration(minutes: 2));
      if (result.exitCode == 0) {
        _mcpInstalled = false;
        _mcpVersion = null;
      } else {
        _error = result.stderr.toString().trim();
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _operating = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZh = widget.isZh;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.hub_rounded, size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.plugin.name} MCP ${isZh ? "服务" : "Service"}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isZh
                    ? '管理 ${widget.plugin.name} 关联的 MCP 服务（@playwright/mcp）。'
                    : 'Manage the MCP service associated with ${widget.plugin.name}.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (_checking)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _mcpInstalled ? Icons.check_circle : Icons.cancel,
                        size: 18,
                        color: _mcpInstalled
                            ? const Color(0xFF16A34A)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _mcpInstalled
                                  ? (isZh ? '已安装' : 'Installed')
                                  : (isZh ? '未安装' : 'Not Installed'),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_mcpVersion != null)
                              Text(
                                'v$_mcpVersion',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!_mcpInstalled)
                      FilledButton.icon(
                        onPressed: _operating ? null : _installMcp,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(isZh ? '安装 MCP' : 'Install MCP'),
                      )
                    else ...[
                      FilledButton.tonalIcon(
                        onPressed: _operating ? null : _updateMcp,
                        icon: const Icon(Icons.system_update_alt_rounded, size: 18),
                        label: Text(isZh ? '更新' : 'Update'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _operating ? null : _uninstallMcp,
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 18, color: theme.colorScheme.error),
                        label: Text(
                          isZh ? '卸载' : 'Uninstall',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(isZh ? '关闭' : 'Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
