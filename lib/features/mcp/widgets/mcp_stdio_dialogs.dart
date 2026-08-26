import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/system_proxy.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/motion_durations.dart';
import '../../../shared/ui/motion_preference.dart';
import '../../../shared/ui/openhand_clipboard.dart';
import '../../../shared/ui/openhand_console_log_panel.dart';
import '../../../shared/ui/openhand_inline_notice.dart';
import '../../../shared/ui/openhand_reveal_switcher.dart';
import '../../../shared/ui/openhand_spacing.dart';
import '../../../shared/ui/openhand_typography.dart';
import '../../../shared/util/bounded_log_buffer.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/text_normalization.dart';
import '../../../shared/util/timer_safety.dart';
import '../mcp_errors.dart';
import '../model/mcp_server.dart';
import '../service/mcp_stdio_io_utils.dart';
import '../service/mcp_stdio_process_manager.dart';
import '../service/mcp_tool_discovery_service.dart';

/// 包管理器的列举 / 查版本命令，可能要读本地安装树或访问 registry。
const Duration _kPackageQueryTimeout = Duration(seconds: 10);

// STDIO 弹窗公共标题栏

/// STDIO 弹窗统一标题栏：图标 + 标题 + 等宽副标题 + 右侧操作区（含关闭）。
class _StdioDialogHeader extends StatelessWidget {
  const _StdioDialogHeader({
    required this.icon,
    required this.title,
    this.iconColor,
    this.subtitle,
    this.actions = const <Widget>[],
  });

  static const double actionSize = 36;

  final IconData icon;
  final String title;

  /// 缺省取 `colorScheme.primary`；用于表达运行中 / 已停止之类的状态。
  final Color? iconColor;

  /// 为空时不占位；始终单行省略，避免长命令撑破标题栏。
  final String? subtitle;

  /// 关闭按钮由本组件补齐，调用方只传业务动作。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleText = subtitle?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
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
          Icon(icon, size: 20, color: iconColor ?? theme.colorScheme.primary),
          kOpenHandHGap10,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitleText.isNotEmpty)
                  Text(
                    subtitleText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: kOpenHandMonospaceFontFamily,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Wrap(
            spacing: 4,
            children: [
              ...actions,
              _StdioDialogHeaderAction(
                icon: Icons.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 标题栏中的方形图标按钮；[tooltip] 为空时不包 Tooltip。
class _StdioDialogHeaderAction extends StatelessWidget {
  const _StdioDialogHeaderAction({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.selected,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: _StdioDialogHeader.actionSize,
      height: _StdioDialogHeader.actionSize,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        isSelected: selected,
      ),
    );
    final message = tooltip?.trim() ?? '';
    return message.isEmpty ? button : Tooltip(message: message, child: button);
  }
}

// STDIO MCP 服务日志查看弹窗

/// 显示 STDIO MCP 服务的实时日志弹窗。
Future<void> showStdioLogDialog(BuildContext context, McpServer server) {
  return showAnimatedDialog(
    context: context,
    builder: (ctx) => _StdioLogDialog(server: server),
  );
}

class _StdioLogDialog extends StatefulWidget {
  const _StdioLogDialog({required this.server});

  final McpServer server;

  @override
  State<_StdioLogDialog> createState() => _StdioLogDialogState();
}

class _StdioLogDialogState extends State<_StdioLogDialog> {
  final ScrollController _scrollController = ScrollController();
  final AutoFollowScrollGuard _scrollGuard = AutoFollowScrollGuard();
  bool _autoScroll = true;
  bool _updateScheduled = false;
  List<String> _lastLogs = const <String>[];

  @override
  void initState() {
    super.initState();
    _lastLogs = McpStdioProcessManager.instance
        .infoFor(widget.server.name)
        .logs;
    McpStdioProcessManager.instance.addListener(_onUpdate);
    // 弹窗打开时自动滚动到底部显示最新日志
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollGuard.followToBottom(_scrollController);
    });
  }

  @override
  void dispose() {
    McpStdioProcessManager.instance.removeListener(_onUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted || _updateScheduled) return;
    _updateScheduled = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (!mounted) return;
      final info = McpStdioProcessManager.instance.infoFor(widget.server.name);
      final logsChanged = !identical(info.logs, _lastLogs);
      _lastLogs = info.logs;
      if (_autoScroll && logsChanged && info.logs.isNotEmpty) {
        _scrollGuard.followToBottom(
          _scrollController,
          animated: true,
          animationDuration: openHandMotionDuration(
            context,
            kOpenHandMotion220,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final info = McpStdioProcessManager.instance.infoFor(widget.server.name);
    final logs = info.logs;

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthStandard,
      maxHeight: kOpenHandDialogHeightStandard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StdioDialogHeader(
            icon: Icons.terminal_rounded,
            iconColor: info.isRunning
                ? OpenHandStatusColors.success
                : theme.colorScheme.onSurfaceVariant,
            title: l10n.mcpStdioDialogLogsTitle(widget.server.name),
            subtitle: info.isRunning
                ? l10n.mcpStdioDialogRunningPid('${info.pid}')
                : l10n.mcpStdioDialogStopped,
            actions: [
              _StdioDialogHeaderAction(
                tooltip: l10n.mcpStdioDialogAutoScroll,
                icon: _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
                selected: _autoScroll,
                onPressed: () => setState(() => _autoScroll = !_autoScroll),
              ),
              _StdioDialogHeaderAction(
                tooltip: l10n.mcpStdioDialogCopyLogs,
                icon: Icons.copy_rounded,
                onPressed: logs.isEmpty
                    ? null
                    : () async {
                        await copyOpenHandTextToClipboard(
                          logTag: 'mcp',
                          context: context,
                          text: logs.join('\n'),
                          successMessage: l10n.mcpStdioDialogCopiedToClipboard,
                          logAction: '复制 STDIO 日志',
                        );
                      },
              ),
              _StdioDialogHeaderAction(
                tooltip: l10n.mcpStdioDialogClearLogs,
                icon: Icons.delete_sweep_rounded,
                onPressed: logs.isEmpty
                    ? null
                    : () => McpStdioProcessManager.instance.clearLogs(
                        widget.server.name,
                      ),
              ),
            ],
          ),
          // 状态指示条
          Container(
            height: 3,
            color: info.isRunning
                ? OpenHandStatusColors.success
                : info.isTransitioning
                ? OpenHandStatusColors.warning
                : theme.colorScheme.outlineVariant,
          ),
          // 终端输出区域
          Flexible(
            child: Container(
              color: _kStdioLogSurface,
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        l10n.mcpStdioDialogNoLogOutput,
                        style: const TextStyle(
                          fontFamily: kOpenHandMonospaceFontFamily,
                          fontSize: 12,
                          color: OpenHandConsolePalette.muted,
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
                          final style = _resolveLogLineStyle(line);
                          return Padding(
                            padding: EdgeInsets.only(
                              top: style.topPadding,
                              bottom: 0.5,
                            ),
                            child: Text(
                              line,
                              style: TextStyle(
                                fontFamily: kOpenHandMonospaceFontFamily,
                                fontSize: style.fontSize,
                                height: kOpenHandConsoleLogLineHeight,
                                color: style.color,
                                fontWeight: style.bold
                                    ? FontWeight.w600
                                    : FontWeight.normal,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  Icons.article_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                kOpenHandHGap6,
                Text(
                  l10n.mcpStdioDialogLineCount(logs.length),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (info.uptime != null)
                  Text(
                    l10n.mcpStdioDialogUptime(
                      formatCompactDuration(info.uptime!),
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _LogLineStyle _resolveLogLineStyle(String line) {
    // 空行
    if (line.trim().isEmpty) {
      return const _LogLineStyle(color: OpenHandConsolePalette.muted);
    }
    // 成功标记
    if (line.contains('✓')) {
      return const _LogLineStyle(
        color: OpenHandConsolePalette.success,
        bold: true,
      );
    }
    // 警告标记
    if (line.contains('⚠')) {
      return const _LogLineStyle(
        color: OpenHandConsolePalette.warning,
        bold: true,
      );
    }
    // 错误标记
    if (line.contains('✗') ||
        line.contains('[stderr error]') ||
        line.contains('[stdout error]')) {
      return const _LogLineStyle(color: _kStdioErrorColor, bold: true);
    }
    // 系统时间戳行（如 [19:38:23] 进程已启动）
    if (line.startsWith('[') && _kStdioTimestampPrefix.hasMatch(line)) {
      return const _LogLineStyle(
        color: OpenHandConsolePalette.timestamp,
        bold: true,
        topPadding: _kStdioGroupTopPadding,
      );
    }
    // JSON-RPC 摘要行
    if (line.startsWith('[jsonrpc')) {
      return const _LogLineStyle(
        color: OpenHandConsolePalette.jsonRpc,
        bold: true,
        topPadding: _kStdioGroupTopPadding,
      );
    }
    // JSON-RPC 摘要的缩进详情行
    if (line.startsWith('  ·') || line.startsWith('  …')) {
      return const _LogLineStyle(
        color: _kStdioJsonRpcDetailColor,
        fontSize: _kStdioSecondaryFontSize,
      );
    }
    // JSON-RPC 摘要的缩进属性行
    if (line.startsWith('  ') && (line.contains(': ') || line.contains('：'))) {
      return const _LogLineStyle(
        color: _kStdioJsonRpcAttributeColor,
        fontSize: _kStdioSecondaryFontSize,
      );
    }
    // stderr 输出
    if (line.startsWith('[stderr]')) {
      final content = line
          .substring(_kStdioStderrPrefix.length)
          .trim()
          .toLowerCase();
      // stderr 中的错误
      if (content.contains('error') ||
          content.contains('fatal') ||
          content.contains('failed')) {
        return const _LogLineStyle(color: _kStdioErrorColor);
      }
      // stderr 中的警告
      if (content.contains('warn') || content.contains('deprecat')) {
        return const _LogLineStyle(color: OpenHandConsolePalette.warning);
      }
      // stderr 中的普通信息输出（很多 MCP 服务把正常信息写到 stderr）
      return const _LogLineStyle(color: _kStdioStderrInfoColor);
    }
    // stdout closed / stderr closed 等系统事件
    if (line.startsWith('[stdout') || line.startsWith('[stderr')) {
      return const _LogLineStyle(
        color: _kStdioSystemEventColor,
        fontSize: _kStdioSecondaryFontSize,
      );
    }
    // 普通 stdout 输出
    return const _LogLineStyle(color: _kStdioStdoutColor);
  }
}

// ── STDIO 运行日志专属色阶 ──
// 比安装控制台多分了 jsonrpc / stderr / 系统事件几档，故不并入
// OpenHandConsolePalette 的通用令牌。
const Color _kStdioErrorColor = Color(0xFFF87171);
const Color _kStdioJsonRpcDetailColor = Color(0xFFC4B5FD);
const Color _kStdioJsonRpcAttributeColor = Color(0xFFD1D5DB);
const Color _kStdioStderrInfoColor = Color(0xFFD4A574);
const Color _kStdioSystemEventColor = Color(0xFF6B7280);
const Color _kStdioStdoutColor = Color(0xFFE5E7EB);
const Color _kStdioLogSurface = Color(0xFF1A1A2E);
const Duration _kLogFollowDuration = Duration(milliseconds: 150);
const double _kStdioSecondaryFontSize = 10.5;
const double _kStdioGroupTopPadding = 4;
const String _kStdioStderrPrefix = '[stderr]';
final RegExp _kStdioTimestampPrefix = RegExp(r'^\[\d{2}:\d{2}:\d{2}\]');

class _LogLineStyle {
  const _LogLineStyle({
    required this.color,
    this.fontSize = kOpenHandConsoleLogFontSize,
    this.bold = false,
    this.topPadding = 0,
  });

  final Color color;
  final double fontSize;
  final bool bold;
  final double topPadding;
}

// STDIO MCP 服务运行时详情弹窗

/// 显示 STDIO MCP 服务的运行时详情弹窗。
Future<void> showStdioDetailsDialog(BuildContext context, McpServer server) {
  return showAnimatedDialog(
    context: context,
    builder: (ctx) => _StdioDetailsDialog(server: server),
  );
}

class _StdioDetailsDialog extends StatefulWidget {
  const _StdioDetailsDialog({required this.server});

  final McpServer server;

  @override
  State<_StdioDetailsDialog> createState() => _StdioDetailsDialogState();
}

class _StdioDetailsDialogState extends State<_StdioDetailsDialog> {
  Map<String, String> _runtimeInfo = {};
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadInfo();
    // 每 3 秒刷新一次运行时信息
    _refreshTimer = startNonOverlappingPeriodicTimer(
      const Duration(seconds: 3),
      (_) => _loadInfo(),
      callbackTimeout: const Duration(seconds: 10),
      onError: (error, stack) =>
          silentLog('mcp_stdio_dialogs', '刷新运行时信息', error, stack),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await McpStdioProcessManager.instance.getRuntimeInfo(
        widget.server.name,
      );
      if (mounted) {
        setState(() {
          _runtimeInfo = info;
          _loading = false;
        });
      }
    } catch (error, stack) {
      silentLog('mcp_stdio_dialogs', '加载运行时信息', error, stack);
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final processInfo = McpStdioProcessManager.instance.infoFor(
      widget.server.name,
    );

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthCompact,
      maxHeight: kOpenHandDialogHeightCompact,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StdioDialogHeader(
            icon: Icons.analytics_outlined,
            title: l10n.mcpStdioDialogRuntimeDetailsTitle(widget.server.name),
            subtitle: widget.server.summary,
            actions: [
              _StdioDialogHeaderAction(
                tooltip: l10n.mcpStdioDialogRefresh,
                icon: Icons.refresh_rounded,
                onPressed: _loading ? null : _loadInfo,
              ),
            ],
          ),
          // 内容
          Flexible(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // 进程状态
                      _InfoSection(
                        title: l10n.mcpStdioDialogProcessStatus,
                        icon: Icons.memory_rounded,
                        color: processInfo.isRunning
                            ? OpenHandStatusColors.success
                            : theme.colorScheme.onSurfaceVariant,
                        children: [
                          for (final entry in _runtimeInfo.entries.take(5))
                            _InfoRow(label: entry.key, value: entry.value),
                        ],
                      ),
                      kOpenHandGap16,
                      // 服务配置
                      _InfoSection(
                        title: l10n.mcpStdioDialogServiceConfig,
                        icon: Icons.settings_rounded,
                        children: [
                          _InfoRow(
                            label: l10n.mcpStdioDialogType,
                            value: 'STDIO',
                          ),
                          _InfoRow(
                            label: l10n.mcpStdioDialogCommand,
                            value: widget.server.command,
                          ),
                          if (widget.server.args.isNotEmpty)
                            _InfoRow(
                              label: l10n.mcpStdioDialogArgs,
                              value: widget.server.args.join(' '),
                            ),
                          _InfoRow(
                            label: l10n.mcpStdioDialogEnabled,
                            value: widget.server.enabled
                                ? l10n.mcpStdioDialogYes
                                : l10n.mcpStdioDialogNo,
                          ),
                        ],
                      ),
                      kOpenHandGap16,
                      // 环境信息
                      _InfoSection(
                        title: l10n.mcpStdioDialogEnvironment,
                        icon: Icons.computer_rounded,
                        children: [
                          for (final entry in _runtimeInfo.entries.skip(5))
                            _InfoRow(label: entry.key, value: entry.value),
                        ],
                      ),
                      if (processInfo.errorMessage != null) ...[
                        kOpenHandGap16,
                        _InfoSection(
                          title: l10n.mcpStdioDialogError,
                          icon: Icons.error_outline_rounded,
                          color: theme.colorScheme.error,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                processInfo.errorMessage!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                  fontFamily: kOpenHandMonospaceFontFamily,
                                  fontSize: 11,
                                ),
                              ),
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

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.icon,
    required this.children,
    this.color,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: effectiveColor),
            kOpenHandHGap8,
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: effectiveColor,
              ),
            ),
          ],
        ),
        kOpenHandGap8,
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            borderRadius: BorderRadius.circular(kOpenHandRadius10),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

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
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontFamily: kOpenHandMonospaceFontFamily,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// STDIO MCP 服务依赖管理弹窗

/// 显示 STDIO MCP 服务的依赖管理弹窗（安装/更新/卸载 npm 包）。
Future<void> showStdioDepsDialog(BuildContext context, McpServer server) {
  return showAnimatedDialog(
    context: context,
    builder: (ctx) => _StdioDepsDialog(server: server),
  );
}

class _StdioDepsDialog extends StatefulWidget {
  const _StdioDepsDialog({required this.server});

  final McpServer server;

  @override
  State<_StdioDepsDialog> createState() => _StdioDepsDialogState();
}

class _StdioDepsDialogState extends State<_StdioDepsDialog> {
  final ScrollController _logScroll = ScrollController();
  final AutoFollowScrollGuard _logGuard = AutoFollowScrollGuard();
  final BoundedLogBuffer _logs = BoundedLogBuffer();
  bool _operating = false;
  bool _checking = true;
  bool _packageInstalled = false;
  String? _installedVersion;
  String? _latestVersion;
  String? _error;
  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  String get _packageName {
    // 从命令配置中提取包名，兼容两种输入习惯：
    //   1. command="npx", args=["@playwright/mcp"]
    //   2. command="npx chrome-devtools-mcp@latest", args=["--autoConnect"]
    final cmd = widget.server.command.trim();
    final tokens = cmd.split(kInlineWhitespacePattern);
    // command 字段包含多个 token 时，第二个 token 就是包名
    if (tokens.length > 1) return tokens[1];
    // 否则从 args 的第一个非 flag 参数提取
    for (final arg in widget.server.args) {
      final trimmed = arg.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('-')) continue;
      return trimmed;
    }
    return '';
  }

  bool get _isNpxService => isMcpNpxCommandLine(widget.server.command);

  bool get _isUvxService => isMcpUvxCommandLine(widget.server.command);

  bool get _isPackageManagerService => _isNpxService || _isUvxService;

  /// 清理后的包名（去掉 @version/@latest 后缀），用于 npm/uv 命令操作和状态检查。
  String get _cleanPackageName =>
      _packageName.replaceAll(RegExp(r'@[^/]*$'), '');

  @override
  void initState() {
    super.initState();
    _checkDepsStatus();
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  void _addLog(String line) {
    _logs.add(line);
    if (!mounted) return;
    setState(() {});
    _logGuard.scheduleFollowToBottom(
      _logScroll,
      animated: true,
      animationDuration: openHandMotionDuration(context, _kLogFollowDuration),
    );
  }

  Future<void> _checkDepsStatus() async {
    setState(() => _checking = true);
    final pkg = _packageName;
    if (pkg.isEmpty || !_isPackageManagerService) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    final cleanPkg = _cleanPackageName;
    try {
      if (_isNpxService) {
        // npm 全局安装状态检查：用清理后的包名查询
        final listResult = await runTrackedProcessOrFailed(
          'npm',
          ['list', '-g', cleanPkg, '--depth=0'],
          timeout: _kPackageQueryTimeout,
          environment: SystemProxyResolver.instance
              .resolveSubprocessEnvironment(),
        );
        // npm list 输出格式如 "├── chrome-devtools-mcp@0.25.0"
        // 用清理后的包名匹配，避免 @latest 导致永远匹配不上
        _packageInstalled =
            listResult.exitCode == 0 &&
            listResult.stdout.toString().contains(cleanPkg);
        if (_packageInstalled) {
          final match = RegExp(
            '${RegExp.escape(cleanPkg)}@([\\d][\\d.]*)',
          ).firstMatch(listResult.stdout.toString());
          _installedVersion = match?.group(1);
        }
        // 检查最新版本
        try {
          final viewResult = await runTrackedProcessOrFailed(
            'npm',
            ['view', cleanPkg, 'version'],
            timeout: _kPackageQueryTimeout,
            environment: SystemProxyResolver.instance
                .resolveSubprocessEnvironment(),
          );
          if (viewResult.exitCode == 0) {
            _latestVersion = viewResult.stdout.toString().trim();
          }
        } catch (error, stack) {
          silentLog(
            'mcp_stdio_dialogs',
            '查询 npm 软件包版本：$cleanPkg',
            error,
            stack,
          );
        }
      } else if (_isUvxService) {
        // uvx/pip 全局安装状态检查
        final listResult = await runTrackedProcessOrFailed(
          'uv',
          ['tool', 'list'],
          timeout: _kPackageQueryTimeout,
          environment: SystemProxyResolver.instance
              .resolveSubprocessEnvironment(),
        );
        _packageInstalled =
            listResult.exitCode == 0 &&
            listResult.stdout.toString().contains(cleanPkg);
        if (_packageInstalled) {
          final match = RegExp(
            '${RegExp.escape(cleanPkg)}\\s+v?([\\d][\\d.]*)',
          ).firstMatch(listResult.stdout.toString());
          _installedVersion = match?.group(1);
        }
      }
    } catch (error, stack) {
      silentLog('mcp_stdio_dialogs', '检查软件包状态', error, stack);
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<bool> _runPackageOperation(
    String action,
    String executable,
    List<String> args,
  ) async {
    final l10n = _l10n;
    setState(() {
      _operating = true;
      _error = null;
      _logs.clear();
    });
    _addLog('[${_ts()}] > $executable ${args.join(' ')}');
    _addLog('');
    var succeeded = false;
    try {
      final result = await runTrackedProcessWithLineLogging(
        executable,
        args,
        environment: SystemProxyResolver.instance
            .resolveSubprocessEnvironment(),
        timeout: const Duration(minutes: 5),
        tag: 'mcp_stdio_dialogs',
        onStdoutLine: _addLog,
        onStderrLine: _addLog,
        onTimeout: () => _addLog(l10n.mcpStdioDialogOperationTimeout),
      );
      final exitCode = result.exitCode;
      _addLog('');
      if (exitCode == 0) {
        _addLog(l10n.mcpStdioDialogOperationCompleted(_ts(), action, 0));
        await _checkDepsStatus();
        succeeded = true;
      } else {
        _addLog(l10n.mcpStdioDialogOperationFailed(_ts(), action, exitCode));
        _error = l10n.mcpStdioDialogOperationFailedPlain(action, exitCode);
      }
    } catch (error, stack) {
      silentLog('mcp_stdio_dialogs', '执行软件包操作', error, stack);
      final message = mcpFailureMessage(
        error,
        fallback: l10n.mcpOperationFailed,
      );
      _addLog(l10n.mcpStdioDialogOperationException(_ts(), message));
      _error = message;
    }
    if (mounted) setState(() => _operating = false);
    return succeeded;
  }

  Future<void> _installDeps() async {
    final l10n = _l10n;
    final cleanPkg = _cleanPackageName;
    if (cleanPkg.isEmpty) return;
    if (_isNpxService) {
      final installed = await _runPackageOperation(
        l10n.mcpStdioDialogInstall,
        'npm',
        ['install', '-g', cleanPkg],
      );
      if (!installed || !mounted) return;
      setState(() => _operating = true);
      // 同时预热隔离缓存
      _addLog('');
      _addLog(l10n.mcpStdioDialogWarmCache(_ts()));
      final cacheRoot = mcpStdioIsolatedCacheRoot();
      try {
        await runTrackedProcessOrFailed(
          'npm',
          ['cache', 'add', cleanPkg],
          environment: <String, String>{
            ...SystemProxyResolver.instance.resolveSubprocessEnvironment(),
            'npm_config_cache': '$cacheRoot/npm',
          },
          timeout: const Duration(seconds: 30),
          tag: 'mcp_stdio.npm_cache_add',
        );
        _addLog(l10n.mcpStdioDialogWarmCacheDone(_ts()));
      } catch (error, stack) {
        silentLog('mcp_stdio_dialogs', '预热 MCP 软件包缓存', error, stack);
        _addLog(
          l10n.mcpStdioDialogWarmCacheSkipped(
            _ts(),
            mcpFailureMessage(error, fallback: l10n.mcpOperationFailed),
          ),
        );
      } finally {
        if (mounted) setState(() => _operating = false);
      }
    } else if (_isUvxService) {
      await _runPackageOperation(l10n.mcpStdioDialogInstall, 'uv', [
        'tool',
        'install',
        cleanPkg,
      ]);
    }
    if (mounted) setState(() {});
  }

  Future<void> _updateDeps() async {
    final l10n = _l10n;
    final cleanPkg = _cleanPackageName;
    if (_isNpxService) {
      await _runPackageOperation(l10n.mcpStdioDialogUpdate, 'npm', [
        'update',
        '-g',
        cleanPkg,
      ]);
    } else {
      await _runPackageOperation(l10n.mcpStdioDialogUpdate, 'uv', [
        'tool',
        'upgrade',
        cleanPkg,
      ]);
    }
  }

  Future<void> _uninstallDeps() async {
    final l10n = _l10n;
    final cleanPkg = _cleanPackageName;
    if (_isNpxService) {
      await _runPackageOperation(l10n.mcpStdioDialogUninstall, 'npm', [
        'uninstall',
        '-g',
        cleanPkg,
      ]);
    } else {
      await _runPackageOperation(l10n.mcpStdioDialogUninstall, 'uv', [
        'tool',
        'uninstall',
        cleanPkg,
      ]);
    }
  }

  static String _ts() {
    return formatHourMinuteSecond(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final cleanPkg = _cleanPackageName;
    final hasUpdate =
        _packageInstalled &&
        _latestVersion != null &&
        _installedVersion != null &&
        _latestVersion != _installedVersion;

    return buildOpenHandResponsiveDialogShell(
      context: context,
      maxWidth: kOpenHandDialogWidthStandard,
      maxHeight: kOpenHandDialogHeightCompact,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StdioDialogHeader(
            icon: Icons.inventory_2_outlined,
            title: l10n.mcpStdioDialogDepsTitle,
            subtitle: cleanPkg,
          ),
          // 状态 + 操作按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: OpenHandContentStateSwitcher(
              stateKey: _checking
                  ? 'checking'
                  : (!_isPackageManagerService || cleanPkg.isEmpty)
                  ? 'unmanaged'
                  : 'ready',
              child: _checking
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                    )
                  : !_isPackageManagerService || cleanPkg.isEmpty
                  ? Text(
                      l10n.mcpStdioDialogNoDepsToManage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _packageInstalled
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              size: 18,
                              color: _packageInstalled
                                  ? OpenHandStatusColors.success
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            kOpenHandHGap8,
                            Expanded(
                              child: Text(
                                _packageInstalled
                                    ? l10n.mcpStdioDialogInstalledVersion(
                                        _installedVersion ??
                                            l10n.mcpStdioDialogUnknownVersion,
                                      )
                                    : l10n.mcpStdioDialogNotGloballyInstalled,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            // 操作按钮
                            if (!_packageInstalled)
                              FilledButton.tonalIcon(
                                onPressed: _operating ? null : _installDeps,
                                icon: const Icon(
                                  Icons.download_rounded,
                                  size: 18,
                                ),
                                label: Text(l10n.mcpStdioDialogInstall),
                              )
                            else ...[
                              if (hasUpdate)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: FilledButton.tonalIcon(
                                    onPressed: _operating ? null : _updateDeps,
                                    icon: const Icon(
                                      Icons.system_update_alt_rounded,
                                      size: 18,
                                    ),
                                    label: Text(l10n.mcpStdioDialogUpdate),
                                  ),
                                ),
                              IconButton.filledTonal(
                                tooltip: l10n.mcpStdioDialogUninstall,
                                onPressed: _operating ? null : _uninstallDeps,
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
                        if (_latestVersion != null) ...[
                          kOpenHandGap6,
                          Text(
                            l10n.mcpStdioDialogLatestVersion(_latestVersion!) +
                                (hasUpdate
                                    ? l10n.mcpStdioDialogUpdateAvailableSuffix
                                    : ''),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: hasUpdate
                                  ? OpenHandStatusColors.warning
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          OpenHandInlineErrorText(message: _error),
          // 进度指示
          if (_operating)
            LinearProgressIndicator(
              minHeight: 3,
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            )
          else
            kOpenHandGap3,
          // 终端输出区域
          if (_logs.isNotEmpty || _operating)
            Flexible(
              child: OpenHandConsoleLogPanel(
                lineCount: _logs.length,
                lineAt: (index) => _logs[index],
                controller: _logScroll,
                onNotification: _logGuard.handleNotification,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
