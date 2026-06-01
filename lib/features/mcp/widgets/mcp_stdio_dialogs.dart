import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/system_proxy.dart';
import '../../../app/theme/openhand_status_colors.dart';
import '../../../shared/ui/animated_dialog.dart';
import '../../../shared/ui/auto_follow_scroll_guard.dart';
import '../../../shared/ui/openhand_snack_bar.dart';
import '../model/mcp_server.dart';
import '../service/mcp_stdio_process_manager.dart';
import '../service/mcp_tool_discovery_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STDIO MCP 服务日志查看弹窗
// ─────────────────────────────────────────────────────────────────────────────

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
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
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
    if (!mounted) return;
    setState(() {});
    final info = McpStdioProcessManager.instance.infoFor(widget.server.name);
    if (_autoScroll && info.logs.length > _lastLogCount) {
      _lastLogCount = info.logs.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollGuard.followToBottom(
          _scrollController,
          animated: true,
          animationDuration: const Duration(milliseconds: 220),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final info = McpStdioProcessManager.instance.infoFor(widget.server.name);
    final logs = info.logs;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.terminal_rounded,
                    size: 20,
                    color: info.isRunning
                        ? const Color(0xFF16A34A)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.server.name} ${isZh ? "日志" : "Logs"}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          info.isRunning
                              ? (isZh
                                    ? '运行中 · PID ${info.pid}'
                                    : 'Running · PID ${info.pid}')
                              : (isZh ? '已停止' : 'Stopped'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 操作按钮组
                  Wrap(
                    spacing: 4,
                    children: [
                      Tooltip(
                        message: isZh ? '自动滚动' : 'Auto-scroll',
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton(
                            onPressed: () =>
                                setState(() => _autoScroll = !_autoScroll),
                            icon: Icon(
                              _autoScroll
                                  ? Icons.vertical_align_bottom
                                  : Icons.pause,
                              size: 18,
                            ),
                            isSelected: _autoScroll,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: isZh ? '复制日志' : 'Copy logs',
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton(
                            onPressed: logs.isEmpty
                                ? null
                                : () {
                                    Clipboard.setData(
                                      ClipboardData(text: logs.join('\n')),
                                    );
                                    OpenHandSnackBar.showSuccess(
                                      context,
                                      isZh
                                          ? '已复制到剪贴板'
                                          : 'Copied to clipboard',
                                    );
                                  },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: isZh ? '清除日志' : 'Clear logs',
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton(
                            onPressed: logs.isEmpty
                                ? null
                                : () => McpStdioProcessManager.instance
                                      .clearLogs(widget.server.name),
                            icon: const Icon(
                              Icons.delete_sweep_rounded,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 状态指示条
            Container(
              height: 3,
              color: info.isRunning
                  ? const Color(0xFF16A34A)
                  : info.isTransitioning
                  ? OpenHandStatusColors.warning
                  : theme.colorScheme.outlineVariant,
            ),
            // 终端输出区域
            Flexible(
              child: Container(
                color: const Color(0xFF1A1A2E),
                child: logs.isEmpty
                    ? Center(
                        child: Text(
                          isZh ? '暂无日志输出' : 'No log output yet',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFF808080),
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
                                  fontFamily: 'monospace',
                                  fontSize: style.fontSize,
                                  height: 1.5,
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
                  const SizedBox(width: 6),
                  Text(
                    isZh ? '${logs.length} 行' : '${logs.length} lines',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (info.uptime != null)
                    Text(
                      isZh
                          ? '运行 ${_formatUptime(info.uptime!)}'
                          : 'Up ${_formatUptime(info.uptime!)}',
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

  _LogLineStyle _resolveLogLineStyle(String line) {
    // 空行
    if (line.trim().isEmpty) {
      return const _LogLineStyle(color: Color(0xFF808080));
    }
    // 成功标记
    if (line.contains('✓')) {
      return const _LogLineStyle(color: Color(0xFF4ADE80), bold: true);
    }
    // 警告标记
    if (line.contains('⚠')) {
      return const _LogLineStyle(color: Color(0xFFFBBF24), bold: true);
    }
    // 错误标记
    if (line.contains('✗') ||
        line.contains('[stderr error]') ||
        line.contains('[stdout error]')) {
      return const _LogLineStyle(color: Color(0xFFF87171), bold: true);
    }
    // 系统时间戳行（如 [19:38:23] 进程已启动）
    if (line.startsWith('[') &&
        RegExp(r'^\[\d{2}:\d{2}:\d{2}\]').hasMatch(line)) {
      return const _LogLineStyle(
        color: Color(0xFF93C5FD),
        bold: true,
        topPadding: 4,
      );
    }
    // JSON-RPC 摘要行
    if (line.startsWith('[jsonrpc')) {
      return const _LogLineStyle(
        color: Color(0xFFA78BFA),
        bold: true,
        topPadding: 4,
      );
    }
    // JSON-RPC 摘要的缩进详情行
    if (line.startsWith('  ·') || line.startsWith('  …')) {
      return const _LogLineStyle(color: Color(0xFFC4B5FD), fontSize: 10.5);
    }
    // JSON-RPC 摘要的缩进属性行
    if (line.startsWith('  ') && (line.contains(': ') || line.contains('：'))) {
      return const _LogLineStyle(color: Color(0xFFD1D5DB), fontSize: 10.5);
    }
    // stderr 输出
    if (line.startsWith('[stderr]')) {
      final content = line.substring(8).trim().toLowerCase();
      // stderr 中的错误
      if (content.contains('error') ||
          content.contains('fatal') ||
          content.contains('failed')) {
        return const _LogLineStyle(color: Color(0xFFF87171));
      }
      // stderr 中的警告
      if (content.contains('warn') || content.contains('deprecat')) {
        return const _LogLineStyle(color: Color(0xFFFBBF24));
      }
      // stderr 中的普通信息输出（很多 MCP 服务把正常信息写到 stderr）
      return const _LogLineStyle(color: Color(0xFFD4A574));
    }
    // stdout closed / stderr closed 等系统事件
    if (line.startsWith('[stdout') || line.startsWith('[stderr')) {
      return const _LogLineStyle(color: Color(0xFF6B7280), fontSize: 10.5);
    }
    // 普通 stdout 输出
    return const _LogLineStyle(color: Color(0xFFE5E7EB));
  }

  String _formatUptime(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}

class _LogLineStyle {
  const _LogLineStyle({
    required this.color,
    this.fontSize = 11,
    this.bold = false,
    this.topPadding = 0,
  });

  final Color color;
  final double fontSize;
  final bool bold;
  final double topPadding;
}

// ─────────────────────────────────────────────────────────────────────────────
// STDIO MCP 服务运行时详情弹窗
// ─────────────────────────────────────────────────────────────────────────────

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
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadInfo();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    final info = await McpStdioProcessManager.instance.getRuntimeInfo(
      widget.server.name,
    );
    if (mounted) {
      setState(() {
        _runtimeInfo = info;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final processInfo = McpStdioProcessManager.instance.infoFor(
      widget.server.name,
    );

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.server.name} ${isZh ? "运行时详情" : "Runtime Details"}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          widget.server.summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // 操作按钮组
                  Wrap(
                    spacing: 4,
                    children: [
                      Tooltip(
                        message: isZh ? '刷新' : 'Refresh',
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: IconButton(
                            onPressed: _loading ? null : _loadInfo,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ),
                    ],
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
                        // 进程状态
                        _InfoSection(
                          title: isZh ? '进程状态' : 'Process Status',
                          icon: Icons.memory_rounded,
                          color: processInfo.isRunning
                              ? const Color(0xFF16A34A)
                              : theme.colorScheme.onSurfaceVariant,
                          children: [
                            for (final entry in _runtimeInfo.entries.take(5))
                              _InfoRow(label: entry.key, value: entry.value),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 服务配置
                        _InfoSection(
                          title: isZh ? '服务配置' : 'Service Config',
                          icon: Icons.settings_rounded,
                          children: [
                            _InfoRow(
                              label: isZh ? '类型' : 'Type',
                              value: 'STDIO',
                            ),
                            _InfoRow(
                              label: isZh ? '命令' : 'Command',
                              value: widget.server.command,
                            ),
                            if (widget.server.args.isNotEmpty)
                              _InfoRow(
                                label: isZh ? '参数' : 'Args',
                                value: widget.server.args.join(' '),
                              ),
                            _InfoRow(
                              label: isZh ? '已启用' : 'Enabled',
                              value: widget.server.enabled
                                  ? (isZh ? '是' : 'Yes')
                                  : (isZh ? '否' : 'No'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 环境信息
                        _InfoSection(
                          title: isZh ? '环境信息' : 'Environment',
                          icon: Icons.computer_rounded,
                          children: [
                            for (final entry in _runtimeInfo.entries.skip(5))
                              _InfoRow(label: entry.key, value: entry.value),
                          ],
                        ),
                        if (processInfo.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          _InfoSection(
                            title: isZh ? '错误信息' : 'Error',
                            icon: Icons.error_outline_rounded,
                            color: theme.colorScheme.error,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Text(
                                  processInfo.errorMessage!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                    fontFamily: 'monospace',
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
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: effectiveColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
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
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STDIO MCP 服务依赖管理弹窗
// ─────────────────────────────────────────────────────────────────────────────

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
  final List<String> _logs = [];
  bool _operating = false;
  bool _checking = true;
  bool _packageInstalled = false;
  String? _installedVersion;
  String? _latestVersion;
  String? _error;

  String get _packageName {
    // 从命令配置中提取包名，兼容两种输入习惯：
    //   1. command="npx", args=["@playwright/mcp"]
    //   2. command="npx chrome-devtools-mcp@latest", args=["--autoConnect"]
    final cmd = widget.server.command.trim();
    final tokens = cmd.split(RegExp(r'\s+'));
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

  bool get _isNpxService {
    final cmd = widget.server.command.trim();
    if (cmd == 'npx' || cmd.endsWith('/npx')) return true;
    final firstToken = cmd.split(RegExp(r'\s+')).first;
    return firstToken == 'npx' || firstToken.endsWith('/npx');
  }

  bool get _isUvxService {
    final cmd = widget.server.command.trim();
    if (cmd == 'uvx' || cmd.endsWith('/uvx')) return true;
    final firstToken = cmd.split(RegExp(r'\s+')).first;
    return firstToken == 'uvx' || firstToken.endsWith('/uvx');
  }

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
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _logGuard.followToBottom(
          _logScroll,
          animated: true,
          animationDuration: const Duration(milliseconds: 150),
        );
      });
    }
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
          [
            'list',
            '-g',
            cleanPkg,
            '--depth=0',
          ],
          timeout: const Duration(seconds: 10),
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
            [
              'view',
              cleanPkg,
              'version',
            ],
            timeout: const Duration(seconds: 10),
            environment: SystemProxyResolver.instance
                .resolveSubprocessEnvironment(),
          );
          if (viewResult.exitCode == 0) {
            _latestVersion = viewResult.stdout.toString().trim();
          }
        } catch (_) {}
      } else if (_isUvxService) {
        // uvx/pip 全局安装状态检查
        final listResult = await runTrackedProcessOrFailed(
          'uv',
          ['tool', 'list'],
          timeout: const Duration(seconds: 10),
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
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _runPackageOperation(
    String action,
    String executable,
    List<String> args,
  ) async {
    setState(() {
      _operating = true;
      _error = null;
      _logs.clear();
    });
    _addLog('[${_ts()}] > $executable ${args.join(' ')}');
    _addLog('');
    try {
      final process = await startTrackedProcess(
        executable,
        args,
        environment: SystemProxyResolver.instance
            .resolveSubprocessEnvironment(),
      );
      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) _addLog(line);
        }
      });
      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) _addLog(line.trim());
        }
      });
      final exitCode = await process.exitCode.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      _addLog('');
      if (exitCode == 0) {
        _addLog('[${_ts()}] ✓ $action 完成 (exit code: 0)');
        await _checkDepsStatus();
      } else {
        _addLog('[${_ts()}] ✗ $action 失败 (exit code: $exitCode)');
        _error = '$action 失败 (exit code: $exitCode)';
      }
    } catch (e) {
      _addLog('[${_ts()}] ✗ 异常: $e');
      _error = '$e';
    }
    if (mounted) setState(() => _operating = false);
  }

  Future<void> _installDeps() async {
    final cleanPkg = _cleanPackageName;
    if (cleanPkg.isEmpty) return;
    if (_isNpxService) {
      await _runPackageOperation('安装', 'npm', ['install', '-g', cleanPkg]);
      // 同时预热隔离缓存
      _addLog('');
      _addLog('[${_ts()}] 预热隔离缓存…');
      final cacheRoot = mcpStdioIsolatedCacheRoot();
      try {
        await runTrackedProcessOrFailed(
          'npm',
          ['cache', 'add', cleanPkg],
          environment: <String, String>{
            ...SystemProxyResolver.instance
                .resolveSubprocessEnvironment(),
            'npm_config_cache': '$cacheRoot/npm',
          },
          timeout: const Duration(seconds: 30),
          tag: 'mcp_stdio.npm_cache_add',
        );
        _addLog('[${_ts()}] ✓ 缓存预热完成');
      } catch (e) {
        _addLog('[${_ts()}] 缓存预热跳过: $e');
      }
    } else if (_isUvxService) {
      await _runPackageOperation('安装', 'uv', ['tool', 'install', cleanPkg]);
    }
    if (mounted) setState(() {});
  }

  Future<void> _updateDeps() {
    final cleanPkg = _cleanPackageName;
    if (_isNpxService) {
      return _runPackageOperation('更新', 'npm', ['update', '-g', cleanPkg]);
    } else {
      return _runPackageOperation('更新', 'uv', ['tool', 'upgrade', cleanPkg]);
    }
  }

  Future<void> _uninstallDeps() {
    final cleanPkg = _cleanPackageName;
    if (_isNpxService) {
      return _runPackageOperation('卸载', 'npm', ['uninstall', '-g', cleanPkg]);
    } else {
      return _runPackageOperation('卸载', 'uv', ['tool', 'uninstall', cleanPkg]);
    }
  }

  static String _ts() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZh = Localizations.localeOf(context).languageCode.startsWith('zh');
    final cleanPkg = _cleanPackageName;
    final hasUpdate =
        _packageInstalled &&
        _latestVersion != null &&
        _installedVersion != null &&
        _latestVersion != _installedVersion;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isZh ? '依赖管理' : 'Dependency Management',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (cleanPkg.isNotEmpty)
                          Text(
                            cleanPkg,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            // 状态 + 操作按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
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
                      isZh
                          ? '此服务非包管理器类型（npx / uvx），无需管理依赖。'
                          : 'This service is not package-manager-based (npx / uvx). No deps to manage.',
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
                                  ? const Color(0xFF16A34A)
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _packageInstalled
                                    ? '${isZh ? "已安装" : "Installed"} v${_installedVersion ?? "?"}'
                                    : (isZh
                                          ? '未全局安装'
                                          : 'Not globally installed'),
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
                                label: Text(isZh ? '安装' : 'Install'),
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
                                    label: Text(isZh ? '更新' : 'Update'),
                                  ),
                                ),
                              IconButton.filledTonal(
                                tooltip: isZh ? '卸载' : 'Uninstall',
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
                          const SizedBox(height: 6),
                          Text(
                            '${isZh ? "最新版本" : "Latest"}: $_latestVersion'
                            '${hasUpdate ? (isZh ? " (可更新)" : " (update available)") : ""}',
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
            // 进度指示
            if (_operating)
              LinearProgressIndicator(
                minHeight: 3,
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              )
            else
              const SizedBox(height: 3),
            // 终端输出区域
            if (_logs.isNotEmpty || _operating)
              Flexible(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
                              return Text(
                                line,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  height: 1.5,
                                  color: _depsLogColor(line),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _depsLogColor(String line) {
    if (line.contains('✗') || line.toLowerCase().contains('error')) {
      return const Color(0xFFFF6B6B);
    }
    if (line.contains('✓')) return const Color(0xFF4ADE80);
    if (line.startsWith('[') && line.contains(']')) {
      return const Color(0xFF7DD3FC);
    }
    return const Color(0xFFD4D4D4);
  }
}
