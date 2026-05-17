import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/model/dialog_animation_settings.dart';
import '../../../app/state/settings_controller.dart';
import '../../../app/support/openhand_scroll_physics.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/animated_menu.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/highlight_pulse.dart';
import '../../../shared/ui/openhand_dialog_action_button.dart';
import '../../../shared/ui/openhand_safe_scrollbar.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../message_gateway_controller.dart';
import '../model/web_message_platform_config.dart';
import '../service/web_message_platform_service.dart';

void _showGatewaySnackBar(BuildContext context, SnackBar snackBar) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  OpenHandSnackBar.show(context, messenger, snackBar);
}

class MessageGatewayView extends StatefulWidget {
  const MessageGatewayView({super.key});

  @override
  State<MessageGatewayView> createState() => _MessageGatewayViewState();
}

class _MessageGatewayViewState extends State<MessageGatewayView> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<MessageGatewayController>().updateTheme(Theme.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final controller = context.watch<MessageGatewayController>();

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsMessageGatewayTitle,
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.settingsMessageGatewayDescription,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
            child: HighlightPulse(signal: controller.saveSuccessSignal),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, MessageGatewayController controller) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.errorMessage != null) {
      return _GatewayStateCard(
        icon: Icons.error_outline_rounded,
        title: '消息网关加载失败',
        body: controller.errorMessage!,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
      children: [_WebPlatformServiceCard(controller: controller)],
    );
  }
}

class _WebPlatformServiceCard extends StatelessWidget {
  const _WebPlatformServiceCard({required this.controller});

  final MessageGatewayController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = controller.config;
    final runtime = controller.runtimeSnapshot();
    final isRunning = controller.isRunning;
    final boundPort = Uri.tryParse(runtime.boundUrl)?.port;
    final usingFallbackPort =
        isRunning && boundPort != null && boundPort != config.listenPort;
    final stateColor = switch (controller.runtimeState) {
      WebGatewayRuntimeState.running => const Color(0xFF16A34A),
      WebGatewayRuntimeState.crashed => theme.colorScheme.error,
      WebGatewayRuntimeState.starting ||
      WebGatewayRuntimeState.stopping => const Color(0xFFF59E0B),
      WebGatewayRuntimeState.stopped => theme.colorScheme.onSurfaceVariant,
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
                final compact = constraints.maxWidth < 760;
                final title = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 状态点采用与 MCP 服务同款布局：
                    // 套在图标 Stack 里，用 Positioned(right:-2,bottom:-2) 顶出于右下角，
                    // 带与 surface 同色的 3px 描边 + 软阴影，提供一致的“状态徽标”观感。
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
                            Icons.language_rounded,
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
                          // 状态点已上移到图标右下角，标题行只留应用名。
                          Text(
                            webMessagePlatformBuiltinName,
                            style: theme.textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            config.description,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    _FeatureIconButton(
                      tooltip: config.loggingEnabled
                          ? '查看 Web 服务日志'
                          : '开启日志后可查看日志',
                      enabled: config.loggingEnabled,
                      icon: Icons.terminal_rounded,
                      onPressed: () => _showLogs(context, controller),
                    ),
                    _FeatureIconButton(
                      tooltip: isRunning ? '端口连通性测试' : '服务运行后可测试端口',
                      enabled: isRunning,
                      icon: Icons.network_check_rounded,
                      onPressed: () =>
                          _showConnectivityTest(context, controller),
                    ),
                    _FeatureIconButton(
                      tooltip: config.healthCheck.enabled
                          ? '健康检测'
                          : '开启健康检查后可使用',
                      enabled: config.healthCheck.enabled,
                      icon: Icons.monitor_heart_outlined,
                      onPressed: () => _runHealth(context, controller),
                    ),
                    _FeatureIconButton(
                      tooltip: config.opsEnabled ? '运维面板' : '开启运维后可查看',
                      enabled: config.opsEnabled,
                      icon: Icons.speed_rounded,
                      onPressed: () => _showOps(context, controller),
                    ),
                    IconButton.filledTonal(
                      tooltip: '编辑配置',
                      onPressed: () => _showEditor(context, controller),
                      icon: const Icon(Icons.edit_rounded),
                    ),
                    IconButton.filled(
                      tooltip: isRunning ? '停止' : '启动',
                      onPressed: controller.isOperating
                          ? null
                          : () => isRunning
                                ? controller.stopService()
                                : controller.startService(),
                      icon: Icon(
                        isRunning
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ],
                );
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
                    const SizedBox(width: 18),
                    Flexible(
                      child: Align(
                        alignment: Alignment.topRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: actions,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.power_settings_new_rounded,
                  label: config.enabled ? '已启用' : '未启用',
                ),
                _InfoChip(
                  icon: Icons.rocket_launch_outlined,
                  label: config.autoStartOnLaunch ? '冷启动自启' : '冷启动不干预',
                ),
                _InfoChip(
                  icon: Icons.sync_rounded,
                  label: config.autoReloadOnChange ? '配置自动重载' : '配置重启生效',
                ),
                if (controller.hasPendingRuntimeConfig)
                  const _InfoChip(
                    icon: Icons.pending_actions_rounded,
                    label: '待重启生效',
                  ),
                _InfoChip(
                  icon: Icons.link_rounded,
                  label: isRunning
                      ? controller.webUrl
                      : '${config.listenHost}:${config.listenPort}',
                ),
                if (usingFallbackPort)
                  _InfoChip(
                    icon: Icons.warning_amber_rounded,
                    label: '${config.listenPort} 被占用，临时端口 $boundPort',
                  ),
                _InfoChip(
                  icon: Icons.lock_outline_rounded,
                  label: config.authEnabled ? '鉴权开启' : '免鉴权',
                ),
                _InfoChip(
                  icon: Icons.analytics_outlined,
                  label: config.telemetryEnabled ? '遥测开启' : '遥测关闭',
                ),
                _InfoChip(
                  icon: Icons.article_outlined,
                  label: config.loggingEnabled ? '日志开启' : '日志关闭',
                ),
                _InfoChip(
                  icon: Icons.security_rounded,
                  label: '并发 ${config.maxConcurrentRequests}',
                ),
                _InfoChip(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '单消息 ${config.singleMessageTokenLimit} tokens',
                ),
                _InfoChip(
                  icon: Icons.forum_outlined,
                  label: '单会话 ${config.maxMessagesPerSession} 条',
                ),
                _InfoChip(
                  icon: Icons.manage_accounts_outlined,
                  label: config.sessionManagementEnabled ? '会话可管理' : '会话只读',
                ),
                _InfoChip(
                  icon: Icons.folder_open_rounded,
                  label: config.workspaceFileWriteEnabled
                      ? '文件浏览 / 可操作'
                      : '文件浏览 / 只读',
                ),
              ],
            ),
            // 监听通配符地址（0.0.0.0 / ::）时由 service.accessibleUrls 列出
            // 全部可访问 URL（含 LAN IP），点 chip 即拷贝。仅当 URL 数量 >1
            // 时渲染，避免与上方"已运行单 URL"的 InfoChip 重复。
            if (isRunning && controller.webUrls.length > 1) ...[
              const SizedBox(height: 12),
              _AccessibleUrlsBar(urls: controller.webUrls),
            ],
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth < 820 ? 1 : 4;
                return GridView.count(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: columns == 1 ? 5.8 : 2.9,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _MetricTile(
                      label: '状态',
                      value: _runtimeStateLabel(context, runtime.state),
                    ),
                    _MetricTile(
                      label: '请求数',
                      value: '${runtime.totalRequests}',
                    ),
                    _MetricTile(label: '错误数', value: '${runtime.totalErrors}'),
                    _MetricTile(
                      label: '运行时长',
                      value: _formatDuration(runtime.uptimeMs),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditor(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => _WebPlatformEditorDialog(
        controller: controller,
        initialConfig: controller.config,
      ),
    );
  }

  Future<void> _runHealth(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    final result = await controller.runHealthCheck();
    if (!context.mounted) return;
    _showGatewaySnackBar(
      context,
      SnackBar(
        content: Text('${result.summary} (${result.durationMs}ms)'),
        backgroundColor: result.ok ? const Color(0xFF16A34A) : null,
      ),
    );
  }

  Future<void> _showLogs(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => _WebGatewayLogDialog(controller: controller),
    );
  }

  Future<void> _showConnectivityTest(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => _WebGatewayConnectivityDialog(controller: controller),
    );
  }

  Future<void> _showOps(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    await showAnimatedDialog<void>(
      context: context,
      builder: (_) => _WebGatewayOpsDialog(controller: controller),
    );
  }
}

class _WebPlatformEditorDialog extends StatefulWidget {
  const _WebPlatformEditorDialog({
    required this.controller,
    required this.initialConfig,
  });

  final MessageGatewayController controller;
  final WebMessagePlatformConfig initialConfig;

  @override
  State<_WebPlatformEditorDialog> createState() =>
      _WebPlatformEditorDialogState();
}

class _WebPlatformEditorDialogState extends State<_WebPlatformEditorDialog> {
  late bool _enabled;
  late bool _autoStartOnLaunch;
  late bool _autoReloadOnChange;
  late bool _authEnabled;
  late bool _telemetryEnabled;
  late bool _loggingEnabled;
  late bool _opsEnabled;
  late bool _healthEnabled;
  late bool _planModeEnabled;
  late bool _sessionManagementEnabled;
  late bool _workspaceFileWriteEnabled;
  late final TextEditingController _descriptionController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _maxConcurrentController;
  late final TextEditingController _singleMessageController;
  late final TextEditingController _maxMessagesController;
  late final TextEditingController _logMaxMbController;
  late final TextEditingController _logRotationDaysController;
  late final TextEditingController _logMaxFilesController;
  late final TextEditingController _workspaceFileMaxMbController;
  late final TextEditingController _workspaceFileExtensionsController;
  late final TextEditingController _uploadCacheRetentionDaysController;
  late final TextEditingController _uploadCacheMaxMbController;
  late final TextEditingController _healthPathController;
  late final TextEditingController _healthMethodController;
  late final TextEditingController _healthTimeoutController;
  late final TextEditingController _healthStatusController;
  late final TextEditingController _healthContainsController;
  late final TextEditingController _healthQueryController;
  late bool _healthFollowRedirects;
  late Set<String> _templates;
  late Set<String> _skills;
  late Set<String> _mcpServers;
  late Set<String> _memories;
  late Set<String> _tools;
  late Set<String> _instructions;
  late Set<String> _models;
  late Set<WebGatewayMessageType> _messageTypes;
  late Set<WebGatewayConversationMode> _modes;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    _enabled = config.enabled;
    _autoStartOnLaunch = config.autoStartOnLaunch;
    _autoReloadOnChange = config.autoReloadOnChange;
    _authEnabled = config.authEnabled;
    _telemetryEnabled = config.telemetryEnabled;
    _loggingEnabled = config.loggingEnabled;
    _opsEnabled = config.opsEnabled;
    _healthEnabled = config.healthCheck.enabled;
    _planModeEnabled = config.planModeEnabled;
    _sessionManagementEnabled = config.sessionManagementEnabled;
    _workspaceFileWriteEnabled = config.workspaceFileWriteEnabled;
    _descriptionController = TextEditingController(text: config.description);
    _hostController = TextEditingController(text: config.listenHost);
    _portController = TextEditingController(text: '${config.listenPort}');
    _usernameController = TextEditingController(text: config.username);
    _passwordController = TextEditingController(text: config.password);
    _maxConcurrentController = TextEditingController(
      text: '${config.maxConcurrentRequests}',
    );
    _singleMessageController = TextEditingController(
      text: '${config.singleMessageTokenLimit}',
    );
    _maxMessagesController = TextEditingController(
      text: '${config.maxMessagesPerSession}',
    );
    _logMaxMbController = TextEditingController(
      text: '${(config.logConfig.fileMaxBytes / (1024 * 1024)).round()}',
    );
    _logRotationDaysController = TextEditingController(
      text: '${config.logConfig.rotationDays}',
    );
    _logMaxFilesController = TextEditingController(
      text: '${config.logConfig.maxFiles}',
    );
    _workspaceFileMaxMbController = TextEditingController(
      text:
          '${math.max(1, (config.workspaceFileMaxBytes / (1024 * 1024)).ceil())}',
    );
    _workspaceFileExtensionsController = TextEditingController(
      text: config.workspaceFileAllowedExtensions.join(', '),
    );
    _uploadCacheRetentionDaysController = TextEditingController(
      text: '${config.uploadCacheRetentionDays}',
    );
    _uploadCacheMaxMbController = TextEditingController(
      text: '${(config.uploadCacheMaxBytes / (1024 * 1024)).round()}',
    );
    _healthPathController = TextEditingController(
      text: config.healthCheck.path,
    );
    _healthMethodController = TextEditingController(
      text: config.healthCheck.method,
    );
    _healthTimeoutController = TextEditingController(
      text: '${config.healthCheck.timeoutMs}',
    );
    _healthStatusController = TextEditingController(
      text: '${config.healthCheck.expectedStatusCode}',
    );
    _healthContainsController = TextEditingController(
      text: config.healthCheck.responseContains,
    );
    _healthQueryController = TextEditingController(
      text: _formatQueryParameters(config.healthCheck.queryParameters),
    );
    _healthFollowRedirects = config.healthCheck.followRedirects;
    _templates = config.allowedTemplateIds.toSet();
    _skills = config.allowedSkillNames.toSet();
    _mcpServers = config.allowedMcpServerNames.toSet();
    _memories = config.allowedMemoryIds.toSet();
    _tools = config.allowedBuiltinToolNames.toSet();
    _instructions = config.allowedInstructionIds.toSet();
    _models = config.allowedModelKeys.toSet();
    _messageTypes = config.allowedMessageTypes.toSet();
    _modes = config.allowedConversationModes.toSet();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _maxConcurrentController.dispose();
    _singleMessageController.dispose();
    _maxMessagesController.dispose();
    _logMaxMbController.dispose();
    _logRotationDaysController.dispose();
    _logMaxFilesController.dispose();
    _workspaceFileMaxMbController.dispose();
    _workspaceFileExtensionsController.dispose();
    _uploadCacheRetentionDaysController.dispose();
    _uploadCacheMaxMbController.dispose();
    _healthPathController.dispose();
    _healthMethodController.dispose();
    _healthTimeoutController.dispose();
    _healthStatusController.dispose();
    _healthContainsController.dispose();
    _healthQueryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaSize = MediaQuery.sizeOf(context);
    final dialogMaxHeight = math.min(
      720.0,
      math.max(420.0, mediaSize.height - 120),
    );
    return SafeArea(
      minimum: const EdgeInsets.all(18),
      child: Dialog(
        insetPadding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: colorScheme.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(mediaSize.width - 36, 920),
            maxHeight: dialogMaxHeight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  border: Border(
                    bottom: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(19),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: .14),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.language_rounded,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            webMessagePlatformBuiltinName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '配置 Web 端可见能力、访问边界与运行保护策略',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  primary: false,
                  physics: const OpenHandBouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth >= 760;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SwitchGrid(
                            twoColumns: twoColumns,
                            children: [
                              _SwitchTile(
                                label: '是否启用',
                                value: _enabled,
                                onChanged: (v) => setState(() => _enabled = v),
                              ),
                              _SwitchTile(
                                label: '冷启动自动启动',
                                value: _autoStartOnLaunch,
                                onChanged: (value) =>
                                    setState(() => _autoStartOnLaunch = value),
                              ),
                              _SwitchTile(
                                label: '配置变更自动重载',
                                value: _autoReloadOnChange,
                                onChanged: (value) =>
                                    setState(() => _autoReloadOnChange = value),
                              ),
                              _SwitchTile(
                                label: '是否开启鉴权',
                                value: _authEnabled,
                                onChanged: (v) =>
                                    setState(() => _authEnabled = v),
                              ),
                              _SwitchTile(
                                label: '是否启用遥测',
                                value: _telemetryEnabled,
                                onChanged: (v) =>
                                    setState(() => _telemetryEnabled = v),
                              ),
                              _SwitchTile(
                                label: '是否记录日志',
                                value: _loggingEnabled,
                                onChanged: (v) =>
                                    setState(() => _loggingEnabled = v),
                              ),
                              _SwitchTile(
                                label: '是否支持运维',
                                value: _opsEnabled,
                                onChanged: (v) =>
                                    setState(() => _opsEnabled = v),
                              ),
                              _SwitchTile(
                                label: '是否开启健康检查',
                                value: _healthEnabled,
                                onChanged: (v) =>
                                    setState(() => _healthEnabled = v),
                              ),
                              _SwitchTile(
                                label: '是否支持计划模式',
                                value: _planModeEnabled,
                                onChanged: (v) =>
                                    setState(() => _planModeEnabled = v),
                              ),
                              _SwitchTile(
                                label: '是否允许 Web 会话管理',
                                value: _sessionManagementEnabled,
                                onChanged: (v) => setState(
                                  () => _sessionManagementEnabled = v,
                                ),
                              ),
                              _SwitchTile(
                                label: '是否支持操作文件',
                                value: _workspaceFileWriteEnabled,
                                onChanged: (v) => setState(
                                  () => _workspaceFileWriteEnabled = v,
                                ),
                              ),
                            ],
                          ),
                          AnimatedSwitcher(
                            duration: _motionDuration(context, 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _autoReloadOnChange
                                ? const SizedBox.shrink(
                                    key: ValueKey('auto-reload-on'),
                                  )
                                : const Padding(
                                    key: ValueKey('auto-reload-off'),
                                    padding: EdgeInsets.only(top: 10),
                                    child: _EditorNotice(
                                      icon: Icons.restart_alt_rounded,
                                      title: '配置将等待重启生效',
                                      body:
                                          '自动重载关闭后，本次保存只写入配置文件；运行中的 Web 服务会继续使用旧配置，直到手动重启服务或应用冷启动。',
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 18),
                          const _SectionTitle('基础信息'),
                          _TextArea(
                            label: '介绍',
                            controller: _descriptionController,
                          ),
                          _ResponsiveFields(
                            twoColumns: twoColumns,
                            children: [
                              _TextFieldSpec(
                                label: '监听 IP 地址',
                                controller: _hostController,
                              ),
                              _TextFieldSpec(
                                label: '监听端口',
                                controller: _portController,
                                keyboardType: TextInputType.number,
                              ),
                              _TextFieldSpec(
                                label: '可接受并发数',
                                controller: _maxConcurrentController,
                                keyboardType: TextInputType.number,
                              ),
                              _TextFieldSpec(
                                label: '单消息大小(tokens)',
                                controller: _singleMessageController,
                                keyboardType: TextInputType.number,
                              ),
                              _TextFieldSpec(
                                label: '单会话最大消息数',
                                controller: _maxMessagesController,
                                keyboardType: TextInputType.number,
                              ),
                            ],
                          ),
                          if (_authEnabled) ...[
                            const SizedBox(height: 18),
                            const _SectionTitle('鉴权'),
                            _ResponsiveFields(
                              twoColumns: twoColumns,
                              children: [
                                _TextFieldSpec(
                                  label: '用户名',
                                  controller: _usernameController,
                                ),
                                _TextFieldSpec(
                                  label: '密码',
                                  controller: _passwordController,
                                  obscureText: true,
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 18),
                          const _SectionTitle('安全控制'),
                          _MultiSelectDropdown<String>(
                            label: '可新建的线程模板类型',
                            emptyMeansAll: true,
                            noneValue: webGatewayDenyAllSelectionMarker,
                            options: [
                              for (final t in widget.controller.templates)
                                _SelectOption(value: t.id, label: t.name),
                            ],
                            selected: _templates,
                            onChanged: (next) =>
                                setState(() => _templates = next),
                          ),
                          _MultiSelectDropdown<String>(
                            label: '可用的技能',
                            emptyMeansAll: true,
                            noneValue: webGatewayDenyAllSelectionMarker,
                            options: [
                              for (final name in widget.controller.skillNames)
                                _SelectOption(value: name, label: name),
                            ],
                            selected: _skills,
                            onChanged: (next) => setState(() => _skills = next),
                          ),
                          _MultiSelectDropdown<String>(
                            label: '可用的 MCP',
                            emptyMeansAll: true,
                            noneValue: webGatewayDenyAllSelectionMarker,
                            options: [
                              for (final name
                                  in widget.controller.mcpServerNames)
                                _SelectOption(value: name, label: name),
                            ],
                            selected: _mcpServers,
                            onChanged: (next) =>
                                setState(() => _mcpServers = next),
                          ),
                          _MultiSelectDropdown<String>(
                            label: '可用的记忆',
                            emptyMeansAll: true,
                            noneValue: webGatewayDenyAllSelectionMarker,
                            options: [
                              for (final id in widget.controller.memoryIds)
                                _SelectOption(value: id, label: id),
                            ],
                            selected: _memories,
                            onChanged: (next) =>
                                setState(() => _memories = next),
                          ),
                          _MultiSelectDropdown<String>(
                            label: '可用的内建工具',
                            emptyMeansAll: true,
                            noneValue: webGatewayDenyAllSelectionMarker,
                            options: [
                              for (final name
                                  in widget.controller.builtinToolNames)
                                _SelectOption(value: name, label: name),
                            ],
                            selected: _tools,
                            onChanged: (next) => setState(() => _tools = next),
                          ),
                          _MultiSelectDropdown<String>(
                            label: '可用的用户指令',
                            emptyMeansAll: true,
                            noneValue: webGatewayDenyAllSelectionMarker,
                            options: [
                              for (final option
                                  in widget.controller.instructionOptions)
                                _SelectOption(
                                  value: option.id,
                                  label: option.enabled
                                      ? option.label
                                      : '${option.label}（已禁用）',
                                ),
                            ],
                            selected: _instructions,
                            onChanged: (next) =>
                                setState(() => _instructions = next),
                          ),
                          _EnumMultiSelectDropdown<WebGatewayMessageType>(
                            label: '可发送的消息类型',
                            values: WebGatewayMessageType.values,
                            selected: _messageTypes,
                            labelFor: (v) =>
                                v == WebGatewayMessageType.text ? '纯文本' : '带附件',
                            onChanged: (next) =>
                                setState(() => _messageTypes = next),
                          ),
                          _EnumMultiSelectDropdown<WebGatewayConversationMode>(
                            label: '可使用的对话模式',
                            values: WebGatewayConversationMode.values,
                            selected: _modes,
                            labelFor: _modeLabel,
                            onChanged: (next) => setState(() => _modes = next),
                          ),
                          _ModelMultiSelectField(
                            label: '可使用的模型',
                            emptyMeansAll: true,
                            options: widget.controller.modelOptions,
                            selected: _models,
                            onChanged: (next) => setState(() => _models = next),
                          ),
                          const SizedBox(height: 18),
                          const _SectionTitle('项目文件'),
                          _ResponsiveFields(
                            twoColumns: twoColumns,
                            children: [
                              _TextFieldSpec(
                                label: '单文件最大(MB)',
                                controller: _workspaceFileMaxMbController,
                                keyboardType: TextInputType.number,
                              ),
                              _TextFieldSpec(
                                label: '允许扩展名(空=全部文本)',
                                controller: _workspaceFileExtensionsController,
                              ),
                              _TextFieldSpec(
                                label: '上传缓存保留天数',
                                controller: _uploadCacheRetentionDaysController,
                                keyboardType: TextInputType.number,
                              ),
                              _TextFieldSpec(
                                label: '上传缓存上限(MB)',
                                controller: _uploadCacheMaxMbController,
                                keyboardType: TextInputType.number,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const _SectionTitle('健康检查'),
                          _SwitchTile(
                            label: '是否跟随重定向',
                            value: _healthFollowRedirects,
                            onChanged: (v) =>
                                setState(() => _healthFollowRedirects = v),
                          ),
                          const SizedBox(height: 12),
                          _ResponsiveFields(
                            twoColumns: twoColumns,
                            children: [
                              _TextFieldSpec(
                                label: '请求 URL',
                                controller: _healthPathController,
                              ),
                              _TextFieldSpec(
                                label: '请求方式',
                                controller: _healthMethodController,
                              ),
                              _TextFieldSpec(
                                label: '超时时间(ms)',
                                controller: _healthTimeoutController,
                                keyboardType: TextInputType.number,
                              ),
                              _TextFieldSpec(
                                label: '期望状态码',
                                controller: _healthStatusController,
                                keyboardType: TextInputType.number,
                              ),
                              _TextFieldSpec(
                                label: '响应断言包含',
                                controller: _healthContainsController,
                              ),
                              _TextFieldSpec(
                                label: '查询参数(k=v&k2=v2)',
                                controller: _healthQueryController,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const _SectionTitle('日志轮转'),
                          _ResponsiveFields(
                            twoColumns: twoColumns,
                            children: [
                              _TextFieldSpec(
                                label: '单日志最大(MB)',
                                controller: _logMaxMbController,
                                keyboardType: TextInputType.number,
                              ),
                              _TextFieldSpec(
                                label: '轮转天数',
                                controller: _logRotationDaysController,
                                keyboardType: TextInputType.number,
                              ),
                              _TextFieldSpec(
                                label: '最多日志文件数',
                                controller: _logMaxFilesController,
                                keyboardType: TextInputType.number,
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  border: Border(
                    top: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedSwitcher(
                      duration: _motionDuration(context, 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _saveError == null
                          ? const SizedBox.shrink(key: ValueKey('save-ok'))
                          : Padding(
                              key: const ValueKey('save-error'),
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _EditorNotice(
                                icon: Icons.error_outline_rounded,
                                title: '保存失败',
                                body: _saveError!,
                                error: true,
                              ),
                            ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OpenHandDialogActionButton.secondary(
                          label: '取消',
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 12),
                        OpenHandDialogActionButton.primary(
                          label: _saving ? '保存中' : '保存配置',
                          onPressed: _saving ? null : _save,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final config = WebMessagePlatformConfig(
      enabled: _enabled,
      autoStartOnLaunch: _autoStartOnLaunch,
      autoReloadOnChange: _autoReloadOnChange,
      description: _descriptionController.text.trim().isEmpty
          ? WebMessagePlatformConfig.defaultDescription
          : _descriptionController.text.trim(),
      listenHost: _hostController.text.trim().isEmpty
          ? '0.0.0.0'
          : _hostController.text.trim(),
      listenPort: _int(_portController.text, 8848),
      authEnabled: _authEnabled,
      username: _usernameController.text.trim().isEmpty
          ? 'openhand'
          : _usernameController.text.trim(),
      password: _passwordController.text,
      telemetryEnabled: _telemetryEnabled,
      loggingEnabled: _loggingEnabled,
      opsEnabled: _opsEnabled,
      maxConcurrentRequests: _int(_maxConcurrentController.text, 200),
      allowedTemplateIds: _templates.toList(growable: false),
      allowedSkillNames: _skills.toList(growable: false),
      allowedMcpServerNames: _mcpServers.toList(growable: false),
      allowedMemoryIds: _memories.toList(growable: false),
      allowedBuiltinToolNames: _tools.toList(growable: false),
      allowedInstructionIds: _instructions.toList(growable: false),
      allowedMessageTypes: _messageTypes,
      allowedConversationModes: _modes,
      allowedModelKeys: _models.toList(growable: false),
      planModeEnabled: _planModeEnabled,
      singleMessageTokenLimit: _int(_singleMessageController.text, 2000),
      maxMessagesPerSession: _int(_maxMessagesController.text, 100),
      sessionManagementEnabled: _sessionManagementEnabled,
      workspaceFileWriteEnabled: _workspaceFileWriteEnabled,
      workspaceFileMaxBytes:
          math.max(1, _int(_workspaceFileMaxMbController.text, 1)) *
          1024 *
          1024,
      workspaceFileAllowedExtensions: _parseExtensions(
        _workspaceFileExtensionsController.text,
      ),
      uploadCacheRetentionDays: _int(
        _uploadCacheRetentionDaysController.text,
        7,
      ),
      uploadCacheMaxBytes:
          math.max(1, _int(_uploadCacheMaxMbController.text, 512)) *
          1024 *
          1024,
      healthCheck: WebGatewayHealthCheckConfig(
        enabled: _healthEnabled,
        path: _healthPathController.text.trim().isEmpty
            ? '/api/health'
            : _healthPathController.text.trim(),
        method: _healthMethodController.text.trim().isEmpty
            ? 'GET'
            : _healthMethodController.text.trim().toUpperCase(),
        timeoutMs: _int(_healthTimeoutController.text, 3000),
        expectedStatusCode: _int(_healthStatusController.text, 200),
        responseContains: _healthContainsController.text.trim(),
        queryParameters: _parseQueryParameters(_healthQueryController.text),
        followRedirects: _healthFollowRedirects,
      ),
      logConfig: WebGatewayLogConfig(
        fileMaxBytes:
            math.max(1, _int(_logMaxMbController.text, 50)) * 1024 * 1024,
        rotationDays: _int(_logRotationDaysController.text, 7),
        maxFiles: _int(_logMaxFilesController.text, 10),
      ),
    );
    try {
      await widget.controller.saveConfig(config);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _showGatewaySnackBar(context, SnackBar(content: Text('保存失败: $error')));
      setState(() {
        _saveError = '$error';
        _saving = false;
      });
    }
  }
}

class _EditorNotice extends StatelessWidget {
  const _EditorNotice({
    required this.icon,
    required this.title,
    required this.body,
    this.error = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = error ? colorScheme.error : colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

class _WebGatewayConnectivityDialog extends StatefulWidget {
  const _WebGatewayConnectivityDialog({required this.controller});

  final MessageGatewayController controller;

  @override
  State<_WebGatewayConnectivityDialog> createState() =>
      _WebGatewayConnectivityDialogState();
}

class _WebGatewayConnectivityDialogState
    extends State<_WebGatewayConnectivityDialog> {
  WebGatewayConnectivityTestResult? _result;
  Object? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.controller.runConnectivityTest();
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaSize = MediaQuery.sizeOf(context);
    final dialogMaxHeight = math.min(
      700.0,
      math.max(420.0, mediaSize.height - 120),
    );
    final result = _result;
    final error = _error;

    return SafeArea(
      minimum: const EdgeInsets.all(18),
      child: Dialog(
        insetPadding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(mediaSize.width - 36, 920),
            maxHeight: dialogMaxHeight,
            minHeight: math.min(dialogMaxHeight, 480),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.network_check_rounded,
                      color: result == null
                          ? colorScheme.primary
                          : result.ok
                          ? const Color(0xFF16A34A)
                          : colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('端口连通性测试', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            '逐一探测当前可用 IP + 端口入口的 /api/health',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        IconButton.filledTonal(
                          tooltip: '复制结果 JSON',
                          onPressed: result == null
                              ? null
                              : () => _copyResult(result),
                          icon: const Icon(Icons.content_copy_rounded),
                        ),
                        IconButton.filledTonal(
                          tooltip: '重新测试',
                          onPressed: _running ? null : _run,
                          icon: _running
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                        ),
                        IconButton.filledTonal(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: AnimatedSwitcher(
                  duration: _motionDuration(context, 260),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  child: error != null
                      ? _ConnectivityErrorView(error: error)
                      : result == null
                      ? const _ConnectivityLoadingView()
                      : _ConnectivityResultView(result: result),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyResult(WebGatewayConnectivityTestResult result) async {
    const encoder = JsonEncoder.withIndent('  ');
    await Clipboard.setData(
      ClipboardData(text: encoder.convert(result.toJson())),
    );
    if (!mounted) return;
    _showGatewaySnackBar(
      context,
      const SnackBar(
        content: Text('连通性测试结果已复制'),
        duration: Duration(milliseconds: 1600),
      ),
    );
  }
}

class _ConnectivityLoadingView extends StatelessWidget {
  const _ConnectivityLoadingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('正在检测全部可访问入口', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            '会按当前运行时 URL 顺序逐个探测并汇总结果',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectivityErrorView extends StatelessWidget {
  const _ConnectivityErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '测试启动失败: $error',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
    );
  }
}

class _ConnectivityResultView extends StatelessWidget {
  const _ConnectivityResultView({required this.result});

  final WebGatewayConnectivityTestResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SingleChildScrollView(
      primary: false,
      physics: const OpenHandBouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (result.ok ? const Color(0xFF16A34A) : colorScheme.error)
                  .withValues(alpha: .10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: (result.ok ? const Color(0xFF16A34A) : colorScheme.error)
                    .withValues(alpha: .35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  result.ok
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  color: result.ok
                      ? const Color(0xFF16A34A)
                      : colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(result.summary, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatDateTime(result.startedAt)} · 总耗时 ${result.durationMs}ms',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 720 ? 2 : 4;
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: columns == 2 ? 2.6 : 2.8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _MetricTile(label: '入口总数', value: '${result.targets.length}'),
                  _MetricTile(label: '连通', value: '${result.successCount}'),
                  _MetricTile(label: '失败', value: '${result.failureCount}'),
                  _MetricTile(label: '总耗时', value: '${result.durationMs}ms'),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          const _SectionTitle('入口探测结果'),
          if (result.targets.isEmpty)
            Text(
              '当前服务没有可测试入口。请先启动 Web 通用消息平台服务。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (var index = 0; index < result.targets.length; index++)
              _ConnectivityTargetCard(
                target: result.targets[index],
                index: index,
              ),
          const SizedBox(height: 18),
          const _SectionTitle('测试流程日志'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF101218),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: SelectableText(
              result.logs.isEmpty ? '暂无流程日志' : result.logs.join('\n'),
              style: const TextStyle(
                fontFamily: 'Menlo',
                fontSize: 12,
                height: 1.45,
                color: Color(0xFFE5E7EB),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectivityTargetCard extends StatelessWidget {
  const _ConnectivityTargetCard({required this.target, required this.index});

  final WebGatewayConnectivityProbeResult target;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stateColor = target.ok ? const Color(0xFF16A34A) : colorScheme.error;
    final content = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: stateColor.withValues(alpha: .32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                target.ok
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                size: 20,
                color: stateColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  target.hostPort,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${target.durationMs}ms',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            target.endpointUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.http_rounded,
                label: 'HTTP ${target.statusCode}',
              ),
              _InfoChip(
                icon: Icons.timer_outlined,
                label: '${target.durationMs}ms',
              ),
              _InfoChip(icon: Icons.dns_outlined, label: target.baseUrl),
            ],
          ),
          if (target.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              target.errorMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ],
          if (target.bodyPreview.isNotEmpty) ...[
            const SizedBox(height: 8),
            _StructuredResponsePreview(raw: target.bodyPreview),
          ],
        ],
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return content;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + math.min(index, 6) * 30),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 10),
            child: child,
          ),
        );
      },
      child: content,
    );
  }
}

class _StructuredResponsePreview extends StatelessWidget {
  const _StructuredResponsePreview({required this.raw});

  final String raw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final decoded = _tryDecodeJson(raw);
    final entries = decoded is Map
        ? decoded.entries.toList(growable: false)
        : const <MapEntry<Object?, Object?>>[];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.data_object_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text('响应数据', style: theme.textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 10),
          if (entries.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in entries)
                  _ResponseFieldChip(
                    label: '${entry.key}',
                    value: _formatStructuredValue(entry.value),
                  ),
              ],
            )
          else
            SelectableText(
              raw,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'Menlo',
              ),
            ),
        ],
      ),
    );
  }
}

class _ResponseFieldChip extends StatelessWidget {
  const _ResponseFieldChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            maxLines: 4,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
              fontFamily: 'Menlo',
            ),
          ),
        ],
      ),
    );
  }
}

class _WebGatewayLogDialog extends StatefulWidget {
  const _WebGatewayLogDialog({required this.controller});

  final MessageGatewayController controller;

  @override
  State<_WebGatewayLogDialog> createState() => _WebGatewayLogDialogState();
}

class _WebGatewayLogDialogState extends State<_WebGatewayLogDialog> {
  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final Set<WebGatewayLogLevel> _hidden = <WebGatewayLogLevel>{};
  final List<WebGatewayLogEntry> _rendered = <WebGatewayLogEntry>[];
  final Set<int> _renderedIds = <int>{};
  bool _follow = true;
  int _anchorLogId = 0;
  int _historyLimit = 0;
  int _lastPageSize = 60;
  int _renderedFingerprint = 0;
  int _pendingRenderedFingerprint = 0;
  List<WebGatewayLogEntry> _pendingRenderedTarget =
      const <WebGatewayLogEntry>[];
  bool _syncScheduled = false;
  bool _isExportingLog = false;

  @override
  void initState() {
    super.initState();
    final logs = widget.controller.logs;
    _anchorLogId = logs.isEmpty ? 0 : logs.last.id;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_follow) _scrollToBottomSoon();
  }

  @override
  Widget build(BuildContext context) {
    final logs = widget.controller.logs;
    final mediaSize = MediaQuery.sizeOf(context);
    final dialogMaxHeight = math.min(
      680.0,
      math.max(360.0, mediaSize.height - 120),
    );
    _lastPageSize = _logPageSize(dialogMaxHeight);
    final visible = _visibleLogs(logs);
    final historicalCount = logs
        .where(
          (entry) => entry.id <= _anchorLogId && !_hidden.contains(entry.level),
        )
        .length;
    _scheduleRenderedSync(visible);
    return SafeArea(
      minimum: const EdgeInsets.all(18),
      child: Dialog(
        insetPadding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(mediaSize.width - 36, 960),
            maxHeight: dialogMaxHeight,
            minHeight: math.min(dialogMaxHeight, 480),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
                child: Row(
                  children: [
                    const Icon(Icons.terminal_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Web 服务日志',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        IconButton(
                          tooltip: '加载历史更多',
                          onPressed: historicalCount > _historyLimit
                              ? () => setState(
                                  () => _historyLimit += _lastPageSize,
                                )
                              : null,
                          icon: const Icon(Icons.history_rounded),
                        ),
                        IconButton(
                          tooltip: '加载最新日志',
                          onPressed: _loadLatestLogs,
                          icon: const Icon(Icons.new_releases_outlined),
                        ),
                        IconButton(
                          tooltip: _follow ? '取消跟随' : '跟随日志',
                          onPressed: () => setState(() => _follow = !_follow),
                          icon: Icon(
                            _follow
                                ? Icons.vertical_align_bottom_rounded
                                : Icons.vertical_align_center_rounded,
                          ),
                        ),
                        IconButton(
                          tooltip: '保存日志到剪贴板',
                          onPressed: () => _copyLogs(visible),
                          icon: const Icon(Icons.content_copy_rounded),
                        ),
                        IconButton(
                          tooltip: '导出当前日志',
                          onPressed: _isExportingLog ? null : _exportCurrentLog,
                          icon: _isExportingLog
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_alt_rounded),
                        ),
                        // 清空终端：仅清除当前弹窗内的渲染项，
                        // 底层服务的日志环形缓冲与磁盘文件保持不变（类似 shell `clear`）。
                        IconButton(
                          tooltip: '清空终端（仅清除显示，不删除日志文件）',
                          onPressed: _clearTerminal,
                          icon: const Icon(Icons.cleaning_services_outlined),
                        ),
                        // 日志级别多选菜单：取代原来顶部的 FilterChip 条，并走
                        // OpenHand 共用菜单转场，让 App / Web 服务面板的进退场手感一致。
                        AnimatedPopupMenuButton<WebGatewayLogLevel>(
                          tooltip: '日志级别筛选',
                          icon: const Icon(Icons.filter_list_rounded),
                          // 返回 null 代表点击了外部区域 / Esc，不需要响应。
                          onSelected: (level) =>
                              setState(() => _toggleLogLevel(level)),
                          // 多选能力：在 itemBuilder 里手搽复选框，
                          // 点击任一项都在 onSelected 里进行反选。
                          itemBuilder: (menuContext) => WebGatewayLogLevel
                              .values
                              .map(
                                (level) =>
                                    CheckedPopupMenuItem<WebGatewayLogLevel>(
                                      value: level,
                                      checked: !_hidden.contains(level),
                                      child: Text(level.name),
                                    ),
                              )
                              .toList(growable: false),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Container(
                  color: const Color(0xFF101218),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _scrollGuard.handleNotification,
                    child: OpenHandSafeScrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: AnimatedList(
                        key: _listKey,
                        initialItemCount: _rendered.length,
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                        itemBuilder: (context, index, animation) =>
                            _AnimatedLogLine(
                              entry: _rendered[index],
                              animation: animation,
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 在 _hidden 集合中切换一个级别的可见性。
  // 保证至少保留一个级别可见，避免用户误操作后看到空列表。
  void _toggleLogLevel(WebGatewayLogLevel level) {
    if (_hidden.contains(level)) {
      _hidden.remove(level);
      return;
    }
    final wouldHideAll = _hidden.length + 1 >= WebGatewayLogLevel.values.length;
    if (wouldHideAll) return;
    _hidden.add(level);
  }

  // 清空终端：仅清零当前弹窗内的渲染项。
  // 使用 _anchorLogId = 当前最后一条日志的 id，以后只追加新增日志；
  // _historyLimit 归 0，避免下一次渲染又把历史记录拉回来。
  // 底层 service.logs 与磁盘日志文件都不动，效果类似 shell `clear`。
  void _clearTerminal() {
    final logs = widget.controller.logs;
    setState(() {
      _anchorLogId = logs.isEmpty ? 0 : logs.last.id;
      _historyLimit = 0;
    });
    _showGatewaySnackBar(
      context,
      const SnackBar(
        content: Text('终端显示已清空，底层日志文件保持不变'),
        duration: Duration(milliseconds: 1600),
      ),
    );
  }

  List<WebGatewayLogEntry> _visibleLogs(List<WebGatewayLogEntry> logs) {
    final historical = logs
        .where(
          (entry) => entry.id <= _anchorLogId && !_hidden.contains(entry.level),
        )
        .toList(growable: false);
    final live = logs
        .where(
          (entry) => entry.id > _anchorLogId && !_hidden.contains(entry.level),
        )
        .toList(growable: false);
    final start = math.max(0, historical.length - _historyLimit);
    return <WebGatewayLogEntry>[
      if (_historyLimit > 0) ...historical.skip(start),
      ...live,
    ];
  }

  int _logFingerprint(List<WebGatewayLogEntry> logs) {
    var hash = logs.length;
    for (final entry in logs) {
      hash = 0x3fffffff & (hash * 31 + entry.id);
    }
    return hash;
  }

  void _scheduleRenderedSync(List<WebGatewayLogEntry> target) {
    final fingerprint = _logFingerprint(target);
    if (fingerprint == _renderedFingerprint && !_syncScheduled) return;
    _pendingRenderedTarget = List<WebGatewayLogEntry>.from(target);
    _pendingRenderedFingerprint = fingerprint;
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncScheduled = false;
      _renderedFingerprint = _pendingRenderedFingerprint;
      _syncRendered(_pendingRenderedTarget);
      if (_follow) _scrollToBottomSoon();
    });
  }

  void _syncRendered(List<WebGatewayLogEntry> target) {
    final listState = _listKey.currentState;
    if (listState == null) {
      setState(() {
        _rendered
          ..clear()
          ..addAll(target);
        _renderedIds
          ..clear()
          ..addAll(target.map((entry) => entry.id));
      });
      return;
    }
    final targetIds = target.map((entry) => entry.id).toSet();
    for (var index = _rendered.length - 1; index >= 0; index--) {
      final entry = _rendered[index];
      if (!targetIds.contains(entry.id)) {
        _rendered.removeAt(index);
        _renderedIds.remove(entry.id);
        listState.removeItem(
          index,
          (context, animation) => _AnimatedLogLine(
            entry: entry,
            animation: animation,
            removing: true,
          ),
          duration: _motionDuration(context, 220),
        );
      }
    }
    for (var targetIndex = 0; targetIndex < target.length; targetIndex++) {
      final entry = target[targetIndex];
      if (_renderedIds.contains(entry.id)) continue;
      final insertIndex = math.min(targetIndex, _rendered.length);
      _rendered.insert(insertIndex, entry);
      _renderedIds.add(entry.id);
      listState.insertItem(
        insertIndex,
        duration: _motionDuration(context, 280),
      );
    }
  }

  void _loadLatestLogs() {
    final logs = widget.controller.logs;
    setState(() {
      _anchorLogId = logs.isEmpty ? 0 : logs.last.id;
      _historyLimit = _lastPageSize;
    });
    _scrollToBottomSoon();
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollGuard.followToBottom(
        _scrollController,
        animated: true,
        animationDuration: _motionDuration(context, 220),
      );
    });
  }

  Future<void> _copyLogs(List<WebGatewayLogEntry> logs) async {
    await Clipboard.setData(
      ClipboardData(text: logs.map((entry) => entry.toLogLine()).join('\n')),
    );
    if (!mounted) return;
    _showGatewaySnackBar(context, const SnackBar(content: Text('日志已保存到剪贴板')));
  }

  Future<void> _exportCurrentLog() async {
    if (_isExportingLog) return;
    setState(() => _isExportingLog = true);
    final stamp = DateTime.now()
        .toLocal()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    try {
      final location = await getSaveLocation(
        suggestedName: 'openhand-web-gateway-current-$stamp.log',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Log', extensions: ['log', 'txt', 'jsonl']),
        ],
      );
      if (location == null) return;
      final text = await widget.controller.exportCurrentLogText();
      await File(location.path).writeAsString(text);
      if (!mounted) return;
      _showGatewaySnackBar(
        context,
        SnackBar(
          content: Text(
            '当前日志已导出到 ${location.path}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showGatewaySnackBar(
        context,
        SnackBar(
          content: Text(
            '当前日志导出失败: $error',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isExportingLog = false);
    }
  }
}

class _WebGatewayOpsDialog extends StatefulWidget {
  const _WebGatewayOpsDialog({required this.controller});

  final MessageGatewayController controller;

  @override
  State<_WebGatewayOpsDialog> createState() => _WebGatewayOpsDialogState();
}

class _WebGatewayOpsDialogState extends State<_WebGatewayOpsDialog> {
  static const Duration _refreshInterval = Duration(seconds: 2);
  static const int _trendLimit = 40;

  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  final List<WebGatewayRuntimeSnapshot> _trend = <WebGatewayRuntimeSnapshot>[];
  bool _isCleaning = false;
  bool _isRefreshingSnapshot = false;
  bool _isServiceActing = false;
  bool _isHealthChecking = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(_refreshInterval, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    if (!mounted || _isRefreshingSnapshot) return;
    _isRefreshingSnapshot = true;
    try {
      final snapshot = await widget.controller.refreshRuntimeSnapshot();
      if (!mounted) return;
      setState(() {
        _trend.add(snapshot);
        if (_trend.length > _trendLimit) _trend.removeAt(0);
      });
    } finally {
      _isRefreshingSnapshot = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _trend.isEmpty
        ? widget.controller.runtimeSnapshot()
        : _trend.last;
    final cleanupHistory = widget.controller.cleanupHistory.reversed
        .take(6)
        .toList(growable: false);
    final isRunning = widget.controller.isRunning;
    final isTransitioning =
        snapshot.state == WebGatewayRuntimeState.starting ||
        snapshot.state == WebGatewayRuntimeState.stopping;
    final serviceControlsDisabled = _isServiceActing || isTransitioning;
    final mediaSize = MediaQuery.sizeOf(context);
    final dialogMaxHeight = math.min(
      720.0,
      math.max(420.0, mediaSize.height - 120),
    );
    return SafeArea(
      minimum: const EdgeInsets.all(18),
      child: Dialog(
        insetPadding: EdgeInsets.zero,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(mediaSize.width - 36, 1100),
            maxHeight: dialogMaxHeight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.speed_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Web 服务运维',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: OpenHandSafeScrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    primary: false,
                    physics: const OpenHandBouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedOpacity(
                          duration: _motionDuration(context, 220),
                          curve: Curves.easeOutCubic,
                          opacity: serviceControlsDisabled ? .62 : 1,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: isRunning || serviceControlsDisabled
                                    ? null
                                    : () => _runServiceAction(
                                        label: '开启',
                                        action: widget.controller.startService,
                                      ),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('开启'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: !isRunning || serviceControlsDisabled
                                    ? null
                                    : () => _runServiceAction(
                                        label: '关机',
                                        action: widget.controller.stopService,
                                      ),
                                icon: const Icon(Icons.stop_rounded),
                                label: const Text('关机'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: serviceControlsDisabled
                                    ? null
                                    : () => _runServiceAction(
                                        label: '重启',
                                        action:
                                            widget.controller.restartService,
                                      ),
                                icon: const Icon(Icons.restart_alt_rounded),
                                label: const Text('重启'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: serviceControlsDisabled
                                    ? null
                                    : () => _runServiceAction(
                                        label: '配置重载',
                                        action: widget.controller.reloadConfig,
                                      ),
                                icon: const Icon(Icons.sync_rounded),
                                label: const Text('配置重载'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: serviceControlsDisabled
                                    ? null
                                    : () => _runServiceAction(
                                        label: '热修复',
                                        action: widget.controller.hotFix,
                                      ),
                                icon: const Icon(Icons.healing_rounded),
                                label: const Text('热修复'),
                              ),
                              FilledButton.icon(
                                onPressed: _isHealthChecking
                                    ? null
                                    : _runOpsHealthCheck,
                                icon: _isHealthChecking
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.monitor_heart_outlined),
                                label: const Text('健康诊断'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _isCleaning
                                    ? null
                                    : () => _runCleanup(
                                        label: '过期资源',
                                        action: widget
                                            .controller
                                            .cleanupExpiredArtifacts,
                                      ),
                                icon: const Icon(
                                  Icons.cleaning_services_outlined,
                                ),
                                label: const Text('清理过期'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _isCleaning
                                    ? null
                                    : () => _confirmAndCleanup(
                                        title: '清空日志',
                                        message:
                                            '会清空内存日志和 Web 服务磁盘日志，保留策略不会保留当前内容。',
                                        label: '日志',
                                        action: widget.controller.cleanupLogs,
                                      ),
                                icon: const Icon(Icons.delete_sweep_outlined),
                                label: const Text('清空日志'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _isCleaning
                                    ? null
                                    : () => _confirmAndCleanup(
                                        title: '清空上传缓存',
                                        message:
                                            '会删除 Web 消息附件落盘缓存，不影响已经写入会话的消息记录。',
                                        label: '上传缓存',
                                        action: widget
                                            .controller
                                            .cleanupUploadCache,
                                      ),
                                icon: const Icon(Icons.folder_delete_outlined),
                                label: const Text('清空缓存'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth < 760 ? 2 : 4;
                            return GridView.count(
                              crossAxisCount: columns,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: columns == 2 ? 2.1 : 2.4,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                _MetricTile(
                                  label: '运行状态',
                                  value: _runtimeStateLabel(
                                    context,
                                    snapshot.state,
                                  ),
                                ),
                                _MetricTile(
                                  label: '运行时间',
                                  value: _formatDuration(snapshot.uptimeMs),
                                ),
                                _MetricTile(
                                  label: 'CPU',
                                  value: snapshot.cpuPercent == null
                                      ? '不可用'
                                      : '${snapshot.cpuPercent!.toStringAsFixed(1)}%',
                                ),
                                _MetricTile(
                                  label: '线程数',
                                  value:
                                      snapshot.threadCount?.toString() ?? '不可用',
                                ),
                                _MetricTile(
                                  label: '文件句柄',
                                  value:
                                      snapshot.fileHandleCount?.toString() ??
                                      '不可用',
                                ),
                                _MetricTile(
                                  label: 'Swap',
                                  value: snapshot.swapBytes == null
                                      ? '不可用'
                                      : _bytes(snapshot.swapBytes!),
                                ),
                                _MetricTile(
                                  label: '内存',
                                  value: _bytes(snapshot.currentRssBytes),
                                ),
                                _MetricTile(
                                  label: '最大内存',
                                  value: _bytes(snapshot.maxRssBytes),
                                ),
                                _MetricTile(
                                  label: '日志磁盘',
                                  value: _bytes(snapshot.logBytes),
                                ),
                                _MetricTile(
                                  label: '活动请求',
                                  value: '${snapshot.activeRequests}',
                                ),
                                _MetricTile(
                                  label: 'SSE 长连接',
                                  value: '${snapshot.activeSseSubscriptions}',
                                ),
                                _MetricTile(
                                  label: '总请求',
                                  value: '${snapshot.totalRequests}',
                                ),
                                _MetricTile(
                                  label: '请求/min',
                                  value: _rate(snapshot.requestsPerMinute),
                                ),
                                _MetricTile(
                                  label: '错误数',
                                  value: '${snapshot.totalErrors}',
                                ),
                                _MetricTile(
                                  label: '错误/min',
                                  value: _rate(snapshot.errorsPerMinute),
                                ),
                                _MetricTile(
                                  label: '入流量/min',
                                  value: _bytes(
                                    snapshot.bytesInPerMinute.round(),
                                  ),
                                ),
                                _MetricTile(
                                  label: '出流量/min',
                                  value: _bytes(
                                    snapshot.bytesOutPerMinute.round(),
                                  ),
                                ),
                                _MetricTile(
                                  label: '延迟 P95',
                                  value: '${snapshot.latencyStats.p95Ms}ms',
                                ),
                                _MetricTile(
                                  label: '延迟 P50',
                                  value: '${snapshot.latencyStats.p50Ms}ms',
                                ),
                                _MetricTile(
                                  label: '延迟 P99',
                                  value: '${snapshot.latencyStats.p99Ms}ms',
                                ),
                                _MetricTile(
                                  label: '延迟 MAX',
                                  value: '${snapshot.latencyStats.maxMs}ms',
                                ),
                                _MetricTile(
                                  label: '延迟样本',
                                  value: '${snapshot.latencyStats.sampleCount}',
                                ),
                                _MetricTile(
                                  label: '累计入流量',
                                  value: _bytes(snapshot.totalBytesIn),
                                ),
                                _MetricTile(
                                  label: '累计出流量',
                                  value: _bytes(snapshot.totalBytesOut),
                                ),
                                _MetricTile(
                                  label: '崩溃数',
                                  value: '${snapshot.crashCount}',
                                ),
                                _MetricTile(
                                  label: '重启数',
                                  value: '${snapshot.restartCount}',
                                ),
                                _MetricTile(
                                  label: '线程会话',
                                  value: '${snapshot.openSessionCount}',
                                ),
                                _MetricTile(
                                  label: '并发水位',
                                  value: _percent(snapshot.activeRequestRatio),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        _OpsHealthCard(snapshot: snapshot),
                        const SizedBox(height: 18),
                        _OpsSummaryCard(snapshot: snapshot),
                        const SizedBox(height: 18),
                        _NaturalCardGrid(
                          minTileWidth: 360,
                          spacing: 12,
                          maxColumns: 2,
                          children: [
                            _OpsBreakdownCard(
                              title: 'HTTP 状态码分布',
                              values: snapshot.statusCodeBreakdown,
                            ),
                            _OpsBreakdownCard(
                              title: 'HTTP Method 分布',
                              values: snapshot.methodBreakdown,
                            ),
                            _OpsBreakdownCard(
                              title: '延迟桶',
                              values: snapshot.latencyBuckets,
                            ),
                            _OpsBreakdownCard(
                              title: '发送阶段分布',
                              values: snapshot.sendPhaseBreakdown,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _NaturalCardGrid(
                          minTileWidth: 360,
                          spacing: 12,
                          maxColumns: 2,
                          children: [
                            _TopRoutesCard(routes: snapshot.topRoutes),
                            _RecentErrorsCard(errors: snapshot.recentErrors),
                            _OpsBreakdownCard(
                              title: '日志级别分布',
                              values: snapshot.logLevelBreakdown,
                              footer: '${snapshot.memoryLogCount} 条内存日志',
                            ),
                            _ResourceInventoryCard(snapshot: snapshot),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const _SectionTitle('吞吐趋势'),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth < 720 ? 1 : 2;
                            return GridView.count(
                              crossAxisCount: columns,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: columns == 1 ? 2.35 : 1.85,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                _TrendLineChart(
                                  title: '请求/秒',
                                  values: _deltaSeries(
                                    _trend,
                                    (snapshot) =>
                                        snapshot.totalRequests.toDouble(),
                                  ),
                                  valueFormatter: (value) =>
                                      value.toStringAsFixed(0),
                                ),
                                _TrendLineChart(
                                  title: '错误/秒',
                                  values: _deltaSeries(
                                    _trend,
                                    (snapshot) =>
                                        snapshot.totalErrors.toDouble(),
                                  ),
                                  valueFormatter: (value) =>
                                      value.toStringAsFixed(0),
                                ),
                                _TrendLineChart(
                                  title: '活动请求',
                                  values: _series(
                                    _trend,
                                    (snapshot) =>
                                        snapshot.activeRequests.toDouble(),
                                  ),
                                  valueFormatter: (value) =>
                                      value.toStringAsFixed(0),
                                ),
                                _TrendLineChart(
                                  title: 'P95 延迟',
                                  values: _series(
                                    _trend,
                                    (snapshot) =>
                                        snapshot.latencyStats.p95Ms.toDouble(),
                                  ),
                                  valueFormatter: (value) =>
                                      '${value.toStringAsFixed(0)}ms',
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        const _SectionTitle('资源趋势'),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth < 720 ? 1 : 2;
                            return GridView.count(
                              crossAxisCount: columns,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: columns == 1 ? 2.35 : 1.85,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                _TrendLineChart(
                                  title: 'CPU %',
                                  values: _series(
                                    _trend,
                                    (snapshot) => snapshot.cpuPercent,
                                  ),
                                  valueFormatter: (value) =>
                                      '${value.toStringAsFixed(1)}%',
                                ),
                                _TrendLineChart(
                                  title: '内存 RSS',
                                  values: _series(
                                    _trend,
                                    (snapshot) =>
                                        snapshot.currentRssBytes.toDouble(),
                                  ),
                                  valueFormatter: (value) =>
                                      _bytes(value.round()),
                                ),
                                _TrendLineChart(
                                  title: '日志磁盘',
                                  values: _series(
                                    _trend,
                                    (snapshot) => snapshot.logBytes.toDouble(),
                                  ),
                                  valueFormatter: (value) =>
                                      _bytes(value.round()),
                                ),
                                _TrendLineChart(
                                  title: '线程数',
                                  values: _series(
                                    _trend,
                                    (snapshot) =>
                                        snapshot.threadCount?.toDouble(),
                                  ),
                                  valueFormatter: (value) =>
                                      value.toStringAsFixed(0),
                                ),
                                _TrendLineChart(
                                  title: '会话数',
                                  values: _series(
                                    _trend,
                                    (snapshot) =>
                                        snapshot.openSessionCount.toDouble(),
                                  ),
                                  valueFormatter: (value) =>
                                      value.toStringAsFixed(0),
                                ),
                                _TrendLineChart(
                                  title: '入流量/min',
                                  values: _series(
                                    _trend,
                                    (snapshot) => snapshot.bytesInPerMinute,
                                  ),
                                  valueFormatter: (value) =>
                                      _bytes(value.round()),
                                ),
                              ],
                            );
                          },
                        ),
                        if (cleanupHistory.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          const _SectionTitle('清理历史'),
                          ...cleanupHistory.map(
                            (entry) => _CleanupHistoryLine(entry: entry),
                          ),
                        ],
                        if (snapshot.lastError.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          const _SectionTitle('最近错误'),
                          SelectableText(snapshot.lastError),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndCleanup({
    required String title,
    required String message,
    required String label,
    required Future<WebGatewayCleanupResult> Function() action,
  }) async {
    final confirmed = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          OpenHandDialogActionButton.secondary(
            onPressed: () => Navigator.of(context).pop(false),
            label: '取消',
          ),
          OpenHandDialogActionButton.primary(
            onPressed: () => Navigator.of(context).pop(true),
            label: '确认清理',
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _runCleanup(label: label, action: action);
    }
  }

  Future<void> _runServiceAction({
    required String label,
    required Future<void> Function() action,
  }) async {
    if (_isServiceActing) return;
    setState(() => _isServiceActing = true);
    try {
      await action();
      await _tick();
      if (!mounted) return;
      _showGatewaySnackBar(
        context,
        SnackBar(
          content: Text('$label 已完成'),
          duration: const Duration(milliseconds: 1600),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showGatewaySnackBar(
        context,
        SnackBar(
          content: Text(
            '$label 失败: $error',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isServiceActing = false);
    }
  }

  Future<void> _runOpsHealthCheck() async {
    if (_isHealthChecking) return;
    setState(() => _isHealthChecking = true);
    try {
      final result = await widget.controller.runHealthCheck();
      await _tick();
      if (!mounted) return;
      _showGatewaySnackBar(
        context,
        SnackBar(
          content: Text('${result.summary} (${result.durationMs}ms)'),
          backgroundColor: result.ok ? const Color(0xFF16A34A) : null,
          duration: const Duration(milliseconds: 1800),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showGatewaySnackBar(
        context,
        SnackBar(
          content: Text(
            '健康诊断失败: $error',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isHealthChecking = false);
    }
  }

  Future<void> _runCleanup({
    required String label,
    required Future<WebGatewayCleanupResult> Function() action,
  }) async {
    if (_isCleaning) return;
    setState(() => _isCleaning = true);
    try {
      final result = await action();
      if (!mounted) return;
      _showGatewaySnackBar(
        context,
        SnackBar(
          content: Text(
            '$label清理完成，释放 ${_bytes(result.bytesFreed)}，删除 ${result.deletedFiles} 个文件',
          ),
        ),
      );
      await _tick();
    } catch (error) {
      if (!mounted) return;
      _showGatewaySnackBar(
        context,
        SnackBar(content: Text('$label清理失败: $error')),
      );
    } finally {
      if (mounted) setState(() => _isCleaning = false);
    }
  }
}

class _GatewayStateCard extends StatelessWidget {
  const _GatewayStateCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(body),
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
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 与 MCP `_McpHealthStatusDot` 对齐：16×16 + 3px surface 同色描边 + 32% 透明软阴影；
    // 颜色变化走 AnimatedContainer，但若全局动画被禁用则 duration 归零，避免不必要重绘。
    return AnimatedContainer(
      duration: _motionDuration(context, 180),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.surface, width: 3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.32),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class _FeatureIconButton extends StatelessWidget {
  const _FeatureIconButton({
    required this.tooltip,
    required this.enabled,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final bool enabled;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        style: IconButton.styleFrom(
          disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: .42),
          disabledForegroundColor: theme.colorScheme.onSurfaceVariant
              .withValues(alpha: .45),
        ),
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      side: BorderSide(color: theme.colorScheme.outlineVariant),
    );
  }
}

/// 监听通配符地址（0.0.0.0 / ::）时展示全部可访问 URL 的横向胶囊条。
/// 每个 URL 胶囊同时提供复制与浏览器访问动作。
class _AccessibleUrlsBar extends StatelessWidget {
  const _AccessibleUrlsBar({required this.urls});

  final List<String> urls;

  Future<void> _copy(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    _showGatewaySnackBar(context, SnackBar(content: Text('已复制 $url')));
  }

  Future<void> _open(BuildContext context, String url) async {
    try {
      final result = Platform.isMacOS
          ? await runProcessWithTimeout('open', <String>[
              url,
            ], tag: 'message_gateway.open_url')
          : Platform.isWindows
          ? await runProcessWithTimeout(
              'cmd',
              <String>['/c', 'start', '', url],
              tag: 'message_gateway.open_url',
              runInShell: true,
            )
          : await runProcessWithTimeout('xdg-open', <String>[
              url,
            ], tag: 'message_gateway.open_url');
      if (!context.mounted) return;
      if (result == null) {
        _showGatewaySnackBar(context, SnackBar(content: Text('打开失败: $url')));
        return;
      }
      _showGatewaySnackBar(context, SnackBar(content: Text('正在打开 $url')));
    } catch (error, stack) {
      silentLog('message_gateway_view', 'open url', error, stack);
      if (!context.mounted) return;
      _showGatewaySnackBar(context, SnackBar(content: Text('打开失败: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lan_outlined, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '可访问 URL（复制 / 访问）',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final url in urls)
              _AccessibleUrlPill(
                url: url,
                onCopy: () => _copy(context, url),
                onOpen: () => _open(context, url),
              ),
          ],
        ),
      ],
    );
  }
}

class _AccessibleUrlPill extends StatelessWidget {
  const _AccessibleUrlPill({
    required this.url,
    required this.onCopy,
    required this.onOpen,
  });

  final String url;
  final VoidCallback onCopy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.32),
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: '复制地址',
            child: IconButton(
              onPressed: onCopy,
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: cs.onPrimaryContainer,
                hoverColor: cs.primary.withValues(alpha: 0.08),
                highlightColor: cs.primary.withValues(alpha: 0.12),
                focusColor: cs.primary.withValues(alpha: 0.10),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.content_copy_rounded),
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            ),
          ),
          Flexible(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: cs.onPrimaryContainer,
              ),
            ),
          ),
          Tooltip(
            message: '浏览器访问',
            child: IconButton(
              onPressed: onOpen,
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: cs.onPrimaryContainer,
                hoverColor: cs.primary.withValues(alpha: 0.08),
                highlightColor: cs.primary.withValues(alpha: 0.12),
                focusColor: cs.primary.withValues(alpha: 0.10),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.open_in_browser_rounded),
              iconSize: 17,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 36, height: 34),
            ),
          ),
        ],
      ),
    );
  }
}

Object? _tryDecodeJson(String value) {
  try {
    return jsonDecode(value);
  } catch (_) {
    return null;
  }
}

String _formatStructuredValue(Object? value) {
  if (value == null) return 'null';
  if (value is String || value is num || value is bool) return '$value';
  try {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(value);
  } catch (_) {
    return '$value';
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.56,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: .74),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _sectionIconFor(text),
              size: 15,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: .72),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _sectionIconFor(String text) {
  if (text.contains('基础')) return Icons.info_outline_rounded;
  if (text.contains('鉴权')) return Icons.lock_outline_rounded;
  if (text.contains('安全')) return Icons.shield_outlined;
  if (text.contains('项目') || text.contains('资源')) {
    return Icons.folder_open_rounded;
  }
  if (text.contains('健康') || text.contains('入口')) {
    return Icons.monitor_heart_outlined;
  }
  if (text.contains('日志') || text.contains('错误')) return Icons.article_outlined;
  if (text.contains('吞吐') || text.contains('趋势')) return Icons.show_chart;
  if (text.contains('清理')) return Icons.cleaning_services_outlined;
  return Icons.tune_rounded;
}

class _NaturalCardGrid extends StatelessWidget {
  const _NaturalCardGrid({
    required this.children,
    this.minTileWidth = 320,
    required this.spacing,
    required this.maxColumns,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final possibleColumns =
          ((constraints.maxWidth + spacing) / (minTileWidth + spacing)).floor();
      final columns = possibleColumns.clamp(1, maxColumns).toInt();
      final tileWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children)
            SizedBox(width: tileWidth, child: child),
        ],
      );
    },
  );
}

class _OpsHealthCard extends StatelessWidget {
  const _OpsHealthCard({required this.snapshot});

  final WebGatewayRuntimeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diagnosis = _OpsDiagnosis.from(snapshot);
    final color = switch (diagnosis.tone) {
      _OpsDiagnosisTone.ok => Colors.green.shade700,
      _OpsDiagnosisTone.warn => Colors.orange.shade800,
      _OpsDiagnosisTone.error => theme.colorScheme.error,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(
        theme,
      ).copyWith(border: Border.all(color: color.withValues(alpha: 0.42))),
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
                      '运行健康度',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${diagnosis.score}',
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                            diagnosis.label,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.health_and_safety_outlined, size: 24),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: diagnosis.signals
                .map((signal) => _OpsPill(signal.label, signal.value))
                .toList(growable: false),
          ),
          const SizedBox(height: 12),
          ...diagnosis.recommendations.map((item) => _OpsKeyValue('建议', item)),
          const SizedBox(height: 4),
          Text(
            '阈值告警',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (diagnosis.alerts.isEmpty)
            Text(
              '暂无触发阈值',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: diagnosis.alerts
                  .map(
                    (alert) => _OpsPill(
                      alert.label,
                      '${alert.threshold} · ${alert.actual}',
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

enum _OpsDiagnosisTone { ok, warn, error }

class _OpsDiagnosisSignal {
  const _OpsDiagnosisSignal(this.label, this.value);
  final String label;
  final String value;
}

class _OpsDiagnosisAlert {
  const _OpsDiagnosisAlert(this.label, this.threshold, this.actual);
  final String label;
  final String threshold;
  final String actual;
}

class _OpsDiagnosis {
  const _OpsDiagnosis({
    required this.score,
    required this.label,
    required this.tone,
    required this.signals,
    required this.alerts,
    required this.recommendations,
  });

  factory _OpsDiagnosis.from(WebGatewayRuntimeSnapshot snapshot) {
    var score = 100;
    final recommendations = <String>[];
    final alerts = <_OpsDiagnosisAlert>[];
    final errorRate = snapshot.totalRequests <= 0
        ? 0.0
        : snapshot.totalErrors / snapshot.totalRequests;
    final p95 = snapshot.latencyStats.p95Ms;
    final p99 = snapshot.latencyStats.p99Ms;
    final saturation = snapshot.activeRequestRatio;
    final logErrors = snapshot.logLevelBreakdown['error'] ?? 0;

    if (snapshot.state == WebGatewayRuntimeState.crashed) {
      score -= 45;
      alerts.add(_OpsDiagnosisAlert('服务状态', 'running', snapshot.state.name));
      recommendations.add('服务处于 crashed，优先查看最近错误和内存日志并重启服务。');
    } else if (snapshot.state != WebGatewayRuntimeState.running) {
      score -= 20;
      alerts.add(_OpsDiagnosisAlert('服务状态', 'running', snapshot.state.name));
      recommendations.add('服务未处于 running，确认监听端口、鉴权配置和启动日志。');
    }
    if (errorRate >= 0.05) {
      score -= 25;
      alerts.add(_OpsDiagnosisAlert('错误率', '>= 5%', _percent(errorRate)));
      recommendations.add('错误率超过 5%，优先按最近错误路径定位 4xx/5xx 来源。');
    } else if (errorRate >= 0.01) {
      score -= 12;
      alerts.add(_OpsDiagnosisAlert('错误率', '>= 1%', _percent(errorRate)));
      recommendations.add('错误率超过 1%，建议核对请求来源、模型服务和文件权限。');
    }
    if (snapshot.errorsPerMinute > 0) {
      score -= math.min(15, 5 + (snapshot.errorsPerMinute * 2).round());
      alerts.add(
        _OpsDiagnosisAlert('错误/min', '> 0', _rate(snapshot.errorsPerMinute)),
      );
      recommendations.add('最近 1 分钟仍有错误增长，观察错误是否持续并检查对应路由。');
    }
    if (saturation >= 0.85) {
      score -= 20;
      alerts.add(_OpsDiagnosisAlert('并发水位', '>= 85%', _percent(saturation)));
      recommendations.add('并发水位接近上限，建议降低长连接/轮询压力或提高并发限制。');
    } else if (saturation >= 0.6) {
      score -= 10;
      alerts.add(_OpsDiagnosisAlert('并发水位', '>= 60%', _percent(saturation)));
      recommendations.add('并发水位偏高，继续观察请求排队和 SSE 连接数。');
    }
    if (p95 >= 3000) {
      score -= 15;
      alerts.add(_OpsDiagnosisAlert('P95 延迟', '>= 3000ms', '${p95}ms'));
      recommendations.add('P95 延迟超过 3s，建议检查慢路由、上游模型和文件 IO。');
    } else if (p95 >= 1000) {
      score -= 8;
      alerts.add(_OpsDiagnosisAlert('P95 延迟', '>= 1000ms', '${p95}ms'));
      recommendations.add('P95 延迟超过 1s，可结合 Top Routes 排查热点路径。');
    }
    if (snapshot.crashCount > 0 || snapshot.restartCount > 0) {
      score -= math.min(
        12,
        snapshot.crashCount * 6 + snapshot.restartCount * 2,
      );
      alerts.add(
        _OpsDiagnosisAlert(
          '崩溃/重启',
          '= 0',
          '${snapshot.crashCount}/${snapshot.restartCount}',
        ),
      );
    }
    if (logErrors > 0) {
      score -= math.min(10, logErrors);
      alerts.add(_OpsDiagnosisAlert('错误日志', '= 0', '$logErrors'));
    }
    if (recommendations.isEmpty) {
      recommendations.add('当前核心信号平稳，保持自动刷新并关注错误率、P95 延迟和并发水位。');
    }
    score = score.clamp(0, 100).toInt();
    final tone = score >= 85
        ? _OpsDiagnosisTone.ok
        : score >= 65
        ? _OpsDiagnosisTone.warn
        : _OpsDiagnosisTone.error;
    final label = switch (tone) {
      _OpsDiagnosisTone.ok => '健康',
      _OpsDiagnosisTone.warn => '需关注',
      _OpsDiagnosisTone.error => '异常',
    };
    return _OpsDiagnosis(
      score: score,
      label: label,
      tone: tone,
      recommendations: recommendations.take(4).toList(growable: false),
      alerts: alerts,
      signals: [
        _OpsDiagnosisSignal('错误率', _percent(errorRate)),
        _OpsDiagnosisSignal('P95', p95 > 0 ? '${p95}ms' : '—'),
        _OpsDiagnosisSignal('P99', p99 > 0 ? '${p99}ms' : '—'),
        _OpsDiagnosisSignal('并发水位', _percent(saturation)),
        _OpsDiagnosisSignal('错误/min', _rate(snapshot.errorsPerMinute)),
        _OpsDiagnosisSignal('SSE', '${snapshot.activeSseSubscriptions}'),
      ],
    );
  }

  final int score;
  final String label;
  final _OpsDiagnosisTone tone;
  final List<_OpsDiagnosisSignal> signals;
  final List<_OpsDiagnosisAlert> alerts;
  final List<String> recommendations;
}

class _OpsSummaryCard extends StatelessWidget {
  const _OpsSummaryCard({required this.snapshot});

  final WebGatewayRuntimeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slow = snapshot.slowestRecent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart_outlined, size: 18),
              const SizedBox(width: 8),
              Text('Golden Signals', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OpsPill(
                'Traffic',
                '${_rate(snapshot.requestsPerMinute)} req/min',
              ),
              _OpsPill('Errors', '${_rate(snapshot.errorsPerMinute)} err/min'),
              _OpsPill(
                'Latency',
                'avg ${snapshot.latencyStats.avgMs}ms / p95 ${snapshot.latencyStats.p95Ms}ms / p99 ${snapshot.latencyStats.p99Ms}ms',
              ),
              _OpsPill(
                'Saturation',
                '${snapshot.activeRequests}/${snapshot.maxConcurrentRequests} active · ${_percent(snapshot.activeRequestRatio)}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _OpsKeyValue(
            '绑定地址',
            snapshot.boundUrl.isEmpty ? '未监听' : snapshot.boundUrl,
          ),
          _OpsKeyValue(
            '可访问 URL',
            snapshot.accessibleUrls.isEmpty
                ? '暂无'
                : snapshot.accessibleUrls.join(' / '),
          ),
          _OpsKeyValue(
            '主机 / Dart',
            '${snapshot.hostName.isEmpty ? 'unknown' : snapshot.hostName} · ${snapshot.dartVersion.isEmpty ? 'unknown' : snapshot.dartVersion}',
          ),
          if (slow != null)
            _OpsKeyValue(
              '近期最慢请求',
              '${slow.method} ${slow.path} -> ${slow.statusCode} · ${slow.durationMs}ms${slow.at == null ? '' : ' · ${_dateTime(slow.at!)}'}',
            ),
        ],
      ),
    );
  }
}

class _OpsBreakdownCard extends StatelessWidget {
  const _OpsBreakdownCard({
    required this.title,
    required this.values,
    this.footer,
  });

  final String title;
  final Map<String, int> values;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Text(
              '暂无样本',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...entries
                .take(8)
                .map(
                  (entry) => _OpsDistributionRow(
                    label: entry.key,
                    value: entry.value,
                    total: total,
                  ),
                ),
          if (footer != null) ...[
            const SizedBox(height: 12),
            Text(
              footer!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OpsDistributionRow extends StatelessWidget {
  const _OpsDistributionRow({
    required this.label,
    required this.value,
    required this.total,
  });

  final String label;
  final int value;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = total <= 0 ? 0.0 : value / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(width: 8),
              Text('$value', style: theme.textTheme.labelMedium),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0).toDouble(),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopRoutesCard extends StatelessWidget {
  const _TopRoutesCard({required this.routes});

  final List<MapEntry<String, int>> routes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top Routes', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          if (routes.isEmpty)
            Text(
              '暂无路由样本',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...routes
                .take(8)
                .map((entry) => _OpsKeyValue(entry.key, '${entry.value} 次')),
        ],
      ),
    );
  }
}

class _RecentErrorsCard extends StatelessWidget {
  const _RecentErrorsCard({required this.errors});

  final List<Map<String, Object?>> errors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('近期错误请求', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          if (errors.isEmpty)
            Text(
              '暂无 4xx/5xx 请求',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...errors.reversed.take(6).map((entry) {
              final method = entry['method']?.toString() ?? '';
              final path = entry['path']?.toString() ?? '';
              final status = entry['status']?.toString() ?? '';
              final duration = entry['duration_ms']?.toString() ?? '';
              return _OpsKeyValue('$method $path', '$status · ${duration}ms');
            }),
        ],
      ),
    );
  }
}

class _ResourceInventoryCard extends StatelessWidget {
  const _ResourceInventoryCard({required this.snapshot});

  final WebGatewayRuntimeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _opsCardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Web 可见资源', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OpsPill('模型', '${snapshot.allowedModelCount}'),
              _OpsPill('供应商', '${snapshot.modelProviderCount}'),
              _OpsPill('模板', '${snapshot.templateCount}'),
              _OpsPill(
                'Crons',
                '${snapshot.cronEnabledCount}/${snapshot.cronTotalCount}',
              ),
              _OpsPill('Memory', '${snapshot.memoryEntryCount}'),
              _OpsPill(
                'MCP',
                '${snapshot.mcpServerEnabledCount}/${snapshot.mcpServerTotalCount}',
              ),
              _OpsPill('SSE', '${snapshot.activeSseSubscriptions}'),
              _OpsPill('会话', '${snapshot.openSessionCount}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _OpsPill extends StatelessWidget {
  const _OpsPill(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.48,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpsKeyValue extends StatelessWidget {
  const _OpsKeyValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 2,
              style: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _opsCardDecoration(ThemeData theme) => BoxDecoration(
  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.36),
  borderRadius: BorderRadius.circular(8),
  border: Border.all(color: theme.colorScheme.outlineVariant),
);

class _SwitchGrid extends StatelessWidget {
  const _SwitchGrid({required this.twoColumns, required this.children});
  final bool twoColumns;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: twoColumns ? 2 : 1,
    childAspectRatio: twoColumns ? 5.0 : 5.8,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: children,
  );
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AnimatedContainer(
      duration: _motionDuration(context, 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: value
            ? colorScheme.primaryContainer.withValues(alpha: .34)
            : colorScheme.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value
              ? colorScheme.primary.withValues(alpha: .32)
              : colorScheme.outlineVariant.withValues(alpha: .78),
        ),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: value ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 0, 10, 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _TextArea extends StatelessWidget {
  const _TextArea({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      minLines: 3,
      maxLines: 5,
      decoration: _gatewayInputDecoration(context, label),
    ),
  );
}

class _TextFieldSpec {
  const _TextFieldSpec({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.obscureText = false,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.twoColumns, required this.children});
  final bool twoColumns;
  final List<_TextFieldSpec> children;
  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: twoColumns ? 2 : 1,
    childAspectRatio: twoColumns ? 5.0 : 6.0,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    children: children
        .map(
          (spec) => TextField(
            controller: spec.controller,
            keyboardType: spec.keyboardType,
            obscureText: spec.obscureText,
            decoration: _gatewayInputDecoration(context, spec.label),
          ),
        )
        .toList(growable: false),
  );
}

InputDecoration _gatewayInputDecoration(BuildContext context, String label) {
  final colorScheme = Theme.of(context).colorScheme;
  final radius = BorderRadius.circular(16);
  final border = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(
      color: colorScheme.outlineVariant.withValues(alpha: .78),
    ),
  );
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: .44),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
    ),
  );
}

class _SelectOption<T> {
  const _SelectOption({required this.value, required this.label});
  final T value;
  final String label;
}

class _MultiSelectDropdown<T> extends StatefulWidget {
  const _MultiSelectDropdown({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.emptyMeansAll = false,
    this.noneValue,
  });

  final String label;
  final List<_SelectOption<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool emptyMeansAll;
  final T? noneValue;

  @override
  State<_MultiSelectDropdown<T>> createState() =>
      _MultiSelectDropdownState<T>();
}

class _MultiSelectDropdownState<T> extends State<_MultiSelectDropdown<T>> {
  final MenuController _menuController = MenuController();

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MenuAnchor(
        controller: _menuController,
        alignmentOffset: const Offset(0, 8),
        menuChildren: [
          _MultiSelectDropdownMenu<T>(
            label: widget.label,
            options: widget.options,
            selected: widget.selected,
            emptyMeansAll: widget.emptyMeansAll,
            noneValue: widget.noneValue,
            onApply: widget.onChanged,
            onClose: _menuController.close,
          ),
        ],
        builder: (context, controller, child) {
          final open = controller.isOpen;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => open ? controller.close() : controller.open(),
            child: InputDecorator(
              decoration:
                  _gatewayInputDecoration(
                    context,
                    widget.emptyMeansAll
                        ? '${widget.label}（空=全部）'
                        : widget.label,
                  ).copyWith(
                    suffixIcon: Icon(
                      open
                          ? Icons.arrow_drop_up_rounded
                          : Icons.arrow_drop_down_rounded,
                    ),
                  ),
              child: Text(
                _summary(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          );
        },
      ),
    );
  }

  String _summary() {
    if (_isExplicitNone(widget.selected, widget.noneValue)) return '全部不可用';
    if (widget.emptyMeansAll && widget.selected.isEmpty) return '全部可用';
    if (widget.selected.isEmpty) return '未选择';
    final labels = widget.options
        .where((option) => widget.selected.contains(option.value))
        .map((option) => option.label)
        .toList(growable: false);
    if (labels.length <= 2) return labels.join('、');
    return '${labels.take(2).join('、')} 等 ${labels.length} 项';
  }
}

class _MultiSelectDropdownMenu<T> extends StatefulWidget {
  const _MultiSelectDropdownMenu({
    required this.label,
    required this.options,
    required this.selected,
    required this.emptyMeansAll,
    required this.noneValue,
    required this.onApply,
    required this.onClose,
  });

  final String label;
  final List<_SelectOption<T>> options;
  final Set<T> selected;
  final bool emptyMeansAll;
  final T? noneValue;
  final ValueChanged<Set<T>> onApply;
  final VoidCallback onClose;

  @override
  State<_MultiSelectDropdownMenu<T>> createState() =>
      _MultiSelectDropdownMenuState<T>();
}

class _MultiSelectDropdownMenuState<T>
    extends State<_MultiSelectDropdownMenu<T>>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final AnimationController _transitionController;
  late Set<T> _selected;
  bool _closing = false;
  DialogAnimationSettings? _lastMotionSettings;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(vsync: this);
    _selected = Set<T>.from(widget.selected);
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = _dialogMotionSettingsOf(context);
    _lastMotionSettings = settings;
    _transitionController
      ..duration = settings.duration
      ..reverseDuration = settings.duration;
    if (_transitionController.value == 0 && !_closing) {
      if (MediaQuery.disableAnimationsOf(context) ||
          settings.duration == Duration.zero) {
        _transitionController.value = 1;
      } else {
        unawaited(_transitionController.forward());
      }
    }
  }

  @override
  void didUpdateWidget(covariant _MultiSelectDropdownMenu<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _selected = Set<T>.from(widget.selected);
    }
  }

  @override
  void dispose() {
    _transitionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = _lastMotionSettings ?? _dialogMotionSettingsOf(context);
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.options
        : widget.options
              .where((option) => option.label.toLowerCase().contains(query))
              .toList(growable: false);
    final filteredValues = filtered.map((option) => option.value).toSet();
    final totalValues = widget.options.map((option) => option.value).toSet();
    final effectiveSelected = _effectiveSelectedValues();
    final selectedCount = effectiveSelected.length;
    final scopeText = query.isEmpty ? '全部条目' : '当前筛选 ${filtered.length} 项';
    return buildAnimationStyleTransition(
      animation: _transitionController,
      settings: settings,
      child: Material(
        type: MaterialType.card,
        clipBehavior: Clip.antiAlias,
        elevation: 14,
        shadowColor: colorScheme.shadow.withValues(alpha: 0.18),
        surfaceTintColor: colorScheme.surfaceTint,
        color: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: SizedBox(
          width: 460,
          height: 410,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 10),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.label,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectionSummaryText(
                              selectedCount,
                              totalValues.length,
                              scopeText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _GatewayRoundIconActionButton(
                      tooltip: query.isEmpty ? '全选' : '当前筛选全选',
                      icon: Icons.done_all_rounded,
                      onPressed: filteredValues.isEmpty
                          ? null
                          : () => _selectValues(filteredValues),
                    ),
                    const SizedBox(width: 8),
                    _GatewayRoundIconActionButton(
                      tooltip: query.isEmpty ? '全不选' : '当前筛选全不选',
                      icon: Icons.remove_done_rounded,
                      onPressed: filteredValues.isEmpty
                          ? null
                          : () => _deselectValues(filteredValues),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.58,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    hintText: '搜索',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.72,
                        ),
                      ),
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空搜索',
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.clear_rounded, size: 18),
                          ),
                  ),
                ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          '没有匹配项',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final option = filtered[index];
                          final selected = effectiveSelected.contains(
                            option.value,
                          );
                          return Material(
                            color: selected
                                ? colorScheme.primaryContainer.withValues(
                                    alpha: 0.36,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            child: CheckboxListTile(
                              dense: true,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              value: selected,
                              onChanged: (_) => _toggle(option.value),
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                option.label,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        query.isEmpty ? '对全部条目生效' : '仅对当前筛选结果生效',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    _MenuActionButton(
                      onPressed: _applyAndClose,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('完成'),
                      filled: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggle(T value) {
    final next = _effectiveSelectedValues();
    if (next.contains(value)) {
      next.remove(value);
    } else {
      next.add(value);
    }
    _setEffectiveSelected(next);
  }

  Set<T> _effectiveSelectedValues() {
    if (_isExplicitNone(_selected, widget.noneValue)) return <T>{};
    if (widget.emptyMeansAll && _selected.isEmpty) {
      return widget.options.map((option) => option.value).toSet();
    }
    final values = widget.options.map((option) => option.value).toSet();
    return _selected.where(values.contains).toSet();
  }

  void _selectValues(Set<T> values) {
    final next = _effectiveSelectedValues()..addAll(values);
    _setEffectiveSelected(next);
  }

  void _deselectValues(Set<T> values) {
    final next = _effectiveSelectedValues()..removeAll(values);
    _setEffectiveSelected(next);
  }

  void _setEffectiveSelected(Set<T> values) {
    final allValues = widget.options.map((option) => option.value).toSet();
    if (values.isEmpty) {
      final noneValue = widget.noneValue;
      _setSelected(noneValue == null ? <T>{} : <T>{noneValue});
      return;
    }
    if (widget.emptyMeansAll && values.length == allValues.length) {
      _setSelected(<T>{});
      return;
    }
    _setSelected(values.intersection(allValues));
  }

  void _setSelected(Set<T> next) {
    setState(() => _selected = next);
  }

  void _applyAndClose() {
    if (_closing) return;
    widget.onApply(Set<T>.from(_selected));
    if (MediaQuery.disableAnimationsOf(context) ||
        _transitionController.duration == Duration.zero) {
      widget.onClose();
      return;
    }
    _closing = true;
    unawaited(
      _transitionController.reverse().whenComplete(() {
        if (mounted) widget.onClose();
      }),
    );
  }

  String _selectionSummaryText(
    int selectedCount,
    int totalCount,
    String scope,
  ) {
    if (_isExplicitNone(_selected, widget.noneValue)) return '$scope · 全部不可用';
    if (widget.emptyMeansAll && _selected.isEmpty) return '$scope · 全部可用';
    return '$scope · 已选 $selectedCount/$totalCount';
  }
}

bool _isExplicitNone<T>(Set<T> selected, T? noneValue) {
  return noneValue != null && selected.contains(noneValue);
}

DialogAnimationSettings _dialogMotionSettingsOf(BuildContext context) {
  try {
    return context.read<SettingsController>().dialogAnimationSettings;
  } catch (_) {
    return const DialogAnimationSettings();
  }
}

class _GatewayRoundIconActionButton extends StatelessWidget {
  const _GatewayRoundIconActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          fixedSize: const Size(38, 38),
          minimumSize: const Size(38, 38),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _MenuActionButton extends StatelessWidget {
  const _MenuActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.filled = false,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final Widget label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = filled
        ? FilledButton.styleFrom(
            minimumSize: const Size(104, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          )
        : TextButton.styleFrom(
            minimumSize: const Size(104, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          );
    if (filled) {
      return FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: icon,
        label: label,
        style: style,
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: label,
      style: style,
    );
  }
}

class _EnumMultiSelectDropdown<T> extends StatelessWidget {
  const _EnumMultiSelectDropdown({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final Set<T> selected;
  final String Function(T value) labelFor;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) => _MultiSelectDropdown<T>(
    label: label,
    options: values
        .map((value) => _SelectOption<T>(value: value, label: labelFor(value)))
        .toList(growable: false),
    selected: selected,
    onChanged: onChanged,
  );
}

class _ModelMultiSelectField extends StatelessWidget {
  const _ModelMultiSelectField({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.emptyMeansAll = false,
  });

  final String label;
  final List<WebGatewayModelOption> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool emptyMeansAll;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final result = await showAnimatedDialog<Set<String>>(
            context: context,
            builder: (_) => _ModelMultiSelectDialog(
              options: options,
              selected: selected,
              emptyMeansAll: emptyMeansAll,
            ),
          );
          if (result != null) onChanged(result);
        },
        child: InputDecorator(
          decoration: _gatewayInputDecoration(
            context,
            emptyMeansAll ? '$label（空=全部）' : label,
          ).copyWith(suffixIcon: const Icon(Icons.manage_search_rounded)),
          child: Text(
            _modelSummary(options, selected, emptyMeansAll),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class _ModelMultiSelectDialog extends StatefulWidget {
  const _ModelMultiSelectDialog({
    required this.options,
    required this.selected,
    required this.emptyMeansAll,
  });

  final List<WebGatewayModelOption> options;
  final Set<String> selected;
  final bool emptyMeansAll;

  @override
  State<_ModelMultiSelectDialog> createState() =>
      _ModelMultiSelectDialogState();
}

class _ModelMultiSelectDialogState extends State<_ModelMultiSelectDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selected);
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.options
        : widget.options
              .where((option) => option.label.toLowerCase().contains(query))
              .toList(growable: false);
    // 按 providerId 顺序保留首次出现的 providerLabel，避免标签碰撞造成串组。
    final providerOrder = <String>[];
    final providerLabels = <String, String>{};
    final grouped = <String, List<WebGatewayModelOption>>{};
    for (final option in filtered) {
      final pid = option.providerId;
      if (!grouped.containsKey(pid)) {
        providerOrder.add(pid);
        providerLabels[pid] = option.providerLabel;
      }
      (grouped[pid] ??= <WebGatewayModelOption>[]).add(option);
    }
    final rows = <Object>[];
    for (final pid in providerOrder) {
      rows
        ..add(
          _ProviderGroupHeader(
            providerId: pid,
            providerLabel: providerLabels[pid] ?? pid,
            options: grouped[pid]!,
          ),
        )
        ..addAll(grouped[pid]!);
    }
    final visibleKeys = filtered.map((option) => option.key).toSet();
    final totalKeys = _allModelKeys();
    final effectiveSelected = _effectiveSelectedModelKeys();
    final scopeText = query.isEmpty ? '全部模型' : '当前筛选 ${filtered.length} 个模型';
    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: colorScheme.surfaceContainerHigh,
      surfaceTintColor: colorScheme.surfaceTint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 680),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      Icons.hub_outlined,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('选择可用模型', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 3),
                        Text(
                          '$scopeText · ${_modelSelectionCountText(effectiveSelected.length, totalKeys.length)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _GatewayRoundIconActionButton(
                    tooltip: query.isEmpty ? '全选' : '当前筛选全选',
                    icon: Icons.done_all_rounded,
                    onPressed: visibleKeys.isEmpty
                        ? null
                        : () => _selectModelKeys(visibleKeys),
                  ),
                  const SizedBox(width: 8),
                  _GatewayRoundIconActionButton(
                    tooltip: query.isEmpty ? '全不选' : '当前筛选全不选',
                    icon: Icons.remove_done_rounded,
                    onPressed: visibleKeys.isEmpty
                        ? null
                        : () => _deselectModelKeys(visibleKeys),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.58,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: '搜索模型',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                    ),
                  ),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.clear_rounded),
                        ),
                ),
              ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的模型',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row is _ProviderGroupHeader) {
                          final groupKeys = row.options
                              .map((option) => option.key)
                              .toSet();
                          final selectedInGroup = groupKeys
                              .where(effectiveSelected.contains)
                              .length;
                          final allSelected =
                              selectedInGroup == groupKeys.length;
                          final noneSelected = selectedInGroup == 0;
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(4, 12, 0, 5),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    row.providerLabel,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                Text(
                                  '$selectedInGroup/${groupKeys.length}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _GatewayRoundIconActionButton(
                                  tooltip: '本服务商全选',
                                  icon: Icons.done_all_rounded,
                                  onPressed: allSelected
                                      ? null
                                      : () => _selectGroup(groupKeys),
                                ),
                                const SizedBox(width: 8),
                                _GatewayRoundIconActionButton(
                                  tooltip: '本服务商全不选',
                                  icon: Icons.remove_done_rounded,
                                  onPressed: noneSelected
                                      ? null
                                      : () => _deselectGroup(groupKeys),
                                ),
                              ],
                            ),
                          );
                        }
                        final option = row as WebGatewayModelOption;
                        final selected = effectiveSelected.contains(option.key);
                        return CheckboxListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          tileColor: selected
                              ? colorScheme.primaryContainer.withValues(
                                  alpha: 0.30,
                                )
                              : null,
                          value: selected,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            option.modelId,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          onChanged: (_) => _toggle(option.key),
                        );
                      },
                    ),
            ),
            Divider(height: 1, color: colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _modelSummary(
                        widget.options,
                        _selected,
                        widget.emptyMeansAll,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OpenHandDialogActionButton.primary(
                    label: '完成',
                    onPressed: () => Navigator.of(context).pop(_selected),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(String key) {
    final next = _effectiveSelectedModelKeys();
    if (next.contains(key)) {
      next.remove(key);
    } else {
      next.add(key);
    }
    _setEffectiveSelectedModels(next);
  }

  void _selectGroup(Set<String> keys) {
    _selectModelKeys(keys);
  }

  void _deselectGroup(Set<String> keys) {
    _deselectModelKeys(keys);
  }

  Set<String> _allModelKeys() =>
      widget.options.map((option) => option.key).toSet();

  Set<String> _effectiveSelectedModelKeys() {
    if (_selected.contains(webGatewayDenyAllSelectionMarker)) {
      return <String>{};
    }
    final allKeys = _allModelKeys();
    if (widget.emptyMeansAll && _selected.isEmpty) return allKeys;
    return _selected.intersection(allKeys);
  }

  void _selectModelKeys(Set<String> keys) {
    final next = _effectiveSelectedModelKeys()..addAll(keys);
    _setEffectiveSelectedModels(next);
  }

  void _deselectModelKeys(Set<String> keys) {
    final next = _effectiveSelectedModelKeys()..removeAll(keys);
    _setEffectiveSelectedModels(next);
  }

  void _setEffectiveSelectedModels(Set<String> keys) {
    final allKeys = _allModelKeys();
    if (keys.isEmpty) {
      setState(() {
        _selected = const <String>{webGatewayDenyAllSelectionMarker};
      });
      return;
    }
    if (widget.emptyMeansAll && keys.length == allKeys.length) {
      setState(() => _selected = <String>{});
      return;
    }
    setState(() => _selected = keys.intersection(allKeys));
  }

  String _modelSelectionCountText(int selectedCount, int totalCount) {
    if (_selected.contains(webGatewayDenyAllSelectionMarker)) return '全部不可用';
    if (widget.emptyMeansAll && _selected.isEmpty) return '全部可用';
    return '已选 $selectedCount/$totalCount';
  }
}

class _ProviderGroupHeader {
  const _ProviderGroupHeader({
    required this.providerId,
    required this.providerLabel,
    required this.options,
  });

  final String providerId;
  final String providerLabel;
  final List<WebGatewayModelOption> options;
}

class _AnimatedLogLine extends StatelessWidget {
  const _AnimatedLogLine({
    required this.entry,
    required this.animation,
    this.removing = false,
  });

  final WebGatewayLogEntry entry;
  final Animation<double> animation;
  final bool removing;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return _LogLine(entry: entry);
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: removing ? Curves.easeInCubic : Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .18),
            end: Offset.zero,
          ).animate(curved),
          child: _LogLine(entry: entry),
        ),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});
  final WebGatewayLogEntry entry;
  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      WebGatewayLogLevel.success => const Color(0xFF86EFAC),
      WebGatewayLogLevel.warn => const Color(0xFFFCD34D),
      WebGatewayLogLevel.error => const Color(0xFFFCA5A5),
      WebGatewayLogLevel.debug => const Color(0xFF9CA3AF),
      WebGatewayLogLevel.telemetry => const Color(0xFF7DD3FC),
      WebGatewayLogLevel.info => const Color(0xFFE5E7EB),
    };
    final ts = entry.timestamp.toLocal().toIso8601String().substring(11, 23);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$ts ',
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
            TextSpan(
              text: entry.tag.padRight(9),
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: ' ${entry.message}',
              style: TextStyle(color: color),
            ),
          ],
        ),
        style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, height: 1.45),
      ),
    );
  }
}

class _CleanupHistoryLine extends StatelessWidget {
  const _CleanupHistoryLine({required this.entry});

  final WebGatewayCleanupResult entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .52),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(Icons.cleaning_services_outlined, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_cleanupTargetLabel(entry.target)} · ${entry.expiredOnly ? '保留策略' : '手动清理'} · ${_formatDateTime(entry.timestamp)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${entry.deletedFiles} 文件 / ${_bytes(entry.bytesFreed)}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendLineChart extends StatefulWidget {
  const _TrendLineChart({
    required this.title,
    required this.values,
    required this.valueFormatter,
  });

  final String title;
  final List<double> values;
  final String Function(double value) valueFormatter;

  @override
  State<_TrendLineChart> createState() => _TrendLineChartState();
}

class _TrendLineChartState extends State<_TrendLineChart> {
  List<double> _fromValues = const <double>[];
  List<double> _toValues = const <double>[];
  List<double> _lastPaintValues = const <double>[];
  int _animationVersion = 0;

  @override
  void initState() {
    super.initState();
    _toValues = List<double>.from(widget.values);
    _lastPaintValues = _toValues;
  }

  @override
  void didUpdateWidget(covariant _TrendLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_seriesFingerprint(oldWidget.values) ==
        _seriesFingerprint(widget.values)) {
      return;
    }
    _fromValues = _lastPaintValues;
    _toValues = List<double>.from(widget.values);
    _animationVersion++;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final headerValues = _toValues;
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Text(
                  headerValues.isEmpty
                      ? '暂无数据'
                      : widget.valueFormatter(headerValues.last),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 112,
              child: TweenAnimationBuilder<double>(
                key: ValueKey<int>(_animationVersion),
                tween: Tween<double>(begin: 0, end: 1),
                duration: _motionDuration(context, 420),
                curve: Curves.easeOutBack,
                builder: (context, progress, child) {
                  final values = _lerpSeries(_fromValues, _toValues, progress);
                  _lastPaintValues = values;
                  final minValue = values.isEmpty
                      ? 0.0
                      : values.reduce(math.min);
                  final maxValue = values.isEmpty
                      ? 1.0
                      : math.max(minValue + 1, values.reduce(math.max));
                  return CustomPaint(
                    painter: _TrendLinePainter(
                      values: values,
                      minValue: minValue,
                      maxValue: maxValue,
                      progress: 1,
                      lineColor: colorScheme.primary,
                      gridColor: colorScheme.outlineVariant.withValues(
                        alpha: .72,
                      ),
                      labelColor: colorScheme.onSurfaceVariant,
                      valueFormatter: widget.valueFormatter,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int _seriesFingerprint(List<double> values) {
  var hash = values.length;
  for (final value in values) {
    hash = 0x3fffffff & (hash * 31 + (value * 1000).round());
  }
  return hash;
}

List<double> _lerpSeries(List<double> from, List<double> to, double progress) {
  if (to.isEmpty) return const <double>[];
  final t = progress.clamp(0.0, 1.0).toDouble();
  final fallback = from.isEmpty ? to.first : from.last;
  return List<double>.generate(to.length, (index) {
    final start = index < from.length ? from[index] : fallback;
    return start + (to[index] - start) * t;
  }, growable: false);
}

class _TrendLinePainter extends CustomPainter {
  const _TrendLinePainter({
    required this.values,
    required this.minValue,
    required this.maxValue,
    required this.progress,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
    required this.valueFormatter,
  });

  final List<double> values;
  final double minValue;
  final double maxValue;
  final double progress;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;
  final String Function(double value) valueFormatter;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 50.0;
    const right = 8.0;
    const top = 8.0;
    const bottom = 24.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      math.max(1, size.width - left - right),
      math.max(1, size.height - top - bottom),
    );
    final axisPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), axisPaint);
    }
    canvas.drawLine(
      Offset(chart.left, chart.top),
      Offset(chart.left, chart.bottom),
      axisPaint,
    );
    canvas.drawLine(
      Offset(chart.left, chart.bottom),
      Offset(chart.right, chart.bottom),
      axisPaint,
    );
    _paintLabel(canvas, valueFormatter(maxValue), Offset(0, chart.top - 2));
    _paintLabel(canvas, valueFormatter(minValue), Offset(0, chart.bottom - 14));
    _paintLabel(
      canvas,
      '0',
      Offset(chart.left - 3, chart.bottom + 5),
      alignRight: false,
    );
    _paintLabel(
      canvas,
      '${math.max(0, values.length - 1)}',
      Offset(chart.right - 16, chart.bottom + 5),
      alignRight: false,
    );
    if (values.length < 2) return;
    final span = math.max(1.0, maxValue - minValue);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = chart.left + chart.width * i / (values.length - 1);
      final normalized = ((values[i] - minValue) / span).clamp(0.0, 1.0);
      final y = chart.bottom - chart.height * normalized;
      points.add(Offset(x, y));
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final point = points[i];
      final mid = Offset(
        (previous.dx + point.dx) / 2,
        (previous.dy + point.dy) / 2,
      );
      path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, chart.bottom)
      ..lineTo(points.first.dx, chart.bottom)
      ..close();
    final visibleRight = chart.left + chart.width * progress.clamp(0.0, 1.0);
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(chart.left, chart.top, visibleRight, chart.bottom),
    );
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: .20),
            lineColor.withValues(alpha: .02),
          ],
        ).createShader(chart),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset offset, {
    bool alignRight = true,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: labelColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 48);
    final dx = alignRight ? 46 - painter.width : offset.dx;
    painter.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.progress != progress ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor;
  }
}

String _modeLabel(WebGatewayConversationMode mode) {
  return switch (mode) {
    WebGatewayConversationMode.normal => '普通',
    WebGatewayConversationMode.image => '生成图片',
    WebGatewayConversationMode.video => '生成视频',
    WebGatewayConversationMode.audio => '生成音频',
    WebGatewayConversationMode.deepResearch => '深度研究',
  };
}

String _modelSummary(
  List<WebGatewayModelOption> options,
  Set<String> selected,
  bool emptyMeansAll,
) {
  if (selected.contains(webGatewayDenyAllSelectionMarker)) {
    return '全部模型不可用';
  }
  if (emptyMeansAll && selected.isEmpty) return '全部模型可用';
  if (selected.isEmpty) return '未选择模型';
  final labels = options
      .where((option) => selected.contains(option.key))
      .map((option) => option.label)
      .toList(growable: false);
  if (labels.length <= 2) return labels.join('、');
  return '${labels.take(2).join('、')} 等 ${labels.length} 个模型';
}

String _runtimeStateLabel(BuildContext context, WebGatewayRuntimeState state) {
  final isZh = Localizations.localeOf(context).languageCode == 'zh';
  if (!isZh) {
    return switch (state) {
      WebGatewayRuntimeState.stopped => 'Stopped',
      WebGatewayRuntimeState.starting => 'Starting',
      WebGatewayRuntimeState.running => 'Running',
      WebGatewayRuntimeState.stopping => 'Stopping',
      WebGatewayRuntimeState.crashed => 'Crashed',
    };
  }
  return switch (state) {
    WebGatewayRuntimeState.stopped => '已停止',
    WebGatewayRuntimeState.starting => '启动中',
    WebGatewayRuntimeState.running => '运行中',
    WebGatewayRuntimeState.stopping => '停止中',
    WebGatewayRuntimeState.crashed => '已崩溃',
  };
}

Duration _motionDuration(BuildContext context, int milliseconds) {
  return MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
}

List<double> _series(
  List<WebGatewayRuntimeSnapshot> snapshots,
  double? Function(WebGatewayRuntimeSnapshot snapshot) pick,
) {
  return snapshots
      .map(pick)
      .whereType<double>()
      .map((value) => value.isFinite ? value : 0.0)
      .toList(growable: false);
}

List<double> _deltaSeries(
  List<WebGatewayRuntimeSnapshot> snapshots,
  double Function(WebGatewayRuntimeSnapshot snapshot) pick,
) {
  if (snapshots.length < 2) return const <double>[];
  final values = <double>[];
  for (var index = 1; index < snapshots.length; index++) {
    values.add(
      math.max(0, pick(snapshots[index]) - pick(snapshots[index - 1])),
    );
  }
  return values;
}

int _logPageSize(double dialogHeight) {
  final available = math.max(160.0, dialogHeight - 190);
  return math.max(24, (available / 22).floor());
}

String _formatQueryParameters(Map<String, String> value) {
  return value.entries.map((entry) => '${entry.key}=${entry.value}').join('&');
}

Map<String, String> _parseQueryParameters(String raw) {
  final result = <String, String>{};
  final normalized = raw.replaceAll('\n', '&');
  for (final part in normalized.split('&')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final index = trimmed.indexOf('=');
    if (index <= 0) {
      result[trimmed] = '';
      continue;
    }
    final key = trimmed.substring(0, index).trim();
    final value = trimmed.substring(index + 1).trim();
    if (key.isNotEmpty) result[key] = value;
  }
  return result;
}

List<String> _parseExtensions(String raw) {
  final result = <String>[];
  final seen = <String>{};
  final normalized = raw.replaceAll('\n', ',').replaceAll(';', ',');
  for (final part in normalized.split(',')) {
    final trimmed = part.trim().toLowerCase();
    if (trimmed.isEmpty) continue;
    final withoutDot = trimmed.startsWith('.') ? trimmed.substring(1) : trimmed;
    final safe = withoutDot.replaceAll(RegExp(r'[^a-z0-9_+-]'), '');
    if (safe.isEmpty) continue;
    final extension = '.$safe';
    if (seen.add(extension)) result.add(extension);
  }
  return result;
}

int _int(String value, int fallback) {
  final parsed = int.tryParse(value.trim());
  return parsed == null || parsed <= 0 ? fallback : parsed;
}

String _formatDuration(int ms) {
  final d = Duration(milliseconds: ms);
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  return '${d.inSeconds}s';
}

String _formatDateTime(DateTime value) {
  return value
      .toLocal()
      .toIso8601String()
      .replaceFirst('T', ' ')
      .substring(0, 19);
}

String _dateTime(DateTime value) => _formatDateTime(value);

String _rate(double value) {
  if (value >= 100) return value.toStringAsFixed(0);
  if (value >= 10) return value.toStringAsFixed(1);
  return value.toStringAsFixed(2);
}

String _percent(double value) =>
    '${(value * 100).clamp(0, 999).toStringAsFixed(0)}%';

String _cleanupTargetLabel(String target) {
  return switch (target) {
    'logs' => '日志',
    'uploads' => '上传缓存',
    'all' => '全部资源',
    _ => target,
  };
}

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}
