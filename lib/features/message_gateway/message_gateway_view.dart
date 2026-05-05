import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/widgets/animated_dialog.dart';
import '../../shared/widgets/highlight_pulse.dart';
import '../../shared/widgets/openhand_dialog_action_button.dart';
import 'message_gateway_controller.dart';
import 'model/web_message_platform_config.dart';
import 'service/web_message_platform_service.dart';

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
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 920;
                final header = Column(
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
                );
                final actions = Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: controller.isLoading
                          ? null
                          : () => _copyEndpoint(context, controller),
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('复制地址'),
                    ),
                    FilledButton.icon(
                      onPressed: controller.isLoading
                          ? null
                          : () => _showEditor(context, controller),
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('编辑服务'),
                    ),
                  ],
                );
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [header, const SizedBox(height: 18), actions],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: 18),
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

  Future<void> _copyEndpoint(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    final text = controller.webUrl.isEmpty
        ? 'http://${controller.config.listenHost}:${controller.config.listenPort}'
        : controller.webUrl;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 $text')));
  }

  Future<void> _showEditor(
    BuildContext context,
    MessageGatewayController controller,
  ) async {
    await showAnimatedDialog<void>(
      context: context,
      builder: (dialogContext) => _WebPlatformEditorDialog(
        controller: controller,
        initialConfig: controller.config,
      ),
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
                    FilledButton.icon(
                      onPressed: controller.isSaving
                          ? null
                          : () => isRunning
                                ? controller.stopService()
                                : controller.startService(),
                      icon: Icon(
                        isRunning
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline_rounded,
                      ),
                      label: Text(isRunning ? '停止' : '启动'),
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
                        child: actions,
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
                  icon: Icons.link_rounded,
                  label: isRunning
                      ? controller.webUrl
                      : '${config.listenHost}:${config.listenPort}',
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
    ScaffoldMessenger.of(context).showSnackBar(
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
  late Set<String> _models;
  late Set<WebGatewayMessageType> _messageTypes;
  late Set<WebGatewayConversationMode> _modes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    _enabled = config.enabled;
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
    final mediaSize = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(mediaSize.width - 36, 920),
          maxHeight: mediaSize.height - 36,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.language_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      webMessagePlatformBuiltinName,
                      style: Theme.of(context).textTheme.titleLarge,
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
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
                              onChanged: (v) => setState(() => _opsEnabled = v),
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
                              onChanged: (v) =>
                                  setState(() => _sessionManagementEnabled = v),
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
                          options: [
                            for (final name in widget.controller.mcpServerNames)
                              _SelectOption(value: name, label: name),
                          ],
                          selected: _mcpServers,
                          onChanged: (next) =>
                              setState(() => _mcpServers = next),
                        ),
                        _MultiSelectDropdown<String>(
                          label: '可用的记忆',
                          emptyMeansAll: true,
                          options: [
                            for (final id in widget.controller.memoryIds)
                              _SelectOption(value: id, label: id),
                          ],
                          selected: _memories,
                          onChanged: (next) => setState(() => _memories = next),
                        ),
                        _MultiSelectDropdown<String>(
                          label: '可用的内建工具',
                          emptyMeansAll: true,
                          options: [
                            for (final name
                                in widget.controller.builtinToolNames)
                              _SelectOption(value: name, label: name),
                          ],
                          selected: _tools,
                          onChanged: (next) => setState(() => _tools = next),
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
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Row(
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
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final config = WebMessagePlatformConfig(
      enabled: _enabled,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $error')));
      setState(() => _saving = false);
    }
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
    _lastPageSize = _logPageSize(mediaSize.height);
    final visible = _visibleLogs(logs);
    final historicalCount = logs
        .where(
          (entry) => entry.id <= _anchorLogId && !_hidden.contains(entry.level),
        )
        .length;
    _scheduleRenderedSync(visible);
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(mediaSize.width - 36, 960),
          maxHeight: mediaSize.height - 36,
          minHeight: math.min(mediaSize.height - 36, 560),
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
                            ? () =>
                                  setState(() => _historyLimit += _lastPageSize)
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
                        onPressed: _exportCurrentLog,
                        icon: const Icon(Icons.save_alt_rounded),
                      ),
                      // 清空终端：仅清除当前弹窗内的渲染项，
                      // 底层服务的日志环形缓冲与磁盘文件保持不变（类似 shell `clear`）。
                      IconButton(
                        tooltip: '清空终端（仅清除显示，不删除日志文件）',
                        onPressed: _clearTerminal,
                        icon: const Icon(Icons.cleaning_services_outlined),
                      ),
                      // 日志级别多选菜单：取代原来顶部的 FilterChip 条。
                      // 菜单本身走 PopupMenuButton 默认进 / 退场动画，
                      // 与全局 reduceMotion 设置默认联动（Flutter 框架级在
                      // disableAnimations=true 时会自动跳过过渡）。
                      PopupMenuButton<WebGatewayLogLevel>(
                        tooltip: '日志级别筛选',
                        icon: const Icon(Icons.filter_list_rounded),
                        // 返回 null 代表点击了外部区域 / Esc，不需要响应。
                        onSelected: (level) =>
                            setState(() => _toggleLogLevel(level)),
                        // 多选能力：在 itemBuilder 里手搽复选框，
                        // 点击任一项都在 onSelected 里进行反选。
                        itemBuilder: (menuContext) => WebGatewayLogLevel.values
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
                child: Scrollbar(
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
          ],
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
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: _motionDuration(context, 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _copyLogs(List<WebGatewayLogEntry> logs) async {
    await Clipboard.setData(
      ClipboardData(text: logs.map((entry) => entry.toLogLine()).join('\n')),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志已保存到剪贴板')));
  }

  Future<void> _exportCurrentLog() async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('当前日志已导出到 ${location.path}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('当前日志导出失败: $error')));
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
  Timer? _timer;
  final List<WebGatewayRuntimeSnapshot> _trend = <WebGatewayRuntimeSnapshot>[];
  bool _isCleaning = false;
  bool _isRefreshingSnapshot = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
        if (_trend.length > 60) _trend.removeAt(0);
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
    final mediaSize = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(mediaSize.width - 36, 900),
          maxHeight: mediaSize.height - 36,
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: isRunning || isTransitioning
                              ? null
                              : widget.controller.startService,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('开启'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: !isRunning || isTransitioning
                              ? null
                              : widget.controller.stopService,
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text('关机'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: widget.controller.restartService,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: const Text('重启'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: widget.controller.reloadConfig,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('配置重载'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: widget.controller.hotFix,
                          icon: const Icon(Icons.healing_rounded),
                          label: const Text('热修复'),
                        ),
                        FilledButton.icon(
                          onPressed: widget.controller.runHealthCheck,
                          icon: const Icon(Icons.monitor_heart_outlined),
                          label: const Text('健康诊断'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _isCleaning
                              ? null
                              : () => _runCleanup(
                                  label: '过期资源',
                                  action:
                                      widget.controller.cleanupExpiredArtifacts,
                                ),
                          icon: const Icon(Icons.cleaning_services_outlined),
                          label: const Text('清理过期'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _isCleaning
                              ? null
                              : () => _confirmAndCleanup(
                                  title: '清空日志',
                                  message: '会清空内存日志和 Web 服务磁盘日志，保留策略不会保留当前内容。',
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
                                  message: '会删除 Web 消息附件落盘缓存，不影响已经写入会话的消息记录。',
                                  label: '上传缓存',
                                  action: widget.controller.cleanupUploadCache,
                                ),
                          icon: const Icon(Icons.folder_delete_outlined),
                          label: const Text('清空缓存'),
                        ),
                      ],
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
                              value: snapshot.threadCount?.toString() ?? '不可用',
                            ),
                            _MetricTile(
                              label: '文件句柄',
                              value:
                                  snapshot.fileHandleCount?.toString() ?? '不可用',
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
                              label: '错误数',
                              value: '${snapshot.totalErrors}',
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
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    const _SectionTitle('吞吐趋势'),
                    _TrendLineChart(
                      title: '请求/秒',
                      values: _deltaSeries(
                        _trend,
                        (snapshot) => snapshot.totalRequests.toDouble(),
                      ),
                      valueFormatter: (value) => value.toStringAsFixed(0),
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
                              valueFormatter: (value) => _bytes(value.round()),
                            ),
                            _TrendLineChart(
                              title: '日志磁盘',
                              values: _series(
                                _trend,
                                (snapshot) => snapshot.logBytes.toDouble(),
                              ),
                              valueFormatter: (value) => _bytes(value.round()),
                            ),
                            _TrendLineChart(
                              title: '线程数',
                              values: _series(
                                _trend,
                                (snapshot) => snapshot.threadCount?.toDouble(),
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
          ],
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认清理'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _runCleanup(label: label, action: action);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$label清理完成，释放 ${_bytes(result.bytesFreed)}，删除 ${result.deletedFiles} 个文件',
          ),
        ),
      );
      await _tick();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label清理失败: $error')));
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
/// 点击任意一项 → 拷贝该 URL 并 SnackBar 提示。视觉与 _InfoChip 同源
/// 但使用 ActionChip + primary tint，提示"可点"且与状态 chip 区分开。
class _AccessibleUrlsBar extends StatelessWidget {
  const _AccessibleUrlsBar({required this.urls});

  final List<String> urls;

  Future<void> _copy(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 $url')));
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
              '可访问 URL（点击复制）',
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
              ActionChip(
                avatar: Icon(
                  Icons.content_copy_rounded,
                  size: 14,
                  color: cs.primary,
                ),
                label: Text(
                  url,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                onPressed: () => _copy(context, url),
                backgroundColor: cs.primaryContainer.withValues(alpha: 0.42),
                side: BorderSide(
                  color: cs.primary.withValues(alpha: 0.32),
                  width: 0.6,
                ),
              ),
          ],
        ),
      ],
    );
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _SwitchGrid extends StatelessWidget {
  const _SwitchGrid({required this.twoColumns, required this.children});
  final bool twoColumns;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: twoColumns ? 2 : 1,
    childAspectRatio: twoColumns ? 5.2 : 6,
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
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
  Widget build(BuildContext context) => SwitchListTile(
    value: value,
    onChanged: onChanged,
    title: Text(label),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );
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
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
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
    childAspectRatio: twoColumns ? 5.2 : 6.2,
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
            decoration: InputDecoration(
              labelText: spec.label,
              border: const OutlineInputBorder(),
            ),
          ),
        )
        .toList(growable: false),
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
  });

  final String label;
  final List<_SelectOption<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool emptyMeansAll;

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
            options: widget.options,
            selected: widget.selected,
            emptyMeansAll: widget.emptyMeansAll,
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
              decoration: InputDecoration(
                labelText: widget.emptyMeansAll
                    ? '${widget.label}（空=全部）'
                    : widget.label,
                border: const OutlineInputBorder(),
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
    required this.options,
    required this.selected,
    required this.emptyMeansAll,
    required this.onApply,
    required this.onClose,
  });

  final List<_SelectOption<T>> options;
  final Set<T> selected;
  final bool emptyMeansAll;
  final ValueChanged<Set<T>> onApply;
  final VoidCallback onClose;

  @override
  State<_MultiSelectDropdownMenu<T>> createState() =>
      _MultiSelectDropdownMenuState<T>();
}

class _MultiSelectDropdownMenuState<T>
    extends State<_MultiSelectDropdownMenu<T>> {
  final TextEditingController _searchController = TextEditingController();
  late Set<T> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<T>.from(widget.selected);
    _searchController.addListener(() => setState(() {}));
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
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.options
        : widget.options
              .where((option) => option.label.toLowerCase().contains(query))
              .toList(growable: false);
    return SizedBox(
      width: 420,
      height: 360,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: '搜索',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _setSelected(
                    widget.emptyMeansAll
                        ? <T>{}
                        : widget.options.map((option) => option.value).toSet(),
                  ),
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: Text(widget.emptyMeansAll ? '全部' : '全选'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    if (widget.emptyMeansAll) {
                      _setSelected(<T>{});
                      return;
                    }
                    if (_selected.length > 1) {
                      _setSelected({_selected.first});
                    }
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 18),
                  label: Text(widget.emptyMeansAll ? '清空限制' : '保留一项'),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: _applyAndClose,
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('没有匹配项'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final option = filtered[index];
                      final isImplicitAll =
                          widget.emptyMeansAll && _selected.isEmpty;
                      return CheckboxListTile(
                        dense: true,
                        value:
                            isImplicitAll || _selected.contains(option.value),
                        onChanged: (_) => _toggle(option.value),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _toggle(T value) {
    final next = Set<T>.from(_selected);
    if (next.contains(value)) {
      next.remove(value);
    } else {
      next.add(value);
    }
    if (!widget.emptyMeansAll && next.isEmpty) return;
    _setSelected(next);
  }

  void _setSelected(Set<T> next) {
    setState(() => _selected = next);
  }

  void _applyAndClose() {
    widget.onApply(Set<T>.from(_selected));
    widget.onClose();
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
          decoration: InputDecoration(
            labelText: emptyMeansAll ? '$label（空=全部）' : label,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.manage_search_rounded),
          ),
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
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.options
        : widget.options
              .where((option) => option.label.toLowerCase().contains(query))
              .toList(growable: false);
    final grouped = <String, List<WebGatewayModelOption>>{};
    for (final option in filtered) {
      final providerLabel = option.label.split(' / ').first;
      (grouped[providerLabel] ??= <WebGatewayModelOption>[]).add(option);
    }
    final rows = <Object>[];
    for (final entry in grouped.entries) {
      rows
        ..add(entry.key)
        ..addAll(entry.value);
    }
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.hub_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('选择可用模型', style: theme.textTheme.titleMedium),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selected = <String>{}),
                    child: Text(widget.emptyMeansAll ? '全部' : '清空'),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: '搜索模型',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
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
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('没有匹配的模型'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row is String) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
                            child: Text(
                              row,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }
                        final option = row as WebGatewayModelOption;
                        return CheckboxListTile(
                          dense: true,
                          value: widget.emptyMeansAll && _selected.isEmpty
                              ? true
                              : _selected.contains(option.key),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            option.modelId,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            option.providerId,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: (_) => _toggle(option.key),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
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
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }
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

class _TrendLineChart extends StatelessWidget {
  const _TrendLineChart({
    required this.title,
    required this.values,
    required this.valueFormatter,
  });

  final String title;
  final List<double> values;
  final String Function(double value) valueFormatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final minValue = values.isEmpty ? 0.0 : values.reduce(math.min);
    final maxValue = values.isEmpty
        ? 1.0
        : math.max(minValue + 1, values.reduce(math.max));
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
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                Text(
                  values.isEmpty ? '暂无数据' : valueFormatter(values.last),
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
                tween: Tween<double>(begin: 0, end: 1),
                duration: _motionDuration(context, 420),
                curve: Curves.easeOutCubic,
                builder: (context, progress, child) => CustomPaint(
                  painter: _TrendLinePainter(
                    values: values,
                    minValue: minValue,
                    maxValue: maxValue,
                    progress: progress,
                    lineColor: colorScheme.primary,
                    gridColor: colorScheme.outlineVariant.withValues(
                      alpha: .72,
                    ),
                    labelColor: colorScheme.onSurfaceVariant,
                    valueFormatter: valueFormatter,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
