import 'dart:async';
import 'dart:math' as math;

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
                      style: theme.textTheme.bodyMedium?.copyWith(
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
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
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
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.language_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  webMessagePlatformBuiltinName,
                                  style: theme.textTheme.titleLarge,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              _StatusDot(color: stateColor),
                            ],
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
                    Tooltip(
                      message: config.loggingEnabled
                          ? '查看 Web 服务日志'
                          : '开启日志后可查看日志',
                      child: IconButton.filledTonal(
                        onPressed: config.loggingEnabled
                            ? () => _showLogs(context, controller)
                            : null,
                        icon: const Icon(Icons.terminal_rounded),
                      ),
                    ),
                    Tooltip(
                      message: '健康检测',
                      child: IconButton.filledTonal(
                        onPressed: () => _runHealth(context, controller),
                        icon: const Icon(Icons.monitor_heart_outlined),
                      ),
                    ),
                    Tooltip(
                      message: config.opsEnabled ? '运维面板' : '开启运维后可查看',
                      child: IconButton.filledTonal(
                        onPressed: config.opsEnabled
                            ? () => _showOps(context, controller)
                            : null,
                        icon: const Icon(Icons.speed_rounded),
                      ),
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
                  label: config.workspaceFilesEnabled
                      ? (config.workspaceFileWriteEnabled ? '文件读写' : '文件只读')
                      : '文件关闭',
                ),
              ],
            ),
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
                    _MetricTile(label: '状态', value: runtime.state.name),
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
  late bool _planModeEnabled;
  late bool _sessionManagementEnabled;
  late bool _workspaceFilesEnabled;
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
    _planModeEnabled = config.planModeEnabled;
    _sessionManagementEnabled = config.sessionManagementEnabled;
    _workspaceFilesEnabled = config.workspaceFilesEnabled;
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
                              label: '是否开放项目文件',
                              value: _workspaceFilesEnabled,
                              onChanged: (v) =>
                                  setState(() => _workspaceFilesEnabled = v),
                            ),
                            _SwitchTile(
                              label: '是否允许写入文件',
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
                        _ChipPicker(
                          label: '可新建的线程模板类型',
                          emptyMeansAll: true,
                          options: {
                            for (final t in widget.controller.templates)
                              t.id: t.name,
                          },
                          selected: _templates,
                          onChanged: (next) =>
                              setState(() => _templates = next),
                        ),
                        _ChipPicker(
                          label: '可用的技能',
                          emptyMeansAll: true,
                          options: {
                            for (final name in widget.controller.skillNames)
                              name: name,
                          },
                          selected: _skills,
                          onChanged: (next) => setState(() => _skills = next),
                        ),
                        _ChipPicker(
                          label: '可用的 MCP',
                          emptyMeansAll: true,
                          options: {
                            for (final name in widget.controller.mcpServerNames)
                              name: name,
                          },
                          selected: _mcpServers,
                          onChanged: (next) =>
                              setState(() => _mcpServers = next),
                        ),
                        _ChipPicker(
                          label: '可用的记忆',
                          emptyMeansAll: true,
                          options: {
                            for (final id in widget.controller.memoryIds)
                              id: id,
                          },
                          selected: _memories,
                          onChanged: (next) => setState(() => _memories = next),
                        ),
                        _ChipPicker(
                          label: '可用的内建工具',
                          emptyMeansAll: true,
                          options: {
                            for (final name
                                in widget.controller.builtinToolNames)
                              name: name,
                          },
                          selected: _tools,
                          onChanged: (next) => setState(() => _tools = next),
                        ),
                        _EnumChipPicker<WebGatewayMessageType>(
                          label: '可发送的消息类型',
                          values: WebGatewayMessageType.values,
                          selected: _messageTypes,
                          labelFor: (v) =>
                              v == WebGatewayMessageType.text ? '纯文本' : '带附件',
                          onChanged: (next) =>
                              setState(() => _messageTypes = next),
                        ),
                        _EnumChipPicker<WebGatewayConversationMode>(
                          label: '可使用的对话模式',
                          values: WebGatewayConversationMode.values,
                          selected: _modes,
                          labelFor: _modeLabel,
                          onChanged: (next) => setState(() => _modes = next),
                        ),
                        _ChipPicker(
                          label: '可使用的模型',
                          emptyMeansAll: true,
                          options: {
                            for (final option in widget.controller.modelOptions)
                              option.key: option.label,
                          },
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
      workspaceFilesEnabled: _workspaceFilesEnabled,
      workspaceFileWriteEnabled:
          _workspaceFilesEnabled && _workspaceFileWriteEnabled,
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
  final Set<WebGatewayLogLevel> _hidden = <WebGatewayLogLevel>{};
  bool _follow = true;
  int _limit = 300;

  @override
  void initState() {
    super.initState();
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
    if (_follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = widget.controller.logs;
    final visible = logs
        .skip(math.max(0, logs.length - _limit))
        .where((entry) => !_hidden.contains(entry.level))
        .toList(growable: false);
    final mediaSize = MediaQuery.sizeOf(context);
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
                  IconButton(
                    tooltip: '加载更多',
                    onPressed: () => setState(() => _limit += 300),
                    icon: const Icon(Icons.unfold_more_rounded),
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
                    icon: const Icon(Icons.save_alt_rounded),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Container(
              width: double.infinity,
              color: const Color(0xFF101218),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: WebGatewayLogLevel.values
                    .map((level) {
                      final selected = !_hidden.contains(level);
                      return FilterChip(
                        selected: selected,
                        label: Text(level.name),
                        onSelected: (_) => setState(() {
                          if (selected) {
                            _hidden.add(level);
                          } else {
                            _hidden.remove(level);
                          }
                        }),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
            Expanded(
              child: Container(
                color: const Color(0xFF101218),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    itemCount: visible.length,
                    itemBuilder: (context, index) =>
                        _LogLine(entry: visible[index]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    if (!mounted) return;
    final snapshot = await widget.controller.refreshRuntimeSnapshot();
    if (!mounted) return;
    setState(() {
      _trend.add(snapshot);
      if (_trend.length > 60) _trend.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _trend.isEmpty
        ? widget.controller.runtimeSnapshot()
        : _trend.last;
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
                          onPressed: widget.controller.startService,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('开启'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: widget.controller.stopService,
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
                              value: snapshot.state.name,
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
                    _TrendStrip(
                      values: _trend
                          .map((snapshot) => snapshot.totalRequests)
                          .toList(growable: false),
                    ),
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
    final confirmed = await showDialog<bool>(
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
          shape: RoundedRectangleBorder(
            side: BorderSide(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
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
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
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

class _ChipPicker extends StatelessWidget {
  const _ChipPicker({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.emptyMeansAll = false,
  });
  final String label;
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool emptyMeansAll;
  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            emptyMeansAll && selected.isEmpty ? '$label（空=全部）' : label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.entries
                .map((entry) {
                  final isSelected = selected.contains(entry.key);
                  return FilterChip(
                    label: Text(entry.value),
                    selected: isSelected,
                    onSelected: (_) {
                      final next = Set<String>.from(selected);
                      if (isSelected) {
                        next.remove(entry.key);
                      } else {
                        next.add(entry.key);
                      }
                      onChanged(next);
                    },
                  );
                })
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _EnumChipPicker<T> extends StatelessWidget {
  const _EnumChipPicker({
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map((value) {
                final isSelected = selected.contains(value);
                return FilterChip(
                  label: Text(labelFor(value)),
                  selected: isSelected,
                  onSelected: (_) {
                    final next = Set<T>.from(selected);
                    if (isSelected) {
                      next.remove(value);
                    } else {
                      next.add(value);
                    }
                    if (next.isNotEmpty) onChanged(next);
                  },
                );
              })
              .toList(growable: false),
        ),
      ],
    ),
  );
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

class _TrendStrip extends StatelessWidget {
  const _TrendStrip({required this.values});
  final List<int> values;
  @override
  Widget build(BuildContext context) {
    final maxValue = values.isEmpty ? 1 : math.max(1, values.reduce(math.max));
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values
            .map((value) {
              final h = 8 + 58 * (value / maxValue);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    height: h,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
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

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}
