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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
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
                            : 'Manage optional plugin installation, updates, and removal. Plugins extend OpenHand with additional runtime capabilities.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                MicroPressFeedback(
                  child: OutlinedButton.icon(
                    onPressed: controller.isOperating ? null : controller.rescan,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(isZh ? '重新扫描' : 'Rescan'),
                  ),
                ),
              ],
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
    if (plugin.status == PluginStatus.notInstalled) {
      return MicroPressFeedback(
        child: FilledButton.icon(
          onPressed: isBusy ? null : () => _doInstall(context),
          icon: const Icon(Icons.download_rounded),
          label: Text(isZh ? '安装' : 'Install'),
        ),
      );
    }
    if (plugin.isInstalled) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
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
        ],
      );
    }
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2.5),
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
