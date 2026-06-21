import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../shared/ui/animated_dialog.dart';
import '../../shared/ui/openhand_safe_scrollbar.dart';
import '../../shared/util/localized_text.dart';
import '../ai/index.dart';
import 'android_reverse_adb_client.dart';
import 'android_reverse_session_config.dart';
import 'android_reverse_session_controller.dart';

const Duration _kSwitchDuration = Duration(milliseconds: 220);
const Curve _kSwitchInCurve = Curves.easeOutCubic;

Future<void> showAndroidReverseDashboardDialog(
  BuildContext context, {
  required AndroidReverseSessionController controller,
  required String sessionId,
}) {
  return showAnimatedDialog<void>(
    context: context,
    builder: (_) => _AndroidReverseDashboardDialog(
      controller: controller,
      sessionId: sessionId,
    ),
  );
}

enum _Tab {
  devices,
  overview,
  packages,
  processes,
  logcat,
  frida,
  network,
  staticAnalysis,
  certs,
  crypto,
}

extension _TabLabel on _Tab {
  String label(bool isZh) {
    return switch (this) {
      _Tab.devices => isZh ? '设备管理' : 'Devices',
      _Tab.overview => isZh ? '概览' : 'Overview',
      _Tab.packages => isZh ? 'APP 信息' : 'APP Info',
      _Tab.processes => isZh ? '进程' : 'Processes',
      _Tab.logcat => 'Logcat',
      _Tab.frida => 'Frida',
      _Tab.network => isZh ? '网络' : 'Network',
      _Tab.staticAnalysis => isZh ? '静态分析' : 'Static',
      _Tab.certs => isZh ? '证书' : 'Certs',
      _Tab.crypto => isZh ? '加密' : 'Crypto',
    };
  }

  IconData get icon => switch (this) {
    _Tab.devices => Icons.phone_android_rounded,
    _Tab.overview => Icons.dashboard_rounded,
    _Tab.packages => Icons.apps_rounded,
    _Tab.processes => Icons.memory_rounded,
    _Tab.logcat => Icons.receipt_long_rounded,
    _Tab.frida => Icons.bug_report_rounded,
    _Tab.network => Icons.wifi_rounded,
    _Tab.staticAnalysis => Icons.code_rounded,
    _Tab.certs => Icons.verified_user_rounded,
    _Tab.crypto => Icons.lock_rounded,
  };
}

class _AndroidReverseDashboardDialog extends StatefulWidget {
  const _AndroidReverseDashboardDialog({
    required this.controller,
    required this.sessionId,
  });

  final AndroidReverseSessionController controller;
  final String sessionId;

  @override
  State<_AndroidReverseDashboardDialog> createState() =>
      _AndroidReverseDashboardDialogState();
}

class _AndroidReverseDashboardDialogState
    extends State<_AndroidReverseDashboardDialog> {
  _Tab _currentTab = _Tab.devices;
  late final AndroidReverseSessionController _ctrl;
  final _logcatLines = <String>[];
  Timer? _logcatTimer;
  final TextEditingController _shellCtrl = TextEditingController();
  final TextEditingController _shellOutputCtrl = TextEditingController();
  final TextEditingController _fridaScriptCtrl = TextEditingController();
  final TextEditingController _base64Ctrl = TextEditingController();
  final TextEditingController _base64OutCtrl = TextEditingController();
  bool _loadingLogcat = false;
  bool _loadingPackages = false;
  bool _loadingProcesses = false;
  List<String> _packages = const <String>[];
  List<AndroidProcess> _processes = const <AndroidProcess>[];
  final _processFilter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller;
    _ctrl.addListener(_onControllerChanged);
    _refreshAll();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onControllerChanged);
    _logcatTimer?.cancel();
    _shellCtrl.dispose();
    _shellOutputCtrl.dispose();
    _fridaScriptCtrl.dispose();
    _base64Ctrl.dispose();
    _base64OutCtrl.dispose();
    _processFilter.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _refreshAll() {
    unawaited(_doRefreshDevices());
    unawaited(_doRefreshPackages());
    unawaited(_doRefreshProcesses());
  }

  Future<void> _doRefreshDevices() async {
    await _ctrl.refreshDevices();
  }

  Future<void> _doRefreshPackages() async {
    if (_loadingPackages) return;
    setState(() => _loadingPackages = true);
    try {
      final pkgs = await _ctrl.listPackages(thirdParty: true);
      if (mounted) setState(() => _packages = pkgs);
    } finally {
      if (mounted) setState(() => _loadingPackages = false);
    }
  }

  Future<void> _doRefreshProcesses() async {
    if (_loadingProcesses) return;
    setState(() => _loadingProcesses = true);
    try {
      final filter = _processFilter.text.trim().isEmpty
          ? null
          : _processFilter.text.trim();
      final procs = await _ctrl.refreshProcesses(filterName: filter);
      if (mounted) setState(() => _processes = procs);
    } finally {
      if (mounted) setState(() => _loadingProcesses = false);
    }
  }

  Future<void> _fetchLogcat() async {
    if (_loadingLogcat) return;
    setState(() => _loadingLogcat = true);
    try {
      final raw = await _ctrl.logcat(lines: 300);
      if (mounted && raw != null) {
        setState(() {
          _logcatLines
            ..clear()
            ..addAll(raw.split('\n'));
        });
      }
    } finally {
      if (mounted) setState(() => _loadingLogcat = false);
    }
  }

  Future<void> _runShell() async {
    final cmd = _shellCtrl.text.trim();
    if (cmd.isEmpty) return;
    final result = await _ctrl.shell(cmd);
    if (mounted) {
      _shellOutputCtrl.text = result ?? '(no output)';
    }
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(openHandIsChineseLocale(context) ? '已复制' : 'Copied'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isZh = openHandIsChineseLocale(context);
    final device = _ctrl.connectedDevice;
    final config =
        AndroidReverseSessionConfig.fromJson(
          context.watch<AiSessionController>().sessions
              .where((s) => s.id == widget.sessionId)
              .firstOrNull
              ?.metadata['android_reverse_config'],
        ) ??
        _ctrl.config;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 960,
          maxHeight: 720,
        ),
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            _buildHeader(context, cs, isZh, device, config),
            Divider(height: 1, color: cs.outlineVariant),
            // ── Tab bar ─────────────────────────────────────────────────
            _buildTabBar(context, theme, cs, isZh),
            Divider(height: 1, color: cs.outlineVariant),
            // ── Body ────────────────────────────────────────────────────
            Expanded(child: _buildBody(context, cs, theme, isZh)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme cs,
    bool isZh,
    AdbDevice? device,
    AndroidReverseSessionConfig config,
  ) {
    final running = _ctrl.isRunning;
    final statusColor = !running
        ? cs.outline
        : device == null
        ? cs.error
        : cs.primary;
    final statusLabel = !running
        ? (isZh ? '已停止' : 'stopped')
        : device == null
        ? (isZh ? '无设备' : 'no device')
        : device.model ?? device.serial;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Icon(Icons.android_rounded, size: 22, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isZh ? 'Android 逆向调试面板' : 'Android Reverse Debugger',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  config.objective,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Status chip
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: isZh ? '刷新' : 'Refresh',
            onPressed: _refreshAll,
            iconSize: 20,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: isZh ? '关闭' : 'Close',
            onPressed: () => Navigator.of(context).pop(),
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    bool isZh,
  ) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _Tab.values.map((tab) {
          final selected = _currentTab == tab;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: AnimatedContainer(
              duration: _kSwitchDuration,
              curve: _kSwitchInCurve,
              decoration: BoxDecoration(
                color: selected
                    ? cs.primaryContainer.withValues(alpha: 0.6)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _currentTab = tab);
                  if (tab == _Tab.logcat) _fetchLogcat();
                  if (tab == _Tab.processes) _doRefreshProcesses();
                  if (tab == _Tab.packages) _doRefreshPackages();
                },
                icon: Icon(tab.icon, size: 14),
                label: Text(
                  tab.label(isZh),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    return AnimatedSwitcher(
      duration: _kSwitchDuration,
      switchInCurve: _kSwitchInCurve,
      child: KeyedSubtree(
        key: ValueKey<_Tab>(_currentTab),
        child: _buildTab(context, cs, theme, isZh),
      ),
    );
  }

  Widget _buildTab(
    BuildContext context,
    ColorScheme cs,
    ThemeData theme,
    bool isZh,
  ) {
    return switch (_currentTab) {
      _Tab.devices => _buildDevicesTab(cs, theme, isZh),
      _Tab.overview => _buildOverviewTab(cs, theme, isZh),
      _Tab.packages => _buildPackagesTab(cs, theme, isZh),
      _Tab.processes => _buildProcessesTab(cs, theme, isZh),
      _Tab.logcat => _buildLogcatTab(cs, theme, isZh),
      _Tab.frida => _buildFridaTab(cs, theme, isZh),
      _Tab.network => _buildNetworkTab(cs, theme, isZh),
      _Tab.staticAnalysis => _buildStaticTab(cs, theme, isZh),
      _Tab.certs => _buildCertsTab(cs, theme, isZh),
      _Tab.crypto => _buildCryptoTab(cs, theme, isZh),
    };
  }

  // ── Devices tab ─────────────────────────────────────────────────────────

  Widget _buildDevicesTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final devices = _ctrl.allDevices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Text(
                isZh ? '已检测设备' : 'Detected devices',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _doRefreshDevices,
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: Text(isZh ? '刷新' : 'Refresh'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: devices.isEmpty
              ? Center(
                  child: Text(
                    isZh
                        ? '未找到设备。请连接 Android 设备或启动模拟器后刷新。'
                        : 'No devices found. Connect a device or start an emulator, then refresh.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              : OpenHandSafeScrollbar(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    itemCount: devices.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: cs.outlineVariant),
                    itemBuilder: (_, i) {
                      final d = devices[i];
                      return ListTile(
                        leading: Icon(
                          d.isOnline
                              ? Icons.phone_android_rounded
                              : Icons.phone_disabled_rounded,
                          color: d.isOnline ? cs.primary : cs.error,
                        ),
                        title: Text(
                          d.model ?? d.serial,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${d.serial} · ${d.state}${d.product != null ? " · ${d.product}" : ""}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        trailing: d.isOnline
                            ? Chip(
                                label: Text(
                                  isZh ? '在线' : 'online',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                backgroundColor:
                                    cs.primaryContainer.withValues(alpha: 0.4),
                                visualDensity: VisualDensity.compact,
                                side: BorderSide.none,
                              )
                            : null,
                        dense: true,
                      );
                    },
                  ),
                ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        // ADB shell quick runner
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isZh ? 'ADB Shell 快速执行' : 'ADB Shell quick runner',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _shellCtrl,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: isZh ? 'adb shell 命令' : 'adb shell command',
                        border: const OutlineInputBorder(),
                        prefixText: 'adb shell ',
                        prefixStyle: TextStyle(
                          fontFamily: 'monospace',
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      style: const TextStyle(fontFamily: 'monospace'),
                      onSubmitted: (_) => _runShell(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _runShell,
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: Text(isZh ? '执行' : 'Run'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              if (_shellOutputCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 100),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _shellOutputCtrl.text,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Overview tab ────────────────────────────────────────────────────────

  Widget _buildOverviewTab(ColorScheme cs, ThemeData theme, bool isZh) {
    final config = _ctrl.config;
    final device = _ctrl.connectedDevice;
    final items = <(String, String)>[
      (isZh ? '逆向目标' : 'Objective', config.objective),
      if (config.packageName != null)
        (isZh ? '包名' : 'Package', config.packageName!),
      if (config.apkPath != null)
        (isZh ? 'APK 路径' : 'APK path', config.apkPath!),
      (
        isZh ? 'ADB MCP' : 'ADB MCP',
        config.adbMcpEnabled ? (isZh ? '已启用' : 'enabled') : (isZh ? '未启用' : 'disabled'),
      ),
      (
        isZh ? 'Frida MCP' : 'Frida MCP',
        config.fridaMcpEnabled
            ? (isZh ? '已启用' : 'enabled')
            : (isZh ? '未启用' : 'disabled'),
      ),
      if (device != null) ...[
        (isZh ? '设备型号' : 'Device model', device.model ?? device.serial),
        (isZh ? '设备序列号' : 'Device serial', device.serial),
      ],
      if (config.keywords.isNotEmpty)
        (isZh ? '关键字' : 'Keywords', config.keywords.join(', ')),
      if (config.notes != null && config.notes!.isNotEmpty)
        (isZh ? '备注' : 'Notes', config.notes!),
    ];
    return OpenHandSafeScrollbar(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final (label, value) = items[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _copyText(value),
                    child: Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: value.contains('/') ? 'monospace' : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Packages tab ─────────────────────────────────────────────────────────

  Widget _buildPackagesTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              Text(
                '${isZh ? "第三方 APP" : "Third-party apps"} (${_packages.length})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _loadingPackages ? null : _doRefreshPackages,
                icon: _loadingPackages
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.refresh_rounded, size: 14),
                label: Text(isZh ? '刷新' : 'Refresh'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingPackages && _packages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : OpenHandSafeScrollbar(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _packages.length,
                    itemBuilder: (_, i) {
                      final pkg = _packages[i];
                      return ListTile(
                        leading: Icon(
                          Icons.apps_rounded,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                        title: Text(
                          pkg,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 14),
                              tooltip: isZh ? '复制包名' : 'Copy package name',
                              onPressed: () => _copyText(pkg),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.stop_rounded,
                                size: 14,
                                color: Colors.redAccent,
                              ),
                              tooltip: isZh ? 'Force stop' : 'Force stop',
                              onPressed: () async {
                                await _ctrl.shell('am force-stop $pkg');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        isZh
                                            ? 'Force-stop: $pkg'
                                            : 'Force-stop sent: $pkg',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        dense: true,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ── Processes tab ───────────────────────────────────────────────────────

  Widget _buildProcessesTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _processFilter,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: isZh ? '过滤进程名...' : 'Filter process name...',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  ),
                  onSubmitted: (_) => _doRefreshProcesses(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _loadingProcesses ? null : _doRefreshProcesses,
                icon: _loadingProcesses
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.refresh_rounded, size: 14),
                label: Text(isZh ? '刷新' : 'Refresh'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingProcesses && _processes.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : OpenHandSafeScrollbar(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _processes.length,
                    itemBuilder: (_, i) {
                      final p = _processes[i];
                      return ListTile(
                        leading: Text(
                          '${p.pid}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        title: Text(
                          p.name,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        subtitle: p.user != null
                            ? Text(
                                'user: ${p.user}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              )
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          onPressed: () => _copyText('${p.pid}'),
                          tooltip: isZh ? '复制 PID' : 'Copy PID',
                          visualDensity: VisualDensity.compact,
                        ),
                        dense: true,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ── Logcat tab ──────────────────────────────────────────────────────────

  Widget _buildLogcatTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Text(
                'Logcat (${_logcatLines.length} lines)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (_loadingLogcat)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
              FilledButton.tonalIcon(
                onPressed: _loadingLogcat ? null : _fetchLogcat,
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: Text(isZh ? '刷新' : 'Refresh'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _logcatLines.isEmpty
                    ? null
                    : () => _copyText(_logcatLines.join('\n')),
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: Text(isZh ? '复制' : 'Copy'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _logcatLines.isEmpty
              ? Center(
                  child: TextButton.icon(
                    onPressed: _fetchLogcat,
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: Text(isZh ? '加载 Logcat' : 'Load logcat'),
                  ),
                )
              : OpenHandSafeScrollbar(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: _logcatLines.length,
                    itemBuilder: (_, i) {
                      final line = _logcatLines[i];
                      Color? color;
                      if (line.contains(' E ') || line.contains('/ERROR')) {
                        color = cs.error;
                      } else if (line.contains(' W ') ||
                          line.contains('/WARN')) {
                        color = cs.tertiary;
                      }
                      return Text(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: color ?? cs.onSurface,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ── Frida tab ───────────────────────────────────────────────────────────

  Widget _buildFridaTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isZh ? 'Frida 脚本快速注入' : 'Frida script quick inject',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isZh
                ? '在此处粘贴 Frida JS 脚本，通过 AI 代理注入（实际注入由 AI 调用 Frida MCP 或 Bash 完成）。'
                : 'Paste a Frida JS script here. Injection is handled by the AI agent via Frida MCP or Bash.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _fridaScriptCtrl,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText:
                    isZh ? '// 粘贴 Frida 脚本...' : '// Paste Frida script...',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: _fridaScriptCtrl.text.isEmpty
                    ? null
                    : () => _copyText(_fridaScriptCtrl.text),
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: Text(isZh ? '复制脚本' : 'Copy script'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isZh
                            ? '请告知 AI 执行注入：在对话框输入"注入 Frida 脚本"'
                            : 'Tell the AI to inject: type "inject Frida script" in the chat',
                      ),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                icon: const Icon(Icons.info_outline_rounded, size: 14),
                label: Text(isZh ? '如何注入' : 'How to inject'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: cs.outlineVariant),
          const SizedBox(height: 8),
          Text(
            isZh ? 'Frida 常用命令参考' : 'Frida CLI reference',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          _monospaceCard(
            cs,
            'frida-ps -U\n'
            'frida -U -f <pkg> -l script.js\n'
            'frida -U -p <pid> -l script.js\n'
            'frida-trace -U -i "open" <pkg>',
          ),
        ],
      ),
    );
  }

  // ── Network tab ─────────────────────────────────────────────────────────

  Widget _buildNetworkTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isZh ? '网络抓包 (mitmproxy)' : 'Network capture (mitmproxy)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _InfoCard(
            cs: cs,
            theme: theme,
            icon: Icons.info_outline_rounded,
            text: isZh
                ? '网络流量由 mitmproxy 代理拦截。请先在"证书"面板安装 CA 证书，然后在设备上配置代理为 <本机 IP>:8080，再启动 mitmdump。'
                : 'Traffic is intercepted by mitmproxy. Install the CA cert in the Certs tab, configure the device proxy to <host IP>:8080, then start mitmdump.',
          ),
          const SizedBox(height: 12),
          Text(
            isZh ? 'mitmdump 快速启动' : 'mitmdump quick start',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          _monospaceCard(
            cs,
            'mitmdump -p 8080 -w flows.mitm\n'
            '# 读取保存的流量\n'
            'mitmproxy -r flows.mitm',
          ),
          const SizedBox(height: 12),
          Text(
            isZh ? '本地工件目录' : 'Local artifacts',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '~/.openhand/android_reverse/sessions/${widget.sessionId}/network.jsonl',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ── Static analysis tab ─────────────────────────────────────────────────

  Widget _buildStaticTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isZh ? '静态分析工具参考' : 'Static analysis reference',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isZh ? 'jadx 反编译' : 'jadx decompile',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          _monospaceCard(cs, 'jadx -d out_dir app.apk\n'
              'grep -r "sign\\|encrypt\\|token" out_dir/'),
          const SizedBox(height: 12),
          Text(
            isZh ? 'apktool 解包 + smali' : 'apktool unpack + smali',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          _monospaceCard(
            cs,
            'apktool d app.apk -o out_dir\n'
            'grep -r "invoke-virtual.*sign" out_dir/smali/',
          ),
          const SizedBox(height: 12),
          Text(
            isZh ? 'Flutter/Dart AOT (blutter)' : 'Flutter/Dart AOT (blutter)',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          _monospaceCard(cs, 'blutter libapp.so out_dir/\n'
              '# 查看 Doldrums 或 blutter 输出的 asm.txt'),
          const SizedBox(height: 12),
          Text(
            isZh ? 'radare2 / IDA Pro' : 'radare2 / IDA Pro',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          _monospaceCard(
            cs,
            'r2 lib/arm64-v8a/libxxx.so\n'
            'aaa; afl | grep <keyword>\n'
            '# IDA Pro MCP 可通过 AI 直接调用',
          ),
        ],
      ),
    );
  }

  // ── Certs tab ────────────────────────────────────────────────────────────

  Widget _buildCertsTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isZh ? '证书管理与 SSL Pinning' : 'Certificate management & SSL Pinning',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _InfoCard(
            cs: cs,
            theme: theme,
            icon: Icons.verified_user_rounded,
            text: isZh
                ? 'HTTPS 抓包需要设备信任 mitmproxy / Burp CA 证书。Android 7+ 需要系统级证书（需 root 或 Magisk）或通过 Network Security Config 添加用户证书。'
                : 'HTTPS capture requires the device to trust the mitmproxy/Burp CA. Android 7+ needs system-level certs (root/Magisk) or Network Security Config for user certs.',
          ),
          const SizedBox(height: 12),
          Text(
            isZh ? '推送用户 CA 证书' : 'Push user CA cert',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          _monospaceCard(
            cs,
            '# 生成 mitmproxy CA 证书哈希文件名\n'
            'openssl x509 -inform PEM -subject_hash_old \\\n'
            '  -in ~/.mitmproxy/mitmproxy-ca-cert.pem | head -1\n'
            '# 推送到系统证书目录（需 root）\n'
            'adb push <hash>.0 /system/etc/security/cacerts/\n'
            'adb shell chmod 644 /system/etc/security/cacerts/<hash>.0',
          ),
          const SizedBox(height: 12),
          Text(
            isZh ? 'SSL Pinning 绕过（Frida hook）' : 'SSL Pinning bypass (Frida)',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          _monospaceCard(
            cs,
            '# 使用 snippets/hook_ssl_pinning.js\n'
            'frida -U -f <pkg> -l hook_ssl_pinning.js',
          ),
        ],
      ),
    );
  }

  // ── Crypto pad tab ────────────────────────────────────────────────────────

  Widget _buildCryptoTab(ColorScheme cs, ThemeData theme, bool isZh) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isZh ? '加密工具台' : 'Crypto pad',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isZh ? 'Base64' : 'Base64',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _base64Ctrl,
            decoration: InputDecoration(
              isDense: true,
              hintText: isZh ? '输入文本...' : 'Input text...',
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) {
              setState(() {
                try {
                  _base64OutCtrl.text = _safeBase64Encode(v);
                } catch (_) {
                  _base64OutCtrl.text = '';
                }
              });
            },
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _base64OutCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: isZh ? 'Base64 输出' : 'Base64 output',
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _base64OutCtrl.text.isEmpty
                    ? null
                    : () => _copyText(_base64OutCtrl.text),
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: Text(isZh ? '复制' : 'Copy'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isZh ? '常用编解码命令' : 'Encode/decode reference',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          _monospaceCard(
            cs,
            '# Base64\necho -n "text" | base64\necho "b64==" | base64 -d\n\n'
            '# MD5 / SHA256\necho -n "text" | md5sum\necho -n "text" | sha256sum\n\n'
            '# JWT decode (header.payload)\necho "<jwt_part>" | base64 -d',
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _monospaceCard(ColorScheme cs, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: cs.onSurface,
          height: 1.5,
        ),
      ),
    );
  }

  String _safeBase64Encode(String input) {
    if (input.isEmpty) return '';
    try {
      final decoded = utf8.decode(base64Decode(input));
      return decoded;
    } catch (_) {
      return base64Encode(utf8.encode(input));
    }
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.cs,
    required this.theme,
    required this.icon,
    required this.text,
  });

  final ColorScheme cs;
  final ThemeData theme;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
