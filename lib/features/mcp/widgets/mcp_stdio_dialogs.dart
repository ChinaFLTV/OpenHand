import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/animated_dialog.dart';
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
    barrierDismissible: true,
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
  bool _autoScroll = true;
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    McpStdioProcessManager.instance.addListener(_onUpdate);
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
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
          );
        }
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
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
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
                              ? (isZh ? '运行中 · PID ${info.pid}' : 'Running · PID ${info.pid}')
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
                  // 自动滚动切换
                  Tooltip(
                    message: isZh ? '自动滚动' : 'Auto-scroll',
                    child: IconButton(
                      onPressed: () => setState(() => _autoScroll = !_autoScroll),
                      icon: Icon(
                        _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
                        size: 18,
                      ),
                      isSelected: _autoScroll,
                    ),
                  ),
                  // 复制日志
                  Tooltip(
                    message: isZh ? '复制日志' : 'Copy logs',
                    child: IconButton(
                      onPressed: logs.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: logs.join('\n')));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(isZh ? '已复制到剪贴板' : 'Copied to clipboard')),
                              );
                            },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                    ),
                  ),
                  // 清除日志
                  Tooltip(
                    message: isZh ? '清除日志' : 'Clear logs',
                    child: IconButton(
                      onPressed: logs.isEmpty
                          ? null
                          : () => McpStdioProcessManager.instance.clearLogs(widget.server.name),
                      icon: const Icon(Icons.delete_sweep_rounded, size: 18),
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
            // 状态指示条
            Container(
              height: 3,
              color: info.isRunning
                  ? const Color(0xFF16A34A)
                  : info.isTransitioning
                      ? const Color(0xFFF59E0B)
                      : theme.colorScheme.outlineVariant,
            ),
            // 终端输出区域
            Flexible(
              child: Container(
                color: const Color(0xFF1E1E1E),
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
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final line = logs[index];
                          return Text(
                            line,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.5,
                              color: _logLineColor(line),
                            ),
                          );
                        },
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
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
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

  Color _logLineColor(String line) {
    if (line.startsWith('[stderr]')) return const Color(0xFFF59E0B);
    if (line.startsWith('✗') || line.toLowerCase().contains('error')) {
      return const Color(0xFFFF6B6B);
    }
    if (line.startsWith('[') && line.contains(']')) return const Color(0xFF7DD3FC);
    return const Color(0xFFD4D4D4);
  }

  String _formatUptime(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STDIO MCP 服务运行时详情弹窗
// ─────────────────────────────────────────────────────────────────────────────

/// 显示 STDIO MCP 服务的运行时详情弹窗。
Future<void> showStdioDetailsDialog(BuildContext context, McpServer server) {
  return showAnimatedDialog(
    context: context,
    barrierDismissible: true,
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
    final info = await McpStdioProcessManager.instance.getRuntimeInfo(widget.server.name);
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
    final processInfo = McpStdioProcessManager.instance.infoFor(widget.server.name);

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
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.analytics_outlined, size: 20, color: theme.colorScheme.primary),
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
                  // 刷新按钮
                  Tooltip(
                    message: isZh ? '刷新' : 'Refresh',
                    child: IconButton(
                      onPressed: _loading ? null : _loadInfo,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
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
                                padding: const EdgeInsets.symmetric(vertical: 4),
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
    barrierDismissible: true,
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
  final List<String> _logs = [];
  bool _operating = false;
  bool _checking = true;
  bool _packageInstalled = false;
  String? _installedVersion;
  String? _latestVersion;
  String? _error;

  String get _packageName {
    // 从 npx 命令的 args 中提取包名
    if (widget.server.args.isNotEmpty) {
      return widget.server.args.first.trim();
    }
    return '';
  }

  bool get _isNpxService {
    final cmd = widget.server.command.trim();
    return cmd == 'npx' || cmd.endsWith('/npx');
  }

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
        if (_logScroll.hasClients) {
          _logScroll.animateTo(
            _logScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  Future<void> _checkDepsStatus() async {
    setState(() => _checking = true);
    final pkg = _packageName;
    if (pkg.isEmpty || !_isNpxService) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    try {
      // 检查全局安装状态
      final listResult = await Process.run(
        'npm', ['list', '-g', pkg, '--depth=0'],
      ).timeout(const Duration(seconds: 10));
      _packageInstalled = listResult.exitCode == 0 &&
          listResult.stdout.toString().contains(pkg);
      if (_packageInstalled) {
        final match = RegExp('$pkg@([\\d.]+)')
            .firstMatch(listResult.stdout.toString());
        _installedVersion = match?.group(1);
      }
      // 检查最新版本
      try {
        final viewResult = await Process.run(
          'npm', ['view', pkg, 'version'],
        ).timeout(const Duration(seconds: 10));
        if (viewResult.exitCode == 0) {
          _latestVersion = viewResult.stdout.toString().trim();
        }
      } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _runNpmOperation(String action, List<String> args) async {
    setState(() { _operating = true; _error = null; _logs.clear(); });
    _addLog('[${_ts()}] > npm ${args.join(' ')}');
    _addLog('');
    try {
      final process = await Process.start('npm', args);
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
        onTimeout: () { process.kill(); return -1; },
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
    final pkg = _packageName;
    if (pkg.isEmpty) return;
    await _runNpmOperation('安装', ['install', '-g', pkg]);
    // 同时预热隔离缓存
    _addLog('');
    _addLog('[${_ts()}] 预热隔离缓存…');
    final cacheRoot = mcpStdioIsolatedCacheRoot();
    try {
      await Process.run('npm', ['cache', 'add', pkg],
        environment: {'npm_config_cache': '$cacheRoot/npm'},
      ).timeout(const Duration(seconds: 30));
      _addLog('[${_ts()}] ✓ 缓存预热完成');
    } catch (e) {
      _addLog('[${_ts()}] 缓存预热跳过: $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _updateDeps() => _runNpmOperation(
    '更新', ['update', '-g', _packageName],
  );

  Future<void> _uninstallDeps() => _runNpmOperation(
    '卸载', ['uninstall', '-g', _packageName],
  );

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
    final pkg = _packageName;
    final hasUpdate = _packageInstalled &&
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
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 20, color: theme.colorScheme.primary),
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
                        if (pkg.isNotEmpty)
                          Text(
                            pkg,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                              fontSize: 11,
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
            // 状态 + 操作按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: _checking
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                      ),
                    )
                  : !_isNpxService || pkg.isEmpty
                      ? Text(
                          isZh
                              ? '此服务非 npx 类型，无需管理 npm 依赖。'
                              : 'This service is not npx-based. No npm deps to manage.',
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
                                  _packageInstalled ? Icons.check_circle : Icons.cancel,
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
                                        : (isZh ? '未全局安装' : 'Not globally installed'),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                // 操作按钮
                                if (!_packageInstalled)
                                  FilledButton.tonalIcon(
                                    onPressed: _operating ? null : _installDeps,
                                    icon: const Icon(Icons.download_rounded, size: 18),
                                    label: Text(isZh ? '安装' : 'Install'),
                                  )
                                else ...[
                                  if (hasUpdate)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: FilledButton.tonalIcon(
                                        onPressed: _operating ? null : _updateDeps,
                                        icon: const Icon(Icons.system_update_alt_rounded, size: 18),
                                        label: Text(isZh ? '更新' : 'Update'),
                                      ),
                                    ),
                                  IconButton.filledTonal(
                                    tooltip: isZh ? '卸载' : 'Uninstall',
                                    onPressed: _operating ? null : _uninstallDeps,
                                    style: IconButton.styleFrom(
                                      foregroundColor: theme.colorScheme.error,
                                    ),
                                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
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
                                      ? const Color(0xFFF59E0B)
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
                      : ListView.builder(
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
    if (line.startsWith('[') && line.contains(']')) return const Color(0xFF7DD3FC);
    return const Color(0xFFD4D4D4);
  }
}
